/*=====================================================
SUMMARY: Lab 2.2 - Security Configuration (NSG/ASG)
DESCRIPTION: Orchestrates the deployment of NSGs, ASGs, and Bastion across Hub and Spoke.
EXAMPLE: az deployment sub create --location swedencentral --template-file main.bicep
AUTHOR/S: Marcin Biszczanik
VERSION: 0.2.0
DEPLOYMENT: .\scripts\Deploy-Bicep.ps1
======================================================*/

targetScope = 'subscription'

/*******************
*    Parameters    *
*******************/
@description('Location for all resources')
param parLocation string = 'swedencentral'

@description('Development Resource Group Name')
param parResourceGroupNameDev string = 'dev-skycraft-swc-rg'

@description('Production Resource Group Name')
param parResourceGroupNameProd string = 'prod-skycraft-swc-rg'

@description('Platform Resource Group Name')
param parResourceGroupNamePlatform string = 'platform-skycraft-swc-rg'

@description('Development VNet Name')
param parVnetNameDev string = 'dev-skycraft-swc-vnet'

@description('Production VNet Name')
param parVnetNameProd string = 'prod-skycraft-swc-vnet'

@description('Platform VNet Name')
param parVnetNamePlatform string = 'platform-skycraft-swc-vnet'

@description('Deploy Azure Bastion (incurs ~$140/month cost)')
param parDeployBastion bool = false

/*******************
*    Resources     *
*******************/

// Deploy Development Security Resources (ASGs, NSGs)
module modSecurityDev 'modules/security-spoke.bicep' = {
  name: 'security-dev-deployment'
  scope: resourceGroup(parResourceGroupNameDev)
  params: {
    parLocation: parLocation
    parVnetName: parVnetNameDev
    parEnvironment: 'Development'
    parAuthSubnetCidr: '10.1.1.0/24'
    parWorldSubnetCidr: '10.1.2.0/24'
    parDbSubnetCidr: '10.1.3.0/24'
  }
}

// Deploy Production Security Resources (ASGs, NSGs)
module modSecurityProd 'modules/security-spoke.bicep' = {
  name: 'security-prod-deployment'
  scope: resourceGroup(parResourceGroupNameProd)
  params: {
    parLocation: parLocation
    parVnetName: parVnetNameProd
    parEnvironment: 'Production'
    parAuthSubnetCidr: '10.2.1.0/24'
    parWorldSubnetCidr: '10.2.2.0/24'
    parDbSubnetCidr: '10.2.3.0/24'
  }
}

// Deploy Platform Security Resources (NSG, Bastion)
module modSecurityHub 'modules/security-hub.bicep' = {
  name: 'security-hub-deployment'
  scope: resourceGroup(parResourceGroupNamePlatform)
  params: {
    parLocation: parLocation
    parVnetName: parVnetNamePlatform
    parDeployBastion: parDeployBastion
  }
}

/******************
*     Outputs     *
******************/
output outProdNsgAuthId string = modSecurityProd.outputs.outNsgAuthId
output outPlatformNsgId string = modSecurityHub.outputs.outNsgId
output outBastionId string = modSecurityHub.outputs.outBastionId
