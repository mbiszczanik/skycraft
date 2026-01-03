<#
.SYNOPSIS
    Deploys Lab 2.2 security resources using native PowerShell cmdlets.

.DESCRIPTION
    This script manually deploys and configures the SkyCraft Lab 2.2 security resources without using Bicep.
    It serves as an alternative deployment method and demonstrates direct Azure interaction.
    
    Tasks performed:
    1. Create Application Security Groups (ASGs).
    2. Create Network Security Groups (NSGs).
    3. Configure complex NSG Security Rules (Auth, World, DB).
    4. Associate NSGs to subnets properly.
    5. Optionally deploy Azure Bastion (interactive prompt).
    
    It enforces project tagging standards.

.PARAMETER Location
    The Azure region deployment target. Default: 'swedencentral'

.PARAMETER ProdResourceGroup
    The production resource group name. Default: 'prod-skycraft-swc-rg'

.PARAMETER PlatformResourceGroup
    The platform resource group name. Default: 'platform-skycraft-swc-rg'

.PARAMETER ProdVnetName
    The name of the Production VNet. Default: 'prod-skycraft-swc-vnet'

.PARAMETER PlatformVnetName
    The name of the Platform VNet. Default: 'platform-skycraft-swc-vnet'

.EXAMPLE
    .\Deploy-Security.ps1
    Deploys all security resources using default settings.

.NOTES
    Project: SkyCraft
    Lab: 2.2 - Secure Access
    Author: Ops Team
    Date: 2026-01-03
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$Location = 'swedencentral',

    [Parameter(Mandatory = $false)]
    [string]$ProdResourceGroup = 'prod-skycraft-swc-rg',

    [Parameter(Mandatory = $false)]
    [string]$PlatformResourceGroup = 'platform-skycraft-swc-rg',

    [Parameter(Mandatory = $false)]
    [string]$ProdVnetName = 'prod-skycraft-swc-vnet',

    [Parameter(Mandatory = $false)]
    [string]$PlatformVnetName = 'platform-skycraft-swc-vnet'
)

Write-Host "=== Lab 2.2 - Deploy Security Configuration (PowerShell) ===" -ForegroundColor Cyan -BackgroundColor Black

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
# Task 1: Create Application Security Groups
# ===================================
Write-Host "`n=== Task 1: Creating Application Security Groups ===" -ForegroundColor Cyan

$asgNames = @(
    'prod-skycraft-swc-asg-auth',
    'prod-skycraft-swc-asg-world',
    'prod-skycraft-swc-asg-db'
)

$asgs = @{}
foreach ($asgName in $asgNames) {
    Write-Host "Creating ASG: $asgName..." -ForegroundColor Yellow
    try {
        $asg = Get-AzApplicationSecurityGroup -ResourceGroupName $ProdResourceGroup -Name $asgName -ErrorAction SilentlyContinue
        if ($asg) {
            Write-Host "  -> ASG already exists: $asgName" -ForegroundColor Gray
        }
        else {
            $asg = New-AzApplicationSecurityGroup `
                -ResourceGroupName $ProdResourceGroup `
                -Name $asgName `
                -Location $Location `
                -Tag $Tags
            Write-Host "  -> Created ASG: $asgName" -ForegroundColor Green
        }
        $asgs[$asgName] = $asg
    }
    catch {
        Write-Host "  -> [ERROR] Failed to create ASG: $asgName" -ForegroundColor Red
        Write-Host $_.Exception.Message -ForegroundColor Red
        exit 1
    }
}

# ===================================
# Task 2: Create Network Security Groups
# ===================================
Write-Host "`n=== Task 2: Creating Network Security Groups ===" -ForegroundColor Cyan

# Production NSG
Write-Host "Creating NSG: prod-skycraft-swc-nsg..." -ForegroundColor Yellow
try {
    $nsgProd = Get-AzNetworkSecurityGroup -ResourceGroupName $ProdResourceGroup -Name 'prod-skycraft-swc-nsg' -ErrorAction SilentlyContinue
    if ($nsgProd) {
        Write-Host "  -> NSG already exists, will update rules" -ForegroundColor Gray
    }
    else {
        $nsgProd = New-AzNetworkSecurityGroup `
            -ResourceGroupName $ProdResourceGroup `
            -Name 'prod-skycraft-swc-nsg' `
            -Location $Location `
            -Tag $Tags
        Write-Host "  -> Created NSG: prod-skycraft-swc-nsg" -ForegroundColor Green
    }
}
catch {
    Write-Host "  -> [ERROR] Failed to create Production NSG" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    exit 1
}

# Platform NSG
Write-Host "Creating NSG: platform-skycraft-swc-nsg..." -ForegroundColor Yellow
try {
    $nsgPlatform = Get-AzNetworkSecurityGroup -ResourceGroupName $PlatformResourceGroup -Name 'platform-skycraft-swc-nsg' -ErrorAction SilentlyContinue
    if ($nsgPlatform) {
        Write-Host "  -> NSG already exists" -ForegroundColor Gray
    }
    else {
        $nsgPlatform = New-AzNetworkSecurityGroup `
            -ResourceGroupName $PlatformResourceGroup `
            -Name 'platform-skycraft-swc-nsg' `
            -Location $Location `
            -Tag $Tags
        Write-Host "  -> Created NSG: platform-skycraft-swc-nsg" -ForegroundColor Green
    }
}
catch {
    Write-Host "  -> [ERROR] Failed to create Platform NSG" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    exit 1
}

# ===================================
# Task 3 & 4: Configure NSG Rules
# ===================================
Write-Host "`n=== Task 3 & 4: Configuring NSG Rules ===" -ForegroundColor Cyan

# Get fresh NSG object to work with
$nsgProd = Get-AzNetworkSecurityGroup -ResourceGroupName $ProdResourceGroup -Name 'prod-skycraft-swc-nsg'

Write-Host "Adding rule: AllowAuthServer (Port 3724)..." -ForegroundColor Yellow
$nsgProd | Add-AzNetworkSecurityRuleConfig `
    -Name 'AllowAuthServer' `
    -Description 'Allow traffic to Auth Server ASG' `
    -Access Allow `
    -Protocol Tcp `
    -Direction Inbound `
    -Priority 1000 `
    -SourceAddressPrefix '*' `
    -SourcePortRange '*' `
    -DestinationApplicationSecurityGroup $asgs['prod-skycraft-swc-asg-auth'] `
    -DestinationPortRange 3724 `
    -ErrorAction SilentlyContinue | Out-Null

Write-Host "Adding rule: AllowWorldServer (Port 8085)..." -ForegroundColor Yellow
$nsgProd | Add-AzNetworkSecurityRuleConfig `
    -Name 'AllowWorldServer' `
    -Description 'Allow traffic to World Server ASG' `
    -Access Allow `
    -Protocol Tcp `
    -Direction Inbound `
    -Priority 1100 `
    -SourceAddressPrefix '*' `
    -SourcePortRange '*' `
    -DestinationApplicationSecurityGroup $asgs['prod-skycraft-swc-asg-world'] `
    -DestinationPortRange 8085 `
    -ErrorAction SilentlyContinue | Out-Null

Write-Host "Adding rule: AllowAppToDB (Port 3306)..." -ForegroundColor Yellow
$nsgProd | Add-AzNetworkSecurityRuleConfig `
    -Name 'AllowAppToDB' `
    -Description 'Allow Auth and World ASGs to talk to DB ASG' `
    -Access Allow `
    -Protocol Tcp `
    -Direction Inbound `
    -Priority 2000 `
    -SourceApplicationSecurityGroup @($asgs['prod-skycraft-swc-asg-auth'], $asgs['prod-skycraft-swc-asg-world']) `
    -SourcePortRange '*' `
    -DestinationApplicationSecurityGroup $asgs['prod-skycraft-swc-asg-db'] `
    -DestinationPortRange 3306 `
    -ErrorAction SilentlyContinue | Out-Null

Write-Host "Saving NSG configuration..." -ForegroundColor Yellow
try {
    $nsgProd | Set-AzNetworkSecurityGroup | Out-Null
    Write-Host "  -> NSG rules configured successfully" -ForegroundColor Green
}
catch {
    Write-Host "  -> [ERROR] Failed to save NSG rules" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    exit 1
}

# ===================================
# Task 5: Associate NSG to Subnets
# ===================================
Write-Host "`n=== Task 5: Associating NSG to Subnets ===" -ForegroundColor Cyan

