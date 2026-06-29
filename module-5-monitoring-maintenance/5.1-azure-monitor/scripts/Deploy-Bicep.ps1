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
    - Storage Account Diagnostic Settings (skycraft-storage-diag)

    Prerequisites: Lab 3.2 (at least one VM, dev preferred) and Lab 4.1 (Storage) must be deployed.

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

#Requires -Version 7.0
#Requires -Modules Az.Accounts, Az.Resources, Az.Compute, Az.Storage, Az.Monitor

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
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

$context = Get-AzContext
if (-not $context) {
    Write-Host "  [ERROR] Not logged into Azure. Run 'Connect-AzAccount' first." -ForegroundColor Red
    exit 1
}
Write-Host "  ✓ Logged in as: $($context.Account.Id)" -ForegroundColor Green

# Verify Az PowerShell module version
$azVersion = (Get-Module -ListAvailable -Name Az.Accounts | Sort-Object Version -Descending | Select-Object -First 1).Version
Write-Host "  ✓ Az PowerShell (Az.Accounts) version: $azVersion" -ForegroundColor Green

# ── [2/6] Resolve resource IDs ────────────────────────────────────────────
Write-Host "`n[2/6] Resolving existing resource IDs..." -ForegroundColor Yellow

# Platform resource group
$platformRgExists = Get-AzResourceGroup -Name $platformRg -ErrorAction SilentlyContinue
if (-not $platformRgExists) {
    Write-Host "  [ERROR] Resource group '$platformRg' not found. Complete earlier labs first." -ForegroundColor Red
    exit 1
}
Write-Host "  ✓ Platform RG found: $platformRg" -ForegroundColor Green

# VM to monitor (alert + DCR target).
# Lab guide 5.1 prerequisite is "at least one VM should be running" and the
# hands-on steps (VM Insights, CPU>80% alert) use the dev VM. So prefer the dev
# VM and fall back to prod — only fail if neither exists.
$devVmName = "$DevEnvironment-skycraft-swc-auth-vm"
$devRgName  = "$DevEnvironment-skycraft-swc-rg"
$prodVmName = "$ProdEnvironment-skycraft-swc-auth-vm"
$prodRgName = "$ProdEnvironment-skycraft-swc-rg"

$devVmObj  = Get-AzVM -Name $devVmName  -ResourceGroupName $devRgName  -ErrorAction SilentlyContinue
$prodVmObj = Get-AzVM -Name $prodVmName -ResourceGroupName $prodRgName -ErrorAction SilentlyContinue

$monitoredVm = if ($devVmObj) { $devVmObj } elseif ($prodVmObj) { $prodVmObj } else { $null }
if (-not $monitoredVm) {
    Write-Host "  [ERROR] No SkyCraft VM found (checked '$devVmName' and '$prodVmName'). Deploy Lab 3.2 first (at least one VM)." -ForegroundColor Red
    exit 1
}
Write-Host "  ✓ Monitored VM: $($monitoredVm.Name)" -ForegroundColor Green

# Alert target = the VM we monitor; DCR association = dev VM when present, else same VM.
$prodVmId = $monitoredVm.Id
$devVmId  = if ($devVmObj) { $devVmObj.Id } else { $monitoredVm.Id }

# Platform storage account
$storageObj = Get-AzStorageAccount -ResourceGroupName $platformRg -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $storageObj) {
    Write-Host "  [ERROR] No storage account found in '$platformRg'. Deploy Lab 4.1 first." -ForegroundColor Red
    exit 1
}
$storageId = $storageObj.Id
Write-Host "  ✓ Storage account found: $($storageObj.StorageAccountName)" -ForegroundColor Green

# ── [3/6] Display deployment configuration ────────────────────────────────
Write-Host "`n[3/6] Deployment Configuration:" -ForegroundColor Yellow
Write-Host "  Ops Email:        $OpsEmail"
Write-Host "  Monitored VM:     $($monitoredVm.Name)"
Write-Host "  Dev VM:           $devVmName"
Write-Host "  Storage Account:  $($storageObj.StorageAccountName)"
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

$deployParams = @{
    Name                        = $deploymentName
    Location                    = $location
    TemplateFile                = $templatePath
    parOpsEmail                 = $OpsEmail
    parProdVmResourceId         = $prodVmId
    parStorageAccountResourceId = $storageId
    ErrorAction                 = 'Stop'
}

