/*=====================================================
SUMMARY: Lab 3.4 - Dev Parameters
DESCRIPTION: Parameter values for Development Environment
EXAMPLE: az deployment sub create --location swedencentral --template-file main.bicep --parameters parameters/dev.bicepparam
AUTHOR/S: Marcin Biszczanik
VERSION: 1.0.0
======================================================*/

using '../main.bicep'

param parEnvironment = 'dev'
