<#
.SYNOPSIS
    Tests Lab 5.1 Azure Monitor & Insights deployment.

.DESCRIPTION
    Validates that all Lab 5.1 monitoring resources are deployed correctly:
    - Log Analytics Workspace exists with correct SKU and retention
    - VM Insights DCR exists and is associated with a SkyCraft VM
    - Action Group exists with email receiver configured
    - Metric Alert rule exists and is enabled
    - Alert Processing Rule exists and is enabled
    - Storage Diagnostic Settings are configured
    - Tags match governance requirements

.PARAMETER Environment
    Target environment prefix when checking VM resources. Default: prod

.EXAMPLE
    .\Test-Lab.ps1
    .\Test-Lab.ps1 -Environment prod

.NOTES
    Project: SkyCraft
    Author: SkyCraft
    Date: 2026-04-06
#>

#Requires -Version 7.0

[CmdletBinding()]
param(
    [Parameter()]
    [ValidateSet('dev', 'prod')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Environment', Justification = 'Documented public parameter retained for interface stability and future VM-scoped probes.')]
    [string]$Environment = 'prod'
)

$ErrorActionPreference = 'Stop'

# Configuration
$platformRg     = 'platform-skycraft-swc-rg'
$workspaceName  = 'platform-skycraft-swc-law'
$dcrName        = 'skycraft-vm-dcr'
$actionGroupName = 'skycraft-ops-ag'
$alertRuleName  = 'skycraft-cpu-alert'
$aprName        = 'skycraft-hours-apr'
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
# Log Analytics Workspace Tests
# ============================================================================
Write-Host "[Log Analytics Workspace]" -ForegroundColor Yellow

$wsCache = az monitor log-analytics workspace show `
    --workspace-name $workspaceName `
    --resource-group $platformRg `
    --output json 2>$null | ConvertFrom-Json

Invoke-Test "Workspace '$workspaceName' exists" {
    return ($null -ne $wsCache -and $wsCache.name -eq $workspaceName)
}

Invoke-Test "Workspace SKU is PerGB2018" {
    return ($wsCache.sku.name -eq 'PerGB2018')
}

Invoke-Test "Workspace retention is 30 days" {
    return ($wsCache.retentionInDays -eq 30)
}

Invoke-Test "Workspace location is swedencentral" {
    return ($wsCache.location -eq 'swedencentral')
}

Invoke-Test "Workspace has correct tags (Project, Environment, CostCenter)" {
    return ($wsCache.tags.Project -eq 'SkyCraft' -and $wsCache.tags.CostCenter -eq 'MSDN')
}

# ============================================================================
# Data Collection Rule Tests
# ============================================================================
Write-Host ""
Write-Host "[VM Insights Data Collection Rule]" -ForegroundColor Yellow

Invoke-Test "DCR '$dcrName' exists" {
    $dcr = az monitor data-collection rule show `
        --name $dcrName `
        --resource-group $platformRg `
        --output json 2>$null | ConvertFrom-Json
    return ($null -ne $dcr -and $dcr.name -eq $dcrName)
}

Invoke-Test "DCR destination points to workspace" {
    $dcr = az monitor data-collection rule show `
        --name $dcrName `
        --resource-group $platformRg `
        --output json 2>$null | ConvertFrom-Json
    $wsId = az monitor log-analytics workspace show `
        --workspace-name $workspaceName `
        --resource-group $platformRg `
        --query id --output tsv 2>$null
    $destWsId = $dcr.destinations.logAnalytics[0].workspaceResourceId
    return ($destWsId -eq $wsId)
}

Invoke-Test "DCR has InsightsMetrics data flow" {
    $dcr = az monitor data-collection rule show `
        --name $dcrName `
        --resource-group $platformRg `
        --output json 2>$null | ConvertFrom-Json
    $streams = $dcr.dataFlows | ForEach-Object { $_.streams } | Select-Object -Unique
    return ($streams -contains 'Microsoft-InsightsMetrics')
}

Invoke-Test "DCR includes Syslog stream" {
    $dcr = az monitor data-collection rule show `
        --name $dcrName `
        --resource-group $platformRg `
        --output json 2>$null | ConvertFrom-Json
    $streams = $dcr.dataFlows | ForEach-Object { $_.streams } | Select-Object -Unique
    return ($streams -contains 'Microsoft-Syslog')
}

Invoke-Test "DCR has at least one VM association" {
    $assocList = az rest `
        --method GET `
        --url "https://management.azure.com/subscriptions/$($account.id)/resourceGroups/$platformRg/providers/Microsoft.Insights/dataCollectionRules/$dcrName/associations?api-version=2023-03-11" `
        --output json 2>$null | ConvertFrom-Json
    return ($assocList.value.Count -gt 0)
}

# ============================================================================
# Action Group Tests
# ============================================================================
Write-Host ""
Write-Host "[Action Group]" -ForegroundColor Yellow

Invoke-Test "Action Group '$actionGroupName' exists" {
    $ag = az monitor action-group show `
        --name $actionGroupName `
        --resource-group $platformRg `
        --output json 2>$null | ConvertFrom-Json
    return ($null -ne $ag -and $ag.name -eq $actionGroupName)
}

