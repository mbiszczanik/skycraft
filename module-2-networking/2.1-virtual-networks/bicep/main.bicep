/*=====================================================
SUMMARY: Lab 2.1 - Virtual Networks
DESCRIPTION: Orchestrates the deployment of Hub VNet, Spoke VNets (Dev/Prod), Peerings, and Public IPs.
EXAMPLE: az deployment sub create --name Lab-2.1-Virtual-Networks --location swedencentral --template-file main.bicep
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

@description('Platform Resource Group Name')
@minLength(1)
@maxLength(90)
param parResourceGroupNamePlatform string = 'platform-skycraft-swc-rg'

@description('Development Resource Group Name')
@minLength(1)
@maxLength(90)
param parResourceGroupNameDev string = 'dev-skycraft-swc-rg'

@description('Production Resource Group Name')
@minLength(1)
@maxLength(90)
param parResourceGroupNameProd string = 'prod-skycraft-swc-rg'

@description('Platform VNet Name')
@minLength(2)
@maxLength(64)
param parVnetNamePlatform string = 'platform-skycraft-swc-vnet'

@description('Development VNet Name')
@minLength(2)
@maxLength(64)
param parVnetNameDev string = 'dev-skycraft-swc-vnet'

@description('Production VNet Name')
@minLength(2)
@maxLength(64)
param parVnetNameProd string = 'prod-skycraft-swc-vnet'

@description('Owner e-mail address for the canonical Owner governance tag')
param parOwnerEmail string = 'admin@skycraft.com'

/*******************
*    Resources     *
*******************/

// 1. Deploy Hub VNet (Platform)
module modVnetHub 'modules/vnet-hub.bicep' = {
  name: 'hub-vnet-deployment'
  scope: resourceGroup(parResourceGroupNamePlatform)
  params: {
    parLocation: parLocation
    parVnetName: parVnetNamePlatform
    parOwnerEmail: parOwnerEmail
  }
}

// 2. Deploy Spoke VNet (Development)
module modVnetDev 'modules/vnet-spoke.bicep' = {
  name: 'dev-vnet-deployment'
  scope: resourceGroup(parResourceGroupNameDev)
  params: {
    parLocation: parLocation
    parEnvironment: 'Development'
    parVnetName: parVnetNameDev
    parAddressPrefix: '10.1.0.0/16'
    parAuthSubnetPrefix: '10.1.1.0/24'
    parWorldSubnetPrefix: '10.1.2.0/24'
    parDatabaseSubnetPrefix: '10.1.3.0/24'
    parAppServiceSubnetPrefix: '10.1.4.0/24'
    parOwnerEmail: parOwnerEmail
  }
}

// 3. Deploy Spoke VNet (Production)
module modVnetProd 'modules/vnet-spoke.bicep' = {
  name: 'prod-vnet-deployment'
  scope: resourceGroup(parResourceGroupNameProd)
  params: {
    parLocation: parLocation
    parEnvironment: 'Production'
    parVnetName: parVnetNameProd
    parAddressPrefix: '10.2.0.0/16'
    parAuthSubnetPrefix: '10.2.1.0/24'
    parWorldSubnetPrefix: '10.2.2.0/24'
    parDatabaseSubnetPrefix: '10.2.3.0/24'
    parAppServiceSubnetPrefix: '10.2.4.0/24'
    parOwnerEmail: parOwnerEmail
  }
}

// 4. Public IPs

// Bastion PIP (Platform)

// Dev LB PIP
module modPipDevLb 'modules/public-ip.bicep' = {
  name: 'dev-lb-pip-deployment'
  scope: resourceGroup(parResourceGroupNameDev)
  params: {
    parLocation: parLocation
    parPublicIpName: 'dev-skycraft-swc-lb-pip'
    parEnvironment: 'Development'
    parOwnerEmail: parOwnerEmail
  }
}

// Prod LB PIP
module modPipProdLb 'modules/public-ip.bicep' = {
  name: 'prod-lb-pip-deployment'
  scope: resourceGroup(parResourceGroupNameProd)
  params: {
    parLocation: parLocation
    parPublicIpName: 'prod-skycraft-swc-lb-pip'
    parEnvironment: 'Production'
    parOwnerEmail: parOwnerEmail
  }
}

// 5. Peering: Hub <--> Dev

module modPeeringHubToDev 'modules/vnet-peering.bicep' = {
  name: 'peering-hub-to-dev-deployment'
  scope: resourceGroup(parResourceGroupNamePlatform)
  params: {
    parSourceVnetName: parVnetNamePlatform
    parTargetVnetId: modVnetDev.outputs.outVnetId
    parPeeringName: 'hub-to-dev'
  }
  // Non-symbolic: the hub VNet is referenced by name inside the peering module,
  // so Bicep cannot infer it must exist first.
  dependsOn: [
    modVnetHub
  ]
}

module modPeeringDevToHub 'modules/vnet-peering.bicep' = {
  name: 'peering-dev-to-hub-deployment'
  scope: resourceGroup(parResourceGroupNameDev)
  params: {
    parSourceVnetName: parVnetNameDev
    parTargetVnetId: modVnetHub.outputs.outVnetId
    parPeeringName: 'dev-to-hub'
  }
  // Non-symbolic: the dev spoke VNet is referenced by name inside the peering
  // module, so Bicep cannot infer it must exist first.
  dependsOn: [
    modVnetDev
  ]
}

// 6. Peering: Hub <--> Prod

module modPeeringHubToProd 'modules/vnet-peering.bicep' = {
  name: 'peering-hub-to-prod-deployment'
  scope: resourceGroup(parResourceGroupNamePlatform)
  params: {
    parSourceVnetName: parVnetNamePlatform
    parTargetVnetId: modVnetProd.outputs.outVnetId
    parPeeringName: 'hub-to-prod'
  }
  // Serialize peering writes on the hub VNet: concurrent peering PUTs on one VNet
  // fail with AnotherOperationInProgress. This also transitively ensures the hub
  // VNet exists, since modPeeringHubToDev already depends on modVnetHub.
  dependsOn: [
    modPeeringHubToDev
  ]
}

module modPeeringProdToHub 'modules/vnet-peering.bicep' = {
  name: 'peering-prod-to-hub-deployment'
  scope: resourceGroup(parResourceGroupNameProd)
  params: {
    parSourceVnetName: parVnetNameProd
    parTargetVnetId: modVnetHub.outputs.outVnetId
    parPeeringName: 'prod-to-hub'
  }
  // Non-symbolic: the prod spoke VNet is referenced by name inside the peering
  // module, so Bicep cannot infer it must exist first.
  dependsOn: [
    modVnetProd
  ]
}

/******************
*     Outputs     *
******************/
output outHubVnetId string = modVnetHub.outputs.outVnetId
output outDevVnetId string = modVnetDev.outputs.outVnetId
output outProdVnetId string = modVnetProd.outputs.outVnetId
