<#
.SYNOPSIS
    Removes Lab 2.3 DNS zones, VNet links, and dev/prod load balancers.

.DESCRIPTION
    Cleanup script for Lab 2.3. Removes resources in the safe order: public DNS zone,
    both load balancers, private DNS VNet links, private DNS zone. Each removal is
    guarded by a Get-* existence check so the script is idempotent and can be re-run.

    Private DNS VNet link deletion is asynchronous: Remove-AzPrivateDnsVirtualNetworkLink
    returns before ARM has released the link, and deleting the zone too early fails with
    "Cannot delete resource while nested resources exist". The zone deletion is retried on
    that specific error until the links have drained.

.PARAMETER PublicDnsZoneName
    Public DNS zone to delete. Defaults to 'skycraft.example.com'.

.PARAMETER PrivateDnsZoneName
    Private DNS zone to delete. Defaults to 'skycraft.internal'.

.PARAMETER PlatformRG
    Resource group that hosts the DNS zones. Defaults to 'platform-skycraft-swc-rg'.

.PARAMETER DevRG
    Resource group that hosts the dev load balancer. Defaults to 'dev-skycraft-swc-rg'.

.PARAMETER ProdRG
    Resource group that hosts the prod load balancer. Defaults to 'prod-skycraft-swc-rg'.

.PARAMETER DevLbName
    Name of the dev load balancer. Defaults to 'dev-skycraft-swc-lb'.

.PARAMETER ProdLbName
    Name of the prod load balancer. Defaults to 'prod-skycraft-swc-lb'.

.PARAMETER Force
    Skips the confirmation prompt before removing resources.

.EXAMPLE
    .\Remove-LabResource.ps1
    Removes all Lab 2.3 DNS and load balancer resources using the default names.

.NOTES
    Project: SkyCraft
    Lab: 2.3 - Name Resolution & Load Balancing
    Author: Marcin Biszczanik
    Version: 2.1.0
    Date: 2026-08-28
#>

#Requires -Version 7.0
#Requires -Modules Az.Accounts, Az.Dns, Az.Network

[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$PublicDnsZoneName = 'skycraft.example.com',

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$PrivateDnsZoneName = 'skycraft.internal',

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$PlatformRG = 'platform-skycraft-swc-rg',

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$DevRG = 'dev-skycraft-swc-rg',

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$ProdRG = 'prod-skycraft-swc-rg',

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$DevLbName = 'dev-skycraft-swc-lb',

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$ProdLbName = 'prod-skycraft-swc-lb',

    [switch]$Force
)

$ErrorActionPreference = 'Stop'
if ($Force) { $ConfirmPreference = 'None' }

Write-Host "=== Lab 2.3 Cleanup Script ===" -ForegroundColor Cyan -BackgroundColor Black

# 1. Verify Azure Connection
$context = Get-AzContext
if (-not $context) {
    Write-Host "Not logged in. Please run Connect-AzAccount" -ForegroundColor Red
    exit 1
}

# 2. Cleanup Public DNS
Write-Host "`n=== Cleaning up Public DNS ===" -ForegroundColor Cyan
if (Get-AzDnsZone -ResourceGroupName $PlatformRG -Name $PublicDnsZoneName -ErrorAction SilentlyContinue) {
    if ($PSCmdlet.ShouldProcess($PublicDnsZoneName, 'Remove public DNS zone')) {
        Write-Host "Removing Public DNS Zone: $PublicDnsZoneName..." -ForegroundColor Yellow
        Remove-AzDnsZone -ResourceGroupName $PlatformRG -Name $PublicDnsZoneName -Confirm:$false
        Write-Host "  -> Deleted" -ForegroundColor Green
    }
} else {
    Write-Host "  -> Public Zone not found" -ForegroundColor Gray
}

# 3. Cleanup Load Balancers
Write-Host "`n=== Cleaning up Load Balancers ===" -ForegroundColor Cyan

# Dev LB
if (Get-AzLoadBalancer -ResourceGroupName $DevRG -Name $DevLbName -ErrorAction SilentlyContinue) {
    if ($PSCmdlet.ShouldProcess($DevLbName, 'Remove load balancer')) {
        Write-Host "Removing Dev Load Balancer: $DevLbName..." -ForegroundColor Yellow
        Remove-AzLoadBalancer -ResourceGroupName $DevRG -Name $DevLbName -Force
        Write-Host "  -> Deleted" -ForegroundColor Green
    }
} else {
    Write-Host "  -> Dev LB not found" -ForegroundColor Gray
}

# Prod LB
if (Get-AzLoadBalancer -ResourceGroupName $ProdRG -Name $ProdLbName -ErrorAction SilentlyContinue) {
    if ($PSCmdlet.ShouldProcess($ProdLbName, 'Remove load balancer')) {
        Write-Host "Removing Prod Load Balancer: $ProdLbName..." -ForegroundColor Yellow
        Remove-AzLoadBalancer -ResourceGroupName $ProdRG -Name $ProdLbName -Force
        Write-Host "  -> Deleted" -ForegroundColor Green
    }
} else {
    Write-Host "  -> Prod LB not found" -ForegroundColor Gray
}

# 4. Cleanup Private DNS Links & Zone
Write-Host "`n=== Cleaning up Private DNS ===" -ForegroundColor Cyan

# Links
$links = Get-AzPrivateDnsVirtualNetworkLink -ResourceGroupName $PlatformRG -ZoneName $PrivateDnsZoneName -ErrorAction SilentlyContinue
foreach ($link in $links) {
    if ($PSCmdlet.ShouldProcess($link.Name, 'Remove private DNS VNet link')) {
        Write-Host "Removing link: $($link.Name)..." -ForegroundColor Yellow
        Remove-AzPrivateDnsVirtualNetworkLink -ResourceGroupName $PlatformRG -ZoneName $PrivateDnsZoneName -Name $link.Name -Confirm:$false
        Write-Host "  -> Deleted" -ForegroundColor Green
    }
}

# Zone
if (Get-AzPrivateDnsZone -ResourceGroupName $PlatformRG -Name $PrivateDnsZoneName -ErrorAction SilentlyContinue) {
    if ($PSCmdlet.ShouldProcess($PrivateDnsZoneName, 'Remove private DNS zone')) {
        Write-Host "Removing Private DNS Zone: $PrivateDnsZoneName..." -ForegroundColor Yellow

        # Link deletion is asynchronous, and ARM still counts the links as nested resources for
        # a few seconds after Get-AzPrivateDnsVirtualNetworkLink has stopped returning them - so
        # polling the link list is not a reliable signal. Retry the delete itself on exactly the
        # nested-resource error instead; anything else fails immediately (#97).
        $maxAttempts = 12
        $delaySeconds = 5

        for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
            try {
                Remove-AzPrivateDnsZone -ResourceGroupName $PlatformRG -Name $PrivateDnsZoneName -Confirm:$false
                Write-Host "  -> Deleted" -ForegroundColor Green
                break
            }
            catch {
                if ($_.Exception.Message -notmatch 'nested resource') {
                    Write-Host "  -> [ERROR] Could not delete the private DNS zone: $($_.Exception.Message)" -ForegroundColor Red
                    exit 1
                }

                if ($attempt -eq $maxAttempts) {
                    Write-Host "  -> [ERROR] VNet links were still draining after $($maxAttempts * $delaySeconds)s. Re-run this script." -ForegroundColor Red
                    exit 1
                }

                Write-Host "  -> VNet links still draining, retrying in ${delaySeconds}s ($attempt/$maxAttempts)..." -ForegroundColor Gray
                Start-Sleep -Seconds $delaySeconds
            }
        }
    }
} else {
    Write-Host "  -> Private Zone not found" -ForegroundColor Gray
}

Write-Host "`n=== Cleanup Complete ===" -ForegroundColor Green
