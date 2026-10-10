<#
.SYNOPSIS
    Removes Lab 3.1 Infrastructure Resources.

.DESCRIPTION
    Deletes the Resource Groups created by the lab.
    WARNING: This is a destructive operation.

    The resource groups are listed once and picked by name. A group that is not in the listing is
    reported as not found and is not a failure. A listing that fails (a 403, throttling, a
    transient ARM error) is reported as [ERROR] and counted, and no group is touched: the script
    cannot tell which of them still exist. A deletion that fails is reported as [ERROR] with the
    Azure error and counted, and the other groups are still deleted. If anything failed the script
    exits 1 (issue #290; it used to read every error as "It may not exist." and exit 0).

    Each non-zero exit is paired with $Host.SetShouldExit: a bare "exit 1" is dropped under
    "pwsh -File" for any script that declares #Requires -Modules for a module it has to
    auto-import, and the process would exit 0 with the failure still on screen (issue #104).

.PARAMETER Environment
    Target environment to clean (dev, prod, all). Default: 'all'
    'all' will remove Platform, Dev, and Prod RGs.

.PARAMETER Force
    Skips the confirmation prompt before deleting resources.

.EXAMPLE
    .\Remove-LabResource.ps1 -Environment all

.NOTES
    Project: SkyCraft
    Lab: 3.1 - Infrastructure as Code
    Author: Marcin Biszczanik
    Date: 2026-01-11
#>

#Requires -Version 7.0
#Requires -Modules Az.Accounts, Az.Resources

[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [ValidateSet('dev', 'prod', 'all')]
    [string]$Environment = 'all',

    [switch]$Force
)

$ErrorActionPreference = 'Stop'
if ($Force) { $ConfirmPreference = 'None' }

# Counts lookups that failed and groups that exist but could not be deleted. Absent groups are
# not failures.
$script:cleanupFailures = 0

# Whether a lookup's error says the object does not exist, rather than that the lookup failed.
# The one lookup below lists the resource groups in the subscription, so a missing group is an
# empty match, not an error: Get-AzResourceGroup -Name would report it as "Provided resource group
# does not exist.", which is not a recognised not-found shape (docs/powershell-standards.md rule 3).
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

Write-Host "=== Lab 3.1 Cleanup Script ===" -ForegroundColor Cyan

$project = 'skycraft'
$locationShortCode = 'swc'

$groupsToRemove = @()

if ($Environment -eq 'dev' -or $Environment -eq 'all') {
    $groupsToRemove += "dev-$project-$locationShortCode-rg"
}
if ($Environment -eq 'prod' -or $Environment -eq 'all') {
    $groupsToRemove += "prod-$project-$locationShortCode-rg"
}
if ($Environment -eq 'all') {
    $groupsToRemove += "platform-$project-$locationShortCode-rg"
}

if ($groupsToRemove.Count -eq 0) {
    Write-Host "No groups selected." -ForegroundColor Yellow
    exit
}

Write-Host "The following Resource Groups will be DELETED:" -ForegroundColor Red
$groupsToRemove | ForEach-Object { Write-Host " - $_" }

# Listed once and picked by name, so a missing group is an empty match rather than an error to
# interpret. If the listing fails, no group is touched: the run exits 1 and a rerun picks them up.
$rgLookup = Invoke-LabLookup -Target 'the resource groups in the subscription' -Lookup {
    Get-AzResourceGroup -ErrorAction Stop
}

if (-not $rgLookup.Failed) {
    foreach ($rgName in $groupsToRemove) {
        if (-not ($rgLookup.Value | Where-Object { $_.ResourceGroupName -eq $rgName })) {
            Write-Host "[INFO] '$rgName' not found - nothing to delete." -ForegroundColor Gray
            continue
        }

        if ($PSCmdlet.ShouldProcess($rgName, 'Remove resource group')) {
            Write-Host "Deleting '$rgName'..." -ForegroundColor Yellow
            try {
                Remove-AzResourceGroup -Name $rgName -Force -ErrorAction Stop | Out-Null
                Write-Host "[SUCCESS] Deleted '$rgName'." -ForegroundColor Green
            }
            catch {
                $script:cleanupFailures++
                Write-Host "[ERROR] Could not delete '$rgName': $_" -ForegroundColor Red
            }
        }
    }
}

if ($script:cleanupFailures -gt 0) {
    Write-Host "`nCleanup finished with $($script:cleanupFailures) failure(s). See the [ERROR] lines above." -ForegroundColor Red
    $Host.SetShouldExit(1)
    exit 1
}

Write-Host "`nCleanup Complete." -ForegroundColor Cyan
