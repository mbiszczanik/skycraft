<#
.SYNOPSIS
    Deploys Lab 2.3 DNS resources using native PowerShell cmdlets.

.DESCRIPTION
    Tasks performed:
    1. Create Public DNS Zone (skycraft.example.com) & Records.
    2. Create Private DNS Zone (skycraft.internal) & Records.
    3. Link Private DNS to VNets (Hub, Dev, Prod).
#>

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
    [string]$HubVnetName = 'platform-skycraft-swc-vnet',

    [Parameter(Mandatory = $false)]
    [string]$DevVnetName = 'dev-skycraft-swc-vnet',

    [Parameter(Mandatory = $false)]
    [string]$ProdVnetName = 'prod-skycraft-swc-vnet',

    [Parameter(Mandatory = $false)]
    [string]$DevLbPipName = 'dev-skycraft-swc-lb-pip',

    [Parameter(Mandatory = $false)]
    [string]$ProdLbPipName = 'prod-skycraft-swc-lb-pip'
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
    Environment = 'Platform'
    CostCenter  = 'MSDN'
}

# ==========================================
# Task 1: Public DNS Zone
# ==========================================
Write-Host "`n=== Task 1: Public DNS Zone ===" -ForegroundColor Cyan

# 1. Create Zone
$pubZone = Get-AzDnsZone -ResourceGroupName $PlatformRG -Name $PublicDnsZoneName -ErrorAction SilentlyContinue
if ($pubZone) {
    Write-Host "  -> Public Zone already exists: $PublicDnsZoneName" -ForegroundColor Gray
} else {
    Write-Host "Creating Public DNS Zone: $PublicDnsZoneName..." -ForegroundColor Yellow
    $pubZone = New-AzDnsZone -ResourceGroupName $PlatformRG -Name $PublicDnsZoneName -Tag $Tags
    Write-Host "  -> Created Zone: $PublicDnsZoneName" -ForegroundColor Green
}

# 2. Get Public IPs
$devPip = Get-AzPublicIpAddress -ResourceGroupName $DevRG -Name $DevLbPipName -ErrorAction SilentlyContinue
$prodPip = Get-AzPublicIpAddress -ResourceGroupName $ProdRG -Name $ProdLbPipName -ErrorAction SilentlyContinue

if (-not $devPip -or -not $prodPip) {
    Write-Host "  -> [WARNING] One or more Public IPs not found. Skipping A record creation." -ForegroundColor Yellow
} else {
    # 3. Create A Records
    $devRecord = Get-AzDnsRecordSet -ResourceGroupName $PlatformRG -ZoneName $PublicDnsZoneName -Name 'dev' -RecordType A -ErrorAction SilentlyContinue
    if (-not $devRecord) {
        New-AzDnsRecordSet -ResourceGroupName $PlatformRG -ZoneName $PublicDnsZoneName -Name 'dev' -RecordType A -Ttl 300 -DnsRecords (New-AzDnsRecordConfig -Ipv4Address $devPip.IpAddress) | Out-Null
        Write-Host "  -> Created A Record: dev.$PublicDnsZoneName -> $($devPip.IpAddress)" -ForegroundColor Green
    } else {
         Write-Host "  -> A Record 'dev' already exists." -ForegroundColor Gray
    }

    $playRecord = Get-AzDnsRecordSet -ResourceGroupName $PlatformRG -ZoneName $PublicDnsZoneName -Name 'play' -RecordType A -ErrorAction SilentlyContinue
    if (-not $playRecord) {
        New-AzDnsRecordSet -ResourceGroupName $PlatformRG -ZoneName $PublicDnsZoneName -Name 'play' -RecordType A -Ttl 300 -DnsRecords (New-AzDnsRecordConfig -Ipv4Address $prodPip.IpAddress) | Out-Null
        Write-Host "  -> Created A Record: play.$PublicDnsZoneName -> $($prodPip.IpAddress)" -ForegroundColor Green
    } else {
         Write-Host "  -> A Record 'play' already exists." -ForegroundColor Gray
    }

    # 4. Create CNAME Record
    $gameRecord = Get-AzDnsRecordSet -ResourceGroupName $PlatformRG -ZoneName $PublicDnsZoneName -Name 'game' -RecordType CNAME -ErrorAction SilentlyContinue
    if (-not $gameRecord) {
        New-AzDnsRecordSet -ResourceGroupName $PlatformRG -ZoneName $PublicDnsZoneName -Name 'game' -RecordType CNAME -Ttl 3600 -DnsRecords (New-AzDnsRecordConfig -Cname "play.$PublicDnsZoneName") | Out-Null
        Write-Host "  -> Created CNAME: game.$PublicDnsZoneName -> play.$PublicDnsZoneName" -ForegroundColor Green
    } else {
         Write-Host "  -> CNAME Record 'game' already exists." -ForegroundColor Gray
    }
}

