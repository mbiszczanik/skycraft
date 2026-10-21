/*=====================================================
SUMMARY: Lab 1.3 - Governance Orchestrator
DESCRIPTION: Orchestrates deployment of tags, policies, and locks for Lab 1.3 via AVM (requires the Lab 1.2 resource groups to exist)
EXAMPLE: .\scripts\Deploy-Bicep.ps1 -Owner mbiszczanik
AUTHOR/S: Marcin Biszczanik
VERSION: 0.4.0
DEPLOYMENT: .\scripts\Deploy-Bicep.ps1
======================================================*/

targetScope = 'subscription'

/*******************
*    Parameters    *
*******************/

@description('Deployment region; the location of the policy assignments and of the managed identity of Inherit-Project-Tag')
@allowed([
  'swedencentral'
  'northeurope'
])
param parLocation string = 'swedencentral'

@description('Resource owner tag value')
@minLength(1)
param parOwner string = 'mbiszczanik'

// Parity with a lab built in the Portal (issue #406). The Portal names a policy assignment with a
// generated id, so a fixed-name module would create a second assignment next to the learner's.
// Deploy-Bicep.ps1 finds the learner's assignments by definition and scope and fills these three;
// left at their defaults, the template creates everything itself.
@description('Guide names of the policy assignments that already exist under another resource name (made in the Portal); the template leaves them as they are')
param parExistingPolicyAssignments array = []

@description('Whether the Inherit-Project-Tag module grants its identity Contributor; false when the identity holds it already (a second grant fails with RoleAssignmentExists)')
param parGrantInheritProjectTagRole bool = true

@description('Principal id of an existing Inherit-Project-Tag identity that does not hold Contributor yet; the template grants it')
param parInheritProjectTagPrincipalId string = ''

/*******************
*    Variables     *
*******************/

var varRgDev = 'dev-skycraft-swc-rg'
var varRgProd = 'prod-skycraft-swc-rg'
var varRgPlatform = 'platform-skycraft-swc-rg'

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

// Fixed list covering every region Lab 1.2 allows, so the Deny policy can never exclude
// the region the existing resource groups live in (independent of the deployment region).
var varAllowedLocations = [
  'swedencentral'
  'northeurope'
]

// Contributor: the role Inherit-Project-Tag's definition lists in roleDefinitionIds.
var varContributorRoleId = '/providers/Microsoft.Authorization/roleDefinitions/b24988ac-6180-42a0-ab88-20f7382dd24c'

/*******************
*    Resources     *
*******************/

// The prod/platform resource groups already exist (created in Lab 1.2). Their location is
// read back so the AVM resource-group re-declaration below stays idempotent regardless of
// the region this deployment runs from (resource group location is immutable).
resource resRgProd 'Microsoft.Resources/resourceGroups@2023-07-01' existing = {
  name: varRgProd
}

resource resRgPlatform 'Microsoft.Resources/resourceGroups@2023-07-01' existing = {
  name: varRgPlatform
}

/*******************
*     Modules      *
*******************/

// 1. Tags on the dev resource group via the local fallback module
//    (Microsoft.Resources/tags has no AVM module - docs/bicep-standards.md, Section 4.3).
//    Kept deliberately as the teaching example of a fallback; prod/platform below get their
//    tags through the AVM resource-group module's own 'tags' parameter instead.
module modTagsDev 'modules/tags.bicep' = {
  name: 'deploy-tags-dev'
  scope: resourceGroup(varRgDev)
  params: {
    parTags: varTagsDev
  }
}

// 2. Locks and tags on prod/platform via the AVM resource-group module.
//    Re-declaring the RG is idempotent; the built-in 'lock' parameter replaces the
//    former modules/locks.bicep. Tags must be passed too - an RG PUT without tags
//    would wipe the ones applied in Lab 1.2.
//    Lock notes are fixed by the module ('Cannot delete resource or child resources.').
module modRgProd 'br/public:avm/res/resources/resource-group:0.4.4' = {
  name: 'deploy-rg-prod-governance'
  params: {
    name: varRgProd
    location: resRgProd.location
    tags: varTagsProd
    lock: {
      kind: 'CanNotDelete'
      name: 'lock-no-delete-prod'
    }
  }
}

module modRgPlatform 'br/public:avm/res/resources/resource-group:0.4.4' = {
  name: 'deploy-rg-platform-governance'
  params: {
    name: varRgPlatform
    location: resRgPlatform.location
    tags: varTagsPlatform
    lock: {
      kind: 'CanNotDelete'
      name: 'lock-no-delete-platform'
    }
  }
}

