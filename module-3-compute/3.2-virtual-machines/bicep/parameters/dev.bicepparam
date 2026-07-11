/*=====================================================
SUMMARY: Lab 3.2 - Dev Parameters
DESCRIPTION: Parameter values for Development Environment
EXAMPLE: az deployment sub create --location swedencentral --template-file main.bicep --parameters parameters/dev.bicepparam
AUTHOR/S: Marcin Biszczanik
VERSION: 1.0.0
======================================================*/

using '../main.bicep'

param parEnvironment = 'dev'

// Required @secure() parameter with no default.
// Empty placeholder keeps 'az bicep build-params' valid (avoids BCP258);
// the real key is overridden by Deploy-Bicep.ps1 at runtime.
param parSshPublicKey = '' // overridden by Deploy-Bicep.ps1 at runtime
