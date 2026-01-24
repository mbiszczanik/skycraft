/*=====================================================
SUMMARY: Lab 3.1 - Prod Parameters
DESCRIPTION: Parameter values for Production Environment
EXAMPLE: az deployment sub create --location swedencentral --template-file main.bicep --parameters parameters/prod.bicepparam
AUTHOR/S: Marcin Biszczanik
VERSION: 1.0.0
======================================================*/

using '../main.bicep'

// Global parameters
param parLocation = 'swedencentral'
param parEnvironment = 'prod'
param parProject = 'skycraft'
param parCostCenter = 'MSDN'

// Network parameters
param parHubVnetAddressPrefix = '10.0.0.0/16'
param parProdVnetAddressPrefix = '10.2.0.0/16'