# ==========================================
# Task 2: Private DNS Zone
# ==========================================
Write-Host "`n=== Task 2: Private DNS Zone ===" -ForegroundColor Cyan

# 1. Create Zone
$privZone = Get-AzPrivateDnsZone -ResourceGroupName $PlatformRG -Name $PrivateDnsZoneName -ErrorAction SilentlyContinue
if ($privZone) {
    Write-Host "  -> Private Zone already exists: $PrivateDnsZoneName" -ForegroundColor Gray
} else {
    Write-Host "Creating Private DNS Zone: $PrivateDnsZoneName..." -ForegroundColor Yellow
    $privZone = New-AzPrivateDnsZone -ResourceGroupName $PlatformRG -Name $PrivateDnsZoneName -Tag $Tags
    Write-Host "  -> Created Zone: $PrivateDnsZoneName" -ForegroundColor Green
}

# 2. Create DB Records (Placeholder)
function New-PrivateDnsRecord {
    param($Name, $Ip)
    $rec = Get-AzPrivateDnsRecordSet -ResourceGroupName $PlatformRG -ZoneName $PrivateDnsZoneName -Name $Name -RecordType A -ErrorAction SilentlyContinue
    if (-not $rec) {
        New-AzPrivateDnsRecordSet -ResourceGroupName $PlatformRG -ZoneName $PrivateDnsZoneName -Name $Name -RecordType A -Ttl 300 -PrivateDnsRecords (New-AzPrivateDnsRecordConfig -Ipv4Address $Ip) | Out-Null
        Write-Host "  -> Created A Record: $Name.$PrivateDnsZoneName -> $Ip" -ForegroundColor Green
    } else {
        Write-Host "  -> A Record '$Name' already exists." -ForegroundColor Gray
    }
}

New-PrivateDnsRecord -Name 'dev-db' -Ip '10.1.3.10'
New-PrivateDnsRecord -Name 'prod-db' -Ip '10.2.3.10'

# ==========================================
# Task 3: VNet Links
# ==========================================
Write-Host "`n=== Task 3: Linking Virtual Networks ===" -ForegroundColor Cyan

function New-PrivateDnsLink {
    param($LinkName, $VnetRG, $VnetName, $AutoReg)
    
    $link = Get-AzPrivateDnsVirtualNetworkLink -ResourceGroupName $PlatformRG -ZoneName $PrivateDnsZoneName -Name $LinkName -ErrorAction SilentlyContinue
    if ($link) {
        Write-Host "  -> Link '$LinkName' already exists." -ForegroundColor Gray
    } else {
        Write-Host "Linking VNet: $VnetName..." -ForegroundColor Yellow
        $vnet = Get-AzVirtualNetwork -ResourceGroupName $VnetRG -Name $VnetName
        if ($vnet) {
            New-AzPrivateDnsVirtualNetworkLink -ResourceGroupName $PlatformRG -ZoneName $PrivateDnsZoneName -Name $LinkName -VirtualNetworkId $vnet.Id -EnableRegistration:$AutoReg | Out-Null
            Write-Host "  -> Link created (AutoReg: $AutoReg)" -ForegroundColor Green
        } else {
             Write-Host "  -> [ERROR] VNet '$VnetName' not found!" -ForegroundColor Red
        }
    }
}

New-PrivateDnsLink -LinkName 'hub-vnet-link' -VnetRG $PlatformRG -VnetName $HubVnetName -AutoReg $false
New-PrivateDnsLink -LinkName 'dev-vnet-link' -VnetRG $DevRG -VnetName $DevVnetName -AutoReg $true
New-PrivateDnsLink -LinkName 'prod-vnet-link' -VnetRG $ProdRG -VnetName $ProdVnetName -AutoReg $true

Write-Host "`n=== DNS Deployment Complete ===" -ForegroundColor Cyan -BackgroundColor Black
