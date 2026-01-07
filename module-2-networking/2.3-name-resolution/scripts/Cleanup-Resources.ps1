[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$DnsZoneName = 'skycraft.internal',

    [Parameter(Mandatory = $false)]
    [string]$PlatformRG = 'platform-skycraft-swc-rg'
)

Write-Host "=== Lab 2.3 Cleanup Script ===" -ForegroundColor Cyan -BackgroundColor Black

# 1. Verify Azure Connection
$context = Get-AzContext
if (-not $context) {
    Write-Host "Not logged in. Please run Connect-AzAccount" -ForegroundColor Red
    exit 1
}

# 2. Delete VNet Links
Write-Host "`nDeleting Virtual Network Links..." -ForegroundColor Yellow
$links = Get-AzPrivateDnsVirtualNetworkLink -ResourceGroupName $PlatformRG -ZoneName $DnsZoneName -ErrorAction SilentlyContinue
foreach ($link in $links) {
    Write-Host "  -> Removing link: $($link.Name)..." -ForegroundColor Gray
    Remove-AzPrivateDnsVirtualNetworkLink -ResourceGroupName $PlatformRG -ZoneName $DnsZoneName -Name $link.Name -Force
}

# 3. Delete DNS Zone
Write-Host "`nDeleting Private DNS Zone: $DnsZoneName..." -ForegroundColor Yellow
if (Get-AzPrivateDnsZone -ResourceGroupName $PlatformRG -Name $DnsZoneName -ErrorAction SilentlyContinue) {
    Remove-AzPrivateDnsZone -ResourceGroupName $PlatformRG -Name $DnsZoneName -Force
    Write-Host "  -> DNS Zone deleted" -ForegroundColor Green
} else {
    Write-Host "  -> DNS Zone not found, skipping" -ForegroundColor Gray
}

Write-Host "`n=== Cleanup Complete ===" -ForegroundColor Green
