<#
.SYNOPSIS
    Removes Lab 4.3 Resources
.DESCRIPTION
    Removes only the two Azure File Shares created by Lab 4.3 (skycraft-config, skycraft-shared)
    from the storage account of the selected environment. Does NOT delete the shared
    <env>-skycraft-swc-rg resource group, which contains Lab 4.1 storage required by Labs 4.2 and 4.4.

    A lookup that fails (a 403, throttling, a transient ARM error) or a removal that fails is
    reported as [ERROR] and counted; if anything failed the script exits 1. An object that does
    not exist is not a failure: only a lookup that succeeds and does not find it, or a getter that
    reports it as not found, means "absent" - Test-LabNotFoundError tells the two apart (issue
    #290, as #255 did for Labs 1.2-2.3). The shares are listed once and picked by name, so a
    missing share is an empty match rather than an error to interpret; a listing that fails
    touches no share.

    Each non-zero exit is paired with $Host.SetShouldExit: a bare "exit 1" is dropped under
    "pwsh -File" for any script that declares #Requires -Modules for a module it has to
    auto-import, and the process would exit 0 with the failure still on screen (issue #104).
.PARAMETER Environment
    Environment to clean up (prod, dev or platform). Default: prod. Matches Deploy-Bicep.ps1.
.PARAMETER Force
    Skip confirmation prompt.
.EXAMPLE
    .\Remove-LabResource.ps1 -Force
    Removes both shares from prodskycraftswcsa.
.EXAMPLE
    .\Remove-LabResource.ps1 -Environment dev -Force
    Removes both shares from devskycraftswcsa.
.NOTES
    Project: SkyCraft
    Author: SkyCraft
    Version: 2.1.0
    Date: 2026-08-28
#>

#Requires -Version 7.0
#Requires -Modules Az.Accounts, Az.Storage

[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory = $false)]
    [ValidateSet('prod', 'dev', 'platform')]
    [string]$Environment = 'prod',

    [Parameter(Mandatory = $false)]
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
if ($Force) { $ConfirmPreference = 'None' }

# Counts lookups that failed and shares that exist but could not be removed. Absent objects are
# not failures.
$script:cleanupFailures = 0

# Whether a lookup's error says the object does not exist, rather than that the lookup failed.
# Get-AzStorageAccount reports a missing account as an ARM 404: "The Resource
# 'Microsoft.Storage/storageAccounts/<name>' under resource group '<rg>' was not found.", code
# ResourceNotFound; when the group is gone as well, "Resource group '<rg>' could not be found.",
# code ResourceGroupNotFound; with no error body, "Operation returned an invalid status code
# 'NotFound'". The shares are listed, so a missing share is an empty match. The Azure.Core
# clients say "Status: 404 (Not Found)". A missing subscription is a 404 too, but it means the
# context is wrong, not that the object is gone, so it never reads as "absent".
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

$resourceGroupName  = "$Environment-skycraft-swc-rg"
$storageAccountName = "${Environment}skycraftswcsa"
$subscriptionId     = (Get-AzContext).Subscription.Id

Write-Host "=== Lab 4.3: Cleaning Up File Shares ($Environment) ===" -ForegroundColor Cyan

# 1. Verify Connection
if (-not (Get-AzContext)) {
    Write-Host " [ERROR] Not logged in. Please run Connect-AzAccount." -ForegroundColor Red; $Host.SetShouldExit(1); exit 1
}

# 2. Verify storage account exists (do not attempt to delete the RG)
$saLookup = Invoke-LabLookup -Target "storage account '$storageAccountName'" -Lookup {
    Get-AzStorageAccount -ResourceGroupName $resourceGroupName -Name $storageAccountName -ErrorAction Stop
}
if (-not $saLookup.Failed -and -not $saLookup.Value) {
    Write-Host " [INFO] Storage account '$storageAccountName' not found. Nothing to clean up." -ForegroundColor Gray
    exit 0
}

# 3. Remove the two file shares created by this lab. Listed once and picked by name; if the
#    account or its shares could not be looked up, no share is touched.
$sharesToRemove = @('skycraft-config', 'skycraft-shared')
$shareLookup = $null
if (-not $saLookup.Failed) {
    $shareLookup = Invoke-LabLookup -Target "the file shares in '$storageAccountName'" -Lookup {
        Get-AzRmStorageShare -ResourceGroupName $resourceGroupName -StorageAccountName $storageAccountName -ErrorAction Stop
    }
}

if ($shareLookup -and -not $shareLookup.Failed) {
    foreach ($shareName in $sharesToRemove) {
        $shareId = "/subscriptions/$subscriptionId/resourceGroups/$resourceGroupName/providers/Microsoft.Storage/storageAccounts/$storageAccountName/fileServices/default/shares/$shareName"
        if ($shareLookup.Value | Where-Object { $_.Name -eq $shareName }) {
            Write-Host "Removing file share '$shareName'..." -ForegroundColor Yellow
            try {
                if ($PSCmdlet.ShouldProcess($shareName, 'Remove file share')) {
                    Remove-AzResource -ResourceId $shareId -Force -ErrorAction Stop | Out-Null
                    Write-Host "  -> Successfully removed '$shareName'." -ForegroundColor Green
                }
            } catch {
                $script:cleanupFailures++
                Write-Host "  -> [ERROR] Could not remove '$shareName': $($_.Exception.Message)" -ForegroundColor Red
            }
        } else {
            Write-Host "  -> Share '$shareName' not found, skipping." -ForegroundColor Gray
        }
    }
}

if ($script:cleanupFailures -gt 0) {
    Write-Host "`nLab 4.3 cleanup finished with $($script:cleanupFailures) failure(s). See the [ERROR] lines above." -ForegroundColor Red
    $Host.SetShouldExit(1)
    exit 1
}

Write-Host "`nLab 4.3 Cleanup Complete." -ForegroundColor Cyan
Write-Host "Note: The shared '$resourceGroupName' resource group and storage account were preserved for Labs 4.2 and 4.4." -ForegroundColor Gray
