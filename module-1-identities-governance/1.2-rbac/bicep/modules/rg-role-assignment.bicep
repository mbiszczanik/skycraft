/*
SUMMARY: Helper module for Resource Group scoped role assignments
DESCRIPTION: Assigns a role to a principal within a specific Resource Group.
*/

@description('The Principal ID of the user or group')
param principalId string

@description('The Role Definition ID (not name)')
param roleDefinitionId string

@description('The type of principal (User, Group, ServicePrincipal)')
@allowed([
  'User'
  'Group'
  'ServicePrincipal'
])
param principalType string = 'User'

resource roleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, principalId, roleDefinitionId)
  properties: {
    roleDefinitionId: roleDefinitionId
    principalId: principalId
    principalType: principalType
  }
}