try {
    $vnet = Get-AzVirtualNetwork -ResourceGroupName $ProdResourceGroup -Name $ProdVnetName
    $nsgProd = Get-AzNetworkSecurityGroup -ResourceGroupName $ProdResourceGroup -Name 'prod-skycraft-swc-nsg'

    $subnetsToUpdate = @('AuthSubnet', 'WorldSubnet', 'DatabaseSubnet')

    foreach ($subnetName in $subnetsToUpdate) {
        Write-Host "Associating NSG to $subnetName..." -ForegroundColor Yellow
        $subnet = $vnet.Subnets | Where-Object { $_.Name -eq $subnetName }
        if ($subnet) {
            $subnet.NetworkSecurityGroup = $nsgProd
            Write-Host "  -> Associated NSG to $subnetName" -ForegroundColor Green
        }
        else {
            Write-Host "  -> [WARNING] Subnet $subnetName not found" -ForegroundColor Yellow
        }
    }

    # Save the VNet configuration
    $vnet | Set-AzVirtualNetwork | Out-Null
    Write-Host "VNet configuration saved successfully" -ForegroundColor Green
}
catch {
    Write-Host "[ERROR] Failed to associate NSG to subnets" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    exit 1
}

# ===================================
# Task 6: Deploy Azure Bastion (Optional)
# ===================================
Write-Host "`n=== Task 6: Deploying Azure Bastion (Optional) ===" -ForegroundColor Cyan
Write-Host "Checking if Bastion already exists..." -ForegroundColor Yellow

$bastion = Get-AzBastion -ResourceGroupName $PlatformResourceGroup -Name 'platform-skycraft-swc-bas' -ErrorAction SilentlyContinue

if ($bastion) {
    Write-Host "  -> Bastion already exists, skipping deployment" -ForegroundColor Gray
}
else {
    Write-Host "Do you want to deploy Azure Bastion? (This will take ~15 minutes and incur costs)" -ForegroundColor Yellow
    $response = Read-Host "Deploy Bastion? (y/N)"
    
    if ($response -eq 'y' -or $response -eq 'Y') {
        Write-Host "Creating Bastion Public IP..." -ForegroundColor Yellow
        try {
            $bastionPip = New-AzPublicIpAddress `
                -ResourceGroupName $PlatformResourceGroup `
                -Name 'platform-skycraft-swc-bas-pip' `
                -Location $Location `
                -AllocationMethod Static `
                -Sku Standard `
                -Tag $Tags
            Write-Host "  -> Created Bastion Public IP" -ForegroundColor Green

            # Get the VNet and Bastion Subnet
            $vnetHub = Get-AzVirtualNetwork -ResourceGroupName $PlatformResourceGroup -Name $PlatformVnetName
            $bastionSubnet = $vnetHub.Subnets | Where-Object { $_.Name -eq 'AzureBastionSubnet' }

            if (-not $bastionSubnet) {
                Write-Host "  -> [ERROR] AzureBastionSubnet not found in $PlatformVnetName" -ForegroundColor Red
                exit 1
            }

            Write-Host "Creating Azure Bastion (this will take ~15 minutes)..." -ForegroundColor Yellow
            $bastion = New-AzBastion `
                -ResourceGroupName $PlatformResourceGroup `
                -Name 'platform-skycraft-swc-bas' `
                -PublicIpAddress $bastionPip `
                -VirtualNetwork $vnetHub `
                -Sku Basic `
                -Tag $Tags
            Write-Host "  -> Bastion created successfully!" -ForegroundColor Green
        }
        catch {
            Write-Host "  -> [ERROR] Failed to create Bastion" -ForegroundColor Red
            Write-Host $_.Exception.Message -ForegroundColor Red
        }
    }
    else {
        Write-Host "  -> Skipping Bastion deployment" -ForegroundColor Gray
    }
}

Write-Host "`n=== Deployment Complete ===" -ForegroundColor Cyan -BackgroundColor Black
Write-Host "Run Test-Lab.ps1 to verify the deployment" -ForegroundColor Green
