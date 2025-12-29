/*=====================================================
SUMMARY: Lab 1.3 - Resource Group Tags
DESCRIPTION: This template applies standardized tags to resource groups
EXAMPLE:
AUTHOR/S: Marcin Biszczanik
VERSION: 0.1.0
======================================================*/

targetScope = 'subscription'

@description('Admin email for Owner tag')
param parAdminEmail string = 'admin@skycraft.com'

@description('Dev RG Name')
param parResourceGroupNameDev string = 'dev-skycraft-swc-rg'

@description('Prod RG Name')
param parResourceGroupNameProd string = 'prod-skycraft-swc-rg'

@description('Platform RG Name')
param parResourceGroupNamePlatform string = 'platform-skycraft-swc-rg'

// Development resource group tags
var devTags = {
  Environment: 'Development'
  Project: 'SkyCraft'
  CostCenter: 'MSDN'
  Owner: parAdminEmail
}

// Production resource group tags
var prodTags = {
  Environment: 'Production'
  Project: 'SkyCraft'
  CostCenter: 'MSDN'
  Owner: parAdminEmail
  Criticality: 'High'
}

// Shared resource group tags
var platformTags = {
  Environment: 'Platform'
  Project: 'SkyCraft'
  CostCenter: 'MSDN'
  Owner: parAdminEmail
}

module modTagsDev 'modules/rg-tags.bicep' = {
  name: 'tags-dev'
  scope: resourceGroup(parResourceGroupNameDev)
  params: {
    parTags: devTags
  }
}

module modTagsProd 'modules/rg-tags.bicep' = {
  name: 'tags-prod'
  scope: resourceGroup(parResourceGroupNameProd)
  params: {
    parTags: prodTags
  }
}

module modTagsPlatform 'modules/rg-tags.bicep' = {
  name: 'tags-platform'
  scope: resourceGroup(parResourceGroupNamePlatform)
  params: {
    parTags: platformTags
  }
}
