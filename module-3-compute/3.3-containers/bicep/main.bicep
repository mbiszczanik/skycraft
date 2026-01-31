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
param parLocation string = 'swedencentral'

@description('Resource Group Name')
param parResourceGroupName string = 'dev-skycraft-swc-rg'

@description('Environment tag')
param parEnvironment string = 'dev'

@description('Name of the Container Registry')
param parAcrName string = 'devskycraftswcacr01'

@description('Name of the ACI Instance')
param parAciName string = 'dev-skycraft-swc-aci-auth'

@description('Name of the Container Apps Environment')
param parCaeName string = 'dev-skycraft-swc-cae-02'

@description('Name of the Container App')
param parAcaName string = 'dev-skycraft-swc-aca-world-02'

@description('Name of the image repository and tag')
param parImage string = 'skycraft-auth:v1'

/*******************
*    Resources     *
*******************/

// Ensure Resource Group exists
resource resRg 'Microsoft.Resources/resourceGroups@2023-07-01' = {
  name: parResourceGroupName
  location: parLocation
  tags: {
    Project: 'SkyCraft'
    Environment: parEnvironment
  }
}

// 1. Deploy ACR
module modAcr 'modules/acr.bicep' = {
  name: 'deploy-acr'
  scope: resRg
  params: {
    parLocation: parLocation
    parEnvironment: parEnvironment
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
    parEnvironment: parEnvironment
    parAcrName: parAcrName
    parAciName: parAciName
    parImage: parImage
  }
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
    parEnvironment: parEnvironment
    parAcrName: parAcrName
    parCaeName: parCaeName
    parAcaName: parAcaName
    parImage: parImage
  }
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
