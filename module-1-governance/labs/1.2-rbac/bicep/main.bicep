/*=====================================================
SUMMARY: Lab 1.2 - Resource Groups and RBAC Assignments
DESCRIPTION: Creates resource groups with proper tagging 
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

@description('Project name prefix')
param parProjectName string = 'skycraft'

@description('Tags to apply to all resources')
param parCommonTags object = {}

@description('Admin email for Owner tag')
param parAdminEmail string = 'admin@skycraft.com'

// @description('Principal ID for SkyCraft Admin user')
// param parAdminPrincipalId string

// @description('Principal ID for SkyCraft-Developers group')
// param parDeveloperGroupPrincipalId string

// @description('Principal ID for SkyCraft-Testers group')
// param parTesterGroupPrincipalId string

// @description('Principal ID for External Partner user')
// param parPartnerPrincipalId string

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
    Owner: parAdminEmail
  })
  Production: union(parCommonTags, {
    Environment: 'Production'
    Project: 'SkyCraft'
    CostCenter: 'MSDN'
    Owner: parAdminEmail
  })
  Platform: union(parCommonTags, {
    Environment: 'Platform'
    Project: 'SkyCraft'
    CostCenter: 'MSDN'
    Owner: parAdminEmail
  })
}

/** Built-in role definition IDs **/
var varOwnerRoleId = '8e3af657-a8ff-443c-a75c-2fe8c4bcb635'
var varContributorRoleId = 'b24988ac-6180-42a0-ab88-20f7382dd24c'
var varReaderRoleId = 'acdd72a7-3385-48ef-bd42-f606fba81ae7'

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

// Subscription-level assignments
// module modAdminOwnerAssigment 'br/public:avm/res/authorization/role-assignment/sub-scope:0.1.1' = {
//   scope: subscription()
//   params: {
//     principalId: parAdminPrincipalId
//     roleDefinitionIdOrName: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', varOwnerRoleId)
//   }
// }

// module modDeveloperContributorAssigment 'br/public:avm/res/authorization/role-assignment/sub-scope:0.1.1' = {
//   scope: subscription()
//   params: {
//     principalId: parDeveloperGroupPrincipalId
//     roleDefinitionIdOrName: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', varContributorRoleId)
//   }
// }

// module modTesterReaderAssigment 'br/public:avm/res/authorization/role-assignment/sub-scope:0.1.1' = {
//   scope: subscription()
//   params: {
//     principalId: parTesterGroupPrincipalId
//     roleDefinitionIdOrName: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', varReaderRoleId)
//   }
// }

// module modPartnerReaderAssigment 'br/public:avm/res/authorization/role-assignment/sub-scope:0.1.1' = {
//   scope: subscription()
//   params: {
//     principalId: parPartnerPrincipalId
//     roleDefinitionIdOrName: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', varReaderRoleId)
//   }
// }

/******************
*     Outputs     *
******************/
output devResourceGroupName string = modResourceGroupDev.name
output prodResourceGroupName string = modResourceGroupProd.name
output sharedResourceGroupName string = modResourceGroupPlatform.name
