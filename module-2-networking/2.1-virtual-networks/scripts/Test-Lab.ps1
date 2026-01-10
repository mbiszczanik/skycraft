<#
.SYNOPSIS
    Validates the configuration of Lab 2.1 networking resources.

.DESCRIPTION
    This script runs a comprehensive validation suite against the deployed VNets (Hub/Dev/Prod), 
    Subnets, Peering configurations, and Public IPs to ensure they meet the Lab 2.1 requirements.

    Valdiates:
    - Hub VNet and all 4 subnets.
    - Dev VNet and all 3 subnets.
    - Prod VNet and all 3 subnets.
    - VNet Peering state (Connected) and settings (Forwarded traffic, VNet access).
    - Public IPs existence and SKU (Standard/Static).

.EXAMPLE
    .\Test-Lab.ps1
    Runs all validation checks and outputs Pass/Fail status.

.NOTES
    Project: SkyCraft
    Lab: 2.1 - Virtual Networks
    Author: Marcin Biszczanik
    Date: 2026-01-04
#>

Write-Host "=== Lab 2.1 Validation Script ===" -ForegroundColor Cyan -BackgroundColor Black

# Check Azure Connection
$context = Get-AzContext
if (-not $context) {
    Write-Host "Not logged in. Please run Connect-AzAccount" -ForegroundColor Red
    return
}
Write-Host "Connected to: $($context.Subscription.Name)" -ForegroundColor Green

# 1. Validate Hub VNet
Write-Host "`n=== 1. Validating Hub VNet ===" -ForegroundColor Cyan
$hubRgName = "platform-skycraft-swc-rg"
$hubVnetName = "platform-skycraft-swc-vnet"
$hubExpectedSubnets = @{
    "AzureBastionSubnet"  = "10.0.1.0/26"
    "AzureFirewallSubnet" = "10.0.2.0/26"
    "GatewaySubnet"       = "10.0.3.0/27"
    "SharedSubnet"        = "10.0.4.0/24"
}

try {
    $hubVnet = Get-AzVirtualNetwork -Name $hubVnetName -ResourceGroupName $hubRgName -ErrorAction Stop
    Write-Host "[OK] Hub VNet found: $hubVnetName" -ForegroundColor Green
    
    # Check Address Space
    if ($hubVnet.AddressSpace.AddressPrefixes -contains "10.0.0.0/16") {
        Write-Host "  - Address Space 10.0.0.0/16 verified." -ForegroundColor Green
    }
    else {
        Write-Host "  - [FAIL] Address Space is $($hubVnet.AddressSpace.AddressPrefixes -join ', ')" -ForegroundColor Red
    }

    # Check Subnets
    foreach ($subnetName in $hubExpectedSubnets.Keys) {
        $subnet = $hubVnet.Subnets | Where-Object { $_.Name -eq $subnetName }
        if ($subnet) {
            if ($subnet.AddressPrefix -eq $hubExpectedSubnets[$subnetName]) {
                Write-Host "  - [OK] Subnet $subnetName ($($subnet.AddressPrefix)) verified." -ForegroundColor Green
            }
            else {
                Write-Host "  - [FAIL] Subnet $subnetName found but address range is $($subnet.AddressPrefix) (Expected: $($hubExpectedSubnets[$subnetName]))" -ForegroundColor Red
            }
        }
        else {
            Write-Host "  - [FAIL] Subnet $subnetName not found." -ForegroundColor Red
        }
    }
}
catch {
    Write-Host "[FAIL] Hub VNet $hubVnetName not found in Resource Group $hubRgName." -ForegroundColor Red
}

function Test-SpokeVNet {
    param($VnetName, $RgName, $Prefix, $ExpectedSubnets)
    Write-Host "`n=== Validating VNet: $VnetName ===" -ForegroundColor Cyan
    try {
        $vnet = Get-AzVirtualNetwork -Name $VnetName -ResourceGroupName $RgName -ErrorAction Stop
        Write-Host "[OK] VNet found: $VnetName" -ForegroundColor Green
        
        if ($vnet.AddressSpace.AddressPrefixes -contains $Prefix) {
            Write-Host "  - Address Space $Prefix verified." -ForegroundColor Green
        } else {
            Write-Host "  - [FAIL] Address Space is $($vnet.AddressSpace.AddressPrefixes -join ', ')" -ForegroundColor Red
        }

        foreach ($subnetName in $ExpectedSubnets.Keys) {
            $subnet = $vnet.Subnets | Where-Object { $_.Name -eq $subnetName }
            if ($subnet) {
                if ($subnet.AddressPrefix -eq $ExpectedSubnets[$subnetName]) {
                    Write-Host "  - [OK] Subnet $subnetName ($($subnet.AddressPrefix)) verified." -ForegroundColor Green
                } else {
                    Write-Host "  - [FAIL] Subnet $subnetName found but address range is $($subnet.AddressPrefix) (Expected: $($ExpectedSubnets[$subnetName]))" -ForegroundColor Red
                }
            } else {
                Write-Host "  - [FAIL] Subnet $subnetName not found." -ForegroundColor Red
            }
        }
    } catch {
        Write-Host "[FAIL] VNet $VnetName not found in Resource Group $RgName." -ForegroundColor Red
    }
}

