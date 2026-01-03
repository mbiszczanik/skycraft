/*=====================================================
SUMMARY: Lab 2.2 - Security Configuration (NSG/ASG)
DESCRIPTION: Orchestrates the deployment of NSGs, ASGs, and Bastion across Hub and Spoke.
EXAMPLE: az deployment sub create --location swedencentral --template-file main.bicep
AUTHOR/S: Marcin Biszczanik
VERSION: 0.2.0
DEPLOYMENT: az deployment sub create
======================================================*/

targetScope = 'subscription'

/*******************
*    Parameters    *
*******************/
@description('Location for all resources')
param parLocation string = 'swedencentral'

@description('Production Resource Group Name')
param parResourceGroupNameProd string = 'prod-skycraft-swc-rg'

@description('Platform Resource Group Name')
param parResourceGroupNamePlatform string = 'platform-skycraft-swc-rg'

@description('Production VNet Name')
param parVnetNameProd string = 'prod-skycraft-swc-vnet'

@description('Platform VNet Name')
param parVnetNamePlatform string = 'platform-skycraft-swc-vnet'

@description('Deploy Azure Bastion (incurs ~$140/month cost)')
param parDeployBastion bool = false

/*******************
*    Resources     *
*******************/

// Deploy Production Security Resources (ASGs, NSG)
module modSecurityProd 'modules/security-prod.bicep' = {
  name: 'security-prod-deployment'
  scope: resourceGroup(parResourceGroupNameProd)
  params: {
    parLocation: parLocation
    parVnetName: parVnetNameProd
  }
}

// Deploy Platform Security Resources (NSG, Bastion)
module modSecurityPlatform 'modules/security-platform.bicep' = {
  name: 'security-platform-deployment'
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
output outProdNsgId string = modSecurityProd.outputs.outNsgId
output outPlatformNsgId string = modSecurityPlatform.outputs.outNsgId
output outBastionId string = modSecurityPlatform.outputs.outBastionId
