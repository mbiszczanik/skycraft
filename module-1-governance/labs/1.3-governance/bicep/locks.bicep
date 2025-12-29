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

module modLockProd 'modules/rg-lock.bicep' = {
  name: 'lock-prod'
  scope: resourceGroup(parProdResourceGroupName)
  params: {
    parLockName: 'lock-no-delete-prod'
    parLockNotes: 'Prevents accidental deletion of production resources'
  }
}

module modLockPlatform 'modules/rg-lock.bicep' = {
  name: 'lock-platform'
  scope: resourceGroup(parPlatformResourceGroupName)
  params: {
    parLockName: 'lock-no-delete-platform'
    parLockNotes: 'Protects platform monitoring and logging infrastructure'
  }
}
