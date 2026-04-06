/*=====================================================
SUMMARY: Lab 5.2 - Business Continuity & Disaster Recovery - Orchestrator
DESCRIPTION: Orchestrates deployment of BCDR infrastructure for SkyCraft.
             Deploys a Recovery Services Vault for VM backup, a Backup Vault
             for Blob operational backup, and diagnostic settings routing
             backup reports to the central Log Analytics Workspace.
EXAMPLE: az deployment sub create --location swedencentral --template-file main.bicep --parameters parWorkspaceId=<LAW-resource-id>
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

@description('Resource ID of the Log Analytics Workspace for diagnostic settings (platform-skycraft-swc-law).')
param parWorkspaceId string

@description('Environment tag value applied to all BCDR resources.')
param parEnvironment string = 'Platform'

/*******************
*    Variables     *
*******************/

var varPlatformRgName = 'platform-skycraft-swc-rg'

/*******************
*    Resources     *
*******************/

// Reference the existing platform resource group (created in Module 1/2)
resource resPlatformRg 'Microsoft.Resources/resourceGroups@2023-07-01' existing = {
  name: varPlatformRgName
}

// ── Recovery Services Vault ────────────────────────────────────────────────
module modRecoveryServicesVault 'modules/recoveryServicesVault.bicep' = {
  name: 'bcdr-rsv-deployment'
  scope: resPlatformRg
  params: {
    parLocation: parLocation
    parWorkspaceId: parWorkspaceId
    parEnvironment: parEnvironment
  }
}

// ── Backup Vault ───────────────────────────────────────────────────────────
module modBackupVault 'modules/backupVault.bicep' = {
  name: 'bcdr-bv-deployment'
  scope: resPlatformRg
  params: {
    parLocation: parLocation
    parWorkspaceId: parWorkspaceId
    parEnvironment: parEnvironment
  }
}

/******************
*     Outputs     *
******************/

@description('Resource ID of the Recovery Services Vault.')
output outRsvId string = modRecoveryServicesVault.outputs.outRsvId

@description('Resource ID of the Backup Vault.')
output outBvId string = modBackupVault.outputs.outBvId

@description('Object ID of the Backup Vault system-assigned managed identity.')
output outBvPrincipalId string = modBackupVault.outputs.outBvPrincipalId
