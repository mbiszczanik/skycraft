/*=====================================================
SUMMARY: Lab 5.3 - Network Monitoring Module
DESCRIPTION: Deploys Network Watcher monitoring resources for SkyCraft:
             - VNet Flow Log (prod-skycraft-swc-vnet-flowlog) targeting
               prod-skycraft-swc-vnet with Version 2, 7-day retention,
               and Traffic Analytics to the platform Log Analytics Workspace.
             - Connection Monitor (skycraft-hub-spoke-cm) probing SSH
               connectivity from the production auth VM to the dev auth VM
               every 5 minutes.
             Both resources are child resources of the existing Network Watcher
             in NetworkWatcherRG and are scoped to Sweden Central.
AUTHOR/S: SkyCraft
VERSION: 0.2.0
DEPLOYMENT: [Internal use via Orchestrator]
======================================================*/

/*******************
*    Parameters    *
*******************/

@description('Azure region for all resources.')
param parLocation string = 'swedencentral'

@description('Environment tag value for the monitoring resources.')
param parEnvironment string = 'Production'

@description('Resource ID of the production VNet to enable flow logging on.')
param parProdVnetResourceId string

@description('Resource ID of the platform storage account to store flow logs.')
param parStorageAccountResourceId string

@description('Resource ID of the Log Analytics Workspace for Traffic Analytics and Connection Monitor output.')
param parWorkspaceResourceId string

@description('Resource ID of the production VM used as the Connection Monitor source endpoint.')
param parProdVmResourceId string

@description('Resource ID of the dev auth VM used as the Connection Monitor destination endpoint.')
param parDevVmResourceId string

@description('Private IP address of the dev auth VM. Used only as fallback if the VM endpoint is not resolvable at test time.')
param parDevAuthVmPrivateIp string = '10.1.1.4'

/*******************
*    Variables     *
*******************/

var varCommonTags = {
  Project: 'SkyCraft'
  Environment: parEnvironment
  CostCenter: 'MSDN'
}

// Derived from location so this module works in any region without changes
var varNetworkWatcherName = 'NetworkWatcher_${parLocation}'
var varFlowLogName = 'prod-skycraft-swc-vnet-flowlog'
var varConnectionMonitorName = 'skycraft-hub-spoke-cm'

/*******************
*    Resources     *
*******************/

// Reference the existing Network Watcher (auto-provisioned in NetworkWatcherRG)
resource resNetworkWatcher 'Microsoft.Network/networkWatchers@2023-11-01' existing = {
  name: varNetworkWatcherName
}

// ── VNet Flow Log ──────────────────────────────────────────────────────────
// Captures all IP traffic traversing prod-skycraft-swc-vnet using the newer
// virtual network flow log type (NSG flow logs deprecated June 2025).
resource resFlowLog 'Microsoft.Network/networkWatchers/flowLogs@2023-11-01' = {
  parent: resNetworkWatcher
  name: varFlowLogName
  location: parLocation
  tags: varCommonTags
  properties: {
    targetResourceId: parProdVnetResourceId
    storageId: parStorageAccountResourceId
    enabled: true
    format: {
      type: 'JSON'
      version: 2
    }
    retentionPolicy: {
      days: 7
      enabled: true
    }
    flowAnalyticsConfiguration: {
      networkWatcherFlowAnalyticsConfiguration: {
        enabled: true
        workspaceResourceId: parWorkspaceResourceId
        trafficAnalyticsInterval: 10
      }
    }
  }
}

// ── Connection Monitor ──────────────────────────────────────────────────────
// Continuously probes TCP/22 (SSH) from prod-skycraft-swc-auth-vm to the dev
// auth VM every 5 minutes to verify Hub-Spoke peering health.
resource resConnectionMonitor 'Microsoft.Network/networkWatchers/connectionMonitors@2023-11-01' = {
  parent: resNetworkWatcher
  name: varConnectionMonitorName
  location: parLocation
  tags: varCommonTags
  properties: {
    endpoints: [
      {
        name: 'prod-auth-source'
        type: 'AzureVM'
        resourceId: parProdVmResourceId
      }
      {
        // AzureVM type gives hop-level correlation; address is the fallback hint
        name: 'dev-auth-destination'
        type: 'AzureVM'
        resourceId: parDevVmResourceId
        address: parDevAuthVmPrivateIp
      }
    ]
    testConfigurations: [
      {
        name: 'tcp-22-every-5m'
        testFrequencySec: 300
        protocol: 'Tcp'
        tcpConfiguration: {
          port: 22
          disableTraceRoute: false
        }
        successThreshold: {
          checksFailedPercent: 10
          roundTripTimeMs: 100
        }
      }
    ]
    testGroups: [
      {
        name: 'hub-spoke-ssh'
        disable: false
        sources: [
          'prod-auth-source'
        ]
        destinations: [
          'dev-auth-destination'
        ]
        testConfigurations: [
          'tcp-22-every-5m'
        ]
      }
    ]
    outputs: [
      {
        type: 'Workspace'
        workspaceSettings: {
          workspaceResourceId: parWorkspaceResourceId
        }
      }
    ]
  }
}

/******************
*     Outputs     *
******************/

@description('Resource ID of the VNet Flow Log.')
output outFlowLogId string = resFlowLog.id

@description('Resource ID of the Connection Monitor.')
output outConnectionMonitorId string = resConnectionMonitor.id
