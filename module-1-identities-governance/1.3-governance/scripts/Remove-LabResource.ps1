<#
.SYNOPSIS
    Cleans up resources created in Lab 1.3 (Locks, Policies, Budgets and the Advisor alert).

.DESCRIPTION
    Removes, in this order:
    1. The resource locks on the production and platform resource groups
       (lock-no-delete-prod, lock-no-delete-platform).
    2. The three subscription-level policy assignments.
    3. The two budgets: SkyCraft-Monthly-Budget on the subscription (step 1.3.14) and
       SkyCraft-Prod-Monthly on prod-skycraft-swc-rg (step 1.3.16).
    4. The Advisor alert Advisor-Cost-Recommendations (step 1.3.21), an activity log alert in
       prod-skycraft-swc-rg, and then its action group skycraft-advisor-ag in the same group.
       An action group created before issue #225 renamed it is called prod-skycraft-swc-rg,
       like the group it lives in; it is removed too.

    Budgets and the Advisor alert are created in the Portal only: neither the Bicep deployment
    nor Invoke-LabGovernance.ps1 creates them. They are removed here all the same, whichever path
    built the rest. The objects in prod-skycraft-swc-rg are deleted here rather than left for the
    group's own deletion: Lab 1.2 owns that group and later labs keep using it, so it outlives
    this cleanup, and the next Lab 1.3 run would find a budget and an alert with the names it is
    told to create (issue #252). They are deleted after the locks, because the CanNotDelete lock
    on the group blocks deleting anything inside it.

    Every step continues on error, so a single stuck object does not strand the rest. A lookup
    that fails (a 403, throttling, a transient ARM error) or a deletion that fails is reported as
    [ERROR] and counted; if anything failed the script exits 1. An object that does not exist is
    not a failure: only a lookup that succeeds and does not find it, or a getter that reports it
    as not found, means "absent" - Test-LabNotFoundError tells the two apart (issue #252, as #238
    did for Lab 5.2).

    Each non-zero exit is paired with $Host.SetShouldExit: a bare "exit 1" is dropped under
    "pwsh -File" for any script that declares #Requires -Modules for a module it has to
    auto-import, and the process would exit 0 with the failure still on screen (issue #104).

.PARAMETER Force
    Skip confirmation prompt.

.EXAMPLE
    .\Remove-LabResource.ps1
    Interactive cleanup.

.EXAMPLE
    .\Remove-LabResource.ps1 -WhatIf
    Lists what would be removed, without removing anything.

.NOTES
    Project: SkyCraft
    Lab: 1.3 - Governance
#>

#Requires -Version 7.0
#Requires -Modules Az.Accounts, Az.Resources, Az.Billing, Az.Monitor

[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [switch]$Force
)

$ErrorActionPreference = "Stop"
if ($Force) { $ConfirmPreference = 'None' }

$prodRg = "prod-skycraft-swc-rg"

# Counts lookups that failed and objects that exist but could not be removed. Absent objects
# are not failures.
$script:cleanupFailures = 0

# Whether a lookup's error says the object (or the resource group holding it) does not exist,
# rather than that the lookup failed. The locks, budgets, alerts and action groups are found by
# listing their scope, so for them a not-found error means the resource group is gone:
# "Resource group '<rg>' could not be found.", code ResourceGroupNotFound. Get-AzPolicyAssignment
# reads one assignment by name and reports a missing one as PolicyAssignmentNotFound. The status
# travels in Response.StatusCode (Get-AzConsumptionBudget), ResponseStatusCode (the generated
# Az.Monitor and policy cmdlets) or HttpStatus (Get-AzResourceLock). A missing subscription is a
# 404 too, but it means the context is wrong, not that the object is gone, so it never reads as
# "absent".
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
        foreach ($status in @($exception.Response.StatusCode, $exception.ResponseStatusCode, $exception.Status, $exception.HttpStatus)) {
            if ("$status" -in @('404', 'NotFound')) { $status404 = $true }
        }
    }
    $text = $evidence -join "`n"

    if ($text -match 'SubscriptionNotFound|subscription .{0,80}(could not be|was not) found') { return $false }
    if ($status404) { return $true }
    return $text -match '\b(Resource(Group)?|PolicyAssignment)NotFound\b|was not found|Resource group .{0,100}could not be found|invalid status code ''NotFound''|\b404 \(Not Found\)'
}

