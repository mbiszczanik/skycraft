/*=====================================================
SUMMARY: Backup Vault Module
DESCRIPTION: Deploys the Backup Vault (platform-skycraft-swc-bv) with LRS
             storage, system-assigned managed identity, and diagnostic settings
             routing backup reports to the central Log Analytics Workspace.
             The Blob Backup Policy (SkyCraft-Blob-Policy) is created by
             Deploy-Bicep.ps1 and the blob backup instance is configured by
             New-LabBlobBackup.ps1 because ARM PUT updates on existing policies
             are not supported (see docs/bicep-standards.md §9.4).
AUTHOR/S: SkyCraft
VERSION: 0.2.0
DEPLOYMENT: Internal use via Orchestrator
======================================================*/

/*******************
*    Parameters    *
*******************/

@description('Azure region for all resources.')
param parLocation string

@description('Resource ID of the Log Analytics Workspace for diagnostic settings.')
param parWorkspaceId string

@description('Environment tag value.')
param parEnvironment string = 'Platform'

/*******************
*    Variables     *
*******************/

var varCommonTags = {
  Project: 'SkyCraft'
  Environment: parEnvironment
  CostCenter: 'MSDN'
}

var varBvName = 'platform-skycraft-swc-bv'

/*******************
*    Resources     *
*******************/

resource resBackupVault 'Microsoft.DataProtection/backupVaults@2023-01-01' = {
  name: varBvName
  location: parLocation
  tags: varCommonTags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    storageSettings: [
      {
        datastoreType: 'VaultStore'
        type: 'LocallyRedundant'
      }
    ]
  }
}

// NOTE: The Blob Backup Policy (SkyCraft-Blob-Policy) is created by Deploy-Bicep.ps1
// because Azure Backup does not allow updating an existing policy via ARM PUT operations.
// On first deployment the script creates it; on subsequent runs it verifies it exists.

// Diagnostic settings → Log Analytics Workspace (resource-specific tables for Backup Reports)
resource resBvDiagSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  scope: resBackupVault
  name: 'bv-backup-reports-diag'
  properties: {
    workspaceId: parWorkspaceId
    logAnalyticsDestinationType: 'Dedicated'
    logs: [
      {
        category: 'CoreAzureBackup'
        enabled: true
      }
      {
        category: 'AddonAzureBackupJobs'
        enabled: true
      }
      {
        category: 'AddonAzureBackupPolicy'
        enabled: true
      }
      {
        category: 'AddonAzureBackupProtectedInstance'
        enabled: true
      }
    ]
  }
}

/******************
*     Outputs     *
******************/

@description('Resource ID of the Backup Vault.')
output outBvId string = resBackupVault.id

@description('Object ID of the Backup Vault system-assigned managed identity.')
output outBvPrincipalId string = resBackupVault.identity.principalId
