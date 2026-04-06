<#
.SYNOPSIS
    Removes Lab 5.1 Azure Monitor & Insights resources.

.DESCRIPTION
    Cleans up Lab 5.1 monitoring resources in the following order:
    1. Alert Processing Rule (skycraft-hours-apr)
    2. Metric Alert (skycraft-cpu-alert)
    3. VM Insights DCR association
    4. VM Insights Data Collection Rule (skycraft-vm-dcr)
    5. Action Group (skycraft-ops-ag)
    6. Storage Diagnostic Settings (skycraft-storage-diag)
    7. Log Analytics Workspace (platform-skycraft-swc-law)

    Note: This does NOT remove VMs, VNets, or Storage Accounts from earlier labs.
    The Azure Dashboard (SkyCraft-Ops) must be removed manually via the Azure Portal.

.PARAMETER DevEnvironment
    Dev environment prefix to locate the dev VM for DCR association removal. Default: dev

.PARAMETER Force
    Skip confirmation prompts.

.EXAMPLE
    .\Remove-LabResource.ps1

.EXAMPLE
    .\Remove-LabResource.ps1 -Force

.NOTES
    Project: SkyCraft
    Author: SkyCraft
    Date: 2026-04-06
#>

[CmdletBinding()]
param(
    [Parameter()]
    [ValidateSet('dev', 'prod')]
    [string]$DevEnvironment = 'dev',

    [Parameter()]
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

# Configuration
$platformRg      = 'platform-skycraft-swc-rg'
$workspaceName   = 'platform-skycraft-swc-law'
$dcrName         = 'skycraft-vm-dcr'
$dcrAssocName    = 'skycraft-vminsights-dcr-assoc'
$actionGroupName = 'skycraft-ops-ag'
$alertRuleName   = 'skycraft-cpu-alert'
$aprName         = 'skycraft-hours-apr'
$devVmName       = "$DevEnvironment-skycraft-swc-auth-vm"
$devRgName       = "$DevEnvironment-skycraft-swc-rg"

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  Lab 5.1 - Resource Cleanup" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# Verify login
$account = az account show --output json 2>$null | ConvertFrom-Json
if (-not $account) {
    Write-Host "  [ERROR] Not logged into Azure CLI. Run 'az login' first." -ForegroundColor Red
    exit 1
}
$subscriptionId = $account.id

# Allow non-interactive installation of required Azure CLI extensions.
az config set extension.use_dynamic_install=yes_without_prompt --only-show-errors | Out-Null

# ── Inventory resources to delete ────────────────────────────────────────
Write-Host "Resources to be deleted:" -ForegroundColor Yellow

$resourcesToDelete = [System.Collections.Generic.List[hashtable]]::new()

# Alert Processing Rule
$aprExists = az rest `
    --method GET `
    --url "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$platformRg/providers/Microsoft.AlertsManagement/alertProcessingRules/$($aprName)?api-version=2021-08-08" `
    --output json 2>$null | ConvertFrom-Json
if ($aprExists) {
    $resourcesToDelete.Add(@{ Type = 'APR'; Name = $aprName })
    Write-Host "  - Alert Processing Rule: $aprName" -ForegroundColor Gray
}

# Metric Alert
$alertExists = az monitor metrics alert show `
    --name $alertRuleName --resource-group $platformRg --output json 2>$null | ConvertFrom-Json
if ($alertExists) {
    $resourcesToDelete.Add(@{ Type = 'Alert'; Name = $alertRuleName })
    Write-Host "  - Metric Alert: $alertRuleName" -ForegroundColor Gray
}

# DCR Association on dev VM
$devVmExists = az vm show --name $devVmName --resource-group $devRgName --output json 2>$null | ConvertFrom-Json
if ($devVmExists) {
    $devVmId = $devVmExists.id
    $assocExists = az monitor data-collection rule association show `
        --name $dcrAssocName `
        --resource $devVmId `
        --output json 2>$null | ConvertFrom-Json
    if ($assocExists) {
        $resourcesToDelete.Add(@{ Type = 'DCRAssoc'; Name = $dcrAssocName; VmId = $devVmId })
        Write-Host "  - DCR Association: $dcrAssocName (on $devVmName)" -ForegroundColor Gray
    }
}

# Data Collection Rule
$dcrExists = az monitor data-collection rule show `
    --name $dcrName --resource-group $platformRg --output json 2>$null | ConvertFrom-Json
if ($dcrExists) {
    $resourcesToDelete.Add(@{ Type = 'DCR'; Name = $dcrName })
    Write-Host "  - Data Collection Rule: $dcrName" -ForegroundColor Gray
}

# Action Group
$agExists = az monitor action-group show `
    --name $actionGroupName --resource-group $platformRg --output json 2>$null | ConvertFrom-Json
if ($agExists) {
    $resourcesToDelete.Add(@{ Type = 'ActionGroup'; Name = $actionGroupName })
    Write-Host "  - Action Group: $actionGroupName" -ForegroundColor Gray
}

# Storage Diagnostic Settings (scoped to blobServices/default)
$storageAcct = az storage account list `
    --resource-group $platformRg `
    --output json 2>$null | ConvertFrom-Json | Select-Object -First 1
if ($storageAcct) {
    $blobServiceId = "$($storageAcct.id)/blobServices/default"
    $diagExists = az monitor diagnostic-settings show `
        --name 'skycraft-storage-diag' `
        --resource $blobServiceId `
        --output json 2>$null | ConvertFrom-Json
    if ($diagExists) {
        $resourcesToDelete.Add(@{ Type = 'StorageDiag'; Name = 'skycraft-storage-diag'; BlobServiceId = $blobServiceId })
        Write-Host "  - Storage Diagnostic Settings: skycraft-storage-diag" -ForegroundColor Gray
    }
}

# Log Analytics Workspace
$wsExists = az monitor log-analytics workspace show `
    --workspace-name $workspaceName --resource-group $platformRg --output json 2>$null | ConvertFrom-Json
if ($wsExists) {
    $resourcesToDelete.Add(@{ Type = 'Workspace'; Name = $workspaceName })
    Write-Host "  - Log Analytics Workspace: $workspaceName" -ForegroundColor Gray
}

if ($resourcesToDelete.Count -eq 0) {
    Write-Host "`nNo Lab 5.1 resources found to delete." -ForegroundColor Green
    exit 0
}

# ── Confirm deletion ──────────────────────────────────────────────────────
if (-not $Force) {
    Write-Host "`n⚠️  This will permanently delete the above resources." -ForegroundColor Yellow
    Write-Host "  Note: The 'SkyCraft-Ops' dashboard must be removed manually in the Azure Portal." -ForegroundColor Gray
    $confirm = Read-Host "Are you sure? Type 'DELETE' to confirm"
    if ($confirm -ne 'DELETE') {
        Write-Host "Cleanup cancelled." -ForegroundColor Yellow
        exit 0
    }
}

# ── Delete resources in dependency order ──────────────────────────────────
Write-Host "`nDeleting resources..." -ForegroundColor Yellow

# 1. Alert Processing Rule
foreach ($r in $resourcesToDelete | Where-Object { $_.Type -eq 'APR' }) {
    Write-Host "  Deleting Alert Processing Rule: $($r.Name)..." -ForegroundColor Gray
    try {
        az rest `
            --method DELETE `
            --url "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$platformRg/providers/Microsoft.AlertsManagement/alertProcessingRules/$($r.Name)?api-version=2021-08-08" | Out-Null
        Write-Host "  ✓ Deleted" -ForegroundColor Green
    } catch {
        Write-Host "  [WARNING] Could not delete: $_" -ForegroundColor Yellow
    }
}

