/*=====================================================
SUMMARY: Lab 3.3 - Orchestrator
DESCRIPTION: Orchestrates deployment for Lab 3.3 (ACR, ACI, CA)
EXAMPLE: az deployment sub create --location swedencentral --template-file main.bicep
AUTHOR/S: Antigravity
VERSION: 0.1.0
DEPLOYMENT: .\scripts\Deploy-Bicep.ps1
======================================================*/

targetScope = 'subscription'

/*******************
*    Parameters    *
*******************/
@description('Location for all resources')
@allowed(['swedencentral', 'northeurope'])
param parLocation string = 'swedencentral'

@description('Resource Group Name')
@minLength(1)
@maxLength(90)
param parResourceGroupName string = 'dev-skycraft-swc-rg'

@description('Environment axis for naming and parameter-file selection (short form)')
@allowed(['dev', 'prod', 'platform'])
param parEnvironment string = 'dev'

@description('Owner e-mail address for the canonical Owner governance tag')
param parOwnerEmail string = 'admin@skycraft.com'

@description('Name of the Container Registry')
@minLength(5)
@maxLength(50)
param parAcrName string = 'devskycraftswcacr01'

@description('Name of the ACI Instance')
@minLength(1)
@maxLength(63)
param parAciName string = 'dev-skycraft-swc-aci-auth'

@description('Name of the Container Apps Environment')
@minLength(2)
@maxLength(60)
param parCaeName string = 'dev-skycraft-swc-cae-02'

@description('Name of the Container App')
@minLength(2)
@maxLength(32)
param parAcaName string = 'dev-skycraft-swc-aca-world-02'

@description('Name of the image repository and tag')
param parImage string = 'skycraft-auth:v1'

/*******************
*    Variables     *
*******************/
// parEnvironment stays short because it drives resource naming and the .bicepparam
// axis, but the Environment *tag* must carry the canonical value from
// bicep-standards.md §5. Same mapping as labs 4.3 and 4.4.
var varEnvironmentTag = parEnvironment == 'prod' ? 'Production' : (parEnvironment == 'dev' ? 'Development' : 'Platform')

/*******************
*    Resources     *
*******************/

// Ensure Resource Group exists
resource resRg 'Microsoft.Resources/resourceGroups@2023-07-01' = {
  name: parResourceGroupName
  location: parLocation
  tags: {
    Project: 'SkyCraft'
    Environment: varEnvironmentTag
    CostCenter: 'MSDN'
    Owner: parOwnerEmail
  }
}

// 1. Deploy ACR
module modAcr 'modules/acr.bicep' = {
  name: 'deploy-acr'
  scope: resRg
  params: {
    parLocation: parLocation
    parEnvironment: varEnvironmentTag
    parOwnerEmail: parOwnerEmail
    parAcrName: parAcrName
  }
}

// Note: The image must exist in ACR before ACI/ACA deployment succeeds if pulling immediately.
// In a real pipeline, you'd deploy ACR -> Build Image -> Deploy Compute.
// Here modules might fail if image is missing. User is expected to run "az acr build..." manually after ACR creation if following guides strictly.
// However, if running this template fully, it assumes image exists or will retry.

// 2. Deploy ACI
module modAci 'modules/aci.bicep' = {
  name: 'deploy-aci'
  scope: resRg
  params: {
    parLocation: parLocation
    parEnvironment: varEnvironmentTag
    parOwnerEmail: parOwnerEmail
    parAcrName: parAcrName
    parAciName: parAciName
    parImage: parImage
  }
  // Non-symbolic: the ACR is referenced by name (existing) and must hold the
  // pushed image before the container can start.
  dependsOn: [
    modAcr
  ]
}

// 3. Deploy Container Apps
module modAca 'modules/containerapps.bicep' = {
  name: 'deploy-aca'
  scope: resRg
  params: {
    parLocation: parLocation
    parEnvironment: varEnvironmentTag
    parOwnerEmail: parOwnerEmail
    parAcrName: parAcrName
    parCaeName: parCaeName
    parAcaName: parAcaName
    parImage: parImage
  }
  // Non-symbolic: the ACR is referenced by name (existing) and must hold the
  // pushed image before the container can start.
  dependsOn: [
    modAcr
  ]
}

/******************
*     Outputs     *
******************/
output outAcrLoginServer string = modAcr.outputs.outAcrLoginServer
output outAciFqdn string = modAci.outputs.outAciFqdn
output outAcaFqdn string = modAca.outputs.outAcaFqdn
