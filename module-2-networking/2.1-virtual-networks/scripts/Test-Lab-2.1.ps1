# Lab 2.1 - Virtual Networks Validation Script
# Validates Virtual Networks, Subnets, and Peering

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

# 2. Validate Spoke VNet
Write-Host "`n=== 2. Validating Spoke VNet ===" -ForegroundColor Cyan
$spokeRgName = "prod-skycraft-swc-rg"
$spokeVnetName = "prod-skycraft-swc-vnet"
$spokeExpectedSubnets = @{
    "AuthSubnet"     = "10.1.1.0/24"
    "WorldSubnet"    = "10.1.2.0/24"
    "DatabaseSubnet" = "10.1.3.0/24"
}

try {
    $spokeVnet = Get-AzVirtualNetwork -Name $spokeVnetName -ResourceGroupName $spokeRgName -ErrorAction Stop
    Write-Host "[OK] Spoke VNet found: $spokeVnetName" -ForegroundColor Green
    
    # Check Address Space
    if ($spokeVnet.AddressSpace.AddressPrefixes -contains "10.1.0.0/16") {
        Write-Host "  - Address Space 10.1.0.0/16 verified." -ForegroundColor Green
    }
    else {
        Write-Host "  - [FAIL] Address Space is $($spokeVnet.AddressSpace.AddressPrefixes -join ', ')" -ForegroundColor Red
    }

    # Check Subnets
    foreach ($subnetName in $spokeExpectedSubnets.Keys) {
        $subnet = $spokeVnet.Subnets | Where-Object { $_.Name -eq $subnetName }
        if ($subnet) {
            if ($subnet.AddressPrefix -eq $spokeExpectedSubnets[$subnetName]) {
                Write-Host "  - [OK] Subnet $subnetName ($($subnet.AddressPrefix)) verified." -ForegroundColor Green
            }
            else {
                Write-Host "  - [FAIL] Subnet $subnetName found but address range is $($subnet.AddressPrefix) (Expected: $($spokeExpectedSubnets[$subnetName]))" -ForegroundColor Red
            }
        }
        else {
            Write-Host "  - [FAIL] Subnet $subnetName not found." -ForegroundColor Red
        }
    }
}
catch {
    Write-Host "[FAIL] Spoke VNet $spokeVnetName not found in Resource Group $spokeRgName." -ForegroundColor Red
}

# 3. Validate Peering
Write-Host "`n=== 3. Validating VNet Peering ===" -ForegroundColor Cyan

# Check Peering from Hub to Spoke
$hubPeeringName = "peer-hub-to-prod"
try {
    $hubToProdPeering = Get-AzVirtualNetworkPeering -VirtualNetworkName $hubVnetName -ResourceGroupName $hubRgName -Name $hubPeeringName -ErrorAction SilentlyContinue
    if ($hubToProdPeering) {
        if ($hubToProdPeering.PeeringState -eq "Connected") {
            Write-Host "[OK] Peering found: $hubPeeringName (Status: $($hubToProdPeering.PeeringState))" -ForegroundColor Green
        }
        else {
            Write-Host "[FAIL] Peering found: $hubPeeringName but Status is $($hubToProdPeering.PeeringState)" -ForegroundColor Red
        }

        # Check Access & Forwarded Traffic
        if ($hubToProdPeering.AllowVirtualNetworkAccess) {
            Write-Host "  - [OK] AllowVirtualNetworkAccess: True" -ForegroundColor Green
        }
        else {
            Write-Host "  - [FAIL] AllowVirtualNetworkAccess: False (Expected: True)" -ForegroundColor Red
        }

        if ($hubToProdPeering.AllowForwardedTraffic) {
            Write-Host "  - [OK] AllowForwardedTraffic: True" -ForegroundColor Green
        }
        else {
            Write-Host "  - [FAIL] AllowForwardedTraffic: False (Expected: True)" -ForegroundColor Red
        }
    }
    else {
        Write-Host "[FAIL] VNet Peering '$hubPeeringName' not found on $hubVnetName." -ForegroundColor Red
    }
}
catch {
    Write-Host "[FAIL] Error checking Hub-to-Prod peering." -ForegroundColor Red
}

# Check Peering from Spoke to Hub
$spokePeeringName = "peer-prod-to-hub"
try {
    $prodToHubPeering = Get-AzVirtualNetworkPeering -VirtualNetworkName $spokeVnetName -ResourceGroupName $spokeRgName -Name $spokePeeringName -ErrorAction SilentlyContinue
    if ($prodToHubPeering) {
        if ($prodToHubPeering.PeeringState -eq "Connected") {
            Write-Host "[OK] Peering found: $spokePeeringName (Status: $($prodToHubPeering.PeeringState))" -ForegroundColor Green
        }
        else {
            Write-Host "[FAIL] Peering found: $spokePeeringName but Status is $($prodToHubPeering.PeeringState)" -ForegroundColor Red
        }

        # Check Access & Forwarded Traffic
        if ($prodToHubPeering.AllowVirtualNetworkAccess) {
            Write-Host "  - [OK] AllowVirtualNetworkAccess: True" -ForegroundColor Green
        }
        else {
            Write-Host "  - [FAIL] AllowVirtualNetworkAccess: False (Expected: True)" -ForegroundColor Red
        }

        if ($prodToHubPeering.AllowForwardedTraffic) {
            Write-Host "  - [OK] AllowForwardedTraffic: True" -ForegroundColor Green
        }
        else {
            Write-Host "  - [FAIL] AllowForwardedTraffic: False (Expected: True)" -ForegroundColor Red
        }
    }
    else {
        Write-Host "[FAIL] VNet Peering '$spokePeeringName' not found on $spokeVnetName." -ForegroundColor Red
    }
}
catch {
    Write-Host "[FAIL] Error checking Prod-to-Hub peering." -ForegroundColor Red
}

Write-Host "`n=== Validation Summary ===" -ForegroundColor Cyan
Write-Host "Lab 2.1 validation complete" -ForegroundColor Green