# Runs one lookup with -ErrorAction Stop inside $Lookup, and returns what it found:
#   Value     the lookup's output, as an array - empty when the object is absent
#   NotFound  the getter reported the object as not found (Test-LabNotFoundError)
#   Failed    the lookup failed any other way: it is reported as [ERROR] and counted, because it
#             cannot tell whether the object is gone
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

Write-Host "=== Lab 1.3: Cleanup Resources ===" -ForegroundColor Cyan -BackgroundColor Black

# Check Azure Context
$context = Get-AzContext
if (-not $context) {
    Write-Host "Not logged in. Connecting..." -ForegroundColor Yellow
    # Connect-AzAccount returns a profile, not a context; read the context it set.
    Connect-AzAccount | Out-Null
    $context = Get-AzContext
}
$subId = $context.Subscription.Id
Write-Host "Using Subscription: $($context.Subscription.Name)" -ForegroundColor Green

# 1. Remove Locks
Write-Host "`n1. Removing Resource Locks..." -ForegroundColor Cyan
$locks = @(
    @{ RG = $prodRg; Name = "lock-no-delete-prod" },
    @{ RG = "platform-skycraft-swc-rg"; Name = "lock-no-delete-platform" }
)
$lockRemoved = $false

foreach ($lock in $locks) {
    # The group's locks are listed and this one picked by name, so a missing lock is an empty
    # listing rather than an error to interpret.
    $lockLookup = Invoke-LabLookup -Target "lock $($lock.Name) on $($lock.RG)" -Lookup {
        Get-AzResourceLock -ResourceGroupName $lock.RG -ErrorAction Stop | Where-Object { $_.Name -eq $lock.Name }
    }
    if ($lockLookup.Failed) { continue }
    if ($lockLookup.Value.Count -eq 0) {
        Write-Host "  -> [INFO] Lock $($lock.Name) not found." -ForegroundColor Gray
        continue
    }
    if ($PSCmdlet.ShouldProcess("$($lock.Name) on $($lock.RG)", 'Remove resource lock')) {
        try {
            Remove-AzResourceLock -ResourceGroupName $lock.RG -LockName $lock.Name -Force -ErrorAction Stop
            $lockRemoved = $true
            Write-Host "  -> [SUCCESS] Removed lock: $($lock.Name)" -ForegroundColor Green
        }
        catch {
            $script:cleanupFailures++
            Write-Host "  -> [ERROR] Failed to remove lock $($lock.Name): $_" -ForegroundColor Red
        }
    }
}

# ARM lock removal propagates asynchronously - the deletes in step 4 and downstream cleanup
# (Cleanup Lab 2.3) act on the now-unlocked scope; without this wait they race the propagation
# window and fail with a 'scope is locked' error. Nothing to wait for when no lock was removed.
if ($lockRemoved) {
    Write-Host "`n  Waiting 45 seconds for ARM lock removal to propagate..." -ForegroundColor Gray
    Start-Sleep -Seconds 45
}

# 2. Remove Policies
Write-Host "`n2. Removing Policy Assignments..." -ForegroundColor Cyan
$policies = @("Require-Environment-Tag-RG", "Enforce-Project-Tag", "Restrict-Azure-Regions")

foreach ($policy in $policies) {
    $policyLookup = Invoke-LabLookup -Target "policy assignment $policy" -Lookup {
        Get-AzPolicyAssignment -Name $policy -Scope "/subscriptions/$subId" -ErrorAction Stop
    }
    if ($policyLookup.Failed) { continue }
    if ($policyLookup.Value.Count -eq 0) {
        Write-Host "  -> [INFO] Policy $policy not found." -ForegroundColor Gray
        continue
    }
    if ($PSCmdlet.ShouldProcess("$policy on /subscriptions/$subId", 'Remove policy assignment')) {
        try {
            Remove-AzPolicyAssignment -Name $policy -Scope "/subscriptions/$subId" -ErrorAction Stop
            Write-Host "  -> [SUCCESS] Removed policy: $policy" -ForegroundColor Green
        }
        catch {
            $script:cleanupFailures++
            Write-Host "  -> [ERROR] Failed to remove policy ${policy}: $_" -ForegroundColor Red
        }
    }
}

# 3. Remove Budgets (Get-AzConsumptionBudget and Remove-AzConsumptionBudget ship in Az.Billing)
Write-Host "`n3. Removing Budgets..." -ForegroundColor Cyan
$budgets = @(
    @{ Name = "SkyCraft-Monthly-Budget"; RG = $null; Scope = "the subscription" },
    @{ Name = "SkyCraft-Prod-Monthly"; RG = $prodRg; Scope = $prodRg }
)

