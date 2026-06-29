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

#Requires -Version 7.0
#Requires -Modules Az.Accounts, Az.Storage

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [ValidateSet('prod', 'dev', 'platform')]
    [string]$Environment = 'prod'
)

$ErrorActionPreference = 'Stop'
$failCount = 0

$resourceGroupName  = "$Environment-skycraft-swc-rg"
$storageAccountName = "${Environment}skycraftswcsa"
$expectedSku        = ($Environment -eq 'prod' -or $Environment -eq 'platform') ? 'Standard_GRS' : 'Standard_LRS'

Write-Host "=== Lab 4.3: Validating Azure Files Environment ===" -ForegroundColor Cyan

# 1. Verify Connection
if (-not (Get-AzContext)) {
    Write-Host " [ERROR] Not logged in. Please run Connect-AzAccount." -ForegroundColor Red; exit 1
}

# 2. Check Storage Account
$sa = $null
try {
    Write-Host "Checking Storage Account '$storageAccountName'..." -ForegroundColor Yellow
    $sa = Get-AzStorageAccount -ResourceGroupName $resourceGroupName -Name $storageAccountName -ErrorAction Stop

    if ($sa.Sku.Name -eq $expectedSku) {
        Write-Host "  -> SKU is correct: $($sa.Sku.Name)" -ForegroundColor Green
    }
    else {
        Write-Host "  -> [FAIL] SKU mismatch. Expected: $expectedSku, Found: $($sa.Sku.Name)" -ForegroundColor Red
        $failCount++
    }

    # Verify File Service Soft Delete via management-plane cmdlet (PSStorageAccount has no .FileService property)
    $fileServiceProps = Get-AzStorageFileServiceProperty -ResourceGroupName $resourceGroupName -StorageAccountName $storageAccountName -ErrorAction SilentlyContinue
    $softDelete = $fileServiceProps.ShareDeleteRetentionPolicy
    if ($softDelete -and $softDelete.Enabled -and $softDelete.Days -ge 14) {
        Write-Host "  -> Soft Delete is correctly enabled for $($softDelete.Days) days" -ForegroundColor Green
    }
    else {
        Write-Host "  -> [FAIL] Soft Delete not configured correctly (Enabled: $($softDelete.Enabled), Days: $($softDelete.Days))" -ForegroundColor Red
        $failCount++
    }
}
catch {
    Write-Host "  -> [FAIL] Storage Account '$storageAccountName' not found or not accessible." -ForegroundColor Red
    $failCount++
    Write-Host "`nValidation Complete. Failures: $failCount" -ForegroundColor Red
    exit $failCount
}

# 3. Check File Shares via management-plane (Get-AzRmStorageShare) to read quota and tier reliably
try {
    Write-Host "Checking File Shares..." -ForegroundColor Yellow

    $sharesToCheck = @(
        @{ Name = 'skycraft-config'; ExpectedQuotaGB = 100 },
        @{ Name = 'skycraft-shared'; ExpectedQuotaGB = 500 }
    )

    foreach ($item in $sharesToCheck) {
        $share = Get-AzRmStorageShare -ResourceGroupName $resourceGroupName -StorageAccountName $storageAccountName `
            -Name $item.Name -ErrorAction SilentlyContinue
        if ($share) {
            $quotaGB = $share.ShareProperties.ShareQuota
            $tier    = $share.AccessTier
            Write-Host "  -> Found Share: $($share.Name) (Quota: ${quotaGB}GB, Tier: $tier)" -ForegroundColor Green
            if ($quotaGB -ne $item.ExpectedQuotaGB) {
                Write-Host "  -> [FAIL] $($share.Name) quota ${quotaGB}GB (Expected: $($item.ExpectedQuotaGB)GB)" -ForegroundColor Red
                $failCount++
            }
        }
        else {
            Write-Host "  -> [FAIL] File Share '$($item.Name)' not found." -ForegroundColor Red
            $failCount++
        }
    }
}
catch {
    Write-Host "  -> [FAIL] Could not list file shares: $_" -ForegroundColor Red
    $failCount++
}

Write-Host "`nValidation Complete. Failures: $failCount" -ForegroundColor $(if ($failCount -eq 0) { 'Cyan' } else { 'Red' })
exit $failCount
