<#
.SYNOPSIS
    One-shot deployment runbook for the YPYW Business Intelligence Azure SQL backend.

.DESCRIPTION
    Provisions the Azure SQL infrastructure (resource group, logical server, and
    free serverless database) via Bicep, then applies the relational schema.

    Steps performed, in order:
      1. Verify the SQL admin password is supplied via the SQL_ADMIN_PASSWORD env var.
      2. Create the resource group (idempotent).
      3. Auto-detect the caller's public IP so the SQL firewall lets this machine in.
      4. Deploy main.bicep (server + serverless DB + firewall rule).
      5. Apply schema.sql against the new database with sqlcmd.

    The SQL admin password is NEVER hard-coded: it is read only from the
    SQL_ADMIN_PASSWORD environment variable and passed to Azure as a secure
    parameter, and to sqlcmd at runtime.

.PREREQUISITES
    - Azure CLI (az) logged in:        az login
    - sqlcmd (part of the SQL Server command-line tools / go-sqlcmd)
    - $env:SQL_ADMIN_PASSWORD set in the current shell session.

.EXAMPLE
    $env:SQL_ADMIN_PASSWORD = '<your-strong-password>'
    ./deploy.ps1
#>

# Stop the whole script on the first uncaught error so we never deploy half a stack.
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Shared configuration  (these names are fixed for the project — do not change)
# ---------------------------------------------------------------------------
$ResourceGroup = 'rg-ypyw-bi'
$Location      = 'canadacentral'
$SqlServer     = 'ypyw-sql-ahmedsohail'
$SqlDatabase   = 'ypyw-bi-db'
$SqlAdminUser  = 'ypywadmin'
$SqlServerFqdn = 'ypyw-sql-ahmedsohail.database.windows.net'

# Resolve the Bicep template and schema file relative to this script so the
# runbook works no matter what directory it is invoked from.
$ScriptDir  = Split-Path -Parent $MyInvocation.MyCommand.Path
$BicepFile  = Join-Path $ScriptDir 'main.bicep'
$SchemaFile = Join-Path $ScriptDir 'schema.sql'

# ---------------------------------------------------------------------------
# Step 1 — Verify the SQL admin password is present in the environment.
#          We never accept it as a plaintext parameter or hard-code it.
# ---------------------------------------------------------------------------
if ([string]::IsNullOrWhiteSpace($env:SQL_ADMIN_PASSWORD)) {
    Write-Error @'
SQL_ADMIN_PASSWORD environment variable is not set.

Set it in this shell before running the deployment, e.g.:

    $env:SQL_ADMIN_PASSWORD = '<your-strong-password>'

The password is required to create the SQL server admin login and to apply
the schema. It is never written to disk or committed to source control.
'@
    exit 1
}
$SqlAdminPassword = $env:SQL_ADMIN_PASSWORD

# Sanity-check the input files exist before doing any cloud work.
if (-not (Test-Path $BicepFile))  { Write-Error "Bicep template not found: $BicepFile";  exit 1 }
if (-not (Test-Path $SchemaFile)) { Write-Error "Schema file not found: $SchemaFile";    exit 1 }

# ---------------------------------------------------------------------------
# Step 2 — Create the resource group (safe to re-run; az is idempotent here).
# ---------------------------------------------------------------------------
Write-Host "==> Creating resource group '$ResourceGroup' in '$Location'..." -ForegroundColor Cyan
az group create `
    --name     $ResourceGroup `
    --location $Location `
    --output   table

# ---------------------------------------------------------------------------
# Step 3 — Auto-detect this machine's public IP.
#          The Azure SQL server is locked down by default; we open the
#          firewall just for this client so the schema step can connect.
# ---------------------------------------------------------------------------
Write-Host "==> Detecting public IP address..." -ForegroundColor Cyan
$ClientIp = (Invoke-RestMethod -Uri 'https://api.ipify.org').Trim()
if ([string]::IsNullOrWhiteSpace($ClientIp)) {
    Write-Error "Could not auto-detect public IP address. Check your internet connection."
    exit 1
}
Write-Host "    Detected client IP: $ClientIp"

# ---------------------------------------------------------------------------
# Step 4 — Deploy the Bicep template.
#          sqlAdminPassword is passed as a secure parameter (Azure marks it
#          secret and never echoes it back in deployment output).
# ---------------------------------------------------------------------------
Write-Host "==> Deploying main.bicep to resource group '$ResourceGroup'..." -ForegroundColor Cyan
az deployment group create `
    --resource-group $ResourceGroup `
    --template-file  $BicepFile `
    --parameters     "sqlAdminPassword=$SqlAdminPassword" `
    --parameters     clientIp=$ClientIp `
    --output         table

# ---------------------------------------------------------------------------
# Step 5 — Apply the relational schema to the new database.
#          -N forces an encrypted connection (Azure SQL requires encryption;
#          classic sqlcmd on ODBC 17 defaults to unencrypted and would fail);
#          -I enables QUOTED_IDENTIFIER, which sqlcmd leaves OFF by default but
#             Azure SQL requires ON to CREATE/ALTER the view (not about brackets);
#          -b makes sqlcmd return a non-zero exit code on SQL errors so the
#          script fails loudly instead of silently.
# ---------------------------------------------------------------------------
Write-Host "==> Applying schema.sql to database '$SqlDatabase'..." -ForegroundColor Cyan
sqlcmd `
    -S $SqlServerFqdn `
    -d $SqlDatabase `
    -U $SqlAdminUser `
    -P "$SqlAdminPassword" `
    -i $SchemaFile `
    -N `
    -I `
    -b

if ($LASTEXITCODE -ne 0) {
    Write-Error "Schema deployment failed (sqlcmd exit code $LASTEXITCODE)."
    exit $LASTEXITCODE
}

# ---------------------------------------------------------------------------
# Done.
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "==> Deployment complete." -ForegroundColor Green
Write-Host "    Server:   $SqlServerFqdn"
Write-Host "    Database: $SqlDatabase"
Write-Host "    Region:   $Location"
