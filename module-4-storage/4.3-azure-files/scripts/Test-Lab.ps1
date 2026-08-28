<#
.SYNOPSIS
    Validates Lab 4.3 Deployment
.DESCRIPTION
    Checks if resources exist and are configured correctly according to Lab 4.3 standards.
    Checks for Storage Account redundancy, File Shares, quotas, and Soft Delete policy.

    The file share check compares the deployed set against the expected set in both directions:
    a missing share and an unexpected share both fail. The lab creates exactly two shares.
.PARAMETER Environment
    The environment to validate (prod, dev, platform). Default: prod.
.EXAMPLE
    .\Test-Lab.ps1 -Environment prod
.NOTES
    Project: SkyCraft
    Author: SkyCraft
    Version: 2.1.0
    Date: 2026-08-28
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

    $expectedShares = @{
        'skycraft-config' = 100
        'skycraft-shared' = 500
    }

    # Enumerate rather than probing the expected names one by one: a hardcoded probe list can
    # only catch a missing share, never a stray one left behind by a hand-made experiment (#99).
    $actualShares = @(Get-AzRmStorageShare -ResourceGroupName $resourceGroupName -StorageAccountName $storageAccountName -ErrorAction Stop)

    foreach ($name in $expectedShares.Keys) {
        $share = $actualShares | Where-Object { $_.Name -eq $name }
        if (-not $share) {
            Write-Host "  -> [FAIL] File Share '$name' not found." -ForegroundColor Red
            $failCount++
            continue
        }

        $quotaGB = $share.QuotaGiB
        $tier    = $share.AccessTier
        Write-Host "  -> Found Share: $($share.Name) (Quota: ${quotaGB}GB, Tier: $tier)" -ForegroundColor Green
        if ($quotaGB -ne $expectedShares[$name]) {
            Write-Host "  -> [FAIL] $($share.Name) quota ${quotaGB}GB (Expected: $($expectedShares[$name])GB)" -ForegroundColor Red
            $failCount++
        }
    }

    $unexpected = $actualShares | Where-Object { -not $expectedShares.ContainsKey($_.Name) }
    foreach ($share in $unexpected) {
        Write-Host "  -> [FAIL] Unexpected File Share '$($share.Name)' - Lab 4.3 creates only $($expectedShares.Keys -join ', ')." -ForegroundColor Red
        $failCount++
    }
}
catch {
    Write-Host "  -> [FAIL] Could not list file shares: $_" -ForegroundColor Red
    $failCount++
}

Write-Host "`nValidation Complete. Failures: $failCount" -ForegroundColor $(if ($failCount -eq 0) { 'Cyan' } else { 'Red' })
exit $failCount
