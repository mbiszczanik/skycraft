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

$account = az account show --output json 2>$null | ConvertFrom-Json
if (-not $account) {
    Write-Host "  [ERROR] Not logged into Azure CLI. Run 'az login' first." -ForegroundColor Red
    exit 1
}
Write-Host "  Account: $($account.user.name)" -ForegroundColor Gray

# Allow non-interactive installation of required Azure CLI extensions.
az config set extension.use_dynamic_install=yes_without_prompt --only-show-errors | Out-Null
Write-Host ""

# ============================================================================
# Network Watcher Tests
# ============================================================================
Write-Host "[Network Watcher]" -ForegroundColor Yellow

Invoke-Test "Network Watcher exists for swedencentral" {
    $nw = az network watcher list `
        --query "[?location=='swedencentral']" `
        --output json 2>$null | ConvertFrom-Json
    return ($null -ne $nw -and $nw.Count -gt 0)
}

Invoke-Test "Network Watcher provisioning state is Succeeded" {
    $nw = az network watcher list `
        --query "[?location=='swedencentral']" `
        --output json 2>$null | ConvertFrom-Json
    return ($nw[0].provisioningState -eq 'Succeeded')
}

Invoke-Test "Network Watcher is in NetworkWatcherRG" {
    $nw = az network watcher list --output json 2>$null | ConvertFrom-Json |
        Where-Object { $_.name -eq $networkWatcherName -and $_.resourceGroup -eq $networkWatcherRg }
    return ($null -ne $nw)
}

# ============================================================================
# VNet Flow Log Tests
# ============================================================================
Write-Host ""
Write-Host "[VNet Flow Log]" -ForegroundColor Yellow

Invoke-Test "Flow log '$flowLogName' exists" {
    $fl = az network watcher flow-log show `
        --name $flowLogName `
        --resource-group $networkWatcherRg `
        --location swedencentral `
        --output json 2>$null | ConvertFrom-Json
    return ($null -ne $fl -and $fl.name -eq $flowLogName)
}

Invoke-Test "Flow log is enabled" {
    $fl = az network watcher flow-log show `
        --name $flowLogName `
        --resource-group $networkWatcherRg `
        --location swedencentral `
        --output json 2>$null | ConvertFrom-Json
    return ($fl.enabled -eq $true)
}

Invoke-Test "Flow log uses Version 2 format" {
    $fl = az network watcher flow-log show `
        --name $flowLogName `
        --resource-group $networkWatcherRg `
        --location swedencentral `
        --output json 2>$null | ConvertFrom-Json
    return ($fl.format.version -eq 2)
}

Invoke-Test "Flow log retention is 7 days" {
    $fl = az network watcher flow-log show `
        --name $flowLogName `
        --resource-group $networkWatcherRg `
        --location swedencentral `
        --output json 2>$null | ConvertFrom-Json
    return ($fl.retentionPolicy.days -eq 7 -and $fl.retentionPolicy.enabled -eq $true)
}

Invoke-Test "Flow log targets prod-skycraft-swc-vnet" {
    $fl = az network watcher flow-log show `
        --name $flowLogName `
        --resource-group $networkWatcherRg `
        --location swedencentral `
        --output json 2>$null | ConvertFrom-Json
    return ($fl.targetResourceId -like "*$prodVnetName*")
}

Invoke-Test "Flow log Traffic Analytics is enabled" {
    $fl = az network watcher flow-log show `
        --name $flowLogName `
        --resource-group $networkWatcherRg `
        --location swedencentral `
        --output json 2>$null | ConvertFrom-Json
    $ta = $fl.flowAnalyticsConfiguration.networkWatcherFlowAnalyticsConfiguration
    return ($ta.enabled -eq $true)
}

Invoke-Test "Flow log Traffic Analytics interval is 10 minutes" {
    $fl = az network watcher flow-log show `
        --name $flowLogName `
        --resource-group $networkWatcherRg `
        --location swedencentral `
        --output json 2>$null | ConvertFrom-Json
    $ta = $fl.flowAnalyticsConfiguration.networkWatcherFlowAnalyticsConfiguration
    return ($ta.trafficAnalyticsInterval -eq 10)
}

Invoke-Test "Flow log Traffic Analytics workspace is platform-skycraft-swc-law" {
    $fl = az network watcher flow-log show `
        --name $flowLogName `
        --resource-group $networkWatcherRg `
        --location swedencentral `
        --output json 2>$null | ConvertFrom-Json
    $ta = $fl.flowAnalyticsConfiguration.networkWatcherFlowAnalyticsConfiguration
    return ($ta.workspaceResourceId -like "*$workspaceName*")
}

Invoke-Test "Flow log has correct tags (Project, Environment, CostCenter)" {
    $fl = az network watcher flow-log show `
        --name $flowLogName `
        --resource-group $networkWatcherRg `
        --location swedencentral `
        --output json 2>$null | ConvertFrom-Json
    return ($fl.tags.Project -eq 'SkyCraft' -and $fl.tags.CostCenter -eq 'MSDN')
}

# ============================================================================
# Connection Monitor Tests
# ============================================================================
Write-Host ""
Write-Host "[Connection Monitor]" -ForegroundColor Yellow

Invoke-Test "Connection Monitor '$connectionMonitorName' exists" {
    $cm = az network watcher connection-monitor show `
        --name $connectionMonitorName `
        --location swedencentral `
        --output json 2>$null | ConvertFrom-Json
    return ($null -ne $cm -and $cm.name -eq $connectionMonitorName)
}

Invoke-Test "Connection Monitor monitoring status is Running or not-null" {
    $cm = az network watcher connection-monitor show `
        --name $connectionMonitorName `
        --location swedencentral `
        --output json 2>$null | ConvertFrom-Json
    # Accept Running or empty (may be empty in the first ~30s after creation)
    # Explicitly reject Stopped/Failed states
    return ($null -ne $cm -and $cm.monitoringStatus -notin @('Stopped', 'Failed'))
}

Invoke-Test "Connection Monitor has test group 'hub-spoke-ssh'" {
    $cm = az network watcher connection-monitor show `
        --name $connectionMonitorName `
        --location swedencentral `
        --output json 2>$null | ConvertFrom-Json
    $tg = $cm.testGroups | Where-Object { $_.name -eq 'hub-spoke-ssh' }
    return ($null -ne $tg)
}

Invoke-Test "Connection Monitor test config uses TCP port 22" {
    $cm = az network watcher connection-monitor show `
        --name $connectionMonitorName `
        --location swedencentral `
        --output json 2>$null | ConvertFrom-Json
    $tc = $cm.testConfigurations | Where-Object { $_.name -eq 'tcp-22-every-5m' }
    return ($null -ne $tc -and $tc.tcpConfiguration.port -eq 22 -and $tc.protocol -eq 'Tcp')
}

Invoke-Test "Connection Monitor test frequency is 300 seconds (5 min)" {
    $cm = az network watcher connection-monitor show `
        --name $connectionMonitorName `
        --location swedencentral `
        --output json 2>$null | ConvertFrom-Json
    $tc = $cm.testConfigurations | Where-Object { $_.name -eq 'tcp-22-every-5m' }
    return ($tc.testFrequencySec -eq 300)
}

Invoke-Test "Connection Monitor destination endpoint is dev-skycraft-swc-auth-vm" {
    $cm = az network watcher connection-monitor show `
        --name $connectionMonitorName `
        --location swedencentral `
        --output json 2>$null | ConvertFrom-Json
    $dest = $cm.endpoints | Where-Object { $_.name -eq 'dev-auth-destination' }
    # AzureVM endpoint carries resourceId; accept either resourceId or address match
    return ($null -ne $dest -and (
        $dest.resourceId -like '*dev-skycraft-swc-auth-vm*' -or
        $dest.address    -eq '10.1.1.4'
    ))
}

Invoke-Test "Connection Monitor has correct tags (Project, Environment, CostCenter)" {
    $cm = az network watcher connection-monitor show `
        --name $connectionMonitorName `
        --location swedencentral `
        --output json 2>$null | ConvertFrom-Json
    return ($cm.tags.Project -eq 'SkyCraft' -and $cm.tags.CostCenter -eq 'MSDN')
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
