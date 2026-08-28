/*=====================================================
SUMMARY: Lab 3.4 - App Service Orchestrator
DESCRIPTION: Deploys the Linux App Service Plan (P0v4), the Node web app with a staging slot and regional VNet integration, and the CPU autoscale setting for SkyCraft Lab 3.4 via Azure Verified Modules (autoscale via a local fallback module)
EXAMPLE: az deployment sub create --location swedencentral --template-file main.bicep
AUTHOR/S: Marcin Biszczanik
VERSION: 0.2.0
DEPLOYMENT: .\scripts\Deploy-Bicep.ps1
======================================================*/

targetScope = 'subscription'

/*******************
*    Parameters    *
*******************/

@description('Location for all resources')
@allowed(['swedencentral', 'northeurope'])
param parLocation string = 'swedencentral'

@description('Environment name (used in resource names and mapped to the canonical Environment tag)')
@allowed(['dev', 'prod'])
param parEnvironment string = 'dev'

@description('Resource owner tag value')
@minLength(1)
param parOwner string = 'mbiszczanik'

@description('Resource Group Name')
@minLength(1)
@maxLength(90)
param parResourceGroupName string = 'dev-skycraft-swc-rg'

@description('VNet Name')
@minLength(2)
@maxLength(64)
param parVnetName string = 'dev-skycraft-swc-vnet'

@description('Delegated subnet name for App Service VNet integration')
@minLength(1)
@maxLength(80)
param parSubnetName string = 'AppServiceSubnet'

/*******************
*    Variables     *
*******************/

var varAppServicePlanName = '${parEnvironment}-skycraft-swc-asp'
var varAppName = '${parEnvironment}-skycraft-swc-app01' // Must be globally unique; change on collision
var varEnvironmentTag = parEnvironment == 'dev' ? 'Development' : 'Production'
var varCommonTags = {
  Project: 'SkyCraft'
  Environment: varEnvironmentTag
  CostCenter: 'MSDN'
  Owner: parOwner
}

/*******************
*     Existing     *
*******************/

resource resRg 'Microsoft.Resources/resourceGroups@2023-07-01' existing = {
  name: parResourceGroupName
}

resource resSubnet 'Microsoft.Network/virtualNetworks/subnets@2023-11-01' existing = {
  name: '${parVnetName}/${parSubnetName}'
  scope: resRg
}

/*******************
*     Modules      *
*******************/

// App Service Plan - Premium V4 P0v4, Linux, one instance
module modAppServicePlan 'br/public:avm/res/web/serverfarm:0.7.0' = {
  name: 'asp-deployment'
  scope: resRg
  params: {
    name: varAppServicePlanName
    location: parLocation
    tags: varCommonTags
    kind: 'linux'
    skuName: 'P0v4'
    skuCapacity: 1
    zoneRedundant: false // Lab-friction override (standards section 4.5): AVM defaults P-SKUs to zone-redundant
  }
}

// Web App (Node 20 LTS) with the staging slot and regional VNet integration.
// The slot inherits siteConfig, httpsOnly, identity and the VNet integration from the app.
module modWebApp 'br/public:avm/res/web/site:0.24.0' = {
  name: 'webapp-deployment'
  scope: resRg
  params: {
    name: varAppName
    location: parLocation
    tags: varCommonTags
    kind: 'app,linux'
    serverFarmResourceId: modAppServicePlan.outputs.resourceId
    httpsOnly: true
    managedIdentities: {
      systemAssigned: true
    }
    virtualNetworkSubnetResourceId: resSubnet.id
    siteConfig: {
      linuxFxVersion: 'NODE|20-lts'
      vnetRouteAllEnabled: true
      minTlsVersion: '1.2'
    }
    slots: [
      {
        name: 'staging'
      }
    ]
  }
}

// Autoscale - local fallback (avm/res/insights/autoscale-setting is only Proposed; standards section 4.3)
module modAutoscale 'modules/autoscale.bicep' = {
  name: 'autoscale-deployment'
  scope: resRg
  params: {
    parAutoscaleName: '${varAppServicePlanName}-autoscale'
    parLocation: parLocation
    parEnvironment: varEnvironmentTag
    parOwner: parOwner
    parTargetResourceId: modAppServicePlan.outputs.resourceId
  }
}

/******************
*     Outputs     *
******************/

output outWebAppName string = modWebApp.outputs.name
output outWebAppDefaultHostname string = modWebApp.outputs.defaultHostname
output outAppServicePlanId string = modAppServicePlan.outputs.resourceId
output outAutoscaleId string = modAutoscale.outputs.outAutoscaleId
