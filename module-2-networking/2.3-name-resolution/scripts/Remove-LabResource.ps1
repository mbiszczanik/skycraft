<#
.SYNOPSIS
    Removes Lab 2.3 DNS zones, VNet links, and dev/prod load balancers.

.DESCRIPTION
    Cleanup script for Lab 2.3. Removes resources in the safe order: public DNS zone,
    both load balancers, private DNS VNet links, private DNS zone. Each removal is
    guarded by a Get-* existence check so the script is idempotent and can be re-run.

    Private DNS VNet link deletion is asynchronous: Remove-AzPrivateDnsVirtualNetworkLink
    returns before the link is gone, and deleting the zone too early fails with
    "Cannot delete resource while nested resources exist". The script waits for the links
    to disappear before touching the zone.

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
$linksRemoved = $false
foreach ($link in $links) {
    if ($PSCmdlet.ShouldProcess($link.Name, 'Remove private DNS VNet link')) {
        Write-Host "Removing link: $($link.Name)..." -ForegroundColor Yellow
        Remove-AzPrivateDnsVirtualNetworkLink -ResourceGroupName $PlatformRG -ZoneName $PrivateDnsZoneName -Name $link.Name -Confirm:$false
        Write-Host "  -> Deleted" -ForegroundColor Green
        $linksRemoved = $true
    }
}

# Link deletion is asynchronous. Deleting the zone while a link is still draining fails with
# "Cannot delete resource while nested resources exist" and needs a manual retry (#97).
if ($linksRemoved) {
    $maxAttempts = 12
    $delaySeconds = 5
    for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
        $remaining = @(Get-AzPrivateDnsVirtualNetworkLink -ResourceGroupName $PlatformRG -ZoneName $PrivateDnsZoneName -ErrorAction SilentlyContinue)
        if ($remaining.Count -eq 0) {
            Write-Host "  -> All links drained" -ForegroundColor Green
            break
        }

        if ($attempt -eq $maxAttempts) {
            Write-Host "  -> [ERROR] Links still present after $($maxAttempts * $delaySeconds)s: $($remaining.Name -join ', ')" -ForegroundColor Red
            Write-Host "     The private DNS zone cannot be deleted while they exist. Re-run this script." -ForegroundColor Red
            exit 1
        }

        Write-Host "  -> Waiting for $($remaining.Count) link(s) to finish deleting ($attempt/$maxAttempts)..." -ForegroundColor Gray
        Start-Sleep -Seconds $delaySeconds
    }
}

# Zone
if (Get-AzPrivateDnsZone -ResourceGroupName $PlatformRG -Name $PrivateDnsZoneName -ErrorAction SilentlyContinue) {
    if ($PSCmdlet.ShouldProcess($PrivateDnsZoneName, 'Remove private DNS zone')) {
        Write-Host "Removing Private DNS Zone: $PrivateDnsZoneName..." -ForegroundColor Yellow
        Remove-AzPrivateDnsZone -ResourceGroupName $PlatformRG -Name $PrivateDnsZoneName -Confirm:$false
        Write-Host "  -> Deleted" -ForegroundColor Green
    }
} else {
    Write-Host "  -> Private Zone not found" -ForegroundColor Gray
}

Write-Host "`n=== Cleanup Complete ===" -ForegroundColor Green
