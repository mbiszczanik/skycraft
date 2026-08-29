<#
.SYNOPSIS
    Validates the configuration of Lab 2.2 security resources.

.DESCRIPTION
    This script runs a comprehensive validation suite against the deployed resources to ensure
    they meet the Lab 2.2 requirements, including separate NSGs per subnet and Development environment resources.

    It validates:
    - ASGs: Checks existence of all 6 ASGs (3 Dev, 3 Prod).
    - NSGs: Checks existence of all 7 NSGs (3 Dev, 3 Prod, 1 Platform).
    - NSG Rules: Verifies key rules (SSH, Game Ports, DB Ports) on each NSG.
    - Subnet Associations: Ensures specific NSGs are associated with specific subnets.
    - Service Endpoints: Microsoft.Storage on World subnets, Microsoft.Sql and Microsoft.Storage on Database subnets.
    - Azure Bastion: Checks existence, SKU, public IP and canonical tags when deployed (optional).

.EXAMPLE
    .\Test-Lab.ps1
    Runs all validation checks and outputs Pass/Fail status for each component.

.NOTES
    Project: SkyCraft
    Lab: 2.2 - Secure Access
    Author: Ops Team
    Date: 2026-01-08
#>

#Requires -Version 7.0
#Requires -Modules Az.Accounts, Az.Network

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$script:failCount = 0

Write-Host "=== Lab 2.2 Validation Script ===" -ForegroundColor Cyan -BackgroundColor Black

# Check Azure Connection
$context = Get-AzContext
if (-not $context) {
    Write-Host "Not logged in. Please run Connect-AzAccount" -ForegroundColor Red
    exit 1
}
Write-Host "Connected to: $($context.Subscription.Name)" -ForegroundColor Green

$prodRg = "prod-skycraft-swc-rg"
$devRg  = "dev-skycraft-swc-rg"
$platRg = "platform-skycraft-swc-rg"

$prodVnetName = "prod-skycraft-swc-vnet"
$devVnetName  = "dev-skycraft-swc-vnet"

# 1. Validate Application Security Groups (ASGs)
Write-Host "`n=== 1. Validating Application Security Groups ===" -ForegroundColor Cyan
$expectedAsgs = @(
    @{ Name="dev-skycraft-swc-asg-auth"; RG=$devRg },
    @{ Name="dev-skycraft-swc-asg-world"; RG=$devRg },
    @{ Name="dev-skycraft-swc-asg-db"; RG=$devRg },
    @{ Name="prod-skycraft-swc-asg-auth"; RG=$prodRg },
    @{ Name="prod-skycraft-swc-asg-world"; RG=$prodRg },
    @{ Name="prod-skycraft-swc-asg-db"; RG=$prodRg }
)

foreach ($item in $expectedAsgs) {
    $asg = Get-AzApplicationSecurityGroup -ResourceGroupName $item.RG -Name $item.Name -ErrorAction SilentlyContinue
    if ($asg) { Write-Host "[OK] ASG found: $($item.Name)" -ForegroundColor Green }
    else {
        Write-Host "[FAIL] ASG missing: $($item.Name)" -ForegroundColor Red
        $script:failCount++
    }
}

# 2. Validate Network Security Groups (NSGs)
Write-Host "`n=== 2. Validating Network Security Groups ===" -ForegroundColor Cyan
$nsgs = @(
    @{ Name="dev-skycraft-swc-auth-nsg"; RG=$devRg; Rule="Allow-Auth-GamePort"; Port="3724" },
    @{ Name="dev-skycraft-swc-world-nsg"; RG=$devRg; Rule="Allow-World-GamePort"; Port="8085" },
    @{ Name="dev-skycraft-swc-db-nsg"; RG=$devRg; Rule="Allow-MySQL-From-AppTier"; Port="3306" },
    @{ Name="prod-skycraft-swc-auth-nsg"; RG=$prodRg; Rule="Allow-Auth-GamePort"; Port="3724" },
    @{ Name="prod-skycraft-swc-world-nsg"; RG=$prodRg; Rule="Allow-World-GamePort"; Port="8085" },
    @{ Name="prod-skycraft-swc-db-nsg"; RG=$prodRg; Rule="Allow-MySQL-From-AppTier"; Port="3306" },
    @{ Name="platform-skycraft-swc-nsg"; RG=$platRg; Rule=$null; Port=$null }
)

