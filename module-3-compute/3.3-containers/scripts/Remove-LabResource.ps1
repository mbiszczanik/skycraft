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

# Absence and failure are different outcomes and are reported differently (#121 live pass):
# the old catch blocks printed "Not found or already deleted" for any error, so a delete that
# threw after the long environment teardown left the registry and the instance standing
# behind a "Cleanup Complete." and an exit code of 0. Each step now looks the resource up
# first, deletes only what exists, and counts a failed delete; the script exits 1 if any did.
$script:cleanupFailures = 0

# Delete order matters: the app must go before its environment.
$steps = @(
    @{ Type = 'Container App';              Name = $AcaName; ResourceType = 'Microsoft.App/containerApps'
       Remove = { param($r) Remove-AzResource -ResourceId $r.ResourceId -Force -ErrorAction Stop | Out-Null } }
    @{ Type = 'Container Apps Environment'; Name = $CaeName; ResourceType = 'Microsoft.App/managedEnvironments'
       Remove = { param($r) Remove-AzResource -ResourceId $r.ResourceId -Force -ErrorAction Stop | Out-Null } }
    @{ Type = 'Container Instance';         Name = $AciName; ResourceType = 'Microsoft.ContainerInstance/containerGroups'
       Remove = { param($r) Remove-AzContainerGroup -Name $r.Name -ResourceGroupName $ResourceGroupName -ErrorAction Stop | Out-Null } }
    @{ Type = 'Container Registry';         Name = $AcrName; ResourceType = 'Microsoft.ContainerRegistry/registries'
       Remove = { param($r) Remove-AzContainerRegistry -Name $r.Name -ResourceGroupName $ResourceGroupName -ErrorAction Stop | Out-Null } }
)

foreach ($step in $steps) {
    Write-Host "Removing $($step.Type): $($step.Name)..." -ForegroundColor Yellow
    if (-not $PSCmdlet.ShouldProcess($step.Name, "Remove $($step.Type)")) { continue }

    # The Container Apps types have no base-module cmdlet in the Az gold-path, so every step
    # resolves its target through the generic ARM lookup and the app/environment steps delete
    # through it too.
    $resource = Get-AzResource -ResourceGroupName $ResourceGroupName -ResourceType $step.ResourceType -Name $step.Name -ErrorAction SilentlyContinue
    if (-not $resource) {
        Write-Host "  -> [INFO] Not found - nothing to delete." -ForegroundColor Gray
        continue
    }

    try {
        & $step.Remove $resource
        Write-Host "  -> Deleted" -ForegroundColor Green
    } catch {
        $script:cleanupFailures++
        Write-Host "  -> [ERROR] Could not delete $($step.Type) '$($step.Name)': $_" -ForegroundColor Red
    }
}

if ($script:cleanupFailures -gt 0) {
    Write-Host "`nCleanup finished with $($script:cleanupFailures) failure(s)." -ForegroundColor Red
    Write-Host "  See the [ERROR] lines above - the resources named there are still in $ResourceGroupName. Re-run this script once the cause is cleared." -ForegroundColor Gray
    $Host.SetShouldExit(1)
    exit 1
}

Write-Host "`nCleanup Complete." -ForegroundColor Green
