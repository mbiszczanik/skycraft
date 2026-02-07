/*=====================================================
SUMMARY: Lab 4.3 - Orchestrator
DESCRIPTION: Orchestrates deployment for Lab 4.3 (Storage Account)
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

@description('Resource Group Name')
param parResourceGroupName string = 'prod-skycraft-swc-rg'

@description('Storage Account Name (Global Unique)')
param parStorageAccountName string = 'prodskycraftswcsa${uniqueString(subscription().id, parResourceGroupName)}'

/*******************
*    Resources     *
*******************/

resource resRg 'Microsoft.Resources/resourceGroups@2023-07-01' = {
  name: parResourceGroupName
  location: parLocation
  tags: {
    Project: 'SkyCraft'
    Environment: 'Production'
    CostCenter: 'MSDN'
  }
}

module modStorage 'modules/storage.bicep' = {
  name: 'deploy-storage'
  scope: resRg
  params: {
    parLocation: parLocation
    parStorageAccountName: parStorageAccountName
  }
}

/******************
*     Outputs     *
******************/
output outStorageAccountName string = modStorage.outputs.outStorageAccountName
