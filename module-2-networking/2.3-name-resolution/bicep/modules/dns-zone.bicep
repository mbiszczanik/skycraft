/*=====================================================
SUMMARY: Private DNS Zone Module
DESCRIPTION: Deploys a Private DNS Zone and multiple Virtual Network Links.
AUTHOR/S: Marcin Biszczanik
VERSION: 0.1.0
DEPLOYMENT: Internal Module
=====================================================*/

// ===================================
// Parameters
// ===================================

@description('The name of the Private DNS Zone.')
param parDnsZoneName string

@description('The location for the DNS Zone resource (must be global).')
param parLocation string = 'global'

@description('The tags for the DNS Zone.')
param parTags object = {}

@description('The resource ID of the Hub VNet.')
param parHubVnetId string

@description('The resource ID of the Spoke VNet.')
param parSpokeVnetId string

// ===================================
// Resources
// ===================================

resource resDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: parDnsZoneName
  location: parLocation
  tags: parTags
}

resource resHubLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: resDnsZone
  name: 'link-to-hub'
  location: parLocation
  properties: {
    registrationEnabled: true
    virtualNetwork: {
      id: parHubVnetId
    }
  }
}

resource resSpokeLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: resDnsZone
  name: 'link-to-prod'
  location: parLocation
  properties: {
    registrationEnabled: true
    virtualNetwork: {
      id: parSpokeVnetId
    }
  }
}

// ===================================
// Outputs
// ===================================

output outDnsZoneId string = resDnsZone.id
