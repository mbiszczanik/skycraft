/*=====================================================
SUMMARY: Lab 1.2 - Resource Groups
DESCRIPTION: Deploys the prerequisite Resource Groups for SkyCraft via AVM
EXAMPLE: az deployment sub create --location swedencentral --template-file resource-groups.bicep
AUTHOR/S: Marcin Biszczanik
VERSION: 0.3.0
DEPLOYMENT: .\scripts\Deploy-Bicep.ps1
======================================================*/

targetScope = 'subscription'

/*******************
*    Parameters    *
*******************/

@description('Location for all resources')
@allowed([
  'swedencentral'
  'northeurope'
])
param parLocation string = 'swedencentral'

@description('Resource owner tag value')
@minLength(1)
param parOwner string = 'mbiszczanik'

/*******************
*    Variables     *
*******************/

var varResourceGroupNameDev = 'dev-skycraft-swc-rg'
var varResourceGroupNameProd = 'prod-skycraft-swc-rg'
var varResourceGroupNamePlatform = 'platform-skycraft-swc-rg'

var varTagsDev = {
  Project: 'SkyCraft'
  Environment: 'Development'
  CostCenter: 'MSDN'
  Owner: parOwner
}

var varTagsProd = {
  Project: 'SkyCraft'
  Environment: 'Production'
  CostCenter: 'MSDN'
  Owner: parOwner
}

var varTagsPlatform = {
  Project: 'SkyCraft'
  Environment: 'Platform'
  CostCenter: 'MSDN'
  Owner: parOwner
}

/*******************
*     Modules      *
*******************/

module modRgDev 'br/public:avm/res/resources/resource-group:0.4.4' = {
  name: 'rg-dev-deployment'
  params: {
    name: varResourceGroupNameDev
    location: parLocation
    tags: varTagsDev
  }
}

module modRgProd 'br/public:avm/res/resources/resource-group:0.4.4' = {
  name: 'rg-prod-deployment'
  params: {
    name: varResourceGroupNameProd
    location: parLocation
    tags: varTagsProd
  }
}

module modRgPlatform 'br/public:avm/res/resources/resource-group:0.4.4' = {
  name: 'rg-platform-deployment'
  params: {
    name: varResourceGroupNamePlatform
    location: parLocation
    tags: varTagsPlatform
  }
}

/******************
*     Outputs     *
******************/

output outDevResourceGroupName string = modRgDev.outputs.name
output outProdResourceGroupName string = modRgProd.outputs.name
output outPlatformResourceGroupName string = modRgPlatform.outputs.name
