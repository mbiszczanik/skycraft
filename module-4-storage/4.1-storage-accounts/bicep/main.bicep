/*=====================================================
SUMMARY: Lab 4.1 - Storage Accounts - Orchestrator
DESCRIPTION: Orchestrates deployment of storage accounts for SkyCraft across
             platform, development, and production environments. Supports
             single environment or all environments deployment.
EXAMPLE: 
  Single environment: az deployment sub create --location swedencentral --template-file main.bicep --parameters parEnvironment=dev
  All environments: az deployment sub create --location swedencentral --template-file main.bicep --parameters parDeployAllEnvironments=true
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

@description('Environment to deploy: dev, prod, platform. Ignored if parDeployAllEnvironments is true.')
@allowed(['dev', 'prod', 'platform'])
param parEnvironment string = 'dev'

@description('Deploy storage accounts to all environments (platform, dev, prod)')
param parDeployAllEnvironments bool = false

@description('Enable blob soft delete')
param parEnableBlobSoftDelete bool = true

@description('Blob soft delete retention days')
param parBlobSoftDeleteDays int = 7

@description('Enable container soft delete')
param parEnableContainerSoftDelete bool = true

@description('Enable file share soft delete')
param parEnableFileSoftDelete bool = true

@description('Set to true for new deployments (applies keyType and infrastructureEncryption). Set to false when updating existing storage accounts.')
param parIsNewDeployment bool = true

@description('Enable infrastructure (double) encryption for new deployments. Cannot be changed after creation.')
param parEnableInfrastructureEncryption bool = false

/*******************
*    Variables     *
*******************/
// Environment configurations
var varEnvironments = parDeployAllEnvironments ? ['platform', 'dev', 'prod'] : [parEnvironment]

// Tag configurations per environment
var varTagConfigs = {
  platform: {
    Project: 'SkyCraft'
    Environment: 'Platform'
    CostCenter: 'MSDN'
  }
  dev: {
    Project: 'SkyCraft'
    Environment: 'Development'
    CostCenter: 'MSDN'
  }
  prod: {
    Project: 'SkyCraft'
    Environment: 'Production'
    CostCenter: 'MSDN'
  }
}

/*******************
*    Resources     *
*******************/

// Reference existing resource groups
resource resPlatformRg 'Microsoft.Resources/resourceGroups@2023-07-01' existing = if (contains(varEnvironments, 'platform')) {
  name: 'platform-skycraft-swc-rg'
}

resource resDevRg 'Microsoft.Resources/resourceGroups@2023-07-01' existing = if (contains(varEnvironments, 'dev')) {
  name: 'dev-skycraft-swc-rg'
}

resource resProdRg 'Microsoft.Resources/resourceGroups@2023-07-01' existing = if (contains(varEnvironments, 'prod')) {
  name: 'prod-skycraft-swc-rg'
}

/*******************
*    Modules       *
*******************/

// Platform storage account (GRS)
module modStorageAccountPlatform 'modules/storageAccount.bicep' = if (contains(varEnvironments, 'platform')) {
  name: 'deploy-storage-account-platform'
  scope: resPlatformRg
  params: {
    parLocation: parLocation
    parEnvironment: 'platform'
    parTags: varTagConfigs.platform
    parEnableBlobSoftDelete: parEnableBlobSoftDelete
    parBlobSoftDeleteDays: parBlobSoftDeleteDays
    parEnableContainerSoftDelete: parEnableContainerSoftDelete
    parEnableFileSoftDelete: parEnableFileSoftDelete
    parIsNewDeployment: parIsNewDeployment
    parEnableInfrastructureEncryption: parEnableInfrastructureEncryption
  }
}

// Development storage account (LRS)
module modStorageAccountDev 'modules/storageAccount.bicep' = if (contains(varEnvironments, 'dev')) {
  name: 'deploy-storage-account-dev'
  scope: resDevRg
  params: {
    parLocation: parLocation
    parEnvironment: 'dev'
    parTags: varTagConfigs.dev
    parEnableBlobSoftDelete: parEnableBlobSoftDelete
    parBlobSoftDeleteDays: parBlobSoftDeleteDays
    parEnableContainerSoftDelete: parEnableContainerSoftDelete
    parEnableFileSoftDelete: parEnableFileSoftDelete
    parIsNewDeployment: parIsNewDeployment
    parEnableInfrastructureEncryption: parEnableInfrastructureEncryption
  }
}

// Production storage account (GRS)
module modStorageAccountProd 'modules/storageAccount.bicep' = if (contains(varEnvironments, 'prod')) {
  name: 'deploy-storage-account-prod'
  scope: resProdRg
  params: {
    parLocation: parLocation
    parEnvironment: 'prod'
    parTags: varTagConfigs.prod
    parEnableBlobSoftDelete: parEnableBlobSoftDelete
    parBlobSoftDeleteDays: parBlobSoftDeleteDays
    parEnableContainerSoftDelete: parEnableContainerSoftDelete
    parEnableFileSoftDelete: parEnableFileSoftDelete
    parIsNewDeployment: parIsNewDeployment
    parEnableInfrastructureEncryption: parEnableInfrastructureEncryption
  }
}

/******************
*     Outputs     *
******************/
@description('Platform storage account name (if deployed)')
output outPlatformStorageAccountName string = modStorageAccountPlatform.?outputs.outStorageAccountName ?? 'not-deployed'

@description('Development storage account name (if deployed)')
output outDevStorageAccountName string = modStorageAccountDev.?outputs.outStorageAccountName ?? 'not-deployed'

@description('Production storage account name (if deployed)')
output outProdStorageAccountName string = modStorageAccountProd.?outputs.outStorageAccountName ?? 'not-deployed'

@description('Deployed environments')
output outDeployedEnvironments array = varEnvironments

@description('Deployment summary')
output outDeploymentSummary object = {
  location: parLocation
  environments: varEnvironments
  softDeleteEnabled: parEnableBlobSoftDelete
  softDeleteDays: parBlobSoftDeleteDays
}
