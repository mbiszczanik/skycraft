/*=====================================================
SUMMARY: Lab 4.2 - Implement Azure Blob Storage
DESCRIPTION: Orchestrates deployment for Lab 4.2, configuring containers,
             lifecycle policies, and public access settings.
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
@allowed(['swedencentral', 'northeurope'])
param parLocation string = 'swedencentral'

@description('Owner e-mail address for the canonical Owner governance tag')
param parOwnerEmail string = 'admin@skycraft.com'

/*******************
*    Variables     *
*******************/
var varProdRgName = 'prod-skycraft-swc-rg'
var varDevRgName = 'dev-skycraft-swc-rg'

var varCommonTags = {
  Project: 'SkyCraft'
  CostCenter: 'MSDN'
  Owner: parOwnerEmail
}

// Production Containers (Private)
var varProdContainers = [
  { name: 'game-assets', publicAccess: 'None' }
  { name: 'player-backups', publicAccess: 'None' }
  { name: 'server-config', publicAccess: 'None' }
  { name: 'game-logs', publicAccess: 'None' }
]

// Lifecycle Rules (Production Only)
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
          tierToArchive: { daysAfterModificationGreaterThan: 180 }
          delete: { daysAfterModificationGreaterThan: 365 }
        }
      }
      filters: {
        blobTypes: [ 'blockBlob' ]
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
          tierToArchive: { daysAfterModificationGreaterThan: 7 }
        }
      }
      filters: {
        blobTypes: [ 'blockBlob' ]
        prefixMatch: [ 'player-backups/' ]
      }
    }
  }
]

/*******************
*    Resources     *
*******************/

resource resProdRg 'Microsoft.Resources/resourceGroups@2023-07-01' existing = {
  name: varProdRgName
}

resource resDevRg 'Microsoft.Resources/resourceGroups@2023-07-01' existing = {
  name: varDevRgName
}

// Production Storage: Private, Versioning, Lifecycle Rules
module modStorageProd '../../4.1-storage-accounts/bicep/modules/storageAccount.bicep' = {
  name: 'deploy-storage-prod-4.2'
  scope: resProdRg
  params: {
    parLocation: parLocation
    parEnvironment: 'prod'
    parTags: union(varCommonTags, { Environment: 'Production' })
    parAllowBlobPublicAccess: false
    parEnableVersioning: true
    parContainers: varProdContainers
    parLifecycleRules: varLifecycleRules
    parIsNewDeployment: false // Update existing account
    parEnableInfrastructureEncryption: false // Don't change existing
  }
}

// Development Storage: private access (allowBlobPublicAccess blocked at subscription level).
module modStorageDev '../../4.1-storage-accounts/bicep/modules/storageAccount.bicep' = {
  name: 'deploy-storage-dev-4.2'
  scope: resDevRg
  params: {
    parLocation: parLocation
    parEnvironment: 'dev'
    parTags: union(varCommonTags, { Environment: 'Development' })
    parAllowBlobPublicAccess: false
    parEnableVersioning: false
    parContainers: []
    parLifecycleRules: []
    parIsNewDeployment: false // Update existing
    parEnableInfrastructureEncryption: false
  }
}

// Public-demo container — created as private (allowBlobPublicAccess blocked at subscription level).
module modDevPublicContainer 'modules/blobContainer.bicep' = {
  name: 'deploy-dev-public-container-4.2'
  scope: resDevRg
  params: {
    parStorageAccountName: modStorageDev.outputs.outStorageAccountName
    parContainerName: 'public-demo'
    parPublicAccess: 'None'
  }
}

/******************
*     Outputs     *
******************/
output outProdStorageId string = modStorageProd.outputs.outStorageAccountId
output outDevStorageId string = modStorageDev.outputs.outStorageAccountId
