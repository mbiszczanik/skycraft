/*=====================================================
SUMMARY: Lab 5.2 - Backup Vault Diagnostics (local fallback module)
DESCRIPTION: Attaches a diagnostic setting to an existing Backup Vault and streams the Backup Reports log categories to a Log Analytics workspace (resource-specific tables). Local fallback per docs/bicep-standards.md section 4.3 - avm/res/data-protection/backup-vault has no diagnosticSettings parameter and avm/res/insights/diagnostic-setting is subscription-scope only
AUTHOR/S: Marcin Biszczanik
VERSION: 1.0.0
DEPLOYMENT: [Internal use via Orchestrator]
======================================================*/

targetScope = 'resourceGroup'

/*******************
*    Parameters    *
*******************/

@description('Name of the existing Backup Vault')
@minLength(2)
@maxLength(50)
param parBackupVaultName string

@description('Name of the diagnostic setting')
@minLength(1)
@maxLength(260)
param parDiagnosticSettingName string

@description('Resource ID of the Log Analytics workspace that receives the logs')
@minLength(1)
param parWorkspaceResourceId string

@description('Backup Reports log categories to stream')
@minLength(1)
param parLogCategories array

/*******************
*     Existing     *
*******************/

resource resBackupVault 'Microsoft.DataProtection/backupVaults@2024-04-01' existing = {
  name: parBackupVaultName
}

/*******************
*    Resources     *
*******************/

resource resDiagnosticSetting 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: parDiagnosticSettingName
  scope: resBackupVault
  properties: {
    workspaceId: parWorkspaceResourceId
    logAnalyticsDestinationType: 'Dedicated'
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
