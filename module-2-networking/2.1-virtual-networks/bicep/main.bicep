/*=====================================================
SUMMARY: Lab 2.1 - Virtual Networks
DESCRIPTION: Orchestrates the Hub VNet, the Dev/Prod Spoke VNets, the Hub-Spoke peerings and the Load Balancer Public IPs via AVM (requires the Lab 1.2 resource groups to exist). Only what is missing is deployed: an existing VNet, subnet or public IP is left untouched (see parHubVnetExists).
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

@description('A subnet of the address plan')
type subnetSpecType = {
  @description('Subnet name (the contract for later labs)')
  name: string

  @description('Subnet address prefix (CIDR)')
  addressPrefix: string

  @description('Optional delegation service name')
  delegation: string?

  @description('Private endpoint network policies')
  privateEndpointNetworkPolicies: 'Disabled' | 'Enabled'
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

// Re-running this lab must not reset what later labs built on its networks (issue #188). Two
// facts about a VNet deployment decide how:
//   - Peerings a VNet deployment does not list are removed: when Lab 3.1 redeployed the hub
//     without them, hub-to-prod disappeared. The AVM VNet module never lists peerings (it adds
//     them afterwards as child resources), so redeploying an existing VNet through it would
//     delete and recreate every peering, and the spoke would lose its route to the hub meanwhile.
//   - Subnets a VNet deployment does not list are kept (Virtual Network API 2023-09-01 and later),
//     but a subnet it does list is replaced by exactly what it declares - that would detach the
//     NSGs and service endpoints Lab 2.2 attaches and rename an App Service delegation that the
//     portal created as 'delegation' (the AVM module names it after the service).
// So a VNet that exists is not redeployed at all. Only what is missing is deployed: the subnets it
// lacks (as child resources of the existing VNet) and the peerings (child resources too; a PUT of
// an existing peering with the same settings changes nothing). scripts/Deploy-Bicep.ps1 fills the
// parameters below from a lookup; the defaults describe a first deployment.
@description('True when the hub VNet already exists (filled by scripts/Deploy-Bicep.ps1). It is then not redeployed; only its missing subnets and the peerings are.')
param parHubVnetExists bool = false

@description('True when the dev VNet already exists (filled by scripts/Deploy-Bicep.ps1). It is then not redeployed; only its missing subnets and the peering are.')
param parDevVnetExists bool = false

@description('True when the prod VNet already exists (filled by scripts/Deploy-Bicep.ps1). It is then not redeployed; only its missing subnets and the peering are.')
param parProdVnetExists bool = false

@description('Subnets that already exist, per VNet. Only the others are deployed into an existing VNet. Filled by scripts/Deploy-Bicep.ps1.')
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
// privateEndpointNetworkPolicies is set explicitly (docs/bicep-standards.md Section 4.5): with it
// unset, the #188 what-if showed existing 'Disabled' subnets going to 'Enabled', and 'Disabled' is
// what the portal creates.
var varHubAddressPrefix = '10.0.0.0/16'
var varHubSubnets subnetSpecType[] = [
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
var varDevSubnets subnetSpecType[] = [
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
var varProdSubnets subnetSpecType[] = [
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

// The subnets an existing VNet still lacks (see parExistingSubnets).
var varHubSubnetsToDeploy = filter(varHubSubnets, subnet => !contains(parExistingSubnets.hub, subnet.name))
var varDevSubnetsToDeploy = filter(varDevSubnets, subnet => !contains(parExistingSubnets.dev, subnet.name))
var varProdSubnetsToDeploy = filter(varProdSubnets, subnet => !contains(parExistingSubnets.prod, subnet.name))

// The VNet IDs by name, whether this deployment creates the VNets or they already stand - used as
// peering targets and outputs. Built with resourceId() rather than 'existing' references, so that
// nothing is read from a VNet that a first deployment has yet to create.
var varVnetIdHub = resourceId(subscription().subscriptionId, parResourceGroupNamePlatform, 'Microsoft.Network/virtualNetworks', parVnetNamePlatform)
var varVnetIdDev = resourceId(subscription().subscriptionId, parResourceGroupNameDev, 'Microsoft.Network/virtualNetworks', parVnetNameDev)
var varVnetIdProd = resourceId(subscription().subscriptionId, parResourceGroupNameProd, 'Microsoft.Network/virtualNetworks', parVnetNameProd)

// The four Hub-Spoke peerings, with the names Test-Lab.ps1 expects (see modPeering).
var varPeerings = [
  {
    name: 'hub-to-dev'
    resourceGroupName: parResourceGroupNamePlatform
    localVnetName: parVnetNamePlatform
    remoteVnetId: varVnetIdDev
  }
  {
    name: 'dev-to-hub'
    resourceGroupName: parResourceGroupNameDev
    localVnetName: parVnetNameDev
    remoteVnetId: varVnetIdHub
  }
  {
    name: 'hub-to-prod'
    resourceGroupName: parResourceGroupNamePlatform
    localVnetName: parVnetNamePlatform
    remoteVnetId: varVnetIdProd
  }
  {
    name: 'prod-to-hub'
    resourceGroupName: parResourceGroupNameProd
    localVnetName: parVnetNameProd
    remoteVnetId: varVnetIdHub
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

// 1. VNets that do not exist yet, with all their subnets. No peerings here: they are declared
//    once, in step 3, for new and existing VNets alike.
module modVnetHub 'br/public:avm/res/network/virtual-network:0.10.2' = if (!parHubVnetExists) {
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
  }
}

module modVnetDev 'br/public:avm/res/network/virtual-network:0.10.2' = if (!parDevVnetExists) {
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

module modVnetProd 'br/public:avm/res/network/virtual-network:0.10.2' = if (!parProdVnetExists) {
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

// 2. Subnets missing from a VNet that already exists, as child resources of that VNet - the VNet
//    itself is not touched. Subnet updates on one VNet must not overlap (AnotherOperationInProgress),
//    hence @batchSize(1). Lab 2.2 later attaches the NSGs and service endpoints to Auth/World/Database.
@batchSize(1)
module modSubnetHub 'br/public:avm/res/network/virtual-network/subnet:0.2.0' = [
  for subnet in (parHubVnetExists ? varHubSubnetsToDeploy : []): {
    name: 'hub-subnet-${subnet.name}-deployment'
    scope: resRgPlatform
    params: {
      name: subnet.name
      virtualNetworkName: parVnetNamePlatform
      addressPrefix: subnet.addressPrefix
      privateEndpointNetworkPolicies: subnet.privateEndpointNetworkPolicies
    }
  }
]

@batchSize(1)
module modSubnetDev 'br/public:avm/res/network/virtual-network/subnet:0.2.0' = [
  for subnet in (parDevVnetExists ? varDevSubnetsToDeploy : []): {
    name: 'dev-subnet-${subnet.name}-deployment'
    scope: resRgDev
    params: {
      name: subnet.name
      virtualNetworkName: parVnetNameDev
      addressPrefix: subnet.addressPrefix
      delegation: subnet.?delegation
      privateEndpointNetworkPolicies: subnet.privateEndpointNetworkPolicies
    }
  }
]

@batchSize(1)
module modSubnetProd 'br/public:avm/res/network/virtual-network/subnet:0.2.0' = [
  for subnet in (parProdVnetExists ? varProdSubnetsToDeploy : []): {
    name: 'prod-subnet-${subnet.name}-deployment'
    scope: resRgProd
    params: {
      name: subnet.name
      virtualNetworkName: parVnetNameProd
      addressPrefix: subnet.addressPrefix
      delegation: subnet.?delegation
      privateEndpointNetworkPolicies: subnet.privateEndpointNetworkPolicies
    }
  }
]

// 3. The four Hub-Spoke peerings (varPeerings), as child resources of their local VNet. Declared
//    the same way whether the VNets are new or existing, so a re-run creates a missing peering and
//    leaves an existing one with these settings unchanged. doNotVerifyRemoteGateways is set
//    explicitly (docs/bicep-standards.md Section 4.5): the AVM peering module defaults it to true,
//    while Azure, the portal and Az PowerShell create peerings with false. @batchSize(1) and the
//    explicit dependsOn are genuine sequencing no symbolic reference expresses: the VNet IDs are
//    built by name, so ARM would not otherwise wait for the VNets and subnets above, and a peering
//    must not overlap another operation on the same VNet.
@batchSize(1)
module modPeering 'br/public:avm/res/network/virtual-network/virtual-network-peering:0.2.0' = [
  for peering in varPeerings: {
    name: '${peering.name}-peering-deployment'
    scope: resourceGroup(peering.resourceGroupName)
    params: {
      name: peering.name
      localVnetName: peering.localVnetName
      remoteVirtualNetworkResourceId: peering.remoteVnetId
      allowVirtualNetworkAccess: true
      allowForwardedTraffic: true
      allowGatewayTransit: false
      useRemoteGateways: false
      doNotVerifyRemoteGateways: false
    }
    dependsOn: [
      modVnetHub
      modVnetDev
      modVnetProd
      modSubnetHub
      modSubnetDev
      modSubnetProd
    ]
  }
]

// 4. Public IPs reserved for the Lab 2.3 load balancers: Standard SKU, static, zone-redundant
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

output outHubVnetId string = varVnetIdHub
output outDevVnetId string = varVnetIdDev
output outProdVnetId string = varVnetIdProd
