/*=====================================================
SUMMARY: Lab 5.1 - Storage Blob Diagnostics (local fallback module)
DESCRIPTION: Attaches a diagnostic setting to the blob service of an existing storage account and streams the selected log categories to a Log Analytics workspace. Local fallback per docs/bicep-standards.md section 4.3 - avm/res/insights/diagnostic-setting is a subscription-scope module and cannot target a resource
AUTHOR/S: Marcin Biszczanik
VERSION: 1.0.0
DEPLOYMENT: [Internal use via Orchestrator]
======================================================*/

targetScope = 'resourceGroup'

/*******************
*    Parameters    *
*******************/

@description('Name of the existing storage account whose blob service is monitored')
@minLength(3)
@maxLength(24)
param parStorageAccountName string

@description('Name of the diagnostic setting')
@minLength(1)
@maxLength(260)
param parDiagnosticSettingName string

@description('Resource ID of the Log Analytics workspace that receives the logs')
@minLength(1)
param parWorkspaceResourceId string

@description('Blob service log categories to stream')
@minLength(1)
param parLogCategories array = ['StorageRead', 'StorageWrite']

/*******************
*     Existing     *
*******************/

resource resStorageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' existing = {
  name: parStorageAccountName

  resource resBlobService 'blobServices' existing = {
    name: 'default'
  }
}

/*******************
*    Resources     *
*******************/

resource resDiagnosticSetting 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: parDiagnosticSettingName
  scope: resStorageAccount::resBlobService
  properties: {
    workspaceId: parWorkspaceResourceId
    logs: [
      for category in parLogCategories: {
        category: category
        enabled: true
      }
    ]
  }
}

/******************
*     Outputs     *
******************/

@description('Resource ID of the diagnostic setting')
output outDiagnosticSettingId string = resDiagnosticSetting.id
