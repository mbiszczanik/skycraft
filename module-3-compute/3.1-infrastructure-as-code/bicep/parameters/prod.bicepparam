/*=====================================================
SUMMARY: Lab 3.1 - Prod Parameters
DESCRIPTION: Parameter values for Production Environment
EXAMPLE: .\scripts\Deploy-Bicep.ps1 -Environment prod
AUTHOR/S: Marcin Biszczanik
VERSION: 1.1.0
======================================================*/

using '../main.bicep'

// Global parameters
param parLocation = 'swedencentral'
param parEnvironment = 'prod'
param parProject = 'skycraft'

// Network parameters
param parHubVnetAddressPrefix = '10.0.0.0/16'
param parProdVnetAddressPrefix = '10.2.0.0/16'
