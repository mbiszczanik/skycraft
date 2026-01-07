<#
.SYNOPSIS
    Deploys Lab 2.3 DNS resources using native PowerShell cmdlets.

.DESCRIPTION
    Tasks performed:
    1. Create Private DNS Zone (skycraft.internal).
    2. Link to Hub VNet with Auto-Registration.
    3. Link to Spoke VNet with Auto-Registration.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$DnsZoneName = 'skycraft.internal',

    [Parameter(Mandatory = $false)]
    [string]$PlatformRG = 'platform-skycraft-swc-rg',

    [Parameter(Mandatory = $false)]
    [string]$ProdRG = 'prod-skycraft-swc-rg',

    [Parameter(Mandatory = $false)]
    [string]$HubVnetName = 'platform-skycraft-swc-vnet',

    [Parameter(Mandatory = $false)]
    [string]$SpokeVnetName = 'prod-skycraft-swc-vnet'
)

Write-Host "=== Lab 2.3 - Deploy DNS Configuration (PowerShell) ===" -ForegroundColor Cyan -BackgroundColor Black

# 1. Verify Azure Connection
$context = Get-AzContext
if (-not $context) {
    Write-Host "Not logged in. Please run Connect-AzAccount" -ForegroundColor Red
    exit 1
}

$Tags = @{
    Project     = 'SkyCraft'
    Environment = 'Production'
    CostCenter  = 'MSDN'
}

# 2. Create DNS Zone
Write-Host "`n=== Task 1: Creating Private DNS Zone ===" -ForegroundColor Cyan
try {
    $zone = Get-AzPrivateDnsZone -ResourceGroupName $PlatformRG -Name $DnsZoneName -ErrorAction SilentlyContinue
    if ($zone) {
        Write-Host "  -> Zone already exists: $DnsZoneName" -ForegroundColor Gray
    } else {
        Write-Host "Creating Private DNS Zone: $DnsZoneName..." -ForegroundColor Yellow
        $zone = New-AzPrivateDnsZone -ResourceGroupName $PlatformRG -Name $DnsZoneName -Tag $Tags
        Write-Host "  -> Created Zone: $DnsZoneName" -ForegroundColor Green
    }
} catch {
    Write-Host "  -> [ERROR] Failed to create DNS Zone: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# 3. Create VNet Links
Write-Host "`n=== Task 2: Linking Virtual Networks ===" -ForegroundColor Cyan

# Link to Hub
try {
    $hubLink = Get-AzPrivateDnsVirtualNetworkLink -ResourceGroupName $PlatformRG -ZoneName $DnsZoneName -Name 'link-to-hub' -ErrorAction SilentlyContinue
    if ($hubLink) {
        Write-Host "  -> Hub link already exists" -ForegroundColor Gray
    } else {
        Write-Host "Linking Hub VNet..." -ForegroundColor Yellow
        $hubVnet = Get-AzVirtualNetwork -ResourceGroupName $PlatformRG -Name $HubVnetName
        New-AzPrivateDnsVirtualNetworkLink -ResourceGroupName $PlatformRG -ZoneName $DnsZoneName -Name 'link-to-hub' -VirtualNetworkId $hubVnet.Id -EnableRegistration
        Write-Host "  -> Hub link created (Auto-Registration: Enabled)" -ForegroundColor Green
    }
} catch {
    Write-Host "  -> [ERROR] Failed to link Hub VNet: $($_.Exception.Message)" -ForegroundColor Red
}

# Link to Spoke
try {
    $spokeLink = Get-AzPrivateDnsVirtualNetworkLink -ResourceGroupName $PlatformRG -ZoneName $DnsZoneName -Name 'link-to-prod' -ErrorAction SilentlyContinue
    if ($spokeLink) {
        Write-Host "  -> Spoke link already exists" -ForegroundColor Gray
    } else {
        Write-Host "Linking Spoke VNet..." -ForegroundColor Yellow
        $spokeVnet = Get-AzVirtualNetwork -ResourceGroupName $ProdRG -Name $SpokeVnetName
        New-AzPrivateDnsVirtualNetworkLink -ResourceGroupName $PlatformRG -ZoneName $DnsZoneName -Name 'link-to-prod' -VirtualNetworkId $spokeVnet.Id -EnableRegistration
        Write-Host "  -> Spoke link created (Auto-Registration: Enabled)" -ForegroundColor Green
    }
} catch {
    Write-Host "  -> [ERROR] Failed to link Spoke VNet: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host "`n=== Deployment Complete ===" -ForegroundColor Cyan -BackgroundColor Black
Write-Host "Run Test-Lab.ps1 to verify the DNS configuration" -ForegroundColor Green
