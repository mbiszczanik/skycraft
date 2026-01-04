/*=====================================================
SUMMARY: Lab 2.2 - Production Security Modules
DESCRIPTION: Deploys ASGs, NSG and associates them to subnets.
AUTHOR/S: Marcin Biszczanik
VERSION: 0.1.0
======================================================*/

/*******************
*    Parameters    *
*******************/
@description('Location for resources')
param parLocation string

@description('Name of the production VNet')
param parVnetName string

@description('Environment tag value')
param parEnvironment string = 'Production'

/*******************
*    Variables     *
*******************/
var varCommonTags = {
  Project: 'SkyCraft'
  Environment: parEnvironment
  CostCenter: 'MSDN'
}

var varNsgName = 'prod-skycraft-swc-nsg'
var varAsgAuthName = 'prod-skycraft-swc-asg-auth'
var varAsgWorldName = 'prod-skycraft-swc-asg-world'
var varAsgDbName = 'prod-skycraft-swc-asg-db'

/*******************
*    Resources     *
*******************/

// Application Security Groups
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

// Network Security Group
resource resNsgProd 'Microsoft.Network/networkSecurityGroups@2023-11-01' = {
  name: varNsgName
  location: parLocation
  tags: varCommonTags
  properties: {
    securityRules: [
      {
        name: 'AllowAuthServer'
        properties: {
          description: 'Allow traffic to Auth Server ASG'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '3724'
          sourceAddressPrefix: '*'
          destinationApplicationSecurityGroups: [
            {
              id: resAsgAuth.id
            }
          ]
          access: 'Allow'
          priority: 1000
          direction: 'Inbound'
        }
      }
      {
        name: 'AllowWorldServer'
        properties: {
          description: 'Allow traffic to World Server ASG'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '8085'
          sourceAddressPrefix: '*'
          destinationApplicationSecurityGroups: [
            {
              id: resAsgWorld.id
            }
          ]
          access: 'Allow'
          priority: 1100
          direction: 'Inbound'
        }
      }
      {
        name: 'AllowAppToDB'
        properties: {
          description: 'Allow Auth and World ASGs to talk to DB ASG'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '3306'
          sourceApplicationSecurityGroups: [
            {
              id: resAsgAuth.id
            }
            {
              id: resAsgWorld.id
            }
          ]
          destinationApplicationSecurityGroups: [
            {
              id: resAsgDb.id
            }
          ]
          access: 'Allow'
          priority: 2000
          direction: 'Inbound'
        }
      }
    ]
  }
}

// Subnet Associations
resource resVnet 'Microsoft.Network/virtualNetworks@2023-11-01' existing = {
  name: parVnetName
}

resource resSubnetAuth 'Microsoft.Network/virtualNetworks/subnets@2023-11-01' = {
  parent: resVnet
  name: 'AuthSubnet'
  properties: {
    addressPrefix: '10.1.1.0/24'
    networkSecurityGroup: {
      id: resNsgProd.id
    }
  }
}

resource resSubnetWorld 'Microsoft.Network/virtualNetworks/subnets@2023-11-01' = {
  parent: resVnet
  name: 'WorldSubnet'
  properties: {
    addressPrefix: '10.1.2.0/24'
    networkSecurityGroup: {
      id: resNsgProd.id
    }
  }
}

resource resSubnetDb 'Microsoft.Network/virtualNetworks/subnets@2023-11-01' = {
  parent: resVnet
  name: 'DatabaseSubnet'
  properties: {
    addressPrefix: '10.1.3.0/24'
    networkSecurityGroup: {
      id: resNsgProd.id
    }
  }
}

/******************
*     Outputs     *
******************/
output outNsgId string = resNsgProd.id
output outAsgAuthId string = resAsgAuth.id
output outAsgWorldId string = resAsgWorld.id
output outAsgDbId string = resAsgDb.id
