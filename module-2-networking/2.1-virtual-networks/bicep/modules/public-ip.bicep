/*=====================================================
SUMMARY: Public IP Address Module
DESCRIPTION: Deploys a Standard SKU Public IP Address.
AUTHOR/S: Marcin Biszczanik
VERSION: 0.1.0
======================================================*/

/*******************
*    Parameters    *
*******************/
@description('Location for resources')
param parLocation string

@description('Name of the Public IP')
param parPublicIpName string

@description('Environment tag value')
param parEnvironment string

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

resource resPublicIp 'Microsoft.Network/publicIPAddresses@2023-11-01' = {
  name: parPublicIpName
  location: parLocation
  tags: varCommonTags
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}

/******************
*     Outputs     *
******************/
output outPublicIpId string = resPublicIp.id
output outPublicIpName string = resPublicIp.name
