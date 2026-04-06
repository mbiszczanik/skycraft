/*=====================================================
SUMMARY: Lab 5.1 - Monitoring Module
DESCRIPTION: Deploys all Azure Monitor resources for Lab 5.1:
             - Log Analytics Workspace (platform-skycraft-swc-law)
             - VM Insights Data Collection Rule (skycraft-vm-dcr)
             - Action Group (skycraft-ops-ag) with email notification
             - Metric Alert (skycraft-cpu-alert) for CPU > 80%
             - Storage Account Diagnostic Settings (skycraft-storage-diag)
NOTE: DCR Association (skycraft-vminsights-dcr-assoc) and Alert Processing
      Rule (skycraft-hours-apr) are created post-deployment by Deploy-Bicep.ps1
      (steps 5/6) due to runtime dependency on VM resource IDs.
AUTHOR/S: SkyCraft
VERSION: 0.1.0
DEPLOYMENT: [Internal use via Orchestrator]
======================================================*/

/*******************
*    Parameters    *
*******************/

@description('Azure region for all resources.')
param parLocation string = 'swedencentral'

@description('Environment tag value for the monitoring resources.')
param parEnvironment string = 'Platform'

@description('Email address for Action Group notifications.')
param parOpsEmail string

@description('Resource ID of the production VM to monitor with the CPU metric alert.')
param parProdVmResourceId string

@description('Resource ID of the platform storage account for diagnostic settings.')
param parStorageAccountResourceId string

/*******************
*    Variables     *
*******************/

var varCommonTags = {
  Project: 'SkyCraft'
  Environment: parEnvironment
  CostCenter: 'MSDN'
}

var varWorkspaceName = 'platform-skycraft-swc-law'
var varDcrName = 'skycraft-vm-dcr'
var varActionGroupName = 'skycraft-ops-ag'
var varAlertRuleName = 'skycraft-cpu-alert'
var varStorageDiagName = 'skycraft-storage-diag'
var varStorageAccountName = split(parStorageAccountResourceId, '/')[8]

resource resStorageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' existing = {
  name: varStorageAccountName
}

resource resStorageBlobService 'Microsoft.Storage/storageAccounts/blobServices@2023-05-01' existing = {
  parent: resStorageAccount
  name: 'default'
}

/*******************
*    Resources     *
*******************/

// ── 1. Log Analytics Workspace ──────────────────────────────────────────────
resource resWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: varWorkspaceName
  location: parLocation
  tags: varCommonTags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

// ── 2. VM Insights Data Collection Rule ─────────────────────────────────────
// Collects predefined VM Insights performance data and writes it to InsightsMetrics
resource resDcr 'Microsoft.Insights/dataCollectionRules@2023-03-11' = {
  name: varDcrName
  location: parLocation
  tags: varCommonTags
  kind: 'Linux'
  properties: {
    description: 'Data collection rule for VM Insights logs-based metrics (InsightsMetrics).'
    dataSources: {
      performanceCounters: [
        {
          name: 'VMInsightsPerfCounters'
          streams: [
            'Microsoft-InsightsMetrics'
          ]
          samplingFrequencyInSeconds: 60
          counterSpecifiers: [
            '\\VmInsights\\DetailedMetrics'
          ]
        }
      ]
      syslog: [
        {
          name: 'VMInsightsSyslog'
          streams: [
            'Microsoft-Syslog'
          ]
          facilityNames: [
            '*'
          ]
          logLevels: [
            '*'
          ]
        }
      ]
    }
    destinations: {
      logAnalytics: [
        {
          workspaceResourceId: resWorkspace.id
          name: 'VMInsightsPerf-Logs-Dest'
        }
      ]
    }
    dataFlows: [
      {
        streams: [
          'Microsoft-InsightsMetrics'
          'Microsoft-Syslog'
        ]
        destinations: [
          'VMInsightsPerf-Logs-Dest'
        ]
      }
    ]
  }
}

// ── 3. Action Group ──────────────────────────────────────────────────────────
resource resActionGroup 'Microsoft.Insights/actionGroups@2023-01-01' = {
  name: varActionGroupName
  location: 'global'
  tags: varCommonTags
  properties: {
    groupShortName: 'SkyCraftOps'
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

// ── 4. Metric Alert — CPU > 80% on prod VM ──────────────────────────────────
resource resAlertRule 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: varAlertRuleName
  location: 'global'
  tags: varCommonTags
  properties: {
    description: 'CPU > 80% on SkyCraft VM'
    severity: 2
    enabled: true
    scopes: [
      parProdVmResourceId
    ]
    evaluationFrequency: 'PT1M'
    windowSize: 'PT5M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'CPU_GT_80'
          criterionType: 'StaticThresholdCriterion'
          metricName: 'Percentage CPU'
          metricNamespace: 'Microsoft.Compute/virtualMachines'
          timeAggregation: 'Average'
          operator: 'GreaterThan'
          threshold: 80
        }
      ]
    }
    actions: [
      {
        actionGroupId: resActionGroup.id
      }
    ]
  }
}

// ── 5. Storage Account Diagnostic Settings ───────────────────────────────────
// Sends StorageRead and StorageWrite blob logs to the Log Analytics Workspace
resource resStorageDiag 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: varStorageDiagName
  scope: resStorageBlobService
  properties: {
    workspaceId: resWorkspace.id
    logs: [
      {
        category: 'StorageRead'
        enabled: true
        retentionPolicy: {
          enabled: false
          days: 0
        }
      }
      {
        category: 'StorageWrite'
        enabled: true
        retentionPolicy: {
          enabled: false
          days: 0
        }
      }
    ]
  }
}

/******************
*     Outputs     *
******************/

@description('Resource ID of the deployed Log Analytics Workspace.')
output outWorkspaceId string = resWorkspace.id

@description('Customer ID (GUID) for the Log Analytics Workspace.')
output outWorkspaceCustomerId string = resWorkspace.properties.customerId

@description('Resource ID of the VM Insights Data Collection Rule.')
output outDcrId string = resDcr.id

@description('Resource ID of the Action Group.')
output outActionGroupId string = resActionGroup.id

@description('Resource ID of the Metric Alert rule.')
output outAlertRuleId string = resAlertRule.id
