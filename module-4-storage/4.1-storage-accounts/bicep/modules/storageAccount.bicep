/*=====================================================
SUMMARY: Storage Account Module
DESCRIPTION: Deploys a storage account with environment-specific redundancy,
             security settings, and data protection. Follows AZ-104 best practices.
             Supports both new deployments (with full encryption settings) and
             updates to existing storage accounts.
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

@description('Enable blob soft delete')
param parEnableBlobSoftDelete bool = true

@description('Blob soft delete retention days')
@minValue(1)
@maxValue(365)
param parBlobSoftDeleteDays int = 7

@description('Enable container soft delete')
param parEnableContainerSoftDelete bool = true

@description('Container soft delete retention days')
@minValue(1)
@maxValue(365)
param parContainerSoftDeleteDays int = 7

@description('Enable file share soft delete')
param parEnableFileSoftDelete bool = true

@description('File share soft delete retention days')
@minValue(1)
@maxValue(365)
param parFileSoftDeleteDays int = 7

@description('Allow public network access')
@allowed(['Enabled', 'Disabled'])
param parPublicNetworkAccess string = 'Enabled'

@description('Set to true for new deployments to enable creation-only properties (keyType, infrastructureEncryption). Set to false when updating existing storage accounts.')
param parIsNewDeployment bool = true

@description('Enable infrastructure (double) encryption. Only applies to new deployments. Cannot be changed after creation.')
param parEnableInfrastructureEncryption bool = false

@description('Allow Blob public access. Required for AZ-104 labs (Dev), disabled for Prod.')
param parAllowBlobPublicAccess bool = false

@description('Enable blob versioning')
param parEnableVersioning bool = false

@description('List of containers to create')
param parContainers array = []

@description('List of lifecycle management rules')
param parLifecycleRules array = []

/*******************
*    Variables     *
*******************/
// Storage account names must be lowercase, 3-24 chars, no hyphens
var varStorageAccountName = '${parEnvironment}skycraftswcsa'

// Select redundancy based on environment
// Production: GRS (geo-redundancy for player data, enables archive tier)
// Platform: GRS (geo-redundancy for shared services)
// Development: LRS (cost optimization, data can be recreated)
var varRedundancy = parEnvironment == 'prod' ? 'Standard_GRS' : parEnvironment == 'platform' ? 'Standard_GRS' : 'Standard_LRS'

// Encryption configuration for NEW deployments (includes keyType and infrastructure encryption)
var varEncryptionNew = {
  keySource: 'Microsoft.Storage'
  services: {
    blob: {
      enabled: true
      keyType: 'Account'
    }
    file: {
      enabled: true
      keyType: 'Account'
    }
    table: {
      enabled: true
      keyType: 'Account'
    }
    queue: {
      enabled: true
      keyType: 'Account'
    }
  }
  requireInfrastructureEncryption: parEnableInfrastructureEncryption
}

// Encryption configuration for UPDATES to existing accounts (excludes read-only properties)
var varEncryptionUpdate = {
  keySource: 'Microsoft.Storage'
  services: {
    blob: {
      enabled: true
    }
    file: {
      enabled: true
    }
    table: {
      enabled: true
    }
    queue: {
      enabled: true
    }
  }
}

/*******************
*    Resources     *
*******************/

@description('Storage account for SkyCraft environment')
resource resStorageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: varStorageAccountName
  location: parLocation
  tags: parTags
  sku: {
    name: varRedundancy
  }
  kind: 'StorageV2'
  properties: {
    // Access tier
    accessTier: 'Hot'
    
    // Security settings (AZ-104 best practices)
    allowBlobPublicAccess: parAllowBlobPublicAccess
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
    allowSharedKeyAccess: true
    
    // Network access (will be restricted in Lab 4.4)
    publicNetworkAccess: parPublicNetworkAccess
    networkAcls: {
      defaultAction: 'Allow'
      bypass: 'AzureServices'
    }
    
    // Encryption at rest (Microsoft-managed keys)
    // Use full encryption config for new deployments, limited config for updates
    encryption: parIsNewDeployment ? varEncryptionNew : varEncryptionUpdate
  }
}

// Blob service configuration with soft delete
resource resBlobServices 'Microsoft.Storage/storageAccounts/blobServices@2023-01-01' = {
  parent: resStorageAccount
  name: 'default'
  properties: {
    deleteRetentionPolicy: {
      enabled: parEnableBlobSoftDelete
      days: parBlobSoftDeleteDays
    }
    containerDeleteRetentionPolicy: {
      enabled: parEnableContainerSoftDelete
      days: parContainerSoftDeleteDays
    }
    // Versioning and change feed will be enabled in Lab 4.2
    isVersioningEnabled: parEnableVersioning
    changeFeed: {
      enabled: false
    }
  }
}

// File service configuration with soft delete
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

// Containers
resource resContainers 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = [for container in parContainers: {
  parent: resBlobServices
  name: container.name
  properties: {
    publicAccess: contains(container, 'publicAccess') ? container.publicAccess : 'None'
  }
}]

// Lifecycle Management Policy
resource resManagementPolicy 'Microsoft.Storage/storageAccounts/managementPolicies@2023-01-01' = if (!empty(parLifecycleRules)) {
  parent: resStorageAccount
  name: 'default'
  properties: {
    policy: {
      rules: parLifecycleRules
    }
  }
}
/******************
*     Outputs     *
******************/
@description('Name of the storage account')
output outStorageAccountName string = resStorageAccount.name

@description('Resource ID of the storage account')
output outStorageAccountId string = resStorageAccount.id

@description('Primary blob endpoint')
output outPrimaryBlobEndpoint string = resStorageAccount.properties.primaryEndpoints.blob

@description('Primary file endpoint')
output outPrimaryFileEndpoint string = resStorageAccount.properties.primaryEndpoints.file

@description('Storage account SKU (redundancy)')
output outSku string = resStorageAccount.sku.name

@description('Storage account location')
output outLocation string = resStorageAccount.location

@description('Indicates if this was a new deployment with full encryption settings')
output outIsNewDeployment bool = parIsNewDeployment
