<#
.SYNOPSIS
    Deploys Lab 2.1 networking resources using native PowerShell cmdlets.

.DESCRIPTION
    This script manually deploys and configures the SkyCraft Lab 2.1 networking resources without using Bicep.
    It serves as an alternative deployment method and demonstrates direct Azure interaction.
    
    Tasks performed:
    1. Create Hub Virtual Network (platform-skycraft-swc-vnet).
    2. Create Dev Virtual Network (dev-skycraft-swc-vnet).
    3. Create Prod Virtual Network (prod-skycraft-swc-vnet).
    4. Configure bi-directional VNet Peering (Hub-Dev, Hub-Prod).
    5. Create Public IP Addresses (Bastion, Dev LB, Prod LB).
    
    It enforces project tagging standards.

.PARAMETER Location
    The Azure region deployment target. Default: 'swedencentral'

.PARAMETER ProdResourceGroup
    The production resource group name. Default: 'prod-skycraft-swc-rg'

.PARAMETER DevResourceGroup
    The development resource group name. Default: 'dev-skycraft-swc-rg'

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
    [string]$DevResourceGroup = 'dev-skycraft-swc-rg',

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
$TagsPlatform = @{ Project = 'SkyCraft'; Environment = 'Platform'; CostCenter = 'MSDN' }
$TagsDev = @{ Project = 'SkyCraft'; Environment = 'Development'; CostCenter = 'MSDN' }
$TagsProd = @{ Project = 'SkyCraft'; Environment = 'Production'; CostCenter = 'MSDN' }

# ===================================
# Task 2: Create Hub Virtual Network
# ===================================
Write-Host "`n=== Task 2: Creating Hub Virtual Network ===" -ForegroundColor Cyan
$hubVnetName = 'platform-skycraft-swc-vnet'
$hubSubnets = @(
    (New-AzVirtualNetworkSubnetConfig -Name 'AzureBastionSubnet' -AddressPrefix '10.0.1.0/26'),
    (New-AzVirtualNetworkSubnetConfig -Name 'AzureFirewallSubnet' -AddressPrefix '10.0.2.0/26'),
    (New-AzVirtualNetworkSubnetConfig -Name 'GatewaySubnet' -AddressPrefix '10.0.3.0/27'),
    (New-AzVirtualNetworkSubnetConfig -Name 'SharedSubnet' -AddressPrefix '10.0.4.0/24')
)

Write-Host "Creating VNet: $hubVnetName..." -ForegroundColor Yellow
try {
    $hubVnet = Get-AzVirtualNetwork -ResourceGroupName $PlatformResourceGroup -Name $hubVnetName -ErrorAction SilentlyContinue
    if (-not $hubVnet) {
        $hubVnet = New-AzVirtualNetwork -ResourceGroupName $PlatformResourceGroup -Name $hubVnetName -Location $Location -AddressPrefix '10.0.0.0/16' -Subnet $hubSubnets -Tag $TagsPlatform -ErrorAction Stop
        Write-Host "  -> Created Hub VNet: $hubVnetName" -ForegroundColor Green
    } else { Write-Host "  -> exists" -ForegroundColor Gray }
} catch { Write-Host "  -> [ERROR] Failed to create Hub VNet: $_" -ForegroundColor Red; exit 1 }

# ===================================
# Task 3: Create Dev Virtual Network
# ===================================
Write-Host "`n=== Task 3: Creating Dev Virtual Network ===" -ForegroundColor Cyan
$devVnetName = 'dev-skycraft-swc-vnet'
$devSubnets = @(
    (New-AzVirtualNetworkSubnetConfig -Name 'AuthSubnet' -AddressPrefix '10.1.1.0/24'),
    (New-AzVirtualNetworkSubnetConfig -Name 'WorldSubnet' -AddressPrefix '10.1.2.0/24'),
    (New-AzVirtualNetworkSubnetConfig -Name 'DatabaseSubnet' -AddressPrefix '10.1.3.0/24')
)

Write-Host "Creating VNet: $devVnetName..." -ForegroundColor Yellow
try {
    $devVnet = Get-AzVirtualNetwork -ResourceGroupName $DevResourceGroup -Name $devVnetName -ErrorAction SilentlyContinue
    if (-not $devVnet) {
        $devVnet = New-AzVirtualNetwork -ResourceGroupName $DevResourceGroup -Name $devVnetName -Location $Location -AddressPrefix '10.1.0.0/16' -Subnet $devSubnets -Tag $TagsDev -ErrorAction Stop
        Write-Host "  -> Created Dev VNet: $devVnetName" -ForegroundColor Green
    } else { Write-Host "  -> exists" -ForegroundColor Gray }
} catch { Write-Host "  -> [ERROR] Failed to create Dev VNet: $_" -ForegroundColor Red; exit 1 }

