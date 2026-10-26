<#
.SYNOPSIS
    Removes Lab 5.1 Azure Monitor & Insights resources.

.DESCRIPTION
    Cleans up Lab 5.1 monitoring resources in the following order:
    1. Metric Alert (skycraft-cpu-alert)
    2. VM Insights DCR associations
    3. VM Insights Data Collection Rules (skycraft-vm-dcr, or the Portal's MSVMI-<...>)
    4. Action Group (skycraft-ops-ag)
    5. Storage Diagnostic Settings (skycraft-storage-diag)
    6. Log Analytics Workspace (platform-skycraft-swc-law)

    The alert rule and the data collection rule are found the way Test-Lab.ps1 finds them, so
    teardown removes whatever the validator accepts (issues #355, #362). The alert rule is the one
    named 'skycraft-cpu-alert' that watches a SkyCraft VM, in whatever group it sits (the Portal
    defaults it to the VM's group), or that sits in the platform group. The data collection rules
    are those associated with a VM of the dev or prod group that send to the lab's workspace or
    are named 'skycraft-vm-dcr', in whatever group they sit (VM insights puts its 'MSVMI-<...>'
    rule in the VM's group); their associations go with them. The Bicep's 'skycraft-vm-dcr' in the
    platform group is removed even when no VM uses it any more.

    Every step continues on error, so one stuck object does not strand the rest. A lookup that
    fails (a 403, throttling, a transient error) or a deletion that fails is reported as [ERROR]
    and counted; if anything failed the script exits 1. An object that does not exist is not a
    failure: only a lookup that succeeds and does not find it, or a getter that reports it as not
    found, means "absent" - Test-LabNotFoundError tells the two apart (issue #290; the script used
    to look everything up with -ErrorAction SilentlyContinue, and to print a failed deletion as a
    warning and exit 0).

    The alerts, associations, action groups, diagnostic settings and workspaces are listed and
    picked - by name, and the alert and the associations by what they relate to. The Az.Monitor getters for one action group, diagnostic setting or
    association are generated cmdlets, which can report a missing object as a plain exception
    that is no recognised not-found error (as Get-AzAutoscaleSetting does, #297); a missing object
    in a listing is an empty match instead, and the alerts and workspaces are read the same way.
    An object is kept while something that depends on it could
    not be looked up or deleted: the action group while the alert may still use it, the data
    collection rule while its association may still exist, and the workspace while the rule or the
    storage diagnostic setting may still send to it. The kept object is not counted again - the
    failure that keeps it already is.

    Every exit goes through Exit-Lab (tools/LabCommon.psm1): 1 when anything failed, 0
    otherwise. Run as "pwsh -File", where #Requires -Modules would drop a bare "exit 1"
    (issue #104), it also sets the process exit code; run at a prompt or by another script,
    it leaves the session open and the code in $LASTEXITCODE (issue #257).

    Note: This does NOT remove VMs, VNets, or Storage Accounts from earlier labs.
    The Azure Dashboard (SkyCraft-Ops) must be removed manually via the Azure Portal.

.PARAMETER DevEnvironment
    Environment whose group's VMs are searched first for data collection rule associations; the
    other environment's group is searched as well, as Test-Lab.ps1 does. Default: dev

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
#Requires -Modules Az.Accounts, Az.Resources, Az.Compute, Az.Storage, Az.OperationalInsights, Az.Monitor

[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter()]
    [ValidateSet('dev', 'prod')]
    [string]$DevEnvironment = 'dev',

    [Parameter()]
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
# Exit-Lab ends the script with exit code 0 or 1 and leaves an interactive session open (#257).
Import-Module (Join-Path $PSScriptRoot '../../../tools/LabCommon.psm1') -Force -Verbose:$false
if ($Force) { $ConfirmPreference = 'None' }

# Counts lookups that failed and objects that exist but could not be deleted. Absent objects are
# not failures.
$script:cleanupFailures = 0

# Whether a lookup's error says the object does not exist, rather than that the lookup failed.
# Get-AzVM and Get-AzResource -ResourceId report a missing resource as an ARM 404: "The Resource
# '<type>/<name>' under resource group '<rg>' was not found.", code ResourceNotFound; when the
# group is gone as well, "Resource group '<rg>' could not be found.", code ResourceGroupNotFound,
# which is also what every listing in a missing group reports; with no error body, "Operation
# returned an invalid status code 'NotFound'". The Azure.Core clients say "Status: 404 (Not
# Found)". A missing subscription is a 404 too, but it means the context is wrong, not that the
# object is gone, so it never reads as "absent".
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
        # ResponseStatusCode: the generated cmdlets' RestException, which may carry no error body.
        foreach ($status in @($exception.Response.StatusCode, $exception.ResponseStatusCode, $exception.Status)) {
            if ("$status" -in @('404', 'NotFound')) { $status404 = $true }
        }
    }
    $text = $evidence -join "`n"

    if ($text -match 'SubscriptionNotFound|subscription .{0,80}(could not be|was not) found') { return $false }
    if ($status404) { return $true }
    return $text -match '\bResource(Group)?NotFound\b|was not found|Resource group .{0,100}could not be found|invalid status code ''NotFound''|\b404 \(Not Found\)'
}

# Runs one lookup with -ErrorAction Stop inside $Lookup, and returns what it found:
#   Value     the lookup's output, as an array - empty when the object is absent
#   NotFound  the getter reported the object as not found (Test-LabNotFoundError)
#   Failed    the lookup failed any other way: it is reported as [ERROR] and counted, because it
#             cannot tell whether the object is gone, and the caller leaves the object alone
function Invoke-LabLookup {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Target,

        [Parameter(Mandatory = $true)]
        [scriptblock]$Lookup
    )

    try {
        $value = @(& $Lookup)
        return [pscustomobject]@{ Value = $value; NotFound = $false; Failed = $false }
    }
    catch {
        if (Test-LabNotFoundError -ErrorRecord $_) {
            return [pscustomobject]@{ Value = @(); NotFound = $true; Failed = $false }
        }
        $script:cleanupFailures++
        Write-Host "  -> [ERROR] Could not look up $($Target): $_" -ForegroundColor Red
        Write-Host "     A failed lookup is not 'absent': it may still exist, so this counts as a failure." -ForegroundColor Gray
        return [pscustomobject]@{ Value = @(); NotFound = $false; Failed = $true }
    }
}

# Configuration
$platformRg      = 'platform-skycraft-swc-rg'
$workspaceName   = 'platform-skycraft-swc-law'
$dcrName         = 'skycraft-vm-dcr'
$actionGroupName = 'skycraft-ops-ag'
$alertRuleName   = 'skycraft-cpu-alert'
$diagSettingName = 'skycraft-storage-diag'
$devRgName       = "$DevEnvironment-skycraft-swc-rg"
# The scope Test-Lab.ps1 reads as a SkyCraft VM, in any group.
$labVmScope      = '/providers/Microsoft\.Compute/virtualMachines/(dev|prod)-skycraft-swc-'

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  Lab 5.1 - Resource Cleanup" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# Verify login
$context = Get-AzContext
if (-not $context) {
    Write-Host "  [ERROR] Not logged into Azure. Run 'Connect-AzAccount' first." -ForegroundColor Red
    Exit-Lab -FailureCount 1
}
$subscriptionId = $context.Subscription.Id
$workspaceId    = "/subscriptions/$subscriptionId/resourceGroups/$platformRg/providers/Microsoft.OperationalInsights/workspaces/$workspaceName"

# Why an object is kept although it was found: something that depends on it could not be looked up
# or deleted. The lookup or the deletion is already counted, so keeping is not.
$keepActionGroupReason = $null
$keepDcrReason         = $null
$keepWorkspaceReason   = $null

# ── Inventory resources to delete ────────────────────────────────────────
Write-Host "Resources to be deleted:" -ForegroundColor Yellow

$resourcesToDelete = [System.Collections.Generic.List[hashtable]]::new()

# Metric Alert - found as Test-Lab.ps1 finds it (#355, #362): the rule named '$alertRuleName' that
# watches a SkyCraft VM, in whatever group it sits, or that sits in the platform group. The Portal
# defaults the rule's group to the watched VM's, and the guide tells the learner that a rule left
# there passes, so the alert rules of the whole subscription are listed and picked by name and scope.
# A rule of that name elsewhere, watching something else, is not the lab's and is left alone.
$alertLookup = Invoke-LabLookup -Target 'the metric alert rules in the subscription' -Lookup {
    Get-AzMetricAlertRuleV2 -ErrorAction Stop
}
if ($alertLookup.Failed) {
    $keepActionGroupReason = "metric alert '$alertRuleName' could not be looked up, and it may still use the action group"
}
foreach ($alertRule in @($alertLookup.Value | Where-Object { $_ -and $_.Name -eq $alertRuleName })) {
    $alertRg = if ($alertRule.ResourceGroup) { "$($alertRule.ResourceGroup)" } else { ("$($alertRule.Id)" -split '/')[4] }
    $onLabVm = @($alertRule.Scopes | Where-Object { "$_" -match $labVmScope }).Count -gt 0
    if (-not $onLabVm -and $alertRg -ne $platformRg) { continue }
    $resourcesToDelete.Add(@{ Type = 'Alert'; Name = $alertRuleName; ResourceGroup = $alertRg })
    Write-Host "  - Metric Alert: $alertRuleName (in $alertRg)" -ForegroundColor Gray
}

# Data Collection Rules and their associations - found as Test-Lab.ps1 finds the rule (#355,
# #362): through the VMs they are associated with. VM insights names its rule 'MSVMI-<...>' in the
# VM's group, the data collection rule wizard takes any group, and the Bicep creates '$dcrName' in
# the platform group. The VMs of the dev and prod groups are listed, the associations of each are
# read, and every rule they name is read: a rule is the lab's when it sends to the lab's workspace
# or is named '$dcrName'. A rule that sends elsewhere is not the lab's and is left alone, with its
# association. The Bicep's rule is also looked up by its id, in case no VM uses it any more.
$vmGroups = @($devRgName) + @(@('dev', 'prod') | Where-Object { $_ -ne $DevEnvironment } | ForEach-Object { "$_-skycraft-swc-rg" })
$associations = [System.Collections.Generic.List[hashtable]]::new()
foreach ($vmGroup in $vmGroups) {
    $vmLookup = Invoke-LabLookup -Target "the VMs in '$vmGroup'" -Lookup {
        Get-AzVM -ResourceGroupName $vmGroup -ErrorAction Stop
    }
    if ($vmLookup.Failed) {
        $keepDcrReason = "the VMs in '$vmGroup' could not be looked up, and a rule may still be associated with one of them"
        continue
    }
    foreach ($vm in @($vmLookup.Value | Where-Object { $_ })) {
        $vmId = $vm.Id
        $assocLookup = Invoke-LabLookup -Target "the data collection rule associations on '$($vm.Name)'" -Lookup {
            Get-AzDataCollectionRuleAssociation -ResourceUri $vmId -ErrorAction Stop
        }
        if ($assocLookup.Failed) {
            $keepDcrReason = "the associations on '$($vm.Name)' could not be looked up, and a rule may still be associated with it"
            continue
        }
        foreach ($assoc in @($assocLookup.Value | Where-Object { $_ })) {
            # An association with a data collection endpoint names no rule.
            if (-not "$($assoc.DataCollectionRuleId)") { continue }
            $associations.Add(@{ Name = "$($assoc.Name)"; VmId = $vmId; VmName = "$($vm.Name)"; RuleId = "$($assoc.DataCollectionRuleId)" })
        }
    }
}

$bicepDcrId = "/subscriptions/$subscriptionId/resourceGroups/$platformRg/providers/Microsoft.Insights/dataCollectionRules/$dcrName"
$candidateRuleIds = [ordered]@{}   # rule id (lower case) -> rule id
foreach ($id in @($associations | ForEach-Object { $_.RuleId }) + $bicepDcrId) {
    if (-not $candidateRuleIds.Contains($id.ToLowerInvariant())) { $candidateRuleIds[$id.ToLowerInvariant()] = $id }
}
$labRuleKeys = [System.Collections.Generic.HashSet[string]]::new()
foreach ($ruleId in @($candidateRuleIds.Values)) {
    $ruleName = ($ruleId -split '/')[-1]
    $ruleLookup = Invoke-LabLookup -Target "data collection rule '$ruleName'" -Lookup {
        Get-AzResource -ResourceId $ruleId -ExpandProperties -ErrorAction Stop
    }
    if ($ruleLookup.Failed) {
        if (-not $keepWorkspaceReason) {
            $keepWorkspaceReason = "data collection rule '$ruleName' could not be looked up, and it may still send to the workspace"
        }
        continue
    }
    $rule = $ruleLookup.Value | Select-Object -First 1
    if (-not $rule) { continue }
    $sendsHere = @($rule.Properties.destinations.logAnalytics | ForEach-Object { "$($_.workspaceResourceId)" }) -contains $workspaceId
    if (-not $sendsHere -and $ruleName -ne $dcrName) { continue }
    [void]$labRuleKeys.Add($ruleId.ToLowerInvariant())
    $ruleGroup = ($ruleId -split '/')[4]
    $resourcesToDelete.Add(@{ Type = 'DCR'; Name = $ruleName; ResourceId = $ruleId; ResourceGroup = $ruleGroup })
    Write-Host "  - Data Collection Rule: $ruleName (in $ruleGroup)" -ForegroundColor Gray
}
foreach ($assoc in $associations) {
    if (-not $labRuleKeys.Contains($assoc.RuleId.ToLowerInvariant())) { continue }
    $resourcesToDelete.Add(@{ Type = 'DCRAssoc'; Name = $assoc.Name; VmId = $assoc.VmId; VmName = $assoc.VmName; RuleKey = $assoc.RuleId.ToLowerInvariant() })
    Write-Host "  - DCR Association: $($assoc.Name) (on $($assoc.VmName))" -ForegroundColor Gray
}

# Action Group - listed and picked by name
$agLookup = Invoke-LabLookup -Target "the action groups in '$platformRg'" -Lookup {
    Get-AzActionGroup -ResourceGroupName $platformRg -ErrorAction Stop
}
if ($agLookup.Value | Where-Object { $_.Name -eq $actionGroupName }) {
    $resourcesToDelete.Add(@{ Type = 'ActionGroup'; Name = $actionGroupName })
    Write-Host "  - Action Group: $actionGroupName" -ForegroundColor Gray
}

# Storage Diagnostic Settings (scoped to blobServices/default) - listed and picked by name, on
# every account in the platform group: the group can hold more than the lab's account, and the
# first one listed need not be the one the setting is on.
$storageLookup = Invoke-LabLookup -Target "the storage accounts in '$platformRg'" -Lookup {
    Get-AzStorageAccount -ResourceGroupName $platformRg -ErrorAction Stop
}
if ($storageLookup.Failed) {
    if (-not $keepWorkspaceReason) {
        $keepWorkspaceReason = "the storage accounts in '$platformRg' could not be looked up, and diagnostic setting '$diagSettingName' may still send to the workspace"
    }
}
foreach ($storageAcct in $storageLookup.Value) {
    $blobServiceId = "$($storageAcct.Id)/blobServices/default"
    $diagLookup = Invoke-LabLookup -Target "the diagnostic settings of '$($storageAcct.StorageAccountName)'" -Lookup {
        Get-AzDiagnosticSetting -ResourceId $blobServiceId -ErrorAction Stop
    }
    if ($diagLookup.Failed) {
        if (-not $keepWorkspaceReason) {
            $keepWorkspaceReason = "diagnostic setting '$diagSettingName' on '$($storageAcct.StorageAccountName)' could not be looked up, and it may still send to the workspace"
        }
    }
    elseif ($diagLookup.Value | Where-Object { $_.Name -eq $diagSettingName }) {
        $resourcesToDelete.Add(@{ Type = 'StorageDiag'; Name = $diagSettingName; BlobServiceId = $blobServiceId; Account = $storageAcct.StorageAccountName })
        Write-Host "  - Storage Diagnostic Settings: $diagSettingName (on $($storageAcct.StorageAccountName))" -ForegroundColor Gray
    }
}

# Log Analytics Workspace - listed and picked by name
$wsLookup = Invoke-LabLookup -Target "the Log Analytics workspaces in '$platformRg'" -Lookup {
    Get-AzOperationalInsightsWorkspace -ResourceGroupName $platformRg -ErrorAction Stop
}
if ($wsLookup.Value | Where-Object { $_.Name -eq $workspaceName }) {
    $resourcesToDelete.Add(@{ Type = 'Workspace'; Name = $workspaceName })
    Write-Host "  - Log Analytics Workspace: $workspaceName" -ForegroundColor Gray
}

if ($resourcesToDelete.Count -eq 0 -and $script:cleanupFailures -eq 0) {
    Write-Host "`nNo Lab 5.1 resources found to delete." -ForegroundColor Green
    exit 0
}
if ($resourcesToDelete.Count -eq 0) {
    Write-Host "  (nothing found - but what could not be looked up may still exist)" -ForegroundColor Gray
}

# ── Delete resources in dependency order ──────────────────────────────────
Write-Host "`nDeleting resources..." -ForegroundColor Yellow

# 1. Metric Alert
foreach ($r in $resourcesToDelete | Where-Object { $_.Type -eq 'Alert' }) {
    if ($PSCmdlet.ShouldProcess("$($r.ResourceGroup)/$($r.Name)", 'Remove Metric Alert')) {
        Write-Host "  Deleting Metric Alert: $($r.Name) (in $($r.ResourceGroup))..." -ForegroundColor Gray
        try {
            Remove-AzMetricAlertRuleV2 -ResourceGroupName $r.ResourceGroup -Name $r.Name -ErrorAction Stop | Out-Null
            Write-Host "  ✓ Deleted" -ForegroundColor Green
        } catch {
            $script:cleanupFailures++
            $keepActionGroupReason = "metric alert '$($r.Name)' could not be deleted, and it may still use the action group"
            Write-Host "  [ERROR] Could not delete Metric Alert '$($r.Name)' in '$($r.ResourceGroup)': $_" -ForegroundColor Red
        }
    }
}

# 2. DCR Associations - a rule whose association could not be deleted is kept in step 3.
$keepRuleReasons = @{}   # rule id (lower case) -> why that rule is kept
foreach ($r in $resourcesToDelete | Where-Object { $_.Type -eq 'DCRAssoc' }) {
    if ($PSCmdlet.ShouldProcess("$($r.VmName)/$($r.Name)", 'Remove DCR Association')) {
        Write-Host "  Deleting DCR Association: $($r.Name) (on $($r.VmName))..." -ForegroundColor Gray
        try {
            Remove-AzDataCollectionRuleAssociation -ResourceUri $r.VmId -AssociationName $r.Name -ErrorAction Stop | Out-Null
            Write-Host "  ✓ Deleted" -ForegroundColor Green
        } catch {
            $script:cleanupFailures++
            $keepRuleReasons[$r.RuleKey] = "association '$($r.Name)' could not be deleted, and it still ties the rule to '$($r.VmName)'"
            Write-Host "  [ERROR] Could not delete DCR Association '$($r.Name)' on '$($r.VmName)': $_" -ForegroundColor Red
        }
    }
}

# 3. Data Collection Rules
foreach ($r in $resourcesToDelete | Where-Object { $_.Type -eq 'DCR' }) {
    $keepReason = if ($keepDcrReason) { $keepDcrReason } else { $keepRuleReasons[$r.ResourceId.ToLowerInvariant()] }
    if ($keepReason) {
        $keepWorkspaceReason = "data collection rule '$($r.Name)' was kept, and it still sends to the workspace"
        Write-Host "  [SKIP] Kept Data Collection Rule '$($r.Name)': $keepReason." -ForegroundColor Yellow
        continue
    }
    if ($PSCmdlet.ShouldProcess("$($r.ResourceGroup)/$($r.Name)", 'Remove Data Collection Rule')) {
        Write-Host "  Deleting Data Collection Rule: $($r.Name) (in $($r.ResourceGroup))..." -ForegroundColor Gray
        try {
            Remove-AzResource -ResourceId $r.ResourceId -Force -ErrorAction Stop | Out-Null
            Write-Host "  ✓ Deleted" -ForegroundColor Green
        } catch {
            $script:cleanupFailures++
            $keepWorkspaceReason = "data collection rule '$($r.Name)' could not be deleted, and it still sends to the workspace"
            Write-Host "  [ERROR] Could not delete Data Collection Rule '$($r.Name)': $_" -ForegroundColor Red
        }
    }
}

# 4. Action Group
foreach ($r in $resourcesToDelete | Where-Object { $_.Type -eq 'ActionGroup' }) {
    if ($keepActionGroupReason) {
        Write-Host "  [SKIP] Kept Action Group '$($r.Name)': $keepActionGroupReason." -ForegroundColor Yellow
        continue
    }
    if ($PSCmdlet.ShouldProcess($r.Name, 'Remove Action Group')) {
        Write-Host "  Deleting Action Group: $($r.Name)..." -ForegroundColor Gray
        try {
            Remove-AzActionGroup -ResourceGroupName $platformRg -Name $r.Name -ErrorAction Stop | Out-Null
            Write-Host "  ✓ Deleted" -ForegroundColor Green
        } catch {
            $script:cleanupFailures++
            Write-Host "  [ERROR] Could not delete Action Group '$($r.Name)': $_" -ForegroundColor Red
        }
    }
}

# 5. Storage Diagnostic Settings
foreach ($r in $resourcesToDelete | Where-Object { $_.Type -eq 'StorageDiag' }) {
    if ($PSCmdlet.ShouldProcess("$($r.Account)/$($r.Name)", 'Remove Storage Diagnostic Settings')) {
        Write-Host "  Deleting Storage Diagnostic Settings: $($r.Name) (on $($r.Account))..." -ForegroundColor Gray
        try {
            Remove-AzDiagnosticSetting -ResourceId $r.BlobServiceId -Name $r.Name -ErrorAction Stop | Out-Null
            Write-Host "  ✓ Deleted" -ForegroundColor Green
        } catch {
            $script:cleanupFailures++
            if (-not $keepWorkspaceReason) {
                $keepWorkspaceReason = "diagnostic setting '$($r.Name)' on '$($r.Account)' could not be deleted, and it still sends to the workspace"
            }
            Write-Host "  [ERROR] Could not delete Storage Diagnostic Settings '$($r.Name)' on '$($r.Account)': $_" -ForegroundColor Red
        }
    }
}

# 6. Log Analytics Workspace (soft-delete by default — 14 days recovery window)
foreach ($r in $resourcesToDelete | Where-Object { $_.Type -eq 'Workspace' }) {
    if ($keepWorkspaceReason) {
        Write-Host "  [SKIP] Kept Log Analytics Workspace '$($r.Name)': $keepWorkspaceReason." -ForegroundColor Yellow
        continue
    }
    if ($PSCmdlet.ShouldProcess($r.Name, 'Remove Log Analytics Workspace')) {
        Write-Host "  Deleting Log Analytics Workspace: $($r.Name)..." -ForegroundColor Gray
        try {
            Remove-AzOperationalInsightsWorkspace -ResourceGroupName $platformRg -Name $r.Name -Force -ErrorAction Stop | Out-Null
            Write-Host "  ✓ Deleted (soft-delete: 14-day recovery window)" -ForegroundColor Green
            Write-Host "    To permanently purge: Remove-AzOperationalInsightsWorkspace -ResourceGroupName $platformRg -Name $($r.Name) -ForceDelete" -ForegroundColor Gray
        } catch {
            $script:cleanupFailures++
            Write-Host "  [ERROR] Could not delete Log Analytics Workspace '$($r.Name)': $_" -ForegroundColor Red
        }
    }
}

Write-Host "`n========================================" -ForegroundColor Cyan
if ($script:cleanupFailures -gt 0) {
    Write-Host "  Cleanup finished with $($script:cleanupFailures) failure(s)" -ForegroundColor Red
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "  See the [ERROR] lines above. What could not be looked up or deleted may still exist." -ForegroundColor Gray
    Write-Host "========================================`n" -ForegroundColor Cyan
    Exit-Lab -FailureCount 1
}
Write-Host "  Cleanup Complete" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  VMs, VNets, Storage Accounts were NOT deleted." -ForegroundColor Gray
Write-Host "  Remove the 'SkyCraft-Ops' dashboard manually in the Azure Portal." -ForegroundColor Gray
Write-Host "========================================`n" -ForegroundColor Cyan
