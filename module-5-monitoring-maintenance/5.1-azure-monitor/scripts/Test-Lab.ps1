<#
.SYNOPSIS
    Tests Lab 5.1 Azure Monitor & Insights deployment.

.DESCRIPTION
    Validates that all Lab 5.1 monitoring resources are deployed correctly:
    - Log Analytics Workspace exists with correct SKU and retention
    - VM DCR is associated with a SkyCraft VM, sends to the workspace and collects Perf and Syslog
    - Azure Monitor Agent is Succeeded on those VMs and their Heartbeat reaches the workspace
    - Action Group exists with email receiver configured
    - Metric Alert rule exists and is enabled
    - Storage Diagnostic Settings are configured
    - Tags match governance requirements

    The data collection rule is found through the VM it applies to, not by name and group
    (issue #355): VM insights names its rule 'MSVMI-<...>' in the VM's group, the data collection
    rule wizard takes any group, and the Bicep creates 'skycraft-vm-dcr' in the platform group.
    The rules associated with the VMs of the dev and prod groups are read, and the one that sends
    to the lab's workspace is checked ('skycraft-vm-dcr' first if several do); a group, VM or
    rule that cannot be read is skipped and named, never allowed to hide a rule found elsewhere.
    The alert rule is found through its scope (issues #355, #365): the rule named
    'skycraft-cpu-alert' that watches a SkyCraft VM, in whatever group it sits, since the Portal
    defaults the rule's group to the VM's. Its name stays literal because the guide has the
    learner type it and VM insights' recommended alerts put other rules on the same VM. Names
    stay literal where the guide has the learner type both name and group: the action group and
    the diagnostic setting.

    The Azure Monitor Agent is checked on every VM the lab's rule is associated with (issue #369):
    its extension must be present and Succeeded, and the workspace must hold a Heartbeat row from
    each of those VMs from the last 15 minutes. A failed extension read or workspace query is a
    failure, never a pass. While every agent is Succeeded and a VM's Heartbeat is still missing,
    the wait for its first row is keyed to when that VM's agent extension was installed: the time
    of its last successful 'Create or Update Virtual Machine Extension' event in the activity log
    (the extension's own instance view carries no time), and the query is repeated once a minute,
    with a progress line, until -AgentInstallWaitMinutes after that time. The first row has
    reached the workspace 27-39 minutes after the install, also on a recovered workspace whose
    table already exists. An agent installed longer ago than that with still no row fails at
    once, naming the cause: the agent is installed but not sending. Without a readable install
    time (no event, or the log cannot be read) the short -HeartbeatWaitMinutes applies, and the
    message says the time was unknown.
    A new workspace has no Heartbeat table until the first row arrives, up to about 40 minutes
    after the workspace is created; until then the query fails with BadRequest (failed to resolve
    the table). While every agent is Succeeded, that is read as 'workspace not ready' and the
    query is repeated once a minute for up to -NewWorkspaceWaitMinutes, with a progress line per
    minute; if the table never appears the check fails and the message names that cause.

.PARAMETER Environment
    Target environment prefix when checking VM resources: its group's VMs are searched first for
    the data collection rule, then the other environment's. Default: dev

.PARAMETER HeartbeatWaitMinutes
    How long to keep waiting for a first Heartbeat row when the agent's install time cannot be
    read (see -AgentInstallWaitMinutes). 0 queries once. Counted from the moment the Heartbeat
    table exists. Default: 10

.PARAMETER AgentInstallWaitMinutes
    How long after an agent extension was installed to keep waiting for the first Heartbeat row
    of its VM; a rebuilt VM sends it 27-39 minutes after the install. Counted from the install
    time in the activity log, so a run started late waits only for the rest, and an agent older
    than this fails at once when its VM has no row. The wait applies only while every agent is
    Succeeded. 0 queries once. Default: 45

.PARAMETER NewWorkspaceWaitMinutes
    How long to keep waiting for the Heartbeat table itself to exist, which a new workspace
    creates only with its first row (about 40 minutes after the workspace is created). The wait
    applies only while every agent is Succeeded. 0 fails at once when the table is missing.
    Default: 45

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
    [string]$Environment = 'dev',

    [Parameter()]
    [ValidateRange(0, 60)]
    [int]$HeartbeatWaitMinutes = 10,

    [Parameter()]
    [ValidateRange(0, 120)]
    [int]$NewWorkspaceWaitMinutes = 45,

    [Parameter()]
    [ValidateRange(0, 120)]
    [int]$AgentInstallWaitMinutes = 45
)

$ErrorActionPreference = 'Stop'
# Exit-Lab ends the script with exit code 0 or 1 and leaves an interactive session open (#257).
Import-Module (Join-Path $PSScriptRoot '../../../tools/LabCommon.psm1') -Force -Verbose:$false

# Configuration
$platformRg     = 'platform-skycraft-swc-rg'
$workspaceName  = 'platform-skycraft-swc-law'
$dcrName        = 'skycraft-vm-dcr'
$actionGroupName = 'skycraft-ops-ag'
$alertRuleName  = 'skycraft-cpu-alert'
$storageRg      = 'platform-skycraft-swc-rg'
# Explicit api-versions for the raw ARM reads (#452); Sweden Central serves both.
$dcrApiVersion         = '2023-03-11'
$metricAlertApiVersion = '2018-03-01'

$passCount = 0
$failCount = 0

# Whether a lookup's error says the object does not exist rather than that the lookup failed.
# Same rule as Test-LabNotFoundError in this lab's Remove-LabResource.ps1.
function Test-LabNotFoundError {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [System.Management.Automation.ErrorRecord]$ErrorRecord
    )

    $evidence = [System.Collections.Generic.List[string]]::new()
    $evidence.Add([string]$ErrorRecord)
    $evidence.Add([string]$ErrorRecord.FullyQualifiedErrorId)
    $status404 = $false
    for ($exception = $ErrorRecord.Exception; $exception; $exception = $exception.InnerException) {
        $evidence.Add([string]$exception.Message)
        foreach ($code in @($exception.Body.Code, $exception.Body.Error.Code, $exception.ErrorCode)) {
            if ($code) { $evidence.Add([string]$code) }
        }
        foreach ($status in @($exception.Response.StatusCode, $exception.ResponseStatusCode, $exception.Status)) {
            if ("$status" -in @('404', 'NotFound')) { $status404 = $true }
        }
    }
    $text = $evidence -join "`n"

    if ($text -match 'SubscriptionNotFound|subscription .{0,80}(could not be|was not) found') { return $false }
    if ($status404) { return $true }
    return $text -match '\bResource(Group)?NotFound\b|was not found|Resource group .{0,100}could not be found|invalid status code ''NotFound''|\b404 \(Not Found\)'
}

# Reads one resource by id at an explicit api-version (#452: without one ARM uses the newest version
# the provider lists, which a region may not serve yet). A missing resource is $null; any other
# error throws, so the check that asked fails with the error instead of reading the resource as missing.
function Get-LabArmResource {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ResourceId,

        [Parameter(Mandatory = $true)]
        [string]$ApiVersion,

        [switch]$ExpandProperties
    )

    try {
        if ($ExpandProperties) {
            return Get-AzResource -ResourceId $ResourceId -ApiVersion $ApiVersion -ExpandProperties -ErrorAction Stop
        }
        return Get-AzResource -ResourceId $ResourceId -ApiVersion $ApiVersion -ErrorAction Stop
    }
    catch {
        if (Test-LabNotFoundError -ErrorRecord $_) { return $null }
        throw
    }
}

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
    Exit-Lab -FailureCount 1
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
$dcrVmIds       = @()
$dcrLookupError = $null
$dcrUnread      = @()   # what could not be read, when what was read shows no rule
try {
    $ruleVms    = [ordered]@{}   # rule id (lower case) -> names of the VMs it is associated with
    $readErrors = @()
    $vmsRead    = 0
    # Each group, VM and rule is read on its own: one that cannot be read (a missing group, a
    # failed call, an association left pointing at a deleted rule or at a rule in another
    # subscription) is noted and skipped, so it never hides the lab's rule found elsewhere.
    foreach ($group in $vmGroups) {
        try {
            $vms = @(Get-AzResource -ResourceGroupName $group -ResourceType 'Microsoft.Compute/virtualMachines' -ErrorAction Stop | Where-Object { $_ })
        }
        catch {
            $readErrors += "VMs in '$group': $($_.Exception.Message)"
            continue
        }
        foreach ($vm in $vms) {
            try {
                $response = Invoke-AzRestMethod -Method GET -Path "$($vm.ResourceId)/providers/Microsoft.Insights/dataCollectionRuleAssociations?api-version=2023-03-11" -ErrorAction Stop
            }
            catch {
                $readErrors += "associations of '$($vm.Name)': $($_.Exception.Message)"
                continue
            }
            if ($response.StatusCode -ne 200) {
                $readErrors += "associations of '$($vm.Name)': HTTP $($response.StatusCode)"
                continue
            }
            $vmsRead++
            foreach ($association in @(($response.Content | ConvertFrom-Json).value)) {
                # An association with a data collection endpoint names no rule.
                $ruleId = "$($association.properties.dataCollectionRuleId)"
                if (-not $ruleId) { continue }
                $key = $ruleId.ToLowerInvariant()
                if (-not $ruleVms.Contains($key)) { $ruleVms[$key] = [pscustomobject]@{ Id = $ruleId; Vms = @(); VmIds = @() } }
                $ruleVms[$key].Vms += $vm.Name
                $ruleVms[$key].VmIds += $vm.ResourceId
            }
        }
    }

    $rules = foreach ($entry in $ruleVms.Values) {
        try {
            $rule = Get-AzResource -ResourceId $entry.Id -ApiVersion $dcrApiVersion -ExpandProperties -ErrorAction Stop
        }
        catch {
            $readErrors += "rule '$($entry.Id)': $($_.Exception.Message)"
            continue
        }
        if (-not $rule) {
            $readErrors += "rule '$($entry.Id)': not found"
            continue
        }
        $sendsHere = $null -ne $wsCache -and (@($rule.Properties.destinations.logAnalytics | ForEach-Object { "$($_.workspaceResourceId)" }) -contains $wsCache.ResourceId)
        [pscustomobject]@{ Resource = $rule; Vms = $entry.Vms; VmIds = $entry.VmIds; SendsHere = $sendsHere; Preferred = ($rule.Name -eq $dcrName) }
    }
    # The rule that sends to the lab's workspace is the lab's; the Bicep's name breaks a tie.
    $chosen = @($rules) | Where-Object { $_ } |
        Sort-Object -Property @{ Expression = 'SendsHere'; Descending = $true }, @{ Expression = 'Preferred'; Descending = $true } |
        Select-Object -First 1
    if ($chosen) {
        $dcrResource = $chosen.Resource
        $dcrVmNames  = $chosen.Vms
        $dcrVmIds    = $chosen.VmIds
    }
    elseif ($readErrors.Count -gt 0 -and ($vmsRead -eq 0 -or $ruleVms.Count -gt 0)) {
        # Nothing was read, or every associated rule was unreadable: the lookup itself failed.
        throw "could not read $($readErrors -join '; ')"
    }
    else {
        # What was read carries no rule; what was not is said next to the step to take.
        $dcrUnread = $readErrors
    }
}
catch {
    $dcrLookupError = $_.Exception.Message
}

