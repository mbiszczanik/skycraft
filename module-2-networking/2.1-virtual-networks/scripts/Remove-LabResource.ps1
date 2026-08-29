<#
.SYNOPSIS
    Cleans up resources created in Lab 2.1.

.DESCRIPTION
    This script removes the Hub and Spoke Virtual Networks (Dev/Prod), their peering
    configurations, and Public IPs. It prompts for confirmation unless the -Force switch is used.

    A resource that is genuinely absent is reported as [INFO] and is not an error. A resource
    that exists but cannot be deleted is reported as [ERROR] with the Azure error message, and
    the script exits 1 - so a masked failure cannot be mistaken for a clean cleanup.

.PARAMETER Force
    Skip the confirmation prompt.

.EXAMPLE
    .\Remove-LabResource.ps1
    Prompts for confirmation before deleting resources.

.EXAMPLE
    .\Remove-LabResource.ps1 -Force
    Deletes resources without prompting.

.NOTES
    Project: SkyCraft
    Lab: 2.1 - Virtual Networks
    Author: Marcin Biszczanik
    Version: 2.1.0
    Date: 2026-08-28
#>

#Requires -Version 7.0
#Requires -Modules Az.Accounts, Az.Network

[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory = $false)]
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
if ($Force) { $ConfirmPreference = 'None' }

Write-Host "=== Lab 2.1 - Resource Cleanup ===" -ForegroundColor Cyan -BackgroundColor Black

# Verify Azure Connection
$context = Get-AzContext
if (-not $context) {
    Write-Host "Not logged in. Please run Connect-AzAccount" -ForegroundColor Red
    $Host.SetShouldExit(1)
    exit 1
}

$hubRgName = "platform-skycraft-swc-rg"
$hubVnetName = "platform-skycraft-swc-vnet"

$devRgName = "dev-skycraft-swc-rg"
$devVnetName = "dev-skycraft-swc-vnet"

$prodRgName = "prod-skycraft-swc-rg"
$prodVnetName = "prod-skycraft-swc-vnet"

# Counts resources that exist but could not be deleted. Absent resources are not failures.
$script:cleanupFailures = 0

Write-Host "`nStarting cleanup..." -ForegroundColor Cyan

# Function to remove peerings
function Remove-VNetPeering {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param($VnetName, $RgName)
    try {
        Write-Host "Removing peerings on $VnetName..." -ForegroundColor Yellow
        $vnet = Get-AzVirtualNetwork -Name $VnetName -ResourceGroupName $RgName -ErrorAction SilentlyContinue
        if ($vnet) {
            # No name filter: SkyCraft peerings are named hub-to-dev / dev-to-hub etc., and every peering
            # on a lab VNet is lab state. Leaving the spoke side behind is what caused
            # RemotePeeringIsDisconnected on the next Lab 2.1 deployment during the #87 live cycle.
            $peerings = $vnet.VirtualNetworkPeerings
            foreach ($p in $peerings) {
                if ($PSCmdlet.ShouldProcess("$VnetName/$($p.Name)", 'Remove VNet peering')) {
                    Write-Host "  -> Deleting $($p.Name)" -ForegroundColor Gray
                    Remove-AzVirtualNetworkPeering -VirtualNetworkName $VnetName -ResourceGroupName $RgName -Name $p.Name -Force -ErrorAction Stop
                }
            }
        }
    } catch {
        $script:cleanupFailures++
        Write-Host "  - [ERROR] Failed to remove peering on ${VnetName}: $($_.Exception.Message)" -ForegroundColor Red
    }
}

Remove-VNetPeering -VnetName $hubVnetName -RgName $hubRgName
Remove-VNetPeering -VnetName $devVnetName -RgName $devRgName
Remove-VNetPeering -VnetName $prodVnetName -RgName $prodRgName

# Function to remove VNet
function Remove-VNet {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param($VnetName, $RgName)

    # Probe first. A bare catch reported every failure as "not found or already deleted", which
    # hid a real InUseSubnetCannotBeDeleted on the prod VNet during the #93 live cycle (#96).
    $vnet = Get-AzVirtualNetwork -Name $VnetName -ResourceGroupName $RgName -ErrorAction SilentlyContinue
    if (-not $vnet) {
        Write-Host "  - [INFO] VNet $VnetName not found or already deleted." -ForegroundColor Gray
        return
    }

    try {
        Write-Host "Removing VNet: $VnetName..." -ForegroundColor Yellow
        if ($PSCmdlet.ShouldProcess($VnetName, 'Remove virtual network')) {
            Remove-AzVirtualNetwork -Name $VnetName -ResourceGroupName $RgName -Force -ErrorAction Stop
            Write-Host "  -> Success" -ForegroundColor Green
        }
    } catch {
        $script:cleanupFailures++
        Write-Host "  - [ERROR] Failed to remove VNet ${VnetName}: $($_.Exception.Message)" -ForegroundColor Red
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
    $existingPip = Get-AzPublicIpAddress -Name $pip.Name -ResourceGroupName $pip.RG -ErrorAction SilentlyContinue
    if (-not $existingPip) {
        Write-Host "  - [INFO] PIP $($pip.Name) not found or already deleted." -ForegroundColor Gray
        continue
    }

    try {
        Write-Host "Removing Public IP: $($pip.Name)..." -ForegroundColor Yellow
        if ($PSCmdlet.ShouldProcess($pip.Name, 'Remove public IP address')) {
            Remove-AzPublicIpAddress -Name $pip.Name -ResourceGroupName $pip.RG -Force -ErrorAction Stop
            Write-Host "  -> Success" -ForegroundColor Green
        }
    } catch {
        $script:cleanupFailures++
        Write-Host "  - [ERROR] Failed to remove PIP $($pip.Name): $($_.Exception.Message)" -ForegroundColor Red
    }
}

if ($script:cleanupFailures -gt 0) {
    Write-Host "`nCleanup finished with $($script:cleanupFailures) failure(s) - see the [ERROR] lines above." -ForegroundColor Red
    $Host.SetShouldExit(1)
    exit 1
}

Write-Host "`nCleanup Complete." -ForegroundColor Green