foreach ($nsgInfo in $nsgs) {
    $nsg = Get-AzNetworkSecurityGroup -ResourceGroupName $nsgInfo.RG -Name $nsgInfo.Name -ErrorAction SilentlyContinue
    if ($nsg) {
        Write-Host "[OK] NSG found: $($nsgInfo.Name)" -ForegroundColor Green

        if ($nsgInfo.Rule) {
            $rule = $nsg.SecurityRules | Where-Object { $_.Name -match $nsgInfo.Rule }
            if ($rule) {
                if ($rule.DestinationPortRange -eq $nsgInfo.Port -and $rule.Access -eq "Allow") {
                    Write-Host "  -> [OK] Rule '$($nsgInfo.Rule)' verified (Port: $($nsgInfo.Port))" -ForegroundColor Gray
                } else {
                    Write-Host "  -> [FAIL] Rule '$($nsgInfo.Rule)' matches incorrect settings" -ForegroundColor Red
                    $script:failCount++
                }
            } else {
                $ruleByPort = $nsg.SecurityRules | Where-Object { $_.DestinationPortRange -eq $nsgInfo.Port }
                if ($ruleByPort) {
                    Write-Host "  -> [OK] Rule for Port $($nsgInfo.Port) found (Name: $($ruleByPort.Name))" -ForegroundColor Gray
                } else {
                    Write-Host "  -> [FAIL] Rule '$($nsgInfo.Rule)' missing" -ForegroundColor Red
                    $script:failCount++
                }
            }
        }
    }
    else {
        Write-Host "[FAIL] NSG missing: $($nsgInfo.Name)" -ForegroundColor Red
        $script:failCount++
    }
}

# 3. Validate Subnet Associations & Service Endpoints
Write-Host "`n=== 3. Validating Subnet Associations & Service Endpoints ===" -ForegroundColor Cyan

function Test-Subnet {
    param($VnetName, $RgName, $SubnetName, $ExpectedNsgName, [string[]]$ExpectedServiceEndpoints = @())
    $vnet = Get-AzVirtualNetwork -Name $VnetName -ResourceGroupName $RgName -ErrorAction SilentlyContinue
    if ($vnet) {
        $sn = $vnet.Subnets | Where-Object { $_.Name -eq $SubnetName }
        if ($sn) {
            if ($sn.NetworkSecurityGroup.Id -match $ExpectedNsgName) {
                Write-Host "[OK] $SubnetName associated with $ExpectedNsgName" -ForegroundColor Green
            } else {
                Write-Host "[FAIL] $SubnetName NOT associated with $ExpectedNsgName (Current: $($sn.NetworkSecurityGroup.Id))" -ForegroundColor Red
                $script:failCount++
            }

            if ($ExpectedServiceEndpoints.Count -gt 0) {
                $present = @($sn.ServiceEndpoints | ForEach-Object { $_.Service })
                $missing = @($ExpectedServiceEndpoints | Where-Object { $present -notcontains $_ })
                if ($missing.Count -eq 0) {
                    Write-Host "  -> [OK] Service Endpoints ($($ExpectedServiceEndpoints -join ', ')) enabled" -ForegroundColor Gray
                } else {
                    Write-Host "  -> [FAIL] Missing Service Endpoints on ${SubnetName}: $($missing -join ', ')" -ForegroundColor Red
                    $script:failCount++
                }
            }
        } else {
            Write-Host "[FAIL] Subnet $SubnetName not found in $VnetName" -ForegroundColor Red
            $script:failCount++
        }
    } else {
        Write-Host "[FAIL] VNet $VnetName not found" -ForegroundColor Red
        $script:failCount++
    }
}

# Dev
Test-Subnet -VnetName $devVnetName -RgName $devRg -SubnetName "AuthSubnet"     -ExpectedNsgName "dev-skycraft-swc-auth-nsg"
Test-Subnet -VnetName $devVnetName -RgName $devRg -SubnetName "WorldSubnet"    -ExpectedNsgName "dev-skycraft-swc-world-nsg" -ExpectedServiceEndpoints 'Microsoft.Storage'
Test-Subnet -VnetName $devVnetName -RgName $devRg -SubnetName "DatabaseSubnet" -ExpectedNsgName "dev-skycraft-swc-db-nsg"    -ExpectedServiceEndpoints 'Microsoft.Sql', 'Microsoft.Storage'