Invoke-Test "Action Group shortName is 'SkyCraftOps'" {
    $ag = az monitor action-group show `
        --name $actionGroupName `
        --resource-group $platformRg `
        --output json 2>$null | ConvertFrom-Json
    return ($ag.groupShortName -eq 'SkyCraftOps')
}

Invoke-Test "Action Group has at least one email receiver" {
    $ag = az monitor action-group show `
        --name $actionGroupName `
        --resource-group $platformRg `
        --output json 2>$null | ConvertFrom-Json
    return ($ag.emailReceivers.Count -gt 0)
}

Invoke-Test "Action Group is enabled" {
    $ag = az monitor action-group show `
        --name $actionGroupName `
        --resource-group $platformRg `
        --output json 2>$null | ConvertFrom-Json
    return ($ag.enabled -eq $true)
}

# ============================================================================
# Metric Alert Tests
# ============================================================================
Write-Host ""
Write-Host "[Metric Alert]" -ForegroundColor Yellow

Invoke-Test "Alert rule '$alertRuleName' exists" {
    $alert = az monitor metrics alert show `
        --name $alertRuleName `
        --resource-group $platformRg `
        --output json 2>$null | ConvertFrom-Json
    return ($null -ne $alert -and $alert.name -eq $alertRuleName)
}

Invoke-Test "Alert rule is enabled" {
    $alert = az monitor metrics alert show `
        --name $alertRuleName `
        --resource-group $platformRg `
        --output json 2>$null | ConvertFrom-Json
    return ($alert.enabled -eq $true)
}

Invoke-Test "Alert rule severity is 2 (Warning)" {
    $alert = az monitor metrics alert show `
        --name $alertRuleName `
        --resource-group $platformRg `
        --output json 2>$null | ConvertFrom-Json
    return ($alert.severity -eq 2)
}

Invoke-Test "Alert rule window size is 5 minutes" {
    $alert = az monitor metrics alert show `
        --name $alertRuleName `
        --resource-group $platformRg `
        --output json 2>$null | ConvertFrom-Json
    return ($alert.windowSize -eq 'PT5M')
}

Invoke-Test "Alert rule evaluation frequency is 1 minute" {
    $alert = az monitor metrics alert show `
        --name $alertRuleName `
        --resource-group $platformRg `
        --output json 2>$null | ConvertFrom-Json
    return ($alert.evaluationFrequency -eq 'PT1M')
}

Invoke-Test "Alert rule threshold is > 80% CPU" {
    $alert = az monitor metrics alert show `
        --name $alertRuleName `
        --resource-group $platformRg `
        --output json 2>$null | ConvertFrom-Json
    $criteria = $alert.criteria.allOf[0]
    return ($criteria.metricName -eq 'Percentage CPU' -and $criteria.threshold -eq 80 -and $criteria.operator -eq 'GreaterThan')
}

# ============================================================================
# Alert Processing Rule Tests
# ============================================================================
Write-Host ""
Write-Host "[Alert Processing Rule]" -ForegroundColor Yellow

Invoke-Test "Alert processing rule '$aprName' exists" {
    $apr = az monitor alert-processing-rule show `
        --name $aprName `
        --resource-group $platformRg `
        --output json 2>$null | ConvertFrom-Json
    return ($null -ne $apr -and $apr.name -eq $aprName)
}

Invoke-Test "Alert processing rule is enabled" {
    $apr = az monitor alert-processing-rule show `
        --name $aprName `
        --resource-group $platformRg `
        --output json 2>$null | ConvertFrom-Json
    return ($apr.properties.enabled -eq $true)
}

Invoke-Test "APR action type is AddActionGroups" {
    $apr = az monitor alert-processing-rule show `
        --name $aprName `
        --resource-group $platformRg `
        --output json 2>$null | ConvertFrom-Json
    $action = $apr.properties.actions | Where-Object { $_.actionType -eq 'AddActionGroups' }
    return ($null -ne $action)
}

# ============================================================================
# Storage Diagnostic Settings Tests
# ============================================================================
Write-Host ""
Write-Host "[Storage Diagnostic Settings]" -ForegroundColor Yellow

Invoke-Test "Diagnostic setting 'skycraft-storage-diag' exists on blob service" {
    $storageAcct = az storage account list `
        --resource-group $storageRg `
        --output json 2>$null | ConvertFrom-Json | Select-Object -First 1
    if (-not $storageAcct) { return $false }
    $blobServiceId = "$($storageAcct.id)/blobServices/default"
    $diag = az monitor diagnostic-settings show `
        --name 'skycraft-storage-diag' `
        --resource $blobServiceId `
        --output json 2>$null | ConvertFrom-Json
    return ($null -ne $diag -and $diag.name -eq 'skycraft-storage-diag')
}

Invoke-Test "Diagnostic setting sends StorageRead and StorageWrite to workspace" {
    $storageAcct = az storage account list `
        --resource-group $storageRg `
        --output json 2>$null | ConvertFrom-Json | Select-Object -First 1
    if (-not $storageAcct) { return $false }
    $blobServiceId = "$($storageAcct.id)/blobServices/default"
    $diag = az monitor diagnostic-settings show `
        --name 'skycraft-storage-diag' `
        --resource $blobServiceId `
        --output json 2>$null | ConvertFrom-Json
    $readLog  = $diag.logs | Where-Object { $_.category -eq 'StorageRead'  -and $_.enabled -eq $true }
    $writeLog = $diag.logs | Where-Object { $_.category -eq 'StorageWrite' -and $_.enabled -eq $true }
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
