<#
.SYNOPSIS
    Removes Lab 5.2 Business Continuity & Disaster Recovery resources.

.DESCRIPTION
    Cleans up Lab 5.2 BCDR resources in the correct dependency order:
    1. Blob backup instances (Backup Vault)
    2. Backup Vault (platform-skycraft-swc-bv)
    3. VM backup protection item with data deletion
    4. Recovery Services Vault (platform-skycraft-swc-rsv)

    Notes:
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

[CmdletBinding()]
param(
    [Parameter()]
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

$platformRg     = 'platform-skycraft-swc-rg'
$prodRg         = 'prod-skycraft-swc-rg'
$rsvName        = 'platform-skycraft-swc-rsv'
$bvName         = 'platform-skycraft-swc-bv'
$storageAccount = 'prodskycraftswcsa'

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  Lab 5.2 - Resource Cleanup" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

$account = az account show --output json 2>$null | ConvertFrom-Json
if (-not $account) {
    Write-Host "  [ERROR] Not logged into Azure CLI. Run 'az login' first." -ForegroundColor Red
    exit 1
}

az config set extension.use_dynamic_install=yes_without_prompt --only-show-errors | Out-Null

# ── Inventory existing resources ──────────────────────────────────────────
Write-Host "Checking resources to delete..." -ForegroundColor Yellow

$resourcesToDelete = [System.Collections.Generic.List[hashtable]]::new()

$bvExists = az dataprotection backup-vault show `
    --resource-group $platformRg `
    --vault-name $bvName `
    --output json 2>$null | ConvertFrom-Json
if ($bvExists) {
    $instances = az dataprotection backup-instance list `
        --resource-group $platformRg `
        --vault-name $bvName `
        --output json 2>$null | ConvertFrom-Json
    foreach ($inst in $instances) {
        $resourcesToDelete.Add(@{ Type = 'BlobInstance'; Name = $inst.name })
        Write-Host "  - Blob Backup Instance: $($inst.name)" -ForegroundColor Gray
    }
    $resourcesToDelete.Add(@{ Type = 'BackupVault'; Name = $bvName })
    Write-Host "  - Backup Vault: $bvName" -ForegroundColor Gray
}

$rsvExists = az backup vault show `
    --resource-group $platformRg `
    --name $rsvName `
    --output json 2>$null | ConvertFrom-Json
if ($rsvExists) {
    $vmItems = az backup item list `
        --resource-group $platformRg `
        --vault-name $rsvName `
        --backup-management-type AzureIaasVM `
        --output json 2>$null | ConvertFrom-Json
    if ($vmItems -and $vmItems.Count -gt 0) {
        foreach ($item in $vmItems) {
            $resourcesToDelete.Add(@{
                Type          = 'VmBackupItem'
                Name          = $item.name
                ContainerName = $item.properties.containerName
                FriendlyName  = $item.properties.friendlyName
            })
            Write-Host "  - VM Backup Item: $($item.properties.friendlyName)" -ForegroundColor Gray
        }
    }
    $resourcesToDelete.Add(@{ Type = 'RSV'; Name = $rsvName })
    Write-Host "  - Recovery Services Vault: $rsvName" -ForegroundColor Gray
}

if ($resourcesToDelete.Count -eq 0) {
    Write-Host "`nNo Lab 5.2 resources found to delete." -ForegroundColor Green
    exit 0
}

# ── Confirm deletion ──────────────────────────────────────────────────────
if (-not $Force) {
    Write-Host "`n[WARNING] This will permanently delete the above resources." -ForegroundColor Yellow
    Write-Host "  Ensure ASR replication has been removed via Azure Portal first." -ForegroundColor Gray
    Write-Host "  VMs, VNets, and Storage Accounts will NOT be deleted." -ForegroundColor Gray
    $confirm = Read-Host "Are you sure? Type 'DELETE' to confirm"
    if ($confirm -ne 'DELETE') {
        Write-Host "Cleanup cancelled." -ForegroundColor Yellow
        exit 0
    }
}

Write-Host "`nDeleting resources..." -ForegroundColor Yellow

# 1. Delete Blob Backup Instances
foreach ($r in $resourcesToDelete | Where-Object { $_.Type -eq 'BlobInstance' }) {
    Write-Host "  Deleting Blob Backup Instance: $($r.Name)..." -ForegroundColor Gray
    try {
        az dataprotection backup-instance delete `
            --resource-group $platformRg `
            --vault-name $bvName `
            --backup-instance-name $r.Name `
            --yes --output none 2>$null
        Write-Host "  ✓ Deleted" -ForegroundColor Green
    } catch {
        Write-Host "  [WARNING] Could not delete: $_" -ForegroundColor Yellow
    }
}

# 2. Delete Backup Vault
foreach ($r in $resourcesToDelete | Where-Object { $_.Type -eq 'BackupVault' }) {
    Write-Host "  Deleting Backup Vault: $($r.Name)..." -ForegroundColor Gray
    try {
        az dataprotection backup-vault delete `
            --resource-group $platformRg `
            --vault-name $r.Name `
            --yes --output none 2>$null
        Write-Host "  ✓ Deleted" -ForegroundColor Green
    } catch {
        Write-Host "  [WARNING] Could not delete Backup Vault: $_" -ForegroundColor Yellow
    }
}

# 3. Disable VM backup protection and delete backup data
foreach ($r in $resourcesToDelete | Where-Object { $_.Type -eq 'VmBackupItem' }) {
    Write-Host "  Disabling VM backup protection: $($r.FriendlyName)..." -ForegroundColor Gray
    try {
        az backup protection disable `
            --resource-group $platformRg `
            --vault-name $rsvName `
            --item-name $r.Name `
            --container-name $r.ContainerName `
            --backup-management-type AzureIaasVM `
            --delete-backup-data true `
            --yes --output none 2>$null
        Write-Host "  ✓ Protection disabled and backup data deleted" -ForegroundColor Green
    } catch {
        Write-Host "  [WARNING] Could not disable backup protection: $_" -ForegroundColor Yellow
        Write-Host "    Manual cleanup may be required via Azure Portal." -ForegroundColor Gray
    }
}

# 4. Delete Recovery Services Vault
foreach ($r in $resourcesToDelete | Where-Object { $_.Type -eq 'RSV' }) {
    Write-Host "  Deleting Recovery Services Vault: $($r.Name)..." -ForegroundColor Gray
    try {
        az backup vault delete `
            --resource-group $platformRg `
            --name $r.Name `
            --yes --output none 2>$null
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
