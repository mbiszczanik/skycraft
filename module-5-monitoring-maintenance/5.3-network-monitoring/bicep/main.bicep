/*=====================================================
SUMMARY: Lab 5.3 - Network Monitoring & Diagnostics Orchestrator
DESCRIPTION: Orchestrates deployment of Network Monitoring resources for
             SkyCraft Lab 5.3. Deploys a VNet Flow Log and Connection Monitor
             into the NetworkWatcherRG resource group, targeting the
             production VNet and Hub-to-Spoke SSH connectivity path.
EXAMPLE: az deployment sub create --location swedencentral --template-file main.bicep
AUTHOR/S: SkyCraft
VERSION: 0.2.0
DEPLOYMENT: .\scripts\Deploy-Bicep.ps1
======================================================*/

targetScope = 'subscription'

/*******************
*    Parameters    *
*******************/

@description('Azure region for all resources.')
param parLocation string = 'swedencentral'

@description('Environment tag value applied to all resources.')
param parEnvironment string = 'Production'

@description('Resource ID of the production VNet to enable flow logging on.')
param parProdVnetResourceId string

@description('Resource ID of the platform storage account to store flow logs.')
param parStorageAccountResourceId string

@description('Resource ID of the Log Analytics Workspace for Traffic Analytics.')
param parWorkspaceResourceId string

@description('Resource ID of the production VM used as the Connection Monitor source endpoint.')
param parProdVmResourceId string

@description('Resource ID of the dev auth VM used as the Connection Monitor destination endpoint.')
param parDevVmResourceId string

/*******************
*    Variables     *
*******************/

var varNetworkWatcherRgName = 'NetworkWatcherRG'

/*******************
*    Resources     *
*******************/

// Reference the existing NetworkWatcherRG (auto-provisioned by Azure)
resource resNetworkWatcherRg 'Microsoft.Resources/resourceGroups@2023-07-01' existing = {
  name: varNetworkWatcherRgName
}

// ── Network Monitoring Module ──────────────────────────────────────────────
module modNetworkMonitoring 'modules/network-monitoring.bicep' = {
  name: 'network-monitoring-deployment'
  scope: resNetworkWatcherRg
  params: {
    parLocation: parLocation
    parEnvironment: parEnvironment
    parProdVnetResourceId: parProdVnetResourceId
    parStorageAccountResourceId: parStorageAccountResourceId
    parWorkspaceResourceId: parWorkspaceResourceId
    parProdVmResourceId: parProdVmResourceId
    parDevVmResourceId: parDevVmResourceId
  }
}

/******************
*     Outputs     *
******************/

@description('Resource ID of the VNet Flow Log.')
output outFlowLogId string = modNetworkMonitoring.outputs.outFlowLogId

@description('Resource ID of the Connection Monitor.')
output outConnectionMonitorId string = modNetworkMonitoring.outputs.outConnectionMonitorId
