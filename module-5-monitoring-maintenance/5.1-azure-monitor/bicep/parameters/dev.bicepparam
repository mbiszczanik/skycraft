/*=====================================================
SUMMARY: Lab 5.1 - Dev Parameters
DESCRIPTION: Parameter values for the Development environment (Azure Monitor & Insights).
EXAMPLE: az deployment sub create --location swedencentral --template-file main.bicep --parameters parameters/dev.bicepparam
AUTHOR/S: Marcin Biszczanik
VERSION: 1.0.0
======================================================*/

using '../main.bicep'

param parEnvironment = 'Development'

// Required parameters with no default. Empty placeholders keep
// 'az bicep build-params' valid (avoids BCP258); the real values are
// overridden by Deploy-Bicep.ps1 at runtime.
param parOpsEmail = '' // overridden by Deploy-Bicep.ps1 at runtime
param parProdVmResourceId = '' // overridden by Deploy-Bicep.ps1 at runtime
param parStorageAccountResourceId = '' // overridden by Deploy-Bicep.ps1 at runtime
