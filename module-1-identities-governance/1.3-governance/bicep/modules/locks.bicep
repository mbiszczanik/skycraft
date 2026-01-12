/*=====================================================
SUMMARY: Lab 1.3 - Locks Module
DESCRIPTION: Applies a CanNotDelete lock to the current Resource Group
AUTHOR/S: Marcin Biszczanik
VERSION: 0.2.0
======================================================*/

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
