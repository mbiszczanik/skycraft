/*=====================================================
SUMMARY: Lab 5.1 - Azure Monitor & Insights Orchestrator
DESCRIPTION: Orchestrates deployment of centralized monitoring
             infrastructure for SkyCraft. Deploys a Log Analytics
             Workspace, VM Insights Data Collection Rule, Action Group,
             Metric Alert, and Alert Processing Rule into the
             platform-skycraft-swc-rg resource group.
EXAMPLE: az deployment sub create --location swedencentral --template-file main.bicep
AUTHOR/S: SkyCraft
VERSION: 0.1.0
DEPLOYMENT: .\scripts\Deploy-Bicep.ps1
======================================================*/

targetScope = 'subscription'

/*******************
*    Parameters    *
*******************/

@description('Azure region for all resources.')
param parLocation string = 'swedencentral'

@description('Environment tag value for monitoring resources.')
param parEnvironment string = 'Platform'

@description('Email address for the operations Action Group notifications.')
param parOpsEmail string

@description('Resource ID of the production VM to monitor for the CPU metric alert.')
param parProdVmResourceId string

@description('Resource ID of the platform storage account for diagnostic settings.')
param parStorageAccountResourceId string

/*******************
*    Variables     *
*******************/

var varPlatformRgName = 'platform-skycraft-swc-rg'

/*******************
*    Resources     *
*******************/

// Reference existing platform resource group (created in Module 2)
resource resPlatformRg 'Microsoft.Resources/resourceGroups@2023-07-01' existing = {
  name: varPlatformRgName
}

// ── Monitoring Module ──────────────────────────────────────────────────────
module modMonitoring 'modules/monitoring.bicep' = {
  name: 'monitoring-deployment'
  scope: resPlatformRg
  params: {
    parLocation: parLocation
    parEnvironment: parEnvironment
    parOpsEmail: parOpsEmail
    parProdVmResourceId: parProdVmResourceId
    parStorageAccountResourceId: parStorageAccountResourceId
  }
}

/******************
*     Outputs     *
******************/

@description('Resource ID of the deployed Log Analytics Workspace.')
output outWorkspaceId string = modMonitoring.outputs.outWorkspaceId

@description('Customer ID (workspace GUID) for the Log Analytics Workspace.')
output outWorkspaceCustomerId string = modMonitoring.outputs.outWorkspaceCustomerId

@description('Resource ID of the VM Insights Data Collection Rule.')
output outDcrId string = modMonitoring.outputs.outDcrId

@description('Resource ID of the Action Group.')
output outActionGroupId string = modMonitoring.outputs.outActionGroupId

@description('Resource ID of the Metric Alert rule.')
output outAlertRuleId string = modMonitoring.outputs.outAlertRuleId
