/*=====================================================
SUMMARY: Lab 1.2 - RBAC Assignments Orchestrator
DESCRIPTION: Orchestrates role assignments for SkyCraft users and groups via AVM
EXAMPLE: .\scripts\Deploy-Bicep.ps1 -IncludeRoleAssignments
AUTHOR/S: Marcin Biszczanik
VERSION: 0.5.0
DEPLOYMENT: .\scripts\Deploy-Bicep.ps1 -IncludeRoleAssignments (resolves the four principal IDs from Entra ID and passes them as overrides; the template has no .bicepparam because object IDs are tenant-specific. It also lists the assignments that already exist in parExistingAssignments, so the template creates only the missing ones). Imperative alternative: .\scripts\New-LabRoleAssignment.ps1 through the ARM role assignments API.
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
@minLength(1)
@maxLength(42) // deployment names prefix this with up to 22 chars; ARM limit is 64
param parResourceGroupNameDev string = 'dev-skycraft-swc-rg'

@description('Name of the Production Resource Group')
@minLength(1)
@maxLength(42) // deployment names prefix this with up to 22 chars; ARM limit is 64
param parResourceGroupNameProd string = 'prod-skycraft-swc-rg'

@description('Name of the Platform Resource Group')
@minLength(1)
@maxLength(42) // deployment names prefix this with up to 22 chars; ARM limit is 64
param parResourceGroupNamePlatform string = 'platform-skycraft-swc-rg'

// Parity with a lab built another way (issue #406). The Portal and New-LabRoleAssignment.ps1 name an
// assignment with a random GUID, the AVM modules with their own guid(), and ARM refuses a second
// assignment of one principal, role and scope (RoleAssignmentExists). Deploy-Bicep.ps1 lists the
// ones that exist; left empty, the template creates all five.
@description('Keys of the assignments that already exist, whatever their name (made in the Portal or by New-LabRoleAssignment.ps1); the template does not deploy them')
@allowed([
  'admin-owner'
  'developer-contributor-dev'
  'tester-reader-dev'
  'tester-reader-prod'
  'partner-reader-platform'
])
param parExistingAssignments array = []

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
module modAdminOwnerAssignment 'br/public:avm/res/authorization/role-assignment/sub-scope:0.1.1' = if (!contains(parExistingAssignments, 'admin-owner')) {
  name: 'admin-owner-sub'
  scope: subscription()
  params: {
    principalId: parAdminPrincipalId
    roleDefinitionIdOrName: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', varOwnerRoleId)
    principalType: 'User'
  }
}

/* Resource Group level assignments */
module modDeveloperContributorAssignment 'br/public:avm/res/authorization/role-assignment/rg-scope:0.1.1' = if (!contains(parExistingAssignments, 'developer-contributor-dev')) {
  name: 'developer-contributor-${parResourceGroupNameDev}'
  scope: resourceGroup(parResourceGroupNameDev)
  params: {
    principalId: parDeveloperGroupPrincipalId
    roleDefinitionIdOrName: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', varContributorRoleId)
    principalType: 'Group'
  }
}

module modTesterReaderAssignment 'br/public:avm/res/authorization/role-assignment/rg-scope:0.1.1' = if (!contains(parExistingAssignments, 'tester-reader-dev')) {
  name: 'tester-reader-${parResourceGroupNameDev}'
  scope: resourceGroup(parResourceGroupNameDev)
  params: {
    principalId: parTesterGroupPrincipalId
    roleDefinitionIdOrName: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', varReaderRoleId)
    principalType: 'Group'
  }
}

module modTesterProdReaderAssignment 'br/public:avm/res/authorization/role-assignment/rg-scope:0.1.1' = if (!contains(parExistingAssignments, 'tester-reader-prod')) {
  name: 'tester-reader-${parResourceGroupNameProd}'
  scope: resourceGroup(parResourceGroupNameProd)
  params: {
    principalId: parTesterGroupPrincipalId
    roleDefinitionIdOrName: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', varReaderRoleId)
    principalType: 'Group'
  }
}

module modPartnerReaderAssignment 'br/public:avm/res/authorization/role-assignment/rg-scope:0.1.1' = if (!contains(parExistingAssignments, 'partner-reader-platform')) {
  name: 'partner-reader-${parResourceGroupNamePlatform}'
  scope: resourceGroup(parResourceGroupNamePlatform)
  params: {
    principalId: parPartnerPrincipalId
    roleDefinitionIdOrName: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', varReaderRoleId)
    principalType: 'User'
  }
}
