<#
.SYNOPSIS
    Validates Lab 2.3 DNS zones, links, records, and load balancers.

.DESCRIPTION
    Runs a set of read-only checks against the deployed Lab 2.3 resources and prints a
    pass/fail summary. Exits with a non-zero code if any validation fails. Checks:
      - Public DNS zone, its canonical tags, and required A / CNAME records - the A records
        must point at the load balancer public IPs reserved in Lab 2.1
      - Private DNS zone, its canonical tags, and hub / dev / prod VNet links with the expected
        registration flag
      - Dev and prod load balancers have Standard SKU, >=2 probes, >=2 LB rules, outbound SNAT
        disabled on every LB rule, the egress pool <lb>-be-outbound with an outbound rule for it
        (protocol All, manual port allocation) - the Module 3 VMs' only path to the internet -
        and the canonical tags for their environment. The pools are empty until Lab 3.2, so
        their members are not checked here.

.EXAMPLE
    .\Test-Lab.ps1
    Runs all Lab 2.3 validations using the current Az context.

.NOTES
    Project: SkyCraft
    Lab: 2.3 - Name Resolution & Load Balancing
    Author: Marcin Biszczanik
    Date: 2026-01-11
#>

#Requires -Version 7.0
#Requires -Modules Az.Accounts, Az.Dns, Az.Network

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
# Exit-Lab ends the script with exit code 0 or 1 and leaves an interactive session open (#257).
Import-Module (Join-Path $PSScriptRoot '../../../tools/LabCommon.psm1') -Force -Verbose:$false

Write-Host "=== Lab 2.3 Validation Script ===" -ForegroundColor Cyan -BackgroundColor Black

# 1. Verify Azure Connection
$context = Get-AzContext
if (-not $context) {
    Write-Host "Not logged in. Please run Connect-AzAccount" -ForegroundColor Red
    Exit-Lab -FailureCount 1
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
    
    foreach ($t in @('Project', 'Environment', 'CostCenter', 'Owner')) {
        if (-not $pubZone.Tags -or [string]::IsNullOrWhiteSpace($pubZone.Tags[$t])) {
            Write-Host "  - [FAIL] Public DNS zone is missing tag '$t'" -ForegroundColor Red
            $validationErrors++
        }
    }
    if ($pubZone.Tags -and $pubZone.Tags['Environment'] -ne 'Platform') {
        Write-Host "  - [FAIL] Public DNS zone tag 'Environment' is '$($pubZone.Tags['Environment'])' (Expected Platform)" -ForegroundColor Red
        $validationErrors++
    }

    # Check Records. The two A records must resolve to the load balancer public IPs Lab 2.1 reserved.
    $recs = @(
        @{ Name = 'dev';  Type = 'A';     PipRg = $DevRG;  PipName = 'dev-skycraft-swc-lb-pip' },
        @{ Name = 'play'; Type = 'A';     PipRg = $ProdRG; PipName = 'prod-skycraft-swc-lb-pip' },
        @{ Name = 'game'; Type = 'CNAME' }
    )
    foreach ($r in $recs) {
        $rec = Get-AzDnsRecordSet -ResourceGroupName $PlatformRG -ZoneName $PublicDnsZoneName -Name $r.Name -RecordType $r.Type -ErrorAction SilentlyContinue
        if ($rec) {
            Write-Host "  - [OK] Record '$($r.Name)' found ($($rec.RecordType))" -ForegroundColor Green
            if ($r.PipName) {
                $pip = Get-AzPublicIpAddress -ResourceGroupName $r.PipRg -Name $r.PipName -ErrorAction SilentlyContinue
                $recorded = @($rec.Records | ForEach-Object { $_.Ipv4Address })
                if (-not $pip) {
                    Write-Host "    - [FAIL] Public IP '$($r.PipName)' NOT found - cannot verify record value" -ForegroundColor Red
                    $validationErrors++
                } elseif ($recorded -contains $pip.IpAddress) {
                    Write-Host "    - [OK] Record '$($r.Name)' points at $($pip.IpAddress)" -ForegroundColor Green
                } else {
                    Write-Host "    - [FAIL] Record '$($r.Name)' is $($recorded -join ', ') (Expected $($pip.IpAddress) from $($r.PipName))" -ForegroundColor Red
                    $validationErrors++
                }
            }
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

    foreach ($t in @('Project', 'Environment', 'CostCenter', 'Owner')) {
        if (-not $privZone.Tags -or [string]::IsNullOrWhiteSpace($privZone.Tags[$t])) {
            Write-Host "  - [FAIL] Private DNS zone is missing tag '$t'" -ForegroundColor Red
            $validationErrors++
        }
    }
    if ($privZone.Tags -and $privZone.Tags['Environment'] -ne 'Platform') {
        Write-Host "  - [FAIL] Private DNS zone tag 'Environment' is '$($privZone.Tags['Environment'])' (Expected Platform)" -ForegroundColor Red
        $validationErrors++
    }

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
    param($RgName, $LbName, $ExpectedEnvironment)
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

        # Egress (docs/bicep-standards.md section 4.5). The Lab 2.1 subnets are private, so the
        # Module 3 VMs reach the internet only through the outbound rule. A frontend IP takes one
        # outbound rule with an overlapping protocol, so the rule (protocol All) serves one egress
        # pool, '<lb>-be-outbound', which Lab 3.2 puts every VM NIC into. Azure then refuses SNAT on
        # the load balancing rules of that frontend; the check documents the design.
        $snatOn = @($lb.LoadBalancingRules | Where-Object { $_.DisableOutboundSnat -ne $true })
        if ($snatOn.Count -eq 0) {
            Write-Host "  - [OK] Outbound SNAT disabled on all $($lb.LoadBalancingRules.Count) LB rule(s)" -ForegroundColor Green
        } else {
            Write-Host "  - [FAIL] Outbound SNAT not disabled on: $(($snatOn | ForEach-Object { $_.Name }) -join ', ')" -ForegroundColor Red
            $script:validationErrors++
        }

        $egressPoolName = "$LbName-be-outbound"
        $egressPool = $lb.BackendAddressPools | Where-Object { $_.Name -eq $egressPoolName }
        if ($egressPool) {
            Write-Host "  - [OK] Egress backend pool found: $egressPoolName" -ForegroundColor Green
            # Pools are compared by name (the last segment of the ID), case-insensitively.
            $egressRules = @($lb.OutboundRules | Where-Object {
                $_.BackendAddressPool.Id -and ($_.BackendAddressPool.Id -split '/')[-1] -eq $egressPoolName
            })
            $goodRules = @($egressRules | Where-Object { $_.Protocol -eq 'All' -and $_.AllocatedOutboundPorts -gt 0 })
            if ($goodRules.Count -gt 0) {
                Write-Host "  - [OK] Outbound rule $($goodRules[0].Name) serves $egressPoolName (All, $($goodRules[0].AllocatedOutboundPorts) ports per instance)" -ForegroundColor Green
            } elseif ($egressRules.Count -gt 0) {
                Write-Host "  - [FAIL] Outbound rule $($egressRules[0].Name) for $egressPoolName has protocol $($egressRules[0].Protocol) and $($egressRules[0].AllocatedOutboundPorts) allocated ports (Expected All, more than 0)" -ForegroundColor Red
                $script:validationErrors++
            } else {
                Write-Host "  - [FAIL] No outbound rule uses $egressPoolName - the Module 3 VMs would have no internet access" -ForegroundColor Red
                $script:validationErrors++
            }
        } else {
            Write-Host "  - [FAIL] Egress backend pool NOT found: $egressPoolName" -ForegroundColor Red
            $script:validationErrors++
        }

        foreach ($t in @('Project', 'Environment', 'CostCenter', 'Owner')) {
            if (-not $lb.Tag -or [string]::IsNullOrWhiteSpace($lb.Tag[$t])) {
                Write-Host "  - [FAIL] $LbName is missing tag '$t'" -ForegroundColor Red
                $script:validationErrors++
            }
        }
        if ($lb.Tag -and $lb.Tag['Environment'] -ne $ExpectedEnvironment) {
            Write-Host "  - [FAIL] $LbName tag 'Environment' is '$($lb.Tag['Environment'])' (Expected $ExpectedEnvironment)" -ForegroundColor Red
            $script:validationErrors++
        }
    } else {
        Write-Host "[FAIL] Load Balancer NOT found: $LbName" -ForegroundColor Red
        $script:validationErrors++
    }
}

Test-LB -RgName $DevRG -LbName 'dev-skycraft-swc-lb' -ExpectedEnvironment 'Development'
Test-LB -RgName $ProdRG -LbName 'prod-skycraft-swc-lb' -ExpectedEnvironment 'Production'


# Summary
Write-Host "`n=== Validation Summary ===" -ForegroundColor Cyan
if ($validationErrors -eq 0) {
    Write-Host "Lab 2.3 validation complete. All checks passed!" -ForegroundColor Green -BackgroundColor Black
} else {
    Write-Host "Lab 2.3 validation failed with $validationErrors error(s). Please review the logs above." -ForegroundColor Red -BackgroundColor Black
}
Exit-Lab -FailureCount $validationErrors
