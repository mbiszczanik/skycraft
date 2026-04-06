/*=====================================================
SUMMARY: Recovery Services Vault Module
DESCRIPTION: Deploys the Recovery Services Vault (platform-skycraft-swc-rsv)
             with LRS storage redundancy (set post-deploy by Deploy-Bicep.ps1),
             soft delete enabled by default, and diagnostic settings routing
             backup reports to the central Log Analytics Workspace.
             The VM Backup Policy (SkyCraft-Daily-Prod) is created by
             Deploy-Bicep.ps1 because ARM PUT updates on existing policies are
             not supported (see docs/bicep-standards.md §9.4).
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

var varRsvName = 'platform-skycraft-swc-rsv'

/*******************
*    Resources     *
*******************/

// SkyCraft uses LRS to keep lab costs low; use GRS in production environments.
// Storage redundancy is set idempotently by Deploy-Bicep.ps1 (az backup vault backup-properties set)
// immediately after vault creation. The backupstorageconfig ARM sub-resource cannot be applied once
// the type is locked (after first backup), so PowerShell handles this to keep Bicep idempotent.
resource resRsv 'Microsoft.RecoveryServices/vaults@2023-06-01' = {
  name: varRsvName
  location: parLocation
  tags: varCommonTags
  sku: {
    name: 'RS0'
    tier: 'Standard'
  }
  properties: {
    publicNetworkAccess: 'Enabled'
  }
}

// NOTE: The VM Backup Policy (SkyCraft-Daily-Prod) is created by Deploy-Bicep.ps1
// because Azure Backup does not allow updating an existing policy via ARM PUT operations.
// On first deployment the script creates it; on subsequent runs it verifies it exists.

// Diagnostic settings → Log Analytics Workspace (resource-specific tables for Backup Reports)
resource resRsvDiagSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  scope: resRsv
  name: 'rsv-backup-reports-diag'
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
      {
        category: 'AzureBackupReport'
        enabled: true
      }
    ]
  }
}

/******************
*     Outputs     *
******************/

@description('Resource ID of the Recovery Services Vault.')
output outRsvId string = resRsv.id
