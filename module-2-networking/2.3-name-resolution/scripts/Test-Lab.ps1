[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$DnsZoneName = 'skycraft.internal',

    [Parameter(Mandatory = $false)]
    [string]$PlatformRG = 'platform-skycraft-swc-rg'
)

Write-Host "=== Lab 2.3 Validation Script ===" -ForegroundColor Cyan -BackgroundColor Black

# 1. Verify Azure Connection
$context = Get-AzContext
if (-not $context) {
    Write-Host "Not logged in. Please run Connect-AzAccount" -ForegroundColor Red
    exit 1
}
Write-Host "Connected to: $($context.Subscription.Name)" -ForegroundColor Green

$validationErrors = 0

# 2. Check DNS Zone
Write-Host "`n=== 1. Validating Private DNS Zone ===" -ForegroundColor Cyan
$zone = Get-AzPrivateDnsZone -ResourceGroupName $PlatformRG -Name $DnsZoneName -ErrorAction SilentlyContinue
if ($zone) {
    Write-Host "[OK] Private DNS Zone found: $DnsZoneName" -ForegroundColor Green
} else {
    Write-Host "[FAIL] Private DNS Zone NOT found: $DnsZoneName" -ForegroundColor Red
    $validationErrors++
}

# 3. Check VNet Links
Write-Host "`n=== 2. Validating Virtual Network Links ===" -ForegroundColor Cyan
if ($zone) {
    $links = Get-AzPrivateDnsVirtualNetworkLink -ResourceGroupName $PlatformRG -ZoneName $DnsZoneName -ErrorAction SilentlyContinue
    
    $hubLink = $links | Where-Object { $_.Name -eq 'link-to-hub' }
    if ($hubLink -and $hubLink.LinkStatus -eq 'Completed') {
        Write-Host "[OK] Hub VNet Link found and Completed" -ForegroundColor Green
        if ($hubLink.RegistrationEnabled) {
            Write-Host "  - [OK] Auto-Registration: Enabled" -ForegroundColor Green
        } else {
            Write-Host "  - [FAIL] Auto-Registration: Disabled" -ForegroundColor Yellow
        }
    } else {
        Write-Host "[FAIL] Hub VNet Link missing or not completed" -ForegroundColor Red
        $validationErrors++
    }

    $spokeLink = $links | Where-Object { $_.Name -eq 'link-to-prod' }
    if ($spokeLink -and $spokeLink.LinkStatus -eq 'Completed') {
        Write-Host "[OK] Spoke VNet Link found and Completed" -ForegroundColor Green
        if ($spokeLink.RegistrationEnabled) {
            Write-Host "  - [OK] Auto-Registration: Enabled" -ForegroundColor Green
        } else {
            Write-Host "  - [FAIL] Auto-Registration: Disabled" -ForegroundColor Yellow
        }
    } else {
        Write-Host "[FAIL] Spoke VNet Link missing or not completed" -ForegroundColor Red
        $validationErrors++
    }
}

# Summary
Write-Host "`n=== Validation Summary ===" -ForegroundColor Cyan
if ($validationErrors -eq 0) {
    Write-Host "Lab 2.3 validation complete. All checks passed!" -ForegroundColor Green -BackgroundColor Black
} else {
    Write-Host "Lab 2.3 validation failed with $validationErrors error(s). Please review the logs above." -ForegroundColor Red -BackgroundColor Black
    exit 1
}
