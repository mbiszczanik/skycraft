/*=====================================================
SUMMARY: Lab 4.1 - Parameters
DESCRIPTION: Assigns the parameters the CI "bicep build-params" check requires; every other parameter keeps its main.bicep default
EXAMPLE: az deployment sub create --location swedencentral --template-file ../main.bicep --parameters main.bicepparam
AUTHOR/S: Marcin Biszczanik
VERSION: 1.0.0
======================================================*/

using '../main.bicep'

param parLocation = 'swedencentral'
param parEnvironment = 'dev'
param parDeployAllEnvironments = false
