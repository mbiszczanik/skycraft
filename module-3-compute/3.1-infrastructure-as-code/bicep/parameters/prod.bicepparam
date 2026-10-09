/*=====================================================
SUMMARY: Lab 3.1 - Prod Parameters
DESCRIPTION: Parameter values for Production Environment
EXAMPLE: .\scripts\Deploy-Bicep.ps1 -Environment prod
AUTHOR/S: Marcin Biszczanik
VERSION: 1.2.0
======================================================*/

using '../main.bicep'

// Global parameters
param parLocation = 'swedencentral'
param parEnvironment = 'prod'
param parProject = 'skycraft'

// Network parameters
param parHubVnetAddressPrefix = '10.0.0.0/16'
param parProdVnetAddressPrefix = '10.2.0.0/16'

// Existing VNets, as scripts/Deploy-Bicep.ps1 found them. A VNet that exists is referenced, not
// redeployed, so the peerings and subnet settings Module 2 added survive (issue #188). Unset - a
// direct Test-AzSubscriptionDeployment or 'bicep build-params' - means both VNets are declared.
param parHubVnetExists = bool(readEnvironmentVariable('SKYCRAFT_HUB_VNET_EXISTS', 'false'))
param parDevVnetExists = bool(readEnvironmentVariable('SKYCRAFT_DEV_VNET_EXISTS', 'false'))
