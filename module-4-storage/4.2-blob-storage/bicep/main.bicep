/*=====================================================
SUMMARY: Lab 4.2 - Implement Azure Blob Storage
DESCRIPTION: Configures the production and development storage accounts from Lab 4.1 with containers, blob versioning and lifecycle management rules via the Azure Verified Module for storage accounts
EXAMPLE: .\scripts\Deploy-Bicep.ps1
AUTHOR/S: Marcin Biszczanik
VERSION: 2.2.0
DEPLOYMENT: .\scripts\Deploy-Bicep.ps1
======================================================*/

targetScope = 'subscription'

/*******************
*    Parameters    *
*******************/

@description('Location for all resources')
@allowed(['swedencentral', 'northeurope'])
param parLocation string = 'swedencentral'

@description('Resource owner tag value')
@minLength(1)
param parOwner string = 'mbiszczanik'

@description('Production resource group name')
@minLength(1)
@maxLength(90)
param parResourceGroupNameProd string = 'prod-skycraft-swc-rg'

@description('Development resource group name')
@minLength(1)
@maxLength(90)
param parResourceGroupNameDev string = 'dev-skycraft-swc-rg'

// Storage account names are unique across Azure: use the names Lab 4.1 deployed (#438).
@description('Production storage account name: 3-24 lowercase letters and digits')
@minLength(3)
@maxLength(24)
param parProdSaName string = 'prodskycraftswcsa'

@description('Development storage account name: 3-24 lowercase letters and digits')
@minLength(3)
@maxLength(24)
param parDevSaName string = 'devskycraftswcsa'

@description('Blob soft delete retention days (baseline from Lab 4.1)')
@minValue(1)
@maxValue(365)
param parBlobSoftDeleteDays int = 7

@description('Container soft delete retention days (baseline from Lab 4.1)')
@minValue(1)
@maxValue(365)
param parContainerSoftDeleteDays int = 7

/*******************
*    Variables     *
*******************/

var varTagsProd = {
  Project: 'SkyCraft'
  Environment: 'Production'
  CostCenter: 'MSDN'
  Owner: parOwner
}

var varTagsDev = {
  Project: 'SkyCraft'
  Environment: 'Development'
  CostCenter: 'MSDN'
  Owner: parOwner
}

// Production containers - all private
var varContainersProd = [
  { name: 'game-assets', publicAccess: 'None' }
  { name: 'player-backups', publicAccess: 'None' }
  { name: 'server-config', publicAccess: 'None' }
  { name: 'game-logs', publicAccess: 'None' }
]

// Development container - created private; the account keeps allowBlobPublicAccess false (guide Step 4.2.12)
var varContainersDev = [
  { name: 'public-demo', publicAccess: 'None' }
]

// Lifecycle management - production only. Each rule is limited to its own container by a prefix
// filter: without 'game-logs/', tier-game-logs would delete every block blob in the account after
// 365 days, game assets and player backups included (#356). Test-Lab.ps1 fails a rule without it.
// daysAfterLastTierChangeGreaterThan is the Portal's "Skip blobs that have been rehydrated in the
// last [7] days", ticked by default on an archive block, so all three paths write it.
var varLifecycleRules = [
  {
    enabled: true
    name: 'tier-game-logs'
    type: 'Lifecycle'
    definition: {
      actions: {
        baseBlob: {
          tierToCool: { daysAfterModificationGreaterThan: 30 }
          tierToCold: { daysAfterModificationGreaterThan: 90 }
          tierToArchive: { daysAfterModificationGreaterThan: 180, daysAfterLastTierChangeGreaterThan: 7 }
          delete: { daysAfterModificationGreaterThan: 365 }
        }
      }
      filters: {
        blobTypes: ['blockBlob']
        prefixMatch: ['game-logs/']
      }
    }
  }
  {
    enabled: true
    name: 'archive-backups'
    type: 'Lifecycle'
    definition: {
      actions: {
        baseBlob: {
          tierToArchive: { daysAfterModificationGreaterThan: 7, daysAfterLastTierChangeGreaterThan: 7 }
        }
      }
      filters: {
        blobTypes: ['blockBlob']
        prefixMatch: ['player-backups/']
      }
    }
  }
]

/*******************
*     Modules      *
*******************/

// Production: private containers, versioning and lifecycle tiering.
// fileServices is omitted deliberately - an empty value makes AVM skip the file service entirely,
// so Lab 4.1's (and later Lab 4.3's) file share configuration is left untouched.
module modStorageProd 'br/public:avm/res/storage/storage-account:0.33.0' = {
  name: 'sa-deployment-prod-42'
  scope: resourceGroup(parResourceGroupNameProd)
  params: {
    name: parProdSaName
    location: parLocation
    tags: varTagsProd
    skuName: 'Standard_GRS'
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
    blobServices: {
      deleteRetentionPolicyEnabled: true
      deleteRetentionPolicyDays: parBlobSoftDeleteDays
      containerDeleteRetentionPolicyEnabled: true
      containerDeleteRetentionPolicyDays: parContainerSoftDeleteDays
      isVersioningEnabled: true
      changeFeedEnabled: false
      containers: varContainersProd
    }
    managementPolicyRules: varLifecycleRules
  }
}

// Development: one demo container, no versioning, no lifecycle rules.
module modStorageDev 'br/public:avm/res/storage/storage-account:0.33.0' = {
  name: 'sa-deployment-dev-42'
  scope: resourceGroup(parResourceGroupNameDev)
  params: {
    name: parDevSaName
    location: parLocation
    tags: varTagsDev
    skuName: 'Standard_LRS'
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
    blobServices: {
      deleteRetentionPolicyEnabled: true
      deleteRetentionPolicyDays: parBlobSoftDeleteDays
      containerDeleteRetentionPolicyEnabled: true
      containerDeleteRetentionPolicyDays: parContainerSoftDeleteDays
      isVersioningEnabled: false
      changeFeedEnabled: false
      containers: varContainersDev
    }
  }
}

/******************
*     Outputs     *
******************/

@description('Resource ID of the production storage account')
output outProdStorageId string = modStorageProd.outputs.resourceId

@description('Resource ID of the development storage account')
output outDevStorageId string = modStorageDev.outputs.resourceId

@description('Production container names created by this lab')
output outProdContainerNames array = [for container in varContainersProd: container.name]
