/*=====================================================
SUMMARY: Lab 1.2 - Role Assignment Module
DESCRIPTION: Assigns a role to a principal within a specific scope
AUTHOR/S: Marcin Biszczanik
VERSION: 0.2.0
======================================================*/

@description('The Principal ID of the user or group')
param parPrincipalId string

@description('The Role Definition ID (not name)')
param parRoleDefinitionId string

@description('The type of principal (User, Group, ServicePrincipal)')
@allowed([
  'User'
  'Group'
  'ServicePrincipal'
])
param parPrincipalType string = 'User'

resource resRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, parPrincipalId, parRoleDefinitionId)
  properties: {
    roleDefinitionId: parRoleDefinitionId
    principalId: parPrincipalId
    principalType: parPrincipalType
  }
}
