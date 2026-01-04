<#
.SYNOPSIS
    Cleans up resources created in Lab 2.1.

.DESCRIPTION
    This script removes the Hub and Spoke Virtual Networks and their peering 
    configurations. It prompts for confirmation unless the -Force switch is used.

.PARAMETER Force
    Skip the confirmation prompt.

.EXAMPLE
    .\Cleanup-Resources.ps1
    Prompts for confirmation before deleting resources.

.EXAMPLE
    .\Cleanup-Resources.ps1 -Force
    Deletes resources without prompting.

.NOTES
    Project: SkyCraft
    Lab: 2.1 - Virtual Networks
    Author: Marcin Biszczanik
    Date: 2026-01-04
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [switch]$Force
)

Write-Host "=== Lab 2.1 - Resource Cleanup ===" -ForegroundColor Cyan -BackgroundColor Black

# Verify Azure Connection
$context = Get-AzContext
if (-not $context) {
    Write-Host "Not logged in. Please run Connect-AzAccount" -ForegroundColor Red
    exit 1
}

$hubRgName = "platform-skycraft-swc-rg"
$hubVnetName = "platform-skycraft-swc-vnet"
$spokeRgName = "prod-skycraft-swc-rg"
$spokeVnetName = "prod-skycraft-swc-vnet"

# Confirmation
if (-not $Force) {
    $confirm = Read-Host "Are you sure you want to delete Lab 2.1 Networking resources (VNets/Peering) in $hubRgName and $spokeRgName? (y/N)"
    if ($confirm -notmatch "^y$") {
        Write-Host "Cleanup cancelled." -ForegroundColor Yellow
        exit 0
    }
}

Write-Host "`nStarting cleanup..." -ForegroundColor Cyan

# Removing Peerings First
try {
    Write-Host "Removing peering on $hubVnetName..." -ForegroundColor Yellow
    $hubVnet = Get-AzVirtualNetwork -Name $hubVnetName -ResourceGroupName $hubRgName -ErrorAction SilentlyContinue
    if ($hubVnet) {
        $hubPeering = $hubVnet.VirtualNetworkPeerings | Where-Object { $_.Name -match "peer" }
        foreach ($p in $hubPeering) {
            Write-Host "  -> Deleting $($p.Name)" -ForegroundColor Gray
            Remove-AzVirtualNetworkPeering -VirtualNetworkName $hubVnetName -ResourceGroupName $hubRgName -Name $p.Name -Force -ErrorAction Stop
        }
    }
} catch {
    Write-Host "  - [WARNING] Failed to remove peering on Hub VNet. It might have already been removed." -ForegroundColor Yellow
}

try {
    Write-Host "Removing peering on $spokeVnetName..." -ForegroundColor Yellow
    $spokeVnet = Get-AzVirtualNetwork -Name $spokeVnetName -ResourceGroupName $spokeRgName -ErrorAction SilentlyContinue
    if ($spokeVnet) {
        $spokePeering = $spokeVnet.VirtualNetworkPeerings | Where-Object { $_.Name -match "peer" }
        foreach ($p in $spokePeering) {
            Write-Host "  -> Deleting $($p.Name)" -ForegroundColor Gray
            Remove-AzVirtualNetworkPeering -VirtualNetworkName $spokeVnetName -ResourceGroupName $spokeRgName -Name $p.Name -Force -ErrorAction Stop
        }
    }
} catch {
    Write-Host "  - [WARNING] Failed to remove peering on Spoke VNet." -ForegroundColor Yellow
}

# Removing VNets
try {
    Write-Host "Removing Hub VNet ($hubVnetName)..." -ForegroundColor Yellow
    Remove-AzVirtualNetwork -Name $hubVnetName -ResourceGroupName $hubRgName -Force -ErrorAction Stop
    Write-Host "  -> Success" -ForegroundColor Green
} catch {
    Write-Host "  - [INFO] Hub VNet not found or already deleted." -ForegroundColor Gray
}

try {
    Write-Host "Removing Spoke VNet ($spokeVnetName)..." -ForegroundColor Yellow
    Remove-AzVirtualNetwork -Name $spokeVnetName -ResourceGroupName $spokeRgName -Force -ErrorAction Stop
    Write-Host "  -> Success" -ForegroundColor Green
} catch {
    Write-Host "  - [INFO] Spoke VNet not found or already deleted." -ForegroundColor Gray
}

Write-Host "`nCleanup Complete." -ForegroundColor Green
