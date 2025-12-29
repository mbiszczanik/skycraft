/*
SUMMARY: Helper module to apply locks to a Resource Group
DESCRIPTION: Uses Microsoft.Authorization/locks to apply a CanNotDelete lock to the current Resource Group scope.
*/

@description('Name of the lock')
param parLockName string

@description('Notes for the lock')
param parLockNotes string

resource resLock 'Microsoft.Authorization/locks@2020-05-01' = {
  name: parLockName
  properties: {
    level: 'CanNotDelete'
    notes: parLockNotes
  }
}
