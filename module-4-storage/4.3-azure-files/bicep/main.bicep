/*=====================================================
SUMMARY: Lab 4.3 - Azure Files - Orchestrator
DESCRIPTION: Configures the file service on a SkyCraft storage account via the Azure Verified Module for storage accounts - raises share soft delete to 14 days and creates the two SkyCraft file shares. Targets Production by default to demonstrate GRS.
EXAMPLE: .\scripts\Deploy-Bicep.ps1 -Environment prod
AUTHOR/S: Marcin Biszczanik
VERSION: 2.0.0
DEPLOYMENT: .\scripts\Deploy-Bicep.ps1
======================================================*/

targetScope = 'subscription'

/*******************
*    Parameters    *
*******************/

@description('Location for all resources')
@allowed(['swedencentral', 'northeurope'])
param parLocation string = 'swedencentral'

@description('Target environment')
@allowed(['dev', 'prod', 'platform'])
param parEnvironment string = 'prod'

@description('Resource owner tag value')
@minLength(1)
param parOwner string = 'mbiszczanik'

@description('File share soft delete retention days')
@minValue(1)
@maxValue(365)
param parFileSoftDeleteDays int = 14

@description('Quota in GiB for the skycraft-config share')
@minValue(1)
@maxValue(102400)
param parConfigShareQuotaGiB int = 100

@description('Quota in GiB for the skycraft-shared share')
@minValue(1)
@maxValue(102400)
param parSharedShareQuotaGiB int = 500

/*******************
*    Variables     *
*******************/

var varEnvironmentTags = {
  dev: 'Development'
  prod: 'Production'
  platform: 'Platform'
}

var varCommonTags = {
  Project: 'SkyCraft'
  Environment: varEnvironmentTags[parEnvironment]
  CostCenter: 'MSDN'
  Owner: parOwner
}

var varSkuNames = {
  platform: 'Standard_GRS'
  dev: 'Standard_LRS'
  prod: 'Standard_GRS'
}

/*******************
*     Modules      *
*******************/

// blobServices is passed empty on purpose: an empty value makes AVM skip the blob service
// deployment entirely, so the containers, versioning and lifecycle rules Lab 4.2 configured
// survive this deployment untouched. This lab owns the file service only.
module modStorage 'br/public:avm/res/storage/storage-account:0.33.0' = {
  name: 'sa-deployment-files'
  scope: resourceGroup('${parEnvironment}-skycraft-swc-rg')
  params: {
    name: '${parEnvironment}skycraftswcsa'
    location: parLocation
    tags: varCommonTags
    skuName: varSkuNames[parEnvironment]
    kind: 'StorageV2'
    accessTier: 'Hot'
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
    allowBlobPublicAccess: false
    allowSharedKeyAccess: true
    publicNetworkAccess: 'Enabled'
    requireInfrastructureEncryption: false
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: 'Allow'
    }
    blobServices: {}
    fileServices: {
      shareDeleteRetentionPolicy: {
        enabled: true
        days: parFileSoftDeleteDays
      }
      shares: [
        {
          name: 'skycraft-config'
          accessTier: 'Hot'
          shareQuota: parConfigShareQuotaGiB
        }
        {
          name: 'skycraft-shared'
          accessTier: 'Hot'
          shareQuota: parSharedShareQuotaGiB
        }
      ]
    }
  }
}

/******************
*     Outputs     *
******************/

@description('Name of the storage account hosting the file shares')
output outStorageAccountName string = modStorage.outputs.name

@description('Resource ID of the storage account')
output outStorageAccountId string = modStorage.outputs.resourceId

@description('Redundancy of the storage account')
output outStorageSku string = varSkuNames[parEnvironment]

@description('Primary file service endpoint')
output outPrimaryFileEndpoint string = modStorage.outputs.serviceEndpoints.file
