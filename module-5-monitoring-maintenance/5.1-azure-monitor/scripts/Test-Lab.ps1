<#
.SYNOPSIS
    Tests Lab 5.1 Azure Monitor & Insights deployment.

.DESCRIPTION
    Validates that all Lab 5.1 monitoring resources are deployed correctly:
    - Log Analytics Workspace exists with correct SKU and retention
    - VM Insights DCR is associated with a SkyCraft VM and sends to the workspace
    - Action Group exists with email receiver configured
    - Metric Alert rule exists and is enabled
    - Storage Diagnostic Settings are configured
    - Tags match governance requirements

    The data collection rule is found through the VM it applies to, not by name and group
    (issue #355): VM insights names its rule 'MSVMI-<...>' in the VM's group, the data collection
    rule wizard takes any group, and the Bicep creates 'skycraft-vm-dcr' in the platform group.
    The rules associated with the VMs of the dev and prod groups are read, and the one that sends
    to the lab's workspace is checked ('skycraft-vm-dcr' first if several do). Names stay literal
    where the guide has the learner type both name and group: the action group, the alert rule
    and the diagnostic setting. When the alert rule is not where the guide puts it, the failure
    names the rules found on a SkyCraft VM through their scope, since the Portal defaults the
    rule's group to the VM's.

.PARAMETER Environment
    Target environment prefix when checking VM resources: its group's VMs are searched first for
    the data collection rule, then the other environment's. Default: dev

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
    $Host.SetShouldExit(1)
    exit 1
}
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

# Found through the VM it applies to, not by name and group (#355): a VM's data collection rule
# associations name the rules that apply to it, wherever they live and whatever they are called.
# DCR detail is read from the raw ARM body (Get-AzResource -ExpandProperties) so the camelCase
# destinations/dataFlows structure matches the ARM schema.
$vmGroups = @("$Environment-skycraft-swc-rg") + @(@('dev', 'prod') | Where-Object { $_ -ne $Environment } | ForEach-Object { "$_-skycraft-swc-rg" })
$dcrResource    = $null
$dcrVmNames     = @()
$dcrLookupError = $null
try {
    $ruleVms     = [ordered]@{}   # rule id (lower case) -> names of the VMs it is associated with
    $groupErrors = @()
    foreach ($group in $vmGroups) {
        try {
            $vms = @(Get-AzResource -ResourceGroupName $group -ResourceType 'Microsoft.Compute/virtualMachines' -ErrorAction Stop | Where-Object { $_ })
        }
        catch {
            $groupErrors += "VMs in '$group': $($_.Exception.Message)"
            continue
        }
        foreach ($vm in $vms) {
            $response = Invoke-AzRestMethod -Method GET -Path "$($vm.ResourceId)/providers/Microsoft.Insights/dataCollectionRuleAssociations?api-version=2023-03-11" -ErrorAction Stop
            if ($response.StatusCode -ne 200) {
                $groupErrors += "associations of '$($vm.Name)': HTTP $($response.StatusCode)"
                continue
            }
            foreach ($association in @(($response.Content | ConvertFrom-Json).value)) {
                # An association with a data collection endpoint names no rule.
                $ruleId = "$($association.properties.dataCollectionRuleId)"
                if (-not $ruleId) { continue }
                $key = $ruleId.ToLowerInvariant()
                if (-not $ruleVms.Contains($key)) { $ruleVms[$key] = [pscustomobject]@{ Id = $ruleId; Vms = @() } }
                $ruleVms[$key].Vms += $vm.Name
            }
        }
    }

    $rules = foreach ($entry in $ruleVms.Values) {
        $rule = Get-AzResource -ResourceId $entry.Id -ExpandProperties -ErrorAction Stop
        $sendsHere = $null -ne $wsCache -and (@($rule.Properties.destinations.logAnalytics | ForEach-Object { "$($_.workspaceResourceId)" }) -contains $wsCache.ResourceId)
        [pscustomobject]@{ Resource = $rule; Vms = $entry.Vms; SendsHere = $sendsHere; Preferred = ($rule.Name -eq $dcrName) }
    }
    # The rule that sends to the lab's workspace is the lab's; the Bicep's name breaks a tie.
    $chosen = @($rules) | Where-Object { $_ } |
        Sort-Object -Property @{ Expression = 'SendsHere'; Descending = $true }, @{ Expression = 'Preferred'; Descending = $true } |
        Select-Object -First 1
    if ($chosen) {
        $dcrResource = $chosen.Resource
        $dcrVmNames  = $chosen.Vms
    }
    elseif ($groupErrors.Count -gt 0) {
        throw "could not read $($groupErrors -join '; ')"
    }
}
catch {
    $dcrLookupError = $_.Exception.Message
}

Invoke-Test "Data collection rule associated with a VM in $($vmGroups -join ' or ')" {
    if ($dcrLookupError) { throw $dcrLookupError }
    if (-not $dcrResource) {
        Write-Host " (no rule is associated with these VMs - Step 5.1.2)" -NoNewline -ForegroundColor Gray
        return $false
    }
    Write-Host " ('$($dcrResource.Name)' in $($dcrResource.ResourceGroupName), on $($dcrVmNames -join ', '))" -NoNewline -ForegroundColor Gray
    return $true
}

Invoke-Test "DCR destination points to workspace" {
    if (-not $dcrResource -or -not $wsCache) { return $false }
    $destWsIds = @($dcrResource.Properties.destinations.logAnalytics | ForEach-Object { "$($_.workspaceResourceId)" })
    return ($destWsIds -contains $wsCache.ResourceId)
}

Invoke-Test "DCR has InsightsMetrics data flow" {
    $streams = $dcrResource.Properties.dataFlows | ForEach-Object { $_.streams } | Select-Object -Unique
    return ($streams -contains 'Microsoft-InsightsMetrics')
}

Invoke-Test "DCR includes Syslog stream" {
    $streams = $dcrResource.Properties.dataFlows | ForEach-Object { $_.streams } | Select-Object -Unique
    return ($streams -contains 'Microsoft-Syslog')
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
    if ($null -ne $alert -and $alert.Name -eq $alertRuleName) { return $true }
    # The guide has the learner type both name and group, so the check stays literal. But the
    # Portal defaults the rule's group to the watched VM's group, so say where a rule on a
    # SkyCraft VM ended up, found through its scope (#355). The hint never replaces the FAIL.
    $vmScope = '/providers/Microsoft\.Compute/virtualMachines/(dev|prod)-skycraft-swc-'
    $elsewhere = @()
    try {
        $elsewhere = @(Get-AzMetricAlertRuleV2 -ErrorAction Stop | Where-Object {
                $_ -and ($_.Name -eq $alertRuleName -or @($_.Scopes | Where-Object { "$_" -match $vmScope }).Count -gt 0)
            })
    }
    catch {
        Write-Host " (no rule named '$alertRuleName' in $platformRg; the subscription's alert rules could not be listed: $($_.Exception.Message))" -NoNewline -ForegroundColor Gray
    }
    if ($elsewhere.Count -gt 0) {
        $found = ($elsewhere | ForEach-Object { "'$($_.Name)' in $($_.ResourceGroup)" }) -join ', '
        Write-Host " (not in ${platformRg}; found $found on a SkyCraft VM - Step 5.1.5 names the rule '$alertRuleName' and sets Details > Resource group to $platformRg)" -NoNewline -ForegroundColor Gray
    }
    return $false
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

$Host.SetShouldExit($failCount)
exit $failCount
