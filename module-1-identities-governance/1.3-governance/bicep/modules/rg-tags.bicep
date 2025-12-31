/*
SUMMARY: Helper module to apply tags to a Resource Group
DESCRIPTION: Uses Microsoft.Resources/tags to apply tags to the current Resource Group scope.
*/

@description('Tags to apply')
param parTags object

resource resTags 'Microsoft.Resources/tags@2021-04-01' = {
  name: 'default'
  properties: {
    tags: parTags
  }
}
