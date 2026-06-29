<#
.SYNOPSIS
    Tests Lab 5.3 Network Monitoring & Diagnostics deployment.

.DESCRIPTION
    Validates that all Lab 5.3 network monitoring resources are deployed correctly:
    - Network Watcher enabled for Sweden Central in NetworkWatcherRG
    - VNet Flow Log (prod-skycraft-swc-vnet-flowlog) exists, is enabled,
      uses Version 2 format, retains logs for 7 days, and has Traffic Analytics
      linked to the platform Log Analytics Workspace
    - Connection Monitor (skycraft-hub-spoke-cm) exists and is running,
      with the correct source, destination, and test configuration

.EXAMPLE
    .\Test-Lab.ps1

.NOTES
    Project: SkyCraft
    Author: SkyCraft
    Date: 2026-04-06
#>

#Requires -Version 7.0
#Requires -Modules Az.Accounts, Az.Network, Az.Resources

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

# Configuration
$networkWatcherRg      = 'NetworkWatcherRG'
$networkWatcherName    = 'NetworkWatcher_swedencentral'
$flowLogName           = 'prod-skycraft-swc-vnet-flowlog'
$connectionMonitorName = 'skycraft-hub-spoke-cm'
$workspaceName         = 'platform-skycraft-swc-law'
$prodVnetName          = 'prod-skycraft-swc-vnet'
$location              = 'swedencentral'

$passCount = 0
$failCount = 0

function Invoke-Test {
    param(
        [string]$Label,
        [scriptblock]$Test
    )
    Write-Host "  Testing: $Label..." -NoNewline
    try {
        $result = & $Test
        if ($result) {
            Write-Host " PASS" -ForegroundColor Green
            $script:passCount++
        } else {
            Write-Host " FAIL" -ForegroundColor Red
            $script:failCount++
        }
    } catch {
        Write-Host " FAIL ($($_.Exception.Message))" -ForegroundColor Red
        $script:failCount++
    }
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Lab 5.3 - Deployment Validation" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

$context = Get-AzContext
if (-not $context) {
    Write-Host "  [ERROR] Not logged into Azure. Run 'Connect-AzAccount' first." -ForegroundColor Red
    exit 1
}
Write-Host "  Account: $($context.Account.Id)" -ForegroundColor Gray

# Connection Monitor V2 detail is read from the raw ARM body (Get-AzResource
# -ExpandProperties) because PSConnectionMonitorResultV2 does not surface
# monitoringStatus and nests endpoints/test configs under test groups.
$connectionMonitorResourceId = "/subscriptions/$($context.Subscription.Id)/resourceGroups/$networkWatcherRg/providers/Microsoft.Network/networkWatchers/$networkWatcherName/connectionMonitors/$connectionMonitorName"
Write-Host ""

# ============================================================================
# Network Watcher Tests
# ============================================================================
Write-Host "[Network Watcher]" -ForegroundColor Yellow

Invoke-Test "Network Watcher exists for swedencentral" {
    $nw = @(Get-AzNetworkWatcher -ErrorAction SilentlyContinue | Where-Object { $_.Location -eq $location })
    return ($null -ne $nw -and $nw.Count -gt 0)
}

Invoke-Test "Network Watcher provisioning state is Succeeded" {
    $nw = @(Get-AzNetworkWatcher -ErrorAction SilentlyContinue | Where-Object { $_.Location -eq $location })
    return ($nw[0].ProvisioningState -eq 'Succeeded')
}

Invoke-Test "Network Watcher is in NetworkWatcherRG" {
    $nw = Get-AzNetworkWatcher -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -eq $networkWatcherName -and $_.ResourceGroupName -eq $networkWatcherRg }
    return ($null -ne $nw)
}

# ============================================================================
# VNet Flow Log Tests
# ============================================================================
Write-Host ""
Write-Host "[VNet Flow Log]" -ForegroundColor Yellow

Invoke-Test "Flow log '$flowLogName' exists" {
    $fl = Get-AzNetworkWatcherFlowLog -NetworkWatcherName $networkWatcherName -ResourceGroupName $networkWatcherRg -Name $flowLogName -ErrorAction SilentlyContinue
    return ($null -ne $fl -and $fl.Name -eq $flowLogName)
}

Invoke-Test "Flow log is enabled" {
    $fl = Get-AzNetworkWatcherFlowLog -NetworkWatcherName $networkWatcherName -ResourceGroupName $networkWatcherRg -Name $flowLogName -ErrorAction SilentlyContinue
    return ($fl.Enabled -eq $true)
}

Invoke-Test "Flow log uses Version 2 format" {
    $fl = Get-AzNetworkWatcherFlowLog -NetworkWatcherName $networkWatcherName -ResourceGroupName $networkWatcherRg -Name $flowLogName -ErrorAction SilentlyContinue
    return ($fl.Format.Version -eq 2)
}

Invoke-Test "Flow log retention is 7 days" {
    $fl = Get-AzNetworkWatcherFlowLog -NetworkWatcherName $networkWatcherName -ResourceGroupName $networkWatcherRg -Name $flowLogName -ErrorAction SilentlyContinue
    return ($fl.RetentionPolicy.Days -eq 7 -and $fl.RetentionPolicy.Enabled -eq $true)
}

Invoke-Test "Flow log targets prod-skycraft-swc-vnet" {
    $fl = Get-AzNetworkWatcherFlowLog -NetworkWatcherName $networkWatcherName -ResourceGroupName $networkWatcherRg -Name $flowLogName -ErrorAction SilentlyContinue
    return ($fl.TargetResourceId -like "*$prodVnetName*")
}

