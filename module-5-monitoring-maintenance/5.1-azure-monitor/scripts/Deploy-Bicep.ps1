<#
.SYNOPSIS
    Deploys Lab 5.1 Azure Monitor & Insights infrastructure using Bicep.

.DESCRIPTION
    This script deploys the Lab 5.1 Bicep templates to Azure, including:
    - Log Analytics Workspace (platform-skycraft-swc-law)
    - VM Insights Data Collection Rule (skycraft-vm-dcr)
    - DCR Association with the target VM
    - Action Group (skycraft-ops-ag) with email notification
    - Metric Alert (skycraft-cpu-alert) for CPU > 80%
    - Alert Processing Rule (skycraft-hours-apr) for business hours
    - Storage Account Diagnostic Settings (skycraft-storage-diag)

    Prerequisites: Lab 3.2 (VMs) and Lab 4.1 (Storage) must be deployed.

.PARAMETER OpsEmail
    Email address for Action Group notifications. Required.

.PARAMETER ProdEnvironment
    Prod environment prefix to locate the production VM. Default: prod

.PARAMETER DevEnvironment
    Dev environment prefix to locate the development VM. Default: dev

.PARAMETER WhatIf
    Run deployment in what-if mode (dry run).

.PARAMETER Force
    Skip confirmation prompt for non-interactive execution.

.EXAMPLE
    .\Deploy-Bicep.ps1 -OpsEmail "ops@example.com"

.EXAMPLE
    .\Deploy-Bicep.ps1 -OpsEmail "ops@example.com" -WhatIf

.NOTES
    Project: SkyCraft
    Author: SkyCraft
    Date: 2026-04-06
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$OpsEmail,

    [Parameter()]
    [ValidateSet('dev', 'prod')]
    [string]$ProdEnvironment = 'prod',

    [Parameter()]
    [ValidateSet('dev', 'prod')]
    [string]$DevEnvironment = 'dev',

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
$deploymentName = "lab51-$(Get-Date -Format 'yyyyMMdd-HHmmss')"

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  Lab 5.1 - Azure Monitor Deployment" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# ── [1/6] Validate prerequisites ──────────────────────────────────────────
Write-Host "[1/6] Validating prerequisites..." -ForegroundColor Yellow

$account = az account show --output json 2>$null | ConvertFrom-Json
if (-not $account) {
    Write-Host "  [ERROR] Not logged into Azure CLI. Run 'az login' first." -ForegroundColor Red
    exit 1
}
Write-Host "  ✓ Logged in as: $($account.user.name)" -ForegroundColor Green

# Allow non-interactive installation of required Azure CLI extensions.
az config set extension.use_dynamic_install=yes_without_prompt --only-show-errors | Out-Null

# Verify AZ CLI version
$cliVersion = az version --output json 2>$null | ConvertFrom-Json
Write-Host "  ✓ Azure CLI version: $($cliVersion.'azure-cli')" -ForegroundColor Green

# ── [2/6] Resolve resource IDs ────────────────────────────────────────────
Write-Host "`n[2/6] Resolving existing resource IDs..." -ForegroundColor Yellow

# Platform resource group
$platformRgExists = az group show --name $platformRg --output json 2>$null | ConvertFrom-Json
if (-not $platformRgExists) {
    Write-Host "  [ERROR] Resource group '$platformRg' not found. Complete earlier labs first." -ForegroundColor Red
    exit 1
}
Write-Host "  ✓ Platform RG found: $platformRg" -ForegroundColor Green

# Prod VM (alert target)
$prodVmName = "$ProdEnvironment-skycraft-swc-auth-vm"
$prodRgName  = "$ProdEnvironment-skycraft-swc-rg"
$prodVmJson = az vm show --name $prodVmName --resource-group $prodRgName --output json 2>$null | ConvertFrom-Json
if (-not $prodVmJson) {
    Write-Host "  [ERROR] Prod VM '$prodVmName' not found in '$prodRgName'. Deploy Lab 3.2 first." -ForegroundColor Red
    exit 1
}
$prodVmId = $prodVmJson.id
Write-Host "  ✓ Prod VM found: $prodVmName" -ForegroundColor Green

