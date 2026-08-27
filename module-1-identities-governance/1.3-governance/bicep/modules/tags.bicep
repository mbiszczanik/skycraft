/*=====================================================
SUMMARY: Lab 1.3 - Tags Module
DESCRIPTION: Applies tags to the current Resource Group (local fallback - no AVM module exists for Microsoft.Resources/tags)
AUTHOR/S: Marcin Biszczanik
VERSION: 0.3.0
======================================================*/

@description('Tags to apply to the resource group')
param parTags object

resource resTags 'Microsoft.Resources/tags@2021-04-01' = {
  name: 'default'
  properties: {
    tags: parTags
  }
}
