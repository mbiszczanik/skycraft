<#
.SYNOPSIS
    Cleans up resources created in Lab 1.2 (Resource Groups and Assignments).

.DESCRIPTION
    Deletes the 'dev', 'prod', and 'platform' resource groups.
    Removes the subscription-level Owner assignment for Malfurion Stormrage.
    Prompts for confirmation unless -Force is specified.

    The Owner assignment is read and removed through the Azure Resource Manager role assignments
    API (tools/LabCommon.psm1), not through Get-AzRoleAssignment / Remove-AzRoleAssignment, which
    call Microsoft Graph (issue #397). Finding Malfurion by his userPrincipalName still needs
    Microsoft Graph, through the Az sign-in's Graph token (Get-AzADUser). Where the tenant asks
    for interaction before it issues that token, sign in with
    'Connect-AzAccount -AuthScope MicrosoftGraphEndpointResourceId'; a lookup that fails is an
    [ERROR] that names that sign-in, and the resource groups are still deleted.

    Every step continues on error, so one stuck object does not strand the rest. A lookup that
    fails (a 403, throttling, a transient ARM error) or a deletion that fails is reported as
    [ERROR] and counted; if anything failed the script exits 1. An object that does not exist is
    not a failure: only a lookup that succeeds and does not find it, or a getter that reports it
    as not found, means "absent" - Test-LabNotFoundError tells the two apart (issue #255, as #238
    did for Lab 5.2).

    Every exit goes through Exit-Lab (tools/LabCommon.psm1): 1 when anything failed, 0
    otherwise. Run as "pwsh -File", where #Requires -Modules would drop a bare "exit 1"
    (issue #104), it also sets the process exit code; run at a prompt or by another script,
    it leaves the session open and the code in $LASTEXITCODE (issue #257).

.PARAMETER Force
    Skip confirmation prompt.

.EXAMPLE
    .\Remove-LabResource.ps1
    Interactive cleanup.

.NOTES
    Project: SkyCraft
    Lab: 1.2 - RBAC
#>

#Requires -Version 7.0
#Requires -Modules Az.Accounts, Az.Resources

[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [switch]$Force
)

$ErrorActionPreference = "Stop"
# Exit-Lab ends the script with exit code 0 or 1 and leaves an interactive session open (#257).
# The module's role assignment helpers use the ARM API, not Microsoft Graph (#397).
Import-Module (Join-Path $PSScriptRoot '../../../tools/LabCommon.psm1') -Force -Verbose:$false
if ($Force) { $ConfirmPreference = 'None' }

# Counts lookups that failed and objects that exist but could not be removed. Absent objects
# are not failures.
$script:cleanupFailures = 0

# Whether a lookup's error says the object does not exist, rather than that the lookup failed.
# Both lookups below are listings - the role assignments at the subscription scope and the
# resource groups in the subscription - so a missing object is an empty listing, not an error.
# The classification still covers the shapes ARM answers a missing object with: "The Resource
# '<type>/<name>' under resource group '<rg>' was not found." (code ResourceNotFound), "Resource
# group '<rg>' could not be found." (ResourceGroupNotFound), "Operation returned an invalid status
# code 'NotFound'" and Azure.Core's "Status: 404 (Not Found)". A missing subscription is a 404
# too, but it means the context is wrong, not that the object is gone, so it never reads as
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

Write-Host "=== Lab 1.2: Cleanup Resources ===" -ForegroundColor Cyan -BackgroundColor Black

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


Write-Host "`n1. Removing Subscription-Level Role Assignment (Owner)..." -ForegroundColor Cyan
# Malfurion is found in Entra ID by his userPrincipalName prefix (the domain varies), through the
# Az sign-in's Graph token - the one Microsoft Graph call left in this script (issue #397). A
# lookup that fails is counted and names the sign-in that provides Graph; a directory without him
# leaves no assignment this script can attribute to him.
$subscriptionScope = "/subscriptions/$subId"
$userLookup = Invoke-LabLookup -Target 'Malfurion in Entra ID' -Lookup {
    Get-AzADUser -Filter "startsWith(userPrincipalName,'malfurion.stormrage@')" -ErrorAction Stop
}
$malfurionId = $null
if ($userLookup.Failed) {
    Write-Host "     $(Get-LabGraphSignInHint -Client Az)" -ForegroundColor Gray
}
else {
    $users = @($userLookup.Value | Where-Object { $_ })
    if ($users.Count -gt 1) {
        $script:cleanupFailures++
        Write-Host "  -> [ERROR] $($users.Count) users match malfurion.stormrage@*; removing no Owner assignment. Remove the right one in the Portal (Subscription > Access control (IAM))." -ForegroundColor Red
    }
    elseif ($users.Count -eq 0) {
        Write-Host "  -> [INFO] Malfurion not found in Entra ID; no Owner assignment of his to remove." -ForegroundColor Gray
    }
    else {
        $malfurionId = [string]$users[0].Id
    }
}

if ($malfurionId) {
    # His assignments, read through the ARM role assignments API rather than Get-AzRoleAssignment,
    # which resolves every principal through Microsoft Graph (issue #397).
    $assignmentLookup = Invoke-LabLookup -Target "the role assignments on $subscriptionScope" -Lookup {
        Get-LabArmRoleAssignment -Scope $subscriptionScope -PrincipalId $malfurionId
    }
    if (-not $assignmentLookup.Failed) {
        # Only the assignment made at the subscription itself: the listing also returns assignments
        # inherited from a management group, which this lab did not create and cannot remove here.
        # ARM holds one assignment per principal, role and scope, so the first match is the one.
        $ownerRoleId = Get-LabBuiltInRoleId -Name 'Owner'
        $malfurion = $assignmentLookup.Value |
            Where-Object { ($_.RoleDefinitionId -eq $ownerRoleId) -and ($_.Scope -eq $subscriptionScope) } |
            Select-Object -First 1

        if (-not $malfurion) {
            Write-Host "  -> [INFO] Assignment not found." -ForegroundColor Gray
        }
        elseif ($PSCmdlet.ShouldProcess($subscriptionScope, "Remove Owner role assignment for Malfurion")) {
            try {
                Remove-LabArmRoleAssignment -Id $malfurion.RoleAssignmentId
                Write-Host "  -> [SUCCESS] Removed Owner role for Malfurion." -ForegroundColor Green
            }
            catch {
                $script:cleanupFailures++
                Write-Host "  -> [ERROR] Failed to remove role: $_" -ForegroundColor Red
            }
        }
    }
}

Write-Host "`n2. Deleting Resource Groups..." -ForegroundColor Cyan
$rgs = @("dev-skycraft-swc-rg", "prod-skycraft-swc-rg", "platform-skycraft-swc-rg")

# The groups are listed once and picked by name, so a missing group is an empty match rather than
# an error to interpret. If the listing fails, no group is touched: the run exits 1 and a rerun
# picks them up.
$rgLookup = Invoke-LabLookup -Target 'the resource groups in the subscription' -Lookup {
    Get-AzResourceGroup -ErrorAction Stop
}
if (-not $rgLookup.Failed) {
    foreach ($rg in $rgs) {
        if ($rgLookup.Value | Where-Object { $_.ResourceGroupName -eq $rg }) {
            if ($PSCmdlet.ShouldProcess($rg, "Remove resource group")) {
                Write-Host "  Deleting $rg... (this may take a moment)" -ForegroundColor Yellow
                try {
                    Remove-AzResourceGroup -Name $rg -Force -ErrorAction Stop
                    Write-Host "  -> [SUCCESS] Deleted $rg" -ForegroundColor Green
                }
                catch {
                    $script:cleanupFailures++
                    Write-Host "  -> [ERROR] Failed to delete $($rg): $_" -ForegroundColor Red
                }
            }
        }
        else {
            Write-Host "  -> [INFO] $rg not found." -ForegroundColor Gray
        }
    }
}

if ($script:cleanupFailures -gt 0) {
    Write-Host "`nCleanup finished with $($script:cleanupFailures) failure(s). See the [ERROR] lines above." -ForegroundColor Red
    Exit-Lab -FailureCount 1
}

Write-Host "`nCleanup complete." -ForegroundColor Green
Exit-Lab -FailureCount 0
