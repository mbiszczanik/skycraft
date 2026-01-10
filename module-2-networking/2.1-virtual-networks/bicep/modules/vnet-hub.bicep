/*=====================================================
SUMMARY: Lab 2.1 - Hub Virtual Network
DESCRIPTION: Deploys the Hub (Platform) VNet with administrative subnets.
AUTHOR/S: Marcin Biszczanik
VERSION: 0.1.0
======================================================*/

/*******************
*    Parameters    *
*******************/
@description('Location for resources')
param parLocation string

@description('Name of the Platform VNet')
param parVnetName string = 'platform-skycraft-swc-vnet'

@description('Environment tag value')
param parEnvironment string = 'Platform'

/*******************
*    Variables     *
*******************/
var varCommonTags = {
  Project: 'SkyCraft'
  Environment: parEnvironment
  CostCenter: 'MSDN'
}

/*******************
*    Resources     *
*******************/

resource resVnetHub 'Microsoft.Network/virtualNetworks@2023-11-01' = {
  name: parVnetName
  location: parLocation
  tags: varCommonTags
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.0.0.0/16'
      ]
    }
    subnets: [
      {
        name: 'AzureBastionSubnet'
        properties: {
          addressPrefix: '10.0.0.0/26'
        }
      }
      {
        name: 'GatewaySubnet'
        properties: {
          addressPrefix: '10.0.1.0/27'
        }
      }
    ]
  }
}

/******************
*     Outputs     *
******************/
output outVnetId string = resVnetHub.id
output outVnetName string = resVnetHub.name
