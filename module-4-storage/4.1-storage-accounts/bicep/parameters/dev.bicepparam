/*=====================================================
SUMMARY: Lab 4.1 - Storage Accounts - Dev Parameters
DESCRIPTION: Parameter values for the Development environment storage account.
EXAMPLE: az deployment sub create --location swedencentral --template-file main.bicep --parameters parameters/dev.bicepparam
AUTHOR/S: Marcin Biszczanik
VERSION: 1.0.0
======================================================*/

using '../main.bicep'

// Differentiating parameter (all others use template defaults)
param parEnvironment = 'dev'
