/*=====================================================
SUMMARY: Lab 1.3 - Tags Module
DESCRIPTION: Applies tags to the current Resource Group
AUTHOR/S: Marcin Biszczanik
VERSION: 0.2.0
======================================================*/

@description('Tags to apply')
param parTags object

resource resTags 'Microsoft.Resources/tags@2021-04-01' = {
  name: 'default'
  properties: {
    tags: parTags
  }
}
