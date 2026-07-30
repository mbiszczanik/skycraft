/*=====================================================
SUMMARY: Lab 5.3 - Prod Parameters
DESCRIPTION: Parameter values for the Production environment (Network Monitoring & Diagnostics).
EXAMPLE: .\scripts\Deploy-Bicep.ps1
         Deploy through the script, not 'az deployment' directly: this file leaves
         the VNet, storage, workspace and VM resource IDs as empty placeholders, which exist only to keep
         'az bicep build-params' valid (BCP258). Passing it straight to the CLI
         submits those empty values.
AUTHOR/S: Marcin Biszczanik
VERSION: 1.0.0
======================================================*/

using '../main.bicep'

param parEnvironment = 'Production'

// Required parameters with no default. Empty placeholders keep
// 'az bicep build-params' valid (avoids BCP258); the real values are
// overridden by Deploy-Bicep.ps1 at runtime.
param parProdVnetResourceId = '' // overridden by Deploy-Bicep.ps1 at runtime
param parStorageAccountResourceId = '' // overridden by Deploy-Bicep.ps1 at runtime
param parWorkspaceResourceId = '' // overridden by Deploy-Bicep.ps1 at runtime
param parProdVmResourceId = '' // overridden by Deploy-Bicep.ps1 at runtime
param parDevVmResourceId = '' // overridden by Deploy-Bicep.ps1 at runtime
