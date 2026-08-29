/*=====================================================
SUMMARY: Lab 5.3 - Network Monitoring & Diagnostics - Orchestrator
DESCRIPTION: Configures the Sweden Central Network Watcher in NetworkWatcherRG through the Azure Verified Module - a VNet flow log on prod-skycraft-swc-vnet (version 2, 7-day retention, Traffic Analytics to the platform workspace) and a connection monitor probing TCP/22 from the production auth VM to the dev auth VM every 5 minutes
EXAMPLE: .\scripts\Deploy-Bicep.ps1
AUTHOR/S: Marcin Biszczanik
VERSION: 2.0.0
DEPLOYMENT: .\scripts\Deploy-Bicep.ps1
======================================================*/

targetScope = 'subscription'

/*******************
*    Parameters    *
*******************/

@description('Location for all resources')
@allowed(['swedencentral', 'northeurope'])
param parLocation string = 'swedencentral'

@description('Environment tag value applied to all resources')
@allowed(['Platform', 'Development', 'Production'])
param parEnvironment string = 'Production'

@description('Resource owner tag value')
@minLength(1)
param parOwner string = 'mbiszczanik'

@description('Resource ID of the production VNet to enable flow logging on')
@minLength(1)
param parProdVnetResourceId string

@description('Resource ID of the platform storage account that stores the flow logs')
@minLength(1)
param parStorageAccountResourceId string

@description('Resource ID of the Log Analytics workspace for Traffic Analytics and the connection monitor output')
@minLength(1)
param parWorkspaceResourceId string

@description('Resource ID of the VM used as the connection monitor source endpoint (Deploy-Bicep.ps1 resolves it at run time)')
@minLength(1)
param parProdVmResourceId string

@description('Resource ID of the dev auth VM used as the connection monitor destination endpoint')
@minLength(1)
param parDevVmResourceId string

@description('Private IP address of the dev auth VM - fallback hint for the destination endpoint if the VM endpoint is not resolvable at test time')
@minLength(7)
@maxLength(15)
param parDevAuthVmPrivateIp string = '10.1.1.4'

@description('Flow log retention in days (0 keeps the logs indefinitely)')
@minValue(0)
@maxValue(365)
param parFlowLogRetentionDays int = 7

/*******************
*    Variables     *
*******************/

var varCommonTags = {
  Project: 'SkyCraft'
  Environment: parEnvironment
  CostCenter: 'MSDN'
  Owner: parOwner
}

var varNetworkWatcherRgName = 'NetworkWatcherRG'
// Derived from the location, so the template works in any region without changes
var varNetworkWatcherName = 'NetworkWatcher_${parLocation}'
var varFlowLogName = 'prod-skycraft-swc-vnet-flowlog'
var varConnectionMonitorName = 'skycraft-hub-spoke-cm'
var varTestConfigurationName = 'tcp-22-every-5m'

/*******************
*     Modules      *
*******************/

// The module re-declares the auto-provisioned Network Watcher (idempotent PUT, now with the canonical tags)
// and deploys the flow log and the connection monitor as its children
module modNetworkWatcher 'br/public:avm/res/network/network-watcher:0.5.1' = {
  name: 'network-monitoring-deployment'
  scope: resourceGroup(varNetworkWatcherRgName)
  params: {
    name: varNetworkWatcherName
    location: parLocation
    tags: varCommonTags
    // VNet flow log (NSG flow logs were retired in June 2025)
    flowLogs: [
      {
        name: varFlowLogName
        location: parLocation
        targetResourceId: parProdVnetResourceId
        storageResourceId: parStorageAccountResourceId
        enabled: true
        formatVersion: 2
        retentionInDays: parFlowLogRetentionDays
        workspaceResourceId: parWorkspaceResourceId
        trafficAnalyticsInterval: 10
      }
    ]
    // Hub-spoke SSH probe: prod auth VM -> dev auth VM, TCP/22 every 5 minutes
    connectionMonitors: [
      {
        name: varConnectionMonitorName
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
            name: varTestConfigurationName
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
            sources: ['prod-auth-source']
            destinations: ['dev-auth-destination']
            testConfigurations: [varTestConfigurationName]
          }
        ]
        workspaceResourceId: parWorkspaceResourceId
      }
    ]
  }
}

/******************
*     Outputs     *
******************/

@description('Resource ID of the Network Watcher')
output outNetworkWatcherId string = modNetworkWatcher.outputs.resourceId

@description('Resource ID of the VNet flow log')
output outFlowLogId string = '${modNetworkWatcher.outputs.resourceId}/flowLogs/${varFlowLogName}'

@description('Resource ID of the connection monitor')
output outConnectionMonitorId string = '${modNetworkWatcher.outputs.resourceId}/connectionMonitors/${varConnectionMonitorName}'
