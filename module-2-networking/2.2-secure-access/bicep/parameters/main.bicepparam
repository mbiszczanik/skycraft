/*=====================================================
SUMMARY: Lab 2.2 - Secure Access Parameters
DESCRIPTION: Default parameter set for main.bicep (Azure Bastion disabled; set parDeployBastion = true to include it)
EXAMPLE: az deployment sub create --location swedencentral --template-file ../main.bicep --parameters main.bicepparam
AUTHOR/S: Marcin Biszczanik
VERSION: 0.1.0
======================================================*/

using '../main.bicep'

param parLocation = 'swedencentral'
param parDeployBastion = false
