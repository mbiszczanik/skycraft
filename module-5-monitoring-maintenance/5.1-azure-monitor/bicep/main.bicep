/*=====================================================
SUMMARY: Lab 5.1 - Azure Monitor & Insights - Orchestrator
DESCRIPTION: Deploys the SkyCraft monitoring hub into platform-skycraft-swc-rg through Azure Verified Modules - the Log Analytics workspace, the VM Insights data collection rule, the operations action group and the CPU metric alert - plus the platform storage account's blob diagnostic setting through a local fallback module
EXAMPLE: .\scripts\Deploy-Bicep.ps1 -OpsEmail ops@example.com
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

@description('Environment tag value for the monitoring resources')
@allowed(['Platform', 'Development', 'Production'])
param parEnvironment string = 'Platform'

@description('Resource owner tag value')
@minLength(1)
param parOwner string = 'mbiszczanik'

@description('Email address for the operations action group notifications')
@minLength(3)
param parOpsEmail string

@description('Resource ID of the VM the CPU metric alert is scoped to (Deploy-Bicep.ps1 resolves it at run time)')
@minLength(1)
param parProdVmResourceId string

@description('Resource ID of the platform storage account whose blob service streams StorageRead/StorageWrite logs to the workspace')
@minLength(1)
param parStorageAccountResourceId string

@description('Log Analytics data retention in days')
@minValue(30)
@maxValue(730)
param parRetentionInDays int = 30

@description('CPU percentage threshold that fires the metric alert')
@minValue(1)
@maxValue(100)
param parCpuThreshold int = 80

/*******************
*    Variables     *
*******************/

var varCommonTags = {
  Project: 'SkyCraft'
  Environment: parEnvironment
  CostCenter: 'MSDN'
  Owner: parOwner
}

var varPlatformRgName = 'platform-skycraft-swc-rg'
var varWorkspaceName = 'platform-skycraft-swc-law'
var varDcrName = 'skycraft-vm-dcr'
var varDcrDestinationName = 'VMInsightsPerf-Logs-Dest'
var varActionGroupName = 'skycraft-ops-ag'
var varAlertRuleName = 'skycraft-cpu-alert'
var varStorageDiagName = 'skycraft-storage-diag'

// The storage account lives wherever its resource ID says (Lab 4.1 puts the platform account in the platform group)
var varStorageAccountRgName = split(parStorageAccountResourceId, '/')[4]
var varStorageAccountName = split(parStorageAccountResourceId, '/')[8]

/*******************
*     Modules      *
*******************/

// 1. Log Analytics workspace - the central sink for Labs 5.1-5.3
module modWorkspace 'br/public:avm/res/operational-insights/workspace:0.16.1' = {
  name: 'law-deployment'
  scope: resourceGroup(varPlatformRgName)
  params: {
    name: varWorkspaceName
    location: parLocation
    tags: varCommonTags
    skuName: 'PerGB2018'
    dataRetention: parRetentionInDays
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

// 2. VM Insights data collection rule (the association with the VM is created by Deploy-Bicep.ps1,
//    because the VM resource ID is only known at run time)
module modDcr 'br/public:avm/res/insights/data-collection-rule:0.11.0' = {
  name: 'dcr-deployment'
  scope: resourceGroup(varPlatformRgName)
  params: {
    name: varDcrName
    location: parLocation
    tags: varCommonTags
    dataCollectionRuleProperties: {
      kind: 'Linux'
      description: 'Data collection rule for VM Insights logs-based metrics (InsightsMetrics).'
      dataSources: {
        performanceCounters: [
          {
            name: 'VMInsightsPerfCounters'
            streams: ['Microsoft-InsightsMetrics']
            samplingFrequencyInSeconds: 60
            counterSpecifiers: ['\\VmInsights\\DetailedMetrics']
          }
        ]
        syslog: [
          {
            name: 'VMInsightsSyslog'
            streams: ['Microsoft-Syslog']
            facilityNames: ['*']
            logLevels: ['*']
          }
        ]
      }
      destinations: {
        logAnalytics: [
          {
            workspaceResourceId: modWorkspace.outputs.resourceId
            name: varDcrDestinationName
          }
        ]
      }
      dataFlows: [
        {
          streams: ['Microsoft-InsightsMetrics', 'Microsoft-Syslog']
          destinations: [varDcrDestinationName]
        }
      ]
    }
  }
}

// 3. Operations action group - e-mail notification
module modActionGroup 'br/public:avm/res/insights/action-group:0.8.0' = {
  name: 'ag-deployment'
  scope: resourceGroup(varPlatformRgName)
  params: {
    name: varActionGroupName
    groupShortName: 'SkyCraftOps'
    location: 'global'
    tags: varCommonTags
    enabled: true
    emailReceivers: [
      {
        name: 'ops-email'
        emailAddress: parOpsEmail
        useCommonAlertSchema: true
      }
    ]
  }
}

// 4. Metric alert - CPU above the threshold on the monitored VM
module modCpuAlert 'br/public:avm/res/insights/metric-alert:0.4.1' = {
  name: 'alert-deployment'
  scope: resourceGroup(varPlatformRgName)
  params: {
    name: varAlertRuleName
    location: 'global'
    tags: varCommonTags
    alertDescription: 'CPU > ${parCpuThreshold}% on SkyCraft VM'
    severity: 2
    enabled: true
    scopes: [parProdVmResourceId]
    evaluationFrequency: 'PT1M'
    windowSize: 'PT5M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allof: [
        {
          name: 'CPU_GT_80'
          criterionType: 'StaticThresholdCriterion'
          metricName: 'Percentage CPU'
          metricNamespace: 'Microsoft.Compute/virtualMachines'
          timeAggregation: 'Average'
          operator: 'GreaterThan'
          threshold: parCpuThreshold
        }
      ]
    }
    actions: [modActionGroup.outputs.resourceId]
  }
}

// 5. Platform storage account blob diagnostics - local fallback module (docs/bicep-standards.md section 4.3):
//    avm/res/insights/diagnostic-setting is subscription-scope only and cannot target a resource
module modStorageDiagnostics 'modules/storage-blob-diagnostics.bicep' = {
  name: 'storage-diag-deployment'
  scope: resourceGroup(varStorageAccountRgName)
  params: {
    parStorageAccountName: varStorageAccountName
    parDiagnosticSettingName: varStorageDiagName
    parWorkspaceResourceId: modWorkspace.outputs.resourceId
  }
}

/******************
*     Outputs     *
******************/

@description('Resource ID of the Log Analytics workspace')
output outWorkspaceId string = modWorkspace.outputs.resourceId

@description('Customer ID (workspace GUID) of the Log Analytics workspace')
output outWorkspaceCustomerId string = modWorkspace.outputs.logAnalyticsWorkspaceId

@description('Resource ID of the VM Insights data collection rule')
output outDcrId string = modDcr.outputs.resourceId

@description('Resource ID of the action group')
output outActionGroupId string = modActionGroup.outputs.resourceId

@description('Resource ID of the metric alert rule')
output outAlertRuleId string = modCpuAlert.outputs.resourceId

@description('Resource ID of the storage blob diagnostic setting')
output outStorageDiagnosticSettingId string = modStorageDiagnostics.outputs.outDiagnosticSettingId
