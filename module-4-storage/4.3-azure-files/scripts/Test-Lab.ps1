<#
.SYNOPSIS
    Validates Lab 4.3 Deployment
.DESCRIPTION
    Checks if resources exist and are configured correctly according to Lab 4.3 standards.
    Checks for Storage Account redundancy, File Shares, quotas, and Soft Delete policy.
.PARAMETER Environment
    The environment to validate (prod, dev, platform). Default: prod.
.EXAMPLE
    .\Test-Lab.ps1 -Environment prod
.NOTES
    Project: SkyCraft
    Author: SkyCraft
    Date: 2026-02-07
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$Environment = 'prod'
)

$resourceGroupName = "$Environment-skycraft-swc-rg"
$storageAccountName = "${Environment}skycraftswcsa"
$expectedSku = ($Environment -eq 'prod' -or $Environment -eq 'platform') ? 'Standard_GRS' : 'Standard_LRS'

Write-Host "=== Lab 4.3: Validating Azure Files Environment ===" -ForegroundColor Cyan

# 1. Verify Connection
if (-not (Get-AzContext)) {
    Write-Host " [ERROR] Not logged in. Please run Connect-AzAccount." -ForegroundColor Red; exit 1
}

# 2. Check Storage Account
try {
    Write-Host "Checking Storage Account '$storageAccountName'..." -ForegroundColor Yellow
    $sa = Get-AzStorageAccount -ResourceGroupName $resourceGroupName -Name $storageAccountName -ErrorAction Stop
    
    # Verify SKU
    if ($sa.Sku.Name -eq $expectedSku) {
        Write-Host "  -> SKU is correct: $($sa.Sku.Name)" -ForegroundColor Green
    }
    else {
        Write-Host "  -> [WARNING] SKU mismatch. Expected: $expectedSku, Found: $($sa.Sku.Name)" -ForegroundColor Yellow
    }

    # Verify File Service Soft Delete
    $fileProps = Get-AzStorageAccount -ResourceGroupName $resourceGroupName -Name $storageAccountName
    $softDelete = $fileProps.FileService.ShareDeleteRetentionPolicy
    if ($softDelete.Enabled -and $softDelete.Days -ge 14) {
        Write-Host "  -> Soft Delete is correctly enabled for $($softDelete.Days) days" -ForegroundColor Green
    }
    else {
        Write-Host "  -> [WARNING] Soft Delete not configured correctly (Enabled: $($softDelete.Enabled), Days: $($softDelete.Days))" -ForegroundColor Yellow
    }
}
catch {
    Write-Host "  -> [ERROR] Storage Account not found or accessible." -ForegroundColor Red
    return
}

# 3. Check File Shares
try {
    Write-Host "Checking File Shares..." -ForegroundColor Yellow
    $shares = Get-AzStorageShare -Context $sa.Context -ErrorAction SilentlyContinue

    if ($shares) {
        $sharesToCheck = @('skycraft-config', 'skycraft-shared')
        foreach ($shareName in $sharesToCheck) {
            $share = $shares | Where-Object { $_.Name -eq $shareName }
            if ($share) {
                Write-Host "  -> Found Share: $($share.Name) (Quota: $($share.Quota)GB, Tier: $($share.AccessTier))" -ForegroundColor Green
            }
            else {
                Write-Host "  -> [MISSING] File Share '$shareName' not found." -ForegroundColor Red
            }
        }
    }
    else {
        Write-Host "  -> [INFO] No file shares found. Please create them as per the lab guide." -ForegroundColor Gray
    }
}
catch {
    Write-Host "  -> [ERROR] Could not list file shares." -ForegroundColor Red
}

Write-Host "`nValidation Complete." -ForegroundColor Cyan
