/*=====================================================
SUMMARY: Lab 2.3 - DNS and Load Balancing
DESCRIPTION: Deploys the Dev/Prod Standard Load Balancers, the public DNS zone with its records and the private DNS zone with its VNet links via AVM (requires the Lab 2.1 virtual networks and public IPs to exist)
EXAMPLE: az deployment sub create --name Lab-2.3-DNS --location swedencentral --template-file main.bicep
AUTHOR/S: Marcin Biszczanik
VERSION: 0.2.0
DEPLOYMENT: .\scripts\Deploy-Bicep.ps1
======================================================*/

targetScope = 'subscription'

/*******************
*    Parameters    *
*******************/

@description('Location for the load balancers (DNS zones are global)')
@allowed([
  'swedencentral'
  'northeurope'
])
param parLocation string = 'swedencentral'

@description('Resource owner tag value')
@minLength(1)
param parOwner string = 'mbiszczanik'

@description('Name of the Private DNS Zone')
@minLength(1)
param parPrivateDnsZoneName string = 'skycraft.internal'

@description('Name of the Public DNS Zone')
@minLength(1)
param parPublicDnsZoneName string = 'skycraft.example.com'

@description('Platform (Hub) Resource Group Name - hosts both DNS zones')
@minLength(1)
@maxLength(90)
param parPlatformRG string = 'platform-skycraft-swc-rg'

@description('Development Resource Group Name')
@minLength(1)
@maxLength(90)
param parDevRG string = 'dev-skycraft-swc-rg'

@description('Production Resource Group Name')
@minLength(1)
@maxLength(90)
param parProdRG string = 'prod-skycraft-swc-rg'

@description('Hub VNet Name')
@minLength(2)
@maxLength(64)
param parHubVnetName string = 'platform-skycraft-swc-vnet'

@description('Dev VNet Name')
@minLength(2)
@maxLength(64)
param parDevVnetName string = 'dev-skycraft-swc-vnet'

@description('Prod VNet Name')
@minLength(2)
@maxLength(64)
param parProdVnetName string = 'prod-skycraft-swc-vnet'

@description('Dev Load Balancer Public IP name (created in Lab 2.1)')
@minLength(1)
@maxLength(80)
param parDevLbPipName string = 'dev-skycraft-swc-lb-pip'

@description('Prod Load Balancer Public IP name (created in Lab 2.1)')
@minLength(1)
@maxLength(80)
param parProdLbPipName string = 'prod-skycraft-swc-lb-pip'

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

var varLbNameDev = 'dev-skycraft-swc-lb'
var varLbNameProd = 'prod-skycraft-swc-lb'

// Game server ports: 3724 = authentication (realm list), 8085 = world
var varAuthPort = 3724
var varWorldPort = 8085
var varProbeIntervalInSeconds = 15
var varProbeCount = 2

// Placeholder database records (VMs auto-register their own names in Module 3)
var varDevDbIp = '10.1.3.10'
var varProdDbIp = '10.2.3.10'
var varTtlARecord = 300
var varTtlCname = 3600

/*******************
*    Resources     *
*******************/

resource resPlatformRG 'Microsoft.Resources/resourceGroups@2023-07-01' existing = {
  name: parPlatformRG
}

resource resDevRG 'Microsoft.Resources/resourceGroups@2023-07-01' existing = {
  name: parDevRG
}

resource resProdRG 'Microsoft.Resources/resourceGroups@2023-07-01' existing = {
  name: parProdRG
}

// VNets created in Lab 2.1 - linked to the private DNS zone
resource resVnetHub 'Microsoft.Network/virtualNetworks@2023-11-01' existing = {
  name: parHubVnetName
  scope: resPlatformRG
}

resource resVnetDev 'Microsoft.Network/virtualNetworks@2023-11-01' existing = {
  name: parDevVnetName
  scope: resDevRG
}

resource resVnetProd 'Microsoft.Network/virtualNetworks@2023-11-01' existing = {
  name: parProdVnetName
  scope: resProdRG
}

/*******************
*     Modules      *
*******************/

