<#
.SYNOPSIS
    Validates configuration of Lab 3.1 Infrastructure resources.

.DESCRIPTION
    Checks presence and configuration of:
    - Resource Groups (Platform, Dev, Prod)
    - Virtual Networks and Subnets
    - Network Security Groups (Auth, World) and Rules
    - Load Balancers and Public IPs

.PARAMETER Environment
    Target environment (dev, prod). Default: 'dev'

.EXAMPLE
    .\Test-Lab.ps1 -Environment dev
#>

[CmdletBinding()]
param(
    [ValidateSet('dev', 'prod')]
    [string]$Environment = 'dev'
)

Write-Host "=== Lab 3.1 Validation Script ($Environment) ===" -ForegroundColor Cyan

# Configuration Mappings based on main.bicep
$locationShortCode = 'swc'
$project = 'skycraft'

$rgName = "$Environment-$project-$locationShortCode-rg"
$vnetName = "$Environment-$project-$locationShortCode-vnet"
$lbName = "$Environment-$project-$locationShortCode-lb"
$pipName = "$Environment-$project-$locationShortCode-lb-pip"

# 1. Verify Resource Group
try {
    # Use $rg to suppress output but check existence
    $rg = Get-AzResourceGroup -Name $rgName -ErrorAction Stop
    Write-Host "[OK] Resource Group '$($rg.ResourceGroupName)' found." -ForegroundColor Green
}
catch {
    Write-Host "[FAIL] Resource Group '$rgName' NOT found." -ForegroundColor Red
    return # Cannot proceed if RG is missing
}

# 2. Verify VNet
try {
    $vnet = Get-AzVirtualNetwork -Name $vnetName -ResourceGroupName $rgName -ErrorAction Stop
    Write-Host "[OK] VNet '$vnetName' found." -ForegroundColor Green
    
    # Check Subnets (Dev expects Auth, World, Database)
    $expectedSubnets = @('AuthSubnet', 'WorldSubnet', 'DatabaseSubnet')
    foreach ($sub in $expectedSubnets) {
        if ($vnet.Subnets.Name -contains $sub) {
            Write-Host "  - [OK] Subnet '$sub' found." -ForegroundColor Green
        }
        else {
            Write-Host "  - [FAIL] Subnet '$sub' MISSING." -ForegroundColor Red
        }
    }
}
catch {
    Write-Host "[FAIL] VNet '$vnetName' NOT found." -ForegroundColor Red
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
    }
}
catch {
    Write-Host "[FAIL] Load Balancer '$lbName' NOT found." -ForegroundColor Red
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
}

Write-Host "`nValidation Complete." -ForegroundColor Cyan
