/*=====================================================
SUMMARY: Lab 2.1 - Virtual Networks
DESCRIPTION: Orchestrates the Hub VNet, the Dev/Prod Spoke VNets, the Hub-Spoke peerings and the Load Balancer Public IPs via AVM (requires the Lab 1.2 resource groups to exist). Subnets and public IPs that already exist are left untouched (see parExistingSubnets).
EXAMPLE: .\scripts\Deploy-Bicep.ps1
AUTHOR/S: Marcin Biszczanik
VERSION: 0.4.0
DEPLOYMENT: .\scripts\Deploy-Bicep.ps1
======================================================*/

targetScope = 'subscription'

/*******************
*      Types       *
*******************/

@description('Names of the subnets that already exist, per VNet')
type existingSubnetsType = {
  @description('Subnets of the hub VNet')
  hub: string[]

  @description('Subnets of the dev VNet')
  dev: string[]

  @description('Subnets of the prod VNet')
  prod: string[]
}

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

// Re-running this lab must not reset what later labs set on its resources (issue #188). A subnet
// that exists is therefore left out of the deployment: re-declaring it would detach the NSGs and
// service endpoints Lab 2.2 attaches, and rename an App Service delegation that the portal created
// as 'delegation' (the AVM module names it after the service and cannot be told otherwise). The
// VNet itself is still deployed (address space, tags, peerings): the Virtual Network API keeps the
// subnets a VNet update does not list, and the AVM module never lists them, so an omitted subnet
// stays exactly as it is. scripts/Deploy-Bicep.ps1 fills this from a lookup; the default is a
// first deployment, in which every subnet is declared.
@description('Subnets that already exist, per VNet. They are left out of the deployment so a re-run keeps the settings later labs added. Filled by scripts/Deploy-Bicep.ps1.')
param parExistingSubnets existingSubnetsType = {
  hub: []
  dev: []
  prod: []
}

// Zones and SKU are fixed when a public IP is created, so there is nothing this lab could update
// on an existing one - and one created without zones (portal, Deploy-Networking.ps1) makes a
// redeploy of the zone-redundant declaration fail. An existing public IP is left untouched.
@description('True when dev-skycraft-swc-lb-pip already exists (filled by scripts/Deploy-Bicep.ps1). It is then left untouched.')
param parDevLbPipExists bool = false

@description('True when prod-skycraft-swc-lb-pip already exists (filled by scripts/Deploy-Bicep.ps1). It is then left untouched.')
param parProdLbPipExists bool = false

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
// see docs/bicep-standards.md Section 10.2).
// privateEndpointNetworkPolicies is set explicitly (docs/bicep-standards.md Section 4.5): left
// unset, the AVM subnet module sends nothing and the API applies 'Enabled', while the portal and
// the other labs' subnets carry 'Disabled'.
var varHubAddressPrefix = '10.0.0.0/16'
var varHubSubnets = [
  {
    name: 'AzureBastionSubnet'
    addressPrefix: '10.0.0.0/26'
    privateEndpointNetworkPolicies: 'Disabled'
  }
  {
    name: 'GatewaySubnet'
    addressPrefix: '10.0.1.0/27'
    privateEndpointNetworkPolicies: 'Disabled'
  }
]

var varDevAddressPrefix = '10.1.0.0/16'
var varDevSubnets = [
  {
    name: 'AuthSubnet'
    addressPrefix: '10.1.1.0/24'
    privateEndpointNetworkPolicies: 'Disabled'
  }
  {
    name: 'WorldSubnet'
    addressPrefix: '10.1.2.0/24'
    privateEndpointNetworkPolicies: 'Disabled'
  }
  {
    name: 'DatabaseSubnet'
    addressPrefix: '10.1.3.0/24'
    privateEndpointNetworkPolicies: 'Disabled'
  }
  {
    name: 'AppServiceSubnet'
    addressPrefix: '10.1.4.0/24'
    delegation: 'Microsoft.Web/serverFarms'
    privateEndpointNetworkPolicies: 'Disabled'
  }
]

