<#
.SYNOPSIS
    Validates configuration of Lab 3.1 Infrastructure resources.

.DESCRIPTION
    Checks presence and configuration of:
    - Resource Groups (Platform, Dev, Prod)
    - Virtual Networks and Subnets, including AppServiceSubnet and its delegation to
      Microsoft.Web/serverFarms (found by service, so a Portal-named delegation passes)
    - Network Security Groups (Auth, World) and Rules
    - Load Balancers and Public IPs

.PARAMETER Environment
    Target environment (dev, prod). Default: 'dev'

.EXAMPLE
    .\Test-Lab.ps1 -Environment dev

.NOTES
    Project: SkyCraft
    Lab: 3.1 - Infrastructure as Code
    Author: Marcin Biszczanik
    Date: 2026-01-11
#>

#Requires -Version 7.0
#Requires -Modules Az.Accounts, Az.Resources, Az.Network

[CmdletBinding()]
param(
    [ValidateSet('dev', 'prod')]
    [string]$Environment = 'dev'
)

$ErrorActionPreference = 'Stop'
# Exit-Lab ends the script with exit code 0 or 1 and leaves an interactive session open (#257).
Import-Module (Join-Path $PSScriptRoot '../../../tools/LabCommon.psm1') -Force -Verbose:$false
$failCount = 0

Write-Host "=== Lab 3.1 Validation Script ($Environment) ===" -ForegroundColor Cyan

$locationShortCode = 'swc'
$project           = 'skycraft'

$rgName   = "$Environment-$project-$locationShortCode-rg"
$vnetName = "$Environment-$project-$locationShortCode-vnet"
$lbName   = "$Environment-$project-$locationShortCode-lb"
$pipName  = "$Environment-$project-$locationShortCode-lb-pip"

# 1. Verify Resource Group
try {
    $rg = Get-AzResourceGroup -Name $rgName -ErrorAction Stop
    Write-Host "[OK] Resource Group '$($rg.ResourceGroupName)' found." -ForegroundColor Green
}
catch {
    Write-Host "[FAIL] Resource Group '$rgName' NOT found." -ForegroundColor Red
    $failCount++
    # Cannot proceed with VNet/NSG/LB checks if the RG is missing
    Write-Host "`nValidation Complete. Failures: $failCount" -ForegroundColor Red
    Exit-Lab -FailureCount $failCount
}

# 2. Verify VNet
try {
    $vnet = Get-AzVirtualNetwork -Name $vnetName -ResourceGroupName $rgName -ErrorAction Stop
    Write-Host "[OK] VNet '$vnetName' found." -ForegroundColor Green

    $expectedSubnets = @('AuthSubnet', 'WorldSubnet', 'DatabaseSubnet')
    foreach ($sub in $expectedSubnets) {
        if ($vnet.Subnets.Name -contains $sub) {
            Write-Host "  - [OK] Subnet '$sub' found." -ForegroundColor Green
        }
        else {
            Write-Host "  - [FAIL] Subnet '$sub' MISSING." -ForegroundColor Red
            $failCount++
        }
    }

    # Lab 3.4's VNet integration needs the delegation. Matched by service: the Portal names the
    # delegation itself, Bicep after its service.
    $appSubnetName  = 'AppServiceSubnet'
    $appServiceName = 'Microsoft.Web/serverFarms'
    $appSubnet = $vnet.Subnets | Where-Object Name -eq $appSubnetName | Select-Object -First 1
    if (-not $appSubnet) {
        Write-Host "  - [FAIL] Subnet '$appSubnetName' MISSING." -ForegroundColor Red
        $failCount++
    }
    elseif (@($appSubnet.Delegations.ServiceName) -contains $appServiceName) {
        Write-Host "  - [OK] Subnet '$appSubnetName' found, delegated to $appServiceName." -ForegroundColor Green
    }
    else {
        $actual = @($appSubnet.Delegations.ServiceName | Where-Object { $_ })
        $shown  = if ($actual.Count) { $actual -join ', ' } else { 'none' }
        Write-Host "  - [FAIL] Subnet '$appSubnetName' is not delegated to $appServiceName (delegations: $shown)." -ForegroundColor Red
        $failCount++
    }
}
catch {
    Write-Host "[FAIL] VNet '$vnetName' NOT found." -ForegroundColor Red
    $failCount++
}

# 3. Verify NSGs
$expectedNsgs = @('auth-nsg', 'world-nsg')
foreach ($nsgName in $expectedNsgs) {
    try {
        $nsg = Get-AzNetworkSecurityGroup -Name $nsgName -ResourceGroupName $rgName -ErrorAction Stop
        Write-Host "[OK] NSG '$nsgName' found." -ForegroundColor Green

        if ($nsg.SecurityRules.Count -gt 0) {
            Write-Host "  - [OK] Rules present ($($nsg.SecurityRules.Count))." -ForegroundColor Green
        }
        else {
            Write-Host "  - [WARN] No security rules defined." -ForegroundColor Yellow
        }
    }
    catch {
        Write-Host "[FAIL] NSG '$nsgName' NOT found." -ForegroundColor Red
        $failCount++
    }
}

# 4. Verify Load Balancer
try {
    $lb = Get-AzLoadBalancer -Name $lbName -ResourceGroupName $rgName -ErrorAction Stop
    Write-Host "[OK] Load Balancer '$lbName' found." -ForegroundColor Green

    if ($lb.FrontendIpConfigurations.Count -gt 0) {
        Write-Host "  - [OK] Frontend IP Configured." -ForegroundColor Green
    }
    else {
        Write-Host "  - [FAIL] No Frontend IP Config." -ForegroundColor Red
        $failCount++
    }
}
catch {
    Write-Host "[FAIL] Load Balancer '$lbName' NOT found." -ForegroundColor Red
    $failCount++
}

# 5. Verify Public IP
try {
    $pip = Get-AzPublicIpAddress -Name $pipName -ResourceGroupName $rgName -ErrorAction Stop
    Write-Host "[OK] Public IP '$pipName' found." -ForegroundColor Green

    if ($pip.IpAddress) {
        Write-Host "  - [OK] IP Address: $($pip.IpAddress)" -ForegroundColor Green
    }
}
catch {
    Write-Host "[FAIL] Public IP '$pipName' NOT found." -ForegroundColor Red
    $failCount++
}

Write-Host "`nValidation Complete. Failures: $failCount" -ForegroundColor $(if ($failCount -eq 0) { 'Cyan' } else { 'Red' })
Exit-Lab -FailureCount $failCount
