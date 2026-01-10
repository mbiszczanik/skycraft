[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$PublicDnsZoneName = 'skycraft.example.com',

    [Parameter(Mandatory = $false)]
    [string]$PrivateDnsZoneName = 'skycraft.internal',

    [Parameter(Mandatory = $false)]
    [string]$PlatformRG = 'platform-skycraft-swc-rg',

    [Parameter(Mandatory = $false)]
    [string]$DevRG = 'dev-skycraft-swc-rg',

    [Parameter(Mandatory = $false)]
    [string]$ProdRG = 'prod-skycraft-swc-rg',

    [Parameter(Mandatory = $false)]
    [string]$DevLbName = 'dev-skycraft-swc-lb',

    [Parameter(Mandatory = $false)]
    [string]$ProdLbName = 'prod-skycraft-swc-lb'
)

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
    Write-Host "Removing Public DNS Zone: $PublicDnsZoneName..." -ForegroundColor Yellow
    Remove-AzDnsZone -ResourceGroupName $PlatformRG -Name $PublicDnsZoneName -Confirm:$false
    Write-Host "  -> Deleted" -ForegroundColor Green
} else {
    Write-Host "  -> Public Zone not found" -ForegroundColor Gray
}

# 3. Cleanup Load Balancers
Write-Host "`n=== Cleaning up Load Balancers ===" -ForegroundColor Cyan

# Dev LB
if (Get-AzLoadBalancer -ResourceGroupName $DevRG -Name $DevLbName -ErrorAction SilentlyContinue) {
    Write-Host "Removing Dev Load Balancer: $DevLbName..." -ForegroundColor Yellow
    Remove-AzLoadBalancer -ResourceGroupName $DevRG -Name $DevLbName -Force
    Write-Host "  -> Deleted" -ForegroundColor Green
} else {
    Write-Host "  -> Dev LB not found" -ForegroundColor Gray
}

# Prod LB
if (Get-AzLoadBalancer -ResourceGroupName $ProdRG -Name $ProdLbName -ErrorAction SilentlyContinue) {
    Write-Host "Removing Prod Load Balancer: $ProdLbName..." -ForegroundColor Yellow
    Remove-AzLoadBalancer -ResourceGroupName $ProdRG -Name $ProdLbName -Force
    Write-Host "  -> Deleted" -ForegroundColor Green
} else {
    Write-Host "  -> Prod LB not found" -ForegroundColor Gray
}

# 4. Cleanup Private DNS Links & Zone
Write-Host "`n=== Cleaning up Private DNS ===" -ForegroundColor Cyan

# Links
$links = Get-AzPrivateDnsVirtualNetworkLink -ResourceGroupName $PlatformRG -ZoneName $PrivateDnsZoneName -ErrorAction SilentlyContinue
foreach ($link in $links) {
    Write-Host "Removing link: $($link.Name)..." -ForegroundColor Yellow
    Remove-AzPrivateDnsVirtualNetworkLink -ResourceGroupName $PlatformRG -ZoneName $PrivateDnsZoneName -Name $link.Name -Confirm:$false
    Write-Host "  -> Deleted" -ForegroundColor Green
}

# Zone
if (Get-AzPrivateDnsZone -ResourceGroupName $PlatformRG -Name $PrivateDnsZoneName -ErrorAction SilentlyContinue) {
    Write-Host "Removing Private DNS Zone: $PrivateDnsZoneName..." -ForegroundColor Yellow
    Remove-AzPrivateDnsZone -ResourceGroupName $PlatformRG -Name $PrivateDnsZoneName -Confirm:$false
    Write-Host "  -> Deleted" -ForegroundColor Green
} else {
    Write-Host "  -> Private Zone not found" -ForegroundColor Gray
}

Write-Host "`n=== Cleanup Complete ===" -ForegroundColor Green
