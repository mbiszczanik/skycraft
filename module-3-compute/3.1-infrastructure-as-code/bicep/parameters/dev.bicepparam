/*=====================================================
SUMMARY: Lab 3.1 - Dev Parameters
DESCRIPTION: Parameter values for Development Environment
EXAMPLE: .\scripts\Deploy-Bicep.ps1 -Environment dev
AUTHOR/S: Marcin Biszczanik
VERSION: 1.1.0
======================================================*/

using '../main.bicep'

// Global parameters
param parLocation = 'swedencentral'
param parEnvironment = 'dev'
param parProject = 'skycraft'

// Network parameters
param parHubVnetAddressPrefix = '10.0.0.0/16'
param parDevVnetAddressPrefix = '10.1.0.0/16'
