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
    5. Optionally deploy Azure Bastion (-DeployBastion, or an interactive prompt).

    It enforces project tagging standards: every resource carries the canonical four tags
    (Project, Environment, CostCenter, Owner), and the hub resources are tagged Platform.

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

.PARAMETER Owner
    Value of the canonical Owner tag. Default: 'mbiszczanik'. Mirrors parOwner in the Bicep path.

.PARAMETER DeployBastion
    Deploy Azure Bastion without prompting. Without it the script asks, and a non-interactive
    session declines - which is not an error.

.EXAMPLE
    .\Deploy-Security.ps1
    Deploys all security resources using default settings, prompting about Bastion.

.EXAMPLE
    .\Deploy-Security.ps1 -DeployBastion
    Deploys all security resources including Azure Bastion, with no prompt.

.NOTES
    Project: SkyCraft
    Lab: 2.2 - Secure Access
    Author: Ops Team
    Version: 2.1.0
    Date: 2026-08-28
#>

#Requires -Version 7.0
#Requires -Modules Az.Accounts, Az.Network

[CmdletBinding()]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Deploy script; -DeployBastion switch and idempotent Get-before-New guards cover ShouldProcess intent.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'ProdVnetName', Justification = 'Used as -VnetName in Set-SubnetSecurity calls; PSSA nested-scope false positive.')]
param(
    [Parameter(Mandatory = $false)]
    [ValidateSet('swedencentral', 'northeurope')]
    [string]$Location = 'swedencentral',

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$ProdResourceGroup = 'prod-skycraft-swc-rg',

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$PlatformResourceGroup = 'platform-skycraft-swc-rg',

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$ProdVnetName = 'prod-skycraft-swc-vnet',

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$PlatformVnetName = 'platform-skycraft-swc-vnet',

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$Owner = 'mbiszczanik',

    [Parameter(Mandatory = $false)]
    [switch]$DeployBastion
)

$ErrorActionPreference = 'Stop'

Write-Host "=== Lab 2.2 - Deploy Security Configuration (PowerShell) ===" -ForegroundColor Cyan -BackgroundColor Black

# Verify Azure Connection
$context = Get-AzContext
if (-not $context) {
    Write-Host "Not logged in. Please run Connect-AzAccount" -ForegroundColor Red
    exit 1
}
Write-Host "Connected to: $($context.Subscription.Name)" -ForegroundColor Green

# Canonical four-tag set. The hub resources are Platform, not Production - the Bicep path
# tags them varTagsPlatform, and a mismatch showed up as ten what-if Modify entries (#100).
$PlatformTags = @{
    Project     = 'SkyCraft'
    Environment = 'Platform'
    CostCenter  = 'MSDN'
    Owner       = $Owner
}

# Counts tasks that failed without aborting the script (subnet association, Bastion).
$script:taskFailures = 0

# ===================================
# Task 1: Create Application Security Groups
# ===================================
Write-Host "`n=== Task 1: Creating Application Security Groups ===" -ForegroundColor Cyan

$asgConfigs = @(
    @{ Name = 'dev-skycraft-swc-asg-auth'; RG = 'dev-skycraft-swc-rg' },
    @{ Name = 'dev-skycraft-swc-asg-world'; RG = 'dev-skycraft-swc-rg' },
    @{ Name = 'dev-skycraft-swc-asg-db'; RG = 'dev-skycraft-swc-rg' },
    @{ Name = 'prod-skycraft-swc-asg-auth'; RG = $ProdResourceGroup },
    @{ Name = 'prod-skycraft-swc-asg-world'; RG = $ProdResourceGroup },
    @{ Name = 'prod-skycraft-swc-asg-db'; RG = $ProdResourceGroup }
)

$asgs = @{}
foreach ($config in $asgConfigs) {
    Write-Host "Creating ASG: $($config.Name)..." -ForegroundColor Yellow
    try {
        $asg = Get-AzApplicationSecurityGroup -ResourceGroupName $config.RG -Name $config.Name -ErrorAction SilentlyContinue
        if ($asg) {
            Write-Host "  -> ASG already exists: $($config.Name)" -ForegroundColor Gray
        }
        else {
            $tagEnv = if ($config.RG -match 'prod') { 'Production' } else { 'Development' }
            $tags = @{ Project = 'SkyCraft'; Environment = $tagEnv; CostCenter = 'MSDN'; Owner = $Owner }
            
            $asg = New-AzApplicationSecurityGroup `
                -ResourceGroupName $config.RG `
                -Name $config.Name `
                -Location $Location `
                -Tag $tags
            Write-Host "  -> Created ASG: $($config.Name)" -ForegroundColor Green
        }
        $asgs[$config.Name] = $asg
    }
    catch {
        Write-Host "  -> [ERROR] Failed to create ASG: $($config.Name)" -ForegroundColor Red
        Write-Host $_.Exception.Message -ForegroundColor Red
        exit 1
    }
}

