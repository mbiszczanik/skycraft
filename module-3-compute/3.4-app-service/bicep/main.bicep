/*=====================================================
SUMMARY: Lab 3.4 - App Service Orchestrator
DESCRIPTION: Orchestrates deployment of App Service Lab resources
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

@description('Environment Name')
@allowed(['dev', 'prod'])
param parEnvironment string = 'dev'

@description('Resource Group Name')
@minLength(1)
@maxLength(90)
param parResourceGroupName string = 'dev-skycraft-swc-rg'

@description('VNet Name')
@minLength(2)
@maxLength(64)
param parVnetName string = 'dev-skycraft-swc-vnet'

@description('Subnet Name for App Service')
@minLength(1)
@maxLength(80)
param parSubnetName string = 'AppServiceSubnet'

/*******************
*    Resources     *
*******************/

resource resRg 'Microsoft.Resources/resourceGroups@2023-07-01' existing = {
  name: parResourceGroupName
}

// Reference existing VNet to construct Subnet ID
resource resVnet 'Microsoft.Network/virtualNetworks@2023-11-01' existing = {
  scope: resRg
  name: parVnetName
}

// Construct Subnet ID manually or via nested resource reference
// Using string interpolation is reliable for existing subnets
var varSubnetId = '${resVnet.id}/subnets/${parSubnetName}'

module modAppService 'modules/app-service.bicep' = {
  name: 'deploy-app-service-${parEnvironment}'
  scope: resRg
  params: {
    parLocation: parLocation
    parEnvironment: parEnvironment
    parAppServicePlanName: '${parEnvironment}-skycraft-swc-asp'
    parAppName: '${parEnvironment}-skycraft-swc-app01' // Note: This must be globally unique. User might need to change it if collision.
    parSubnetId: varSubnetId
  }
}

/******************
*     Outputs     *
******************/
output outWebAppName string = modAppService.outputs.outWebAppName
output outAppServicePlanId string = modAppService.outputs.outAppServicePlanId