Invoke-Test "Data collection rule associated with a VM in $($vmGroups -join ' or ')" {
    if ($dcrLookupError) { throw $dcrLookupError }
    if (-not $dcrResource) {
        $unread = if ($dcrUnread.Count -gt 0) { "; could not read $($dcrUnread -join '; ')" } else { '' }
        Write-Host " (no rule is associated with these VMs - Step 5.1.2$unread)" -NoNewline -ForegroundColor Gray
        return $false
    }
    Write-Host " ('$($dcrResource.Name)' in $($dcrResource.ResourceGroupName), on $($dcrVmNames -join ', '))" -NoNewline -ForegroundColor Gray
    $ruleState = "$($dcrResource.Properties.provisioningState)"
    if ($ruleState -ne 'Succeeded') {
        Write-Host " (rule provisioning state is '$ruleState', expected Succeeded)" -NoNewline -ForegroundColor Gray
        return $false
    }
    return $true
}

Invoke-Test "DCR destination points to workspace" {
    if (-not $dcrResource -or -not $wsCache) { return $false }
    $destWsIds = @($dcrResource.Properties.destinations.logAnalytics | ForEach-Object { "$($_.workspaceResourceId)" })
    return ($destWsIds -contains $wsCache.ResourceId)
}

# Perf, not InsightsMetrics: Step 5.1.4 queries the Perf table (#369).
Invoke-Test "DCR has Perf data flow" {
    $streams = $dcrResource.Properties.dataFlows | ForEach-Object { $_.streams } | Select-Object -Unique
    return ($streams -contains 'Microsoft-Perf')
}

