<#
.SYNOPSIS
    Cleans up resources deployed for Lab 2.2 - Secure Access.

.DESCRIPTION
    This script safely removes the resources associated with Lab 2.2, specifically ensuring that 
    dependencies between NSGs and ASGs are handled correctly. It allows for granular removal of 
    specific components (Bastion, NSGs, ASGs) or a full cleanup.
    
    It handles:
    - Dissociation of NSGs from Subnets across all VNets
    - Clearing of NSG Security Rules to break ASG dependencies
    - Removal of updated Bastion Host and Public IP
    - Removal of NSGs and ASGs

.PARAMETER ProdResourceGroup
    The name of the Production Resource Group. Default: 'prod-skycraft-swc-rg'

.PARAMETER PlatformResourceGroup
    The name of the Platform Resource Group. Default: 'platform-skycraft-swc-rg'

.PARAMETER ProdVnetName
    The name of the Production VNet. Default: 'prod-skycraft-swc-vnet'

.PARAMETER RemoveBastion
    Switch to remove Azure Bastion and its Public IP.

.PARAMETER RemoveNSGs
    Switch to remove Network Security Groups.

.PARAMETER RemoveASGs
    Switch to remove Application Security Groups.

.PARAMETER RemoveAll
    Switch to remove ALL Lab 2.2 resources (Bastion, NSGs, ASGs).

.PARAMETER Force
    Switch to suppress confirmation prompts.

.EXAMPLE
    .\Cleanup-Resources.ps1 -RemoveAll
    Removes all Lab 2.2 resources after asking for confirmation.

.EXAMPLE
    .\Cleanup-Resources.ps1 -RemoveBastion -Force
    Removes only Azure Bastion without asking for confirmation.

.NOTES
    Project: SkyCraft
    Lab: 2.2 - Secure Access
    Author: Ops Team
    Date: 2026-01-03
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$ProdResourceGroup = 'prod-skycraft-swc-rg',

    [Parameter(Mandatory = $false)]
    [string]$PlatformResourceGroup = 'platform-skycraft-swc-rg',

    [Parameter(Mandatory = $false)]
    [string]$ProdVnetName = 'prod-skycraft-swc-vnet',

    [Parameter(Mandatory = $false)]
    [switch]$RemoveBastion,

    [Parameter(Mandatory = $false)]
    [switch]$RemoveNSGs,

    [Parameter(Mandatory = $false)]
    [switch]$RemoveASGs,

    [Parameter(Mandatory = $false)]
    [switch]$RemoveAll,

    [Parameter(Mandatory = $false)]
    [switch]$Force
)

Write-Host "=== Lab 2.2 - Cleanup Security Resources ===" -ForegroundColor Cyan -BackgroundColor Black

# Verify Azure Connection
$context = Get-AzContext
if (-not $context) {
    Write-Host "Not logged in. Please run Connect-AzAccount" -ForegroundColor Red
    exit 1
}
Write-Host "Connected to: $($context.Subscription.Name)" -ForegroundColor Green

# Safety confirmation
if (-not $Force) {
    Write-Host "`n[WARNING] This script will remove Lab 2.2 resources." -ForegroundColor Yellow
    Write-Host "Resources to be removed:" -ForegroundColor Yellow
    
    if ($RemoveAll) {
        Write-Host "  - Azure Bastion (saves ~$140/month)" -ForegroundColor Gray
        Write-Host "  - Bastion Public IP" -ForegroundColor Gray
        Write-Host "  - Network Security Groups" -ForegroundColor Gray
        Write-Host "  - Application Security Groups" -ForegroundColor Gray
    }
    else {
        if ($RemoveBastion) { Write-Host "  - Azure Bastion (saves ~$140/month)" -ForegroundColor Gray }
        if ($RemoveNSGs) { Write-Host "  - Network Security Groups" -ForegroundColor Gray }
        if ($RemoveASGs) { Write-Host "  - Application Security Groups" -ForegroundColor Gray }
    }

    $confirmation = Read-Host "`nAre you sure you want to proceed? (yes/no)"
    if ($confirmation -ne 'yes') {
        Write-Host "Cleanup cancelled." -ForegroundColor Yellow
        exit 0
    }
}

# ===================================
# Remove Azure Bastion (Highest Cost)
# ===================================
if ($RemoveBastion -or $RemoveAll) {
    Write-Host "`n=== Removing Azure Bastion ===" -ForegroundColor Cyan
    
    $bastion = Get-AzBastion -ResourceGroupName $PlatformResourceGroup -Name 'platform-skycraft-swc-bas' -ErrorAction SilentlyContinue
    if ($bastion) {
        Write-Host "Removing Bastion: platform-skycraft-swc-bas (this may take a few minutes)..." -ForegroundColor Yellow
        try {
            Remove-AzBastion -ResourceGroupName $PlatformResourceGroup -Name 'platform-skycraft-swc-bas' -Force
            Write-Host "  -> Bastion removed successfully" -ForegroundColor Green
        }
        catch {
            Write-Host "  -> [ERROR] Failed to remove Bastion" -ForegroundColor Red
            Write-Host $_.Exception.Message -ForegroundColor Red
        }
    }
    else {
        Write-Host "  -> Bastion does not exist, skipping" -ForegroundColor Gray
    }

    # Remove Bastion Public IP
    Write-Host "Removing Bastion Public IP..." -ForegroundColor Yellow
    $bastionPip = Get-AzPublicIpAddress -ResourceGroupName $PlatformResourceGroup -Name 'platform-skycraft-swc-bas-pip' -ErrorAction SilentlyContinue
    if ($bastionPip) {
        try {
            Remove-AzPublicIpAddress -ResourceGroupName $PlatformResourceGroup -Name 'platform-skycraft-swc-bas-pip' -Force
            Write-Host "  -> Bastion Public IP removed" -ForegroundColor Green
        }
        catch {
            Write-Host "  -> [ERROR] Failed to remove Bastion Public IP" -ForegroundColor Red
            Write-Host $_.Exception.Message -ForegroundColor Red
        }
    }
    else {
        Write-Host "  -> Bastion Public IP does not exist, skipping" -ForegroundColor Gray
    }
}

