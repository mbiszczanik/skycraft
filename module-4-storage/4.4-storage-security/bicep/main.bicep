/*=====================================================
SUMMARY: Lab 4.4 - Storage Security - Orchestrator
DESCRIPTION: Orchestrates storage security configuration for Lab 4.4.
             References existing storage account and VNet, applies
             firewall rules and creates test container.
EXAMPLE: az deployment sub create --location swedencentral --template-file main.bicep
AUTHOR/S: SkyCraft
VERSION: 1.0.0
DEPLOYMENT: .\scripts\Deploy-Bicep.ps1
======================================================*/

targetScope = 'subscription'

/*******************
*    Parameters    *
*******************/
@description('Location for all resources')
param parLocation string = 'swedencentral'

@description('Environment tag value')
param parEnvironment string = 'prod'

@description('Client IP to allow through storage firewall (leave empty to skip)')
param parClientIp string = ''

/*******************
*    Variables     *
*******************/
var varResourceGroupName = '${parEnvironment}-skycraft-swc-rg'
var varStorageAccountName = '${parEnvironment}skycraftswcsa'
var varVnetName = '${parEnvironment}-skycraft-swc-vnet'
var varCommonTags = {
  Project: 'SkyCraft'
  Environment: parEnvironment == 'prod' ? 'Production' : (parEnvironment == 'dev' ? 'Development' : 'Platform')
  CostCenter: 'MSDN'
}

/*******************
*    Resources     *
*******************/

resource resRg 'Microsoft.Resources/resourceGroups@2023-07-01' existing = {
  name: varResourceGroupName
}

module modSecurity 'modules/security.bicep' = {
  name: 'deploy-storage-security'
  scope: resRg
  params: {
    parLocation: parLocation
    parTags: varCommonTags
    parStorageAccountName: varStorageAccountName
    parVnetName: varVnetName
    parSubnetName: 'WorldSubnet'
    parClientIp: parClientIp
  }
}

/******************
*     Outputs     *
******************/
output outStorageAccountId string = modSecurity.outputs.outStorageAccountId
output outContainerName string = modSecurity.outputs.outContainerName
output outFirewallDefaultAction string = modSecurity.outputs.outFirewallDefaultAction
