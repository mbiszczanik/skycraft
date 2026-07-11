/*=====================================================
SUMMARY: Lab 4.4 - Storage Security - Dev Parameters
DESCRIPTION: Parameter values for the Development environment storage security deployment.
             parClientIp is intentionally left at its template default ('') and is
             overridden by Deploy-Bicep.ps1 at runtime (auto-detected client IP).
EXAMPLE: az deployment sub create --location swedencentral --template-file main.bicep --parameters parameters/dev.bicepparam
AUTHOR/S: Marcin Biszczanik
VERSION: 1.0.0
======================================================*/

using '../main.bicep'

// Differentiating parameter (all others use template defaults)
param parEnvironment = 'dev'
