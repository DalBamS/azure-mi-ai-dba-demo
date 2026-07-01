// ---------------------------------------------------------------------------
// network.bicep — VNet, delegated subnet, NSG and route table for SQL MI.
// PREPARE ONLY. Address spaces are parameterized; adjust to your environment.
// ---------------------------------------------------------------------------

param location string
param namePrefix string
param vnetAddressPrefix string = '10.60.0.0/16'
param miSubnetPrefix string = '10.60.0.0/24'

resource nsg 'Microsoft.Network/networkSecurityGroups@2023-11-01' = {
  name: '${namePrefix}-mi-nsg'
  location: location
  properties: {
    // SQL MI manages most required rules via service tags; add org rules here.
    securityRules: []
  }
}

resource routeTable 'Microsoft.Network/routeTables@2023-11-01' = {
  name: '${namePrefix}-mi-rt'
  location: location
  properties: {
    disableBgpRoutePropagation: false
    routes: []
  }
}

resource vnet 'Microsoft.Network/virtualNetworks@2023-11-01' = {
  name: '${namePrefix}-vnet'
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [ vnetAddressPrefix ]
    }
    subnets: [
      {
        name: 'ManagedInstance'
        properties: {
          addressPrefix: miSubnetPrefix
          networkSecurityGroup: { id: nsg.id }
          routeTable: { id: routeTable.id }
          delegations: [
            {
              name: 'miDelegation'
              properties: {
                serviceName: 'Microsoft.Sql/managedInstances'
              }
            }
          ]
        }
      }
    ]
  }
}

output miSubnetId string = '${vnet.id}/subnets/ManagedInstance'
