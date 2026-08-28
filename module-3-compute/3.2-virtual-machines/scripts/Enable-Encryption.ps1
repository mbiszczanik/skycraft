<#
.SYNOPSIS
    Enables Azure Disk Encryption on Lab 3.2 VMs.

.DESCRIPTION
    This script enables Azure Disk Encryption (ADE) on Auth and World VMs.
    ADE for Linux requires imperative tooling (Az PowerShell; not available via Portal or Bicep).

    The script will:
    1. Resize 4 GB VMs (Standard_B2ls_v2 / Standard_B2als_v2) to their 8 GB sibling (Standard_B2s_v2 / Standard_B2as_v2) - ADE for Linux needs 8 GB RAM
    2. Enable Azure Disk Encryption using the Key Vault
    3. Monitor encryption progress
    4. Optionally resize back to original size

.PARAMETER Environment
    Target environment (dev or prod). Default: dev

.PARAMETER ResizeBack
    Resize VMs back to their original size after encryption completes. Default: true

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
# ADE for Linux requires 8 GB RAM: 4 GB B v2 sizes are resized to their 8 GB sibling for the duration of the encryption.
$resizeMap = @{
    'Standard_B2ls_v2'  = 'Standard_B2s_v2'
    'Standard_B2als_v2' = 'Standard_B2as_v2'
}

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
    $vmInfo[$vmName] = @{ CurrentSize = $vm.HardwareProfile.VmSize; PowerState = $powerState; Resized = $false }
    Write-Host "  ✓ $vmName (Size: $($vmInfo[$vmName].CurrentSize), State: $($vmInfo[$vmName].PowerState))" -ForegroundColor Green
}

# Confirm operation
Write-Host "`n[3/5] Enabling Azure Disk Encryption (4 GB sizes are resized to 8 GB first)" -ForegroundColor Yellow
$confirm = Read-Host "Proceed with encryption? This will restart VMs. (y/N)"
if ($confirm -ne 'y') {
    Write-Host "Operation cancelled." -ForegroundColor Yellow
    exit 0
}

# Process each VM
$failed = @()
foreach ($vmName in $VmNames) {
    Write-Host "`n----------------------------------------" -ForegroundColor Gray
    Write-Host "Processing: $vmName" -ForegroundColor Cyan
    Write-Host "----------------------------------------" -ForegroundColor Gray

    # Resize to an 8 GB size if needed
    $originalSize = $vmInfo[$vmName].CurrentSize
    if ($resizeMap.ContainsKey($originalSize)) {
        $targetSize = $resizeMap[$originalSize]
        Write-Host "  Resizing $originalSize -> $targetSize (ADE needs 8 GB RAM)..." -ForegroundColor Yellow
        $vm = Get-AzVM -ResourceGroupName $rgName -Name $vmName
        $vm.HardwareProfile.VmSize = $targetSize
        # No deallocation needed: both sizes are in the same Bsv2/Basv2 family (same hardware cluster), so the resize is an in-place restart.
        Update-AzVM -ResourceGroupName $rgName -VM $vm -ErrorAction Stop | Out-Null
        $vmInfo[$vmName].Resized = $true
        Write-Host "  ✓ Resized" -ForegroundColor Green
    }

    # Encrypt and wait; the finally block restores the VM size whatever happens above
    $completed = $false
    try {
        # Enable Azure Disk Encryption
        Write-Host "  Enabling Azure Disk Encryption..." -ForegroundColor Yellow
        Write-Host "  (This may take 15-30 minutes per VM)" -ForegroundColor Gray

        $initiated = $false
        try {
            Set-AzVMDiskEncryptionExtension -ResourceGroupName $rgName -VMName $vmName `
                -DiskEncryptionKeyVaultUrl $kv.VaultUri -DiskEncryptionKeyVaultId $kv.ResourceId `
                -VolumeType All -Force -ErrorAction Stop | Out-Null
            $initiated = $true
        } catch {
            Write-Warning "Failed to enable encryption on $vmName : $_"
            $failed += $vmName
        }

        if ($initiated) {
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
                    $completed = $true
                    Write-Host "  ✓ Encryption completed!" -ForegroundColor Green
                    break
                }

                Write-Host "    Still encrypting... (attempt $attempt of $maxAttempts)" -ForegroundColor Gray

            } while ($attempt -lt $maxAttempts)

            if (-not $completed) {
                Write-Warning "Encryption still in progress after 30 minutes. Check status manually:"
                Write-Host "  Get-AzVmDiskEncryptionStatus -ResourceGroupName $rgName -VMName $vmName"
            }
        }
    } finally {
        # Resize back (default) so the lab keeps its cheaper size - only once encryption has completed or never started,
        # because a resize restarts the VM and would interrupt an encryption that is still running
        if ($vmInfo[$vmName].Resized) {
            if ($ResizeBack -and ($completed -or -not $initiated)) {
                # Safe to restore the size: encryption finished, or it never started.
                Write-Host "  Resizing back to $originalSize..." -ForegroundColor Yellow
                $vm = Get-AzVM -ResourceGroupName $rgName -Name $vmName
                $vm.HardwareProfile.VmSize = $originalSize
                # No deallocation needed: both sizes are in the same Bsv2/Basv2 family (same hardware cluster), so the resize is an in-place restart.
                Update-AzVM -ResourceGroupName $rgName -VM $vm -ErrorAction Stop | Out-Null
                Write-Host "  ✓ Resized back" -ForegroundColor Green
            } elseif ($initiated -and -not $completed) {
                Write-Warning "$vmName was resized to $targetSize but encryption did not complete, so it was NOT resized back. Once Get-AzVmDiskEncryptionStatus shows OsVolumeEncrypted = Encrypted, run:"
                Write-Host "  Update-AzVM -ResourceGroupName $rgName -VM (Get-AzVM -ResourceGroupName $rgName -Name $vmName | ForEach-Object { `$_.HardwareProfile.VmSize = '$originalSize'; `$_ })"
            }
        }
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

if ($failed.Count -gt 0) {
    Write-Error "Encryption failed for: $($failed -join ', ')"
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  Azure Disk Encryption Complete" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan
