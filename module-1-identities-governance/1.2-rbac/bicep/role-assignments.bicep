/*=====================================================
SUMMARY: Lab 1.2 - RBAC Assignments Orchestrator
DESCRIPTION: Orchestrates role assignments for SkyCraft users and groups
EXAMPLE: az deployment sub create --location swedencentral --template-file role-assignments.bicep
AUTHOR/S: Marcin Biszczanik
VERSION: 0.2.0
DEPLOYMENT: .\scripts\New-LabRoleAssignment.ps1
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

/* Subscription-level assignment */
module modAdminOwnerAssigment 'br/public:avm/res/authorization/role-assignment/sub-scope:0.1.1' = {
  name: 'admin-owner-sub'
  scope: subscription()
  params: {
    principalId: parAdminPrincipalId
    roleDefinitionIdOrName: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', varOwnerRoleId)
  }
}

/* Resource Group level assignments */
module modDeveloperContributorAssigment 'modules/rg-role-assignment.bicep' = {
  name: 'developer-contributor-${parResourceGroupNameDev}'
  scope: resourceGroup(parResourceGroupNameDev)
  params: {
    parPrincipalId: parDeveloperGroupPrincipalId
    parRoleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', varContributorRoleId)
    parPrincipalType: 'Group'
  }
}

module modTesterReaderAssigment 'modules/rg-role-assignment.bicep' = {
  name: 'tester-reader-${parResourceGroupNameDev}'
  scope: resourceGroup(parResourceGroupNameDev)
  params: {
    parPrincipalId: parTesterGroupPrincipalId
    parRoleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', varReaderRoleId)
    parPrincipalType: 'Group'
  }
}

module modTesterProdReaderAssigment 'modules/rg-role-assignment.bicep' = {
  name: 'tester-reader-${parResourceGroupNameProd}'
  scope: resourceGroup(parResourceGroupNameProd)
  params: {
    parPrincipalId: parTesterGroupPrincipalId
    parRoleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', varReaderRoleId)
    parPrincipalType: 'Group'
  }
}

module modPartnerReaderAssigment 'modules/rg-role-assignment.bicep' = {
  name: 'partner-reader-${parResourceGroupNamePlatform}'
  scope: resourceGroup(parResourceGroupNamePlatform)
  params: {
    parPrincipalId: parPartnerPrincipalId
    parRoleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', varReaderRoleId)
    parPrincipalType: 'User'
  }
}
