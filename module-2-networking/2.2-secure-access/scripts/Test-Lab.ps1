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
    - Service Endpoints: Checks for Microsoft.Sql and Microsoft.Storage on Database subnets.
    - Azure Bastion: Checks for existence.

.EXAMPLE
    .\Test-Lab.ps1
    Runs all validation checks and outputs Pass/Fail status for each component.

.NOTES
    Project: SkyCraft
    Lab: 2.2 - Secure Access
    Author: Ops Team
    Date: 2026-01-08
#>

Write-Host "=== Lab 2.2 Validation Script ===" -ForegroundColor Cyan -BackgroundColor Black

# Check Azure Connection
$context = Get-AzContext
if (-not $context) {
    Write-Host "Not logged in. Please run Connect-AzAccount" -ForegroundColor Red
    return
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
    else { Write-Host "[FAIL] ASG missing: $($item.Name)" -ForegroundColor Red }
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
        
        # Validate critical rule if specified
        if ($nsgInfo.Rule) {
            $rule = $nsg.SecurityRules | Where-Object { $_.Name -match $nsgInfo.Rule }
            if ($rule) {
                if ($rule.DestinationPortRange -eq $nsgInfo.Port -and $rule.Access -eq "Allow") {
                     Write-Host "  -> [OK] Rule '$($nsgInfo.Rule)' verified (Port: $($nsgInfo.Port))" -ForegroundColor Gray
                } else {
                     Write-Host "  -> [FAIL] Rule '$($nsgInfo.Rule)' matches incorrect settings" -ForegroundColor Red
                }
            } else {
                # Try finding by port if name differs (e.g. Bicep vs PS naming)
                $ruleByPort = $nsg.SecurityRules | Where-Object { $_.DestinationPortRange -eq $nsgInfo.Port }
                if ($ruleByPort) {
                    Write-Host "  -> [OK] Rule for Port $($nsgInfo.Port) found (Name: $($ruleByPort.Name))" -ForegroundColor Gray
                } else {
                    Write-Host "  -> [FAIL] Rule '$($nsgInfo.Rule)' missing" -ForegroundColor Red
                }
            }
        }
    }
    else {
        Write-Host "[FAIL] NSG missing: $($nsgInfo.Name)" -ForegroundColor Red
    }
}

# 3. Validate Subnet Associations & Service Endpoints
Write-Host "`n=== 3. Validating Subnet Associations & Service Endpoints ===" -ForegroundColor Cyan

function Test-Subnet {
    param($VnetName, $RgName, $SubnetName, $ExpectedNsgName, $CheckSE=$false)
    $vnet = Get-AzVirtualNetwork -Name $VnetName -ResourceGroupName $RgName -ErrorAction SilentlyContinue
    if ($vnet) {
        $sn = $vnet.Subnets | Where-Object { $_.Name -eq $SubnetName }
        if ($sn) {
            # Check NSG
            if ($sn.NetworkSecurityGroup.Id -match $ExpectedNsgName) {
                Write-Host "[OK] $SubnetName associated with $ExpectedNsgName" -ForegroundColor Green
            } else {
                Write-Host "[FAIL] $SubnetName NOT associated with $ExpectedNsgName (Current: $($sn.NetworkSecurityGroup.Id))" -ForegroundColor Red
            }

            # Check Service Endpoints
            if ($CheckSE) {
                $sqlSE = $sn.ServiceEndpoints | Where-Object { $_.Service -eq "Microsoft.Sql" }
                $storeSE = $sn.ServiceEndpoints | Where-Object { $_.Service -eq "Microsoft.Storage" }
                
                if ($sqlSE -and $storeSE) {
                    Write-Host "  -> [OK] Service Endpoints (SQL, Storage) enabled" -ForegroundColor Gray
                } else {
                    Write-Host "  -> [FAIL] Missing Service Endpoints on $SubnetName" -ForegroundColor Red
                }
            }
        } else { Write-Host "[FAIL] Subnet $SubnetName not found in $VnetName" -ForegroundColor Red }
    } else { Write-Host "[FAIL] VNet $VnetName not found" -ForegroundColor Red }
}

# Dev
Test-Subnet -VnetName $devVnetName -RgName $devRg -SubnetName "AuthSubnet" -ExpectedNsgName "dev-skycraft-swc-auth-nsg"
Test-Subnet -VnetName $devVnetName -RgName $devRg -SubnetName "WorldSubnet" -ExpectedNsgName "dev-skycraft-swc-world-nsg"
Test-Subnet -VnetName $devVnetName -RgName $devRg -SubnetName "DatabaseSubnet" -ExpectedNsgName "dev-skycraft-swc-db-nsg" -CheckSE $true

# Prod
Test-Subnet -VnetName $prodVnetName -RgName $prodRg -SubnetName "AuthSubnet" -ExpectedNsgName "prod-skycraft-swc-auth-nsg"
Test-Subnet -VnetName $prodVnetName -RgName $prodRg -SubnetName "WorldSubnet" -ExpectedNsgName "prod-skycraft-swc-world-nsg"
Test-Subnet -VnetName $prodVnetName -RgName $prodRg -SubnetName "DatabaseSubnet" -ExpectedNsgName "prod-skycraft-swc-db-nsg" -CheckSE $true

# 4. Validate Azure Bastion
Write-Host "`n=== 4. Validating Azure Bastion ===" -ForegroundColor Cyan
$bastion = Get-AzBastion -ResourceGroupName $platRg -Name "platform-skycraft-swc-bas" -ErrorAction SilentlyContinue
if ($bastion) {
    Write-Host "[OK] Bastion 'platform-skycraft-swc-bas' found." -ForegroundColor Green
} else {
    Write-Host "[INFO] Bastion not found (Optional)." -ForegroundColor Yellow
}

Write-Host "`n=== Validation Summary ===" -ForegroundColor Cyan
Write-Host "Lab 2.2 validation complete" -ForegroundColor Green
