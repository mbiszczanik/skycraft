/*=====================================================
SUMMARY: Lab 3.2 - Parameters
DESCRIPTION: Parameter values for the Development environment. The SSH public key is read from the SKYCRAFT_SSH_PUBLIC_KEY environment variable at build time; Deploy-Bicep.ps1 passes it directly instead of using this file.
EXAMPLE: az deployment sub create --location swedencentral --template-file main.bicep --parameters parameters/main.bicepparam
AUTHOR/S: Marcin Biszczanik
VERSION: 1.0.0
======================================================*/

using '../main.bicep'

param parLocation = 'swedencentral'
param parEnvironment = 'dev'
param parSshPublicKey = readEnvironmentVariable('SKYCRAFT_SSH_PUBLIC_KEY', '')
