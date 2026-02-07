/*=====================================================
SUMMARY: Module 4.3 - Azure Files - Storage Module
DESCRIPTION: Deploys a Storage Account with File Service properties
             optimized for Azure Files laboratory.
AUTHOR/S: SkyCraft
VERSION: 1.1.0
DEPLOYMENT: [Internal use via Orchestrator]
======================================================*/

/*******************
*    Parameters    *
*******************/
@description('Location for resources')
param parLocation string

@description('Environment: dev, prod, platform')
@allowed(['dev', 'prod', 'platform'])
param parEnvironment string

@description('Tags to apply to resources')
param parTags object

@description('Enable file share soft delete')
param parEnableFileSoftDelete bool = true

@description('File share soft delete retention days')
@minValue(1)
@maxValue(365)
param parFileSoftDeleteDays int = 14

/*******************
*    Variables     *
*******************/
// Hungarian notation for variables (var)
var varStorageAccountName = '${parEnvironment}skycraftswcsa'

// Redundancy selection (GRS for Prod/Platform, LRS for Dev)
var varSkuName = (parEnvironment == 'prod' || parEnvironment == 'platform') ? 'Standard_GRS' : 'Standard_LRS'

/*******************
*    Resources     *
*******************/

// Hungarian notation for resources (res)
resource resStorageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: varStorageAccountName
  location: parLocation
  tags: parTags
  sku: {
    name: varSkuName
  }
  kind: 'StorageV2'
  properties: {
    accessTier: 'Hot'
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
    allowBlobPublicAccess: false
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: 'Allow'
    }
  }
}

resource resFileServices 'Microsoft.Storage/storageAccounts/fileServices@2023-01-01' = {
  parent: resStorageAccount
  name: 'default'
  properties: {
    shareDeleteRetentionPolicy: {
      enabled: parEnableFileSoftDelete
      days: parFileSoftDeleteDays
    }
  }
}

/******************
*     Outputs     *
******************/
output outStorageAccountId string = resStorageAccount.id
output outStorageAccountName string = resStorageAccount.name
output outStorageSku string = resStorageAccount.sku.name
