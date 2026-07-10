<#
.SYNOPSIS
    Deploys Lab 5.3 Network Monitoring & Diagnostics infrastructure using Bicep.

.DESCRIPTION
    This script deploys the Lab 5.3 Bicep templates to Azure, including:
    - VNet Flow Log (prod-skycraft-swc-vnet-flowlog) on prod-skycraft-swc-vnet
      with Version 2, 7-day retention, and Traffic Analytics
    - Connection Monitor (skycraft-hub-spoke-cm) probing TCP/22 from
      prod-skycraft-swc-auth-vm to dev-skycraft-swc-auth-vm every 5 minutes

    Prerequisites: Labs 2.1 (VNets), 2.2 (NSGs), 3.2 (VMs), 4.1 (Storage),
    and 5.1 (Log Analytics Workspace) must be deployed.

.PARAMETER WhatIf
    Run deployment in what-if mode (dry run).

.EXAMPLE
    .\Deploy-Bicep.ps1

.EXAMPLE
    .\Deploy-Bicep.ps1 -WhatIf

.NOTES
    Project: SkyCraft
    Author: SkyCraft
    Date: 2026-04-06
#>

#Requires -Version 7.0
#Requires -Modules Az.Accounts, Az.Resources, Az.Network, Az.Storage, Az.OperationalInsights, Az.Compute

[CmdletBinding()]
param(
    [Parameter()]
    [switch]$WhatIf,

    [Parameter()]
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

# Script configuration
$scriptPath     = Split-Path -Parent $MyInvocation.MyCommand.Path
$templatePath   = Join-Path $scriptPath '..\bicep\main.bicep'
$location       = 'swedencentral'
$platformRg     = 'platform-skycraft-swc-rg'
$prodRg         = 'prod-skycraft-swc-rg'
$devRg          = 'dev-skycraft-swc-rg'
$deploymentName = "lab53-$(Get-Date -Format 'yyyyMMdd-HHmmss')"

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  Lab 5.3 - Network Monitoring Deployment" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# ── [1/5] Validate prerequisites ──────────────────────────────────────────
Write-Host "[1/5] Validating prerequisites..." -ForegroundColor Yellow

$context = Get-AzContext
if (-not $context) {
    Write-Host "  [ERROR] Not logged into Azure. Run 'Connect-AzAccount' first." -ForegroundColor Red
    exit 1
}
Write-Host "  ✓ Logged in as: $($context.Account.Id)" -ForegroundColor Green

$azVersion = (Get-Module -ListAvailable -Name Az.Accounts | Sort-Object Version -Descending | Select-Object -First 1).Version
Write-Host "  ✓ Az PowerShell (Az.Accounts) version: $azVersion" -ForegroundColor Green

# ── [2/5] Resolve resource IDs ────────────────────────────────────────────
Write-Host "`n[2/5] Resolving existing resource IDs..." -ForegroundColor Yellow

# Platform resource group
$platformRgObj = Get-AzResourceGroup -Name $platformRg -ErrorAction SilentlyContinue
if (-not $platformRgObj) {
    Write-Host "  [ERROR] Resource group '$platformRg' not found. Complete earlier labs first." -ForegroundColor Red
    exit 1
}
Write-Host "  ✓ Platform RG found: $platformRg" -ForegroundColor Green

# Production VNet
$prodVnetName = 'prod-skycraft-swc-vnet'
$prodVnetObj = Get-AzVirtualNetwork -ResourceGroupName $prodRg -Name $prodVnetName -ErrorAction SilentlyContinue
if (-not $prodVnetObj) {
    Write-Host "  [ERROR] VNet '$prodVnetName' not found in '$prodRg'. Deploy Lab 2.1 first." -ForegroundColor Red
    exit 1
}
$prodVnetId = $prodVnetObj.Id
Write-Host "  ✓ Prod VNet found: $prodVnetName" -ForegroundColor Green

# Platform storage account
$storageName = 'platformskycraftswcsa'
$storageObj = Get-AzStorageAccount -ResourceGroupName $platformRg -Name $storageName -ErrorAction SilentlyContinue
if (-not $storageObj) {
    Write-Host "  [ERROR] Storage account '$storageName' not found in '$platformRg'. Deploy Lab 4.1 first." -ForegroundColor Red
    exit 1
}
$storageId = $storageObj.Id
Write-Host "  ✓ Storage account found: $storageName" -ForegroundColor Green

# Log Analytics Workspace
$workspaceName = 'platform-skycraft-swc-law'
$workspaceObj = Get-AzOperationalInsightsWorkspace -ResourceGroupName $platformRg -Name $workspaceName -ErrorAction SilentlyContinue
if (-not $workspaceObj) {
    Write-Host "  [ERROR] Log Analytics Workspace '$workspaceName' not found in '$platformRg'. Deploy Lab 5.1 first." -ForegroundColor Red
    exit 1
}
$workspaceId = $workspaceObj.ResourceId
Write-Host "  ✓ Log Analytics Workspace found: $workspaceName" -ForegroundColor Green

# Connection Monitor endpoints. The lab guide's prerequisite is "at least one VM"
# and the cost-optimized cycle deploys dev VMs only (auth + world). Use two
# distinct existing VMs: prefer the prod auth VM as source (hub→spoke probe) but
# fall back to the dev auth VM; destination is the dev world VM (or dev auth).
$devAuthVm  = Get-AzVM -ResourceGroupName $devRg  -Name 'dev-skycraft-swc-auth-vm'  -ErrorAction SilentlyContinue
$devWorldVm = Get-AzVM -ResourceGroupName $devRg  -Name 'dev-skycraft-swc-world-vm' -ErrorAction SilentlyContinue
$prodAuthVm = Get-AzVM -ResourceGroupName $prodRg -Name 'prod-skycraft-swc-auth-vm' -ErrorAction SilentlyContinue

# Destination must be the dev auth VM — the bicep endpoint is named
# 'dev-auth-destination' and Test-Lab asserts the dest is dev-skycraft-swc-auth-vm.
$destVm = $devAuthVm
# Source prefers the prod auth VM (hub→spoke probe) but falls back to the dev
# world VM so source and destination are two distinct existing VMs.
$sourceVm = if ($prodAuthVm) { $prodAuthVm } else { $devWorldVm }
if (-not $sourceVm -or -not $destVm -or $sourceVm.Id -eq $destVm.Id) {
    Write-Host "  [ERROR] Connection Monitor needs two distinct SkyCraft VMs (dev auth + world, or prod auth + dev auth). Deploy Lab 3.2 first." -ForegroundColor Red
    exit 1
}
$prodVmId = $sourceVm.Id
$devVmId  = $destVm.Id
Write-Host "  ✓ Connection Monitor: $($sourceVm.Name) -> $($destVm.Name)" -ForegroundColor Green

# Connection Monitor with VM endpoints requires the NetworkWatcherAgent extension
# on each VM. Install it (idempotent) on source + dest before the CM is created —
# otherwise the deployment fails with NetworkWatcherVmExtensionNotInstalled.
foreach ($cmVm in @($sourceVm, $destVm)) {
    $hasExt = Get-AzVMExtension -ResourceGroupName $cmVm.ResourceGroupName -VMName $cmVm.Name -ErrorAction SilentlyContinue |
        Where-Object { $_.Publisher -eq 'Microsoft.Azure.NetworkWatcher' }
    if (-not $hasExt) {
        Write-Host "  Installing NetworkWatcherAgent on $($cmVm.Name)..." -ForegroundColor Yellow
        try {
            # Use New-AzResource (not Set-AzVMExtension) so the extension carries the
            # Project tag — the Lab 1.3 governance policy denies untagged resources,
            # and Set-AzVMExtension has no -Tag parameter.
            New-AzResource -ResourceId "$($cmVm.Id)/extensions/NetworkWatcherAgentLinux" -Location $cmVm.Location `
                -Properties @{ publisher = 'Microsoft.Azure.NetworkWatcher'; type = 'NetworkWatcherAgentLinux'; typeHandlerVersion = '1.4'; autoUpgradeMinorVersion = $true } `
                -Tag @{ Project = 'SkyCraft' } -Force -ErrorAction Stop | Out-Null
            Write-Host "  ✓ NetworkWatcherAgent installed on $($cmVm.Name)" -ForegroundColor Green
        } catch {
            Write-Host "  [ERROR] Failed to install NetworkWatcherAgent on $($cmVm.Name): $($_.Exception.Message)" -ForegroundColor Red
            exit 1
        }
    } else {
        Write-Host "  ✓ NetworkWatcherAgent already present on $($cmVm.Name)" -ForegroundColor Green
    }
}

# Verify Network Watcher exists in the region
$nwExists = @(Get-AzNetworkWatcher -ErrorAction SilentlyContinue | Where-Object { $_.Location -eq $location })
if (-not $nwExists -or $nwExists.Count -eq 0) {
    Write-Host "  [WARNING] Network Watcher not found for swedencentral. Enabling now..." -ForegroundColor Yellow
    try {
        $nwRg = Get-AzResourceGroup -Name 'NetworkWatcherRG' -ErrorAction SilentlyContinue
        if (-not $nwRg) {
            New-AzResourceGroup -Name 'NetworkWatcherRG' -Location $location `
                -Tag @{ Project = 'SkyCraft'; Environment = 'Platform'; CostCenter = 'MSDN' } -ErrorAction Stop | Out-Null
        }
        New-AzNetworkWatcher -Name "NetworkWatcher_$location" -ResourceGroupName 'NetworkWatcherRG' -Location $location `
            -Tag @{ Project = 'SkyCraft'; Environment = 'Platform'; CostCenter = 'MSDN' } -ErrorAction Stop | Out-Null
        Write-Host "  ✓ Network Watcher enabled for swedencentral" -ForegroundColor Green
    }
    catch {
        Write-Host "  [ERROR] Could not enable Network Watcher: $_" -ForegroundColor Red
        exit 1
    }
} else {
    Write-Host "  ✓ Network Watcher active for swedencentral" -ForegroundColor Green
}

# ── [3/5] Display deployment configuration ────────────────────────────────
Write-Host "`n[3/5] Deployment Configuration:" -ForegroundColor Yellow
Write-Host "  Prod VNet:        $prodVnetName"
Write-Host "  Storage Account:  $storageName"
Write-Host "  LAW Workspace:    $workspaceName"
Write-Host "  CM Source VM:     $($sourceVm.Name)"
Write-Host "  CM Dest VM:       $($destVm.Name)"
Write-Host "  Location:         $location"
Write-Host "  Template:         $templatePath"
Write-Host "  Deployment Name:  $deploymentName"

if (-not $WhatIf -and -not $Force) {
    $confirm = Read-Host "`nProceed with deployment? (y/N)"
    if ($confirm -ne 'y') {
        Write-Host "Deployment cancelled." -ForegroundColor Yellow
        exit 0
    }
}

# ── [4/5] Run deployment ──────────────────────────────────────────────────
Write-Host "`n[4/5] Running deployment..." -ForegroundColor Yellow

$deployParams = @{
    Name                        = $deploymentName
    Location                    = $location
    TemplateFile                = $templatePath
    parProdVnetResourceId       = $prodVnetId
    parStorageAccountResourceId = $storageId
    parWorkspaceResourceId      = $workspaceId
    parProdVmResourceId         = $prodVmId
    parDevVmResourceId          = $devVmId
    ErrorAction                 = 'Stop'
}

try {
    if ($WhatIf) {
        Write-Host "  Running in what-if mode (dry run)..." -ForegroundColor Cyan
        $result = Get-AzSubscriptionDeploymentWhatIfResult @deployParams
    } else {
        $deployment = New-AzSubscriptionDeployment @deployParams
    }
}
catch {
    Write-Host "`n  [ERROR] Deployment failed: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# ── [5/5] Display results ─────────────────────────────────────────────────
Write-Host "`n[5/5] Deployment Results:" -ForegroundColor Yellow

if ($WhatIf) {
    $result
    Write-Host "`n  What-if completed. Review changes above." -ForegroundColor Cyan
} else {
    Write-Host "  ✓ Deployment succeeded!" -ForegroundColor Green
    Write-Host "`n  Outputs:"
    Write-Host "    Flow Log ID:            $($deployment.Outputs['outFlowLogId'].Value)"
    Write-Host "    Connection Monitor ID:  $($deployment.Outputs['outConnectionMonitorId'].Value)"

    Write-Host "`n  Next Steps:" -ForegroundColor Cyan
    Write-Host "    1. Verify Network Watcher diagnostic tools in the Azure Portal" -ForegroundColor Gray
    Write-Host "    2. Run IP Flow Verify and Next Hop tests from the lab guide" -ForegroundColor Gray
    Write-Host "    3. Wait 10-30 min for Traffic Analytics data to appear in the workspace" -ForegroundColor Gray
    Write-Host "    4. Run .\Test-Lab.ps1 to validate deployment" -ForegroundColor Gray
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  Deployment Complete" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan
