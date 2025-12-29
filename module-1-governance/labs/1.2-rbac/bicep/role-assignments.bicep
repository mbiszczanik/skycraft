/*=====================================================
SUMMARY: Lab 1.2 - RBAC Assignments
DESCRIPTION: Assigns RBAC roles to resource groups
EXAMPLE:
AUTHOR/S: Marcin Biszczanik
VERSION: 0.1.0
DEPLOYMENT: Deploy-Infra.ps1
======================================================*/

targetScope = 'subscription'

/*******************
*    Parameters    *
*******************/
@description('Principal ID for SkyCraft Admin user')
param parAdminPrincipalId string

@description('Principal ID for SkyCraft-Developers group')
param parDeveloperGroupPrincipalId string

@description('Principal ID for SkyCraft-Testers group')
param parTesterGroupPrincipalId string

@description('Principal ID for External Partner user')
param parPartnerPrincipalId string

@description('Name of the Development Resource Group')
param parResourceGroupNameDev string = 'dev-skycraft-swc-rg'

@description('Name of the Production Resource Group')
param parResourceGroupNameProd string = 'prod-skycraft-swc-rg'

@description('Name of the Platform Resource Group')
param parResourceGroupNamePlatform string = 'platform-skycraft-swc-rg'

/*******************
*    Variables     *
*******************/

/** Built-in role definition IDs **/
var varOwnerRoleId = '8e3af657-a8ff-443c-a75c-2fe8c4bcb635'
var varContributorRoleId = 'b24988ac-6180-42a0-ab88-20f7382dd24c'
var varReaderRoleId = 'acdd72a7-3385-48ef-bd42-f606fba81ae7'

/*******************
*    Resources     *
*******************/

/* Subscription-level assignments */
module modAdminOwnerAssigment 'br/public:avm/res/authorization/role-assignment/sub-scope:0.1.1' = {
  scope: subscription()
  params: {
    principalId: parAdminPrincipalId
    roleDefinitionIdOrName: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', varOwnerRoleId)
  }
}

module modDeveloperContributorAssigment 'modules/rg-role-assignment.bicep' = {
  name: 'developer-contributor-${parResourceGroupNameDev}'
  scope: resourceGroup(parResourceGroupNameDev)
  params: {
    principalId: parDeveloperGroupPrincipalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', varContributorRoleId)
    principalType: 'Group'
  }
}

module modTesterReaderAssigment 'modules/rg-role-assignment.bicep' = {
  name: 'tester-reader-${parResourceGroupNameDev}'
  scope: resourceGroup(parResourceGroupNameDev)
  params: {
    principalId: parTesterGroupPrincipalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', varReaderRoleId)
    principalType: 'Group'
  }
}

module modTesterProdReaderAssigment 'modules/rg-role-assignment.bicep' = {
  name: 'tester-reader-${parResourceGroupNameProd}'
  scope: resourceGroup(parResourceGroupNameProd)
  params: {
    principalId: parTesterGroupPrincipalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', varReaderRoleId)
    principalType: 'Group'
  }
}

module modPartnerReaderAssigment 'modules/rg-role-assignment.bicep' = {
  name: 'partner-reader-${parResourceGroupNamePlatform}'
  scope: resourceGroup(parResourceGroupNamePlatform)
  params: {
    principalId: parPartnerPrincipalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', varReaderRoleId)
    principalType: 'User'
  }
}

/******************
*     Outputs     *
******************/
