<#
.SYNOPSIS
    Removes Lab 5.1 Azure Monitor & Insights resources.

.DESCRIPTION
    Cleans up Lab 5.1 monitoring resources in the following order:
    1. Metric Alert (skycraft-cpu-alert)
    2. VM Insights DCR association
    3. VM Insights Data Collection Rule (skycraft-vm-dcr)
    4. Action Group (skycraft-ops-ag)
    5. Storage Diagnostic Settings (skycraft-storage-diag)
    6. Log Analytics Workspace (platform-skycraft-swc-law)

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

#Requires -Version 7.0
#Requires -Modules Az.Accounts, Az.Resources, Az.Compute, Az.Storage, Az.OperationalInsights, Az.Monitor

[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter()]
    [ValidateSet('dev', 'prod')]
    [string]$DevEnvironment = 'dev',

    [Parameter()]
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
if ($Force) { $ConfirmPreference = 'None' }

# Configuration
$platformRg      = 'platform-skycraft-swc-rg'
$workspaceName   = 'platform-skycraft-swc-law'
$dcrName         = 'skycraft-vm-dcr'
$dcrAssocName    = 'skycraft-vminsights-dcr-assoc'
$actionGroupName = 'skycraft-ops-ag'
$alertRuleName   = 'skycraft-cpu-alert'
$devVmName       = "$DevEnvironment-skycraft-swc-auth-vm"
$devRgName       = "$DevEnvironment-skycraft-swc-rg"

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  Lab 5.1 - Resource Cleanup" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# Verify login
$context = Get-AzContext
if (-not $context) {
    Write-Host "  [ERROR] Not logged into Azure. Run 'Connect-AzAccount' first." -ForegroundColor Red
    $Host.SetShouldExit(1)
    exit 1
}
$subscriptionId = $context.Subscription.Id

# ── Inventory resources to delete ────────────────────────────────────────
Write-Host "Resources to be deleted:" -ForegroundColor Yellow

$resourcesToDelete = [System.Collections.Generic.List[hashtable]]::new()

# Metric Alert
$alertExists = Get-AzMetricAlertRuleV2 -ResourceGroupName $platformRg -Name $alertRuleName -ErrorAction SilentlyContinue
if ($alertExists) {
    $resourcesToDelete.Add(@{ Type = 'Alert'; Name = $alertRuleName })
    Write-Host "  - Metric Alert: $alertRuleName" -ForegroundColor Gray
}

# DCR Association on dev VM
$devVmExists = Get-AzVM -Name $devVmName -ResourceGroupName $devRgName -ErrorAction SilentlyContinue
if ($devVmExists) {
    $devVmId = $devVmExists.Id
    $assocExists = Get-AzDataCollectionRuleAssociation -ResourceUri $devVmId -AssociationName $dcrAssocName -ErrorAction SilentlyContinue
    if ($assocExists) {
        $resourcesToDelete.Add(@{ Type = 'DCRAssoc'; Name = $dcrAssocName; VmId = $devVmId })
        Write-Host "  - DCR Association: $dcrAssocName (on $devVmName)" -ForegroundColor Gray
    }
}

# Data Collection Rule
$dcrId = "/subscriptions/$subscriptionId/resourceGroups/$platformRg/providers/Microsoft.Insights/dataCollectionRules/$dcrName"
$dcrExists = Get-AzResource -ResourceId $dcrId -ErrorAction SilentlyContinue
if ($dcrExists) {
    $resourcesToDelete.Add(@{ Type = 'DCR'; Name = $dcrName })
    Write-Host "  - Data Collection Rule: $dcrName" -ForegroundColor Gray
}

# Action Group
$agExists = Get-AzActionGroup -ResourceGroupName $platformRg -Name $actionGroupName -ErrorAction SilentlyContinue
if ($agExists) {
    $resourcesToDelete.Add(@{ Type = 'ActionGroup'; Name = $actionGroupName })
    Write-Host "  - Action Group: $actionGroupName" -ForegroundColor Gray
}

# Storage Diagnostic Settings (scoped to blobServices/default)
$storageAcct = Get-AzStorageAccount -ResourceGroupName $platformRg -ErrorAction SilentlyContinue | Select-Object -First 1
if ($storageAcct) {
    $blobServiceId = "$($storageAcct.Id)/blobServices/default"
    $diagExists = Get-AzDiagnosticSetting -ResourceId $blobServiceId -Name 'skycraft-storage-diag' -ErrorAction SilentlyContinue
    if ($diagExists) {
        $resourcesToDelete.Add(@{ Type = 'StorageDiag'; Name = 'skycraft-storage-diag'; BlobServiceId = $blobServiceId })
        Write-Host "  - Storage Diagnostic Settings: skycraft-storage-diag" -ForegroundColor Gray
    }
}

# Log Analytics Workspace
$wsExists = Get-AzOperationalInsightsWorkspace -ResourceGroupName $platformRg -Name $workspaceName -ErrorAction SilentlyContinue
if ($wsExists) {
    $resourcesToDelete.Add(@{ Type = 'Workspace'; Name = $workspaceName })
    Write-Host "  - Log Analytics Workspace: $workspaceName" -ForegroundColor Gray
}

