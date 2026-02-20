/*=====================================================
SUMMARY: Lab 4.3 - Azure Files - Orchestrator
DESCRIPTION: Orchestrates deployment of storage resources for Lab 4.3.
             Targets the Production environment to demonstrate GRS and File Shares.
EXAMPLE: az deployment sub create --location swedencentral --template-file main.bicep
AUTHOR/S: SkyCraft
VERSION: 1.1.0
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

/*******************
*    Variables     *
*******************/
var varResourceGroupName = '${parEnvironment}-skycraft-swc-rg'
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

module modStorage 'modules/storage.bicep' = {
  name: 'deploy-storage-azure-files'
  scope: resRg
  params: {
    parLocation: parLocation
    parEnvironment: parEnvironment
    parTags: varCommonTags
  }
}

/******************
*     Outputs     *
******************/
output outStorageAccountName string = modStorage.outputs.outStorageAccountName
output outStorageAccountId string = modStorage.outputs.outStorageAccountId
