/*=====================================================
SUMMARY: Lab 5.2 - Business Continuity & Disaster Recovery - Orchestrator
DESCRIPTION: Deploys the SkyCraft BCDR vaults into platform-skycraft-swc-rg through Azure Verified Modules - the Recovery Services Vault for VM backup (LRS, platform-enforced AlwaysON soft delete, backup-report diagnostics) and the Backup Vault for blob backup (LRS, system-assigned identity) - plus the Backup Vault's diagnostic setting through a local fallback module, and the tagged resource group that holds the VM's instant-restore snapshots. Backup policies are created by Deploy-Bicep.ps1 (docs/bicep-standards.md section 10.4)
EXAMPLE: .\scripts\Deploy-Bicep.ps1
AUTHOR/S: Marcin Biszczanik
VERSION: 2.1.0
DEPLOYMENT: .\scripts\Deploy-Bicep.ps1
======================================================*/

targetScope = 'subscription'

/*******************
*    Parameters    *
*******************/

@description('Location for all resources')
@allowed(['swedencentral', 'northeurope'])
param parLocation string = 'swedencentral'

@description('Environment tag value applied to all BCDR resources')
@allowed(['Platform', 'Development', 'Production'])
param parEnvironment string = 'Platform'

@description('Resource owner tag value')
@minLength(1)
param parOwner string = 'mbiszczanik'

@description('Resource ID of the Log Analytics workspace that receives the backup reports (platform-skycraft-swc-law from Lab 5.1)')
@minLength(1)
param parWorkspaceId string

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
var varRsvName = 'platform-skycraft-swc-rsv'
var varBvName = 'platform-skycraft-swc-bv'
var varRsvDiagName = 'rsv-backup-reports-diag'
var varBvDiagName = 'bv-backup-reports-diag'

// Instant-restore snapshot group. Azure Backup names it <prefix><n><suffix> with n starting at 1,
// so the VM backup policy carries the prefix and suffix and this template creates the n = 1 group.
var varSnapshotRgPrefix = 'platform-skycraft-swc-rpc'
var varSnapshotRgSuffix = '-rg'
var varSnapshotRgName = '${varSnapshotRgPrefix}1${varSnapshotRgSuffix}'

// Resource-specific Backup Reports tables shared by both vault types. The Recovery Services Vault
// additionally emits AddonAzureBackupStorage and AzureBackupOperations - Backup Reports needs all six.
// The legacy AzureBackupReport event is left out: it flows only in AzureDiagnostics mode, never to Dedicated tables.
var varBackupLogCategories = [
  'CoreAzureBackup'
  'AddonAzureBackupJobs'
  'AddonAzureBackupPolicy'
  'AddonAzureBackupProtectedInstance'
]

var varRsvLogCategoriesAndGroups = [
  for category in concat(varBackupLogCategories, ['AddonAzureBackupStorage', 'AzureBackupOperations']): {
    category: category
  }
]

/*******************
*     Modules      *
*******************/

// 1. Recovery Services Vault - Azure VM backup. The VM backup policy (SkyCraft-Daily-Prod) and the
//    protected item are created by Deploy-Bicep.ps1, because Azure Backup rejects ARM PUT updates on
//    an existing policy (docs/bicep-standards.md section 10.4).
module modRecoveryServicesVault 'br/public:avm/res/recovery-services/vault:0.13.0' = {
  name: 'bcdr-rsv-deployment'
  scope: resourceGroup(varPlatformRgName)
  params: {
    name: varRsvName
    location: parLocation
    tags: varCommonTags
    // Lab-friction override (docs/bicep-standards.md section 4.5): the module defaults public network
    // access to Disabled, which blocks Azure VM backup without private endpoints.
    publicNetworkAccess: 'Enabled'
    // softDeleteSettings is deliberately not set. Azure Backup "secure by default" enforces soft delete
    // on every new Recovery Services Vault platform-side: the vault is created with softDeleteState and
    // enhancedSecurityState = AlwaysON at the default 14-day retention, and sending any other value is
    // rejected with BMSUserErrorSoftDeleteStateNotSetToAlwaysON. Teardown is unaffected - a vault holding
    // only soft-deleted items can be deleted and is itself soft-deleted at no cost (section 4.5).
    // SkyCraft uses LRS to keep lab costs low; production would use GeoRedundant. Declared at creation
    // because the redundancy is locked once the first backup is stored (section 10.5).
    redundancySettings: {
      standardTierStorageRedundancy: 'LocallyRedundant'
    }
    diagnosticSettings: [
      {
        name: varRsvDiagName
        workspaceResourceId: parWorkspaceId
        logAnalyticsDestinationType: 'Dedicated'
        logCategoriesAndGroups: varRsvLogCategoriesAndGroups
        metricCategories: []
      }
    ]
  }
}

