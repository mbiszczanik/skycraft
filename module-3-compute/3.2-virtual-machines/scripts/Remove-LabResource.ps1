<#
.SYNOPSIS
    Removes Lab 3.2 Virtual Machines resources.

.DESCRIPTION
    Cleans up Lab 3.2 resources in the following order:
    1. Virtual Machines (which auto-deletes NICs and OS disks)
    2. Data Disks
    3. Key Vault (if exists)

    Note: This does NOT remove Lab 3.1 resources (VNets, NSGs, Load Balancer).

.PARAMETER Environment
    Target environment (dev or prod). Default: dev

.PARAMETER Force
    Skip confirmation prompts

.PARAMETER IncludeKeyVault
    Also remove the Key Vault (requires purge permissions)

.EXAMPLE
    .\Remove-LabResource.ps1 -Environment dev
    
.EXAMPLE
    .\Remove-LabResource.ps1 -Environment dev -Force -IncludeKeyVault
#>

[CmdletBinding()]
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

# Configuration
$rgName = "$Environment-skycraft-swc-rg"
$namePrefix = "$Environment-skycraft-swc"

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  Lab 3.2 - Resource Cleanup" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# Check Azure CLI login
$account = az account show 2>$null | ConvertFrom-Json
if (-not $account) {
    Write-Error "Not logged into Azure CLI. Run 'az login' first."
    exit 1
}

# List resources to be deleted
Write-Host "Resources to be deleted:" -ForegroundColor Yellow

$resourcesToDelete = @()

# Check VMs
$vms = @("$namePrefix-auth-vm", "$namePrefix-world-vm")
foreach ($vm in $vms) {
    $exists = az vm show --name $vm --resource-group $rgName 2>$null
    if ($exists) {
        $resourcesToDelete += @{ Type = 'VM'; Name = $vm }
        Write-Host "  - VM: $vm" -ForegroundColor Gray
    }
}

# Check Data Disks
$dataDisk = "$namePrefix-world-datadisk"
$exists = az disk show --name $dataDisk --resource-group $rgName 2>$null
if ($exists) {
    $resourcesToDelete += @{ Type = 'Disk'; Name = $dataDisk }
    Write-Host "  - Disk: $dataDisk" -ForegroundColor Gray
}

# Check Key Vault
if ($IncludeKeyVault) {
    $kvName = "$namePrefix-kv"
    $exists = az keyvault show --name $kvName --resource-group $rgName 2>$null
    if ($exists) {
        $resourcesToDelete += @{ Type = 'KeyVault'; Name = $kvName }
        Write-Host "  - Key Vault: $kvName" -ForegroundColor Gray
    }
}

if ($resourcesToDelete.Count -eq 0) {
    Write-Host "`nNo Lab 3.2 resources found to delete." -ForegroundColor Green
    exit 0
}

# Confirm deletion
if (-not $Force) {
    Write-Host "`n⚠️  This will permanently delete the above resources." -ForegroundColor Yellow
    $confirm = Read-Host "Are you sure? Type 'DELETE' to confirm"
    if ($confirm -ne 'DELETE') {
        Write-Host "Cleanup cancelled." -ForegroundColor Yellow
        exit 0
    }
}

# Delete resources
Write-Host "`nDeleting resources..." -ForegroundColor Yellow

# Delete VMs first (NICs and OS disks auto-delete if configured)
foreach ($resource in $resourcesToDelete | Where-Object { $_.Type -eq 'VM' }) {
    Write-Host "  Deleting VM: $($resource.Name)..." -ForegroundColor Gray
    az vm delete --name $resource.Name --resource-group $rgName --yes --force-deletion true 2>$null
    Write-Host "  ✓ Deleted" -ForegroundColor Green
}

# Delete data disks
foreach ($resource in $resourcesToDelete | Where-Object { $_.Type -eq 'Disk' }) {
    Write-Host "  Deleting Disk: $($resource.Name)..." -ForegroundColor Gray
    az disk delete --name $resource.Name --resource-group $rgName --yes 2>$null
    Write-Host "  ✓ Deleted" -ForegroundColor Green
}

# Delete Key Vault (soft-delete means it goes to "deleted" state first)
foreach ($resource in $resourcesToDelete | Where-Object { $_.Type -eq 'KeyVault' }) {
    Write-Host "  Deleting Key Vault: $($resource.Name)..." -ForegroundColor Gray
    az keyvault delete --name $resource.Name --resource-group $rgName 2>$null
    Write-Host "  ✓ Deleted (soft-delete)" -ForegroundColor Green
    Write-Host "    Note: Key Vault is in soft-deleted state for 90 days." -ForegroundColor Gray
    Write-Host "    To permanently purge: az keyvault purge --name $($resource.Name)" -ForegroundColor Gray
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  Cleanup Complete" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Lab 3.1 resources (VNets, NSGs, LB) were NOT deleted." -ForegroundColor Gray
Write-Host "========================================`n" -ForegroundColor Cyan