Invoke-Test "DCR includes Syslog stream" {
    $streams = $dcrResource.Properties.dataFlows | ForEach-Object { $_.streams } | Select-Object -Unique
    return ($streams -contains 'Microsoft-Syslog')
}

# ============================================================================
# Azure Monitor Agent Tests (#369)
# ============================================================================
Write-Host ""
Write-Host "[Azure Monitor Agent]" -ForegroundColor Yellow

# The lab's VMs are the ones its rule is associated with; a rule without an agent collects nothing.
$agentTypes  = @('AzureMonitorLinuxAgent', 'AzureMonitorWindowsAgent')
$agentStates = [ordered]@{}   # VM name -> provisioning state, 'missing', or the read error
$agentExtIds = @{}            # VM name -> the agent extension's resource id
$agentsReady = $false
if ($dcrVmIds.Count -gt 0) {
    for ($i = 0; $i -lt $dcrVmIds.Count; $i++) {
        try {
            $response = Invoke-AzRestMethod -Method GET -Path "$($dcrVmIds[$i])/extensions?api-version=2024-07-01" -ErrorAction Stop
            if ($response.StatusCode -ne 200) { throw "HTTP $($response.StatusCode)" }
            $agent = @(($response.Content | ConvertFrom-Json).value) |
                Where-Object { $_.properties.publisher -eq 'Microsoft.Azure.Monitor' -and $_.properties.type -in $agentTypes } |
                Select-Object -First 1
            $agentStates[$dcrVmNames[$i]] = if ($agent) { "$($agent.properties.provisioningState)" } else { 'missing' }
            if ($agent) { $agentExtIds[$dcrVmNames[$i]] = "$($dcrVmIds[$i])/extensions/$($agent.name)" }
        }
        catch {
            $agentStates[$dcrVmNames[$i]] = "unreadable: $($_.Exception.Message)"
        }
    }
    $agentsReady = @($agentStates.Values | Where-Object { $_ -ne 'Succeeded' }).Count -eq 0
}

