// ---------------------------------------------------------------------------
// sqlmi.bicep — Azure SQL Managed Instance + security (Defender, VA, Audit).
// PREPARE ONLY. Provisioning a SQL MI can take hours; do not deploy until the
// environment is confirmed.
// ---------------------------------------------------------------------------

param location string
param namePrefix string
param subnetId string
param vCores int
param storageSizeInGB int
param administratorLogin string

@secure()
param administratorLoginPassword string

param aadAdminObjectId string = ''
param aadAdminLogin string = ''
param logAnalyticsWorkspaceId string

@description('GP = GeneralPurpose. Gen5 hardware, 4-8 vCore for the demo.')
param skuName string = 'GP_Gen5'

resource mi 'Microsoft.Sql/managedInstances@2023-08-01-preview' = {
  name: '${namePrefix}-mi'
  location: location
  identity: { type: 'SystemAssigned' }
  sku: {
    name: skuName
    tier: 'GeneralPurpose'
  }
  properties: {
    administratorLogin: administratorLogin
    administratorLoginPassword: administratorLoginPassword
    subnetId: subnetId
    vCores: vCores
    storageSizeInGB: storageSizeInGB
    licenseType: 'LicenseIncluded'
    publicDataEndpointEnabled: false
    minimalTlsVersion: '1.2'
    administrators: empty(aadAdminObjectId) ? null : {
      administratorType: 'ActiveDirectory'
      principalType: 'User'
      login: aadAdminLogin
      sid: aadAdminObjectId
      azureADOnlyAuthentication: false
    }
  }
}

// Microsoft Defender for SQL (Advanced Threat Protection).
resource defender 'Microsoft.Sql/managedInstances/advancedThreatProtectionSettings@2023-08-01-preview' = {
  parent: mi
  name: 'Default'
  properties: { state: 'Enabled' }
}

// Vulnerability Assessment (requires a storage container; set later).
resource va 'Microsoft.Sql/managedInstances/sqlVulnerabilityAssessments@2023-08-01-preview' = {
  parent: mi
  name: 'default'
  properties: { state: 'Enabled' }
}

// SQL Audit -> Log Analytics via diagnostic settings on the MI.
resource audit 'Microsoft.Sql/managedInstances/auditingSettings@2023-08-01-preview' = {
  parent: mi
  name: 'default'
  properties: {
    state: 'Enabled'
    isAzureMonitorTargetEnabled: true
  }
}

resource miDiag 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  scope: mi
  name: 'to-law'
  properties: {
    workspaceId: logAnalyticsWorkspaceId
    logs: [
      { categoryGroup: 'audit', enabled: true }
    ]
  }
}

output managedInstanceName string = mi.name
output managedInstanceFqdn string = mi.properties.fullyQualifiedDomainName
