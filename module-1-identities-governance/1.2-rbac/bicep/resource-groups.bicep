/*=====================================================
SUMMARY: Lab 1.2 - Resource Groups
DESCRIPTION: Deploys the prerequisite Resource Groups for SkyCraft
EXAMPLE: az deployment sub create --location swedencentral --template-file resource-groups.bicep
AUTHOR/S: Marcin Biszczanik
VERSION: 0.2.0
DEPLOYMENT: .\scripts\Deploy-Bicep.ps1
======================================================*/

targetScope = 'subscription'

/*******************
*    Parameters    *
*******************/
@description('Location for all resources')
param parLocation string = 'swedencentral'

@description('Common tags object')
param parCommonTags object = {}

/*******************
*    Variables     *
*******************/
var varResourceGroupNameDev = 'dev-skycraft-swc-rg'
var varResourceGroupNameProd = 'prod-skycraft-swc-rg'
var varResourceGroupNamePlatform = 'platform-skycraft-swc-rg'

var varTagsDev = union(parCommonTags, {
  Environment: 'Development'
  Project: 'SkyCraft'
  CostCenter: 'MSDN'
})

var varTagsProd = union(parCommonTags, {
  Environment: 'Production'
  Project: 'SkyCraft'
  CostCenter: 'MSDN'
})

var varTagsPlatform = union(parCommonTags, {
  Environment: 'Platform'
  Project: 'SkyCraft'
  CostCenter: 'MSDN'
})

/*******************
*    Resources     *
*******************/

resource resRgDev 'Microsoft.Resources/resourceGroups@2023-07-01' = {
  name: varResourceGroupNameDev
  location: parLocation
  tags: varTagsDev
}

resource resRgProd 'Microsoft.Resources/resourceGroups@2023-07-01' = {
  name: varResourceGroupNameProd
  location: parLocation
  tags: varTagsProd
}

resource resRgPlatform 'Microsoft.Resources/resourceGroups@2023-07-01' = {
  name: varResourceGroupNamePlatform
  location: parLocation
  tags: varTagsPlatform
}

/******************
*     Outputs     *
******************/
output outDevResourceGroupName string = resRgDev.name
output outProdResourceGroupName string = resRgProd.name
output outPlatformResourceGroupName string = resRgPlatform.name
