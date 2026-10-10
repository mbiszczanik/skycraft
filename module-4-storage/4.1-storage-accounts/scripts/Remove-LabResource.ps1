<#
.SYNOPSIS
    Removes Lab 4.1 - Storage Account resources.

.DESCRIPTION
    Deletes storage accounts created in Lab 4.1. Includes confirmation
    prompts unless -Force is specified.

    Every account is handled on its own, so one stuck account does not strand the rest. A lookup
    that fails (a 403, throttling, a transient ARM error) or a deletion that fails is reported and
    counted as failed; if anything failed the script exits 1. An account that does not exist is
    skipped, not a failure: only a lookup that succeeds and does not find it, or a getter that
    reports it as not found, means "absent" - Test-LabNotFoundError tells the two apart (issue
    #290, as #255 did for Labs 1.2-2.3).

    Each non-zero exit is paired with $Host.SetShouldExit: a bare "exit 1" is dropped under
    "pwsh -File" for any script that declares #Requires -Modules for a module it has to
    auto-import, and the process would exit 0 with the failure still on screen (issue #104).

.PARAMETER Environment
    Target environment to clean up: dev, prod, platform, or all.

.PARAMETER Force
    Skip confirmation prompts.

.EXAMPLE
    .\Remove-LabResource.ps1 -Environment dev
    Removes development storage account with confirmation.

.EXAMPLE
    .\Remove-LabResource.ps1 -Environment all -Force
    Removes all storage accounts without confirmation.

.NOTES
    Project: SkyCraft
    Lab: 4.1 - Storage Accounts
    Version: 1.0.0
    Date: 2026-02-05
#>

#Requires -Version 7.0
#Requires -Modules Az.Accounts, Az.Storage

[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory = $false)]
    [ValidateSet('dev', 'prod', 'platform', 'all')]
    [string]$Environment = 'all',

    [Parameter(Mandatory = $false)]
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
if ($Force) { $ConfirmPreference = 'None' }

# Counts lookups that failed and accounts that exist but could not be deleted - the "Failed" line
# of the summary. Absent accounts are skipped, not failures.
$script:cleanupFailures = 0

# Whether a lookup's error says the account does not exist, rather than that the lookup failed.
# Get-AzStorageAccount reports a missing account as an ARM 404: "The Resource
# 'Microsoft.Storage/storageAccounts/<name>' under resource group '<rg>' was not found.", code
# ResourceNotFound; when the group is gone as well, "Resource group '<rg>' could not be found.",
# code ResourceGroupNotFound; with no error body, "Operation returned an invalid status code
# 'NotFound'". The Azure.Core clients say "Status: 404 (Not Found)". A missing subscription is a
# 404 too, but it means the context is wrong, not that the account is gone, so it never reads as
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
#   Value     the lookup's output, as an array - empty when the account is absent
#   NotFound  the getter reported the account as not found (Test-LabNotFoundError)
#   Failed    the lookup failed any other way: it is reported as [ERROR] and counted, because it
#             cannot tell whether the account is gone, and the caller leaves the account alone
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

Write-Host "=== Lab 4.1: Remove Storage Accounts ===" -ForegroundColor Cyan
Write-Host ""

# Storage account configurations
$storageConfigs = @{
    platform = @{
        Name          = 'platformskycraftswcsa'
        ResourceGroup = 'platform-skycraft-swc-rg'
        DisplayName   = 'Platform'
    }
    dev      = @{
        Name          = 'devskycraftswcsa'
        ResourceGroup = 'dev-skycraft-swc-rg'
        DisplayName   = 'Development'
    }
    prod     = @{
        Name          = 'prodskycraftswcsa'
        ResourceGroup = 'prod-skycraft-swc-rg'
        DisplayName   = 'Production'
    }
}

# Determine which environments to clean
$envsToClean = if ($Environment -eq 'all') {
    @('platform', 'dev', 'prod')
}
else {
    @($Environment)
}

# Display what will be deleted
Write-Host "--- Resources to Delete ---" -ForegroundColor Yellow
foreach ($env in $envsToClean) {
    $config = $storageConfigs[$env]
    Write-Host "  $($config.DisplayName): $($config.Name)" -ForegroundColor White
}
Write-Host ""

# Warning
Write-Host "[WARNING] This action will permanently delete the above storage accounts!" -ForegroundColor Yellow
Write-Host "          All data in these accounts will be lost." -ForegroundColor Yellow
Write-Host ""

# Delete storage accounts
Write-Host ""
Write-Host "--- Deleting Storage Accounts ---" -ForegroundColor Yellow

$deleted = 0
$skipped = 0

foreach ($env in $envsToClean) {
    $config = $storageConfigs[$env]

    Write-Host "  $($config.DisplayName) ($($config.Name))..." -ForegroundColor White

    # Check if exists. A lookup that fails is not "not found": the account is left alone and the
    # failure is counted.
    $lookup = Invoke-LabLookup -Target "storage account $($config.Name)" -Lookup {
        Get-AzStorageAccount -ResourceGroupName $config.ResourceGroup -Name $config.Name -ErrorAction Stop
    }
    if ($lookup.Failed) {
        Write-Host "    FAILED (lookup)" -ForegroundColor Red
        continue
    }
    if (-not $lookup.Value) {
        Write-Host "    SKIPPED (not found)" -ForegroundColor Gray
        $skipped++
        continue
    }

    # Delete
    if ($PSCmdlet.ShouldProcess($config.Name, "Delete storage account")) {
        try {
            Remove-AzStorageAccount `
                -ResourceGroupName $config.ResourceGroup `
                -Name $config.Name `
                -Force `
                -ErrorAction Stop

            Write-Host "    DELETED" -ForegroundColor Green
            $deleted++
        }
        catch {
            Write-Host "    FAILED" -ForegroundColor Red
            Write-Host "    [ERROR] $($_.Exception.Message)" -ForegroundColor Red
            $script:cleanupFailures++
        }
    }
}

# Summary
$failed = $script:cleanupFailures
Write-Host ""
Write-Host "=== Cleanup Summary ===" -ForegroundColor Cyan
Write-Host "  Deleted: $deleted" -ForegroundColor Green
Write-Host "  Skipped: $skipped" -ForegroundColor Gray
Write-Host "  Failed:  $failed" -ForegroundColor $(if ($failed -gt 0) { 'Red' } else { 'Green' })
Write-Host ""

if ($failed -gt 0) {
    Write-Host "Some storage accounts could not be looked up or deleted. Review the [ERROR] lines above." -ForegroundColor Red
    $Host.SetShouldExit(1)
    exit 1
}

Write-Host "Cleanup complete." -ForegroundColor Green
