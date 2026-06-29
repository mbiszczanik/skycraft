<#
.SYNOPSIS
    Tests Lab 5.1 Azure Monitor & Insights deployment.

.DESCRIPTION
    Validates that all Lab 5.1 monitoring resources are deployed correctly:
    - Log Analytics Workspace exists with correct SKU and retention
    - VM Insights DCR exists and is associated with a SkyCraft VM
    - Action Group exists with email receiver configured
    - Metric Alert rule exists and is enabled
    - Storage Diagnostic Settings are configured
    - Tags match governance requirements

.PARAMETER Environment
    Target environment prefix when checking VM resources. Default: dev

.EXAMPLE
    .\Test-Lab.ps1
    .\Test-Lab.ps1 -Environment dev

.NOTES
    Project: SkyCraft
    Author: SkyCraft
    Date: 2026-04-06
#>

#Requires -Version 7.0
#Requires -Modules Az.Accounts, Az.Resources, Az.OperationalInsights, Az.Monitor, Az.Storage

[CmdletBinding()]
param(
    [Parameter()]
    [ValidateSet('dev', 'prod')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Environment', Justification = 'Documented public parameter retained for interface stability and future VM-scoped probes.')]
    [string]$Environment = 'dev'
)

$ErrorActionPreference = 'Stop'

# Configuration
$platformRg     = 'platform-skycraft-swc-rg'
$workspaceName  = 'platform-skycraft-swc-law'
$dcrName        = 'skycraft-vm-dcr'
$actionGroupName = 'skycraft-ops-ag'
$alertRuleName  = 'skycraft-cpu-alert'
$storageRg      = 'platform-skycraft-swc-rg'

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
Write-Host "  Lab 5.1 - Deployment Validation" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Verify login
$context = Get-AzContext
if (-not $context) {
    Write-Host "  [ERROR] Not logged into Azure. Run 'Connect-AzAccount' first." -ForegroundColor Red
    exit 1
}
$subscriptionId = $context.Subscription.Id
Write-Host "  Account: $($context.Account.Id)" -ForegroundColor Gray
Write-Host ""

# ============================================================================
# Log Analytics Workspace Tests
# ============================================================================
Write-Host "[Log Analytics Workspace]" -ForegroundColor Yellow

$wsCache = Get-AzOperationalInsightsWorkspace -ResourceGroupName $platformRg -Name $workspaceName -ErrorAction SilentlyContinue

Invoke-Test "Workspace '$workspaceName' exists" {
    return ($null -ne $wsCache -and $wsCache.Name -eq $workspaceName)
}

Invoke-Test "Workspace SKU is PerGB2018" {
    return ($wsCache.Sku -eq 'PerGB2018')
}

Invoke-Test "Workspace retention is at least 30 days" {
    return ($wsCache.RetentionInDays -ge 30)
}

Invoke-Test "Workspace location is swedencentral" {
    return ($wsCache.Location -eq 'swedencentral')
}

Invoke-Test "Workspace has correct tags (Project, Environment, CostCenter)" {
    return ($wsCache.Tags.Project -eq 'SkyCraft' -and $wsCache.Tags.Environment -eq 'Platform' -and $wsCache.Tags.CostCenter -eq 'MSDN')
}

# ============================================================================
# Data Collection Rule Tests
# ============================================================================
Write-Host ""
Write-Host "[VM Insights Data Collection Rule]" -ForegroundColor Yellow

# DCR detail is read from the raw ARM body (Get-AzResource -ExpandProperties)
# so the camelCase destinations/dataFlows structure matches the ARM schema.
$dcrId = "/subscriptions/$subscriptionId/resourceGroups/$platformRg/providers/Microsoft.Insights/dataCollectionRules/$dcrName"
$dcrResource = Get-AzResource -ResourceId $dcrId -ExpandProperties -ErrorAction SilentlyContinue

Invoke-Test "DCR '$dcrName' exists" {
    return ($null -ne $dcrResource -and $dcrResource.Name -eq $dcrName)
}

Invoke-Test "DCR destination points to workspace" {
    $destWsId = $dcrResource.Properties.destinations.logAnalytics[0].workspaceResourceId
    return ($destWsId -eq $wsCache.ResourceId)
}

Invoke-Test "DCR has InsightsMetrics data flow" {
    $streams = $dcrResource.Properties.dataFlows | ForEach-Object { $_.streams } | Select-Object -Unique
    return ($streams -contains 'Microsoft-InsightsMetrics')
}

Invoke-Test "DCR includes Syslog stream" {
    $streams = $dcrResource.Properties.dataFlows | ForEach-Object { $_.streams } | Select-Object -Unique
    return ($streams -contains 'Microsoft-Syslog')
}

Invoke-Test "DCR has at least one VM association" {
    $assocResponse = Invoke-AzRestMethod -Method GET -Path "/subscriptions/$subscriptionId/resourceGroups/$platformRg/providers/Microsoft.Insights/dataCollectionRules/$dcrName/associations?api-version=2023-03-11"
    $assocList = $assocResponse.Content | ConvertFrom-Json
    return ($assocList.value.Count -gt 0)
}

# ============================================================================
# Action Group Tests
# ============================================================================
Write-Host ""
Write-Host "[Action Group]" -ForegroundColor Yellow

Invoke-Test "Action Group '$actionGroupName' exists" {
    $ag = Get-AzActionGroup -ResourceGroupName $platformRg -Name $actionGroupName -ErrorAction SilentlyContinue
    return ($null -ne $ag -and $ag.Name -eq $actionGroupName)
}

Invoke-Test "Action Group shortName is 'SkyCraftOps'" {
    $ag = Get-AzActionGroup -ResourceGroupName $platformRg -Name $actionGroupName -ErrorAction SilentlyContinue
    return ($ag.GroupShortName -eq 'SkyCraftOps')
}

Invoke-Test "Action Group has at least one email receiver" {
    $ag = Get-AzActionGroup -ResourceGroupName $platformRg -Name $actionGroupName -ErrorAction SilentlyContinue
    # Guard against $null ag — @($null).Count is 1 (false positive without this guard)
    return ($null -ne $ag -and @($ag.EmailReceiver).Count -gt 0)
}

Invoke-Test "Action Group is enabled" {
    $ag = Get-AzActionGroup -ResourceGroupName $platformRg -Name $actionGroupName -ErrorAction SilentlyContinue
    return ($ag.Enabled -eq $true)
}

# ============================================================================
# Metric Alert Tests
# ============================================================================
Write-Host ""
Write-Host "[Metric Alert]" -ForegroundColor Yellow

Invoke-Test "Alert rule '$alertRuleName' exists" {
    $alert = Get-AzMetricAlertRuleV2 -ResourceGroupName $platformRg -Name $alertRuleName -ErrorAction SilentlyContinue
    return ($null -ne $alert -and $alert.Name -eq $alertRuleName)
}

Invoke-Test "Alert rule is enabled" {
    $alert = Get-AzMetricAlertRuleV2 -ResourceGroupName $platformRg -Name $alertRuleName -ErrorAction SilentlyContinue
    return ($alert.Enabled -eq $true)
}

Invoke-Test "Alert rule severity is 2 (Warning)" {
    $alert = Get-AzMetricAlertRuleV2 -ResourceGroupName $platformRg -Name $alertRuleName -ErrorAction SilentlyContinue
    return ($alert.Severity -eq 2)
}

Invoke-Test "Alert rule window size is 5 minutes" {
    $alert = Get-AzMetricAlertRuleV2 -ResourceGroupName $platformRg -Name $alertRuleName -ErrorAction SilentlyContinue
    return ($null -ne $alert -and $alert.WindowSize -eq [System.TimeSpan]::FromMinutes(5))
}

Invoke-Test "Alert rule evaluation frequency is 1 minute" {
    $alert = Get-AzMetricAlertRuleV2 -ResourceGroupName $platformRg -Name $alertRuleName -ErrorAction SilentlyContinue
    return ($null -ne $alert -and $alert.EvaluationFrequency -eq [System.TimeSpan]::FromMinutes(1))
}

Invoke-Test "Alert rule threshold is > 80% CPU" {
    $alert = Get-AzMetricAlertRuleV2 -ResourceGroupName $platformRg -Name $alertRuleName -ErrorAction SilentlyContinue
    if (-not $alert) { return $false }
    # Read criteria from raw ARM (camelCase) — the typed PSMetricCriteria object
    # does not reliably expose metricName/operator across Az.Monitor versions.
    $crit = (Get-AzResource -ResourceId $alert.Id -ExpandProperties -ErrorAction SilentlyContinue).Properties.criteria.allOf[0]
    return ($crit.metricName -eq 'Percentage CPU' -and [int]$crit.threshold -eq 80 -and $crit.operator -eq 'GreaterThan')
}

# ============================================================================
# Storage Diagnostic Settings Tests
# ============================================================================
Write-Host ""
Write-Host "[Storage Diagnostic Settings]" -ForegroundColor Yellow

Invoke-Test "Diagnostic setting 'skycraft-storage-diag' exists on blob service" {
    $storageAcct = Get-AzStorageAccount -ResourceGroupName $storageRg -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $storageAcct) { return $false }
    # Diagnostic settings are extension resources — Get-AzDiagnosticSetting reads them
    # reliably (Get-AzResource on the sub-resource id returns null).
    $diag = Get-AzDiagnosticSetting -ResourceId "$($storageAcct.Id)/blobServices/default" -Name 'skycraft-storage-diag' -ErrorAction SilentlyContinue
    return ($null -ne $diag)
}

Invoke-Test "Diagnostic setting sends StorageRead and StorageWrite to workspace" {
    $storageAcct = Get-AzStorageAccount -ResourceGroupName $storageRg -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $storageAcct) { return $false }
    $diag = Get-AzDiagnosticSetting -ResourceId "$($storageAcct.Id)/blobServices/default" -Name 'skycraft-storage-diag' -ErrorAction SilentlyContinue
    $readLog  = $diag.Log | Where-Object { $_.Category -eq 'StorageRead'  -and $_.Enabled }
    $writeLog = $diag.Log | Where-Object { $_.Category -eq 'StorageWrite' -and $_.Enabled }
    return ($null -ne $readLog -and $null -ne $writeLog)
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
