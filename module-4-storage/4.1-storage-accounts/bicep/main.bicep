/*=====================================================
SUMMARY: Lab 4.1 - Storage Accounts - Orchestrator
DESCRIPTION: Deploys the SkyCraft storage accounts (platform, development, production) via the Azure Verified Module for storage accounts, with environment-specific redundancy, the canonical tags and blob/file soft delete
EXAMPLE: .\scripts\Deploy-Bicep.ps1 -Environment dev
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

@description('Environment to deploy. Ignored when parDeployAllEnvironments is true.')
@allowed(['dev', 'prod', 'platform'])
param parEnvironment string = 'dev'

@description('Deploy storage accounts to all environments (platform, dev, prod)')
param parDeployAllEnvironments bool = false

@description('Resource owner tag value')
@minLength(1)
param parOwner string = 'mbiszczanik'

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

@description('Allow public network access to the storage accounts (Lab 4.4 restricts this)')
@allowed(['Enabled', 'Disabled'])
param parPublicNetworkAccess string = 'Enabled'

@description('Enable infrastructure (double) encryption. Creation-only - cannot be changed on an existing account.')
param parEnableInfrastructureEncryption bool = false

/*******************
*    Variables     *
*******************/

var varEnvironments = parDeployAllEnvironments ? ['platform', 'dev', 'prod'] : [parEnvironment]

// Canonical four tags per environment (docs/bicep-standards.md section 5)
var varTags = {
  platform: {
    Project: 'SkyCraft'
    Environment: 'Platform'
    CostCenter: 'MSDN'
    Owner: parOwner
  }
  dev: {
    Project: 'SkyCraft'
    Environment: 'Development'
    CostCenter: 'MSDN'
    Owner: parOwner
  }
  prod: {
    Project: 'SkyCraft'
    Environment: 'Production'
    CostCenter: 'MSDN'
    Owner: parOwner
  }
}

// Production and Platform hold data worth geo-replicating; Development is recreatable.
var varSkuNames = {
  platform: 'Standard_GRS'
  dev: 'Standard_LRS'
  prod: 'Standard_GRS'
}

/*******************
*     Modules      *
*******************/

module modStorageAccount 'br/public:avm/res/storage/storage-account:0.33.0' = [for env in varEnvironments: {
  name: 'sa-deployment-${env}'
  scope: resourceGroup('${env}-skycraft-swc-rg')
  params: {
    name: '${env}skycraftswcsa'
    location: parLocation
    tags: varTags[env]
    skuName: varSkuNames[env]
    kind: 'StorageV2'
    accessTier: 'Hot'
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
    allowBlobPublicAccess: false
    allowSharedKeyAccess: true
    publicNetworkAccess: parPublicNetworkAccess
    // Creation-only property; AVM defaults it to true while Azure's own default is false (standards section 4.5)
    requireInfrastructureEncryption: parEnableInfrastructureEncryption
    // AVM emits defaultAction 'Deny' when networkAcls is omitted; Lab 4.4 is the lab that locks the account (standards section 4.5)
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: 'Allow'
    }
    blobServices: {
      deleteRetentionPolicyEnabled: parEnableBlobSoftDelete
      deleteRetentionPolicyDays: parBlobSoftDeleteDays
      containerDeleteRetentionPolicyEnabled: parEnableContainerSoftDelete
      containerDeleteRetentionPolicyDays: parContainerSoftDeleteDays
      isVersioningEnabled: false
      changeFeedEnabled: false
    }
    fileServices: {
      shareDeleteRetentionPolicy: {
        enabled: parEnableFileSoftDelete
        days: parFileSoftDeleteDays
      }
    }
  }
}]

/******************
*     Outputs     *
******************/

@description('Platform storage account name (if deployed)')
output outPlatformStorageAccountName string = contains(varEnvironments, 'platform') ? modStorageAccount[indexOf(varEnvironments, 'platform')].outputs.name : 'not-deployed'

@description('Development storage account name (if deployed)')
output outDevStorageAccountName string = contains(varEnvironments, 'dev') ? modStorageAccount[indexOf(varEnvironments, 'dev')].outputs.name : 'not-deployed'

@description('Production storage account name (if deployed)')
output outProdStorageAccountName string = contains(varEnvironments, 'prod') ? modStorageAccount[indexOf(varEnvironments, 'prod')].outputs.name : 'not-deployed'

@description('Deployed environments')
output outDeployedEnvironments array = varEnvironments

@description('Deployment summary')
output outDeploymentSummary object = {
  location: parLocation
  environments: varEnvironments
  softDeleteEnabled: parEnableBlobSoftDelete
  softDeleteDays: parBlobSoftDeleteDays
}
