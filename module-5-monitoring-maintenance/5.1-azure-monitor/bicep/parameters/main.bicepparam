/*=====================================================
SUMMARY: Lab 5.1 - Parameters
DESCRIPTION: Assigns the parameters the CI "bicep build-params" check requires. The three run-time values (ops e-mail, monitored VM and platform storage account resource IDs) come from environment variables, with well-formed placeholders (zero subscription GUID) as defaults; Deploy-Bicep.ps1 resolves the real values from Azure and passes them directly instead of using this file
EXAMPLE: az deployment sub create --location swedencentral --template-file ../main.bicep --parameters main.bicepparam
AUTHOR/S: Marcin Biszczanik
VERSION: 1.0.0
======================================================*/

using '../main.bicep'

var varPlaceholderSubscription = '/subscriptions/00000000-0000-0000-0000-000000000000'

param parLocation = 'swedencentral'
param parEnvironment = 'Platform'
param parOpsEmail = readEnvironmentVariable('SKYCRAFT_OPS_EMAIL', 'ops@example.com')
param parProdVmResourceId = readEnvironmentVariable(
  'SKYCRAFT_MONITORED_VM_RESOURCE_ID',
  '${varPlaceholderSubscription}/resourceGroups/dev-skycraft-swc-rg/providers/Microsoft.Compute/virtualMachines/dev-skycraft-swc-auth-vm'
)
param parStorageAccountResourceId = readEnvironmentVariable(
  'SKYCRAFT_PLATFORM_STORAGE_RESOURCE_ID',
  '${varPlaceholderSubscription}/resourceGroups/platform-skycraft-swc-rg/providers/Microsoft.Storage/storageAccounts/platformskycraftswcsa'
)
