/*=====================================================
SUMMARY: Lab 2.2 - Spoke Security Module
DESCRIPTION: Deploys ASGs, NSGs for Auth/World/DB and associates them to subnets. Generic for Dev/Prod.
AUTHOR/S: Marcin Biszczanik
VERSION: 0.1.0
DEPLOYMENT: Internal Module
=====================================================*/

// ===================================
// Parameters
// ===================================

@description('Location for resources')
param parLocation string

@description('Name of the existing Spoke VNet')
param parVnetName string

@description('Environment tag value (Development or Production)')
@allowed([
  'Development'
  'Production'
])
param parEnvironment string

@description('Address CIDR for Auth Subnet')
param parAuthSubnetCidr string

@description('Address CIDR for World Subnet')
param parWorldSubnetCidr string

@description('Address CIDR for Database Subnet')
param parDbSubnetCidr string

@description('Source CIDR for MySQL rule (App Tier range)')
param parAppTierCidr string

// ===================================
// Variables
// ===================================

var varCommonTags = {
  Project: 'SkyCraft'
  Environment: parEnvironment
  CostCenter: 'MSDN'
}

// Prefix based on environment for naming resources
var varPrefix = toLower(parEnvironment) == 'development' ? 'dev' : 'prod'

var varAsgAuthName = '${varPrefix}-skycraft-swc-asg-auth'
var varAsgWorldName = '${varPrefix}-skycraft-swc-asg-world'
var varAsgDbName = '${varPrefix}-skycraft-swc-asg-db'

var varNsgAuthName = '${varPrefix}-skycraft-swc-auth-nsg'
var varNsgWorldName = '${varPrefix}-skycraft-swc-world-nsg'
var varNsgDbName = '${varPrefix}-skycraft-swc-db-nsg'

// ===================================
// Resources
// ===================================

// --- Application Security Groups ---

resource resAsgAuth 'Microsoft.Network/applicationSecurityGroups@2023-11-01' = {
  name: varAsgAuthName
  location: parLocation
  tags: varCommonTags
}

resource resAsgWorld 'Microsoft.Network/applicationSecurityGroups@2023-11-01' = {
  name: varAsgWorldName
  location: parLocation
  tags: varCommonTags
}

resource resAsgDb 'Microsoft.Network/applicationSecurityGroups@2023-11-01' = {
  name: varAsgDbName
  location: parLocation
  tags: varCommonTags
}

// --- Network Security Groups ---

// 1. Auth NSG
resource resNsgAuth 'Microsoft.Network/networkSecurityGroups@2023-11-01' = {
  name: varNsgAuthName
  location: parLocation
  tags: varCommonTags
  properties: {
    securityRules: [
      {
        name: 'Allow-SSH-From-Bastion'
        properties: {
          description: 'Allow SSH access from Azure Bastion subnet'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '22'
          sourceAddressPrefix: '10.0.0.0/26' // Creating a param for this is optional but good practice if Platform VNet changes. Hardcoded for now per lab guide.
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 100
          direction: 'Inbound'
        }
      }
      {
        name: 'Allow-Auth-GamePort'
        properties: {
          description: 'Allow game authentication traffic (port 3724)'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '3724'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 110
          direction: 'Inbound'
        }
      }
    ]
  }
}

// 2. World NSG
resource resNsgWorld 'Microsoft.Network/networkSecurityGroups@2023-11-01' = {
  name: varNsgWorldName
  location: parLocation
  tags: varCommonTags
  properties: {
    securityRules: [
      {
        name: 'Allow-SSH-From-Bastion'
        properties: {
          description: 'Allow SSH access from Azure Bastion subnet'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '22'
          sourceAddressPrefix: '10.0.0.0/26'
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 100
          direction: 'Inbound'
        }
      }
      {
        name: 'Allow-World-GamePort'
        properties: {
          description: 'Allow world server connections (port 8085)'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '8085'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 110
          direction: 'Inbound'
        }
      }
    ]
  }
}

// 3. Database NSG
resource resNsgDb 'Microsoft.Network/networkSecurityGroups@2023-11-01' = {
  name: varNsgDbName
  location: parLocation
  tags: varCommonTags
  properties: {
    securityRules: [
      {
        name: 'Allow-SSH-From-Bastion'
        properties: {
          description: 'Allow SSH access from Azure Bastion subnet'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '22'
          sourceAddressPrefix: '10.0.0.0/26'
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 100
          direction: 'Inbound'
        }
      }
      {
        name: 'Allow-MySQL-From-AppTier'
        properties: {
          description: 'Allow MySQL from Auth and World servers'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '3306'
          sourceAddressPrefix: parAppTierCidr
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 110
          direction: 'Inbound'
        }
      }
    ]
  }
}

// --- Subnet Associations ---

resource resVnet 'Microsoft.Network/virtualNetworks@2023-11-01' existing = {
  name: parVnetName
}

resource resSubnetAuth 'Microsoft.Network/virtualNetworks/subnets@2023-11-01' = {
  parent: resVnet
  name: 'AuthSubnet'
  properties: {
    addressPrefix: parAuthSubnetCidr
    networkSecurityGroup: {
      id: resNsgAuth.id
    }
  }
}

resource resSubnetWorld 'Microsoft.Network/virtualNetworks/subnets@2023-11-01' = {
  parent: resVnet
  name: 'WorldSubnet'
  dependsOn: [
    resSubnetAuth
  ]
  properties: {
    addressPrefix: parWorldSubnetCidr
    networkSecurityGroup: {
      id: resNsgWorld.id
    }
  }
}

resource resSubnetDb 'Microsoft.Network/virtualNetworks/subnets@2023-11-01' = {
  parent: resVnet
  name: 'DatabaseSubnet'
  dependsOn: [
    resSubnetWorld
  ]
  properties: {
    addressPrefix: parDbSubnetCidr
    networkSecurityGroup: {
      id: resNsgDb.id
    }
    serviceEndpoints: [
      {
        service: 'Microsoft.Sql'
        locations: [
          parLocation
        ]
      }
      {
        service: 'Microsoft.Storage'
        locations: [
          parLocation
        ]
      }
    ]
  }
}

// ===================================
// Outputs
// ===================================

output outNsgAuthId string = resNsgAuth.id
output outNsgWorldId string = resNsgWorld.id
output outNsgDbId string = resNsgDb.id
output outAsgAuthId string = resAsgAuth.id
output outAsgWorldId string = resAsgWorld.id
output outAsgDbId string = resAsgDb.id
