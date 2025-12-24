/*=====================================================
SUMMARY: Lab 1.3 - Resource Group Tags
DESCRIPTION: This template applies standardized tags to resource groups
EXAMPLE:
AUTHOR/S: Marcin Biszczanik
VERSION: 0.1.0
======================================================*/

@description('Admin email for Owner tag')
param parAdminEmail string

// Development resource group tags
var devTags = {
  Environment: 'Development'
  Project: 'SkyCraft'
  CostCenter: 'MSDN'
  Owner: parAdminEmail
}

// Production resource group tags
var prodTags = {
  Environment: 'Production'
  Project: 'SkyCraft'
  CostCenter: 'MSDN'
  Owner: parAdminEmail
  Criticality: 'High'
}

// Shared resource group tags
var PlatformTags = {
  Environment: 'Platform'
  Project: 'SkyCraft'
  CostCenter: 'MSDN'
  Owner: parAdminEmail
}
