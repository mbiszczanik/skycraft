<#
.SYNOPSIS
    Removes Lab 3.2 Virtual Machines resources.

.DESCRIPTION
    Cleans up Lab 3.2 resources in the following order:
    1. Virtual Machines (which auto-deletes NICs and OS disks via deleteOption=Delete)
    2. Data Disks
    3. Key Vault (if exists; deleted and purged)

    Note: This does NOT remove Lab 3.1 resources (VNets, NSGs, Load Balancer).

.PARAMETER Environment
    Target environment (dev or prod). Default: dev

.PARAMETER Force
    Skip confirmation prompts

.PARAMETER IncludeKeyVault
    Also remove the Key Vault and purge it from the soft-deleted state (requires purge permission on the vault).

.EXAMPLE
    .\Remove-LabResource.ps1 -Environment dev

.EXAMPLE
    .\Remove-LabResource.ps1 -Environment dev -Force -IncludeKeyVault

.NOTES
    Project: SkyCraft
    Lab: 3.2 - Virtual Machines
    Author: Marcin Biszczanik
    Date: 2026-01-11
#>

#Requires -Version 7.0
#Requires -Modules Az.Accounts, Az.Compute, Az.KeyVault

[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter()]
    [ValidateSet('dev', 'prod')]
    [string]$Environment = 'dev',

    [Parameter()]
    [switch]$Force,

    [Parameter()]
    [switch]$IncludeKeyVault
)

$ErrorActionPreference = 'Stop'
if ($Force) { $ConfirmPreference = 'None' }

# Configuration
$rgName = "$Environment-skycraft-swc-rg"
$namePrefix = "$Environment-skycraft-swc"

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  Lab 3.2 - Resource Cleanup" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# Verify Azure context
$context = Get-AzContext
if (-not $context) {
    Write-Error "Not logged into Azure. Run Connect-AzAccount first."
    $Host.SetShouldExit(1)
    exit 1
}

# List resources to be deleted
Write-Host "Resources to be deleted:" -ForegroundColor Yellow

$resourcesToDelete = @()

# Check VMs
$vms = @("$namePrefix-auth-vm", "$namePrefix-world-vm")
foreach ($vm in $vms) {
    $exists = Get-AzVM -Name $vm -ResourceGroupName $rgName -ErrorAction SilentlyContinue
    if ($exists) {
        $resourcesToDelete += @{ Type = 'VM'; Name = $vm }
        Write-Host "  - VM: $vm" -ForegroundColor Gray
    }
}

# Check Data Disks
$dataDisk = "$namePrefix-world-datadisk"
$exists = Get-AzDisk -DiskName $dataDisk -ResourceGroupName $rgName -ErrorAction SilentlyContinue
if ($exists) {
    $resourcesToDelete += @{ Type = 'Disk'; Name = $dataDisk }
    Write-Host "  - Disk: $dataDisk" -ForegroundColor Gray
}

# Check Key Vault
if ($IncludeKeyVault) {
    $kvName = "$namePrefix-kv"
    $exists = Get-AzKeyVault -VaultName $kvName -ResourceGroupName $rgName -ErrorAction SilentlyContinue
    if ($exists) {
        $resourcesToDelete += @{ Type = 'KeyVault'; Name = $kvName }
        Write-Host "  - Key Vault: $kvName" -ForegroundColor Gray
    }
}

if ($resourcesToDelete.Count -eq 0) {
    Write-Host "`nNo Lab 3.2 resources found to delete." -ForegroundColor Green
    exit 0
}

# Delete resources
Write-Host "`nDeleting resources..." -ForegroundColor Yellow

# Delete VMs first (NICs and OS disks auto-delete via deleteOption=Delete)
foreach ($resource in $resourcesToDelete | Where-Object { $_.Type -eq 'VM' }) {
    if ($PSCmdlet.ShouldProcess($resource.Name, 'Remove virtual machine')) {
        Write-Host "  Deleting VM: $($resource.Name)..." -ForegroundColor Gray
        Remove-AzVM -Name $resource.Name -ResourceGroupName $rgName -Force -ErrorAction Stop | Out-Null
        Write-Host "  ✓ Deleted" -ForegroundColor Green
    }
}

# Delete data disks
foreach ($resource in $resourcesToDelete | Where-Object { $_.Type -eq 'Disk' }) {
    if ($PSCmdlet.ShouldProcess($resource.Name, 'Remove managed disk')) {
        Write-Host "  Deleting Disk: $($resource.Name)..." -ForegroundColor Gray
        Remove-AzDisk -DiskName $resource.Name -ResourceGroupName $rgName -Force -ErrorAction Stop | Out-Null
        Write-Host "  ✓ Deleted" -ForegroundColor Green
    }
}

# Delete and purge the Key Vault (soft delete cannot be disabled; the lab keeps 7-day retention and no purge protection)
foreach ($resource in $resourcesToDelete | Where-Object { $_.Type -eq 'KeyVault' }) {
    if ($PSCmdlet.ShouldProcess($resource.Name, 'Remove and purge Key Vault')) {
        $vault = Get-AzKeyVault -VaultName $resource.Name -ResourceGroupName $rgName -ErrorAction Stop
        Write-Host "  Deleting Key Vault: $($resource.Name)..." -ForegroundColor Gray
        Remove-AzKeyVault -VaultName $resource.Name -ResourceGroupName $rgName -Force -ErrorAction Stop | Out-Null
        Write-Host "  Purging Key Vault: $($resource.Name) (location $($vault.Location))..." -ForegroundColor Gray
        try {
            Remove-AzKeyVault -VaultName $resource.Name -Location $vault.Location -InRemovedState -Force -ErrorAction Stop | Out-Null
            Write-Host "  ✓ Deleted and purged" -ForegroundColor Green
        } catch {
            Write-Warning "Vault '$($vault.VaultName)' deleted but not purged: $_"
            Write-Host "  Purge manually: Remove-AzKeyVault -VaultName $($vault.VaultName) -Location $($vault.Location) -InRemovedState -Force" -ForegroundColor Gray
        }
    }
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  Cleanup Complete" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Lab 3.1 resources (VNets, NSGs, LB) were NOT deleted." -ForegroundColor Gray
Write-Host "========================================`n" -ForegroundColor Cyan