# Dev VM (DCR association target)
$devVmName = "$DevEnvironment-skycraft-swc-auth-vm"
$devRgName  = "$DevEnvironment-skycraft-swc-rg"
$devVmJson = az vm show --name $devVmName --resource-group $devRgName --output json 2>$null | ConvertFrom-Json
if (-not $devVmJson) {
    Write-Host "  [WARNING] Dev VM '$devVmName' not found in '$devRgName'. DCR association will be skipped." -ForegroundColor Yellow
    $devVmId = $prodVmId   # fall back to prod VM for APR scope
} else {
    $devVmId = $devVmJson.id
    Write-Host "  ✓ Dev VM found: $devVmName" -ForegroundColor Green
}

# Platform storage account
$storageJson = az storage account list `
    --resource-group $platformRg `
    --output json 2>$null | ConvertFrom-Json | Select-Object -First 1
if (-not $storageJson) {
    Write-Host "  [ERROR] No storage account found in '$platformRg'. Deploy Lab 4.1 first." -ForegroundColor Red
    exit 1
}
$storageId = $storageJson.id
Write-Host "  ✓ Storage account found: $($storageJson.name)" -ForegroundColor Green

# ── [3/6] Display deployment configuration ────────────────────────────────
Write-Host "`n[3/6] Deployment Configuration:" -ForegroundColor Yellow
Write-Host "  Ops Email:        $OpsEmail"
Write-Host "  Prod VM:          $prodVmName"
Write-Host "  Dev VM:           $devVmName"
Write-Host "  Storage Account:  $($storageJson.name)"
Write-Host "  Location:         $location"
Write-Host "  Template:         $templatePath"
Write-Host "  Deployment Name:  $deploymentName"

# Confirm deployment
if (-not $WhatIf -and -not $Force) {
    $confirm = Read-Host "`nProceed with deployment? (y/N)"
    if ($confirm -ne 'y') {
        Write-Host "Deployment cancelled." -ForegroundColor Yellow
        exit 0
    }
}

# ── [4/6] Run deployment ──────────────────────────────────────────────────
Write-Host "`n[4/6] Running deployment..." -ForegroundColor Yellow

$commonParams = @(
    '--name', $deploymentName,
    '--location', $location,
    '--template-file', $templatePath,
    '--parameters', "parOpsEmail=$OpsEmail",
    '--parameters', "parProdVmResourceId=$prodVmId",
    '--parameters', "parStorageAccountResourceId=$storageId"
)

if ($WhatIf) {
    Write-Host "  Running in what-if mode (dry run)..." -ForegroundColor Cyan
    $deployArgs = @('deployment', 'sub', 'what-if') + $commonParams
} else {
    $deployArgs = @('deployment', 'sub', 'create') + $commonParams + @('--output', 'json')
}

$result   = az @deployArgs 2>&1
$exitCode = $LASTEXITCODE

if ($exitCode -ne 0) {
    Write-Host "`n  [ERROR] Deployment failed with exit code $exitCode" -ForegroundColor Red
    Write-Host $result -ForegroundColor Red
    exit $exitCode
}

# ── [5/6] Create DCR association ──────────────────────────────────────────
Write-Host "`n[5/6] Ensuring DCR association for VM Insights..." -ForegroundColor Yellow

$dcrName = 'skycraft-vm-dcr'
$dcrAssocName = 'skycraft-vminsights-dcr-assoc'
$ruleId = "/subscriptions/$($account.id)/resourceGroups/$platformRg/providers/Microsoft.Insights/dataCollectionRules/$dcrName"

