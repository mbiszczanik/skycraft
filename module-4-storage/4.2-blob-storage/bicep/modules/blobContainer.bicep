/*=====================================================
SUMMARY: Blob Container Module
DESCRIPTION: Creates a single blob container on an existing storage account.
             Split out from the storage-account module so the container can be
             created in a SEPARATE deployment that depends on the account's
             allowBlobPublicAccess flag — this avoids the PublicAccessNotPermitted
             race where a 'Blob' container is created before the account-level
             public-access toggle has propagated to the data plane.
AUTHOR/S: SkyCraft
VERSION: 1.0.0
DEPLOYMENT: [Internal use via Orchestrator]
======================================================*/

/*******************
*    Parameters    *
*******************/
@description('Name of the existing storage account')
param parStorageAccountName string

@description('Container name to create')
param parContainerName string

@description('Public access level for the container')
@allowed(['None', 'Blob', 'Container'])
param parPublicAccess string = 'None'

/*******************
*    Resources     *
*******************/
resource resStorageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' existing = {
  name: parStorageAccountName
}

resource resBlobService 'Microsoft.Storage/storageAccounts/blobServices@2023-01-01' existing = {
  parent: resStorageAccount
  name: 'default'
}

resource resContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = {
  parent: resBlobService
  name: parContainerName
  properties: {
    publicAccess: parPublicAccess
  }
}

/******************
*     Outputs     *
******************/
output outContainerName string = resContainer.name
