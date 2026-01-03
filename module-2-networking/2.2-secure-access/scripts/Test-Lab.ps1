<#
.SYNOPSIS
    Validates the configuration of Lab 2.2 security resources.

.DESCRIPTION
    This script runs a comprehensive validation suite against the deployed resources to ensure 
    they meet the Lab 2.2 requirements.

    It validates:
    - Application Security Groups (ASGs): Checks existence of all 3 required ASGs.
    - Network Security Groups (NSGs): Checks existence of production and platform NSGs.
    - Security Rules: Verifies exact configuration (Port, Priority, Access) of:
        - AllowAuthServer
        - AllowWorldServer
        - AllowAppToDB
    - Subnet Associations: Ensures subnets are correctly associated with the NSG.
    - Azure Bastion: Checks for existence (Optional).

.EXAMPLE
    .\Test-Lab.ps1
    Runs all validation checks and outputs Pass/Fail status for each component.

.NOTES
    Project: SkyCraft
    Lab: 2.2 - Secure Access
    Author: Ops Team
    Date: 2026-01-03
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
$platRg = "platform-skycraft-swc-rg"
$prodVnetName = "prod-skycraft-swc-vnet"

# 1. Validate Application Security Groups (ASGs)
Write-Host "`n=== 1. Validating Application Security Groups ===" -ForegroundColor Cyan
$expectedAsgs = @(
    "prod-skycraft-swc-asg-auth",
    "prod-skycraft-swc-asg-world",
    "prod-skycraft-swc-asg-db"
)

foreach ($asgName in $expectedAsgs) {
    $asg = Get-AzApplicationSecurityGroup -ResourceGroupName $prodRg -Name $asgName -ErrorAction SilentlyContinue
    if ($asg) {
        Write-Host "[OK] ASG found: $asgName" -ForegroundColor Green
    }
    else {
        Write-Host "[FAIL] ASG missing: $asgName" -ForegroundColor Red
    }
}

# 2. Validate Network Security Groups (NSGs)
Write-Host "`n=== 2. Validating Network Security Groups ===" -ForegroundColor Cyan
$nsgs = @(
    @{ Name = "prod-skycraft-swc-nsg"; RG = $prodRg },
    @{ Name = "platform-skycraft-swc-nsg"; RG = $platRg }
)

foreach ($nsgInfo in $nsgs) {
    $nsg = Get-AzNetworkSecurityGroup -ResourceGroupName $nsgInfo.RG -Name $nsgInfo.Name -ErrorAction SilentlyContinue
    if ($nsg) {
        Write-Host "[OK] NSG found: $($nsgInfo.Name) in $($nsgInfo.RG)" -ForegroundColor Green
    }
    else {
        Write-Host "[FAIL] NSG missing: $($nsgInfo.Name) in $($nsgInfo.RG)" -ForegroundColor Red
    }
}

# 3. Validate NSG Rules (Prod NSG)
Write-Host "`n=== 3. Validating NSG Rules (prod-skycraft-swc-nsg) ===" -ForegroundColor Cyan
$prodNsg = Get-AzNetworkSecurityGroup -ResourceGroupName $prodRg -Name "prod-skycraft-swc-nsg" -ErrorAction SilentlyContinue

