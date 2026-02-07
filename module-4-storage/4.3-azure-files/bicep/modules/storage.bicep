/*=====================================================
SUMMARY: Module 4.3 - Storage Module
DESCRIPTION: Deploys Storage Account and File Shares for Azure Files lab
AUTHOR/S: SkyCraft
VERSION: 1.0.0
DEPLOYMENT: [Internal use via Orchestrator]
======================================================*/

/*******************
*    Parameters    *
*******************/
@description('Location for resources')
param parLocation string

@description('Environment tag value')
param parEnvironment string = 'Production'

@description('Storage Account Name (Global Unique)')
param parStorageAccountName string

/*******************
*    Variables     *
*******************/
var varCommonTags = {
  Project: 'SkyCraft'
  Environment: parEnvironment
  CostCenter: 'MSDN'
}

/*******************
*    Resources     *
*******************/

resource resStorage 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: parStorageAccountName
  location: parLocation
  tags: varCommonTags
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    accessTier: 'Hot'
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: 'Allow'
    }
  }
}

resource resFileServices 'Microsoft.Storage/storageAccounts/fileServices@2023-01-01' = {
  parent: resStorage
  name: 'default'
  properties: {
    shareDeleteRetentionPolicy: {
      enabled: true
      days: 14
    }
  }
}

// File Shares are created manually in the lab, but we can define them here for reference or idempotency if needed.
// For this lab, the student creates them manually. 
// However, the orchestrator might need to deploy the storage account first.

/******************
*     Outputs     *
******************/
output outStorageAccountId string = resStorage.id
output outStorageAccountName string = resStorage.name
