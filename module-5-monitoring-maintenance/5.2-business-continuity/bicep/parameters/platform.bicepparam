/*=====================================================
SUMMARY: Lab 5.2 - Platform Parameters
DESCRIPTION: Parameter values for the Platform environment (Business Continuity & Disaster Recovery).
EXAMPLE: az deployment sub create --location swedencentral --template-file main.bicep --parameters parameters/platform.bicepparam
AUTHOR/S: Marcin Biszczanik
VERSION: 1.0.0
======================================================*/

using '../main.bicep'

param parEnvironment = 'Platform'

// Required parameter with no default. Empty placeholder keeps
// 'az bicep build-params' valid (avoids BCP258); the real value is
// overridden by Deploy-Bicep.ps1 at runtime.
param parWorkspaceId = '' // overridden by Deploy-Bicep.ps1 at runtime
