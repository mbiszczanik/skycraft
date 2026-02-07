<#
.SYNOPSIS
    Cleans up Lab 4.2 Resources (Containers, Policies).

.DESCRIPTION
    Removes the specific containers and configurations created in Lab 4.2.
    Does NOT delete the storage accounts themselves.
    Reverts Versioning and Public Access settings to Lab 4.1 defaults.

.PARAMETER Force
    Skip confirmation prompt.

.EXAMPLE
    .\Remove-LabResource.ps1 -Force

.NOTES
    Project: SkyCraft
    Author: SkyCraft
#>

[CmdletBinding()]
param(
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
$ProdRgName = 'prod-skycraft-swc-rg'
$ProdSaName = 'prodskycraftswcsa'
$DevRgName = 'dev-skycraft-swc-rg'
$DevSaName = 'devskycraftswcsa'

if (-not $Force) {
    echo "This will DELETE all containers created in Lab 4.2 (game-assets, player-backups, etc.) and reset storage configuration."
    $confirm = Read-Host "Are you sure? (y/n)"
    if ($confirm -ne 'y') { exit }
}

Write-Host "=== Lab 4.2 Cleanup ===" -ForegroundColor Cyan

# 1. Clean Production
try {
    Write-Host "Cleaning Production ($ProdSaName)..." -ForegroundColor Yellow
    $ctx = (Get-AzStorageAccount -ResourceGroupName $ProdRgName -Name $ProdSaName).Context

    # Remove Containers
    $containers = @('game-assets', 'player-backups', 'server-config', 'game-logs')
    foreach ($c in $containers) {
        if (Get-AzStorageContainer -Context $ctx -Name $c -ErrorAction SilentlyContinue) {
            Remove-AzStorageContainer -Context $ctx -Name $c -Force
            Write-Host "  Deleted container: $c" -ForegroundColor Gray
        }
    }

    # Remove Lifecycle Policy
    if (Get-AzStorageAccountManagementPolicy -ResourceGroupName $ProdRgName -StorageAccountName $ProdSaName -ErrorAction SilentlyContinue) {
        Remove-AzStorageAccountManagementPolicy -ResourceGroupName $ProdRgName -StorageAccountName $ProdSaName
        Write-Host "  Removed Lifecycle Policy" -ForegroundColor Gray
    }

    # Disable Versioning (Update-AzStorageBlobServiceProperty)
    Update-AzStorageBlobServiceProperty -ResourceGroupName $ProdRgName -StorageAccountName $ProdSaName -IsVersioningEnabled $false
    Write-Host "  Disabled Versioning" -ForegroundColor Gray
}
catch {
    Write-Host "Error cleaning Production: $_" -ForegroundColor Red
}

# 2. Clean Development
try {
    Write-Host "Cleaning Development ($DevSaName)..." -ForegroundColor Yellow
    $devCtx = (Get-AzStorageAccount -ResourceGroupName $DevRgName -Name $DevSaName).Context

    # Remove Public Demo Container
    if (Get-AzStorageContainer -Context $devCtx -Name 'public-demo' -ErrorAction SilentlyContinue) {
        Remove-AzStorageContainer -Context $devCtx -Name 'public-demo' -Force
        Write-Host "  Deleted container: public-demo" -ForegroundColor Gray
    }

    # Disable Public Access on Account
    # Note: Az types don't always support updating this property easily via Set-AzStorageAccount in older modules?
    # Using Set-AzStorageAccount -AllowBlobPublicAccess $false
    Set-AzStorageAccount -ResourceGroupName $DevRgName -Name $DevSaName -AllowBlobPublicAccess $false
    Write-Host "  Disabled Public Access" -ForegroundColor Gray
}
catch {
    Write-Host "Error cleaning Development: $_" -ForegroundColor Red
}

Write-Host "Cleanup Complete!" -ForegroundColor Green