if ($resourcesToDelete.Count -eq 0) {
    Write-Host "`nNo Lab 5.1 resources found to delete." -ForegroundColor Green
    exit 0
}

# ── Delete resources in dependency order ──────────────────────────────────
Write-Host "`nDeleting resources..." -ForegroundColor Yellow

# 1. Metric Alert
foreach ($r in $resourcesToDelete | Where-Object { $_.Type -eq 'Alert' }) {
    if ($PSCmdlet.ShouldProcess($r.Name, 'Remove Metric Alert')) {
        Write-Host "  Deleting Metric Alert: $($r.Name)..." -ForegroundColor Gray
        try {
            Remove-AzMetricAlertRuleV2 -ResourceGroupName $platformRg -Name $r.Name -ErrorAction Stop | Out-Null
            Write-Host "  ✓ Deleted" -ForegroundColor Green
        } catch {
            Write-Host "  [WARNING] Could not delete: $_" -ForegroundColor Yellow
        }
    }
}

# 2. DCR Association
foreach ($r in $resourcesToDelete | Where-Object { $_.Type -eq 'DCRAssoc' }) {
    if ($PSCmdlet.ShouldProcess($r.Name, 'Remove DCR Association')) {
        Write-Host "  Deleting DCR Association: $($r.Name)..." -ForegroundColor Gray
        try {
            Remove-AzDataCollectionRuleAssociation -ResourceUri $r.VmId -AssociationName $r.Name -ErrorAction Stop | Out-Null
            Write-Host "  ✓ Deleted" -ForegroundColor Green
        } catch {
            Write-Host "  [WARNING] Could not delete: $_" -ForegroundColor Yellow
        }
    }
}

# 3. Data Collection Rule
foreach ($r in $resourcesToDelete | Where-Object { $_.Type -eq 'DCR' }) {
    if ($PSCmdlet.ShouldProcess($r.Name, 'Remove Data Collection Rule')) {
        Write-Host "  Deleting Data Collection Rule: $($r.Name)..." -ForegroundColor Gray
        try {
            $dcrResourceId = "/subscriptions/$subscriptionId/resourceGroups/$platformRg/providers/Microsoft.Insights/dataCollectionRules/$($r.Name)"
            Remove-AzResource -ResourceId $dcrResourceId -Force -ErrorAction Stop | Out-Null
            Write-Host "  ✓ Deleted" -ForegroundColor Green
        } catch {
            Write-Host "  [WARNING] Could not delete: $_" -ForegroundColor Yellow
        }
    }
}

# 4. Action Group
foreach ($r in $resourcesToDelete | Where-Object { $_.Type -eq 'ActionGroup' }) {
    if ($PSCmdlet.ShouldProcess($r.Name, 'Remove Action Group')) {
        Write-Host "  Deleting Action Group: $($r.Name)..." -ForegroundColor Gray
        try {
            Remove-AzActionGroup -ResourceGroupName $platformRg -Name $r.Name -ErrorAction Stop | Out-Null
            Write-Host "  ✓ Deleted" -ForegroundColor Green
        } catch {
            Write-Host "  [WARNING] Could not delete: $_" -ForegroundColor Yellow
        }
    }
}

# 5. Storage Diagnostic Settings
foreach ($r in $resourcesToDelete | Where-Object { $_.Type -eq 'StorageDiag' }) {
    if ($PSCmdlet.ShouldProcess($r.Name, 'Remove Storage Diagnostic Settings')) {
        Write-Host "  Deleting Storage Diagnostic Settings: $($r.Name)..." -ForegroundColor Gray
        try {
            Remove-AzDiagnosticSetting -ResourceId $r.BlobServiceId -Name $r.Name -ErrorAction Stop | Out-Null
            Write-Host "  ✓ Deleted" -ForegroundColor Green
        } catch {
            Write-Host "  [WARNING] Could not delete: $_" -ForegroundColor Yellow
        }
    }
}

# 6. Log Analytics Workspace (soft-delete by default — 14 days recovery window)
foreach ($r in $resourcesToDelete | Where-Object { $_.Type -eq 'Workspace' }) {
    if ($PSCmdlet.ShouldProcess($r.Name, 'Remove Log Analytics Workspace')) {
        Write-Host "  Deleting Log Analytics Workspace: $($r.Name)..." -ForegroundColor Gray
        try {
            Remove-AzOperationalInsightsWorkspace -ResourceGroupName $platformRg -Name $r.Name -Force -ErrorAction Stop | Out-Null
            Write-Host "  ✓ Deleted (soft-delete: 14-day recovery window)" -ForegroundColor Green
            Write-Host "    To permanently purge: Remove-AzOperationalInsightsWorkspace -ResourceGroupName $platformRg -Name $($r.Name) -ForceDelete" -ForegroundColor Gray
        } catch {
            Write-Host "  [WARNING] Could not delete: $_" -ForegroundColor Yellow
        }
    }
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  Cleanup Complete" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  VMs, VNets, Storage Accounts were NOT deleted." -ForegroundColor Gray
Write-Host "  Remove the 'SkyCraft-Ops' dashboard manually in the Azure Portal." -ForegroundColor Gray
Write-Host "========================================`n" -ForegroundColor Cyan
