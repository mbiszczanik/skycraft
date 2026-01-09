/*=====================================================
SUMMARY: Private DNS Zone Module
DESCRIPTION: Deploys a Private DNS Zone, VNet Links, and DB Records.
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

@description('The resource ID of the Dev VNet.')
param parDevVnetId string

@description('The resource ID of the Prod (Spoke) VNet.')
param parProdVnetId string

// ===================================
// Resources
// ===================================

resource resDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: parDnsZoneName
  location: parLocation
  tags: parTags
}

// Link to Hub VNet (Auto-Registration: Disabled)
resource resHubLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: resDnsZone
  name: 'link-to-hub'
  location: parLocation
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: parHubVnetId
    }
  }
}

// Link to Dev VNet (Auto-Registration: Enabled)
resource resDevLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: resDnsZone
  name: 'link-to-dev'
  location: parLocation
  properties: {
    registrationEnabled: true
    virtualNetwork: {
      id: parDevVnetId
    }
  }
}

// Link to Prod VNet (Auto-Registration: Enabled)
resource resProdLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: resDnsZone
  name: 'link-to-prod'
  location: parLocation
  properties: {
    registrationEnabled: true
    virtualNetwork: {
      id: parProdVnetId
    }
  }
}

// A Record for Dev Database (Placeholder)
resource resRecordDevDb 'Microsoft.Network/privateDnsZones/A@2020-06-01' = {
  parent: resDnsZone
  name: 'dev-db'
  properties: {
    ttl: 300
    aRecords: [
      {
        ipv4Address: '10.1.3.10'
      }
    ]
  }
}

// A Record for Prod Database (Placeholder)
resource resRecordProdDb 'Microsoft.Network/privateDnsZones/A@2020-06-01' = {
  parent: resDnsZone
  name: 'prod-db'
  properties: {
    ttl: 300
    aRecords: [
      {
        ipv4Address: '10.2.3.10'
      }
    ]
  }
}

// ===================================
// Outputs
// ===================================

output outDnsZoneId string = resDnsZone.id
