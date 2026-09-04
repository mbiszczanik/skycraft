<#
.SYNOPSIS
    Removes Lab 5.2 Business Continuity & Disaster Recovery resources.

.DESCRIPTION
    Cleans up Lab 5.2 BCDR resources in the correct dependency order:
    1. Blob backup instances (Backup Vault)
    2. RBAC role assignments granted to the Backup Vault identity on the storage account
       (Storage Blob Data Owner, Storage Account Backup Contributor)
    3. Backup Vault (platform-skycraft-swc-bv)
    4. VM backup protection item with data deletion
    5. Recovery Services Vault (platform-skycraft-swc-rsv)
    6. Orphaned Azure Backup restore point collections and the AzureBackupRG_<location>_*
       resource groups that held them, once those groups are empty

    Notes:
    - The role assignments are removed before the Backup Vault so its managed
      identity is still resolvable; otherwise they would be orphaned on the
      storage account after the vault (and its identity) is deleted.
    - Azure Site Recovery resources (ASR fabric, replication, cache storage
      account) must be cleaned up manually via the Azure Portal before
      deleting the Recovery Services Vault.
    - VMs and Storage Accounts from earlier labs are NOT removed by this script.

    Every step continues on error, so a single stuck resource does not strand the rest. A step
    that fails is reported as [ERROR] with the Azure error message and counted; if any step
    failed the script exits 1 - so a masked failure cannot be mistaken for a clean cleanup.

    Each non-zero exit is paired with $Host.SetShouldExit: a bare "exit 1" is dropped under
    "pwsh -File" for any script that declares #Requires -Modules for a module it has to
    auto-import, and the process would exit 0 with the failure still on screen (issue #104).
    A caller that dot-sources this script, or runs "& .\Remove-LabResource.ps1" with further
    statements after it, still ends with its own exit code rather than this one.

.PARAMETER Force
    Skip confirmation prompts.

.EXAMPLE
    .\Remove-LabResource.ps1

.EXAMPLE
    .\Remove-LabResource.ps1 -Force

.NOTES
    Project: SkyCraft
    Lab: 5.2 - Business Continuity & Disaster Recovery
    Version: 1.1.0
    Date: 2026-08-29
#>

#Requires -Version 7.0
#Requires -Modules Az.Accounts, Az.RecoveryServices, Az.DataProtection, Az.Resources, Az.Storage

[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter()]
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
if ($Force) { $ConfirmPreference = 'None' }

$platformRg     = 'platform-skycraft-swc-rg'
$prodRg         = 'prod-skycraft-swc-rg'
$rsvName        = 'platform-skycraft-swc-rsv'
$bvName         = 'platform-skycraft-swc-bv'
$storageAccount = 'prodskycraftswcsa'
$location       = 'swedencentral'

# Minimum Az.RecoveryServices for the one-pass vault delete (see the prerequisite check below).
$rsvMinModuleVersion = [version]'7.5.0'

# Counts resources that exist but could not be deleted. Absent resources are not failures.
$script:cleanupFailures = 0

# Roles granted to the Backup Vault identity by New-LabBlobBackup.ps1 (must be revoked here)
$backupRoles = @(
    @{ Name = 'Storage Blob Data Owner';            RoleId = 'b7e6dc6d-f1e8-4753-8033-0f276bb0955b' },
    @{ Name = 'Storage Account Backup Contributor'; RoleId = 'e5e2a7ff-d759-4cd2-bb51-3152d37e2eb1' }
)

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  Lab 5.2 - Resource Cleanup" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

$context = Get-AzContext
if (-not $context) {
    Write-Host "  [ERROR] Not logged into Azure. Run 'Connect-AzAccount' first." -ForegroundColor Red
    $Host.SetShouldExit(1)
    exit 1
}

# Azure Backup "secure by default" keeps soft delete AlwaysON on every new Recovery Services
# Vault, so step 5 deletes a vault that still holds soft-deleted items. That works in a single
# pass - but only on Azure CLI 2.75.0+ / Az PowerShell 7.5.0+ (Az.RecoveryServices 7.5.0);
# older tooling insists on a fully empty vault and reintroduces the 14-day wait. Diagnose a
# stale module here, before the delete is attempted, and still run the teardown: refusing to
# clean up over a warning would strand billable resources.
$rsvModuleVersion = (Get-Module -ListAvailable -Name Az.RecoveryServices |
                     Sort-Object Version -Descending |
                     Select-Object -First 1).Version
if ($rsvModuleVersion -and $rsvModuleVersion -ge $rsvMinModuleVersion) {
    Write-Host "  ✓ Az.RecoveryServices version: $rsvModuleVersion" -ForegroundColor Green
} else {
    Write-Host "  [WARNING] Az.RecoveryServices $rsvModuleVersion is older than $rsvMinModuleVersion." -ForegroundColor Yellow
    Write-Host "    Deleting a vault that holds soft-deleted items needs Azure CLI 2.75.0+ or" -ForegroundColor Gray
    Write-Host "    Az PowerShell 7.5.0+. Older versions require a fully empty vault and" -ForegroundColor Gray
    Write-Host "    reintroduce the 14-day soft-delete wait. Run: Update-Module Az.RecoveryServices" -ForegroundColor Gray
}

# ── Inventory existing resources ──────────────────────────────────────────
Write-Host "`nChecking resources to delete..." -ForegroundColor Yellow

$resourcesToDelete = [System.Collections.Generic.List[hashtable]]::new()

$bvExists = Get-AzDataProtectionBackupVault -ResourceGroupName $platformRg -VaultName $bvName -ErrorAction SilentlyContinue
if ($bvExists) {
    $instances = Get-AzDataProtectionBackupInstance -ResourceGroupName $platformRg -VaultName $bvName -ErrorAction SilentlyContinue
    foreach ($inst in $instances) {
        $resourcesToDelete.Add(@{ Type = 'BlobInstance'; Name = $inst.Name })
        Write-Host "  - Blob Backup Instance: $($inst.Name)" -ForegroundColor Gray
    }

    # Plan removal of the RBAC roles granted to the BV identity on the storage account.
    # Resolve the principalId now, while the vault (and its identity) still exists.
    $bvPrincipalId = $bvExists.IdentityPrincipalId
    $storage = Get-AzStorageAccount -ResourceGroupName $prodRg -Name $storageAccount -ErrorAction SilentlyContinue
    if ($bvPrincipalId -and $storage) {
        foreach ($role in $backupRoles) {
            $resourcesToDelete.Add(@{
                Type        = 'RoleAssignment'
                Name        = $role.Name
                RoleId      = $role.RoleId
                PrincipalId = $bvPrincipalId
                Scope       = $storage.Id
            })
            Write-Host "  - RBAC role assignment: $($role.Name) on $storageAccount" -ForegroundColor Gray
        }
    }

    $resourcesToDelete.Add(@{ Type = 'BackupVault'; Name = $bvName })
    Write-Host "  - Backup Vault: $bvName" -ForegroundColor Gray
}

$rsvExists = Get-AzRecoveryServicesVault -ResourceGroupName $platformRg -Name $rsvName -ErrorAction SilentlyContinue
if ($rsvExists) {
    $vmItems = Get-AzRecoveryServicesBackupItem -VaultId $rsvExists.ID -BackupManagementType AzureVM -WorkloadType AzureVM -ErrorAction SilentlyContinue
    if ($vmItems -and @($vmItems).Count -gt 0) {
        foreach ($item in $vmItems) {
            # FriendlyName comes back empty for some protected VMs, which left the progress
            # lines and the ShouldProcess target blank during the live v0.8.0 verification.
            # The container name carries the VM name as its last ';'-separated segment.
            $displayName = if ($item.FriendlyName) {
                $item.FriendlyName
            } elseif ($item.ContainerName) {
                ($item.ContainerName -split ';')[-1]
            } else {
                $item.Name
            }
            $resourcesToDelete.Add(@{
                Type          = 'VmBackupItem'
                Name          = $item.Name
                ContainerName = $item.ContainerName
                FriendlyName  = $displayName
                Item          = $item
            })
            Write-Host "  - VM Backup Item: $displayName" -ForegroundColor Gray
        }
    }
    $resourcesToDelete.Add(@{ Type = 'RSV'; Name = $rsvName })
    Write-Host "  - Recovery Services Vault: $rsvName" -ForegroundColor Gray
}

# Azure Backup provisions AzureBackupRG_<location>_<n> next to the protected VM and parks a
# Microsoft.Compute/restorePointCollections container in it for instant-restore snapshots.
# Disabling protection releases the snapshots, but the (now empty) container and its resource
# group outlive the vault and had to be deleted by hand after the v0.8.0 cycle (#105).
$backupRgCandidates = Get-AzResourceGroup -ErrorAction SilentlyContinue |
                      Where-Object { $_.ResourceGroupName -like "AzureBackupRG_${location}_*" }
foreach ($backupRg in $backupRgCandidates) {
    $rgName      = $backupRg.ResourceGroupName
    $rgResources = @(Get-AzResource -ResourceGroupName $rgName -ErrorAction SilentlyContinue)

    # Only SkyCraft's own collections: the group is shared, and an unrelated protected VM's
    # collection must survive this teardown.
    $rpcs = @($rgResources | Where-Object {
        $_.ResourceType -eq 'Microsoft.Compute/restorePointCollections' -and
        $_.Name -like 'AzureBackup_*skycraft*'
    })
    foreach ($rpc in $rpcs) {
        $resourcesToDelete.Add(@{
            Type              = 'RestorePointCollection'
            Name              = $rpc.Name
            ResourceGroupName = $rgName
            ResourceId        = $rpc.ResourceId
        })
        Write-Host "  - Restore point collection: $($rpc.Name) (in $rgName)" -ForegroundColor Gray
    }

    # The group itself is only deleted if it is left empty once those collections are gone.
    if ($rpcs.Count -gt 0 -or $rgResources.Count -eq 0) {
        $resourcesToDelete.Add(@{ Type = 'BackupResourceGroup'; Name = $rgName })
        Write-Host "  - Azure Backup resource group: $rgName (deleted only if left empty)" -ForegroundColor Gray
    }
}

if ($resourcesToDelete.Count -eq 0) {
    Write-Host "`nNo Lab 5.2 resources found to delete." -ForegroundColor Green
    exit 0
}

# ── Confirm deletion (per-operation via ShouldProcess; pass -Force or -Confirm:$false to skip) ──
Write-Host "`n[WARNING] This will permanently delete the above resources." -ForegroundColor Yellow
Write-Host "  Ensure ASR replication has been removed via Azure Portal first." -ForegroundColor Gray
Write-Host "  VMs, VNets, and Storage Accounts will NOT be deleted." -ForegroundColor Gray

Write-Host "`nDeleting resources..." -ForegroundColor Yellow

# 1. Delete Blob Backup Instances
foreach ($r in $resourcesToDelete | Where-Object { $_.Type -eq 'BlobInstance' }) {
    if (-not $PSCmdlet.ShouldProcess($r.Name, 'Delete blob backup instance')) { continue }
    Write-Host "  Deleting Blob Backup Instance: $($r.Name)..." -ForegroundColor Gray
    try {
        Remove-AzDataProtectionBackupInstance `
            -ResourceGroupName $platformRg `
            -VaultName $bvName `
            -Name $r.Name | Out-Null
        Write-Host "  ✓ Deleted" -ForegroundColor Green
    } catch {
        $script:cleanupFailures++
        Write-Host "  [ERROR] Could not delete blob backup instance '$($r.Name)': $_" -ForegroundColor Red
    }
}

# 2. Remove RBAC role assignments granted to the BV identity (before deleting the vault,
#    so the managed identity is still resolvable and no orphaned assignments remain).
foreach ($r in $resourcesToDelete | Where-Object { $_.Type -eq 'RoleAssignment' }) {
    if (-not $PSCmdlet.ShouldProcess("$($r.Name) -> $storageAccount", 'Remove role assignment')) { continue }
    Write-Host "  Removing role assignment '$($r.Name)' on $storageAccount..." -ForegroundColor Gray
    try {
        $existing = Get-AzRoleAssignment -ObjectId $r.PrincipalId -RoleDefinitionId $r.RoleId -Scope $r.Scope -ErrorAction SilentlyContinue
        if ($existing) {
            Remove-AzRoleAssignment -ObjectId $r.PrincipalId -RoleDefinitionId $r.RoleId -Scope $r.Scope -ErrorAction Stop | Out-Null
            Write-Host "  ✓ Removed role assignment: $($r.Name)" -ForegroundColor Green
        } else {
            Write-Host "  ✓ Role assignment already absent: $($r.Name)" -ForegroundColor Green
        }
    } catch {
        $script:cleanupFailures++
        Write-Host "  [ERROR] Could not remove role assignment '$($r.Name)': $_" -ForegroundColor Red
    }
}

# 3. Delete Backup Vault
foreach ($r in $resourcesToDelete | Where-Object { $_.Type -eq 'BackupVault' }) {
    if (-not $PSCmdlet.ShouldProcess($r.Name, 'Delete backup vault')) { continue }
    Write-Host "  Deleting Backup Vault: $($r.Name)..." -ForegroundColor Gray
    try {
        Remove-AzDataProtectionBackupVault `
            -ResourceGroupName $platformRg `
            -VaultName $r.Name | Out-Null
        Write-Host "  ✓ Deleted" -ForegroundColor Green
    } catch {
        $script:cleanupFailures++
        Write-Host "  [ERROR] Could not delete Backup Vault '$($r.Name)': $_" -ForegroundColor Red
    }
}

# 4. Disable VM backup protection and delete backup data
foreach ($r in $resourcesToDelete | Where-Object { $_.Type -eq 'VmBackupItem' }) {
    if (-not $PSCmdlet.ShouldProcess($r.FriendlyName, 'Disable VM backup protection and delete backup data')) { continue }
    Write-Host "  Disabling VM backup protection: $($r.FriendlyName)..." -ForegroundColor Gray
    try {
        Disable-AzRecoveryServicesBackupProtection `
            -Item $r.Item `
            -VaultId $rsvExists.ID `
            -RemoveRecoveryPoints `
            -Force | Out-Null
        Write-Host "  ✓ Protection disabled and backup data deleted" -ForegroundColor Green
    } catch {
        $script:cleanupFailures++
        Write-Host "  [ERROR] Could not disable backup protection for '$($r.FriendlyName)': $_" -ForegroundColor Red
        Write-Host "    Manual cleanup may be required via Azure Portal." -ForegroundColor Gray
    }
}

# 5. Delete Recovery Services Vault
foreach ($r in $resourcesToDelete | Where-Object { $_.Type -eq 'RSV' }) {
    if (-not $PSCmdlet.ShouldProcess($r.Name, 'Delete Recovery Services Vault')) { continue }
    Write-Host "  Deleting Recovery Services Vault: $($r.Name)..." -ForegroundColor Gray
    try {
        Remove-AzRecoveryServicesVault -Vault $rsvExists | Out-Null
        Write-Host "  ✓ Deleted" -ForegroundColor Green
    } catch {
        $script:cleanupFailures++
        Write-Host "  [ERROR] Could not delete RSV '$($r.Name)': $_" -ForegroundColor Red
        Write-Host "    Most likely cause is stale tooling: deleting a vault that still holds" -ForegroundColor Gray
        Write-Host "    soft-deleted items needs Azure CLI 2.75.0+ or Az PowerShell 7.5.0+" -ForegroundColor Gray
        Write-Host "    (Az.RecoveryServices $rsvMinModuleVersion+). Older versions require a fully" -ForegroundColor Gray
        Write-Host "    empty vault and reintroduce the 14-day soft-delete wait." -ForegroundColor Gray
        Write-Host "    Otherwise the vault still has dependencies this script does not touch:" -ForegroundColor Gray
        Write-Host "    ASR replicated items, registered storage accounts, or private endpoints." -ForegroundColor Gray
    }
}

# 6. Delete the orphaned Azure Backup restore point collections and, once they are gone, the
#    AzureBackupRG_<location>_* groups that held them.
foreach ($r in $resourcesToDelete | Where-Object { $_.Type -eq 'RestorePointCollection' }) {
    if (-not $PSCmdlet.ShouldProcess($r.Name, 'Delete orphaned restore point collection')) { continue }
    Write-Host "  Deleting restore point collection: $($r.Name)..." -ForegroundColor Gray
    try {
        Remove-AzResource -ResourceId $r.ResourceId -Force -ErrorAction Stop | Out-Null
        Write-Host "  ✓ Deleted" -ForegroundColor Green
    } catch {
        $script:cleanupFailures++
        Write-Host "  [ERROR] Could not delete restore point collection '$($r.Name)': $_" -ForegroundColor Red
    }
}

foreach ($r in $resourcesToDelete | Where-Object { $_.Type -eq 'BackupResourceGroup' }) {
    # Re-check emptiness: the group is shared infrastructure and Azure recreates it on demand,
    # so it is only removed when nothing is left in it.
    $remaining = @(Get-AzResource -ResourceGroupName $r.Name -ErrorAction SilentlyContinue)
    if ($remaining.Count -gt 0) {
        Write-Host "  [INFO] $($r.Name) still holds $($remaining.Count) resource(s) - left in place." -ForegroundColor Gray
        continue
    }
    if (-not $PSCmdlet.ShouldProcess($r.Name, 'Delete empty Azure Backup resource group')) { continue }
    Write-Host "  Deleting empty Azure Backup resource group: $($r.Name)..." -ForegroundColor Gray
    try {
        Remove-AzResourceGroup -Name $r.Name -Force -ErrorAction Stop | Out-Null
        Write-Host "  ✓ Deleted" -ForegroundColor Green
    } catch {
        $script:cleanupFailures++
        Write-Host "  [ERROR] Could not delete resource group '$($r.Name)': $_" -ForegroundColor Red
    }
}

Write-Host "`n========================================" -ForegroundColor Cyan
if ($script:cleanupFailures -gt 0) {
    Write-Host "  Cleanup finished with $($script:cleanupFailures) failure(s)" -ForegroundColor Red
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "  See the [ERROR] lines above - this run exits 1, nothing was masked." -ForegroundColor Gray
    Write-Host "  VMs, VNets, and Storage Accounts were NOT deleted." -ForegroundColor Gray
    Write-Host "  ASR replication resources must be removed via Azure Portal." -ForegroundColor Gray
    Write-Host "========================================`n" -ForegroundColor Cyan
    $Host.SetShouldExit(1)
    exit 1
}

Write-Host "  Cleanup Complete" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  VMs, VNets, and Storage Accounts were NOT deleted." -ForegroundColor Gray
Write-Host "  ASR replication resources must be removed via Azure Portal." -ForegroundColor Gray
Write-Host "========================================`n" -ForegroundColor Cyan