var varProdAddressPrefix = '10.2.0.0/16'
var varProdSubnets = [
  {
    name: 'AuthSubnet'
    addressPrefix: '10.2.1.0/24'
    privateEndpointNetworkPolicies: 'Disabled'
  }
  {
    name: 'WorldSubnet'
    addressPrefix: '10.2.2.0/24'
    privateEndpointNetworkPolicies: 'Disabled'
  }
  {
    name: 'DatabaseSubnet'
    addressPrefix: '10.2.3.0/24'
    privateEndpointNetworkPolicies: 'Disabled'
  }
  {
    name: 'AppServiceSubnet'
    addressPrefix: '10.2.4.0/24'
    delegation: 'Microsoft.Web/serverFarms'
    privateEndpointNetworkPolicies: 'Disabled'
  }
]

// Only the subnets that do not exist yet are deployed (see parExistingSubnets).
var varHubSubnetsToDeploy = filter(varHubSubnets, subnet => !contains(parExistingSubnets.hub, subnet.name))
var varDevSubnetsToDeploy = filter(varDevSubnets, subnet => !contains(parExistingSubnets.dev, subnet.name))
var varProdSubnetsToDeploy = filter(varProdSubnets, subnet => !contains(parExistingSubnets.prod, subnet.name))

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

// 1. Spoke VNets. Lab 2.2 later attaches the NSGs and service endpoints to Auth/World/Database;
//    a re-run leaves those subnets out (parExistingSubnets), so it does not detach them.
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
    subnets: varDevSubnetsToDeploy
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
    subnets: varProdSubnetsToDeploy
  }
}

// 2. Hub VNet with both Hub-Spoke peerings. remotePeeringEnabled makes the AVM module create
//    the reverse (spoke-to-hub) peering inside the spoke's resource group, so all four peering
//    links are declared in one place. Referencing the spoke outputs orders the deployment.
//    The names are the ones Test-Lab.ps1 expects (hub-to-dev, dev-to-hub, hub-to-prod, prod-to-hub).
//    doNotVerifyRemoteGateways is set explicitly (docs/bicep-standards.md Section 4.5): the AVM
//    peering module defaults it to true, while Azure, the portal and Az PowerShell create peerings
//    with false, so a re-run over a peering made any other way would modify it.
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
    subnets: varHubSubnetsToDeploy
    peerings: [
      {
        name: 'hub-to-dev'
        remoteVirtualNetworkResourceId: modVnetDev.outputs.resourceId
        allowVirtualNetworkAccess: true
        allowForwardedTraffic: true
        allowGatewayTransit: false
        useRemoteGateways: false
        doNotVerifyRemoteGateways: false
        remotePeeringEnabled: true
        remotePeeringName: 'dev-to-hub'
        remotePeeringAllowVirtualNetworkAccess: true
        remotePeeringAllowForwardedTraffic: true
        remotePeeringAllowGatewayTransit: false
        remotePeeringUseRemoteGateways: false
        remotePeeringDoNotVerifyRemoteGateways: false
      }
      {
        name: 'hub-to-prod'
        remoteVirtualNetworkResourceId: modVnetProd.outputs.resourceId
        allowVirtualNetworkAccess: true
        allowForwardedTraffic: true
        allowGatewayTransit: false
        useRemoteGateways: false
        doNotVerifyRemoteGateways: false
        remotePeeringEnabled: true
        remotePeeringName: 'prod-to-hub'
        remotePeeringAllowVirtualNetworkAccess: true
        remotePeeringAllowForwardedTraffic: true
        remotePeeringAllowGatewayTransit: false
        remotePeeringUseRemoteGateways: false
        remotePeeringDoNotVerifyRemoteGateways: false
      }
    ]
  }
}

// 3. Public IPs reserved for the Lab 2.3 load balancers: Standard SKU, static, zone-redundant
//    (AVM default availabilityZones [1, 2, 3] - also the portal default for Standard SKU).
//    Created only when missing (see parDevLbPipExists).
module modPipDevLb 'br/public:avm/res/network/public-ip-address:0.13.0' = if (!parDevLbPipExists) {
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

module modPipProdLb 'br/public:avm/res/network/public-ip-address:0.13.0' = if (!parProdLbPipExists) {
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
