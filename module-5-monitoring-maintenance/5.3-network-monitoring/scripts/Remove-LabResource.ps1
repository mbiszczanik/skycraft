<#
.SYNOPSIS
    Removes Lab 5.3 Network Monitoring & Diagnostics resources.

.DESCRIPTION
    Cleans up Lab 5.3 network monitoring resources in the following order:
    1. Connection Monitor (skycraft-hub-spoke-cm)
    2. VNet Flow Log (prod-skycraft-swc-vnet-flowlog)

    Note: This does NOT remove infrastructure from earlier labs (VMs, VNets,
    Storage Accounts, Log Analytics Workspace, or the Network Watcher itself,
    which is managed automatically by Azure).

.PARAMETER Force
    Skip confirmation prompts.

.EXAMPLE
    .\Remove-LabResource.ps1

.EXAMPLE
    .\Remove-LabResource.ps1 -Force

.NOTES
    Project: SkyCraft
    Author: SkyCraft
    Date: 2026-04-06
#>

[CmdletBinding()]
param(
    [Parameter()]
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

# Configuration
$connectionMonitorName = 'skycraft-hub-spoke-cm'
$flowLogName           = 'prod-skycraft-swc-vnet-flowlog'
$location              = 'swedencentral'

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  Lab 5.3 - Resource Cleanup" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

$account = az account show --output json 2>$null | ConvertFrom-Json
if (-not $account) {
    Write-Host "  [ERROR] Not logged into Azure CLI. Run 'az login' first." -ForegroundColor Red
    exit 1
}
Write-Host "  Account: $($account.user.name)" -ForegroundColor Gray

# Allow non-interactive installation of required Azure CLI extensions.
az config set extension.use_dynamic_install=yes_without_prompt --only-show-errors | Out-Null

Write-Host "`n  The following resources will be removed:" -ForegroundColor Yellow
Write-Host "    - Connection Monitor: $connectionMonitorName (location: $location)"
Write-Host "    - VNet Flow Log:      $flowLogName (location: $location)"

if (-not $Force) {
    $confirm = Read-Host "`nProceed with cleanup? (y/N)"
    if ($confirm -ne 'y') {
        Write-Host "Cleanup cancelled." -ForegroundColor Yellow
        exit 0
    }
}

# ── [1/2] Remove Connection Monitor ───────────────────────────────────────
Write-Host "`n[1/2] Removing Connection Monitor '$connectionMonitorName'..." -ForegroundColor Yellow
try {
    $cmExists = az network watcher connection-monitor show `
        --name $connectionMonitorName `
        --location $location `
        --output json 2>$null | ConvertFrom-Json
    if ($cmExists) {
        az network watcher connection-monitor delete `
            --name $connectionMonitorName `
            --location $location `
            --output none 2>$null
        Write-Host "  ✓ Connection Monitor removed: $connectionMonitorName" -ForegroundColor Green
    } else {
        Write-Host "  ✓ Connection Monitor not found (already removed): $connectionMonitorName" -ForegroundColor Gray
    }
} catch {
    Write-Host "  [ERROR] Failed to remove Connection Monitor: $($_.Exception.Message)" -ForegroundColor Red
}

# ── [2/2] Remove VNet Flow Log ────────────────────────────────────────────
Write-Host "`n[2/2] Removing VNet Flow Log '$flowLogName'..." -ForegroundColor Yellow
try {
    # az network watcher flow-log show/delete accept --location only (not --resource-group)
    $flExists = az network watcher flow-log show `
        --name $flowLogName `
        --location $location `
        --output json 2>$null | ConvertFrom-Json
    if ($flExists) {
        az network watcher flow-log delete `
            --name $flowLogName `
            --location $location `
            --output none 2>$null
        Write-Host "  ✓ VNet Flow Log removed: $flowLogName" -ForegroundColor Green
    } else {
        Write-Host "  ✓ VNet Flow Log not found (already removed): $flowLogName" -ForegroundColor Gray
    }
} catch {
    Write-Host "  [ERROR] Failed to remove VNet Flow Log: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  Cleanup Complete" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan
