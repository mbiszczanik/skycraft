/*=====================================================
SUMMARY: Lab 3.3 - Container Registry bootstrap
DESCRIPTION: Deploys only the Container Registry (same configuration as main.bicep) so Deploy-Bicep.ps1 can import the image before the orchestrator deploys ACI and Container Apps
EXAMPLE: az deployment group create --resource-group dev-skycraft-swc-rg --template-file acr.bicep
AUTHOR/S: Marcin Biszczanik
VERSION: 0.1.0
DEPLOYMENT: .\scripts\Deploy-Bicep.ps1 (Phase 1)
======================================================*/

targetScope = 'resourceGroup'

/*******************
*    Parameters    *
*******************/

@description('Location for the registry')
param parLocation string = resourceGroup().location

@description('Environment (maps to the canonical Environment tag value)')
@allowed(['dev', 'prod', 'platform'])
param parEnvironment string = 'dev'

@description('Resource owner tag value')
@minLength(1)
param parOwner string = 'mbiszczanik'

@description('Name of the Container Registry (alphanumeric, globally unique)')
@minLength(5)
@maxLength(50)
param parAcrName string = 'devskycraftswcacr01'

/*******************
*    Variables     *
*******************/

var varEnvironmentTags = {
  dev: 'Development'
  prod: 'Production'
  platform: 'Platform'
}
var varCommonTags = {
  Project: 'SkyCraft'
  Environment: varEnvironmentTags[parEnvironment]
  CostCenter: 'MSDN'
  Owner: parOwner
}

/*******************
*     Modules      *
*******************/

// Keep in sync with modAcr in main.bicep
module modAcr 'br/public:avm/res/container-registry/registry:0.13.0' = {
  name: 'acr-bootstrap-deployment'
  params: {
    name: toLower(parAcrName)
    location: parLocation
    tags: varCommonTags
    acrSku: 'Standard'
    acrAdminUserEnabled: true
    publicNetworkAccess: 'Enabled'
    networkRuleSetDefaultAction: 'Allow' // AVM default 'Deny' would add a network rule set that blocks the lab
    // AVM defaults this to 'disabled'; Azure's own default is 'enabled'. While disabled, ARM-audience tokens
    // cannot reach the registry data plane, so Get-AzContainerRegistryRepository (used by Test-Lab.ps1)
    // fails with 'Unauthorized' even though the image is present.
    azureADAuthenticationAsArmPolicyStatus: 'enabled'
  }
}

/******************
*     Outputs     *
******************/

output outAcrName string = modAcr.outputs.name
output outAcrLoginServer string = modAcr.outputs.loginServer
