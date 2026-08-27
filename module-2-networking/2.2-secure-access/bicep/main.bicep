/*=====================================================
SUMMARY: Lab 2.2 - Secure Access (NSG/ASG/Bastion)
DESCRIPTION: Deploys the Dev/Prod ASGs and NSGs, attaches the NSGs (and service endpoints) to the spoke subnets, and deploys the Hub NSG and the optional Azure Bastion via AVM (requires the Lab 2.1 virtual networks to exist)
EXAMPLE: az deployment sub create --location swedencentral --template-file main.bicep
AUTHOR/S: Marcin Biszczanik
VERSION: 0.3.0
DEPLOYMENT: .\scripts\Deploy-Bicep.ps1
======================================================*/

targetScope = 'subscription'

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

@description('Development Resource Group Name')
@minLength(1)
@maxLength(90)
param parResourceGroupNameDev string = 'dev-skycraft-swc-rg'

@description('Production Resource Group Name')
@minLength(1)
@maxLength(90)
param parResourceGroupNameProd string = 'prod-skycraft-swc-rg'

@description('Platform Resource Group Name')
@minLength(1)
@maxLength(90)
param parResourceGroupNamePlatform string = 'platform-skycraft-swc-rg'

@description('Development VNet Name')
@minLength(2)
@maxLength(64)
param parVnetNameDev string = 'dev-skycraft-swc-vnet'

@description('Production VNet Name')
@minLength(2)
@maxLength(64)
param parVnetNameProd string = 'prod-skycraft-swc-vnet'

@description('Platform VNet Name')
@minLength(2)
@maxLength(64)
param parVnetNamePlatform string = 'platform-skycraft-swc-vnet'

@description('Deploy Azure Bastion (Basic SKU, incurs ~$140/month cost)')
param parDeployBastion bool = false

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

// AzureBastionSubnet of the hub (Lab 2.1). Intentionally fixed - the NSG rules are explicit
// about their trusted source (ARCHITECTURE.md, "NSG rule specificity").
var varBastionSubnetCidr = '10.0.0.0/26'

var varNsgNameHub = 'platform-skycraft-swc-nsg'
var varBastionName = 'platform-skycraft-swc-bas'
var varBastionPipName = 'platform-skycraft-swc-bas-pip'

// One entry per spoke; every spoke-scoped module below loops over this list.
// Index 0 = dev, index 1 = prod (the outputs rely on this order).
var varSpokes = [
  {
    prefix: 'dev'
    resourceGroupName: parResourceGroupNameDev
    vnetName: parVnetNameDev
    tags: varTagsDev
    authSubnetCidr: '10.1.1.0/24'
    worldSubnetCidr: '10.1.2.0/24'
    dbSubnetCidr: '10.1.3.0/24'
  }
  {
    prefix: 'prod'
    resourceGroupName: parResourceGroupNameProd
    vnetName: parVnetNameProd
    tags: varTagsProd
    authSubnetCidr: '10.2.1.0/24'
    worldSubnetCidr: '10.2.2.0/24'
    dbSubnetCidr: '10.2.3.0/24'
  }
]

/*******************
*    Resources     *
*******************/

resource resRgPlatform 'Microsoft.Resources/resourceGroups@2023-07-01' existing = {
  name: parResourceGroupNamePlatform
}

// Hub VNet created in Lab 2.1 - Bastion attaches to its AzureBastionSubnet
resource resVnetHub 'Microsoft.Network/virtualNetworks@2023-11-01' existing = {
  name: parVnetNamePlatform
  scope: resRgPlatform
}

/*******************
*     Modules      *
*******************/

// --- Application Security Groups (logical tiers; Module 3 adds the VM NICs) ---

module modAsgAuth 'br/public:avm/res/network/application-security-group:0.2.2' = [for spoke in varSpokes: {
  name: '${spoke.prefix}-asg-auth-deployment'
  scope: resourceGroup(spoke.resourceGroupName)
  params: {
    name: '${spoke.prefix}-skycraft-swc-asg-auth'
    location: parLocation
    tags: spoke.tags
  }
}]

module modAsgWorld 'br/public:avm/res/network/application-security-group:0.2.2' = [for spoke in varSpokes: {
  name: '${spoke.prefix}-asg-world-deployment'
  scope: resourceGroup(spoke.resourceGroupName)
  params: {
    name: '${spoke.prefix}-skycraft-swc-asg-world'
    location: parLocation
    tags: spoke.tags
  }
}]

module modAsgDb 'br/public:avm/res/network/application-security-group:0.2.2' = [for spoke in varSpokes: {
  name: '${spoke.prefix}-asg-db-deployment'
  scope: resourceGroup(spoke.resourceGroupName)
  params: {
    name: '${spoke.prefix}-skycraft-swc-asg-db'
    location: parLocation
    tags: spoke.tags
  }
}]

// --- Network Security Groups (one per spoke subnet tier) ---

module modNsgAuth 'br/public:avm/res/network/network-security-group:0.5.3' = [for spoke in varSpokes: {
  name: '${spoke.prefix}-nsg-auth-deployment'
  scope: resourceGroup(spoke.resourceGroupName)
  params: {
    name: '${spoke.prefix}-skycraft-swc-auth-nsg'
    location: parLocation
    tags: spoke.tags
    securityRules: [
      {
        name: 'Allow-SSH-From-Bastion'
        properties: {
          description: 'Allow SSH access from Azure Bastion subnet'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '22'
          sourceAddressPrefix: varBastionSubnetCidr
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
}]

module modNsgWorld 'br/public:avm/res/network/network-security-group:0.5.3' = [for spoke in varSpokes: {
  name: '${spoke.prefix}-nsg-world-deployment'
  scope: resourceGroup(spoke.resourceGroupName)
  params: {
    name: '${spoke.prefix}-skycraft-swc-world-nsg'
    location: parLocation
    tags: spoke.tags
    securityRules: [
      {
        name: 'Allow-SSH-From-Bastion'
        properties: {
          description: 'Allow SSH access from Azure Bastion subnet'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '22'
          sourceAddressPrefix: varBastionSubnetCidr
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
}]

module modNsgDb 'br/public:avm/res/network/network-security-group:0.5.3' = [for spoke in varSpokes: {
  name: '${spoke.prefix}-nsg-db-deployment'
  scope: resourceGroup(spoke.resourceGroupName)
  params: {
    name: '${spoke.prefix}-skycraft-swc-db-nsg'
    location: parLocation
    tags: spoke.tags
    securityRules: [
      {
        name: 'Allow-SSH-From-Bastion'
        properties: {
          description: 'Allow SSH access from Azure Bastion subnet'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '22'
          sourceAddressPrefix: varBastionSubnetCidr
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
          sourceAddressPrefixes: [
            spoke.authSubnetCidr
            spoke.worldSubnetCidr
          ]
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 110
          direction: 'Inbound'
        }
      }
    ]
  }
}]

// --- Subnet associations: the AVM subnet child module re-declares each spoke subnet with
//     its NSG (and service endpoints). Subnet updates on the same VNet must not overlap
//     (AnotherOperationInProgress), so the three loops are chained with explicit dependsOn -
//     no symbolic reference expresses this ordering. ---

module modSubnetAuth 'br/public:avm/res/network/virtual-network/subnet:0.2.0' = [for (spoke, i) in varSpokes: {
  name: '${spoke.prefix}-subnet-auth-deployment'
  scope: resourceGroup(spoke.resourceGroupName)
  params: {
    name: 'AuthSubnet'
    virtualNetworkName: spoke.vnetName
    addressPrefix: spoke.authSubnetCidr
    networkSecurityGroupResourceId: modNsgAuth[i].outputs.resourceId
  }
}]

module modSubnetWorld 'br/public:avm/res/network/virtual-network/subnet:0.2.0' = [for (spoke, i) in varSpokes: {
  name: '${spoke.prefix}-subnet-world-deployment'
  scope: resourceGroup(spoke.resourceGroupName)
  params: {
    name: 'WorldSubnet'
    virtualNetworkName: spoke.vnetName
    addressPrefix: spoke.worldSubnetCidr
    networkSecurityGroupResourceId: modNsgWorld[i].outputs.resourceId
    // Storage service endpoint so Lab 4.4 can add WorldSubnet to the storage account's
    // network ACL. This lab is the final authority on the spoke subnets, so the endpoint
    // lives here, not in Lab 2.1.
    serviceEndpoints: [
      'Microsoft.Storage'
    ]
  }
  dependsOn: [
    modSubnetAuth[i] // serialise subnet updates per VNet (see comment above)
  ]
}]

module modSubnetDb 'br/public:avm/res/network/virtual-network/subnet:0.2.0' = [for (spoke, i) in varSpokes: {
  name: '${spoke.prefix}-subnet-db-deployment'
  scope: resourceGroup(spoke.resourceGroupName)
  params: {
    name: 'DatabaseSubnet'
    virtualNetworkName: spoke.vnetName
    addressPrefix: spoke.dbSubnetCidr
    networkSecurityGroupResourceId: modNsgDb[i].outputs.resourceId
    serviceEndpoints: [
      'Microsoft.Sql'
      'Microsoft.Storage'
    ]
  }
  dependsOn: [
    modSubnetWorld[i] // serialise subnet updates per VNet (see comment above)
  ]
}]

// --- Hub NSG: empty allow-list on purpose (NSGs are default-deny for inbound internet traffic) ---

module modNsgHub 'br/public:avm/res/network/network-security-group:0.5.3' = {
  name: 'hub-nsg-deployment'
  scope: resRgPlatform
  params: {
    name: varNsgNameHub
    location: parLocation
    tags: varTagsPlatform
    securityRules: []
  }
}

// --- Azure Bastion (optional, Basic SKU). The AVM module creates the Standard static
//     Public IP itself from publicIPAddressObject; the PIP name is the one
//     Remove-LabResource.ps1 deletes. ---

module modBastion 'br/public:avm/res/network/bastion-host:0.8.2' = if (parDeployBastion) {
  name: 'hub-bastion-deployment'
  scope: resRgPlatform
  params: {
    name: varBastionName
    location: parLocation
    tags: varTagsPlatform
    skuName: 'Basic'
    virtualNetworkResourceId: resVnetHub.id
    publicIPAddressObject: {
      name: varBastionPipName
      skuName: 'Standard'
      publicIPAllocationMethod: 'Static'
      tags: varTagsPlatform
    }
  }
}

/******************
*     Outputs     *
******************/

output outProdNsgAuthId string = modNsgAuth[1].outputs.resourceId // varSpokes[1] = prod
output outPlatformNsgId string = modNsgHub.outputs.resourceId
output outBastionId string = modBastion.?outputs.resourceId ?? ''
