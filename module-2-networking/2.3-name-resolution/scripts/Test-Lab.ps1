[CmdletBinding()]
param()

Write-Host "=== Lab 2.3 Validation Script ===" -ForegroundColor Cyan -BackgroundColor Black

# 1. Verify Azure Connection
$context = Get-AzContext
if (-not $context) {
    Write-Host "Not logged in. Please run Connect-AzAccount" -ForegroundColor Red
    exit 1
}
Write-Host "Connected to: $($context.Subscription.Name)" -ForegroundColor Green

$validationErrors = 0
$PublicDnsZoneName = 'skycraft.example.com'
$PrivateDnsZoneName = 'skycraft.internal'
$PlatformRG = 'platform-skycraft-swc-rg'
$DevRG = 'dev-skycraft-swc-rg'
$ProdRG = 'prod-skycraft-swc-rg'

# ==========================================
# TEST 1: Public DNS Zone & Records
# ==========================================
Write-Host "`n=== 1. Validating Public DNS Zone ===" -ForegroundColor Cyan
$pubZone = Get-AzDnsZone -ResourceGroupName $PlatformRG -Name $PublicDnsZoneName -ErrorAction SilentlyContinue
if ($pubZone) {
    Write-Host "[OK] Public DNS Zone found: $PublicDnsZoneName" -ForegroundColor Green
    
    # Check Records
    $recs = @(
        @{ Name = 'dev'; Type = 'A' },
        @{ Name = 'play'; Type = 'A' },
        @{ Name = 'game'; Type = 'CNAME' }
    )
    foreach ($r in $recs) {
        $rec = Get-AzDnsRecordSet -ResourceGroupName $PlatformRG -ZoneName $PublicDnsZoneName -Name $r.Name -RecordType $r.Type -ErrorAction SilentlyContinue
        if ($rec) {
            Write-Host "  - [OK] Record '$($r.Name)' found ($($rec.RecordType))" -ForegroundColor Green
        } else {
            Write-Host "  - [FAIL] Record '$($r.Name)' NOT found" -ForegroundColor Red
            $validationErrors++
        }
    }
} else {
    Write-Host "[FAIL] Public DNS Zone NOT found: $PublicDnsZoneName" -ForegroundColor Red
    $validationErrors++
}


# ==========================================
# TEST 2: Private DNS Zone & Links
# ==========================================
Write-Host "`n=== 2. Validating Private DNS Zone ===" -ForegroundColor Cyan
$privZone = Get-AzPrivateDnsZone -ResourceGroupName $PlatformRG -Name $PrivateDnsZoneName -ErrorAction SilentlyContinue
if ($privZone) {
    Write-Host "[OK] Private DNS Zone found: $PrivateDnsZoneName" -ForegroundColor Green

    # Check Links
    $links = Get-AzPrivateDnsVirtualNetworkLink -ResourceGroupName $PlatformRG -ZoneName $PrivateDnsZoneName -ErrorAction SilentlyContinue
    
    # Hub Link (No Reg)
    $hubLink = $links | Where-Object { $_.Name -eq 'hub-vnet-link' }
    if ($hubLink) {
        if ($hubLink.RegistrationEnabled -eq $false) {
             Write-Host "  - [OK] Link 'hub-vnet-link' found (Reg: False)" -ForegroundColor Green
        } else {
             Write-Host "  - [FAIL] Link 'hub-vnet-link' has Reg: True (Expected False)" -ForegroundColor Red
             $validationErrors++
        }
    } else {
        Write-Host "  - [FAIL] Link 'hub-vnet-link' NOT found" -ForegroundColor Red
        $validationErrors++
    }

    # Dev/Prod Links (Reg)
    foreach ($l in @('dev-vnet-link', 'prod-vnet-link')) {
        $link = $links | Where-Object { $_.Name -eq $l }
        if ($link) {
            if ($link.RegistrationEnabled -eq $true) {
                 Write-Host "  - [OK] Link '$l' found (Reg: True)" -ForegroundColor Green
            } else {
                 Write-Host "  - [FAIL] Link '$l' has Reg: False (Expected True)" -ForegroundColor Red
                 $validationErrors++
            }
        } else {
            Write-Host "  - [FAIL] Link '$l' NOT found" -ForegroundColor Red
            $validationErrors++
        }
    }
} else {
    Write-Host "[FAIL] Private DNS Zone NOT found: $PrivateDnsZoneName" -ForegroundColor Red
    $validationErrors++
}


# ==========================================
# TEST 3: Load Balancers
# ==========================================
Write-Host "`n=== 3. Validating Load Balancers ===" -ForegroundColor Cyan

function Test-LB {
    param($RgName, $LbName)
    $lb = Get-AzLoadBalancer -ResourceGroupName $RgName -Name $LbName -ErrorAction SilentlyContinue
    if ($lb) {
        Write-Host "[OK] Load Balancer found: $LbName" -ForegroundColor Green
        # Check SKU
        if ($lb.Sku.Name -eq 'Standard') {
            Write-Host "  - [OK] SKU is Standard" -ForegroundColor Green
        } else {
            Write-Host "  - [FAIL] SKU is $($lb.Sku.Name) (Expected Standard)" -ForegroundColor Red
             $script:validationErrors++
        }
        
        # Check Probes
        if ($lb.Probes.Count -ge 2) {
             Write-Host "  - [OK] Health Probes found ($($lb.Probes.Count))" -ForegroundColor Green
        } else {
             Write-Host "  - [FAIL] Missing Health Probes (Found $($lb.Probes.Count))" -ForegroundColor Red
             $script:validationErrors++
        }

        # Check Rules
        if ($lb.LoadBalancingRules.Count -ge 2) {
             Write-Host "  - [OK] LB Rules found ($($lb.LoadBalancingRules.Count))" -ForegroundColor Green
        } else {
             Write-Host "  - [FAIL] Missing LB Rules (Found $($lb.LoadBalancingRules.Count))" -ForegroundColor Red
             $script:validationErrors++
        }
    } else {
        Write-Host "[FAIL] Load Balancer NOT found: $LbName" -ForegroundColor Red
        $script:validationErrors++
    }
}

Test-LB -RgName $DevRG -LbName 'dev-skycraft-swc-lb'
Test-LB -RgName $ProdRG -LbName 'prod-skycraft-swc-lb'


# Summary
Write-Host "`n=== Validation Summary ===" -ForegroundColor Cyan
if ($validationErrors -eq 0) {
    Write-Host "Lab 2.3 validation complete. All checks passed!" -ForegroundColor Green -BackgroundColor Black
} else {
    Write-Host "Lab 2.3 validation failed with $validationErrors error(s). Please review the logs above." -ForegroundColor Red -BackgroundColor Black
    exit 1
}
