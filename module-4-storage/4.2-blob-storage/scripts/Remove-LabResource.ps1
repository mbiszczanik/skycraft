<#
.SYNOPSIS
    Cleans up Lab 4.2 Resources (Containers, Policies).

.DESCRIPTION
    Removes the specific containers and configurations created in Lab 4.2.
    Does NOT delete the storage accounts themselves.
    Reverts Versioning and Public Access settings to Lab 4.1 defaults.

    Every step continues on error, so one stuck object does not strand the rest. A lookup that
    fails (a 403, throttling, a transient error) or a step that fails is reported as [ERROR] and
    counted; if anything failed the script exits 1. An object that does not exist is not a
    failure: only a lookup that succeeds and does not find it, or a getter that reports it as not
    found, means "absent" - Test-LabNotFoundError tells the two apart (issue #290, as #255 did for
    Labs 1.2-2.3). The containers are listed once per account through the control plane
    (Get-AzRmStorageContainer) and picked by name, so a missing container is an empty match. The
    control plane does not go through the storage firewall: Lab 4.4 sets it to deny, and the lab
    cycle runs this cleanup on the same account right after 4.4 reverts it, while the revert may
    still be applying (it takes up to a minute). A storage account that could not be looked up is
    left alone.

    Each non-zero exit is paired with $Host.SetShouldExit: a bare "exit 1" is dropped under
    "pwsh -File" for any script that declares #Requires -Modules for a module it has to
    auto-import, and the process would exit 0 with the failure still on screen (issue #104).

.PARAMETER Force
    Skip confirmation prompt.

.EXAMPLE
    .\Remove-LabResource.ps1 -Force

.NOTES
    Project: SkyCraft
    Author: SkyCraft
#>

#Requires -Version 7.0
#Requires -Modules Az.Accounts, Az.Storage

[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
if ($Force) { $ConfirmPreference = 'None' }

# Counts lookups that failed and steps that could not be carried out. Absent objects are not
# failures.
$script:cleanupFailures = 0

# Whether a lookup's error says the object does not exist, rather than that the lookup failed.
# Get-AzStorageAccount and Get-AzStorageAccountManagementPolicy report a missing object as an ARM
# 404: "The Resource '<type>/<name>' under resource group '<rg>' was not found.", code
# ResourceNotFound; when the group is gone as well, "Resource group '<rg>' could not be found.",
# code ResourceGroupNotFound; with no error body, "Operation returned an invalid status code
# 'NotFound'", or a 404 status on the response. The containers are listed, so a missing one is an
# empty match. The Azure.Core clients say "Status: 404 (Not Found)". A missing subscription is a
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

# Runs one cleanup step; a step that throws is reported as [ERROR] and counted, and the next
# step still runs.
function Invoke-LabStep {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Description,

        [Parameter(Mandatory = $true)]
        [scriptblock]$Action
    )

    try {
        & $Action
    }
    catch {
        $script:cleanupFailures++
        Write-Host "  [ERROR] Could not $($Description): $_" -ForegroundColor Red
    }
}

$ProdRgName = 'prod-skycraft-swc-rg'
$ProdSaName = 'prodskycraftswcsa'
$DevRgName = 'dev-skycraft-swc-rg'
$DevSaName = 'devskycraftswcsa'

Write-Host "=== Lab 4.2 Cleanup ===" -ForegroundColor Cyan

# 1. Clean Production
Write-Host "Cleaning Production ($ProdSaName)..." -ForegroundColor Yellow
$prodLookup = Invoke-LabLookup -Target "storage account $ProdSaName" -Lookup {
    Get-AzStorageAccount -ResourceGroupName $ProdRgName -Name $ProdSaName -ErrorAction Stop
}
$prodSa = $prodLookup.Value | Select-Object -First 1

if (-not $prodLookup.Failed -and -not $prodSa) {
    Write-Host "  [INFO] Storage account $ProdSaName not found - nothing to clean." -ForegroundColor Gray
}
elseif ($prodSa -and $PSCmdlet.ShouldProcess($ProdSaName, 'Remove Lab 4.2 containers and reset storage configuration')) {
    # Remove Containers - listed once and picked by name; a listing that fails touches none.
    $containers = @('game-assets', 'player-backups', 'server-config', 'game-logs')
    $containerLookup = Invoke-LabLookup -Target "the containers in $ProdSaName" -Lookup {
        Get-AzRmStorageContainer -ResourceGroupName $ProdRgName -StorageAccountName $ProdSaName -ErrorAction Stop
    }
    if (-not $containerLookup.Failed) {
        foreach ($c in $containers) {
            if ($containerLookup.Value | Where-Object { $_.Name -eq $c }) {
                Invoke-LabStep -Description "delete container $c" -Action {
                    Remove-AzRmStorageContainer -ResourceGroupName $ProdRgName -StorageAccountName $ProdSaName -Name $c -Force -ErrorAction Stop
                    Write-Host "  Deleted container: $c" -ForegroundColor Gray
                }
            }
        }
    }

    # Remove Lifecycle Policy
    $policyLookup = Invoke-LabLookup -Target "the lifecycle policy of $ProdSaName" -Lookup {
        Get-AzStorageAccountManagementPolicy -ResourceGroupName $ProdRgName -StorageAccountName $ProdSaName -ErrorAction Stop
    }
    if ($policyLookup.Value) {
        Invoke-LabStep -Description 'remove the lifecycle policy' -Action {
            Remove-AzStorageAccountManagementPolicy -ResourceGroupName $ProdRgName -StorageAccountName $ProdSaName -ErrorAction Stop
            Write-Host "  Removed Lifecycle Policy" -ForegroundColor Gray
        }
    }

    # Disable Versioning (Update-AzStorageBlobServiceProperty)
    Invoke-LabStep -Description 'disable versioning' -Action {
        Update-AzStorageBlobServiceProperty -ResourceGroupName $ProdRgName -StorageAccountName $ProdSaName -IsVersioningEnabled $false -ErrorAction Stop
        Write-Host "  Disabled Versioning" -ForegroundColor Gray
    }
}

# 2. Clean Development
Write-Host "Cleaning Development ($DevSaName)..." -ForegroundColor Yellow
$devLookup = Invoke-LabLookup -Target "storage account $DevSaName" -Lookup {
    Get-AzStorageAccount -ResourceGroupName $DevRgName -Name $DevSaName -ErrorAction Stop
}
$devSa = $devLookup.Value | Select-Object -First 1

if (-not $devLookup.Failed -and -not $devSa) {
    Write-Host "  [INFO] Storage account $DevSaName not found - nothing to clean." -ForegroundColor Gray
}
elseif ($devSa -and $PSCmdlet.ShouldProcess($DevSaName, 'Remove public-demo container and disable public access')) {
    # Remove Public Demo Container
    $devContainerLookup = Invoke-LabLookup -Target "the containers in $DevSaName" -Lookup {
        Get-AzRmStorageContainer -ResourceGroupName $DevRgName -StorageAccountName $DevSaName -ErrorAction Stop
    }
    if ($devContainerLookup.Value | Where-Object { $_.Name -eq 'public-demo' }) {
        Invoke-LabStep -Description 'delete container public-demo' -Action {
            Remove-AzRmStorageContainer -ResourceGroupName $DevRgName -StorageAccountName $DevSaName -Name 'public-demo' -Force -ErrorAction Stop
            Write-Host "  Deleted container: public-demo" -ForegroundColor Gray
        }
    }

    # Disable Public Access on Account
    # Note: Az types don't always support updating this property easily via Set-AzStorageAccount in older modules?
    # Using Set-AzStorageAccount -AllowBlobPublicAccess $false
    Invoke-LabStep -Description 'disable public access' -Action {
        Set-AzStorageAccount -ResourceGroupName $DevRgName -Name $DevSaName -AllowBlobPublicAccess $false -ErrorAction Stop
        Write-Host "  Disabled Public Access" -ForegroundColor Gray
    }
}

if ($script:cleanupFailures -gt 0) {
    Write-Host "`nCleanup finished with $($script:cleanupFailures) failure(s). See the [ERROR] lines above." -ForegroundColor Red
    $Host.SetShouldExit(1)
    exit 1
}

Write-Host "Cleanup Complete!" -ForegroundColor Green