// 1. Public IP address lookups - local fallback for a trivial 'existing' lookup
//    (docs/bicep-standards.md, Section 4.3). Only the address needs a runtime lookup (DNS A
//    records); the LB frontends reference the PIPs by resourceId() so what-if stays static.
//    The IPs themselves are owned by Lab 2.1.
module modDevPip 'modules/get-public-ip.bicep' = {
  name: 'get-dev-pip'
  scope: resDevRG
  params: {
    parPublicIpName: parDevLbPipName
  }
}

module modProdPip 'modules/get-public-ip.bicep' = {
  name: 'get-prod-pip'
  scope: resProdRG
  params: {
    parPublicIpName: parProdLbPipName
  }
}

// 2. Load balancers (Standard SKU, regional). Frontends use the Lab 2.1 public IPs; the
//    backend pools stay empty until Module 3 adds the VM NICs (Lab 3.2 references '-be-auth').
//    disableOutboundSnat is set explicitly: the AVM default (true) would remove the implicit
//    outbound SNAT through the frontend IP that the Module 3 VMs rely on.
module modDevLb 'br/public:avm/res/network/load-balancer:0.8.0' = {
  name: 'deploy-dev-lb'
  scope: resDevRG
  params: {
    name: varLbNameDev
    location: parLocation
    tags: varTagsDev
    skuName: 'Standard'
    skuTier: 'Regional'
    frontendIPConfigurations: [
      {
        name: '${varLbNameDev}-frontend'
        publicIPAddressResourceId: resourceId(parDevRG, 'Microsoft.Network/publicIPAddresses', parDevLbPipName)
      }
    ]
    backendAddressPools: [
      {
        name: '${varLbNameDev}-be-world'
      }
      {
        name: '${varLbNameDev}-be-auth'
      }
    ]
    probes: [
      {
        name: '${varLbNameDev}-probe-world'
        protocol: 'Tcp'
        port: varWorldPort
        intervalInSeconds: varProbeIntervalInSeconds
        numberOfProbes: varProbeCount
      }
      {
        name: '${varLbNameDev}-probe-auth'
        protocol: 'Tcp'
        port: varAuthPort
        intervalInSeconds: varProbeIntervalInSeconds
        numberOfProbes: varProbeCount
      }
    ]
    loadBalancingRules: [
      {
        name: '${varLbNameDev}-rule-world'
        frontendIPConfigurationName: '${varLbNameDev}-frontend'
        backendAddressPoolName: '${varLbNameDev}-be-world'
        probeName: '${varLbNameDev}-probe-world'
        protocol: 'Tcp'
        frontendPort: varWorldPort
        backendPort: varWorldPort
        idleTimeoutInMinutes: 4
        enableTcpReset: true
        disableOutboundSnat: false
        loadDistribution: 'Default'
      }
      {
        name: '${varLbNameDev}-rule-auth'
        frontendIPConfigurationName: '${varLbNameDev}-frontend'
        backendAddressPoolName: '${varLbNameDev}-be-auth'
        probeName: '${varLbNameDev}-probe-auth'
        protocol: 'Tcp'
        frontendPort: varAuthPort
        backendPort: varAuthPort
        idleTimeoutInMinutes: 4
        enableTcpReset: true
        disableOutboundSnat: false
        loadDistribution: 'Default'
      }
    ]
  }
}