$deployment = $null
$result     = $null

if ($WhatIf) {
    Write-Host "  Running in what-if mode (dry run)..." -ForegroundColor Cyan
    try { $result = Get-AzSubscriptionDeploymentWhatIfResult @deployParams }
    catch { Write-Host "`n  [ERROR] What-if failed: $($_.Exception.Message)" -ForegroundColor Red; exit 1 }
}
else {
    # A freshly-created Log Analytics workspace needs a minute before its
    # InsightsMetrics/Syslog tables exist; the DCR deploy fails with
    # InvalidOutputTable until then. Retry on that transient error.
    $maxAttempts = 4
    for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
        try {
            $deployment = New-AzSubscriptionDeployment @deployParams
            break
        }
        catch {
            $msg = $_.Exception.Message
            if ($attempt -lt $maxAttempts -and ($msg -match 'InvalidOutputTable' -or $msg -match 'not available for destination' -or $msg -match 'InvalidPayload')) {
                Write-Host "  [RETRY $attempt/$($maxAttempts-1)] Workspace tables not ready yet; waiting 45s..." -ForegroundColor DarkYellow
                Start-Sleep -Seconds 45
            }
            else {
                Write-Host "`n  [ERROR] Deployment failed: $msg" -ForegroundColor Red
                exit 1
            }
        }
    }
}

# ── [5/6] Create DCR association ──────────────────────────────────────────
Write-Host "`n[5/6] Ensuring DCR association for VM Insights..." -ForegroundColor Yellow

$dcrName = 'skycraft-vm-dcr'
$dcrAssocName = 'skycraft-vminsights-dcr-assoc'
$ruleId = "/subscriptions/$($context.Subscription.Id)/resourceGroups/$platformRg/providers/Microsoft.Insights/dataCollectionRules/$dcrName"

if (-not $WhatIf) {
    $existingAssociation = Get-AzDataCollectionRuleAssociation -ResourceUri $devVmId -AssociationName $dcrAssocName -ErrorAction SilentlyContinue

    if (-not $existingAssociation) {
        New-AzDataCollectionRuleAssociation -ResourceUri $devVmId -AssociationName $dcrAssocName -DataCollectionRuleId $ruleId | Out-Null
        Write-Host "  ✓ DCR association created: $dcrAssocName" -ForegroundColor Green
    } else {
        Write-Host "  ✓ DCR association already exists: $dcrAssocName" -ForegroundColor Green
    }
} else {
    Write-Host "  What-if mode: DCR association creation skipped." -ForegroundColor Gray
}

# ── [6/6] Display results ─────────────────────────────────────────────────
Write-Host "`n[6/6] Deployment Results:" -ForegroundColor Yellow

if ($WhatIf) {
    $result
    Write-Host "`n  What-if completed. Review changes above." -ForegroundColor Cyan
} else {
    Write-Host "  ✓ Deployment succeeded!" -ForegroundColor Green
    if ($deployment -and $deployment.Outputs) {
        Write-Host "`n  Outputs:"
        Write-Host "    Workspace ID:         $($deployment.Outputs['outWorkspaceId'].Value)"
        Write-Host "    Workspace Customer ID: $($deployment.Outputs['outWorkspaceCustomerId'].Value)"
        Write-Host "    DCR ID:               $($deployment.Outputs['outDcrId'].Value)"
        Write-Host "    Action Group ID:      $($deployment.Outputs['outActionGroupId'].Value)"
        Write-Host "    Alert Rule ID:        $($deployment.Outputs['outAlertRuleId'].Value)"
    } else {
        Write-Host "`n  Outputs could not be parsed, but deployment completed." -ForegroundColor Yellow
    }

    Write-Host "`n  Next Steps:" -ForegroundColor Cyan
    Write-Host "    1. Install AMA on VMs via Monitor → Virtual Machines → Enable monitoring" -ForegroundColor Gray
    Write-Host "    2. Wait 5-10 minutes for data to appear in the workspace" -ForegroundColor Gray
    Write-Host "    3. Run .\Test-Lab.ps1 to validate deployment" -ForegroundColor Gray
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  Deployment Complete" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan
