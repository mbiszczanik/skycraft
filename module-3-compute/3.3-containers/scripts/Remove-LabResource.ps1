<#
.SYNOPSIS
    Cleans up resources created in Lab 3.3.

.DESCRIPTION
    This script removes the Container Registry, Container Instance, and Container Apps
    created for Lab 3.3. It preserves the Resource Group (<Environment>-skycraft-swc-rg) as it
    may contain resources from other labs (e.g., VNets).

    A resource that does not exist is reported and skipped. A resource that exists but cannot
    be deleted is reported as [ERROR] with the Azure error message and counted; the later
    steps still run, and the script exits 1 if any step failed, so an orchestrated cycle can
    tell a failed teardown from a clean one.

    A lookup that fails (a 403, throttling, a transient ARM error) is an [ERROR] too, counted, and
    the resource it could not see is left alone. Only a lookup that succeeds and does not find the
    resource, or a getter that reports it as not found, means "absent" - Test-LabNotFoundError
    tells the two apart (issue #290, as #255 did for Labs 1.2-2.3). The Container Apps environment
    stays when its container app could not be looked up or deleted: the app may still be running
    in it. The kept environment is not counted again - the app's failure already is.

    Each non-zero exit is paired with $Host.SetShouldExit: a bare "exit 1" is dropped under
    "pwsh -File" for any script that declares #Requires -Modules for a module it has to
    auto-import, and the process would exit 0 with the failure still on screen (issue #104).

.PARAMETER Force
    Skip the confirmation prompt.

.PARAMETER Environment
    The environment to tear down: dev, prod or platform. Default: 'dev'. Every resource name
    below defaults to the prefix this selects (#121), matching what Deploy-Bicep.ps1 deploys.

.PARAMETER ResourceGroupName
    The resource group name. Default: '<Environment>-skycraft-swc-rg'

.PARAMETER AcrName
    The container registry name. Default: '<Environment>skycraftswcacr01'

.PARAMETER AciName
    The container instance name. Default: '<Environment>-skycraft-swc-aci-auth'

.PARAMETER CaeName
    The Container Apps environment name. Default: '<Environment>-skycraft-swc-cae-02'

.PARAMETER AcaName
    The container app name. Default: '<Environment>-skycraft-swc-aca-world'. Override it to
    remove an app deployed under the pre-#121 scheme, e.g. prod-skycraft-swc-aca-world-02.

.EXAMPLE
    .\Remove-LabResource.ps1
    Prompts for confirmation before deleting the dev resources.

.EXAMPLE
    .\Remove-LabResource.ps1 -Environment prod -Force
    Removes the prod resources from prod-skycraft-swc-rg without prompting.

.NOTES
    Project: SkyCraft
    Lab: 3.3 - Containers
    Author: Antigravity
    Date: 2026-01-31
#>

#Requires -Version 7.0
#Requires -Modules Az.Accounts, Az.Resources, Az.ContainerInstance, Az.ContainerRegistry

[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory = $false)]
    [switch]$Force,

    [Parameter(Mandatory = $false)]
    [ValidateSet('dev', 'prod', 'platform')]
    [string]$Environment = 'dev',

    # Defaults below read $Environment, so it must be declared first.
    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$ResourceGroupName = "$Environment-skycraft-swc-rg",

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$AcrName = "${Environment}skycraftswcacr01",

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$AciName = "$Environment-skycraft-swc-aci-auth",

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$CaeName = "$Environment-skycraft-swc-cae-02",

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$AcaName = "$Environment-skycraft-swc-aca-world"
)

$ErrorActionPreference = 'Stop'
if ($Force) { $ConfirmPreference = 'None' }

# Absence and failure are different outcomes and are reported differently (#121 live pass):
# the old catch blocks printed "Not found or already deleted" for any error, so a delete that
# threw after the long environment teardown left the registry and the instance standing
# behind a "Cleanup Complete." and an exit code of 0. Each step now looks the resource up
# first, deletes only what exists, and counts a failed lookup or a failed delete; the script
# exits 1 if any did.
$script:cleanupFailures = 0

# Whether a lookup's error says the resource does not exist, rather than that the lookup failed.
# Get-AzResource, asked for one name and type, reports a missing resource as an ARM 404: "The
# Resource '<type>/<name>' under resource group '<rg>' was not found.", code ResourceNotFound; when
# the group is gone as well, "Resource group '<rg>' could not be found.", code
# ResourceGroupNotFound; with no error body, "Operation returned an invalid status code
# 'NotFound'". The Azure.Core clients say "Status: 404 (Not Found)". A missing subscription is a
# 404 too, but it means the context is wrong, not that the resource is gone, so it never reads as
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
#   Value     the lookup's output, as an array - empty when the resource is absent
#   NotFound  the getter reported the resource as not found (Test-LabNotFoundError)
#   Failed    the lookup failed any other way: it is reported as [ERROR] and counted, because it
#             cannot tell whether the resource is gone, and the caller leaves the resource alone
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

Write-Host "=== Lab 3.3 - Resource Cleanup ===" -ForegroundColor Cyan -BackgroundColor Black

# Verify Azure Connection
$context = Get-AzContext
if (-not $context) {
    Write-Host "Not logged in. Please run Connect-AzAccount" -ForegroundColor Red
    $Host.SetShouldExit(1)
    exit 1
}

$resourcesToDelete = @(
    @{ Name = $AcaName; Type = "Container App" },
    @{ Name = $CaeName; Type = "Container Apps Environment" },
    @{ Name = $AciName; Type = "Container Instance" },
    @{ Name = $AcrName; Type = "Container Registry" }
)

# Summary of resources targeted for deletion
Write-Host "This will delete the following resources from $($ResourceGroupName) ($Environment):" -ForegroundColor Yellow
foreach ($res in $resourcesToDelete) {
    Write-Host " - [$($res.Type)] $($res.Name)" -ForegroundColor Gray
}

Write-Host "`nStarting cleanup..." -ForegroundColor Cyan

# Delete order matters: the app must go before its environment, and the environment stays when
# the app could not be looked up or deleted (KeepWhenFailed names the step whose failure keeps it).
$steps = @(
    @{ Type = 'Container App';              Name = $AcaName; ResourceType = 'Microsoft.App/containerApps'
       Remove = { param($r) Remove-AzResource -ResourceId $r.ResourceId -Force -ErrorAction Stop | Out-Null } }
    @{ Type = 'Container Apps Environment'; Name = $CaeName; ResourceType = 'Microsoft.App/managedEnvironments'
       KeepWhenFailed = 'Container App'
       Remove = { param($r) Remove-AzResource -ResourceId $r.ResourceId -Force -ErrorAction Stop | Out-Null } }
    @{ Type = 'Container Instance';         Name = $AciName; ResourceType = 'Microsoft.ContainerInstance/containerGroups'
       Remove = { param($r) Remove-AzContainerGroup -Name $r.Name -ResourceGroupName $ResourceGroupName -ErrorAction Stop | Out-Null } }
    @{ Type = 'Container Registry';         Name = $AcrName; ResourceType = 'Microsoft.ContainerRegistry/registries'
       Remove = { param($r) Remove-AzContainerRegistry -Name $r.Name -ResourceGroupName $ResourceGroupName -ErrorAction Stop | Out-Null } }
)

# The steps that failed, by type: 'looked up' or 'deleted', for the message of the step they keep.
$stepFailed = @{}

foreach ($step in $steps) {
    Write-Host "Removing $($step.Type): $($step.Name)..." -ForegroundColor Yellow
    if ($step.KeepWhenFailed -and $stepFailed[$step.KeepWhenFailed]) {
        # Not counted again: the failure that keeps it already is.
        Write-Host "  -> [SKIP] Kept: the $($step.KeepWhenFailed) could not be $($stepFailed[$step.KeepWhenFailed]) and may still be in it." -ForegroundColor Yellow
        continue
    }
    if (-not $PSCmdlet.ShouldProcess($step.Name, "Remove $($step.Type)")) { continue }

    # The Container Apps types have no base-module cmdlet in the Az gold-path, so every step
    # resolves its target through the generic ARM lookup and the app/environment steps delete
    # through it too.
    $lookup = Invoke-LabLookup -Target "$($step.Type) '$($step.Name)'" -Lookup {
        Get-AzResource -ResourceGroupName $ResourceGroupName -ResourceType $step.ResourceType -Name $step.Name -ErrorAction Stop
    }
    if ($lookup.Failed) {
        $stepFailed[$step.Type] = 'looked up'
        continue
    }
    $resource = $lookup.Value | Select-Object -First 1
    if (-not $resource) {
        Write-Host "  -> [INFO] Not found - nothing to delete." -ForegroundColor Gray
        continue
    }

    try {
        & $step.Remove $resource
        Write-Host "  -> Deleted" -ForegroundColor Green
    } catch {
        $script:cleanupFailures++
        $stepFailed[$step.Type] = 'deleted'
        Write-Host "  -> [ERROR] Could not delete $($step.Type) '$($step.Name)': $_" -ForegroundColor Red
    }
}

if ($script:cleanupFailures -gt 0) {
    Write-Host "`nCleanup finished with $($script:cleanupFailures) failure(s)." -ForegroundColor Red
    Write-Host "  See the [ERROR] lines above - the resources named there may still be in $ResourceGroupName. Re-run this script once the cause is cleared." -ForegroundColor Gray
    $Host.SetShouldExit(1)
    exit 1
}

Write-Host "`nCleanup Complete." -ForegroundColor Green
