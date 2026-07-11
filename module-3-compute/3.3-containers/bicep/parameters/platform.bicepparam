/*=====================================================
SUMMARY: Lab 3.3 - Platform Parameters
DESCRIPTION: Parameter values for Platform Environment
EXAMPLE: az deployment sub create --location swedencentral --template-file main.bicep --parameters parameters/platform.bicepparam
AUTHOR/S: Marcin Biszczanik
VERSION: 1.0.0
======================================================*/

using '../main.bicep'

param parEnvironment = 'platform'

// Resource names differ from template defaults (which hard-code the 'dev' prefix).
param parResourceGroupName = 'platform-skycraft-swc-rg'
param parAcrName = 'platformskycraftswcacr01'
param parAciName = 'platform-skycraft-swc-aci-auth'
param parCaeName = 'platform-skycraft-swc-cae-02'
param parAcaName = 'platform-skycraft-swc-aca-02' // shortened to satisfy parAcaName maxLength(32)
