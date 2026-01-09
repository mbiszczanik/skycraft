/*=====================================================
SUMMARY: Lab 2.3 - DNS and Load Balancing
DESCRIPTION: Orchestrates the deployment of Public/Private DNS and Load Balancers.
EXAMPLE: az deployment sub create --name Lab-2.3-DNS --location swedencentral --template-file main.bicep
AUTHOR/S: Marcin Biszczanik
VERSION: 0.1.0
DEPLOYMENT: .\scripts\Deploy-Bicep.ps1
=====================================================*/

targetScope = 'subscription'

// ===================================
// Parameters
// ===================================

@description('The Azure region for the resource group metadata.')
param parLocation string = 'swedencentral'

@description('The name of the Private DNS Zone.')
param parPrivateDnsZoneName string = 'skycraft.internal'

@description('The name of the Public DNS Zone.')
param parPublicDnsZoneName string = 'skycraft.example.com'

@description('The resource group for platform resources (Hub).')
param parPlatformRG string = 'platform-skycraft-swc-rg'

@description('The resource group for development resources.')
param parDevRG string = 'dev-skycraft-swc-rg'

@description('The resource group for production resources.')
param parProdRG string = 'prod-skycraft-swc-rg'

@description('The Hub VNet name.')
param parHubVnetName string = 'platform-skycraft-swc-vnet'

@description('The Dev VNet name.')
param parDevVnetName string = 'dev-skycraft-swc-vnet'

@description('The Prod VNet name.')
param parProdVnetName string = 'prod-skycraft-swc-vnet'

@description('The Dev Load Balancer Public IP name.')
param parDevLbPipName string = 'dev-skycraft-swc-lb-pip'

@description('The Prod Load Balancer Public IP name.')
param parProdLbPipName string = 'prod-skycraft-swc-lb-pip'

// ===================================
// Variables
// ===================================

var varCommonTags = {
  Project: 'SkyCraft'
  Environment: 'Production'
  CostCenter: 'MSDN'
}

// ===================================
// Resources (Existing Lookups)
// ===================================

resource resPlatformRG 'Microsoft.Resources/resourceGroups@2023-07-01' existing = {
  name: parPlatformRG
}

resource resDevRG 'Microsoft.Resources/resourceGroups@2023-07-01' existing = {
  name: parDevRG
}

resource resProdRG 'Microsoft.Resources/resourceGroups@2023-07-01' existing = {
  name: parProdRG
}

// Public IP lookups are handled by individual modules below.

// Actually, easier way: Pass names to LB modules, let them lookup. 
// For DNS, pass names and RGs to a helper module or look them up here?
// 'existing' resource must be within a module if referencing different scope than targetScope (subscription).
// But we can switch scope for modules.

// Solution: Create a 'get-ip.bicep' helper or just use the fact that we can do recursive lookups?
// No, let's just deploy LBs first, then deploy Public DNS.

// ===================================
// Deploy Load Balancers
// ===================================

module modDevLb 'modules/load-balancer.bicep' = {
  name: 'deploy-dev-lb'
  scope: resDevRG
  params: {
    parLbName: 'dev-skycraft-swc-lb'
    parLocation: parLocation
    parTags: varCommonTags
    // We need the Public IP ID. 
    // We can't lookup resources in specific RGs from subscription level directly without nested modules.
    parPublicIpId: resourceId(parDevRG, 'Microsoft.Network/publicIPAddresses', parDevLbPipName)
  }
}

module modProdLb 'modules/load-balancer.bicep' = {
  name: 'deploy-prod-lb'
  scope: resProdRG
  params: {
    parLbName: 'prod-skycraft-swc-lb'
    parLocation: parLocation
    parTags: varCommonTags
    parPublicIpId: resourceId(parProdRG, 'Microsoft.Network/publicIPAddresses', parProdLbPipName)
  }
}

// ===================================
// Deploy Public DNS
// ===================================

// We need the IP Addresses for the A records.
// Bicep doesn't allow easy lookup of properties of existing resources in other RGs from subscription scope without a module.
// So we need a module that outputs the IP address of a pip.

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

module modPublicDns 'modules/dns-public.bicep' = {
  name: 'deploy-public-dns'
  scope: resPlatformRG
  params: {
    parDnsZoneName: parPublicDnsZoneName
    parTags: varCommonTags
    parDevLbPublicIp: modDevPip.outputs.outIpAddress
    parProdLbPublicIp: modProdPip.outputs.outIpAddress
  }
}

// ===================================
// Deploy Private DNS
// ===================================

module modPrivateDns 'modules/dns-private.bicep' = {
  name: 'deploy-private-dns'
  scope: resPlatformRG
  params: {
    parDnsZoneName: parPrivateDnsZoneName
    parLocation: 'global'
    parTags: varCommonTags
    parHubVnetId: resourceId(parPlatformRG, 'Microsoft.Network/virtualNetworks', parHubVnetName)
    parDevVnetId: resourceId(parDevRG, 'Microsoft.Network/virtualNetworks', parDevVnetName)
    parProdVnetId: resourceId(parProdRG, 'Microsoft.Network/virtualNetworks', parProdVnetName)
  }
}

// ===================================
// Outputs
// ===================================

output outPublicDnsZoneId string = modPublicDns.outputs.outDnsZoneId
output outPrivateDnsZoneId string = modPrivateDns.outputs.outDnsZoneId
