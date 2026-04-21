/*=====================================================
SUMMARY: Lab 3.1 - Virtual Network Module
DESCRIPTION: Deploys a Virtual Network with configurable subnets (optionally NSG-associated) for SkyCraft Lab 3.1.
AUTHOR/S: Marcin Biszczanik
VERSION: 1.1.0
DEPLOYMENT: [Internal use via Orchestrator]
======================================================*/

/*******************
*    Parameters    *
*******************/
@description('Name prefix for network resources (e.g., dev-skycraft-swc)')
param parNamePrefix string

@description('Azure region for deployment')
param parLocation string = resourceGroup().location

@description('VNet address space')
param parVnetAddressPrefix string

@description('Subnet configurations: [{ name, addressPrefix, nsgId? }]')
param parSubnets array

@description('Resource tags (must include Project, Environment, CostCenter)')
param parTags object

/*******************
*    Resources     *
*******************/
resource resVnet 'Microsoft.Network/virtualNetworks@2023-11-01' = {
  name: '${parNamePrefix}-vnet'
  location: parLocation
  tags: parTags
  properties: {
    addressSpace: {
      addressPrefixes: [parVnetAddressPrefix]
    }
    subnets: [for subnet in parSubnets: {
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

/******************
*     Outputs     *
******************/
output outVnetId string = resVnet.id
output outVnetName string = resVnet.name
output outSubnets array = [for (subnet, i) in parSubnets: {
  name: subnet.name
  id: resVnet.properties.subnets[i].id
}]
