/*=====================================================
SUMMARY: Lab 3.3 - Parameters
DESCRIPTION: Assigns the parameters the CI "bicep build-params" check requires; every other parameter keeps its main.bicep default, and the resource names compose from parEnvironment (#121)
EXAMPLE: .\scripts\Deploy-Bicep.ps1
AUTHOR/S: Marcin Biszczanik
VERSION: 1.1.0
======================================================*/

using '../main.bicep'

param parLocation = 'swedencentral'
param parEnvironment = 'dev'
