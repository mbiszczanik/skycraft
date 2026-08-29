<#
.SYNOPSIS
    Removes Lab 4.3 Resources
.DESCRIPTION
    Removes only the two Azure File Shares created by Lab 4.3 (skycraft-config, skycraft-shared)
    from the storage account of the selected environment. Does NOT delete the shared
    <env>-skycraft-swc-rg resource group, which contains Lab 4.1 storage required by Labs 4.2 and 4.4.
.PARAMETER Environment
    Environment to clean up (prod, dev or platform). Default: prod. Matches Deploy-Bicep.ps1.
.PARAMETER Force
    Skip confirmation prompt.
.EXAMPLE
    .\Remove-LabResource.ps1 -Force
    Removes both shares from prodskycraftswcsa.
.EXAMPLE
    .\Remove-LabResource.ps1 -Environment dev -Force
    Removes both shares from devskycraftswcsa.
.NOTES
    Project: SkyCraft
    Author: SkyCraft
    Version: 2.1.0
    Date: 2026-08-28
#>

#Requires -Version 7.0
#Requires -Modules Az.Accounts, Az.Storage

[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory = $false)]
    [ValidateSet('prod', 'dev', 'platform')]
    [string]$Environment = 'prod',

    [Parameter(Mandatory = $false)]
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
if ($Force) { $ConfirmPreference = 'None' }

$resourceGroupName  = "$Environment-skycraft-swc-rg"
$storageAccountName = "${Environment}skycraftswcsa"
$subscriptionId     = (Get-AzContext).Subscription.Id

Write-Host "=== Lab 4.3: Cleaning Up File Shares ($Environment) ===" -ForegroundColor Cyan

# 1. Verify Connection
if (-not (Get-AzContext)) {
    Write-Host " [ERROR] Not logged in. Please run Connect-AzAccount." -ForegroundColor Red; $Host.SetShouldExit(1); exit 1
}

# 2. Verify storage account exists (do not attempt to delete the RG)
$sa = Get-AzStorageAccount -ResourceGroupName $resourceGroupName -Name $storageAccountName -ErrorAction SilentlyContinue
if (-not $sa) {
    Write-Host " [INFO] Storage account '$storageAccountName' not found. Nothing to clean up." -ForegroundColor Gray
    exit 0
}

# 3. Remove the two file shares created by this lab
$sharesToRemove = @('skycraft-config', 'skycraft-shared')
foreach ($shareName in $sharesToRemove) {
    $shareId = "/subscriptions/$subscriptionId/resourceGroups/$resourceGroupName/providers/Microsoft.Storage/storageAccounts/$storageAccountName/fileServices/default/shares/$shareName"
    $shareExists = Get-AzResource -ResourceId $shareId -ErrorAction SilentlyContinue
    if ($shareExists) {
        Write-Host "Removing file share '$shareName'..." -ForegroundColor Yellow
        try {
            if ($PSCmdlet.ShouldProcess($shareName, 'Remove file share')) {
                Remove-AzResource -ResourceId $shareId -Force -ErrorAction Stop | Out-Null
                Write-Host "  -> Successfully removed '$shareName'." -ForegroundColor Green
            }
        } catch {
            Write-Host "  -> [WARNING] Could not remove '$shareName': $($_.Exception.Message)" -ForegroundColor Yellow
        }
    } else {
        Write-Host "  -> Share '$shareName' not found, skipping." -ForegroundColor Gray
    }
}

Write-Host "`nLab 4.3 Cleanup Complete." -ForegroundColor Cyan
Write-Host "Note: The shared '$resourceGroupName' resource group and storage account were preserved for Labs 4.2 and 4.4." -ForegroundColor Gray