# 2. Validate Dev VNet
$devExpectedSubnets = @{
    "AuthSubnet"     = "10.1.1.0/24"
    "WorldSubnet"    = "10.1.2.0/24"
    "DatabaseSubnet" = "10.1.3.0/24"
}
Test-SpokeVNet -VnetName "dev-skycraft-swc-vnet" -RgName "dev-skycraft-swc-rg" -Prefix "10.1.0.0/16" -ExpectedSubnets $devExpectedSubnets

# 3. Validate Prod VNet
$prodExpectedSubnets = @{
    "AuthSubnet"     = "10.2.1.0/24"
    "WorldSubnet"    = "10.2.2.0/24"
    "DatabaseSubnet" = "10.2.3.0/24"
}
Test-SpokeVNet -VnetName "prod-skycraft-swc-vnet" -RgName "prod-skycraft-swc-rg" -Prefix "10.2.0.0/16" -ExpectedSubnets $prodExpectedSubnets


# 4. Validate Peering
Write-Host "`n=== 4. Validating VNet Peering ===" -ForegroundColor Cyan

function Test-Peering {
    param($VnetName, $RgName, $PeeringName)
    try {
        $peering = Get-AzVirtualNetworkPeering -VirtualNetworkName $VnetName -ResourceGroupName $RgName -Name $PeeringName -ErrorAction SilentlyContinue
        if ($peering) {
            if ($peering.PeeringState -eq "Connected") {
                Write-Host "[OK] $PeeringName on $VnetName (Status: $($peering.PeeringState))" -ForegroundColor Green
            } else {
                Write-Host "[FAIL] $PeeringName on $VnetName Status is $($peering.PeeringState)" -ForegroundColor Red
            }
            if ($peering.AllowVirtualNetworkAccess) { Write-Host "  - [OK] AllowVirtualNetworkAccess" -ForegroundColor Green }
            else { Write-Host "  - [FAIL] AllowVirtualNetworkAccess is False" -ForegroundColor Red }
            if ($peering.AllowForwardedTraffic) { Write-Host "  - [OK] AllowForwardedTraffic" -ForegroundColor Green }
            else { Write-Host "  - [FAIL] AllowForwardedTraffic is False" -ForegroundColor Red }
        } else {
            Write-Host "[FAIL] Peering $PeeringName not found on $VnetName." -ForegroundColor Red
        }
    } catch { Write-Host "[FAIL] Error checking $PeeringName on ${VnetName}: $_" -ForegroundColor Red }
}

Test-Peering -VnetName "platform-skycraft-swc-vnet" -RgName "platform-skycraft-swc-rg" -PeeringName "hub-to-dev"
Test-Peering -VnetName "dev-skycraft-swc-vnet"      -RgName "dev-skycraft-swc-rg"      -PeeringName "dev-to-hub"
Test-Peering -VnetName "platform-skycraft-swc-vnet" -RgName "platform-skycraft-swc-rg" -PeeringName "hub-to-prod"
Test-Peering -VnetName "prod-skycraft-swc-vnet"     -RgName "prod-skycraft-swc-rg"     -PeeringName "prod-to-hub"

# 5. Validate Public IPs
Write-Host "`n=== 5. Validating Public IPs ===" -ForegroundColor Cyan

function Test-PIP {
    param($Name, $RgName)
    try {
        $pip = Get-AzPublicIpAddress -Name $Name -ResourceGroupName $RgName -ErrorAction SilentlyContinue
        if ($pip) {
            Write-Host "[OK] PIP found: $Name" -ForegroundColor Green
            if ($pip.Sku.Name -eq "Standard") { Write-Host "  - [OK] SKU Standard" -ForegroundColor Green }
            else { Write-Host "  - [FAIL] SKU is $($pip.Sku.Name)" -ForegroundColor Red }
            if ($pip.PublicIpAllocationMethod -eq "Static") { Write-Host "  - [OK] Allocation Static" -ForegroundColor Green }
            else { Write-Host "  - [FAIL] Allocation is $($pip.PublicIpAllocationMethod)" -ForegroundColor Red }
        } else { Write-Host "[FAIL] PIP $Name not found." -ForegroundColor Red }
    } catch { Write-Host "[FAIL] Error checking PIP ${Name}: $_" -ForegroundColor Red }
}

Test-PIP -Name "dev-skycraft-swc-lb-pip" -RgName "dev-skycraft-swc-rg"
Test-PIP -Name "prod-skycraft-swc-lb-pip" -RgName "prod-skycraft-swc-rg"

Write-Host "`n=== Validation Summary ===" -ForegroundColor Cyan
Write-Host "Lab 2.1 validation complete" -ForegroundColor Green

