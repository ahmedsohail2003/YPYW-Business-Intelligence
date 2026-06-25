# Azure Deployment Runbook

This runbook provisions the cloud backend for the YPYW Business Intelligence
platform: an **Azure SQL Database** on the **free serverless tier**, fronted by a
logical SQL server, all inside a single resource group.

| Setting          | Value                                          |
|------------------|------------------------------------------------|
| Resource group   | `rg-ypyw-bi`                                    |
| Region           | `canadacentral`                                |
| Logical server   | `ypyw-sql-ahmedsohail`                          |
| Server FQDN      | `ypyw-sql-ahmedsohail.database.windows.net`    |
| Database         | `ypyw-bi-db`                                    |
| Admin user       | `ypywadmin`                                     |

---

## Prerequisites

1. **Azure CLI** installed and logged in:
   ```powershell
   az login
   az account show          # confirm the correct subscription is active
   ```
2. **sqlcmd** on your PATH (SQL Server command-line tools / `go-sqlcmd`).
   ```powershell
   sqlcmd -?                # should print usage, not "command not found"
   ```
3. **The infrastructure files** present in this `azure/` folder:
   - `main.bicep`  — defines the server, the serverless database, and the firewall rule.
   - `schema.sql`  — the relational schema (tables, keys, seed data).
   - `deploy.ps1`  — the deployment script described below.
4. **The SQL admin password** available as an environment variable.
   The password is **never** stored in any file; you supply it per session.

---

## Deployment — exact commands, in order

Run these from the `azure/` directory in **PowerShell**:

```powershell
# 1. Provide the SQL admin password for this shell session only.
#    (Use a strong password: 8+ chars, upper, lower, digit, symbol.)
$env:SQL_ADMIN_PASSWORD = '<your-strong-password>'

# 2. Make sure you are pointed at the right Azure subscription.
az login                     # skip if already logged in
az account set --subscription "<your-subscription-id-or-name>"

# 3. Run the deployment runbook.
./deploy.ps1
```

`deploy.ps1` performs the following, stopping immediately on any error:

1. Verifies `$env:SQL_ADMIN_PASSWORD` is set (exits with guidance if not).
2. Creates resource group `rg-ypyw-bi` in `canadacentral` (idempotent).
3. Auto-detects your public IP (`https://api.ipify.org`) and uses it to open the
   SQL firewall for your machine only.
4. Deploys `main.bicep` with `az deployment group create`, passing the admin
   password as a **secure parameter** and your client IP as `clientIp`.
5. Applies `schema.sql` against `ypyw-bi-db` with `sqlcmd`.

### Verify the deployment

```powershell
# Confirm the resources exist.
az sql db show `
  --resource-group rg-ypyw-bi `
  --server ypyw-sql-ahmedsohail `
  --name ypyw-bi-db `
  --output table

# Confirm the schema landed (lists user tables).
sqlcmd -S ypyw-sql-ahmedsohail.database.windows.net `
       -d ypyw-bi-db -U ypywadmin -P $env:SQL_ADMIN_PASSWORD `
       -Q "SELECT name FROM sys.tables ORDER BY name;"
```

### Re-running

The script is safe to re-run. Resource-group creation and the Bicep deployment
are idempotent. If you re-run after a public-IP change, the new IP is added to
the firewall automatically.

---

## How this stays at $0 — the free serverless tier

Azure SQL Database offers a **free serverless** General Purpose tier (1 free
database per subscription). `main.bicep` provisions the database under this tier,
which keeps the running cost at **$0/month** as long as usage stays within the
free allowance:

- **Serverless compute, auto-paused.** Billing is per vCPU-second only while the
  database is *active*. After a short idle window the database **auto-pauses** and
  bills **zero compute**. A BI dashboard that is queried occasionally spends most
  of its life paused.
- **Monthly free allowance.** The free offer grants a fixed monthly amount of
  vCPU-seconds of compute plus a capped amount of data storage at no charge.
  Light development and demo workloads sit comfortably under these limits.
- **Capped, not surprise-billed.** The free configuration is bounded so the
  database does not silently spill into paid usage; once the monthly allowance is
  exhausted the database is paused for the rest of the cycle rather than charging
  you (it resumes automatically next cycle).
- **No always-on infrastructure.** There is no provisioned VM, no reserved
  compute, and no gateway charge — the logical server itself is free, and you only
  ever pay if active compute or storage exceeds the free allowance.

**Net effect:** for a single low-traffic BI database that auto-pauses when idle,
the monthly bill is **$0** under normal development use.

> First request after an auto-pause incurs a brief cold-start (a few seconds) while
> the database resumes. This is expected and is the trade-off that keeps idle cost
> at zero.

---

## Teardown

To remove everything and guarantee no further charges:

```powershell
az group delete --name rg-ypyw-bi --yes --no-wait
```

This deletes the resource group and every resource inside it (server, database,
firewall rules).