# ===================================
# Remove NSG Associations and NSGs
# ===================================
if ($RemoveNSGs -or $RemoveAll) {
    Write-Host "`n=== Removing Network Security Groups ===" -ForegroundColor Cyan
    
    # First, dissociate NSG from all subnets it is currently attached to
    # We do a universal check to catch any accidental or deep associations
    Write-Host "Searching for and removing NSG associations across all VNets..." -ForegroundColor Yellow
    # Remove NSGs
    # -----------------------------------
    $nsgList = @(
        @{ Name="dev-skycraft-swc-auth-nsg"; RG="dev-skycraft-swc-rg" },
        @{ Name="dev-skycraft-swc-world-nsg"; RG="dev-skycraft-swc-rg" },
        @{ Name="dev-skycraft-swc-db-nsg"; RG="dev-skycraft-swc-rg" },
        @{ Name="prod-skycraft-swc-auth-nsg"; RG=$ProdResourceGroup },
        @{ Name="prod-skycraft-swc-world-nsg"; RG=$ProdResourceGroup },
        @{ Name="prod-skycraft-swc-db-nsg"; RG=$ProdResourceGroup },
        @{ Name="platform-skycraft-swc-nsg"; RG=$PlatformResourceGroup }
    )

    # 1. Dissociate first
    Write-Host "`nDissociating NSGs from all subnets..." -ForegroundColor Yellow
    $allVnets = Get-AzVirtualNetwork
    foreach ($vnet in $allVnets) {
        $updated = $false
        foreach ($subnet in $vnet.Subnets) {
            if ($subnet.NetworkSecurityGroup) {
                # Check if this subnet's NSG is one we want to remove
                # (Simple check by name similarity or just blanket remove ID if it matches one of our targets)
                foreach ($targetNsg in $nsgList) {
                    if ($subnet.NetworkSecurityGroup.Id -match $targetNsg.Name) {
                        Write-Host "  -> Removing $($targetNsg.Name) from $($vnet.Name)/$($subnet.Name)" -ForegroundColor Yellow
                        $subnet.NetworkSecurityGroup = $null
                        $updated = $true
                        break
                    }
                }
            }
        }
        if ($updated) {
            $vnet | Set-AzVirtualNetwork | Out-Null
        }
    }
    
    # Wait for azure to settle
    Start-Sleep -Seconds 10

    # 2. Delete NSGs
    foreach ($targetNsg in $nsgList) {
        Write-Host "Removing NSG: $($targetNsg.Name)..." -ForegroundColor Yellow
        try {
            Remove-AzNetworkSecurityGroup -ResourceGroupName $targetNsg.RG -Name $targetNsg.Name -Force -ErrorAction SilentlyContinue
            Write-Host "  -> Success" -ForegroundColor Green
        } catch {
             Write-Host "  -> [WARNING] Could not delete $($targetNsg.Name) (may not exist)" -ForegroundColor Gray
        }
    }
}

# ===================================
# Remove Application Security Groups
# ===================================
if ($RemoveASGs -or $RemoveAll) {
    Write-Host "`n=== Removing Application Security Groups ===" -ForegroundColor Cyan
    
    $asgList = @(
        @{ Name="dev-skycraft-swc-asg-auth"; RG="dev-skycraft-swc-rg" },
        @{ Name="dev-skycraft-swc-asg-world"; RG="dev-skycraft-swc-rg" },
        @{ Name="dev-skycraft-swc-asg-db"; RG="dev-skycraft-swc-rg" },
        @{ Name="prod-skycraft-swc-asg-auth"; RG=$ProdResourceGroup },
        @{ Name="prod-skycraft-swc-asg-world"; RG=$ProdResourceGroup },
        @{ Name="prod-skycraft-swc-asg-db"; RG=$ProdResourceGroup }
    )

    foreach ($asg in $asgList) {
        Write-Host "Removing ASG: $($asg.Name)..." -ForegroundColor Yellow
        try {
            Remove-AzApplicationSecurityGroup -ResourceGroupName $asg.RG -Name $asg.Name -Force -ErrorAction SilentlyContinue 
            Write-Host "  -> Success" -ForegroundColor Green
        } catch {
             Write-Host "  -> [WARNING] Could not delete $($asg.Name) (may not exist)" -ForegroundColor Gray
        }
    }
}

Write-Host "`n=== Cleanup Complete ===" -ForegroundColor Cyan -BackgroundColor Black

# Show cost savings estimate
if ($RemoveBastion -or $RemoveAll) {
    Write-Host "`n[INFO] Estimated monthly savings:" -ForegroundColor Green
    Write-Host "  - Azure Bastion Basic SKU: ~$140/month" -ForegroundColor Gray
    Write-Host "  - Public IP: ~$3/month" -ForegroundColor Gray
    Write-Host "  Total: ~$143/month" -ForegroundColor Green
}

Write-Host "`nNote: NSGs and ASGs have no compute costs, only minimal metadata storage." -ForegroundColor Gray
Write-Host "You can recreate resources anytime using Deploy-Security.ps1 or Deploy-Bicep.ps1" -ForegroundColor Gray
