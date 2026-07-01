// ===========================================================================
// azure-mi-ai-dba-demo — Azure SQL Managed Instance + security stack
// ---------------------------------------------------------------------------
// STATUS: PREPARE ONLY. Do NOT deploy yet. Parameterized for a later run once
//         the target subscription/environment details are provided.
// Deploy (later): infra\deploy.ps1  (wraps `az deployment sub create`)
// Secrets: the SQL admin password is passed as a secure parameter sourced from
//          Key Vault / pipeline — never hardcode it here or in parameter files.
// ===========================================================================

targetScope = 'subscription'

@description('Azure region for all resources.')
param location string = 'koreacentral'

@description('Base name used to derive resource names.')
param namePrefix string = 'gamedemo'

@description('Resource group to create/use.')
param resourceGroupName string = '${namePrefix}-rg'

@description('SQL MI vCore count (General Purpose 4-8 recommended for the demo).')
@allowed([ 4, 8 ])
param vCores int = 4

@description('SQL MI storage in GB.')
param storageSizeInGB int = 256

@description('SQL MI administrator login.')
param administratorLogin string = 'sqladmin'

@description('SQL MI administrator password (SECURE — source from Key Vault/pipeline).')
@secure()
param administratorLoginPassword string

@description('Entra ID admin objectId for the MI (AAD auth). Optional.')
param aadAdminObjectId string = ''

@description('Entra ID admin login name (UPN/group) for the MI. Optional.')
param aadAdminLogin string = ''

resource rg 'Microsoft.Resources/resourceGroups@2023-07-01' = {
  name: resourceGroupName
  location: location
}

module network 'modules/network.bicep' = {
  scope: rg
  name: 'network'
  params: {
    location: location
    namePrefix: namePrefix
  }
}

module monitoring 'modules/monitoring.bicep' = {
  scope: rg
  name: 'monitoring'
  params: {
    location: location
    namePrefix: namePrefix
  }
}

module sqlmi 'modules/sqlmi.bicep' = {
  scope: rg
  name: 'sqlmi'
  params: {
    location: location
    namePrefix: namePrefix
    subnetId: network.outputs.miSubnetId
    vCores: vCores
    storageSizeInGB: storageSizeInGB
    administratorLogin: administratorLogin
    administratorLoginPassword: administratorLoginPassword
    aadAdminObjectId: aadAdminObjectId
    aadAdminLogin: aadAdminLogin
    logAnalyticsWorkspaceId: monitoring.outputs.workspaceId
  }
}

output managedInstanceName string = sqlmi.outputs.managedInstanceName
output managedInstanceFqdn string = sqlmi.outputs.managedInstanceFqdn
