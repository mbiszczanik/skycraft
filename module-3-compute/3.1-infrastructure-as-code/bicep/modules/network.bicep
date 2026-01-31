// modules/network.bicep
// Reusable network module for SkyCraft infrastructure

@description('Name prefix for network resources')
param namePrefix string

@description('Azure region for deployment')
param location string = resourceGroup().location

@description('Environment name (dev, prod)')
@allowed(['dev', 'prod', 'platform'])
param environment string

@description('VNet address space')
param vnetAddressPrefix string

@description('Subnet configurations')
param subnets array

@description('Resource tags')
param tags object = {
  Project: 'SkyCraft'
  Environment: environment
  ManagedBy: 'Bicep'
}

// Virtual Network
resource vnet 'Microsoft.Network/virtualNetworks@2023-05-01' = {
  name: '${namePrefix}-vnet'
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [vnetAddressPrefix]
    }
    subnets: [for subnet in subnets: {
      name: subnet.name
      properties: {
        addressPrefix: subnet.addressPrefix
        networkSecurityGroup: contains(subnet, 'nsgId') ? {
          id: subnet.nsgId
        } : null
      }
    }]
  }
}

// Outputs
output vnetId string = vnet.id
output vnetName string = vnet.name
output subnets array = [for (subnet, i) in subnets: {
  name: subnet.name
  id: vnet.properties.subnets[i].id
}]
