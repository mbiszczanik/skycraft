/*=====================================================
SUMMARY: Lab 4.3 - Azure Files - Platform Parameters
DESCRIPTION: Parameter values for the Platform environment Azure Files deployment.
EXAMPLE: az deployment sub create --location swedencentral --template-file main.bicep --parameters parameters/platform.bicepparam
AUTHOR/S: Marcin Biszczanik
VERSION: 1.0.0
======================================================*/

using '../main.bicep'

// Differentiating parameter (all others use template defaults)
param parEnvironment = 'platform'
