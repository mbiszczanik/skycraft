/*=====================================================
SUMMARY: Lab 2.1 - Spoke Virtual Network
DESCRIPTION: Deploys the Spoke (Production) VNet with game server subnets.
AUTHOR/S: Marcin Biszczanik
VERSION: 0.1.0
======================================================*/

/*******************
*    Parameters    *
*******************/
@description('Location for resources')
param parLocation string

@description('Name of the Production VNet')
param parVnetName string = 'prod-skycraft-swc-vnet'

@description('Environment tag value')
param parEnvironment string = 'Production'

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

resource resVnetSpoke 'Microsoft.Network/virtualNetworks@2023-11-01' = {
  name: parVnetName
  location: parLocation
  tags: varCommonTags
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.1.0.0/16'
      ]
    }
    subnets: [
      {
        name: 'AuthSubnet'
        properties: {
          addressPrefix: '10.1.1.0/24'
        }
      }
      {
        name: 'WorldSubnet'
        properties: {
          addressPrefix: '10.1.2.0/24'
        }
      }
      {
        name: 'DatabaseSubnet'
        properties: {
          addressPrefix: '10.1.3.0/24'
        }
      }
    ]
  }
}

/******************
*     Outputs     *
******************/
output outVnetId string = resVnetSpoke.id
output outVnetName string = resVnetSpoke.name
