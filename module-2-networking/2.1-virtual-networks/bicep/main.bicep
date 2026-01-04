/*=====================================================
SUMMARY: Lab 2.1 - Virtual Networks
DESCRIPTION: Orchestrates the deployment of Hub VNet, Spoke VNet, and Peering.
EXAMPLE: az deployment sub create --name Lab-2.1-Virtual-Networks --location swedencentral --template-file main.bicep
AUTHOR/S: Marcin Biszczanik
VERSION: 0.1.0
DEPLOYMENT: .\scripts\Deploy-Bicep.ps1
======================================================*/

targetScope = 'subscription'

/*******************
*    Parameters    *
*******************/
@description('Location for all resources')
param parLocation string = 'swedencentral'

@description('Production Resource Group Name')
param parResourceGroupNameProd string = 'prod-skycraft-swc-rg'

@description('Platform Resource Group Name')
param parResourceGroupNamePlatform string = 'platform-skycraft-swc-rg'

@description('Production VNet Name')
param parVnetNameProd string = 'prod-skycraft-swc-vnet'

@description('Platform VNet Name')
param parVnetNamePlatform string = 'platform-skycraft-swc-vnet'

/*******************
*    Resources     *
*******************/

// Deploy Hub VNet
module modVnetHub 'modules/vnet-hub.bicep' = {
  name: 'hub-vnet-deployment'
  scope: resourceGroup(parResourceGroupNamePlatform)
  params: {
    parLocation: parLocation
    parVnetName: parVnetNamePlatform
  }
}

// Deploy Spoke VNet
module modVnetSpoke 'modules/vnet-spoke.bicep' = {
  name: 'spoke-vnet-deployment'
  scope: resourceGroup(parResourceGroupNameProd)
  params: {
    parLocation: parLocation
    parVnetName: parVnetNameProd
  }
}

// Peering: Hub -> Spoke
module modPeeringHubToSpoke 'modules/vnet-peering.bicep' = {
  name: 'peering-hub-to-prod-deployment'
  scope: resourceGroup(parResourceGroupNamePlatform)
  params: {
    parSourceVnetName: parVnetNamePlatform
    parTargetVnetId: modVnetSpoke.outputs.outVnetId
    parPeeringName: 'peer-hub-to-prod'
  }
}

// Peering: Spoke -> Hub
module modPeeringSpokeToHub 'modules/vnet-peering.bicep' = {
  name: 'peering-prod-to-hub-deployment'
  scope: resourceGroup(parResourceGroupNameProd)
  params: {
    parSourceVnetName: parVnetNameProd
    parTargetVnetId: modVnetHub.outputs.outVnetId
    parPeeringName: 'peer-prod-to-hub'
  }
  dependsOn: [
    modPeeringHubToSpoke
  ]
}

/******************
*     Outputs     *
******************/
output outHubVnetId string = modVnetHub.outputs.outVnetId
output outSpokeVnetId string = modVnetSpoke.outputs.outVnetId
