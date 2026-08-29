/*=====================================================
SUMMARY: Lab 5.3 - Parameters
DESCRIPTION: Assigns the parameters the CI "bicep build-params" check requires. The five resource IDs come from environment variables, with well-formed placeholders (zero subscription GUID) as defaults; Deploy-Bicep.ps1 resolves the real values from Azure and passes them directly instead of using this file
EXAMPLE: az deployment sub create --location swedencentral --template-file ../main.bicep --parameters main.bicepparam
AUTHOR/S: Marcin Biszczanik
VERSION: 1.0.0
======================================================*/

using '../main.bicep'

var varPlaceholderSubscription = '/subscriptions/00000000-0000-0000-0000-000000000000'

param parLocation = 'swedencentral'
param parEnvironment = 'Production'
param parProdVnetResourceId = readEnvironmentVariable(
  'SKYCRAFT_PROD_VNET_RESOURCE_ID',
  '${varPlaceholderSubscription}/resourceGroups/prod-skycraft-swc-rg/providers/Microsoft.Network/virtualNetworks/prod-skycraft-swc-vnet'
)
param parStorageAccountResourceId = readEnvironmentVariable(
  'SKYCRAFT_PLATFORM_STORAGE_RESOURCE_ID',
  '${varPlaceholderSubscription}/resourceGroups/platform-skycraft-swc-rg/providers/Microsoft.Storage/storageAccounts/platformskycraftswcsa'
)
param parWorkspaceResourceId = readEnvironmentVariable(
  'SKYCRAFT_WORKSPACE_RESOURCE_ID',
  '${varPlaceholderSubscription}/resourceGroups/platform-skycraft-swc-rg/providers/Microsoft.OperationalInsights/workspaces/platform-skycraft-swc-law'
)
param parProdVmResourceId = readEnvironmentVariable(
  'SKYCRAFT_CM_SOURCE_VM_RESOURCE_ID',
  '${varPlaceholderSubscription}/resourceGroups/prod-skycraft-swc-rg/providers/Microsoft.Compute/virtualMachines/prod-skycraft-swc-auth-vm'
)
param parDevVmResourceId = readEnvironmentVariable(
  'SKYCRAFT_CM_DESTINATION_VM_RESOURCE_ID',
  '${varPlaceholderSubscription}/resourceGroups/dev-skycraft-swc-rg/providers/Microsoft.Compute/virtualMachines/dev-skycraft-swc-auth-vm'
)
