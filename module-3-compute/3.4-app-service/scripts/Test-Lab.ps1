<#
.SYNOPSIS
    Validates Module 3.4 App Service deployment.

.DESCRIPTION
    Checks if the App Service Plan, Web App, Slots, and Autoscale rules are correctly configured.

.EXAMPLE
    .\Test-Lab.ps1

.NOTES
    Project: SkyCraft
    Date: 2026-01-31
#>

[CmdletBinding()]
param(
    [string]$RgName = "dev-skycraft-swc-rg",
    [string]$AspName = "dev-skycraft-swc-asp",
    [string]$AppName = "dev-skycraft-swc-app01"
)

Write-Host "=== Lab 3.4 Validation: App Service ===" -ForegroundColor Cyan

# 1. Verify Connection
if (-not (Get-AzContext)) { Write-Host "Not logged in." -ForegroundColor Red; exit 1 }

$failures = 0

# Helper function
function Assert-Resource {
    param($Name, $Condition, $Message)
    if ($Condition) {
        Write-Host "  [OK] $Message" -ForegroundColor Green
    } else {
        Write-Host "  [FAIL] $Message ($Name)" -ForegroundColor Red
        $script:failures++
    }
}

# 2. Check App Service Plan
Write-Host "1. Checking App Service Plan..." -ForegroundColor Yellow
$asp = Get-AzAppServicePlan -ResourceGroupName $RgName -Name $AspName -ErrorAction SilentlyContinue

if ($asp) {
    Assert-Resource $AspName ($asp.Sku.Tier -eq "PremiumV3" -or $asp.Sku.Tier -eq "Premium0V3") "Tier is Premium V4 (P0V4/P0v3)"
    Assert-Resource $AspName ($asp.Kind -like "*linux*") "OS is Linux"
    Assert-Resource $AspName ($asp.Status -eq "Ready") "Status is Ready"
} else {
    Write-Host "  [FAIL] App Service Plan '$AspName' not found!" -ForegroundColor Red; $failures++
}

# 3. Check Web App
Write-Host "2. Checking Web App..." -ForegroundColor Yellow
$app = Get-AzWebApp -ResourceGroupName $RgName -Name $AppName -ErrorAction SilentlyContinue

if ($app) {
    Assert-Resource $AppName ($app.State -eq "Running") "App is Running"
    Assert-Resource $AppName ($app.HttpsOnly -eq $true) "HTTPS Only is Enabled"
    
    # Check VNet Integration using CLI for reliability
    $vnetId = az webapp show --name $AppName --resource-group $RgName --query "virtualNetworkSubnetId" -o tsv 2>$null
    Assert-Resource $AppName ($vnetId -like "*AppServiceSubnet*") "VNet Integration Configured"
} else {
    Write-Host "  [FAIL] Web App '$AppName' not found!" -ForegroundColor Red; $failures++
}

# 4. Check Deployment Slots
Write-Host "3. Checking Deployment Slots..." -ForegroundColor Yellow
$slot = Get-AzWebAppSlot -ResourceGroupName $RgName -Name $AppName -Slot "staging" -ErrorAction SilentlyContinue
Assert-Resource "staging" ($null -ne $slot) "Slot 'staging' exists"

# 5. Check Autoscale Settings
Write-Host "4. Checking Autoscale Rules..." -ForegroundColor Yellow
$autoScaleName = "${AspName}-autoscale"
$settings = Get-AzAutoscaleSetting -ResourceGroupName $RgName -Name $autoScaleName -ErrorAction SilentlyContinue

if ($settings) {
    # Profiles is a list, usually one profile
    $profile = $settings.Profiles[0]
    Assert-Resource "Autoscale" ($profile.Capacity.Minimum -eq "1" -and $profile.Capacity.Maximum -eq "3") "Instance limits (1-3) correct"
    Assert-Resource "Autoscale" ($profile.Rules.Count -ge 2) "Found $($profile.Rules.Count) scaling rules"
} else {
    Write-Host "  [FAIL] Autoscale setting '$autoScaleName' not found!" -ForegroundColor Red; $failures++
}

# Summary
Write-Host "`nValidation Summary" -ForegroundColor Cyan
if ($failures -eq 0) {
    Write-Host "SUCCESS: All checks passed!" -ForegroundColor Green
} else {
    Write-Host "FAILURE: Found $failures issues." -ForegroundColor Red
    exit 1
}
