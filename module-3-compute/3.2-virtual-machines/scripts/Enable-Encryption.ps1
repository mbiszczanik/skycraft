<#
.SYNOPSIS
    Enables Azure Disk Encryption on the Lab 3.2 Auth VM.

.DESCRIPTION
    Encrypts <env>-skycraft-swc-auth-vm with Azure Disk Encryption (ADE) and the key vault
    <env>-skycraft-swc-kv, as Steps 3.2.18-3.2.20 do. The World VM is never encrypted: Lab 5.2
    runs file-level recovery and Site Recovery on it, and file-level recovery is not available for
    an ADE-encrypted VM (#368, maintainer decision 2026-10-16). Deploy-Bicep.ps1 runs this script
    after a deployment with -EncryptionStrategy AzureDiskEncryption, so every path ends with the
    same VM encrypted.

    The script will:
    1. Check the key vault and the Auth VM; an Auth VM that is already encrypted is left alone
    2. Resize a 4 GB size (Standard_B2ls_v2 / Standard_B2als_v2) to its 8 GB sibling
       (Standard_B2s_v2 / Standard_B2as_v2) - ADE for Linux needs 8 GB RAM
    3. Install the AzureDiskEncryptionForLinux extension (VolumeType All, -SkipVmBackup: Az.Compute
       refuses a Linux VM with managed disks without it, and the VM has no backup before
       Lab 5.2; in production take a snapshot or a backup first). The extension takes no
       tags: Lab 1.3's Inherit-Project-Tag assignment copies Project from the resource group, and
       without that assignment Enforce-Project-Tag refuses it
    4. Wait until the OS volume reads Encrypted (about 2 hours on Standard_B2s_v2 in the pass of
       2026-10-15)
    5. Resize back to the original size, but only once encryption has completed or never started:
       a resize restarts the VM and would interrupt a running encryption

    Exit code 1 when the Auth VM does not end encrypted (no key vault, refused extension, timeout,
    declined or no console to confirm on), 0 otherwise.

.PARAMETER Environment
    Target environment (dev or prod). Default: dev

.PARAMETER KeyVaultName
    The key vault of Step 3.2.17, for a learner whose vault name differs because the default was
    taken (key vault names are globally unique). Default: <env>-skycraft-swc-kv

.PARAMETER ResizeBack
    Resize the VM back to its original size after encryption completes. Default: true

.PARAMETER Force
    Skip the confirmation prompt, for Deploy-Bicep.ps1 and the lab cycle. Without it, a session
    that cannot prompt exits 1 and changes nothing.

.PARAMETER TimeoutMinutes
    How long to wait for the OS volume to read Encrypted. Default: 180

.PARAMETER PollSeconds
    Seconds between two status reads. Default: 60

.EXAMPLE
    .\Enable-Encryption.ps1 -Environment dev

.EXAMPLE
    .\Enable-Encryption.ps1 -Environment dev -Force -ResizeBack $false

.NOTES
    Project: SkyCraft
    Lab: 3.2 - Virtual Machines
    ADE retires on September 15, 2028, and AZ-104 (skills measured 2026-04-17) lists encryption at
    host, not ADE. The lab keeps ADE on one VM because Lab 5.2 teaches the key vault role Azure
    Backup needs for an encrypted VM.
#>

#Requires -Version 7.0
#Requires -Modules Az.Accounts, Az.Compute, Az.KeyVault

[CmdletBinding()]
param(
    [Parameter()]
    [ValidateSet('dev', 'prod')]
    [string]$Environment = 'dev',

    [Parameter()]
    [ValidatePattern('^[a-zA-Z][a-zA-Z0-9-]{1,22}[a-zA-Z0-9]$')]
    [string]$KeyVaultName,

    [Parameter()]
    [bool]$ResizeBack = $true,

    [Parameter()]
    [switch]$Force,

    [Parameter()]
    [ValidateRange(0, 1440)]
    [int]$TimeoutMinutes = 180,

    [Parameter()]
    [ValidateRange(0, 3600)]
    [int]$PollSeconds = 60
)

$ErrorActionPreference = 'Stop'
# Exit-Lab ends the script with exit code 0 or 1 and leaves an interactive session open (#257).
Import-Module (Join-Path $PSScriptRoot '../../../tools/LabCommon.psm1') -Force -Verbose:$false

# Configuration
$rgName = "$Environment-skycraft-swc-rg"
$kvName = if ($KeyVaultName) { $KeyVaultName } else { "$Environment-skycraft-swc-kv" }
$vmName = "$Environment-skycraft-swc-auth-vm"
$worldVmName = "$Environment-skycraft-swc-world-vm"
# ADE for Linux requires 8 GB RAM: 4 GB B v2 sizes are resized to their 8 GB sibling for the duration of the encryption.
$resizeMap = @{
    'Standard_B2ls_v2'  = 'Standard_B2s_v2'
    'Standard_B2als_v2' = 'Standard_B2as_v2'
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  Azure Disk Encryption - Auth VM" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

Write-Host "[!] ADE retires on September 15, 2028; AZ-104 lists encryption at host instead." -ForegroundColor Yellow
Write-Host "    Only $vmName is encrypted: Lab 5.2 needs $worldVmName unencrypted.`n" -ForegroundColor Yellow

$account = Get-AzContext
if (-not $account) {
    Write-Host "[ERROR] Not logged into Azure. Run 'Connect-AzAccount' first." -ForegroundColor Red
    Exit-Lab -FailureCount 1
}

Write-Host "[1/5] Checking Key Vault..." -ForegroundColor Yellow
$kv = Get-AzKeyVault -VaultName $kvName -ResourceGroupName $rgName -ErrorAction SilentlyContinue
if (-not $kv) {
    Write-Host "[ERROR] Key Vault '$kvName' not found. Create it (Step 3.2.17) or deploy with -EncryptionStrategy AzureDiskEncryption first." -ForegroundColor Red
    Exit-Lab -FailureCount 1
}
if (-not $kv.EnabledForDiskEncryption) {
    Write-Host "[ERROR] Key Vault '$kvName' is not enabled for Azure Disk Encryption (Access configuration > Resource access)." -ForegroundColor Red
    Exit-Lab -FailureCount 1
}
Write-Host "  ✓ Key Vault found: $kvName" -ForegroundColor Green

Write-Host "`n[2/5] Checking $vmName..." -ForegroundColor Yellow
$vm = Get-AzVM -ResourceGroupName $rgName -Name $vmName -ErrorAction SilentlyContinue
if (-not $vm) {
    Write-Host "[ERROR] VM '$vmName' not found in resource group '$rgName'." -ForegroundColor Red
    Exit-Lab -FailureCount 1
}
$originalSize = $vm.HardwareProfile.VmSize
Write-Host "  ✓ $vmName (Size: $originalSize)" -ForegroundColor Green

$status = Get-AzVMDiskEncryptionStatus -ResourceGroupName $rgName -VMName $vmName -ErrorAction SilentlyContinue
if ("$($status.OsVolumeEncrypted)" -eq 'Encrypted') {
    Write-Host "  ✓ Already encrypted (OS: $($status.OsVolumeEncrypted), Data: $($status.DataVolumesEncrypted)). Nothing to do." -ForegroundColor Green
    Exit-Lab -FailureCount 0
}

if (-not $Force) {
    $choices = [System.Management.Automation.Host.ChoiceDescription[]]@(
        [System.Management.Automation.Host.ChoiceDescription]::new('&Yes', "Encrypt $vmName. It restarts, and the encryption runs for about 2 hours.")
        [System.Management.Automation.Host.ChoiceDescription]::new('&No', 'Cancel. Nothing is changed.')
    )
    try {
        $answer = $Host.UI.PromptForChoice('Lab 3.2 - Azure Disk Encryption', "`nEncrypt $vmName now?", $choices, 1)
    }
    catch {
        Write-Host "`n[ABORTED] Cannot ask for confirmation: this session has no interactive console." -ForegroundColor Red
        Write-Host "  Re-run with -Force to encrypt non-interactively. Nothing was changed." -ForegroundColor Gray
        Exit-Lab -FailureCount 1
    }
    if ($answer -ne 0) {
        Write-Host "Encryption cancelled. Nothing was changed." -ForegroundColor Yellow
        Exit-Lab -FailureCount 1
    }
}

$failures = 0
$resized = $false
$initiated = $false
$completed = $false
$targetSize = $resizeMap[$originalSize]

if ($targetSize) {
    Write-Host "`n[3/5] Resizing $originalSize -> $targetSize (ADE needs 8 GB RAM)..." -ForegroundColor Yellow
    $vm.HardwareProfile.VmSize = $targetSize
    # Same Bsv2/Basv2 family (same hardware cluster): the resize is an in-place restart, no deallocation.
    Update-AzVM -ResourceGroupName $rgName -VM $vm -ErrorAction Stop | Out-Null
    $resized = $true
    Write-Host "  ✓ Resized" -ForegroundColor Green
} else {
    Write-Host "`n[3/5] $originalSize needs no resize." -ForegroundColor Yellow
}

try {
    Write-Host "`n[4/5] Enabling Azure Disk Encryption on $vmName..." -ForegroundColor Yellow
    try {
        # Az.Compute refuses a Linux VM with managed disks without -SkipVmBackup; the lab VM has no backup before Lab 5.2.
        Set-AzVMDiskEncryptionExtension -ResourceGroupName $rgName -VMName $vmName `
            -DiskEncryptionKeyVaultUrl $kv.VaultUri -DiskEncryptionKeyVaultId $kv.ResourceId `
            -VolumeType All -SkipVmBackup -Force -ErrorAction Stop | Out-Null
        $initiated = $true
        Write-Host "  ✓ Encryption initiated" -ForegroundColor Green
    } catch {
        $failures++
        Write-Host "  [ERROR] Could not enable encryption on $($vmName): $_" -ForegroundColor Red
        if ("$_" -match 'RequestDisallowedByPolicy') {
            Write-Host "  The extension carries no tags. Lab 1.3's Inherit-Project-Tag assignment adds Project from the resource group;" -ForegroundColor Gray
            Write-Host "  assign it (Step 1.3.8), wait about 10 minutes and run this script again." -ForegroundColor Gray
        }
    }

    if ($initiated) {
        Write-Host "  Waiting up to $TimeoutMinutes minutes for the OS volume (about 2 hours on Standard_B2s_v2)..." -ForegroundColor Gray
        $deadline = (Get-Date).AddMinutes($TimeoutMinutes)
        do {
            Start-Sleep -Seconds $PollSeconds
            $status = Get-AzVMDiskEncryptionStatus -ResourceGroupName $rgName -VMName $vmName -ErrorAction SilentlyContinue
            if ("$($status.OsVolumeEncrypted)" -eq 'Encrypted') {
                $completed = $true
                break
            }
            Write-Host "    $(Get-Date -Format 'HH:mm') OS: $($status.OsVolumeEncrypted) - $($status.ProgressMessage)" -ForegroundColor Gray
        } while ((Get-Date) -lt $deadline)

        if ($completed) {
            Write-Host "  ✓ Encryption completed" -ForegroundColor Green
        } else {
            $failures++
            Write-Host "  [ERROR] The OS volume is not encrypted after $TimeoutMinutes minutes. Check it later with:" -ForegroundColor Red
            Write-Host "    Get-AzVMDiskEncryptionStatus -ResourceGroupName $rgName -VMName $vmName" -ForegroundColor Gray
        }
    }
} finally {
    if ($resized) {
        if ($ResizeBack -and ($completed -or -not $initiated)) {
            Write-Host "  Resizing back to $originalSize..." -ForegroundColor Yellow
            $vm = Get-AzVM -ResourceGroupName $rgName -Name $vmName
            $vm.HardwareProfile.VmSize = $originalSize
            Update-AzVM -ResourceGroupName $rgName -VM $vm -ErrorAction Stop | Out-Null
            Write-Host "  ✓ Resized back" -ForegroundColor Green
        } elseif ($initiated -and -not $completed) {
            Write-Host "  [WARN] $vmName stays at $targetSize and was NOT resized back: a resize now would restart it mid-encryption." -ForegroundColor Yellow
            Write-Host "  Once OsVolumeEncrypted reads Encrypted, resize it back (Step 3.2.20):" -ForegroundColor Gray
            Write-Host "  Update-AzVM -ResourceGroupName $rgName -VM (Get-AzVM -ResourceGroupName $rgName -Name $vmName | ForEach-Object { `$_.HardwareProfile.VmSize = '$originalSize'; `$_ })" -ForegroundColor Gray
        }
    }
}

Write-Host "`n[5/5] Verification" -ForegroundColor Yellow
foreach ($name in $vmName, $worldVmName) {
    $encStatus = Get-AzVMDiskEncryptionStatus -ResourceGroupName $rgName -VMName $name -ErrorAction SilentlyContinue
    Write-Host "  $($name): OS $($encStatus.OsVolumeEncrypted), Data $($encStatus.DataVolumesEncrypted)"
}

Write-Host "`n========================================" -ForegroundColor Cyan
if ($failures -gt 0) {
    Write-Host "  Azure Disk Encryption did not complete" -ForegroundColor Red
} else {
    Write-Host "  Azure Disk Encryption Complete" -ForegroundColor Cyan
}
Write-Host "========================================`n" -ForegroundColor Cyan

Exit-Lab -FailureCount $failures
