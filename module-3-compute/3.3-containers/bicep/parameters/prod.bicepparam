/*=====================================================
SUMMARY: Lab 3.3 - Prod Parameters
DESCRIPTION: Parameter values for Production Environment
EXAMPLE: az deployment sub create --location swedencentral --template-file main.bicep --parameters parameters/prod.bicepparam
AUTHOR/S: Marcin Biszczanik
VERSION: 1.0.0
======================================================*/

using '../main.bicep'

param parEnvironment = 'prod'

// Resource names differ from template defaults (which hard-code the 'dev' prefix).
param parResourceGroupName = 'prod-skycraft-swc-rg'
param parAcrName = 'prodskycraftswcacr01'
param parAciName = 'prod-skycraft-swc-aci-auth'
param parCaeName = 'prod-skycraft-swc-cae-02'
param parAcaName = 'prod-skycraft-swc-aca-world-02'
