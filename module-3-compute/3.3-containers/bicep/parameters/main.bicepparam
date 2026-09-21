/*=====================================================
SUMMARY: Lab 3.3 - Parameters
DESCRIPTION: Assigns the parameters the CI "bicep build-params" check requires; every other parameter keeps its main.bicep default, and the resource names compose from parEnvironment (#121)
EXAMPLE: az deployment sub create --location swedencentral --template-file main.bicep --parameters parameters/main.bicepparam
AUTHOR/S: Marcin Biszczanik
VERSION: 1.1.0
======================================================*/

using '../main.bicep'

param parLocation = 'swedencentral'
param parEnvironment = 'dev'
