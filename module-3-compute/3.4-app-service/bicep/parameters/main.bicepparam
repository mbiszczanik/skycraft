/*=====================================================
SUMMARY: Lab 3.4 - Parameters
DESCRIPTION: Parameter values for the Development environment (the defaults of main.bicep, pinned)
EXAMPLE: az deployment sub create --location swedencentral --template-file main.bicep --parameters parameters/main.bicepparam
AUTHOR/S: Marcin Biszczanik
VERSION: 1.0.0
======================================================*/

using '../main.bicep'

param parLocation = 'swedencentral'
param parEnvironment = 'dev'
param parResourceGroupName = 'dev-skycraft-swc-rg'
param parVnetName = 'dev-skycraft-swc-vnet'
param parSubnetName = 'AppServiceSubnet'
