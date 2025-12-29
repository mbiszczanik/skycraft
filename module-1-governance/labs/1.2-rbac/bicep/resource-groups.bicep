/*=====================================================
SUMMARY: Lab 1.2 - Resource Groups
DESCRIPTION: Creates resource groups
EXAMPLE:
AUTHOR/S: Marcin Biszczanik
VERSION: 0.1.0
DEPLOYMENT: Deploy-Infra.ps1
======================================================*/

targetScope = 'subscription'

/*******************
*    Parameters    *
*******************/
@description('Location for all resources')
param parLocation string = 'swedencentral'

@description('Tags to apply to all resources')
param parCommonTags object = {}

/*******************
*    Variables     *
*******************/
var varResourceGroupNameDev string = 'dev-skycraft-swc-rg'
var varResourceGroupNameProd string = 'prod-skycraft-swc-rg'
var varResourceGroupNamePlatform string = 'platform-skycraft-swc-rg'

var varTags = {
  Development: union(parCommonTags, {
    Environment: 'Development'
    Project: 'SkyCraft'
    CostCenter: 'MSDN'
  })
  Production: union(parCommonTags, {
    Environment: 'Production'
    Project: 'SkyCraft'
    CostCenter: 'MSDN'
  })
  Platform: union(parCommonTags, {
    Environment: 'Platform'
    Project: 'SkyCraft'
    CostCenter: 'MSDN'
  })
}

/*******************
*    Resources     *
*******************/

module modResourceGroupDev 'br/public:avm/res/resources/resource-group:0.4.3' = {
  scope: subscription()
  params: {
    name: varResourceGroupNameDev
    location: parLocation
    tags: varTags.Development
  }
}

module modResourceGroupProd 'br/public:avm/res/resources/resource-group:0.4.3' = {
  scope: subscription()
  params: {
    name: varResourceGroupNameProd
    location: parLocation
    tags: varTags.Production
  }
}

module modResourceGroupPlatform 'br/public:avm/res/resources/resource-group:0.4.3' = {
  scope: subscription()
  params: {
    name: varResourceGroupNamePlatform
    location: parLocation
    tags: varTags.Platform
  }
}

/******************
*     Outputs     *
******************/
output devResourceGroupName string = modResourceGroupDev.name
output prodResourceGroupName string = modResourceGroupProd.name
output sharedResourceGroupName string = modResourceGroupPlatform.name