Invoke-Test "Azure Monitor Agent Succeeded on the rule's VMs" {
    if ($agentStates.Count -eq 0) {
        Write-Host " (no VM carries the lab's rule - Step 5.1.2)" -NoNewline -ForegroundColor Gray
        return $false
    }
    $unread = @($agentStates.Keys | Where-Object { $agentStates[$_] -like 'unreadable:*' })
    if ($unread.Count -gt 0) {
        throw "could not read the extensions of $(($unread | ForEach-Object { "'$_' ($($agentStates[$_] -replace '^unreadable: '))" }) -join ', ')"
    }
    $summary = ($agentStates.Keys | ForEach-Object { "$_ $($agentStates[$_])" }) -join ', '
    $step = if ($agentsReady) { '' } else { ' - Step 5.1.2 installs it' }
    Write-Host " ($summary$step)" -NoNewline -ForegroundColor Gray
    return $agentsReady
}

# When a VM's agent extension last installed successfully, as UTC, or $null with the reason. The
# extension's instance view has no time, the activity log has one event per write (issue #369).
function Get-AgentInstallTime {
    param([string]$ExtensionId)
    try {
        $events = @(Get-AzActivityLog -ResourceId $ExtensionId -StartTime (Get-Date).AddDays(-14) -WarningAction SilentlyContinue -ErrorAction Stop)
    }
    catch {
        return [pscustomobject]@{ Time = $null; Reason = "the activity log could not be read: $($_.Exception.Message)" }
    }
    # Plain output carries strings, detailed output localizable strings with a Value.
    $writes = @($events | Where-Object {
        $op = if ($_.OperationName.Value) { "$($_.OperationName.Value)" } else { "$($_.OperationName)" }
        $status = if ($_.Status.Value) { "$($_.Status.Value)" } else { "$($_.Status)" }
        $status -eq 'Succeeded' -and $op -match 'Create or Update|extensions/write'
    })
    if ($writes.Count -eq 0) {
        return [pscustomobject]@{ Time = $null; Reason = 'the activity log has no successful install of the extension in the last 14 days' }
    }
    $latest = ($writes | Sort-Object -Property EventTimestamp -Descending | Select-Object -First 1).EventTimestamp
    [pscustomobject]@{ Time = ([datetime]$latest).ToUniversalTime(); Reason = $null }
}

