/*=====================================================
SUMMARY: Lab 3.1 - Dev Parameters
DESCRIPTION: Parameter values for Development Environment
EXAMPLE: .\scripts\Deploy-Bicep.ps1 -Environment dev
AUTHOR/S: Marcin Biszczanik
VERSION: 1.3.0
======================================================*/

using '../main.bicep'

// Global parameters
param parLocation = 'swedencentral'
param parEnvironment = 'dev'
param parProject = 'skycraft'

// Network parameters
param parHubVnetAddressPrefix = '10.0.0.0/16'
param parDevVnetAddressPrefix = '10.1.0.0/16'

// Existing VNets, as scripts/Deploy-Bicep.ps1 found them. A VNet that exists is referenced, not
// redeployed, so the peerings and subnet settings Module 2 added survive (issue #188). Unset - a
// direct Test-AzSubscriptionDeployment or 'bicep build-params' - means both VNets are declared.
param parHubVnetExists = bool(readEnvironmentVariable('SKYCRAFT_HUB_VNET_EXISTS', 'false'))
param parDevVnetExists = bool(readEnvironmentVariable('SKYCRAFT_DEV_VNET_EXISTS', 'false'))

// The dev load balancer and its public IP, on the same terms: one that exists is left untouched
// (issue #263) - a public IP made without zones would reject the zone-redundant declaration, and
// the load balancer is Lab 2.3's. Unset means both are declared.
param parDevLbPipExists = bool(readEnvironmentVariable('SKYCRAFT_DEV_LB_PIP_EXISTS', 'false'))
param parDevLbExists = bool(readEnvironmentVariable('SKYCRAFT_DEV_LB_EXISTS', 'false'))
