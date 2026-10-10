<#
.SYNOPSIS
    Removes Lab 5.1 Azure Monitor & Insights resources.

.DESCRIPTION
    Cleans up Lab 5.1 monitoring resources in the following order:
    1. Metric Alert (skycraft-cpu-alert)
    2. VM Insights DCR association
    3. VM Insights Data Collection Rule (skycraft-vm-dcr)
    4. Action Group (skycraft-ops-ag)
    5. Storage Diagnostic Settings (skycraft-storage-diag)
    6. Log Analytics Workspace (platform-skycraft-swc-law)

    Every step continues on error, so one stuck object does not strand the rest. A lookup that
    fails (a 403, throttling, a transient error) or a deletion that fails is reported as [ERROR]
    and counted; if anything failed the script exits 1. An object that does not exist is not a
    failure: only a lookup that succeeds and does not find it, or a getter that reports it as not
    found, means "absent" - Test-LabNotFoundError tells the two apart (issue #290; the script used
    to look everything up with -ErrorAction SilentlyContinue, and to print a failed deletion as a
    warning and exit 0).

    The alerts, associations, action groups, diagnostic settings and workspaces are listed and
    picked by name. The Az.Monitor getters for one action group, diagnostic setting or
    association are generated cmdlets, which can report a missing object as a plain exception
    that is no recognised not-found error (as Get-AzAutoscaleSetting does, #297); a missing object
    in a listing is an empty match instead, and the alerts and workspaces are read the same way.
    An object is kept while something that depends on it could
    not be looked up or deleted: the action group while the alert may still use it, the data
    collection rule while its association may still exist, and the workspace while the rule or the
    storage diagnostic setting may still send to it. The kept object is not counted again - the
    failure that keeps it already is.

    Each non-zero exit is paired with $Host.SetShouldExit: a bare "exit 1" is dropped under
    "pwsh -File" for any script that declares #Requires -Modules for a module it has to
    auto-import, and the process would exit 0 with the failure still on screen (issue #104).

    Note: This does NOT remove VMs, VNets, or Storage Accounts from earlier labs.
    The Azure Dashboard (SkyCraft-Ops) must be removed manually via the Azure Portal.

.PARAMETER DevEnvironment
    Dev environment prefix to locate the dev VM for DCR association removal. Default: dev

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
$dcrAssocName    = 'skycraft-vminsights-dcr-assoc'
$actionGroupName = 'skycraft-ops-ag'
$alertRuleName   = 'skycraft-cpu-alert'
$diagSettingName = 'skycraft-storage-diag'
$devVmName       = "$DevEnvironment-skycraft-swc-auth-vm"
$devRgName       = "$DevEnvironment-skycraft-swc-rg"

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  Lab 5.1 - Resource Cleanup" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# Verify login
$context = Get-AzContext
if (-not $context) {
    Write-Host "  [ERROR] Not logged into Azure. Run 'Connect-AzAccount' first." -ForegroundColor Red
    $Host.SetShouldExit(1)
    exit 1
}
$subscriptionId = $context.Subscription.Id

# Why an object is kept although it was found: something that depends on it could not be looked up
# or deleted. The lookup or the deletion is already counted, so keeping is not.
$keepActionGroupReason = $null
$keepDcrReason         = $null
$keepWorkspaceReason   = $null

# ── Inventory resources to delete ────────────────────────────────────────
Write-Host "Resources to be deleted:" -ForegroundColor Yellow

$resourcesToDelete = [System.Collections.Generic.List[hashtable]]::new()

# Metric Alert - listed and picked by name
$alertLookup = Invoke-LabLookup -Target "the metric alerts in '$platformRg'" -Lookup {
    Get-AzMetricAlertRuleV2 -ResourceGroupName $platformRg -ErrorAction Stop
}
if ($alertLookup.Failed) {
    $keepActionGroupReason = "metric alert '$alertRuleName' could not be looked up, and it may still use the action group"
}
elseif ($alertLookup.Value | Where-Object { $_.Name -eq $alertRuleName }) {
    $resourcesToDelete.Add(@{ Type = 'Alert'; Name = $alertRuleName })
    Write-Host "  - Metric Alert: $alertRuleName" -ForegroundColor Gray
}

# DCR Association on dev VM - the associations of the VM are listed and picked by name
$vmLookup = Invoke-LabLookup -Target "VM '$devVmName'" -Lookup {
    Get-AzVM -Name $devVmName -ResourceGroupName $devRgName -ErrorAction Stop
}
$devVm = $vmLookup.Value | Select-Object -First 1
if ($vmLookup.Failed) {
    $keepDcrReason = "VM '$devVmName' could not be looked up, and the rule may still be associated with it"
}
elseif ($devVm) {
    $devVmId = $devVm.Id
    $assocLookup = Invoke-LabLookup -Target "the data collection rule associations on '$devVmName'" -Lookup {
        Get-AzDataCollectionRuleAssociation -ResourceUri $devVmId -ErrorAction Stop
    }
    if ($assocLookup.Failed) {
        $keepDcrReason = "the associations on '$devVmName' could not be looked up, and the rule may still be associated with it"
    }
    elseif ($assocLookup.Value | Where-Object { $_.Name -eq $dcrAssocName }) {
        $resourcesToDelete.Add(@{ Type = 'DCRAssoc'; Name = $dcrAssocName; VmId = $devVmId })
        Write-Host "  - DCR Association: $dcrAssocName (on $devVmName)" -ForegroundColor Gray
    }
}

# Data Collection Rule
$dcrId = "/subscriptions/$subscriptionId/resourceGroups/$platformRg/providers/Microsoft.Insights/dataCollectionRules/$dcrName"
$dcrLookup = Invoke-LabLookup -Target "data collection rule '$dcrName'" -Lookup {
    Get-AzResource -ResourceId $dcrId -ErrorAction Stop
}
if ($dcrLookup.Failed) {
    $keepWorkspaceReason = "data collection rule '$dcrName' could not be looked up, and it may still send to the workspace"
}
elseif ($dcrLookup.Value) {
    $resourcesToDelete.Add(@{ Type = 'DCR'; Name = $dcrName })
    Write-Host "  - Data Collection Rule: $dcrName" -ForegroundColor Gray
}

# Action Group - listed and picked by name
$agLookup = Invoke-LabLookup -Target "the action groups in '$platformRg'" -Lookup {
    Get-AzActionGroup -ResourceGroupName $platformRg -ErrorAction Stop
}
if ($agLookup.Value | Where-Object { $_.Name -eq $actionGroupName }) {
    $resourcesToDelete.Add(@{ Type = 'ActionGroup'; Name = $actionGroupName })
    Write-Host "  - Action Group: $actionGroupName" -ForegroundColor Gray
}

# Storage Diagnostic Settings (scoped to blobServices/default) - listed and picked by name
$storageLookup = Invoke-LabLookup -Target "the storage accounts in '$platformRg'" -Lookup {
    Get-AzStorageAccount -ResourceGroupName $platformRg -ErrorAction Stop
}
$storageAcct = $storageLookup.Value | Select-Object -First 1
if ($storageLookup.Failed) {
    if (-not $keepWorkspaceReason) {
        $keepWorkspaceReason = "the storage accounts in '$platformRg' could not be looked up, and diagnostic setting '$diagSettingName' may still send to the workspace"
    }
}
elseif ($storageAcct) {
    $blobServiceId = "$($storageAcct.Id)/blobServices/default"
    $diagLookup = Invoke-LabLookup -Target "the diagnostic settings of '$($storageAcct.StorageAccountName)'" -Lookup {
        Get-AzDiagnosticSetting -ResourceId $blobServiceId -ErrorAction Stop
    }
    if ($diagLookup.Failed) {
        if (-not $keepWorkspaceReason) {
            $keepWorkspaceReason = "diagnostic setting '$diagSettingName' could not be looked up, and it may still send to the workspace"
        }
    }
    elseif ($diagLookup.Value | Where-Object { $_.Name -eq $diagSettingName }) {
        $resourcesToDelete.Add(@{ Type = 'StorageDiag'; Name = $diagSettingName; BlobServiceId = $blobServiceId })
        Write-Host "  - Storage Diagnostic Settings: $diagSettingName" -ForegroundColor Gray
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
    if ($PSCmdlet.ShouldProcess($r.Name, 'Remove Metric Alert')) {
        Write-Host "  Deleting Metric Alert: $($r.Name)..." -ForegroundColor Gray
        try {
            Remove-AzMetricAlertRuleV2 -ResourceGroupName $platformRg -Name $r.Name -ErrorAction Stop | Out-Null
            Write-Host "  ✓ Deleted" -ForegroundColor Green
        } catch {
            $script:cleanupFailures++
            $keepActionGroupReason = "metric alert '$($r.Name)' could not be deleted, and it may still use the action group"
            Write-Host "  [ERROR] Could not delete Metric Alert '$($r.Name)': $_" -ForegroundColor Red
        }
    }
}

# 2. DCR Association
foreach ($r in $resourcesToDelete | Where-Object { $_.Type -eq 'DCRAssoc' }) {
    if ($PSCmdlet.ShouldProcess($r.Name, 'Remove DCR Association')) {
        Write-Host "  Deleting DCR Association: $($r.Name)..." -ForegroundColor Gray
        try {
            Remove-AzDataCollectionRuleAssociation -ResourceUri $r.VmId -AssociationName $r.Name -ErrorAction Stop | Out-Null
            Write-Host "  ✓ Deleted" -ForegroundColor Green
        } catch {
            $script:cleanupFailures++
            $keepDcrReason = "association '$($r.Name)' could not be deleted, and it still ties the rule to '$devVmName'"
            Write-Host "  [ERROR] Could not delete DCR Association '$($r.Name)': $_" -ForegroundColor Red
        }
    }
}

# 3. Data Collection Rule
foreach ($r in $resourcesToDelete | Where-Object { $_.Type -eq 'DCR' }) {
    if ($keepDcrReason) {
        $keepWorkspaceReason = "data collection rule '$($r.Name)' was kept, and it still sends to the workspace"
        Write-Host "  [SKIP] Kept Data Collection Rule '$($r.Name)': $keepDcrReason." -ForegroundColor Yellow
        continue
    }
    if ($PSCmdlet.ShouldProcess($r.Name, 'Remove Data Collection Rule')) {
        Write-Host "  Deleting Data Collection Rule: $($r.Name)..." -ForegroundColor Gray
        try {
            $dcrResourceId = "/subscriptions/$subscriptionId/resourceGroups/$platformRg/providers/Microsoft.Insights/dataCollectionRules/$($r.Name)"
            Remove-AzResource -ResourceId $dcrResourceId -Force -ErrorAction Stop | Out-Null
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
    if ($PSCmdlet.ShouldProcess($r.Name, 'Remove Storage Diagnostic Settings')) {
        Write-Host "  Deleting Storage Diagnostic Settings: $($r.Name)..." -ForegroundColor Gray
        try {
            Remove-AzDiagnosticSetting -ResourceId $r.BlobServiceId -Name $r.Name -ErrorAction Stop | Out-Null
            Write-Host "  ✓ Deleted" -ForegroundColor Green
        } catch {
            $script:cleanupFailures++
            if (-not $keepWorkspaceReason) {
                $keepWorkspaceReason = "diagnostic setting '$($r.Name)' could not be deleted, and it still sends to the workspace"
            }
            Write-Host "  [ERROR] Could not delete Storage Diagnostic Settings '$($r.Name)': $_" -ForegroundColor Red
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
    $Host.SetShouldExit(1)
    exit 1
}
Write-Host "  Cleanup Complete" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  VMs, VNets, Storage Accounts were NOT deleted." -ForegroundColor Gray
Write-Host "  Remove the 'SkyCraft-Ops' dashboard manually in the Azure Portal." -ForegroundColor Gray
Write-Host "========================================`n" -ForegroundColor Cyan
