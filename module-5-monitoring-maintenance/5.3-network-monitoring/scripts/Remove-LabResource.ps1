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

#Requires -Version 7.0
#Requires -Modules Az.Accounts, Az.Network

[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter()]
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
if ($Force) { $ConfirmPreference = 'None' }

# Configuration
$networkWatcherRg      = 'NetworkWatcherRG'
$networkWatcherName    = 'NetworkWatcher_swedencentral'
$connectionMonitorName = 'skycraft-hub-spoke-cm'
$flowLogName           = 'prod-skycraft-swc-vnet-flowlog'
$location              = 'swedencentral'

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  Lab 5.3 - Resource Cleanup" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

$context = Get-AzContext
if (-not $context) {
    Write-Host "  [ERROR] Not logged into Azure. Run 'Connect-AzAccount' first." -ForegroundColor Red
    exit 1
}
Write-Host "  Account: $($context.Account.Id)" -ForegroundColor Gray

Write-Host "`n  The following resources will be removed:" -ForegroundColor Yellow
Write-Host "    - Connection Monitor: $connectionMonitorName (location: $location)"
Write-Host "    - VNet Flow Log:      $flowLogName (location: $location)"

# ── [1/2] Remove Connection Monitor ───────────────────────────────────────
Write-Host "`n[1/2] Removing Connection Monitor '$connectionMonitorName'..." -ForegroundColor Yellow
try {
    $cmExists = Get-AzNetworkWatcherConnectionMonitor -NetworkWatcherName $networkWatcherName -ResourceGroupName $networkWatcherRg -Name $connectionMonitorName -ErrorAction SilentlyContinue
    if ($cmExists) {
        if ($PSCmdlet.ShouldProcess($connectionMonitorName, 'Remove Connection Monitor')) {
            Remove-AzNetworkWatcherConnectionMonitor -NetworkWatcherName $networkWatcherName -ResourceGroupName $networkWatcherRg -Name $connectionMonitorName -Confirm:$false -ErrorAction Stop | Out-Null
            Write-Host "  ✓ Connection Monitor removed: $connectionMonitorName" -ForegroundColor Green
        }
    } else {
        Write-Host "  ✓ Connection Monitor not found (already removed): $connectionMonitorName" -ForegroundColor Gray
    }
} catch {
    Write-Host "  [ERROR] Failed to remove Connection Monitor: $($_.Exception.Message)" -ForegroundColor Red
}

# ── [2/2] Remove VNet Flow Log ────────────────────────────────────────────
Write-Host "`n[2/2] Removing VNet Flow Log '$flowLogName'..." -ForegroundColor Yellow
try {
    $flExists = Get-AzNetworkWatcherFlowLog -NetworkWatcherName $networkWatcherName -ResourceGroupName $networkWatcherRg -Name $flowLogName -ErrorAction SilentlyContinue
    if ($flExists) {
        if ($PSCmdlet.ShouldProcess($flowLogName, 'Remove VNet Flow Log')) {
            Remove-AzNetworkWatcherFlowLog -NetworkWatcherName $networkWatcherName -ResourceGroupName $networkWatcherRg -Name $flowLogName -Confirm:$false -ErrorAction Stop | Out-Null
            Write-Host "  ✓ VNet Flow Log removed: $flowLogName" -ForegroundColor Green
        }
    } else {
        Write-Host "  ✓ VNet Flow Log not found (already removed): $flowLogName" -ForegroundColor Gray
    }
} catch {
    Write-Host "  [ERROR] Failed to remove VNet Flow Log: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  Cleanup Complete" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan
