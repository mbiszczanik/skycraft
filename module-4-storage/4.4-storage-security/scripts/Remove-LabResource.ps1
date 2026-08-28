<#
.SYNOPSIS
    Removes Lab 4.4 Security Configuration
.DESCRIPTION
    Reverts storage firewall to allow-all, removes the dev-assets container,
    and cleans up RBAC role assignments created during the lab.
    Does NOT delete the storage account (owned by Lab 4.1) and does NOT remove the
    'Microsoft.Storage' service endpoint from WorldSubnet (owned by Lab 2.2).
.PARAMETER Environment
    The environment to clean up (prod or dev). Default: prod.
.PARAMETER Force
    Skip confirmation prompt.
.EXAMPLE
    .\Remove-LabResource.ps1 -Environment prod -Force
.NOTES
    Project: SkyCraft
    Author: SkyCraft
    Version: 2.0.0
    Date: 2026-08-28
#>

#Requires -Version 7.0
#Requires -Modules Az.Accounts, Az.Resources, Az.Storage

[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory = $false)]
    [ValidateSet('prod', 'dev')]
    [string]$Environment = 'prod',

    [Parameter(Mandatory = $false)]
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
if ($Force) { $ConfirmPreference = 'None' }

$resourceGroupName = "$Environment-skycraft-swc-rg"
$storageAccountName = "${Environment}skycraftswcsa"
$vnetName = "$Environment-skycraft-swc-vnet"

Write-Host "=== Lab 4.4: Cleaning Up Security Configuration ===" -ForegroundColor Cyan

# 1. Verify Connection
if (-not (Get-AzContext)) {
    Write-Host " [ERROR] Not logged in. Please run Connect-AzAccount." -ForegroundColor Red; exit 1
}

# 3. Revert Storage Firewall to Allow
if ($PSCmdlet.ShouldProcess($storageAccountName, 'Revert storage firewall default action to Allow')) {
    try {
        Write-Host "Reverting storage firewall to 'Allow' default..." -ForegroundColor Yellow
        Update-AzStorageAccountNetworkRuleSet -ResourceGroupName $resourceGroupName `
            -Name $storageAccountName `
            -DefaultAction Allow -ErrorAction Stop
        Write-Host "  -> Firewall reverted to 'Allow'." -ForegroundColor Green
    }
    catch {
        Write-Host "  -> [ERROR] Failed to revert firewall." -ForegroundColor Red
        Write-Host $_.Exception.Message -ForegroundColor Red
    }
}

# 4. Remove dev-assets container
if ($PSCmdlet.ShouldProcess('dev-assets', 'Remove storage container')) {
    try {
        Write-Host "Removing 'dev-assets' container..." -ForegroundColor Yellow
        $sa = Get-AzStorageAccount -ResourceGroupName $resourceGroupName -Name $storageAccountName -ErrorAction Stop
        Remove-AzStorageContainer -Name 'dev-assets' -Context $sa.Context -Force -ErrorAction Stop
        Write-Host "  -> Container 'dev-assets' removed." -ForegroundColor Green
    }
    catch {
        Write-Host "  -> [INFO] Container 'dev-assets' not found or already removed." -ForegroundColor Gray
    }
}

# 5. Remove RBAC assignments (Storage Blob Data Contributor)
if ($PSCmdlet.ShouldProcess($storageAccountName, "Remove 'Storage Blob Data Contributor' role assignments")) {
    try {
        Write-Host "Removing 'Storage Blob Data Contributor' role assignments..." -ForegroundColor Yellow
        $storageId = (Get-AzStorageAccount -ResourceGroupName $resourceGroupName -Name $storageAccountName).Id
        $assignments = Get-AzRoleAssignment -Scope $storageId |
            Where-Object RoleDefinitionName -eq 'Storage Blob Data Contributor'

        if ($assignments) {
            foreach ($assignment in $assignments) {
                Remove-AzRoleAssignment -ObjectId $assignment.ObjectId `
                    -RoleDefinitionName 'Storage Blob Data Contributor' `
                    -Scope $storageId -ErrorAction Stop
                Write-Host "  -> Removed assignment for '$($assignment.DisplayName)'." -ForegroundColor Green
            }
        }
        else {
            Write-Host "  -> [INFO] No 'Storage Blob Data Contributor' assignments found." -ForegroundColor Gray
        }
    }
    catch {
        Write-Host "  -> [ERROR] Failed to remove RBAC assignments." -ForegroundColor Red
        Write-Host $_.Exception.Message -ForegroundColor Red
    }
}

# 6. The Microsoft.Storage service endpoint on WorldSubnet is Lab 2.2 state, not Lab 4.4 state:
# Lab 2.2 sets it on WorldSubnet and DatabaseSubnet, and its Test-Lab.ps1 asserts it. Removing it
# here silently regressed Module 2 on every Module 4 cleanup, so it is deliberately left in place.
Write-Host "`n[INFO] Leaving the 'Microsoft.Storage' service endpoint on '$vnetName/WorldSubnet' in place." -ForegroundColor Gray
Write-Host "       It belongs to Lab 2.2; remove it with that lab's cleanup if you want it gone." -ForegroundColor Gray

Write-Host "`nCleanup Complete." -ForegroundColor Cyan
