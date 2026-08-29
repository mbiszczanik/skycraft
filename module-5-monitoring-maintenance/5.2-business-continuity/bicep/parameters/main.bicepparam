/*=====================================================
SUMMARY: Lab 5.2 - Parameters
DESCRIPTION: Assigns the parameters the CI "bicep build-params" check requires. The workspace resource ID comes from an environment variable, with a well-formed placeholder (zero subscription GUID) as the default; Deploy-Bicep.ps1 resolves the real value from Azure and passes it directly instead of using this file
EXAMPLE: az deployment sub create --location swedencentral --template-file ../main.bicep --parameters main.bicepparam
AUTHOR/S: Marcin Biszczanik
VERSION: 1.0.0
======================================================*/

using '../main.bicep'

param parLocation = 'swedencentral'
param parEnvironment = 'Platform'
param parWorkspaceId = readEnvironmentVariable(
  'SKYCRAFT_WORKSPACE_RESOURCE_ID',
  '/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/platform-skycraft-swc-rg/providers/Microsoft.OperationalInsights/workspaces/platform-skycraft-swc-law'
)
