<#
.SYNOPSIS
    Deploys Lab 2.1 networking resources using native PowerShell cmdlets.

.DESCRIPTION
    This script manually deploys and configures the SkyCraft Lab 2.1 networking resources without using Bicep.
    It serves as an alternative deployment method and demonstrates direct Azure interaction.
    
    Tasks performed:
    1. Create Hub Virtual Network (platform-skycraft-swc-vnet) with management subnets.
    2. Create Spoke Virtual Network (prod-skycraft-swc-vnet) with game service subnets.
    3. Configure bi-directional VNet Peering.
    
    It enforces project tagging standards.

.PARAMETER Location
    The Azure region deployment target. Default: 'swedencentral'

.PARAMETER ProdResourceGroup
    The production resource group name. Default: 'prod-skycraft-swc-rg'

.PARAMETER PlatformResourceGroup
    The platform resource group name. Default: 'platform-skycraft-swc-rg'

.EXAMPLE
    .\Deploy-Networking.ps1
    Deploys all networking resources using default settings.

.NOTES
    Project: SkyCraft
    Lab: 2.1 - Virtual Networks
    Author: Marcin Biszczanik
    Date: 2026-01-04
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$Location = 'swedencentral',

    [Parameter(Mandatory = $false)]
    [string]$ProdResourceGroup = 'prod-skycraft-swc-rg',

    [Parameter(Mandatory = $false)]
    [string]$PlatformResourceGroup = 'platform-skycraft-swc-rg'
)

Write-Host "=== Lab 2.1 - Deploy Networking Configuration (PowerShell) ===" -ForegroundColor Cyan -BackgroundColor Black

# Verify Azure Connection
$context = Get-AzContext
if (-not $context) {
    Write-Host "Not logged in. Please run Connect-AzAccount" -ForegroundColor Red
    exit 1
}
Write-Host "Connected to: $($context.Subscription.Name)" -ForegroundColor Green

# Define Mandatory Tags
$Tags = @{
    Project     = 'SkyCraft'
    Environment = 'Production'
    CostCenter  = 'MSDN'
}

# ===================================
# Task 2: Create Hub Virtual Network
# ===================================
Write-Host "`n=== Task 2: Creating Hub Virtual Network ===" -ForegroundColor Cyan

$hubVnetName = 'platform-skycraft-swc-vnet'

# Define Hub Subnets
$hubSubnets = @(
    (New-AzVirtualNetworkSubnetConfig -Name 'AzureBastionSubnet' -AddressPrefix '10.0.1.0/26'),
    (New-AzVirtualNetworkSubnetConfig -Name 'AzureFirewallSubnet' -AddressPrefix '10.0.2.0/26'),
    (New-AzVirtualNetworkSubnetConfig -Name 'GatewaySubnet' -AddressPrefix '10.0.3.0/27'),
    (New-AzVirtualNetworkSubnetConfig -Name 'SharedSubnet' -AddressPrefix '10.0.4.0/24')
)

Write-Host "Creating VNet: $hubVnetName..." -ForegroundColor Yellow
try {
    $hubVnet = Get-AzVirtualNetwork -ResourceGroupName $PlatformResourceGroup -Name $hubVnetName -ErrorAction SilentlyContinue
    if ($hubVnet) {
        Write-Host "  -> VNet already exists: $hubVnetName" -ForegroundColor Gray
    }
    else {
        $hubVnet = New-AzVirtualNetwork `
            -ResourceGroupName $PlatformResourceGroup `
            -Name $hubVnetName `
            -Location $Location `
            -AddressPrefix '10.0.0.0/16' `
            -Subnet $hubSubnets `
            -Tag $Tags
        Write-Host "  -> Created Hub VNet: $hubVnetName" -ForegroundColor Green
    }
}
catch {
    Write-Host "  -> [ERROR] Failed to create Hub VNet" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    exit 1
}

# ===================================
# Task 3: Create Spoke Virtual Network
# ===================================
Write-Host "`n=== Task 3: Creating Spoke Virtual Network ===" -ForegroundColor Cyan

