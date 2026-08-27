/*=====================================================
SUMMARY: Lab 1.2 - RBAC Assignments Orchestrator
DESCRIPTION: Orchestrates role assignments for SkyCraft users and groups via AVM
EXAMPLE: az deployment sub create --location swedencentral --template-file role-assignments.bicep
AUTHOR/S: Marcin Biszczanik
VERSION: 0.3.0
DEPLOYMENT: .\scripts\New-LabRoleAssignment.ps1
======================================================*/

targetScope = 'subscription'

/*******************
*    Parameters    *
*******************/

@description('Principal ID for SkyCraft Admin user')
@minLength(36)
@maxLength(36)
param parAdminPrincipalId string

@description('Principal ID for SkyCraft-Developers group')
@minLength(36)
@maxLength(36)
param parDeveloperGroupPrincipalId string

@description('Principal ID for SkyCraft-Testers group')
@minLength(36)
@maxLength(36)
param parTesterGroupPrincipalId string

@description('Principal ID for External Partner user')
@minLength(36)
@maxLength(36)
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
*     Modules      *
*******************/

/* Subscription-level assignment */
module modAdminOwnerAssignment 'br/public:avm/res/authorization/role-assignment/sub-scope:0.1.1' = {
  name: 'admin-owner-sub'
  scope: subscription()
  params: {
    principalId: parAdminPrincipalId
    roleDefinitionIdOrName: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', varOwnerRoleId)
  }
}

/* Resource Group level assignments */
module modDeveloperContributorAssignment 'br/public:avm/res/authorization/role-assignment/rg-scope:0.1.1' = {
  name: 'developer-contributor-${parResourceGroupNameDev}'
  scope: resourceGroup(parResourceGroupNameDev)
  params: {
    principalId: parDeveloperGroupPrincipalId
    roleDefinitionIdOrName: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', varContributorRoleId)
    principalType: 'Group'
  }
}

module modTesterReaderAssignment 'br/public:avm/res/authorization/role-assignment/rg-scope:0.1.1' = {
  name: 'tester-reader-${parResourceGroupNameDev}'
  scope: resourceGroup(parResourceGroupNameDev)
  params: {
    principalId: parTesterGroupPrincipalId
    roleDefinitionIdOrName: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', varReaderRoleId)
    principalType: 'Group'
  }
}

module modTesterProdReaderAssignment 'br/public:avm/res/authorization/role-assignment/rg-scope:0.1.1' = {
  name: 'tester-reader-${parResourceGroupNameProd}'
  scope: resourceGroup(parResourceGroupNameProd)
  params: {
    principalId: parTesterGroupPrincipalId
    roleDefinitionIdOrName: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', varReaderRoleId)
    principalType: 'Group'
  }
}

module modPartnerReaderAssignment 'br/public:avm/res/authorization/role-assignment/rg-scope:0.1.1' = {
  name: 'partner-reader-${parResourceGroupNamePlatform}'
  scope: resourceGroup(parResourceGroupNamePlatform)
  params: {
    principalId: parPartnerPrincipalId
    roleDefinitionIdOrName: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', varReaderRoleId)
    principalType: 'User'
  }
}
