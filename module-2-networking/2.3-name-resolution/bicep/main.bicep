/*=====================================================
SUMMARY: Lab 2.3 - Name Resolution (Private DNS)
DESCRIPTION: Orchestrates the deployment of a Private DNS Zone and VNet links.
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
param parDnsZoneName string = 'skycraft.internal'

@description('The resource group for platform resources (Hub).')
param parPlatformRG string = 'platform-skycraft-swc-rg'

@description('The resource group for production resources (Spoke).')
param parProdRG string = 'prod-skycraft-swc-rg'

@description('The Hub VNet name.')
param parHubVnetName string = 'platform-skycraft-swc-vnet'

@description('The Spoke VNet name.')
param parSpokeVnetName string = 'prod-skycraft-swc-vnet'

// ===================================
// Variables
// ===================================

var varCommonTags = {
  Project: 'SkyCraft'
  Environment: 'Production'
  CostCenter: 'MSDN'
}

// ===================================
// Resources
// ===================================

resource resPlatformRG 'Microsoft.Resources/resourceGroups@2023-07-01' existing = {
  name: parPlatformRG
}

resource resProdRG 'Microsoft.Resources/resourceGroups@2023-07-01' existing = {
  name: parProdRG
}

// Deploy DNS Zone and Links in the Platform RG
module modDnsZone 'modules/dns-zone.bicep' = {
  name: 'deploy-dns-zone'
  scope: resPlatformRG
  params: {
    parDnsZoneName: parDnsZoneName
    parLocation: 'global'
    parTags: varCommonTags
    parHubVnetId: resourceId(parPlatformRG, 'Microsoft.Network/virtualNetworks', parHubVnetName)
    parSpokeVnetId: resourceId(parProdRG, 'Microsoft.Network/virtualNetworks', parSpokeVnetName)
  }
}

// ===================================
// Outputs
// ===================================

output outDnsZoneId string = modDnsZone.outputs.outDnsZoneId
