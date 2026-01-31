/*=====================================================
SUMMARY: Lab 2.1 - Spoke Virtual Network
DESCRIPTION: Deploys a Spoke Virtual Network (Dev or Prod) with game server subnets.
AUTHOR/S: Marcin Biszczanik
VERSION: 0.2.0
======================================================*/

/*******************
*    Parameters    *
*******************/
@description('Location for resources')
param parLocation string

@description('Name of the Spoke VNet')
param parVnetName string

@description('Environment tag value')
param parEnvironment string

@description('Address Space for the VNet')
param parAddressPrefix string

@description('Address Prefix for AuthSubnet')
param parAuthSubnetPrefix string

@description('Address Prefix for WorldSubnet')
param parWorldSubnetPrefix string

@description('Address Prefix for DatabaseSubnet')
param parDatabaseSubnetPrefix string

@description('Address Prefix for AppServiceSubnet')
param parAppServiceSubnetPrefix string

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
        parAddressPrefix
      ]
    }
    subnets: [
      {
        name: 'AuthSubnet'
        properties: {
          addressPrefix: parAuthSubnetPrefix
        }
      }
      {
        name: 'WorldSubnet'
        properties: {
          addressPrefix: parWorldSubnetPrefix
        }
      }
      {
        name: 'DatabaseSubnet'
        properties: {
          addressPrefix: parDatabaseSubnetPrefix
        }
      }
      {
        name: 'AppServiceSubnet'
        properties: {
          addressPrefix: parAppServiceSubnetPrefix
          delegations: [
            {
              name: 'delegation'
              properties: {
                serviceName: 'Microsoft.Web/serverFarms'
              }
            }
          ]
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
