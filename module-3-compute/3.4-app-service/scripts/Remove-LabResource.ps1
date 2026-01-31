<#
.SYNOPSIS
    Removes Lab 3.4 resources.

.DESCRIPTION
    Deletes the Web App, App Service Plan, and Autoscale settings used in Lab 3.4.
    Does NOT delete the Resource Group or VNet (shared resources).

.EXAMPLE
    .\Remove-LabResource.ps1

.NOTES
    Project: SkyCraft
    Date: 2026-01-31
#>

[CmdletBinding()]
param(
    [string]$RgName = "dev-skycraft-swc-rg"
)

Write-Host "=== Cleanup Lab 3.4: App Service ===" -ForegroundColor Cyan
Write-Host "Target Resource Group: $RgName" -ForegroundColor Yellow

# 1. Verify Connection
if (-not (Get-AzContext)) { Write-Host "Not logged in." -ForegroundColor Red; exit 1 }

$confirm = Read-Host "Are you sure you want to delete App Service resources? (y/n)"
if ($confirm -ne 'y') { exit }

try {
    # Delete Web App (and slots)
    Write-Host "Removing Web App 'dev-skycraft-swc-app01'..." -ForegroundColor Yellow
    Remove-AzWebApp -ResourceGroupName $RgName -Name "dev-skycraft-swc-app01" -Force -ErrorAction SilentlyContinue

    # Delete Autoscale Settings
    Write-Host "Removing Autoscale Settings..." -ForegroundColor Yellow
    Get-AzAutoscaleSetting -ResourceGroupName $RgName -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "*autoscale*" } | Remove-AzAutoscaleSetting -ErrorAction SilentlyContinue

    # Delete App Service Plan
    Write-Host "Removing App Service Plan 'dev-skycraft-swc-asp'..." -ForegroundColor Yellow
    Remove-AzAppServicePlan -ResourceGroupName $RgName -Name "dev-skycraft-swc-asp" -Force -ErrorAction SilentlyContinue

    Write-Host "Cleanup completed successfully." -ForegroundColor Green
}
catch {
    Write-Host "Cleanup failed!" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
}