foreach ($budget in $budgets) {
    # Without -ResourceGroupName both cmdlets work on the subscription's budgets.
    $budgetScope = @{}
    if ($budget.RG) { $budgetScope.ResourceGroupName = $budget.RG }
    $budgetLookup = Invoke-LabLookup -Target "budget $($budget.Name) on $($budget.Scope)" -Lookup {
        Get-AzConsumptionBudget @budgetScope -ErrorAction Stop | Where-Object { $_.Name -eq $budget.Name }
    }
    if ($budgetLookup.Failed) { continue }
    if ($budgetLookup.Value.Count -eq 0) {
        Write-Host "  -> [INFO] Budget $($budget.Name) not found." -ForegroundColor Gray
        continue
    }
    if ($PSCmdlet.ShouldProcess("$($budget.Name) on $($budget.Scope)", 'Remove budget')) {
        try {
            Remove-AzConsumptionBudget -Name $budget.Name @budgetScope -ErrorAction Stop | Out-Null
            Write-Host "  -> [SUCCESS] Removed budget: $($budget.Name)" -ForegroundColor Green
        }
        catch {
            $script:cleanupFailures++
            Write-Host "  -> [ERROR] Failed to remove budget $($budget.Name): $_" -ForegroundColor Red
        }
    }
}

# 4. Remove the Advisor alert, then its action group. A Portal "Advisor alert" is an activity
#    log alert (Microsoft.Insights/activityLogAlerts); both live in prod-skycraft-swc-rg.
Write-Host "`n4. Removing the Advisor Alert and its Action Group..." -ForegroundColor Cyan
$advisorAlertName = "Advisor-Cost-Recommendations"
# skycraft-advisor-ag is the name step 1.3.21 gives; before issue #225 the step named the action
# group like its resource group, so a subscription that ran the older guide holds that one.
$actionGroupNames = @("skycraft-advisor-ag", "prod-skycraft-swc-rg")

$alertLookup = Invoke-LabLookup -Target "Advisor alert $advisorAlertName in $prodRg" -Lookup {
    Get-AzActivityLogAlert -ResourceGroupName $prodRg -ErrorAction Stop | Where-Object { $_.Name -eq $advisorAlertName }
}
if (-not $alertLookup.Failed) {
    if ($alertLookup.Value.Count -eq 0) {
        Write-Host "  -> [INFO] Advisor alert $advisorAlertName not found." -ForegroundColor Gray
    }
    elseif ($PSCmdlet.ShouldProcess("$advisorAlertName in $prodRg", 'Remove Advisor alert')) {
        try {
            Remove-AzActivityLogAlert -ResourceGroupName $prodRg -Name $advisorAlertName -ErrorAction Stop | Out-Null
            Write-Host "  -> [SUCCESS] Removed Advisor alert: $advisorAlertName" -ForegroundColor Green
        }
        catch {
            $script:cleanupFailures++
            Write-Host "  -> [ERROR] Failed to remove Advisor alert ${advisorAlertName}: $_" -ForegroundColor Red
        }
    }
}

$actionGroupLookup = Invoke-LabLookup -Target "the action groups in $prodRg" -Lookup {
    Get-AzActionGroup -ResourceGroupName $prodRg -ErrorAction Stop | Where-Object { $_.Name -in $actionGroupNames }
}
if (-not $actionGroupLookup.Failed) {
    if ($actionGroupLookup.Value.Count -eq 0) {
        Write-Host "  -> [INFO] Action group $($actionGroupNames[0]) not found." -ForegroundColor Gray
    }
    foreach ($actionGroup in $actionGroupLookup.Value) {
        if (-not $PSCmdlet.ShouldProcess("$($actionGroup.Name) in $prodRg", 'Remove action group')) { continue }
        try {
            Remove-AzActionGroup -ResourceGroupName $prodRg -Name $actionGroup.Name -ErrorAction Stop | Out-Null
            Write-Host "  -> [SUCCESS] Removed action group: $($actionGroup.Name)" -ForegroundColor Green
        }
        catch {
            $script:cleanupFailures++
            Write-Host "  -> [ERROR] Failed to remove action group $($actionGroup.Name): $_" -ForegroundColor Red
        }
    }
}

if ($script:cleanupFailures -gt 0) {
    Write-Host "`nCleanup finished with $($script:cleanupFailures) failure(s). See the [ERROR] lines above." -ForegroundColor Red
    $Host.SetShouldExit(1)
    exit 1
}

Write-Host "`nCleanup complete." -ForegroundColor Green
