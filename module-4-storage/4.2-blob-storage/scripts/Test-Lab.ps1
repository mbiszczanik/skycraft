<#
.SYNOPSIS
    Verifies Lab 4.2 Infrastructure (Blob Storage).

.DESCRIPTION
    Checks compliance for production and development storage accounts against lab requirements.

.PARAMETER ProdRgName
    Resoure group name for production. Default: prod-skycraft-swc-rg

.PARAMETER DevRgName
    Resoure group name for development. Default: dev-skycraft-swc-rg

.EXAMPLE
    .\Test-Lab.ps1

.NOTES
    Project: SkyCraft
    Author: SkyCraft
#>

[CmdletBinding()]
param(
    [string]$ProdRgName = 'prod-skycraft-swc-rg',
    [string]$DevRgName = 'dev-skycraft-swc-rg',
    [string]$ProdSaName = 'prodskycraftswcsa',
    [string]$DevSaName = 'devskycraftswcsa'
)

$ErrorActionPreference = 'Stop'
$TestsPassed = 0
$TestsTotal = 0

function Assert-Check {
    param(
        [string]$Description,
        [bool]$Condition,
        [string]$SuccessMessage = "OK",
        [string]$FailureMessage = "FAIL"
    )
    $script:TestsTotal++
    Write-Host "  Checking: $Description ... " -NoNewline
    if ($Condition) {
        Write-Host "PASS ($SuccessMessage)" -ForegroundColor Green
        $script:TestsPassed++
    }
    else {
        Write-Host "FAIL ($FailureMessage)" -ForegroundColor Red
    }
}

Write-Host "`n=== Lab 4.2: Verifying Blob Storage Configuration ===" -ForegroundColor Cyan

# 1. Environment Check
try {
    $prodSa = Get-AzStorageAccount -ResourceGroupName $ProdRgName -Name $ProdSaName -ErrorAction Stop
    $devSa = Get-AzStorageAccount -ResourceGroupName $DevRgName -Name $DevSaName -ErrorAction Stop
}
catch {
    Write-Host "FATAL: Could not retrieve storage accounts. Ensure deployment succeeded." -ForegroundColor Red
    exit 1
}

# 2. Production Security Verification (Privacy & Versioning)
Write-Host "`n--- Production Verification (Secure) ---" -ForegroundColor Yellow

# AllowBlobPublicAccess MUST be False
Assert-Check "PROD: AllowBlobPublicAccess is disabled" `
    -Condition ($prodSa.AllowBlobPublicAccess -eq $false) `
    -SuccessMessage "Public Access Disabled" `
    -FailureMessage "Public Access Enabled (Security Risk!)"

# Versioning MUST be enabled
$prodBlobService = Get-AzStorageBlobServiceProperty -ResourceGroupName $ProdRgName -StorageAccountName $ProdSaName
Assert-Check "PROD: Versioning enabled" `
    -Condition ($prodBlobService.IsVersioningEnabled -eq $true) `
    -SuccessMessage "Versioning ON" `
    -FailureMessage "Versioning OFF"

# Containers Verification
$prodCtx = $prodSa.Context
$prodContainers = Get-AzStorageContainer -Context $prodCtx

$gameAssets = $prodContainers | Where-Object Name -eq 'game-assets'
Assert-Check "PROD: 'game-assets' container exists" `
    -Condition ($null -ne $gameAssets)

if ($gameAssets) {
    Assert-Check "PROD: 'game-assets' is PRIVATE" `
        -Condition ($gameAssets.PublicAccess -eq 'Off') `
        -SuccessMessage "Private Access" `
        -FailureMessage "Public Access detected! Should be Private."
}

# Lifecycle Management Verification
$prodPolicy = Get-AzStorageAccountManagementPolicy -ResourceGroupName $ProdRgName -StorageAccountName $ProdSaName -ErrorAction SilentlyContinue
Assert-Check "PROD: Lifecycle Policy exists" `
    -Condition ($null -ne $prodPolicy)

if ($prodPolicy) {
    $rules = $prodPolicy.Rules | Select-Object -ExpandProperty Name
    Assert-Check "PROD: 'tier-game-logs' rule present" -Condition ($rules -contains 'tier-game-logs')
    Assert-Check "PROD: 'archive-backups' rule present" -Condition ($rules -contains 'archive-backups')
}

# 3. Development Verification (Exam Prep - Public Access)
Write-Host "`n--- Development Verification (Exam Prep) ---" -ForegroundColor Yellow

# AllowBlobPublicAccess MUST be True (for AZ-104 demo)
Assert-Check "DEV: AllowBlobPublicAccess is enabled" `
    -Condition ($devSa.AllowBlobPublicAccess -eq $true) `
    -SuccessMessage "Public Access Enabled (Exam Req)" `
    -FailureMessage "Public Access Disabled (Lab 4.2/Exam Req Missing)"

# Versioning should be Disabled (default)
$devBlobService = Get-AzStorageBlobServiceProperty -ResourceGroupName $DevRgName -StorageAccountName $DevSaName
Assert-Check "DEV: Versioning disabled (scope check)" `
    -Condition ($devBlobService.IsVersioningEnabled -eq $false)

# Public Container Verification
$devCtx = $devSa.Context
$devContainer = Get-AzStorageContainer -Context $devCtx -Name 'public-demo' -ErrorAction SilentlyContinue

Assert-Check "DEV: 'public-demo' container exists" `
    -Condition ($null -ne $devContainer)

if ($devContainer) {
    Assert-Check "DEV: 'public-demo' allows Blob public access" `
        -Condition ($devContainer.PublicAccess -eq 'Blob') `
        -SuccessMessage "Public Blob Access OK" `
        -FailureMessage "Access is $($devContainer.PublicAccess), expected Blob"
}

# Summary
Write-Host "`n=== Test Summary ===" -ForegroundColor Cyan
Write-Host "Tests Passed: $TestsPassed / $TestsTotal"
if ($TestsPassed -eq $TestsTotal) {
    Write-Host "SUCCESS: Lab 4.2 compliant!" -ForegroundColor Green
    exit 0
}
else {
    Write-Host "FAILURE: Some checks failed." -ForegroundColor Red
    exit 1
}
