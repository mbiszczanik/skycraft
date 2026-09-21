<#
.SYNOPSIS
    Cleans up resources created in Lab 3.3.

.DESCRIPTION
    This script removes the Container Registry, Container Instance, and Container Apps
    created for Lab 3.3. It preserves the Resource Group (<Environment>-skycraft-swc-rg) as it
    may contain resources from other labs (e.g., VNets).

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

# 1. Remove ACA
Write-Host "Removing Container App: $AcaName..." -ForegroundColor Yellow
if ($PSCmdlet.ShouldProcess($AcaName, "Remove Container App")) {
    try {
        # Generic ARM delete — no Container Apps base-module cmdlet in the Az gold-path.
        $r = Get-AzResource -ResourceGroupName $ResourceGroupName -ResourceType 'Microsoft.App/containerApps' -Name $AcaName -ErrorAction SilentlyContinue
        if ($r) { Remove-AzResource -ResourceId $r.ResourceId -Force -ErrorAction SilentlyContinue | Out-Null }
        Write-Host "  -> Deleted (via Az)" -ForegroundColor Green
    } catch {
        Write-Host "  -> [INFO] Not found or already deleted." -ForegroundColor Gray
    }
}

# 2. Remove ACA Environment
Write-Host "Removing Container Apps Environment: $CaeName..." -ForegroundColor Yellow
if ($PSCmdlet.ShouldProcess($CaeName, "Remove Container Apps Environment")) {
    try {
        # Generic ARM delete — no Container Apps base-module cmdlet in the Az gold-path.
        $r = Get-AzResource -ResourceGroupName $ResourceGroupName -ResourceType 'Microsoft.App/managedEnvironments' -Name $CaeName -ErrorAction SilentlyContinue
        if ($r) { Remove-AzResource -ResourceId $r.ResourceId -Force -ErrorAction SilentlyContinue | Out-Null }
        Write-Host "  -> Deleted (via Az)" -ForegroundColor Green
    } catch {
        Write-Host "  -> [INFO] Not found or already deleted." -ForegroundColor Gray
    }
}

# 3. Remove ACI
Write-Host "Removing Container Instance: $AciName..." -ForegroundColor Yellow
if ($PSCmdlet.ShouldProcess($AciName, "Remove Container Instance")) {
    try {
        Remove-AzContainerGroup -Name $AciName -ResourceGroupName $ResourceGroupName -ErrorAction Stop | Out-Null
        Write-Host "  -> Deleted" -ForegroundColor Green
    } catch {
        Write-Host "  -> [INFO] Not found or already deleted." -ForegroundColor Gray
    }
}

# 4. Remove ACR
Write-Host "Removing Container Registry: $AcrName..." -ForegroundColor Yellow
if ($PSCmdlet.ShouldProcess($AcrName, "Remove Container Registry")) {
    try {
        Remove-AzContainerRegistry -Name $AcrName -ResourceGroupName $ResourceGroupName -ErrorAction Stop | Out-Null
        Write-Host "  -> Deleted" -ForegroundColor Green
    } catch {
        Write-Host "  -> [INFO] Not found or already deleted." -ForegroundColor Gray
    }
}

Write-Host "`nCleanup Complete." -ForegroundColor Green