$heartbeatWindow = 15
# Waiting only helps a Succeeded agent whose first rows, or whose workspace's table, are still on their way.
# $heartbeatWait bounds the row wait only where the agent's install time is not known.
$heartbeatWait = if ($agentsReady) { $HeartbeatWaitMinutes } else { 0 }
$tableWait     = if ($agentsReady) { $NewWorkspaceWaitMinutes } else { 0 }
$installWait   = $AgentInstallWaitMinutes
# A workspace without its Heartbeat table answers BadRequest: failed to resolve the table.
$tableMissingPattern = 'BadRequest|Bad Request|Failed to resolve|could not be resolved|SEM0100'
Invoke-Test "Heartbeat from the rule's VMs in the last $heartbeatWindow minutes" {
    if ($dcrVmIds.Count -eq 0) {
        Write-Host " (no VM carries the lab's rule - Step 5.1.2)" -NoNewline -ForegroundColor Gray
        return $false
    }
    if (-not $wsCache) { throw "workspace '$workspaceName' not found" }
    $idList = ($dcrVmIds | ForEach-Object { "'$($_.ToLowerInvariant())'" }) -join ', '
    $query = "Heartbeat | where TimeGenerated > ago($($heartbeatWindow)m) | where tolower(_ResourceId) in ($idList) | summarize LastHeartbeat = max(TimeGenerated) by VmId = tolower(_ResourceId)"
    $started       = Get-Date
    $tableDeadline = $started.AddMinutes($tableWait)
    $rowDeadline   = $null   # set when the table first exists; bounds the wait where no install time is known
    $installs      = @{}     # VM name -> install time or why there is none, read once a VM lacks a row
    while ($true) {
        $tableError = $null
        $result     = $null
        try {
            $result = Invoke-AzOperationalInsightsQuery -WorkspaceId "$($wsCache.CustomerId)" -Query $query -ErrorAction Stop
        }
        catch {
            # Only a missing table is waited for; any other failure is a failure.
            if ($_.Exception.Message -notmatch $tableMissingPattern -or $null -ne $rowDeadline) { throw }
            $tableError = $_.Exception.Message
        }
        if (-not $tableError) {
            if ($null -eq $result) { throw 'the workspace query returned nothing' }
            if ($result.Error) {
                if ("$($result.Error.Message)" -notmatch $tableMissingPattern -or $null -ne $rowDeadline) { throw "the workspace query failed: $($result.Error.Message)" }
                $tableError = "$($result.Error.Message)"
            }
        }
        if ($tableError) {
            $waited = [int][math]::Floor(((Get-Date) - $started).TotalMinutes)
            if ((Get-Date) -ge $tableDeadline) {
                $after = if ($tableWait -gt 0) { " after waiting $waited of $tableWait minutes" } else { '' }
                Write-Host " (the Heartbeat table does not exist in '$workspaceName' yet${after}: a new workspace creates it with the first row, up to about 40 minutes after the workspace is created; run again later - Step 5.1.3. Query said: $tableError)" -NoNewline -ForegroundColor Gray
                return $false
            }
            Write-Host ''
            Write-Host "    workspace not ready: no Heartbeat table yet, waited $waited of $tableWait minutes, trying again in 60 seconds" -ForegroundColor Gray
            Start-Sleep -Seconds 60
            continue
        }
        if ($null -eq $rowDeadline) { $rowDeadline = (Get-Date).AddMinutes($heartbeatWait) }
        $seen = @($result.Results | ForEach-Object { "$($_.VmId)" })
        $missing = @(for ($i = 0; $i -lt $dcrVmIds.Count; $i++) { if ($dcrVmIds[$i].ToLowerInvariant() -notin $seen) { $dcrVmNames[$i] } })
        # A Failed or missing agent explains the gap; there is nothing to wait for.
        if ($missing.Count -eq 0 -or -not $agentsReady) { break }
        # The first row follows the install by 27-39 minutes: wait to a bound after the install
        # time, or only -HeartbeatWaitMinutes where it is not known.
        $now = (Get-Date).ToUniversalTime()
        $stillWaiting = @()
        foreach ($name in $missing) {
            if (-not $installs.ContainsKey($name)) {
                $installs[$name] = if ($agentExtIds[$name]) { Get-AgentInstallTime -ExtensionId $agentExtIds[$name] }
                                   else { [pscustomobject]@{ Time = $null; Reason = 'the extension id is not known' } }
            }
            $install = $installs[$name]
            if ($install.Time) {
                if ($now -lt $install.Time.AddMinutes($installWait)) { $stillWaiting += $name }
            }
            elseif ((Get-Date) -lt $rowDeadline) { $stillWaiting += $name }
        }
        if ($stillWaiting.Count -eq 0) { break }
        $progress = foreach ($name in $stillWaiting) {
            if ($installs[$name].Time) {
                $age = [int][math]::Floor(($now - $installs[$name].Time).TotalMinutes)
                "$name (agent installed $age of $installWait minutes ago)"
            }
            else { "$name (install time unknown, waiting up to $heartbeatWait minutes)" }
        }
        Write-Host ''
        Write-Host "    waiting for the first Heartbeat row from $($progress -join ', '), trying again in 60 seconds" -ForegroundColor Gray
        Start-Sleep -Seconds 60
    }
    if ($missing.Count -gt 0) {
        $causes = foreach ($name in $missing) {
            $install = $installs[$name]
            if (-not $install) { $name }
            elseif ($install.Time) {
                $age = [int][math]::Floor(((Get-Date).ToUniversalTime() - $install.Time).TotalMinutes)
                "$name (agent installed $age minutes ago, past the $installWait-minute bound the first row takes: the agent is installed but not sending, check that the VM runs and that the rule is associated with it)"
            }
            else { "$name (install time unknown: $($install.Reason); waited $heartbeatWait minutes)" }
        }
        Write-Host " (no row from $($causes -join '; ') - Steps 5.1.2 and 5.1.3)" -NoNewline -ForegroundColor Gray
        return $false
    }
    return $true
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

# Found through its scope, not by group (#355, #365): the Portal defaults the rule's group to the
# watched VM's group, so the rule the learner named 'skycraft-cpu-alert' is looked for on a
# SkyCraft VM in any group. The name stays the guide's: VM insights' recommended alerts put
# several other CPU and memory rules on the same VM, so the scope alone cannot tell the lab's
# rule apart. All the alert checks below read the rule found here.
$vmScope          = '/providers/Microsoft\.Compute/virtualMachines/(dev|prod)-skycraft-swc-'
$alert            = $null
$alertOnVm        = $false
$alertListError   = $null
$alertOtherOnVm   = @()
try {
    $allAlertRules = @(Get-AzMetricAlertRuleV2 -ErrorAction Stop | Where-Object { $_ })
    $alertRulesOnVm = @($allAlertRules | Where-Object { @($_.Scopes | Where-Object { "$_" -match $vmScope }).Count -gt 0 })
    # A named rule on a SkyCraft VM first, in the guide's group before any other; then a named
    # rule in the guide's group that watches something else, which the checks below still read.
    $alert = @($allAlertRules | Where-Object { $_.Name -eq $alertRuleName -and ($_ -in $alertRulesOnVm -or $_.ResourceGroup -eq $platformRg) }) |
        Sort-Object -Property @{ Expression = { $_ -in $alertRulesOnVm }; Descending = $true }, @{ Expression = { $_.ResourceGroup -eq $platformRg }; Descending = $true } |
        Select-Object -First 1
    $alertOnVm      = $null -ne $alert -and $alert -in $alertRulesOnVm
    $alertOtherOnVm = @($alertRulesOnVm | Where-Object { $_.Name -ne $alertRuleName })
}
catch {
    # Listing the subscription failed: the guide's own group and name still find the rule.
    $alertListError = $_.Exception.Message
    $alert = Get-AzMetricAlertRuleV2 -ResourceGroupName $platformRg -Name $alertRuleName -ErrorAction SilentlyContinue
}

Invoke-Test "Alert rule '$alertRuleName' exists" {
    if ($null -ne $alert -and $alert.Name -eq $alertRuleName) {
        $where = if ($alert.ResourceGroup -and $alert.ResourceGroup -ne $platformRg) { "; Step 5.1.5 puts it in $platformRg, either group works" } else { '' }
        $watches = if ($alertOnVm) { ", on a SkyCraft VM" } else { '' }
        Write-Host " (in $($alert.ResourceGroup)$watches$where)" -NoNewline -ForegroundColor Gray
        return $true
    }
    if ($alertListError) {
        Write-Host " (no rule named '$alertRuleName' in $platformRg; the subscription's alert rules could not be listed: $alertListError)" -NoNewline -ForegroundColor Gray
    }
    elseif ($alertOtherOnVm.Count -gt 0) {
        $found = ($alertOtherOnVm | ForEach-Object { "'$($_.Name)' in $($_.ResourceGroup)" }) -join ', '
        Write-Host " (no rule named '$alertRuleName' on a SkyCraft VM; found $found - Step 5.1.5 names the rule '$alertRuleName')" -NoNewline -ForegroundColor Gray
    }
    else {
        Write-Host " (no rule named '$alertRuleName' on a SkyCraft VM - Step 5.1.5)" -NoNewline -ForegroundColor Gray
    }
    return $false
}

Invoke-Test "Alert rule is enabled" {
    return ($null -ne $alert -and $alert.Enabled -eq $true)
}

Invoke-Test "Alert rule severity is 2 (Warning)" {
    return ($null -ne $alert -and $alert.Severity -eq 2)
}

Invoke-Test "Alert rule window size is 5 minutes" {
    return ($null -ne $alert -and $alert.WindowSize -eq [System.TimeSpan]::FromMinutes(5))
}

Invoke-Test "Alert rule evaluation frequency is 1 minute" {
    return ($null -ne $alert -and $alert.EvaluationFrequency -eq [System.TimeSpan]::FromMinutes(1))
}

Invoke-Test "Alert rule threshold is > 80% CPU" {
    if (-not $alert) { return $false }
    # Read criteria from raw ARM (camelCase) — the typed PSMetricCriteria object
    # does not reliably expose metricName/operator across Az.Monitor versions.
    $crit = (Get-LabArmResource -ResourceId $alert.Id -ApiVersion $metricAlertApiVersion -ExpandProperties).Properties.criteria.allOf[0]
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

Exit-Lab -FailureCount $failCount