# 2. Metric Alert
foreach ($r in $resourcesToDelete | Where-Object { $_.Type -eq 'Alert' }) {
    Write-Host "  Deleting Metric Alert: $($r.Name)..." -ForegroundColor Gray
    try {
        az monitor metrics alert delete `
            --name $r.Name --resource-group $platformRg | Out-Null
        Write-Host "  ✓ Deleted" -ForegroundColor Green
    } catch {
        Write-Host "  [WARNING] Could not delete: $_" -ForegroundColor Yellow
    }
}

# 3. DCR Association
foreach ($r in $resourcesToDelete | Where-Object { $_.Type -eq 'DCRAssoc' }) {
    Write-Host "  Deleting DCR Association: $($r.Name)..." -ForegroundColor Gray
    try {
        az monitor data-collection rule association delete `
            --name $r.Name --resource $r.VmId --yes | Out-Null
        Write-Host "  ✓ Deleted" -ForegroundColor Green
    } catch {
        Write-Host "  [WARNING] Could not delete: $_" -ForegroundColor Yellow
    }
}

# 4. Data Collection Rule
foreach ($r in $resourcesToDelete | Where-Object { $_.Type -eq 'DCR' }) {
    Write-Host "  Deleting Data Collection Rule: $($r.Name)..." -ForegroundColor Gray
    try {
        az monitor data-collection rule delete `
            --name $r.Name --resource-group $platformRg --yes | Out-Null
        Write-Host "  ✓ Deleted" -ForegroundColor Green
    } catch {
        Write-Host "  [WARNING] Could not delete: $_" -ForegroundColor Yellow
    }
}

# 5. Action Group
foreach ($r in $resourcesToDelete | Where-Object { $_.Type -eq 'ActionGroup' }) {
    Write-Host "  Deleting Action Group: $($r.Name)..." -ForegroundColor Gray
    try {
        az monitor action-group delete `
            --name $r.Name --resource-group $platformRg | Out-Null
        Write-Host "  ✓ Deleted" -ForegroundColor Green
    } catch {
        Write-Host "  [WARNING] Could not delete: $_" -ForegroundColor Yellow
    }
}

# 6. Storage Diagnostic Settings
foreach ($r in $resourcesToDelete | Where-Object { $_.Type -eq 'StorageDiag' }) {
    Write-Host "  Deleting Storage Diagnostic Settings: $($r.Name)..." -ForegroundColor Gray
    try {
        az monitor diagnostic-settings delete `
            --name $r.Name `
            --resource $r.BlobServiceId | Out-Null
        Write-Host "  ✓ Deleted" -ForegroundColor Green
    } catch {
        Write-Host "  [WARNING] Could not delete: $_" -ForegroundColor Yellow
    }
}

# 7. Log Analytics Workspace (soft-delete by default — 14 days recovery window)
foreach ($r in $resourcesToDelete | Where-Object { $_.Type -eq 'Workspace' }) {
    Write-Host "  Deleting Log Analytics Workspace: $($r.Name)..." -ForegroundColor Gray
    try {
        az monitor log-analytics workspace delete `
            --workspace-name $r.Name --resource-group $platformRg --yes --force | Out-Null
        Write-Host "  ✓ Deleted (soft-delete: 14-day recovery window)" -ForegroundColor Green
        Write-Host "    To permanently purge: az monitor log-analytics workspace purge --workspace-name $($r.Name) --resource-group $platformRg" -ForegroundColor Gray
    } catch {
        Write-Host "  [WARNING] Could not delete: $_" -ForegroundColor Yellow
    }
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  Cleanup Complete" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  VMs, VNets, Storage Accounts were NOT deleted." -ForegroundColor Gray
Write-Host "  Remove the 'SkyCraft-Ops' dashboard manually in the Azure Portal." -ForegroundColor Gray
Write-Host "========================================`n" -ForegroundColor Cyan
