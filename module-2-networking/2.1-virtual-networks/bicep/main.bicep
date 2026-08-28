/*=====================================================
SUMMARY: Lab 2.1 - Virtual Networks
DESCRIPTION: Orchestrates the Hub VNet, the Dev/Prod Spoke VNets, the Hub-Spoke peerings and the Load Balancer Public IPs via AVM (requires the Lab 1.2 resource groups to exist)
EXAMPLE: az deployment sub create --name Lab-2.1-Virtual-Networks --location swedencentral --template-file main.bicep
AUTHOR/S: Marcin Biszczanik
VERSION: 0.3.0
DEPLOYMENT: .\scripts\Deploy-Bicep.ps1
======================================================*/

targetScope = 'subscription'

/*******************
*    Parameters    *
*******************/

@description('Location for all resources')
@allowed([
  'swedencentral'
  'northeurope'
])
param parLocation string = 'swedencentral'

@description('Resource owner tag value')
@minLength(1)
param parOwner string = 'mbiszczanik'

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

@description('Platform (Hub) VNet Name')
@minLength(2)
@maxLength(64)
param parVnetNamePlatform string = 'platform-skycraft-swc-vnet'

@description('Development (Spoke) VNet Name')
@minLength(2)
@maxLength(64)
param parVnetNameDev string = 'dev-skycraft-swc-vnet'

@description('Production (Spoke) VNet Name')
@minLength(2)
@maxLength(64)
param parVnetNameProd string = 'prod-skycraft-swc-vnet'

/*******************
*    Variables     *
*******************/

var varTagsPlatform = {
  Project: 'SkyCraft'
  Environment: 'Platform'
  CostCenter: 'MSDN'
  Owner: parOwner
}

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

// Address plan (ARCHITECTURE.md; subnet names are the contract for Labs 2.2, 3.x and 4.4 -
// see docs/bicep-standards.md Section 10.2)
var varHubAddressPrefix = '10.0.0.0/16'
var varHubSubnets = [
  {
    name: 'AzureBastionSubnet'
    addressPrefix: '10.0.0.0/26'
  }
  {
    name: 'GatewaySubnet'
    addressPrefix: '10.0.1.0/27'
  }
]

var varDevAddressPrefix = '10.1.0.0/16'
var varDevSubnets = [
  {
    name: 'AuthSubnet'
    addressPrefix: '10.1.1.0/24'
  }
  {
    name: 'WorldSubnet'
    addressPrefix: '10.1.2.0/24'
  }
  {
    name: 'DatabaseSubnet'
    addressPrefix: '10.1.3.0/24'
  }
  {
    name: 'AppServiceSubnet'
    addressPrefix: '10.1.4.0/24'
    delegation: 'Microsoft.Web/serverFarms'
  }
]

var varProdAddressPrefix = '10.2.0.0/16'
var varProdSubnets = [
  {
    name: 'AuthSubnet'
    addressPrefix: '10.2.1.0/24'
  }
  {
    name: 'WorldSubnet'
    addressPrefix: '10.2.2.0/24'
  }
  {
    name: 'DatabaseSubnet'
    addressPrefix: '10.2.3.0/24'
  }
  {
    name: 'AppServiceSubnet'
    addressPrefix: '10.2.4.0/24'
    delegation: 'Microsoft.Web/serverFarms'
  }
]

var varPipNameDevLb = 'dev-skycraft-swc-lb-pip'
var varPipNameProdLb = 'prod-skycraft-swc-lb-pip'

/*******************
*    Resources     *
*******************/

// The resource groups are created in Lab 1.2; they are only referenced here as module scopes.
resource resRgPlatform 'Microsoft.Resources/resourceGroups@2023-07-01' existing = {
  name: parResourceGroupNamePlatform
}

resource resRgDev 'Microsoft.Resources/resourceGroups@2023-07-01' existing = {
  name: parResourceGroupNameDev
}

resource resRgProd 'Microsoft.Resources/resourceGroups@2023-07-01' existing = {
  name: parResourceGroupNameProd
}

/*******************
*     Modules      *
*******************/

// 1. Spoke VNets. NSG associations are applied later by Lab 2.2; re-running this template
//    after Lab 2.2 re-declares the subnets without NSGs or service endpoints - run the labs in order.
module modVnetDev 'br/public:avm/res/network/virtual-network:0.10.2' = {
  name: 'dev-vnet-deployment'
  scope: resRgDev
  params: {
    name: parVnetNameDev
    location: parLocation
    tags: varTagsDev
    addressPrefixes: [
      varDevAddressPrefix
    ]
    subnets: varDevSubnets
  }
}

module modVnetProd 'br/public:avm/res/network/virtual-network:0.10.2' = {
  name: 'prod-vnet-deployment'
  scope: resRgProd
  params: {
    name: parVnetNameProd
    location: parLocation
    tags: varTagsProd
    addressPrefixes: [
      varProdAddressPrefix
    ]
    subnets: varProdSubnets
  }
}

// 2. Hub VNet with both Hub-Spoke peerings. remotePeeringEnabled makes the AVM module create
//    the reverse (spoke-to-hub) peering inside the spoke's resource group, so all four peering
//    links are declared in one place. Referencing the spoke outputs orders the deployment.
//    The names are the ones Test-Lab.ps1 expects (hub-to-dev, dev-to-hub, hub-to-prod, prod-to-hub).
module modVnetHub 'br/public:avm/res/network/virtual-network:0.10.2' = {
  name: 'hub-vnet-deployment'
  scope: resRgPlatform
  params: {
    name: parVnetNamePlatform
    location: parLocation
    tags: varTagsPlatform
    addressPrefixes: [
      varHubAddressPrefix
    ]
    subnets: varHubSubnets
    peerings: [
      {
        name: 'hub-to-dev'
        remoteVirtualNetworkResourceId: modVnetDev.outputs.resourceId
        allowVirtualNetworkAccess: true
        allowForwardedTraffic: true
        allowGatewayTransit: false
        useRemoteGateways: false
        remotePeeringEnabled: true
        remotePeeringName: 'dev-to-hub'
        remotePeeringAllowVirtualNetworkAccess: true
        remotePeeringAllowForwardedTraffic: true
        remotePeeringAllowGatewayTransit: false
        remotePeeringUseRemoteGateways: false
      }
      {
        name: 'hub-to-prod'
        remoteVirtualNetworkResourceId: modVnetProd.outputs.resourceId
        allowVirtualNetworkAccess: true
        allowForwardedTraffic: true
        allowGatewayTransit: false
        useRemoteGateways: false
        remotePeeringEnabled: true
        remotePeeringName: 'prod-to-hub'
        remotePeeringAllowVirtualNetworkAccess: true
        remotePeeringAllowForwardedTraffic: true
        remotePeeringAllowGatewayTransit: false
        remotePeeringUseRemoteGateways: false
      }
    ]
  }
}

// 3. Public IPs reserved for the Lab 2.3 load balancers: Standard SKU, static, zone-redundant
//    (AVM default availabilityZones [1, 2, 3] - also the portal default for Standard SKU).
module modPipDevLb 'br/public:avm/res/network/public-ip-address:0.13.0' = {
  name: 'dev-lb-pip-deployment'
  scope: resRgDev
  params: {
    name: varPipNameDevLb
    location: parLocation
    tags: varTagsDev
    skuName: 'Standard'
    publicIPAllocationMethod: 'Static'
  }
}

module modPipProdLb 'br/public:avm/res/network/public-ip-address:0.13.0' = {
  name: 'prod-lb-pip-deployment'
  scope: resRgProd
  params: {
    name: varPipNameProdLb
    location: parLocation
    tags: varTagsProd
    skuName: 'Standard'
    publicIPAllocationMethod: 'Static'
  }
}

/******************
*     Outputs     *
******************/

output outHubVnetId string = modVnetHub.outputs.resourceId
output outDevVnetId string = modVnetDev.outputs.resourceId
output outProdVnetId string = modVnetProd.outputs.resourceId