// 3. Policy assignments at subscription scope via AVM. definitionVersion pins the built-in
//    definitions' major version explicitly (Azure stores '1.*.*' by default) so what-if reports
//    NoChange on re-runs instead of a spurious Modify.
//    The module defaults managedIdentities to { systemAssigned: true }, so every assignment would
//    get an identity. The three Deny assignments set it to {} - no identity - as the Portal and
//    Invoke-LabGovernance.ps1 create them: a Deny changes nothing and needs none. Only
//    Inherit-Project-Tag (Modify) carries an identity in every path.
//    Display names, descriptions and non-compliance messages are the texts the guide has the
//    learner type (issue #406), so both paths end in the same state. An assignment listed in
//    parExistingPolicyAssignments exists under a Portal-generated name and is not deployed.
module modRequireTagPolicy 'br/public:avm/res/authorization/policy-assignment/sub-scope:0.1.0' = if (!contains(parExistingPolicyAssignments, 'Require-Environment-Tag-RG')) {
  name: 'Require-Environment-Tag-RG'
  params: {
    name: 'Require-Environment-Tag-RG'
    location: parLocation
    managedIdentities: {}
    policyDefinitionId: '/providers/Microsoft.Authorization/policyDefinitions/96670d01-0a4d-4649-9c89-2d3abc0a5025'
    definitionVersion: '1.*.*'
    displayName: 'Require-Environment-Tag-RG'
    description: 'All resource groups must have an Environment tag'
    parameters: {
      tagName: {
        value: 'Environment'
      }
    }
    nonComplianceMessages: [
      {
        message: 'Resource group must have an Environment tag (Development, Production, or Platform)'
      }
    ]
  }
}

module modEnforceProjectTagPolicy 'br/public:avm/res/authorization/policy-assignment/sub-scope:0.1.0' = if (!contains(parExistingPolicyAssignments, 'Enforce-Project-Tag')) {
  name: 'Enforce-Project-Tag'
  params: {
    name: 'Enforce-Project-Tag'
    location: parLocation
    managedIdentities: {}
    policyDefinitionId: '/providers/Microsoft.Authorization/policyDefinitions/1e30110a-5ceb-460c-a204-c1c3969c6d62'
    definitionVersion: '1.*.*'
    displayName: 'Enforce-Project-Tag'
    description: 'All resources must have Project tag set to SkyCraft'
    parameters: {
      tagName: {
        value: 'Project'
      }
      tagValue: {
        value: 'SkyCraft'
      }
    }
    nonComplianceMessages: [
      {
        message: 'All resources must be tagged with Project=SkyCraft'
      }
    ]
  }
}

// Modify assignment next to Enforce-Project-Tag (issue #350): a resource created without the
// Project tag gets its resource group's value. Azure Policy runs Modify before Deny, so resources
// a learner cannot tag (VM extensions, autoscale settings, deployment slots, resources a service
// creates) pass Enforce-Project-Tag when their group carries the tag. A Modify assignment needs a
// managed identity; the identity gets Contributor on the subscription, the role the built-in
// definition lists in roleDefinitionIds and the one the Portal grants itself, so the Portal and
// Bicep paths end in the same state. Only a remediation task uses the role: a request-time
// Modify needs none. Granting it needs Owner (or User Access Administrator) on the subscription:
// with Contributor alone the module's role-assignment deployment fails, while the Portal creates
// the assignment without the role (the guide's Prerequisites say so).
module modInheritProjectTagPolicy 'br/public:avm/res/authorization/policy-assignment/sub-scope:0.1.0' = if (!contains(parExistingPolicyAssignments, 'Inherit-Project-Tag')) {
  name: 'Inherit-Project-Tag'
  params: {
    name: 'Inherit-Project-Tag'
    location: parLocation
    policyDefinitionId: '/providers/Microsoft.Authorization/policyDefinitions/ea3f2387-9b95-492a-a190-fcdc54f7b070'
    definitionVersion: '1.*.*'
    displayName: 'Inherit-Project-Tag'
    description: 'Resources get the Project tag of their resource group when they are created without it'
    parameters: {
      tagName: {
        value: 'Project'
      }
    }
    managedIdentities: {
      systemAssigned: true
    }
    roleDefinitionIds: parGrantInheritProjectTagRole ? [varContributorRoleId] : []
  }
}

// The role of a Portal-made Inherit-Project-Tag whose identity does not hold it (the module above
// is not deployed then). The Portal grants it itself unless the learner may not assign roles.
module modInheritProjectTagRole 'br/public:avm/res/authorization/role-assignment/sub-scope:0.1.1' = if (!empty(parInheritProjectTagPrincipalId)) {
  name: 'Inherit-Project-Tag-Role'
  params: {
    principalId: parInheritProjectTagPrincipalId
    // The module's built-in name resolves to the subscription-scoped id the Portal writes.
    roleDefinitionIdOrName: 'Contributor'
    principalType: 'ServicePrincipal'
  }
}

module modAllowedLocationsPolicy 'br/public:avm/res/authorization/policy-assignment/sub-scope:0.1.0' = if (!contains(parExistingPolicyAssignments, 'Restrict-Azure-Regions')) {
  name: 'Restrict-Azure-Regions'
  params: {
    name: 'Restrict-Azure-Regions'
    location: parLocation
    managedIdentities: {}
    policyDefinitionId: '/providers/Microsoft.Authorization/policyDefinitions/e56962a6-4747-49cd-b67b-bf8b01975c4c'
    definitionVersion: '1.*.*'
    displayName: 'Restrict-Azure-Regions'
    description: 'Resources can only be created in Sweden Central and North Europe'
    parameters: {
      listOfAllowedLocations: {
        value: varAllowedLocations
      }
    }
    nonComplianceMessages: [
      {
        message: 'Resources must be deployed to Sweden Central or North Europe regions only'
      }
    ]
  }
}