# Prod
Test-Subnet -VnetName $prodVnetName -RgName $prodRg -SubnetName "AuthSubnet"     -ExpectedNsgName "prod-skycraft-swc-auth-nsg"
Test-Subnet -VnetName $prodVnetName -RgName $prodRg -SubnetName "WorldSubnet"    -ExpectedNsgName "prod-skycraft-swc-world-nsg" -ExpectedServiceEndpoints 'Microsoft.Storage'
Test-Subnet -VnetName $prodVnetName -RgName $prodRg -SubnetName "DatabaseSubnet" -ExpectedNsgName "prod-skycraft-swc-db-nsg"    -ExpectedServiceEndpoints 'Microsoft.Sql', 'Microsoft.Storage'

# 4. Validate Azure Bastion (optional)
Write-Host "`n=== 4. Validating Azure Bastion ===" -ForegroundColor Cyan

function Test-CanonicalTagSet {
    param($ResourceLabel, $Tags, $ExpectedEnvironment)
    foreach ($t in @('Project', 'Environment', 'CostCenter', 'Owner')) {
        if (-not $Tags -or [string]::IsNullOrWhiteSpace($Tags[$t])) {
            Write-Host "  -> [FAIL] $ResourceLabel is missing tag '$t'" -ForegroundColor Red
            $script:failCount++
        }
    }
    if ($Tags -and $Tags['Environment'] -ne $ExpectedEnvironment) {
        Write-Host "  -> [FAIL] $ResourceLabel tag 'Environment' is '$($Tags['Environment'])' (Expected $ExpectedEnvironment)" -ForegroundColor Red
        $script:failCount++
    }
}

$bastion = Get-AzBastion -ResourceGroupName $platRg -Name "platform-skycraft-swc-bas" -ErrorAction SilentlyContinue
if ($bastion) {
    Write-Host "[OK] Bastion 'platform-skycraft-swc-bas' found." -ForegroundColor Green

    if ($bastion.Sku.Name -eq 'Basic') {
        Write-Host "  -> [OK] Bastion SKU is Basic" -ForegroundColor Gray
    } else {
        Write-Host "  -> [FAIL] Bastion SKU is $($bastion.Sku.Name) (Expected Basic)" -ForegroundColor Red
        $script:failCount++
    }

    Test-CanonicalTagSet -ResourceLabel "Bastion" -Tags $bastion.Tag -ExpectedEnvironment 'Platform'

    $bastionPip = Get-AzPublicIpAddress -ResourceGroupName $platRg -Name "platform-skycraft-swc-bas-pip" -ErrorAction SilentlyContinue
    if ($bastionPip) {
        Write-Host "  -> [OK] Bastion public IP 'platform-skycraft-swc-bas-pip' found" -ForegroundColor Gray

        if ($bastionPip.Sku.Name -eq 'Standard') {
            Write-Host "  -> [OK] Bastion public IP SKU is Standard" -ForegroundColor Gray
        } else {
            Write-Host "  -> [FAIL] Bastion public IP SKU is $($bastionPip.Sku.Name) (Expected Standard)" -ForegroundColor Red
            $script:failCount++
        }

        if ($bastionPip.PublicIpAllocationMethod -eq 'Static') {
            Write-Host "  -> [OK] Bastion public IP allocation is Static" -ForegroundColor Gray
        } else {
            Write-Host "  -> [FAIL] Bastion public IP allocation is $($bastionPip.PublicIpAllocationMethod) (Expected Static)" -ForegroundColor Red
            $script:failCount++
        }

        Test-CanonicalTagSet -ResourceLabel "Bastion public IP" -Tags $bastionPip.Tag -ExpectedEnvironment 'Platform'
    } else {
        Write-Host "  -> [FAIL] Bastion public IP 'platform-skycraft-swc-bas-pip' NOT found" -ForegroundColor Red
        $script:failCount++
    }
} else {
    Write-Host "[INFO] Bastion not found (Optional — parDeployBastion defaults to false)." -ForegroundColor Yellow
}

Write-Host "`n=== Validation Summary ===" -ForegroundColor Cyan
Write-Host "Lab 2.2 validation complete. Failures: $($script:failCount)" -ForegroundColor $(if ($script:failCount -eq 0) { 'Green' } else { 'Red' })
exit $script:failCount