module modProdLb 'br/public:avm/res/network/load-balancer:0.8.0' = {
  name: 'deploy-prod-lb'
  scope: resProdRG
  params: {
    name: varLbNameProd
    location: parLocation
    tags: varTagsProd
    skuName: 'Standard'
    skuTier: 'Regional'
    frontendIPConfigurations: [
      {
        name: '${varLbNameProd}-frontend'
        publicIPAddressResourceId: resourceId(parProdRG, 'Microsoft.Network/publicIPAddresses', parProdLbPipName)
      }
    ]
    backendAddressPools: [
      {
        name: '${varLbNameProd}-be-world'
      }
      {
        name: '${varLbNameProd}-be-auth'
      }
    ]
    probes: [
      {
        name: '${varLbNameProd}-probe-world'
        protocol: 'Tcp'
        port: varWorldPort
        intervalInSeconds: varProbeIntervalInSeconds
        numberOfProbes: varProbeCount
      }
      {
        name: '${varLbNameProd}-probe-auth'
        protocol: 'Tcp'
        port: varAuthPort
        intervalInSeconds: varProbeIntervalInSeconds
        numberOfProbes: varProbeCount
      }
    ]
    loadBalancingRules: [
      {
        name: '${varLbNameProd}-rule-world'
        frontendIPConfigurationName: '${varLbNameProd}-frontend'
        backendAddressPoolName: '${varLbNameProd}-be-world'
        probeName: '${varLbNameProd}-probe-world'
        protocol: 'Tcp'
        frontendPort: varWorldPort
        backendPort: varWorldPort
        idleTimeoutInMinutes: 4
        enableTcpReset: true
        disableOutboundSnat: false
        loadDistribution: 'Default'
      }
      {
        name: '${varLbNameProd}-rule-auth'
        frontendIPConfigurationName: '${varLbNameProd}-frontend'
        backendAddressPoolName: '${varLbNameProd}-be-auth'
        probeName: '${varLbNameProd}-probe-auth'
        protocol: 'Tcp'
        frontendPort: varAuthPort
        backendPort: varAuthPort
        idleTimeoutInMinutes: 4
        enableTcpReset: true
        disableOutboundSnat: false
        loadDistribution: 'Default'
      }
    ]
  }
}

// 3. Public DNS zone: 'dev' and 'play' A records point at the load balancer public IPs,
//    'game' is a CNAME alias of 'play'. The zone is a placeholder (not delegated).
module modPublicDns 'br/public:avm/res/network/dns-zone:0.6.2' = {
  name: 'deploy-public-dns'
  scope: resPlatformRG
  params: {
    name: parPublicDnsZoneName
    tags: varTagsPlatform
    a: [
      {
        name: 'dev'
        ttl: varTtlARecord
        aRecords: [
          {
            ipv4Address: modDevPip.outputs.outIpAddress
          }
        ]
      }
      {
        name: 'play'
        ttl: varTtlARecord
        aRecords: [
          {
            ipv4Address: modProdPip.outputs.outIpAddress
          }
        ]
      }
    ]
    cname: [
      {
        name: 'game'
        ttl: varTtlCname
        cnameRecord: {
          cname: 'play.${parPublicDnsZoneName}'
        }
      }
    ]
  }
}

// 4. Private DNS zone linked to all three VNets - auto-registration on the spokes only
//    (shared hub services are static) - with placeholder database records.
module modPrivateDns 'br/public:avm/res/network/private-dns-zone:0.8.1' = {
  name: 'deploy-private-dns'
  scope: resPlatformRG
  params: {
    name: parPrivateDnsZoneName
    tags: varTagsPlatform
    virtualNetworkLinks: [
      {
        name: 'hub-vnet-link'
        virtualNetworkResourceId: resVnetHub.id
        registrationEnabled: false
      }
      {
        name: 'dev-vnet-link'
        virtualNetworkResourceId: resVnetDev.id
        registrationEnabled: true
      }
      {
        name: 'prod-vnet-link'
        virtualNetworkResourceId: resVnetProd.id
        registrationEnabled: true
      }
    ]
    a: [
      {
        name: 'dev-db'
        ttl: varTtlARecord
        aRecords: [
          {
            ipv4Address: varDevDbIp
          }
        ]
      }
      {
        name: 'prod-db'
        ttl: varTtlARecord
        aRecords: [
          {
            ipv4Address: varProdDbIp
          }
        ]
      }
    ]
  }
}

/******************
*     Outputs     *
******************/

output outPublicDnsZoneId string = modPublicDns.outputs.resourceId
output outPublicDnsNameServers array = modPublicDns.outputs.nameServers
output outPrivateDnsZoneId string = modPrivateDns.outputs.resourceId
output outDevLbId string = modDevLb.outputs.resourceId
output outProdLbId string = modProdLb.outputs.resourceId
