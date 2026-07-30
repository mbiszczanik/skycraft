/*=====================================================
SUMMARY: Lab 3.2 - Dev Parameters
DESCRIPTION: Parameter values for Development Environment
EXAMPLE: .\scripts\Deploy-Bicep.ps1 -Environment dev
         Deploy through the script, not 'az deployment' directly: this file leaves
         the SSH public key as an empty placeholder, which exist only to keep
         'az bicep build-params' valid (BCP258). Passing it straight to the CLI
         submits those empty values.
AUTHOR/S: Marcin Biszczanik
VERSION: 1.0.0
======================================================*/

using '../main.bicep'

param parEnvironment = 'dev'

// Required @secure() parameter with no default.
// Empty placeholder keeps 'az bicep build-params' valid (avoids BCP258);
// the real key is overridden by Deploy-Bicep.ps1 at runtime.
param parSshPublicKey = '' // overridden by Deploy-Bicep.ps1 at runtime
