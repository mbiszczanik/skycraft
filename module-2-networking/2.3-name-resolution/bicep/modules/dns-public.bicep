/*=====================================================
SUMMARY: Public DNS Zone Module
DESCRIPTION: Deploys a Public DNS Zone and A/CNAME records.
AUTHOR/S: Marcin Biszczanik
VERSION: 0.1.0
DEPLOYMENT: Internal Module
=====================================================*/

// ===================================
// Parameters
// ===================================

@description('The name of the Public DNS Zone (e.g., skycraft.example.com).')
param parDnsZoneName string

@description('The tags for the DNS Zone.')
param parTags object = {}

@description('The Public IP address of the Dev Load Balancer.')
param parDevLbPublicIp string

@description('The Public IP address of the Prod Load Balancer.')
param parProdLbPublicIp string

// ===================================
// Resources
// ===================================

resource resDnsZone 'Microsoft.Network/dnsZones@2018-05-01' = {
  name: parDnsZoneName
  location: 'global'
  tags: parTags
}

resource resRecordDev 'Microsoft.Network/dnsZones/A@2018-05-01' = {
  parent: resDnsZone
  name: 'dev'
  properties: {
    TTL: 300
    ARecords: [
      {
        ipv4Address: parDevLbPublicIp
      }
    ]
  }
}

resource resRecordPlay 'Microsoft.Network/dnsZones/A@2018-05-01' = {
  parent: resDnsZone
  name: 'play'
  properties: {
    TTL: 300
    ARecords: [
      {
        ipv4Address: parProdLbPublicIp
      }
    ]
  }
}

resource resRecordGame 'Microsoft.Network/dnsZones/CNAME@2018-05-01' = {
  parent: resDnsZone
  name: 'game'
  properties: {
    TTL: 3600
    CNAMERecord: {
      cname: 'play.${parDnsZoneName}'
    }
  }
}

// ===================================
// Outputs
// ===================================

output outDnsZoneId string = resDnsZone.id
output outNameServers array = resDnsZone.properties.nameServers
