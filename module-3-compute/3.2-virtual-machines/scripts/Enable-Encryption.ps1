<#
.SYNOPSIS
    Enables Azure Disk Encryption on Lab 3.2 VMs.

.DESCRIPTION
    This script enables Azure Disk Encryption (ADE) on Auth and World VMs.
    ADE for Linux requires Azure CLI (not available via Portal or Bicep).
    
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
$originalSize = 'Standard_B2s'
$encryptionSize = 'Standard_B2ms'  # 8 GB RAM required for ADE

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

# Check Azure CLI login
$account = az account show 2>$null | ConvertFrom-Json
if (-not $account) {
    Write-Error "Not logged into Azure CLI. Run 'az login' first."
    exit 1
}
Write-Host "✓ Logged in as: $($account.user.name)" -ForegroundColor Green

# Check Key Vault exists
Write-Host "`n[1/5] Checking Key Vault..." -ForegroundColor Yellow
$kv = az keyvault show --name $kvName --resource-group $rgName 2>$null | ConvertFrom-Json
if (-not $kv) {
    Write-Error "Key Vault '$kvName' not found. Deploy with -EncryptionStrategy AzureDiskEncryption first."
    exit 1
}
Write-Host "  ✓ Key Vault found: $kvName" -ForegroundColor Green

# Check VMs exist and get current sizes
Write-Host "`n[2/5] Checking VMs..." -ForegroundColor Yellow
$vmInfo = @{}
foreach ($vmName in $VmNames) {
    $vm = az vm show --name $vmName --resource-group $rgName 2>$null | ConvertFrom-Json
    if (-not $vm) {
        Write-Error "VM '$vmName' not found in resource group '$rgName'"
        exit 1
    }
    $vmInfo[$vmName] = @{
        CurrentSize = $vm.hardwareProfile.vmSize
        PowerState = (az vm get-instance-view --name $vmName --resource-group $rgName --query "instanceView.statuses[?starts_with(code, 'PowerState/')].displayStatus" -o tsv)
    }
    Write-Host "  ✓ $vmName (Size: $($vmInfo[$vmName].CurrentSize), State: $($vmInfo[$vmName].PowerState))" -ForegroundColor Green
}

# Confirm operation
Write-Host "`n[3/5] Resize VMs to $encryptionSize (8 GB RAM required for ADE)" -ForegroundColor Yellow
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
    
    $currentSize = $vmInfo[$vmName].CurrentSize
    
    # Resize VM if needed
    if ($currentSize -ne $encryptionSize) {
        Write-Host "  Deallocating VM..." -ForegroundColor Yellow
        az vm deallocate --name $vmName --resource-group $rgName --no-wait
        
        Write-Host "  Waiting for deallocation..." -ForegroundColor Yellow
        az vm wait --name $vmName --resource-group $rgName --custom "instanceView.statuses[?code=='PowerState/deallocated']"
        
        Write-Host "  Resizing to $encryptionSize..." -ForegroundColor Yellow
        az vm resize --name $vmName --resource-group $rgName --size $encryptionSize
        
        Write-Host "  Starting VM..." -ForegroundColor Yellow
        az vm start --name $vmName --resource-group $rgName
        
        Write-Host "  ✓ VM resized and started" -ForegroundColor Green
    } else {
        Write-Host "  VM already at $encryptionSize size" -ForegroundColor Green
    }
    
    # Enable Azure Disk Encryption
    Write-Host "  Enabling Azure Disk Encryption..." -ForegroundColor Yellow
    Write-Host "  (This may take 15-30 minutes per VM)" -ForegroundColor Gray
    
    $encryptResult = az vm encryption enable `
        --name $vmName `
        --resource-group $rgName `
        --disk-encryption-keyvault $kvName `
        --volume-type All `
        --force 2>&1
    
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Failed to enable encryption on $vmName : $encryptResult"
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
        
        $status = az vm encryption show --name $vmName --resource-group $rgName 2>$null | ConvertFrom-Json
        $osEncrypted = $status.disks | Where-Object { $_.name -like "*osdisk*" } | Select-Object -ExpandProperty statuses | Where-Object { $_.code -eq 'EncryptionState/encrypted' }
        
        if ($osEncrypted) {
            Write-Host "  ✓ Encryption completed!" -ForegroundColor Green
            break
        }
        
        Write-Host "    Still encrypting... (attempt $attempt of $maxAttempts)" -ForegroundColor Gray
        
    } while ($attempt -lt $maxAttempts)
    
    if ($attempt -ge $maxAttempts) {
        Write-Warning "Encryption still in progress after 30 minutes. Check status manually:"
        Write-Host "  az vm encryption show --name $vmName --resource-group $rgName"
    }
    
    # Resize back if requested
    if ($ResizeBack -and $currentSize -ne $encryptionSize) {
        Write-Host "  Resizing back to $currentSize..." -ForegroundColor Yellow
        az vm deallocate --name $vmName --resource-group $rgName
        az vm wait --name $vmName --resource-group $rgName --custom "instanceView.statuses[?code=='PowerState/deallocated']"
        az vm resize --name $vmName --resource-group $rgName --size $currentSize
        az vm start --name $vmName --resource-group $rgName
        Write-Host "  ✓ VM resized back to $currentSize" -ForegroundColor Green
    }
}

# Final verification
Write-Host "`n[5/5] Verification" -ForegroundColor Yellow
foreach ($vmName in $VmNames) {
    Write-Host "`n  $vmName :" -ForegroundColor Cyan
    az vm encryption show --name $vmName --resource-group $rgName --query "{OS:disks[0].statuses[0].code, Data:disks[1].statuses[0].code}" -o table
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  Azure Disk Encryption Complete" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan
