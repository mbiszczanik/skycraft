/*=====================================================
SUMMARY: Lab 2.2 - Platform Security Modules
DESCRIPTION: Deploys Hub NSG and Azure Bastion.
AUTHOR/S: Marcin Biszczanik
VERSION: 0.1.0
======================================================*/

/*******************
*    Parameters    *
*******************/
@description('Location for resources')
param parLocation string

@description('Name of the platform VNet')
param parVnetName string

@description('Environment tag value')
param parEnvironment string = 'Platform'

@description('Deploy Azure Bastion (incurs ~$140/month cost)')
param parDeployBastion bool = false

/*******************
*    Variables     *
*******************/
var varCommonTags = {
  Project: 'SkyCraft'
  Environment: parEnvironment
  CostCenter: 'MSDN'
}

var varNsgName = 'platform-skycraft-swc-nsg'
var varBastionName = 'platform-skycraft-swc-bas'
var varBastionPipName = 'platform-skycraft-swc-bas-pip'

/*******************
*    Resources     *
*******************/

// Hub NSG
resource resNsgHub 'Microsoft.Network/networkSecurityGroups@2023-09-01' = {
  name: varNsgName
  location: parLocation
  tags: varCommonTags
  properties: {
    securityRules: []
  }
}

// Bastion Public IP (conditional)
resource resBastionPip 'Microsoft.Network/publicIPAddresses@2023-09-01' = if (parDeployBastion) {
  name: varBastionPipName
  location: parLocation
  tags: varCommonTags
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}

// Existing VNet and Bastion Subnet
resource resVnetHub 'Microsoft.Network/virtualNetworks@2023-09-01' existing = {
  name: parVnetName
}

resource resSubnetBastion 'Microsoft.Network/virtualNetworks/subnets@2023-09-01' existing = {
  parent: resVnetHub
  name: 'AzureBastionSubnet'
}

// Bastion Host (conditional)
resource resBastionHost 'Microsoft.Network/bastionHosts@2023-09-01' = if (parDeployBastion) {
  name: varBastionName
  location: parLocation
  tags: varCommonTags
  sku: {
    name: 'Basic'
  }
  properties: {
    ipConfigurations: [
      {
        name: 'IpConf'
        properties: {
          subnet: {
            id: resSubnetBastion.id
          }
          publicIPAddress: {
            id: resBastionPip.id
          }
        }
      }
    ]
  }
}

/******************
*     Outputs     *
******************/
output outNsgId string = resNsgHub.id
output outBastionId string = parDeployBastion ? resBastionHost.id : ''