# ===================================
# Task 4: Create Prod Virtual Network
# ===================================
Write-Host "`n=== Task 4: Creating Prod Virtual Network ===" -ForegroundColor Cyan
$prodVnetName = 'prod-skycraft-swc-vnet'
$prodSubnets = @(
    (New-AzVirtualNetworkSubnetConfig -Name 'AuthSubnet' -AddressPrefix '10.2.1.0/24'),
    (New-AzVirtualNetworkSubnetConfig -Name 'WorldSubnet' -AddressPrefix '10.2.2.0/24'),
    (New-AzVirtualNetworkSubnetConfig -Name 'DatabaseSubnet' -AddressPrefix '10.2.3.0/24')
)

Write-Host "Creating VNet: $prodVnetName..." -ForegroundColor Yellow
try {
    $prodVnet = Get-AzVirtualNetwork -ResourceGroupName $ProdResourceGroup -Name $prodVnetName -ErrorAction SilentlyContinue
    if (-not $prodVnet) {
        $prodVnet = New-AzVirtualNetwork -ResourceGroupName $ProdResourceGroup -Name $prodVnetName -Location $Location -AddressPrefix '10.2.0.0/16' -Subnet $prodSubnets -Tag $TagsProd -ErrorAction Stop
        Write-Host "  -> Created Prod VNet: $prodVnetName" -ForegroundColor Green
    } else { Write-Host "  -> exists" -ForegroundColor Gray }
} catch { Write-Host "  -> [ERROR] Failed to create Prod VNet: $_" -ForegroundColor Red; exit 1 }

# ===================================
# Task 5: Configure VNet Peering
# ===================================
Write-Host "`n=== Task 5: Configuring VNet Peering ===" -ForegroundColor Cyan

function New-SkyCraftPeering {
    param($Name, $SrcVnet, $DstVnetId, $RgName)
    Write-Host "Creating Peering: $Name..." -ForegroundColor Yellow
    try {
        $peer = Get-AzVirtualNetworkPeering -VirtualNetworkName $SrcVnet.Name -ResourceGroupName $RgName -Name $Name -ErrorAction SilentlyContinue
        if (-not $peer) {
            Add-AzVirtualNetworkPeering -Name $Name -VirtualNetwork $SrcVnet -RemoteVirtualNetworkId $DstVnetId -AllowForwardedTraffic -ErrorAction Stop | Out-Null
            Write-Host "  -> Created $Name" -ForegroundColor Green
        } else { Write-Host "  -> exists" -ForegroundColor Gray }
    } catch { Write-Host "  -> [ERROR] Failed to create $Name : $_" -ForegroundColor Red }
}

# Hub <-> Dev
New-SkyCraftPeering -Name "hub-to-dev" -SrcVnet $hubVnet -DstVnetId $devVnet.Id -RgName $PlatformResourceGroup
New-SkyCraftPeering -Name "dev-to-hub" -SrcVnet $devVnet -DstVnetId $hubVnet.Id -RgName $DevResourceGroup

# Hub <-> Prod
New-SkyCraftPeering -Name "hub-to-prod" -SrcVnet $hubVnet -DstVnetId $prodVnet.Id -RgName $PlatformResourceGroup
New-SkyCraftPeering -Name "prod-to-hub" -SrcVnet $prodVnet -DstVnetId $hubVnet.Id -RgName $ProdResourceGroup

# ===================================
# Task 6: Create Public IP Addresses
# ===================================
Write-Host "`n=== Task 6: Creating Public IP Addresses ===" -ForegroundColor Cyan

function New-SkyCraftPip {
    param($Name, $RgName, $Tags)
    Write-Host "Creating PIP: $Name..." -ForegroundColor Yellow
    try {
        $pip = Get-AzPublicIpAddress -Name $Name -ResourceGroupName $RgName -ErrorAction SilentlyContinue
        if (-not $pip) {
            New-AzPublicIpAddress -Name $Name -ResourceGroupName $RgName -Location $Location -Sku Standard -AllocationMethod Static -Tag $Tags -ErrorAction Stop | Out-Null
            Write-Host "  -> Created PIP: $Name" -ForegroundColor Green
        } else { Write-Host "  -> exists" -ForegroundColor Gray }
    } catch { Write-Host "  -> [ERROR] Failed to create PIP $Name : $_" -ForegroundColor Red }
}

New-SkyCraftPip -Name 'platform-skycraft-swc-bas-pip' -RgName $PlatformResourceGroup -Tags $TagsPlatform
New-SkyCraftPip -Name 'dev-skycraft-swc-lb-pip' -RgName $DevResourceGroup -Tags $TagsDev
New-SkyCraftPip -Name 'prod-skycraft-swc-lb-pip' -RgName $ProdResourceGroup -Tags $TagsProd

Write-Host "`n=== Deployment Complete ===" -ForegroundColor Cyan -BackgroundColor Black
Write-Host "Run Test-Lab.ps1 to verify the networking configuration" -ForegroundColor Green
