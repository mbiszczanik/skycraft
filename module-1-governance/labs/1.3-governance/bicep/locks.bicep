/*=====================================================
SUMMARY: Lab 1.3 - Resource Locks
DESCRIPTION: This template applies CanNotDelete locks to resource groups
EXAMPLE:
AUTHOR/S: Marcin Biszczanik
VERSION: 0.1.0
======================================================*/

@description('Name of the production resource group')
param parProdResourceGroupName string = 'prod-skycraft-swc-rg'

@description('Name of the shared resource group')
param parPlatformResourceGroupName string = 'platform-skycraft-swc-rg'

// Lock for production resource group
resource resProdLock 'Microsoft.Authorization/locks@2020-05-01' = {
  name: 'lock-no-delete-prod'
  properties: {
    level: 'CanNotDelete'
    notes: 'Prevents accidental deletion of production resources'
  }
}

// Lock for shared resource group
resource resPlatformLock 'Microsoft.Authorization/locks@2020-05-01' = {
  name: 'lock-no-delete-platform'
  properties: {
    level: 'CanNotDelete'
    notes: 'Protects platform monitoring and logging infrastructure'
  }
}

// Outputs
output locks array = [
  {
    name: resProdLock.name
    level: resProdLock.properties.level
  }
  {
    name: resPlatformLock.name
    level: resPlatformLock.properties.level
  }
]
