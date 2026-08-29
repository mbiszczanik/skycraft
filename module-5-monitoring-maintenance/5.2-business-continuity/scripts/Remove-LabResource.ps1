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

    Notes:
    - The role assignments are removed before the Backup Vault so its managed
      identity is still resolvable; otherwise they would be orphaned on the
      storage account after the vault (and its identity) is deleted.
    - Azure Site Recovery resources (ASR fabric, replication, cache storage
      account) must be cleaned up manually via the Azure Portal before
      deleting the Recovery Services Vault.
    - VMs and Storage Accounts from earlier labs are NOT removed by this script.

.PARAMETER Force
    Skip confirmation prompts.

.EXAMPLE
    .\Remove-LabResource.ps1

.EXAMPLE
    .\Remove-LabResource.ps1 -Force

.NOTES
    Project: SkyCraft
    Lab: 5.2 - Business Continuity & Disaster Recovery
    Version: 1.0.0
    Date: 2026-04-06
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

# ── Inventory existing resources ──────────────────────────────────────────
Write-Host "Checking resources to delete..." -ForegroundColor Yellow

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
            $resourcesToDelete.Add(@{
                Type          = 'VmBackupItem'
                Name          = $item.Name
                ContainerName = $item.ContainerName
                FriendlyName  = $item.FriendlyName
                Item          = $item
            })
            Write-Host "  - VM Backup Item: $($item.FriendlyName)" -ForegroundColor Gray
        }
    }
    $resourcesToDelete.Add(@{ Type = 'RSV'; Name = $rsvName })
    Write-Host "  - Recovery Services Vault: $rsvName" -ForegroundColor Gray
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
        Write-Host "  [WARNING] Could not delete: $_" -ForegroundColor Yellow
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
        Write-Host "  [WARNING] Could not remove role assignment '$($r.Name)': $_" -ForegroundColor Yellow
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
        Write-Host "  [WARNING] Could not delete Backup Vault: $_" -ForegroundColor Yellow
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
        Write-Host "  [WARNING] Could not disable backup protection: $_" -ForegroundColor Yellow
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
        Write-Host "  [WARNING] Could not delete RSV: $_" -ForegroundColor Yellow
        Write-Host "    Ensure all backup items, data, and ASR resources are removed first." -ForegroundColor Gray
        Write-Host "    Use Azure Portal: RSV → Backup Items → Stop protection + Delete backup data" -ForegroundColor Gray
    }
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  Cleanup Complete" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  VMs, VNets, and Storage Accounts were NOT deleted." -ForegroundColor Gray
Write-Host "  ASR replication resources must be removed via Azure Portal." -ForegroundColor Gray
Write-Host "========================================`n" -ForegroundColor Cyan
