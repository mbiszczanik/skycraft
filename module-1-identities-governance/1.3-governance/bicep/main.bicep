/*=====================================================
SUMMARY: Lab 1.3 - Governance Orchestrator
DESCRIPTION: Orchestrates deployment of tags, policies, and locks for Lab 1.3
EXAMPLE: az deployment sub create --location swedencentral --template-file main.bicep
AUTHOR/S: Marcin Biszczanik
VERSION: 0.1.0
DEPLOYMENT: .\scripts\Deploy-Bicep.ps1
======================================================*/

targetScope = 'subscription'

/*******************
*    Parameters    *
*******************/

@description('Azure Region')
param parLocation string = 'swedencentral'

@description('Admin Email for Owner Tag')
param parAdminEmail string = 'malfurion.stormrage@skycraft.com'

/*******************
*    Variables     *
*******************/

var varRgDev = 'dev-skycraft-swc-rg'
var varRgProd = 'prod-skycraft-swc-rg'
var varRgPlatform = 'platform-skycraft-swc-rg'

var varTagsDev = {
  Environment: 'Development'
  Project: 'SkyCraft'
  CostCenter: 'MSDN'
  Owner: parAdminEmail
}

var varTagsProd = {
  Environment: 'Production'
  Project: 'SkyCraft'
  CostCenter: 'MSDN'
  Owner: parAdminEmail
  Criticality: 'High'
}

var varTagsPlatform = {
  Environment: 'Platform'
  Project: 'SkyCraft'
  CostCenter: 'MSDN'
  Owner: parAdminEmail
}

/*******************
*     Modules      *
*******************/

// 1. Apply Tags
module modTagsDev 'modules/tags.bicep' = {
  name: 'deploy-tags-dev'
  scope: resourceGroup(varRgDev)
  params: {
    parTags: varTagsDev
  }
}

module modTagsProd 'modules/tags.bicep' = {
  name: 'deploy-tags-prod'
  scope: resourceGroup(varRgProd)
  params: {
    parTags: varTagsProd
  }
}

module modTagsPlatform 'modules/tags.bicep' = {
  name: 'deploy-tags-platform'
  scope: resourceGroup(varRgPlatform)
  params: {
    parTags: varTagsPlatform
  }
}

// 2. Assign Policies (Subscription Scope)
module modPolicies 'modules/policies.bicep' = {
  name: 'deploy-policies'
  params: {
    parAllowedLocations: [
      parLocation
      'northeurope'
    ]
  }
}

// 3. Apply Locks
module modLockProd 'modules/locks.bicep' = {
  name: 'deploy-lock-prod'
  scope: resourceGroup(varRgProd)
  params: {
    parLockName: 'lock-no-delete-prod'
    parLockNotes: 'Prevents accidental deletion of production resources'
  }
  dependsOn: [
    modTagsProd
  ]
}

module modLockPlatform 'modules/locks.bicep' = {
  name: 'deploy-lock-platform'
  scope: resourceGroup(varRgPlatform)
  params: {
    parLockName: 'lock-no-delete-platform'
    parLockNotes: 'Protects platform monitoring and logging infrastructure'
  }
  dependsOn: [
    modTagsPlatform
  ]
}