# ===================================
# Task 2: Create Network Security Groups
# ===================================
Write-Host "`n=== Task 2: Creating Network Security Groups ===" -ForegroundColor Cyan

function New-SkyCraftNSG {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Internal helper; parent script guards idempotency via Get-before-New.')]
    param($Name, $RG, $Env)
    Write-Host "Creating NSG: $Name..." -ForegroundColor Yellow
    try {
        $nsg = Get-AzNetworkSecurityGroup -ResourceGroupName $RG -Name $Name -ErrorAction SilentlyContinue
        if ($nsg) {
            Write-Host "  -> NSG already exists, will update rules" -ForegroundColor Gray
        } else {
            $tags = @{ Project = 'SkyCraft'; Environment = $Env; CostCenter = 'MSDN'; Owner = $Owner }
            $nsg = New-AzNetworkSecurityGroup -ResourceGroupName $RG -Name $Name -Location $Location -Tag $tags
            Write-Host "  -> Created NSG: $Name" -ForegroundColor Green
        }
        return $nsg
    } catch {
        Write-Host "  -> [ERROR] Failed to create NSG: $Name - $_" -ForegroundColor Red
        exit 1
    }
}

$nsgDevAuth  = New-SkyCraftNSG -Name "dev-skycraft-swc-auth-nsg"  -RG "dev-skycraft-swc-rg"  -Env "Development"
$nsgDevWorld = New-SkyCraftNSG -Name "dev-skycraft-swc-world-nsg" -RG "dev-skycraft-swc-rg"  -Env "Development"
$nsgDevDb    = New-SkyCraftNSG -Name "dev-skycraft-swc-db-nsg"    -RG "dev-skycraft-swc-rg"  -Env "Development"

$nsgProdAuth  = New-SkyCraftNSG -Name "prod-skycraft-swc-auth-nsg"  -RG $ProdResourceGroup -Env "Production"
$nsgProdWorld = New-SkyCraftNSG -Name "prod-skycraft-swc-world-nsg" -RG $ProdResourceGroup -Env "Production"
$nsgProdDb    = New-SkyCraftNSG -Name "prod-skycraft-swc-db-nsg"    -RG $ProdResourceGroup -Env "Production"

# Platform NSG
$null = New-SkyCraftNSG -Name "platform-skycraft-swc-nsg" -RG $PlatformResourceGroup -Env "Platform"

# ===================================
# Task 3 & 4: Configure NSG Rules
# ===================================
Write-Host "`n=== Task 3 & 4: Configuring NSG Rules ===" -ForegroundColor Cyan

function Add-Rule {
    param($NSG, $Name, $Priority, $DestPort, $SrcPrefix = '*', $Desc)
    Write-Host "Adding/Updating rule: $Name to $($NSG.Name)..." -ForegroundColor Yellow
    
    # Check if rule exists to avoid conflicts
    $existing = $NSG.SecurityRules | Where-Object { $_.Name -eq $Name }
    
    # Determine if we use Prefix (Single) or Prefixes (Array)
    # Validated: SourceAddressPrefix parameter accepts string array.
    
    if ($existing) {
        $NSG | Set-AzNetworkSecurityRuleConfig -Name $Name -Description $Desc -Access Allow -Protocol Tcp -Direction Inbound -Priority $Priority -SourceAddressPrefix $SrcPrefix -SourcePortRange '*' -DestinationAddressPrefix '*' -DestinationPortRange $DestPort | Out-Null
    } else {
        $NSG | Add-AzNetworkSecurityRuleConfig -Name $Name -Description $Desc -Access Allow -Protocol Tcp -Direction Inbound -Priority $Priority -SourceAddressPrefix $SrcPrefix -SourcePortRange '*' -DestinationAddressPrefix '*' -DestinationPortRange $DestPort | Out-Null
    }
}

# Dev Rules
Add-Rule -NSG $nsgDevAuth  -Name "Allow-SSH-From-Bastion" -Priority 100 -DestPort 22 -SrcPrefix "10.0.0.0/26" -Desc "Allow SSH from Bastion"
Add-Rule -NSG $nsgDevAuth  -Name "Allow-Auth-GamePort"    -Priority 110 -DestPort 3724 -Desc "Allow Auth Game Port"
$nsgDevAuth | Set-AzNetworkSecurityGroup | Out-Null

Add-Rule -NSG $nsgDevWorld -Name "Allow-SSH-From-Bastion" -Priority 100 -DestPort 22 -SrcPrefix "10.0.0.0/26" -Desc "Allow SSH from Bastion"
Add-Rule -NSG $nsgDevWorld -Name "Allow-World-GamePort"   -Priority 110 -DestPort 8085 -Desc "Allow World Game Port"
$nsgDevWorld | Set-AzNetworkSecurityGroup | Out-Null

Add-Rule -NSG $nsgDevDb    -Name "Allow-SSH-From-Bastion" -Priority 100 -DestPort 22 -SrcPrefix "10.0.0.0/26" -Desc "Allow SSH from Bastion"
Add-Rule -NSG $nsgDevDb    -Name "Allow-MySQL-From-AppTier" -Priority 110 -DestPort 3306 -SrcPrefix @("10.1.1.0/24","10.1.2.0/24") -Desc "Allow MySQL from App Subnets"
$nsgDevDb | Set-AzNetworkSecurityGroup | Out-Null

# Prod Rules
Add-Rule -NSG $nsgProdAuth  -Name "Allow-SSH-From-Bastion" -Priority 100 -DestPort 22 -SrcPrefix "10.0.0.0/26" -Desc "Allow SSH from Bastion"
Add-Rule -NSG $nsgProdAuth  -Name "Allow-Auth-GamePort"    -Priority 110 -DestPort 3724 -Desc "Allow Auth Game Port"
$nsgProdAuth | Set-AzNetworkSecurityGroup | Out-Null

Add-Rule -NSG $nsgProdWorld -Name "Allow-SSH-From-Bastion" -Priority 100 -DestPort 22 -SrcPrefix "10.0.0.0/26" -Desc "Allow SSH from Bastion"
Add-Rule -NSG $nsgProdWorld -Name "Allow-World-GamePort"   -Priority 110 -DestPort 8085 -Desc "Allow World Game Port"
$nsgProdWorld | Set-AzNetworkSecurityGroup | Out-Null

Add-Rule -NSG $nsgProdDb    -Name "Allow-SSH-From-Bastion" -Priority 100 -DestPort 22 -SrcPrefix "10.0.0.0/26" -Desc "Allow SSH from Bastion"
Add-Rule -NSG $nsgProdDb    -Name "Allow-MySQL-From-AppTier" -Priority 110 -DestPort 3306 -SrcPrefix @("10.2.1.0/24","10.2.2.0/24") -Desc "Allow MySQL from App Subnets"
$nsgProdDb | Set-AzNetworkSecurityGroup | Out-Null

# ===================================
# Task 5: Associate NSG to Subnets & Configure Service Endpoints
# ===================================
Write-Host "`n=== Task 5: Associating NSG to Subnets & Service Endpoints ===" -ForegroundColor Cyan

# Service endpoints are per-subnet, not a single on/off switch: the Bicep path puts
# Microsoft.Storage on WorldSubnet and Microsoft.Sql + Microsoft.Storage on DatabaseSubnet.
# The old boolean set both on DatabaseSubnet only, which left WorldSubnet without the endpoint
# Lab 4.4's storage firewall rule requires - so the manual path could not reach Lab 4.4 (#98).
function Set-SubnetSecurity {
    param($VnetName, $RgName, $SubnetName, $NsgObject, [string[]]$ServiceEndpoints = @())
    try {
        $vnet = Get-AzVirtualNetwork -ResourceGroupName $RgName -Name $VnetName
        $subnet = $vnet.Subnets | Where-Object { $_.Name -eq $SubnetName }
        if ($subnet) {
            Write-Host "Configuring $SubnetName in $VnetName..." -ForegroundColor Yellow
            $subnet.NetworkSecurityGroup = $NsgObject

            if ($ServiceEndpoints.Count -gt 0) {
                Write-Host "  -> Enabling Service Endpoints ($($ServiceEndpoints -join ', '))..." -ForegroundColor Yellow
                # No Locations: the Bicep path (AVM virtual-network/subnet) records these endpoints
                # region-unrestricted, and a mismatch makes every subsequent what-if report a Modify.
                $subnet.ServiceEndpoints = @($ServiceEndpoints | ForEach-Object { @{ Service = $_ } })
            }

            $vnet | Set-AzVirtualNetwork | Out-Null
            Write-Host "  -> Success" -ForegroundColor Green
        } else {
            Write-Host "  -> [ERROR] Subnet $SubnetName not found in $VnetName" -ForegroundColor Red
            $script:taskFailures++
        }
    } catch {
        Write-Host "  -> [ERROR] Failed to configure ${SubnetName}: $($_.Exception.Message)" -ForegroundColor Red
        $script:taskFailures++
    }
}

# Dev
Set-SubnetSecurity -VnetName "dev-skycraft-swc-vnet" -RgName "dev-skycraft-swc-rg" -SubnetName "AuthSubnet"     -NsgObject $nsgDevAuth
Set-SubnetSecurity -VnetName "dev-skycraft-swc-vnet" -RgName "dev-skycraft-swc-rg" -SubnetName "WorldSubnet"    -NsgObject $nsgDevWorld -ServiceEndpoints @('Microsoft.Storage')
Set-SubnetSecurity -VnetName "dev-skycraft-swc-vnet" -RgName "dev-skycraft-swc-rg" -SubnetName "DatabaseSubnet" -NsgObject $nsgDevDb    -ServiceEndpoints @('Microsoft.Sql', 'Microsoft.Storage')

# Prod
Set-SubnetSecurity -VnetName $ProdVnetName -RgName $ProdResourceGroup -SubnetName "AuthSubnet"     -NsgObject $nsgProdAuth
Set-SubnetSecurity -VnetName $ProdVnetName -RgName $ProdResourceGroup -SubnetName "WorldSubnet"    -NsgObject $nsgProdWorld -ServiceEndpoints @('Microsoft.Storage')
Set-SubnetSecurity -VnetName $ProdVnetName -RgName $ProdResourceGroup -SubnetName "DatabaseSubnet" -NsgObject $nsgProdDb   -ServiceEndpoints @('Microsoft.Sql', 'Microsoft.Storage')

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
    $deployBastionNow = $DeployBastion.IsPresent

    if (-not $deployBastionNow) {
        Write-Host "Do you want to deploy Azure Bastion? (This will take ~15 minutes and incur costs)" -ForegroundColor Yellow
        try {
            $response = Read-Host "Deploy Bastion? (y/N)"
            $deployBastionNow = ($response -eq 'y' -or $response -eq 'Y')
        }
        catch {
            # Non-interactive session (CI, an automated lab cycle). Declining is the safe default
            # and is not a failure - pass -DeployBastion to deploy it without a prompt (#101).
            Write-Host "  -> Non-interactive session; skipping Bastion. Use -DeployBastion to deploy it." -ForegroundColor Gray
            $deployBastionNow = $false
        }
    }

    if ($deployBastionNow) {
        Write-Host "Creating Bastion Public IP..." -ForegroundColor Yellow
        try {
            $bastionPip = New-AzPublicIpAddress `
                -ResourceGroupName $PlatformResourceGroup `
                -Name 'platform-skycraft-swc-bas-pip' `
                -Location $Location `
                -AllocationMethod Static `
                -Sku Standard `
                -Tag $PlatformTags
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
                -Tag $PlatformTags
            Write-Host "  -> Bastion created successfully!" -ForegroundColor Green
        }
        catch {
            Write-Host "  -> [ERROR] Failed to create Bastion" -ForegroundColor Red
            Write-Host $_.Exception.Message -ForegroundColor Red
            $script:taskFailures++
        }
    }
    else {
        Write-Host "  -> Skipping Bastion deployment" -ForegroundColor Gray
    }
}

if ($script:taskFailures -gt 0) {
    Write-Host "`n=== Deployment finished with $($script:taskFailures) failure(s) ===" -ForegroundColor Red -BackgroundColor Black
    Write-Host "See the [ERROR] lines above." -ForegroundColor Red
    exit 1
}

Write-Host "`n=== Deployment Complete ===" -ForegroundColor Cyan -BackgroundColor Black
Write-Host "Run Test-Lab.ps1 to verify the deployment" -ForegroundColor Green
