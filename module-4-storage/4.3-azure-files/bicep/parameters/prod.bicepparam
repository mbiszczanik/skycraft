/*=====================================================
SUMMARY: Lab 4.3 - Azure Files - Prod Parameters
DESCRIPTION: Parameter values for the Production environment Azure Files deployment.
EXAMPLE: az deployment sub create --location swedencentral --template-file main.bicep --parameters parameters/prod.bicepparam
AUTHOR/S: Marcin Biszczanik
VERSION: 1.0.0
======================================================*/

using '../main.bicep'

// Differentiating parameter (all others use template defaults)
param parEnvironment = 'prod'
