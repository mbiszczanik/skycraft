/*=====================================================
SUMMARY: Lab 3.4 - Prod Parameters
DESCRIPTION: Parameter values for Production Environment
EXAMPLE: az deployment sub create --location swedencentral --template-file main.bicep --parameters parameters/prod.bicepparam
AUTHOR/S: Marcin Biszczanik
VERSION: 1.0.0
======================================================*/

using '../main.bicep'

param parEnvironment = 'prod'

// Resource names differ from template defaults (which hard-code the 'dev' prefix).
param parResourceGroupName = 'prod-skycraft-swc-rg'
param parVnetName = 'prod-skycraft-swc-vnet'
