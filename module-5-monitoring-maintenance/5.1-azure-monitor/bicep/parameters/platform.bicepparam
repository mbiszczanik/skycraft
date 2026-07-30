/*=====================================================
SUMMARY: Lab 5.1 - Platform Parameters
DESCRIPTION: Parameter values for the Platform environment (Azure Monitor & Insights).
EXAMPLE: .\scripts\Deploy-Bicep.ps1 -OpsEmail <you@example.com>
         Deploy through the script, not 'az deployment' directly: this file leaves
         the Ops e-mail and the VM / storage resource IDs as empty placeholders, which exist only to keep
         'az bicep build-params' valid (BCP258). Passing it straight to the CLI
         submits those empty values.
AUTHOR/S: Marcin Biszczanik
VERSION: 1.0.0
======================================================*/

using '../main.bicep'

param parEnvironment = 'Platform'

// Required parameters with no default. Empty placeholders keep
// 'az bicep build-params' valid (avoids BCP258); the real values are
// overridden by Deploy-Bicep.ps1 at runtime.
param parOpsEmail = '' // overridden by Deploy-Bicep.ps1 at runtime
param parProdVmResourceId = '' // overridden by Deploy-Bicep.ps1 at runtime
param parStorageAccountResourceId = '' // overridden by Deploy-Bicep.ps1 at runtime
