// ============================================================================
// YPYW Business Intelligence - Azure SQL infrastructure (Bicep IaC)
// Provisions an Azure SQL logical server and a FREE serverless database that
// auto-pauses to stay at $0, plus a least-privilege firewall rule that allows
// only the specified client IP.
// ============================================================================

// ---------------------------------------------------------------------------
// Parameters
// ---------------------------------------------------------------------------

@description('Azure region for all resources.')
param location string = 'canadacentral'

@description('Administrator login for the Azure SQL logical server.')
param sqlAdminUser string = 'ypywadmin'

@description('Administrator password for the Azure SQL logical server. Pass at deploy time; never commit.')
@secure()
param sqlAdminPassword string

@description('Public client IP address allowed through the SQL server firewall.')
param clientIp string

// ---------------------------------------------------------------------------
// Variables
// ---------------------------------------------------------------------------

var sqlServerName = 'ypyw-sql-ahmedsohail'
var sqlDatabaseName = 'ypyw-bi-db'

// ---------------------------------------------------------------------------
// Azure SQL logical server
// ---------------------------------------------------------------------------

resource sqlServer 'Microsoft.Sql/servers@2023-08-01' = {
  name: sqlServerName
  location: location
  properties: {
    administratorLogin: sqlAdminUser
    administratorLoginPassword: sqlAdminPassword
    version: '12.0'
    minimalTlsVersion: '1.2'
    publicNetworkAccess: 'Enabled'
  }
}

// ---------------------------------------------------------------------------
// Azure SQL Database - FREE serverless General Purpose tier
// GP_S_Gen5_2 serverless with the free-limit configuration so the database
// stays $0: free vCore-seconds + auto-pause on exhaustion.
// ---------------------------------------------------------------------------

resource sqlDatabase 'Microsoft.Sql/servers/databases@2023-08-01' = {
  parent: sqlServer
  name: sqlDatabaseName
  location: location
  sku: {
    name: 'GP_S_Gen5_2'
    tier: 'GeneralPurpose'
    family: 'Gen5'
    capacity: 2
  }
  properties: {
    // Serverless auto-pause: pause after 60 minutes of inactivity.
    autoPauseDelay: 60
    minCapacity: json('0.5')
    // Free-limit configuration: keeps the database at $0 and auto-pauses
    // once the monthly free vCore-seconds allotment is exhausted.
    useFreeLimit: true
    freeLimitExhaustionBehavior: 'AutoPause'
    zoneRedundant: false
  }
}

// ---------------------------------------------------------------------------
// Firewall rule: allow the specified client IP
// ---------------------------------------------------------------------------

resource clientIpFirewallRule 'Microsoft.Sql/servers/firewallRules@2023-08-01' = {
  parent: sqlServer
  name: 'AllowClientIp'
  properties: {
    startIpAddress: clientIp
    endIpAddress: clientIp
  }
}

// ---------------------------------------------------------------------------
// Outputs
// ---------------------------------------------------------------------------

@description('Fully qualified domain name of the Azure SQL logical server.')
output sqlServerFqdn string = sqlServer.properties.fullyQualifiedDomainName

@description('Name of the provisioned Azure SQL database.')
output sqlDatabaseName string = sqlDatabase.name
