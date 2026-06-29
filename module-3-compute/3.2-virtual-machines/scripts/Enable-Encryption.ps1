<#
.SYNOPSIS
    Enables Azure Disk Encryption on Lab 3.2 VMs.

.DESCRIPTION
    This script enables Azure Disk Encryption (ADE) on Auth and World VMs.
    ADE for Linux requires imperative tooling (Az PowerShell; not available via Portal or Bicep).

    The script will:
    1. Resize VMs to Standard_B2ms (8 GB RAM required for ADE)
    2. Enable Azure Disk Encryption using the Key Vault
    3. Monitor encryption progress
    4. Optionally resize back to original size

.PARAMETER Environment
    Target environment (dev or prod). Default: dev

.PARAMETER ResizeBack
    Resize VMs back to Standard_B2s after encryption completes. Default: true

.PARAMETER VmNames
    Specific VM names to encrypt. Default: both Auth and World VMs

.EXAMPLE
    .\Enable-Encryption.ps1 -Environment dev

.EXAMPLE
    .\Enable-Encryption.ps1 -Environment dev -ResizeBack $false

.NOTES
    IMPORTANT: ADE is scheduled for retirement on September 15, 2028.
    For new deployments, consider using Encryption at Host instead.
#>

#Requires -Version 7.0
#Requires -Modules Az.Accounts, Az.Compute, Az.KeyVault

[CmdletBinding()]
param(
    [Parameter()]
    [ValidateSet('dev', 'prod')]
    [string]$Environment = 'dev',

    [Parameter()]
    [bool]$ResizeBack = $true,

    [Parameter()]
    [string[]]$VmNames = @()
)

$ErrorActionPreference = 'Stop'

# Configuration
$rgName = "$Environment-skycraft-swc-rg"
$kvName = "$Environment-skycraft-swc-kv"
# Standard_D2s_v3 (the default VM size) has 8 GB RAM, which meets the ADE requirement.
# No resize is needed before encryption.

# Default VM names if not specified
if ($VmNames.Count -eq 0) {
    $VmNames = @(
        "$Environment-skycraft-swc-auth-vm",
        "$Environment-skycraft-swc-world-vm"
    )
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  Azure Disk Encryption Enablement" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

Write-Host "[!] WARNING: ADE is scheduled for retirement on September 15, 2028." -ForegroundColor Yellow
Write-Host "    Consider using Encryption at Host for new deployments.`n" -ForegroundColor Yellow

# Check Azure connection
$account = Get-AzContext
if (-not $account) {
    Write-Error "Not logged into Azure. Run 'Connect-AzAccount' first."
    exit 1
}
Write-Host "✓ Logged in as: $($account.Account.Id)" -ForegroundColor Green

# Check Key Vault exists
Write-Host "`n[1/5] Checking Key Vault..." -ForegroundColor Yellow
$kv = Get-AzKeyVault -VaultName $kvName -ResourceGroupName $rgName -ErrorAction SilentlyContinue
if (-not $kv) {
    Write-Error "Key Vault '$kvName' not found. Deploy with -EncryptionStrategy AzureDiskEncryption first."
    exit 1
}
Write-Host "  ✓ Key Vault found: $kvName" -ForegroundColor Green

# Check VMs exist and get current sizes
Write-Host "`n[2/5] Checking VMs..." -ForegroundColor Yellow
$vmInfo = @{}
foreach ($vmName in $VmNames) {
    $vm = Get-AzVM -ResourceGroupName $rgName -Name $vmName -ErrorAction SilentlyContinue
    if (-not $vm) {
        Write-Error "VM '$vmName' not found in resource group '$rgName'"
        exit 1
    }
    $powerState = (Get-AzVM -ResourceGroupName $rgName -Name $vmName -Status).Statuses |
        Where-Object { $_.Code -like 'PowerState/*' } |
        Select-Object -ExpandProperty DisplayStatus
    $vmInfo[$vmName] = @{
        CurrentSize = $vm.HardwareProfile.VmSize
        PowerState  = $powerState
    }
    Write-Host "  ✓ $vmName (Size: $($vmInfo[$vmName].CurrentSize), State: $($vmInfo[$vmName].PowerState))" -ForegroundColor Green
}

# Confirm operation
Write-Host "`n[3/5] Enabling Azure Disk Encryption (D2s_v3 has 8 GB RAM — no resize required)" -ForegroundColor Yellow
$confirm = Read-Host "Proceed with encryption? This will restart VMs. (y/N)"
if ($confirm -ne 'y') {
    Write-Host "Operation cancelled." -ForegroundColor Yellow
    exit 0
}

# Process each VM
foreach ($vmName in $VmNames) {
    Write-Host "`n----------------------------------------" -ForegroundColor Gray
    Write-Host "Processing: $vmName" -ForegroundColor Cyan
    Write-Host "----------------------------------------" -ForegroundColor Gray

    # Enable Azure Disk Encryption
    Write-Host "  Enabling Azure Disk Encryption..." -ForegroundColor Yellow
    Write-Host "  (This may take 15-30 minutes per VM)" -ForegroundColor Gray

    try {
        Set-AzVMDiskEncryptionExtension -ResourceGroupName $rgName -VMName $vmName `
            -DiskEncryptionKeyVaultUrl $kv.VaultUri -DiskEncryptionKeyVaultId $kv.ResourceId `
            -VolumeType All -Force -ErrorAction Stop | Out-Null
    } catch {
        Write-Error "Failed to enable encryption on $vmName : $_"
        continue
    }

    Write-Host "  ✓ Encryption initiated" -ForegroundColor Green

    # Wait for encryption to complete
    Write-Host "  Waiting for encryption to complete..." -ForegroundColor Yellow
    $maxAttempts = 60  # 30 minutes max wait
    $attempt = 0

    do {
        Start-Sleep -Seconds 30
        $attempt++

        $status = Get-AzVmDiskEncryptionStatus -ResourceGroupName $rgName -VMName $vmName -ErrorAction SilentlyContinue
        $osEncrypted = $status.OsVolumeEncrypted -eq 'Encrypted'

        if ($osEncrypted) {
            Write-Host "  ✓ Encryption completed!" -ForegroundColor Green
            break
        }

        Write-Host "    Still encrypting... (attempt $attempt of $maxAttempts)" -ForegroundColor Gray

    } while ($attempt -lt $maxAttempts)

    if ($attempt -ge $maxAttempts) {
        Write-Warning "Encryption still in progress after 30 minutes. Check status manually:"
        Write-Host "  Get-AzVmDiskEncryptionStatus -ResourceGroupName $rgName -VMName $vmName"
    }

}

# Final verification
Write-Host "`n[5/5] Verification" -ForegroundColor Yellow
foreach ($vmName in $VmNames) {
    Write-Host "`n  $vmName :" -ForegroundColor Cyan
    $encStatus = Get-AzVmDiskEncryptionStatus -ResourceGroupName $rgName -VMName $vmName -ErrorAction SilentlyContinue
    [PSCustomObject]@{
        OS   = $encStatus.OsVolumeEncrypted
        Data = $encStatus.DataVolumesEncrypted
    } | Format-Table -AutoSize
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  Azure Disk Encryption Complete" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan
