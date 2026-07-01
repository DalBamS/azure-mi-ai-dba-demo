// ---------------------------------------------------------------------------
// monitoring.bicep — Log Analytics workspace (SQL Audit / Defender sink).
// PREPARE ONLY.
// ---------------------------------------------------------------------------

param location string
param namePrefix string
param retentionInDays int = 30

resource workspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: '${namePrefix}-law'
  location: location
  properties: {
    sku: { name: 'PerGB2018' }
    retentionInDays: retentionInDays
    features: { enableLogAccessUsingOnlyResourcePermissions: true }
  }
}

output workspaceId string = workspace.id
output workspaceName string = workspace.name
