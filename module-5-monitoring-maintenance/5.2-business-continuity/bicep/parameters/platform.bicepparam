/*=====================================================
SUMMARY: Lab 5.2 - Platform Parameters
DESCRIPTION: Parameter values for the Platform environment (Business Continuity & Disaster Recovery).
EXAMPLE: .\scripts\Deploy-Bicep.ps1
         Deploy through the script, not 'az deployment' directly: this file leaves
         the Log Analytics workspace ID as an empty placeholder, which exist only to keep
         'az bicep build-params' valid (BCP258). Passing it straight to the CLI
         submits those empty values.
AUTHOR/S: Marcin Biszczanik
VERSION: 1.0.0
======================================================*/

using '../main.bicep'

param parEnvironment = 'Platform'

// Required parameter with no default. Empty placeholder keeps
// 'az bicep build-params' valid (avoids BCP258); the real value is
// overridden by Deploy-Bicep.ps1 at runtime.
param parWorkspaceId = '' // overridden by Deploy-Bicep.ps1 at runtime
