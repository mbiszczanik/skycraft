<#
.SYNOPSIS
    Cleans up resources created in Lab 2.1.

.DESCRIPTION
    This script removes the Hub and Spoke Virtual Networks (Dev/Prod), their peering 
    configurations, and Public IPs. It prompts for confirmation unless the -Force switch is used.

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

$devRgName = "dev-skycraft-swc-rg"
$devVnetName = "dev-skycraft-swc-vnet"

$prodRgName = "prod-skycraft-swc-rg"
$prodVnetName = "prod-skycraft-swc-vnet"

# Confirmation
if (-not $Force) {
    $confirm = Read-Host "Are you sure you want to delete Lab 2.1 Networking resources (Hub/Dev/Prod VNets & PIPs)? (y/N)"
    if ($confirm -notmatch "^y$") {
        Write-Host "Cleanup cancelled." -ForegroundColor Yellow
        exit 0
    }
}

Write-Host "`nStarting cleanup..." -ForegroundColor Cyan

# Function to remove peerings
function Remove-VNetPeerings {
    param($VnetName, $RgName)
    try {
        Write-Host "Removing peerings on $VnetName..." -ForegroundColor Yellow
        $vnet = Get-AzVirtualNetwork -Name $VnetName -ResourceGroupName $RgName -ErrorAction SilentlyContinue
        if ($vnet) {
            $peerings = $vnet.VirtualNetworkPeerings | Where-Object { $_.Name -match "peer" }
            foreach ($p in $peerings) {
                Write-Host "  -> Deleting $($p.Name)" -ForegroundColor Gray
                Remove-AzVirtualNetworkPeering -VirtualNetworkName $VnetName -ResourceGroupName $RgName -Name $p.Name -Force -ErrorAction Stop
            }
        }
    } catch {
        Write-Host "  - [WARNING] Failed to remove peering on ${VnetName}: $_" -ForegroundColor Yellow
    }
}

Remove-VNetPeerings -VnetName $hubVnetName -RgName $hubRgName
Remove-VNetPeerings -VnetName $devVnetName -RgName $devRgName
Remove-VNetPeerings -VnetName $prodVnetName -RgName $prodRgName

# Function to remove VNet
function Remove-VNet {
    param($VnetName, $RgName)
    try {
        Write-Host "Removing VNet: $VnetName..." -ForegroundColor Yellow
        Remove-AzVirtualNetwork -Name $VnetName -ResourceGroupName $RgName -Force -ErrorAction Stop
        Write-Host "  -> Success" -ForegroundColor Green
    } catch {
        Write-Host "  - [INFO] VNet $VnetName not found or already deleted." -ForegroundColor Gray
    }
}

Remove-VNet -VnetName $hubVnetName -RgName $hubRgName
Remove-VNet -VnetName $devVnetName -RgName $devRgName
Remove-VNet -VnetName $prodVnetName -RgName $prodRgName

# Check for and remove PIPs
$pips = @(
    @{"Name"="dev-skycraft-swc-lb-pip"; "RG"=$devRgName},
    @{"Name"="prod-skycraft-swc-lb-pip"; "RG"=$prodRgName}
)

foreach ($pip in $pips) {
    try {
        Write-Host "Removing Public IP: $($pip.Name)..." -ForegroundColor Yellow
        Remove-AzPublicIpAddress -Name $pip.Name -ResourceGroupName $pip.RG -Force -ErrorAction Stop
        Write-Host "  -> Success" -ForegroundColor Green
    } catch {
        Write-Host "  - [INFO] PIP $($pip.Name) not found or already deleted." -ForegroundColor Gray
    }
}

Write-Host "`nCleanup Complete." -ForegroundColor Green