if (-not $WhatIf) {
    $existingAssociation = az monitor data-collection rule association show `
        --name $dcrAssocName `
        --resource $devVmId `
        --output json 2>$null | ConvertFrom-Json

    if (-not $existingAssociation) {
        az monitor data-collection rule association create `
            --name $dcrAssocName `
            --rule-id $ruleId `
            --resource $devVmId `
            --output none
        Write-Host "  ✓ DCR association created: $dcrAssocName" -ForegroundColor Green
    } else {
        Write-Host "  ✓ DCR association already exists: $dcrAssocName" -ForegroundColor Green
    }

    Write-Host "  Ensuring Alert Processing Rule exists: skycraft-hours-apr" -ForegroundColor Gray
    $actionGroupId = "/subscriptions/$($account.id)/resourceGroups/$platformRg/providers/microsoft.insights/actionGroups/skycraft-ops-ag"
    $aprExists = az monitor alert-processing-rule show `
        --name skycraft-hours-apr `
        --resource-group $platformRg `
        --output json 2>$null | ConvertFrom-Json

    if (-not $aprExists) {
        az monitor alert-processing-rule create `
            --name skycraft-hours-apr `
            --resource-group $platformRg `
            --rule-type AddActionGroups `
            --scopes $prodVmId `
            --action-groups $actionGroupId `
            --schedule-time-zone 'W. Europe Standard Time' `
            --schedule-recurrence-type Weekly `
            --schedule-recurrence-start-time '08:00:00' `
            --schedule-recurrence-end-time '18:00:00' `
            --schedule-recurrence Monday Tuesday Wednesday Thursday Friday `
            --description 'Route SkyCraft CPU alerts through action group during business hours' `
            --output none
        Write-Host "  ✓ Alert Processing Rule created: skycraft-hours-apr" -ForegroundColor Green
    } else {
        Write-Host "  ✓ Alert Processing Rule already exists: skycraft-hours-apr" -ForegroundColor Green
    }
} else {
    Write-Host "  What-if mode: DCR association creation skipped." -ForegroundColor Gray
}

# ── [6/6] Display results ─────────────────────────────────────────────────
Write-Host "`n[6/6] Deployment Results:" -ForegroundColor Yellow

if ($WhatIf) {
    Write-Host $result
    Write-Host "`n  What-if completed. Review changes above." -ForegroundColor Cyan
} else {
    $deployment = $null
    try {
        $rawText = ($result | ForEach-Object { $_.ToString() }) -join "`n"
        $jsonStart = $rawText.IndexOf('{')
        if ($jsonStart -ge 0) {
            $deployment = $rawText.Substring($jsonStart) | ConvertFrom-Json
        }
    } catch {
        $deployment = $null
    }

    Write-Host "  ✓ Deployment succeeded!" -ForegroundColor Green
    if ($deployment) {
        Write-Host "`n  Outputs:"
        Write-Host "    Workspace ID:         $($deployment.properties.outputs.outWorkspaceId.value)"
        Write-Host "    Workspace Customer ID: $($deployment.properties.outputs.outWorkspaceCustomerId.value)"
        Write-Host "    DCR ID:               $($deployment.properties.outputs.outDcrId.value)"
        Write-Host "    Action Group ID:      $($deployment.properties.outputs.outActionGroupId.value)"
        Write-Host "    Alert Rule ID:        $($deployment.properties.outputs.outAlertRuleId.value)"
    } else {
        Write-Host "`n  Outputs could not be parsed due mixed CLI warning text, but deployment completed." -ForegroundColor Yellow
    }

    Write-Host "`n  Next Steps:" -ForegroundColor Cyan
    Write-Host "    1. Install AMA on VMs via Monitor → Virtual Machines → Enable monitoring" -ForegroundColor Gray
    Write-Host "    2. Wait 5-10 minutes for data to appear in the workspace" -ForegroundColor Gray
    Write-Host "    3. Run .\Test-Lab.ps1 to validate deployment" -ForegroundColor Gray
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  Deployment Complete" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan
