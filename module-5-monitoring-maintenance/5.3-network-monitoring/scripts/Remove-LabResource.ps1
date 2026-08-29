<#
.SYNOPSIS
    Removes Lab 5.3 Network Monitoring & Diagnostics resources.

.DESCRIPTION
    Cleans up Lab 5.3 network monitoring resources in the following order:
    1. Connection Monitor (skycraft-hub-spoke-cm)
    2. VNet Flow Log (prod-skycraft-swc-vnet-flowlog)
    3. NetworkWatcherAgent extension on the connection monitor endpoint VMs
       (the VMs themselves belong to Lab 3.2 and are left in place)
    4. Traffic Analytics data collection rule and endpoint (NWTA-*) that Azure
       creates in the platform resource group when Traffic Analytics is enabled

    Note: This does NOT remove infrastructure from earlier labs (VMs, VNets,
    Storage Accounts, Log Analytics Workspace, or the Network Watcher itself,
    which Azure provisions once per region and shares across the subscription).

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
#Requires -Modules Az.Accounts, Az.Network, Az.Compute, Az.Resources

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
$platformRg            = 'platform-skycraft-swc-rg'
$location              = 'swedencentral'

# VMs Deploy-Bicep.ps1 can pick as connection monitor endpoints. Only used as a
# fallback when the connection monitor is already gone and its endpoints — the
# authoritative list of VMs that received the agent — can no longer be read.
$candidateVms = @(
    @{ ResourceGroupName = 'prod-skycraft-swc-rg'; Name = 'prod-skycraft-swc-auth-vm' }
    @{ ResourceGroupName = 'dev-skycraft-swc-rg';  Name = 'dev-skycraft-swc-auth-vm' }
    @{ ResourceGroupName = 'dev-skycraft-swc-rg';  Name = 'dev-skycraft-swc-world-vm' }
)

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  Lab 5.3 - Resource Cleanup" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

$context = Get-AzContext
if (-not $context) {
    Write-Host "  [ERROR] Not logged into Azure. Run 'Connect-AzAccount' first." -ForegroundColor Red
    exit 1
}
Write-Host "  Account: $($context.Account.Id)" -ForegroundColor Gray

$connectionMonitorResourceId = "/subscriptions/$($context.Subscription.Id)/resourceGroups/$networkWatcherRg/providers/Microsoft.Network/networkWatchers/$networkWatcherName/connectionMonitors/$connectionMonitorName"

Write-Host "`n  The following resources will be removed:" -ForegroundColor Yellow
Write-Host "    - Connection Monitor:  $connectionMonitorName (location: $location)"
Write-Host "    - VNet Flow Log:       $flowLogName (location: $location)"
Write-Host "    - VM extension:        NetworkWatcherAgent on the connection monitor endpoint VMs"
Write-Host "    - Traffic Analytics:   NWTA-* data collection rule + endpoint in $platformRg"

# ── [1/4] Remove Connection Monitor ───────────────────────────────────────
Write-Host "`n[1/4] Removing Connection Monitor '$connectionMonitorName'..." -ForegroundColor Yellow
$endpointVmIds = [System.Collections.Generic.List[string]]::new()
try {
    # Read the raw ARM body before deleting: its AzureVM endpoints name the VMs
    # that carry the NetworkWatcherAgent extension removed in step [3/4], and
    # they cannot be read once the monitor is gone.
    $cmResource = Get-AzResource -ResourceId $connectionMonitorResourceId -ExpandProperties -ErrorAction SilentlyContinue
    if ($cmResource) {
        foreach ($endpoint in @($cmResource.Properties.endpoints)) {
            if ($endpoint.resourceId -like '*/providers/Microsoft.Compute/virtualMachines/*') {
                $endpointVmIds.Add([string]$endpoint.resourceId)
            }
        }
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

# ── [2/4] Remove VNet Flow Log ────────────────────────────────────────────
Write-Host "`n[2/4] Removing VNet Flow Log '$flowLogName'..." -ForegroundColor Yellow
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

# ── [3/4] Remove the NetworkWatcherAgent extensions ───────────────────────
# Deploy-Bicep.ps1 installs NetworkWatcherAgentLinux on both connection monitor
# endpoint VMs — a VM endpoint cannot be probed without it. No other lab uses
# the agent, so cleanup removes it here instead of letting it survive until
# Lab 3.2 deletes the VMs themselves.
Write-Host "`n[3/4] Removing NetworkWatcherAgent extensions..." -ForegroundColor Yellow

if ($endpointVmIds.Count -eq 0) {
    foreach ($candidate in $candidateVms) {
        $candidateVm = Get-AzVM -ResourceGroupName $candidate.ResourceGroupName -Name $candidate.Name -ErrorAction SilentlyContinue
        if ($candidateVm) { $endpointVmIds.Add($candidateVm.Id) }
    }
}

if ($endpointVmIds.Count -eq 0) {
    Write-Host "  ✓ No connection monitor endpoint VMs found - nothing to remove" -ForegroundColor Gray
}

foreach ($vmId in ($endpointVmIds | Select-Object -Unique)) {
    $vmRg   = ($vmId -split '/')[4]
    $vmName = ($vmId -split '/')[-1]
    try {
        if (-not (Get-AzVM -ResourceGroupName $vmRg -Name $vmName -ErrorAction SilentlyContinue)) {
            Write-Host "  ✓ VM not found (already removed): $vmName" -ForegroundColor Gray
            continue
        }
        $agents = @(Get-AzVMExtension -ResourceGroupName $vmRg -VMName $vmName -ErrorAction SilentlyContinue |
            Where-Object { $_.Publisher -eq 'Microsoft.Azure.NetworkWatcher' })
        if ($agents.Count -eq 0) {
            Write-Host "  ✓ No NetworkWatcherAgent on $vmName (already removed)" -ForegroundColor Gray
            continue
        }
        foreach ($agent in $agents) {
            # Deploy-Bicep.ps1 tags every agent it installs with Project=SkyCraft
            # and skips a VM that already has one, so an untagged agent came from
            # somewhere else — leave it to its owner.
            $agentTags = (Get-AzResource -ResourceId $agent.Id -ErrorAction SilentlyContinue).Tags
            if ($agentTags.Project -ne 'SkyCraft') {
                Write-Host "  [SKIP] $($agent.Name) on $vmName is not tagged Project=SkyCraft - left in place" -ForegroundColor Gray
                continue
            }
            if ($PSCmdlet.ShouldProcess("$vmName/$($agent.Name)", 'Remove VM extension')) {
                Remove-AzVMExtension -ResourceGroupName $vmRg -VMName $vmName -Name $agent.Name -Force -ErrorAction Stop | Out-Null
                Write-Host "  ✓ NetworkWatcherAgent removed from $vmName" -ForegroundColor Green
            }
        }
    } catch {
        Write-Host "  [ERROR] Failed to remove NetworkWatcherAgent from ${vmName}: $($_.Exception.Message)" -ForegroundColor Red
    }
}

# ── [4/4] Remove the Traffic Analytics DCR / DCE ──────────────────────────
# Enabling Traffic Analytics makes Azure create an NWTA-<workspace-guid>-<region>
# data collection rule and endpoint next to the workspace. They are Azure's own
# artifacts — main.bicep never declares them — and they survive the flow log, so
# cleanup removes them once no flow log feeds them any more.
Write-Host "`n[4/4] Removing Traffic Analytics data collection resources..." -ForegroundColor Yellow
try {
    $taFlowLogs = @()
    try {
        $taFlowLogs = @(Get-AzNetworkWatcherFlowLog -NetworkWatcherName $networkWatcherName -ResourceGroupName $networkWatcherRg -ErrorAction Stop |
            Where-Object { $_.FlowAnalyticsConfiguration.NetworkWatcherFlowAnalyticsConfiguration.Enabled -eq $true })
    } catch {
        # Az builds that require -Name cannot list; fall back to the lab's own flow log.
        $taFlowLogs = @(Get-AzNetworkWatcherFlowLog -NetworkWatcherName $networkWatcherName -ResourceGroupName $networkWatcherRg -Name $flowLogName -ErrorAction SilentlyContinue |
            Where-Object { $_.FlowAnalyticsConfiguration.NetworkWatcherFlowAnalyticsConfiguration.Enabled -eq $true })
    }

    if ($taFlowLogs.Count -gt 0) {
        Write-Host "  [SKIP] $($taFlowLogs.Count) flow log(s) still use Traffic Analytics - NWTA-* resources left in place" -ForegroundColor Yellow
    } else {
        $taResources = @(Get-AzResource -ResourceGroupName $platformRg -ErrorAction SilentlyContinue |
            Where-Object {
                $_.Name -like 'NWTA-*' -and
                $_.ResourceType -in @('Microsoft.Insights/dataCollectionRules', 'Microsoft.Insights/dataCollectionEndpoints')
            })
        if ($taResources.Count -eq 0) {
            Write-Host "  ✓ No NWTA-* data collection resources found (already removed)" -ForegroundColor Gray
        }
        # Descending sort puts dataCollectionRules before dataCollectionEndpoints:
        # the rule references the endpoint, so it has to go first.
        foreach ($taResource in ($taResources | Sort-Object ResourceType -Descending)) {
            $taKind = ($taResource.ResourceType -split '/')[-1]
            try {
                if ($PSCmdlet.ShouldProcess($taResource.Name, "Remove Traffic Analytics $taKind")) {
                    Remove-AzResource -ResourceId $taResource.ResourceId -Force -ErrorAction Stop | Out-Null
                    Write-Host "  ✓ Traffic Analytics $taKind removed: $($taResource.Name)" -ForegroundColor Green
                }
            } catch {
                Write-Host "  [ERROR] Failed to remove $($taResource.Name): $($_.Exception.Message)" -ForegroundColor Red
            }
        }
    }
} catch {
    Write-Host "  [ERROR] Failed to inspect Traffic Analytics resources: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  Cleanup Complete" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan
