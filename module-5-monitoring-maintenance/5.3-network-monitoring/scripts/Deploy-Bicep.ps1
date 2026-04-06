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

[CmdletBinding()]
param(
    [Parameter()]
    [switch]$WhatIf
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

$account = az account show --output json 2>$null | ConvertFrom-Json
if (-not $account) {
    Write-Host "  [ERROR] Not logged into Azure CLI. Run 'az login' first." -ForegroundColor Red
    exit 1
}
Write-Host "  ✓ Logged in as: $($account.user.name)" -ForegroundColor Green

# Allow non-interactive installation of required Azure CLI extensions.
az config set extension.use_dynamic_install=yes_without_prompt --only-show-errors | Out-Null

$cliVersion = az version --output json 2>$null | ConvertFrom-Json
Write-Host "  ✓ Azure CLI version: $($cliVersion.'azure-cli')" -ForegroundColor Green

# ── [2/5] Resolve resource IDs ────────────────────────────────────────────
Write-Host "`n[2/5] Resolving existing resource IDs..." -ForegroundColor Yellow

# Platform resource group
$platformRgJson = az group show --name $platformRg --output json 2>$null | ConvertFrom-Json
if (-not $platformRgJson) {
    Write-Host "  [ERROR] Resource group '$platformRg' not found. Complete earlier labs first." -ForegroundColor Red
    exit 1
}
Write-Host "  ✓ Platform RG found: $platformRg" -ForegroundColor Green

# Production VNet
$prodVnetName = 'prod-skycraft-swc-vnet'
$prodVnetJson = az network vnet show `
    --resource-group $prodRg `
    --name $prodVnetName `
    --output json 2>$null | ConvertFrom-Json
if (-not $prodVnetJson) {
    Write-Host "  [ERROR] VNet '$prodVnetName' not found in '$prodRg'. Deploy Lab 2.1 first." -ForegroundColor Red
    exit 1
}
$prodVnetId = $prodVnetJson.id
Write-Host "  ✓ Prod VNet found: $prodVnetName" -ForegroundColor Green

# Platform storage account
$storageName = 'platformskycraftswcsa'
$storageJson = az storage account show `
    --resource-group $platformRg `
    --name $storageName `
    --output json 2>$null | ConvertFrom-Json
if (-not $storageJson) {
    Write-Host "  [ERROR] Storage account '$storageName' not found in '$platformRg'. Deploy Lab 4.1 first." -ForegroundColor Red
    exit 1
}
$storageId = $storageJson.id
Write-Host "  ✓ Storage account found: $storageName" -ForegroundColor Green

# Log Analytics Workspace
$workspaceName = 'platform-skycraft-swc-law'
$workspaceJson = az monitor log-analytics workspace show `
    --resource-group $platformRg `
    --workspace-name $workspaceName `
    --output json 2>$null | ConvertFrom-Json
if (-not $workspaceJson) {
    Write-Host "  [ERROR] Log Analytics Workspace '$workspaceName' not found in '$platformRg'. Deploy Lab 5.1 first." -ForegroundColor Red
    exit 1
}
$workspaceId = $workspaceJson.id
Write-Host "  ✓ Log Analytics Workspace found: $workspaceName" -ForegroundColor Green

# Production VM (Connection Monitor source)
$prodVmName = 'prod-skycraft-swc-auth-vm'
$prodVmJson = az vm show `
    --resource-group $prodRg `
    --name $prodVmName `
    --output json 2>$null | ConvertFrom-Json
if (-not $prodVmJson) {
    Write-Host "  [ERROR] Prod VM '$prodVmName' not found in '$prodRg'. Deploy Lab 3.2 first." -ForegroundColor Red
    exit 1
}
$prodVmId = $prodVmJson.id
Write-Host "  ✓ Prod VM found: $prodVmName" -ForegroundColor Green

# Dev VM (Connection Monitor destination)
$devVmName = 'dev-skycraft-swc-auth-vm'
$devVmJson = az vm show `
    --resource-group $devRg `
    --name $devVmName `
    --output json 2>$null | ConvertFrom-Json
if (-not $devVmJson) {
    Write-Host "  [ERROR] Dev VM '$devVmName' not found in '$devRg'. Deploy Lab 3.2 first." -ForegroundColor Red
    exit 1
}
$devVmId = $devVmJson.id
Write-Host "  ✓ Dev VM found: $devVmName" -ForegroundColor Green

# Verify Network Watcher exists in the region
$nwExists = az network watcher list `
    --query "[?location=='swedencentral']" `
    --output json 2>$null | ConvertFrom-Json
if (-not $nwExists -or $nwExists.Count -eq 0) {
    Write-Host "  [WARNING] Network Watcher not found for swedencentral. Enabling now..." -ForegroundColor Yellow
    try {
        az network watcher configure `
            --resource-group 'NetworkWatcherRG' `
            --locations swedencentral `
            --enabled true `
            --output none 2>$null
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
Write-Host "  Prod VM:          $prodVmName"
Write-Host "  Dev VM:           $devVmName"
Write-Host "  Location:         $location"
Write-Host "  Template:         $templatePath"
Write-Host "  Deployment Name:  $deploymentName"

if (-not $WhatIf) {
    $confirm = Read-Host "`nProceed with deployment? (y/N)"
    if ($confirm -ne 'y') {
        Write-Host "Deployment cancelled." -ForegroundColor Yellow
        exit 0
    }
}