$spokeVnetName = 'prod-skycraft-swc-vnet'

# Define Spoke Subnets
$spokeSubnets = @(
    (New-AzVirtualNetworkSubnetConfig -Name 'AuthSubnet' -AddressPrefix '10.1.1.0/24'),
    (New-AzVirtualNetworkSubnetConfig -Name 'WorldSubnet' -AddressPrefix '10.1.2.0/24'),
    (New-AzVirtualNetworkSubnetConfig -Name 'DatabaseSubnet' -AddressPrefix '10.1.3.0/24')
)

Write-Host "Creating VNet: $spokeVnetName..." -ForegroundColor Yellow
try {
    $spokeVnet = Get-AzVirtualNetwork -ResourceGroupName $ProdResourceGroup -Name $spokeVnetName -ErrorAction SilentlyContinue
    if ($spokeVnet) {
        Write-Host "  -> VNet already exists: $spokeVnetName" -ForegroundColor Gray
    }
    else {
        $spokeVnet = New-AzVirtualNetwork `
            -ResourceGroupName $ProdResourceGroup `
            -Name $spokeVnetName `
            -Location $Location `
            -AddressPrefix '10.1.0.0/16' `
            -Subnet $spokeSubnets `
            -Tag $Tags
        Write-Host "  -> Created Spoke VNet: $spokeVnetName" -ForegroundColor Green
    }
}
catch {
    Write-Host "  -> [ERROR] Failed to create Spoke VNet" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    exit 1
}

# ===================================
# Task 4: Configure VNet Peering
# ===================================
Write-Host "`n=== Task 4: Configuring VNet Peering ===" -ForegroundColor Cyan

# Peering 1: Hub to Spoke
Write-Host "Creating Peering: peer-hub-to-prod..." -ForegroundColor Yellow
try {
    $peerHub = Get-AzVirtualNetworkPeering -VirtualNetworkName $hubVnetName -ResourceGroupName $PlatformResourceGroup -Name 'peer-hub-to-prod' -ErrorAction SilentlyContinue
    if ($peerHub) {
        Write-Host "  -> Peering already exists: peer-hub-to-prod" -ForegroundColor Gray
    }
    else {
        Add-AzVirtualNetworkPeering `
            -Name 'peer-hub-to-prod' `
            -VirtualNetwork $hubVnet `
            -RemoteVirtualNetworkId $spokeVnet.Id `
            -AllowForwardedTraffic | Out-Null
        Write-Host "  -> Created Peering: Hub to Spoke" -ForegroundColor Green
    }
}
catch {
    Write-Host "  -> [ERROR] Failed to create Hub-to-Spoke peering" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    exit 1
}

# Peering 2: Spoke to Hub
Write-Host "Creating Peering: peer-prod-to-hub..." -ForegroundColor Yellow
try {
    $peerSpoke = Get-AzVirtualNetworkPeering -VirtualNetworkName $spokeVnetName -ResourceGroupName $ProdResourceGroup -Name 'peer-prod-to-hub' -ErrorAction SilentlyContinue
    if ($peerSpoke) {
        Write-Host "  -> Peering already exists: peer-prod-to-hub" -ForegroundColor Gray
    }
    else {
        Add-AzVirtualNetworkPeering `
            -Name 'peer-prod-to-hub' `
            -VirtualNetwork $spokeVnet `
            -RemoteVirtualNetworkId $hubVnet.Id `
            -AllowForwardedTraffic | Out-Null
        Write-Host "  -> Created Peering: Spoke to Hub" -ForegroundColor Green
    }
}
catch {
    Write-Host "  -> [ERROR] Failed to create Spoke-to-Hub peering" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    exit 1
}

Write-Host "`n=== Deployment Complete ===" -ForegroundColor Cyan -BackgroundColor Black
Write-Host "Run Test-Lab.ps1 to verify the networking configuration" -ForegroundColor Green