if ($prodNsg) {
    # Rule: AllowAuthServer
    $authRule = $prodNsg.SecurityRules | Where-Object { $_.Name -eq "AllowAuthServer" }
    if ($authRule) {
        if ($authRule.DestinationPortRange -eq "3724" -and $authRule.Access -eq "Allow" -and $authRule.Priority -eq 1000) {
            Write-Host "[OK] Rule 'AllowAuthServer' (Port 3724, Priority 1000) verified." -ForegroundColor Green
        }
        else {
            Write-Host "[FAIL] Rule 'AllowAuthServer' found but settings differ: Port=$($authRule.DestinationPortRange), Priority=$($authRule.Priority), Access=$($authRule.Access)" -ForegroundColor Red
        }
    }
    else {
        Write-Host "[FAIL] Rule 'AllowAuthServer' not found." -ForegroundColor Red
    }

    # Rule: AllowWorldServer
    $worldRule = $prodNsg.SecurityRules | Where-Object { $_.Name -eq "AllowWorldServer" }
    if ($worldRule) {
        if ($worldRule.DestinationPortRange -eq "8085" -and $worldRule.Access -eq "Allow" -and $worldRule.Priority -eq 1100) {
            Write-Host "[OK] Rule 'AllowWorldServer' (Port 8085, Priority 1100) verified." -ForegroundColor Green
        }
        else {
            Write-Host "[FAIL] Rule 'AllowWorldServer' found but settings differ: Port=$($worldRule.DestinationPortRange), Priority=$($worldRule.Priority), Access=$($worldRule.Access)" -ForegroundColor Red
        }
    }
    else {
        Write-Host "[FAIL] Rule 'AllowWorldServer' not found." -ForegroundColor Red
    }

    # Rule: AllowAppToDB
    $dbRule = $prodNsg.SecurityRules | Where-Object { $_.Name -eq "AllowAppToDB" }
    if ($dbRule) {
        if ($dbRule.DestinationPortRange -eq "3306" -and $dbRule.Access -eq "Allow" -and $dbRule.Priority -eq 2000) {
            Write-Host "[OK] Rule 'AllowAppToDB' (Port 3306, Priority 2000) verified." -ForegroundColor Green
            # Check if source is ASG
            if ($dbRule.SourceApplicationSecurityGroups) {
                Write-Host "  - Source ASGs correctly configured." -ForegroundColor Gray
            }
            else {
                Write-Host "  - [WARNING] Rule 'AllowAppToDB' should ideally use ASGs as source." -ForegroundColor Yellow
            }
        }
        else {
            Write-Host "[FAIL] Rule 'AllowAppToDB' found but settings differ: Port=$($dbRule.DestinationPortRange), Priority=$($dbRule.Priority), Access=$($dbRule.Access)" -ForegroundColor Red
        }
    }
    else {
        Write-Host "[FAIL] Rule 'AllowAppToDB' not found." -ForegroundColor Red
    }
}

# 4. Validate Subnet-NSG Associations
Write-Host "`n=== 4. Validating Subnet Associations ===" -ForegroundColor Cyan
$vnet = Get-AzVirtualNetwork -Name $prodVnetName -ResourceGroupName $prodRg -ErrorAction SilentlyContinue
if ($vnet) {
    $subnetsToCheck = @("AuthSubnet", "WorldSubnet", "DatabaseSubnet")
    foreach ($snName in $subnetsToCheck) {
        $sn = $vnet.Subnets | Where-Object { $_.Name -eq $snName }
        if ($sn) {
            if ($sn.NetworkSecurityGroup -and $sn.NetworkSecurityGroup.Id -like "*prod-skycraft-swc-nsg") {
                Write-Host "[OK] Subnet $snName is associated with prod-skycraft-swc-nsg." -ForegroundColor Green
            }
            else {
                Write-Host "[FAIL] Subnet $snName is NOT associated with prod-skycraft-swc-nsg." -ForegroundColor Red
            }
        }
        else {
            Write-Host "[FAIL] Subnet $snName not found." -ForegroundColor Red
        }
    }
}

# 5. Validate Azure Bastion (Optional)
Write-Host "`n=== 5. Validating Azure Bastion (Optional) ===" -ForegroundColor Cyan
$bastion = Get-AzBastion -ResourceGroupName $platRg -Name "platform-skycraft-swc-bas" -ErrorAction SilentlyContinue
if ($bastion) {
    Write-Host "[OK] Bastion 'platform-skycraft-swc-bas' found." -ForegroundColor Green
}
else {
    Write-Host "[INFO] Bastion not found. (Task 6 was optional)" -ForegroundColor Yellow
}

Write-Host "`n=== Validation Summary ===" -ForegroundColor Cyan
Write-Host "Lab 2.2 validation complete" -ForegroundColor Green
