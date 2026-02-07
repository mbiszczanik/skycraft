<#
.SYNOPSIS
    Removes Lab 4.3 Resources
.DESCRIPTION
    Deletes the resource group and all contained resources.
.NOTES
    Project: SkyCraft
    Author: SkyCraft Team
    Date: 2026-02-07
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$ResourceGroupName = 'prod-skycraft-swc-rg'
)

Write-Host "=== Lab 4.3: Cleaning Up ===" -ForegroundColor Cyan

# 1. Verify Connection
if (-not (Get-AzContext)) {
    Write-Host "Not logged in." -ForegroundColor Red; exit 1
}

# 2. Confirm Deletion
$confirm = Read-Host "Are you sure you want to delete Resource Group '$ResourceGroupName'? (y/n)"
if ($confirm -ne 'y') {
    Write-Host "Cleanup cancelled." -ForegroundColor Gray
    exit 0
}

# 3. Delete Resource Group
try {
    Write-Host "Deleting Resource Group '$ResourceGroupName'..." -ForegroundColor Yellow
    Remove-AzResourceGroup -Name $ResourceGroupName -Force -ErrorAction Stop
    Write-Host "  -> Resource Group deleted successfully." -ForegroundColor Green
}
catch {
    Write-Host "  -> [ERROR] Failed to delete Resource Group." -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
}