# ── [4/5] Run deployment ──────────────────────────────────────────────────
Write-Host "`n[4/5] Running deployment..." -ForegroundColor Yellow

$commonParams = @(
    '--name', $deploymentName,
    '--location', $location,
    '--template-file', $templatePath,
    '--parameters', "parProdVnetResourceId=$prodVnetId",
    '--parameters', "parStorageAccountResourceId=$storageId",
    '--parameters', "parWorkspaceResourceId=$workspaceId",
    '--parameters', "parProdVmResourceId=$prodVmId",
    '--parameters', "parDevVmResourceId=$devVmId"
)

if ($WhatIf) {
    Write-Host "  Running in what-if mode (dry run)..." -ForegroundColor Cyan
    $deployArgs = @('deployment', 'sub', 'what-if') + $commonParams
} else {
    $deployArgs = @('deployment', 'sub', 'create') + $commonParams + @('--output', 'json')
}

$result   = az @deployArgs 2>$null
$exitCode = $LASTEXITCODE

if ($exitCode -ne 0) {
    Write-Host "`n  [ERROR] Deployment failed with exit code $exitCode" -ForegroundColor Red
    Write-Host $result -ForegroundColor Red
    exit $exitCode
}

# ── [5/5] Display results ─────────────────────────────────────────────────
Write-Host "`n[5/5] Deployment Results:" -ForegroundColor Yellow

if ($WhatIf) {
    Write-Host $result
    Write-Host "`n  What-if completed. Review changes above." -ForegroundColor Cyan
} else {
    $deployment = $result | ConvertFrom-Json
    Write-Host "  ✓ Deployment succeeded!" -ForegroundColor Green
    Write-Host "`n  Outputs:"
    Write-Host "    Flow Log ID:            $($deployment.properties.outputs.outFlowLogId.value)"
    Write-Host "    Connection Monitor ID:  $($deployment.properties.outputs.outConnectionMonitorId.value)"

    Write-Host "`n  Next Steps:" -ForegroundColor Cyan
    Write-Host "    1. Verify Network Watcher diagnostic tools in the Azure Portal" -ForegroundColor Gray
    Write-Host "    2. Run IP Flow Verify and Next Hop tests from the lab guide" -ForegroundColor Gray
    Write-Host "    3. Wait 10-30 min for Traffic Analytics data to appear in the workspace" -ForegroundColor Gray
    Write-Host "    4. Run .\Test-Lab.ps1 to validate deployment" -ForegroundColor Gray
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  Deployment Complete" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan
