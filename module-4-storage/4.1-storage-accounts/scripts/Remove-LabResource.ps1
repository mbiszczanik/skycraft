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

    Lab 1.3's CanNotDelete lock on the platform and prod groups refuses deleting their accounts
    (ScopeLocked, issue #372). Those deletes run inside Invoke-LabWithoutLock
    (tools/LabCommon.psm1), which lifts the lock, runs them and puts it back with the same name,
    level and notes, also when one fails. A lock it cannot read, lift or restore is an [ERROR]
    and counted; any other lock is left alone.

    Deleting an account does not delete its diagnostic settings, and they re-attach to the next
    account created with the same id (issue #373: Lab 5.1's 'skycraft-storage-diag' on the platform
    account's blob service). Before an account is deleted, every diagnostic setting on the account
    and on its blob, file, queue and table services is listed and removed, whatever its name. A
    listing or a removal that fails is counted, and the account is left in place, because deleting
    it would orphan the setting for good.

    Every exit goes through Exit-Lab (tools/LabCommon.psm1): 1 when anything failed, 0
    otherwise. Run as "pwsh -File", where #Requires -Modules would drop a bare "exit 1"
    (issue #104), it also sets the process exit code; run at a prompt or by another script,
    it leaves the session open and the code in $LASTEXITCODE (issue #257).

.PARAMETER Environment
    Target environment to clean up: dev, prod, platform, or all.

.PARAMETER PlatformSaName
    Platform storage account name. Default: platformskycraftswcsa. Pass the name given to
    Deploy-Bicep.ps1.

.PARAMETER DevSaName
    Development storage account name. Default: devskycraftswcsa.

.PARAMETER ProdSaName
    Production storage account name. Default: prodskycraftswcsa.

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
#Requires -Modules Az.Accounts, Az.Storage, Az.Monitor

[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory = $false)]
    [ValidateSet('dev', 'prod', 'platform', 'all')]
    [string]$Environment = 'all',

    [Parameter(Mandatory = $false)]
    [ValidatePattern('^[a-z0-9]{3,24}$')]
    [string]$PlatformSaName = 'platformskycraftswcsa',

    [Parameter(Mandatory = $false)]
    [ValidatePattern('^[a-z0-9]{3,24}$')]
    [string]$DevSaName = 'devskycraftswcsa',

    [Parameter(Mandatory = $false)]
    [ValidatePattern('^[a-z0-9]{3,24}$')]
    [string]$ProdSaName = 'prodskycraftswcsa',

    [Parameter(Mandatory = $false)]
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
# Exit-Lab ends the script with exit code 0 or 1 and leaves an interactive session open (#257).
Import-Module (Join-Path $PSScriptRoot '../../../tools/LabCommon.psm1') -Force -Verbose:$false
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

# Removes every diagnostic setting on each of $ResourceId, whatever its name, so a recreated
# resource with the same id does not inherit one (#373). Returns $false when a listing or a
# removal failed (both are counted): the caller keeps the resource, since deleting it would leave
# the setting behind for good. A listing that reports the resource not found has nothing to remove.
function Remove-LabDiagnosticSetting {
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$ResourceId
    )

    $clean = $true
    foreach ($id in $ResourceId) {
        $shortId = ($id -split '/providers/')[-1]
        $lookup = Invoke-LabLookup -Target "the diagnostic settings of $shortId" -Lookup {
            Get-AzDiagnosticSetting -ResourceId $id -ErrorAction Stop
        }
        if ($lookup.Failed) { $clean = $false; continue }
        foreach ($setting in @($lookup.Value | Where-Object { $_ })) {
            if (-not $PSCmdlet.ShouldProcess("$shortId/$($setting.Name)", 'Remove diagnostic setting')) { continue }
            try {
                Remove-AzDiagnosticSetting -ResourceId $id -Name $setting.Name -ErrorAction Stop | Out-Null
                Write-Host "    Removed diagnostic setting '$($setting.Name)' on $shortId" -ForegroundColor Gray
            }
            catch {
                $script:cleanupFailures++
                $clean = $false
                Write-Host "    [ERROR] Could not remove diagnostic setting '$($setting.Name)' on $($shortId): $_" -ForegroundColor Red
            }
        }
    }
    return $clean
}

Write-Host "=== Lab 4.1: Remove Storage Accounts ===" -ForegroundColor Cyan
Write-Host ""

# Storage account configurations
$storageConfigs = @{
    platform = @{
        Name          = $PlatformSaName
        ResourceGroup = 'platform-skycraft-swc-rg'
        DisplayName   = 'Platform'
    }
    dev      = @{
        Name          = $DevSaName
        ResourceGroup = 'dev-skycraft-swc-rg'
        DisplayName   = 'Development'
    }
    prod     = @{
        Name          = $ProdSaName
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

$script:deleted = 0
$skipped = 0
$found = [System.Collections.Generic.List[hashtable]]::new()
$accountIds = @{}   # account name -> resource id, for the diagnostic settings

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
    Write-Host "    FOUND" -ForegroundColor White
    $accountIds[$config.Name] = "$(@($lookup.Value)[0].Id)"
    $found.Add($config)
}

# Lab 1.3's CanNotDelete locks on the platform and prod groups refuse these deletes (ScopeLocked);
# Invoke-LabWithoutLock lifts them for the deletes and puts them back (#372).
if ($found.Count -gt 0) {
    $lockFailures = Invoke-LabWithoutLock -ResourceGroupName @($found | ForEach-Object { $_.ResourceGroup }) -WhatIf:$WhatIfPreference -Action {
        foreach ($config in $found) {
            if ($PSCmdlet.ShouldProcess($config.Name, "Delete storage account")) {
                Write-Host "  $($config.DisplayName) ($($config.Name))..." -ForegroundColor White
                # The account's diagnostic settings go first (#373); one that cannot be listed or
                # removed keeps the account, and the failure is already counted.
                $accountId = $accountIds[$config.Name]
                $diagIds = @($accountId) + @('blobServices', 'fileServices', 'queueServices', 'tableServices' | ForEach-Object { "$accountId/$_/default" })
                if (-not (Remove-LabDiagnosticSetting -ResourceId $diagIds)) {
                    Write-Host "    FAILED (diagnostic settings)" -ForegroundColor Red
                    continue
                }
                try {
                    Remove-AzStorageAccount `
                        -ResourceGroupName $config.ResourceGroup `
                        -Name $config.Name `
                        -Force `
                        -ErrorAction Stop

                    Write-Host "    DELETED" -ForegroundColor Green
                    $script:deleted++
                }
                catch {
                    Write-Host "    FAILED" -ForegroundColor Red
                    Write-Host "    [ERROR] $($_.Exception.Message)" -ForegroundColor Red
                    $script:cleanupFailures++
                }
            }
        }
    }
    $script:cleanupFailures += $lockFailures
}

# Summary
$failed = $script:cleanupFailures
Write-Host ""
Write-Host "=== Cleanup Summary ===" -ForegroundColor Cyan
Write-Host "  Deleted: $script:deleted" -ForegroundColor Green
Write-Host "  Skipped: $skipped" -ForegroundColor Gray
Write-Host "  Failed:  $failed" -ForegroundColor $(if ($failed -gt 0) { 'Red' } else { 'Green' })
Write-Host ""

if ($failed -gt 0) {
    Write-Host "Some storage accounts could not be looked up or deleted. Review the [ERROR] lines above." -ForegroundColor Red
    Exit-Lab -FailureCount 1
}

Write-Host "Cleanup complete." -ForegroundColor Green