// 2. Backup Vault - operational blob backup. The blob backup policy (SkyCraft-Blob-Policy) is created by
//    Deploy-Bicep.ps1 and the backup instance by New-LabBlobBackup.ps1 (section 10.4).
module modBackupVault 'br/public:avm/res/data-protection/backup-vault:0.13.2' = {
  name: 'bcdr-bv-deployment'
  scope: resourceGroup(varPlatformRgName)
  params: {
    name: varBvName
    location: parLocation
    tags: varCommonTags
    type: 'LocallyRedundant'
    dataStoreType: 'VaultStore'
    managedIdentities: {
      systemAssigned: true
    }
    // Lab-friction override (section 4.5): soft delete off, so Remove-LabResource.ps1 can delete the
    // blob backup instance and the vault in one pass.
    softDeleteSettings: {
      state: 'Off'
      retentionDurationInDays: 14
    }
  }
}

// 3. Backup Vault diagnostics - local fallback module (section 4.3): the backup-vault AVM module has no
//    diagnosticSettings parameter and avm/res/insights/diagnostic-setting is subscription-scope only
module modBackupVaultDiagnostics 'modules/backup-vault-diagnostics.bicep' = {
  name: 'bcdr-bv-diag-deployment'
  scope: resourceGroup(varPlatformRgName)
  params: {
    parBackupVaultName: modBackupVault.outputs.name
    parDiagnosticSettingName: varBvDiagName
    parWorkspaceResourceId: parWorkspaceId
    parLogCategories: varBackupLogCategories
  }
}

// 4. Instant-restore snapshot resource group. Without one named in the VM backup policy, Azure Backup
//    creates AzureBackupRG_<region>_<n> itself, untagged, and Lab 1.3's Require-Environment-Tag-RG
//    denies it - every backup then fails with UserErrorRequestDisallowedByPolicy (issue #184).
//    Deliberately not platform-skycraft-swc-rg and deliberately unlocked: Lab 1.3 locks that group
//    CanNotDelete, and a lock on the snapshot group blocks restore-point garbage collection
//    (UserErrorRpCollectionLimitReached).
module modSnapshotResourceGroup 'br/public:avm/res/resources/resource-group:0.4.4' = {
  name: 'bcdr-snapshot-rg-deployment'
  params: {
    name: varSnapshotRgName
    location: parLocation
    tags: varCommonTags
  }
}

/******************
*     Outputs     *
******************/

@description('Resource ID of the Recovery Services Vault')
output outRsvId string = modRecoveryServicesVault.outputs.resourceId

@description('Resource ID of the Backup Vault')
output outBvId string = modBackupVault.outputs.resourceId

@description('Object ID of the Backup Vault system-assigned managed identity')
output outBvPrincipalId string = modBackupVault.outputs.?systemAssignedMIPrincipalId ?? ''

@description('Name of the instant-restore snapshot resource group')
output outSnapshotRgName string = modSnapshotResourceGroup.outputs.name

@description('Snapshot resource group name prefix for the VM backup policy (Azure Backup appends the number)')
output outSnapshotRgPrefix string = varSnapshotRgPrefix

@description('Snapshot resource group name suffix for the VM backup policy')
output outSnapshotRgSuffix string = varSnapshotRgSuffix