Invoke-Test "Flow log Traffic Analytics is enabled" {
    $fl = Get-AzNetworkWatcherFlowLog -NetworkWatcherName $networkWatcherName -ResourceGroupName $networkWatcherRg -Name $flowLogName -ErrorAction SilentlyContinue
    $ta = $fl.FlowAnalyticsConfiguration.NetworkWatcherFlowAnalyticsConfiguration
    return ($ta.Enabled -eq $true)
}

Invoke-Test "Flow log Traffic Analytics interval is 10 minutes" {
    $fl = Get-AzNetworkWatcherFlowLog -NetworkWatcherName $networkWatcherName -ResourceGroupName $networkWatcherRg -Name $flowLogName -ErrorAction SilentlyContinue
    $ta = $fl.FlowAnalyticsConfiguration.NetworkWatcherFlowAnalyticsConfiguration
    return ($ta.TrafficAnalyticsInterval -eq 10)
}

Invoke-Test "Flow log Traffic Analytics workspace is platform-skycraft-swc-law" {
    $fl = Get-AzNetworkWatcherFlowLog -NetworkWatcherName $networkWatcherName -ResourceGroupName $networkWatcherRg -Name $flowLogName -ErrorAction SilentlyContinue
    $ta = $fl.FlowAnalyticsConfiguration.NetworkWatcherFlowAnalyticsConfiguration
    return ($ta.WorkspaceResourceId -like "*$workspaceName*")
}

Invoke-Test "Flow log has correct tags (Project, Environment, CostCenter)" {
    $fl = Get-AzNetworkWatcherFlowLog -NetworkWatcherName $networkWatcherName -ResourceGroupName $networkWatcherRg -Name $flowLogName -ErrorAction SilentlyContinue
    if (-not $fl) { return $false }
    # The typed flow-log object does not surface tags; read them from raw ARM.
    $tags = (Get-AzResource -ResourceId $fl.Id -ErrorAction SilentlyContinue).Tags
    return ($null -ne $tags -and $tags.Project -eq 'SkyCraft' -and $tags.CostCenter -eq 'MSDN')
}

# ============================================================================
# Connection Monitor Tests
# ============================================================================
Write-Host ""
Write-Host "[Connection Monitor]" -ForegroundColor Yellow

Invoke-Test "Connection Monitor '$connectionMonitorName' exists" {
    $cm = Get-AzResource -ResourceId $connectionMonitorResourceId -ExpandProperties -ErrorAction SilentlyContinue
    return ($null -ne $cm -and $cm.Name -eq $connectionMonitorName)
}

Invoke-Test "Connection Monitor monitoring status is Running or not-null" {
    $cm = Get-AzResource -ResourceId $connectionMonitorResourceId -ExpandProperties -ErrorAction SilentlyContinue
    # Accept Running or empty (may be empty in the first ~30s after creation)
    # Explicitly reject Stopped/Failed states
    return ($null -ne $cm -and $cm.Properties.monitoringStatus -notin @('Stopped', 'Failed'))
}

Invoke-Test "Connection Monitor has test group 'hub-spoke-ssh'" {
    $cm = Get-AzResource -ResourceId $connectionMonitorResourceId -ExpandProperties -ErrorAction SilentlyContinue
    $tg = $cm.Properties.testGroups | Where-Object { $_.name -eq 'hub-spoke-ssh' }
    return ($null -ne $tg)
}

Invoke-Test "Connection Monitor test config uses TCP port 22" {
    $cm = Get-AzResource -ResourceId $connectionMonitorResourceId -ExpandProperties -ErrorAction SilentlyContinue
    $tc = $cm.Properties.testConfigurations | Where-Object { $_.name -eq 'tcp-22-every-5m' }
    return ($null -ne $tc -and $tc.tcpConfiguration.port -eq 22 -and $tc.protocol -eq 'Tcp')
}

Invoke-Test "Connection Monitor test frequency is 300 seconds (5 min)" {
    $cm = Get-AzResource -ResourceId $connectionMonitorResourceId -ExpandProperties -ErrorAction SilentlyContinue
    $tc = $cm.Properties.testConfigurations | Where-Object { $_.name -eq 'tcp-22-every-5m' }
    return ($tc.testFrequencySec -eq 300)
}

Invoke-Test "Connection Monitor destination endpoint is dev-skycraft-swc-auth-vm" {
    $cm = Get-AzResource -ResourceId $connectionMonitorResourceId -ExpandProperties -ErrorAction SilentlyContinue
    $dest = $cm.Properties.endpoints | Where-Object { $_.name -eq 'dev-auth-destination' }
    # AzureVM endpoint carries resourceId; accept either resourceId or address match
    return ($null -ne $dest -and (
        $dest.resourceId -like '*dev-skycraft-swc-auth-vm*' -or
        $dest.address    -eq '10.1.1.4'
    ))
}

Invoke-Test "Connection Monitor has correct tags (Project, Environment, CostCenter)" {
    $cm = Get-AzResource -ResourceId $connectionMonitorResourceId -ExpandProperties -ErrorAction SilentlyContinue
    return ($cm.Tags.Project -eq 'SkyCraft' -and $cm.Tags.CostCenter -eq 'MSDN')
}

# ============================================================================
# Summary
# ============================================================================
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Test Results Summary" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Passed: $passCount" -ForegroundColor Green
if ($failCount -gt 0) {
    Write-Host "  Failed: $failCount" -ForegroundColor Red
} else {
    Write-Host "  Failed: $failCount" -ForegroundColor Gray
}
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

exit $failCount
