<#
.SYNOPSIS
    Tests Lab 3.2 Virtual Machines deployment.

.DESCRIPTION
    Validates that all Lab 3.2 resources are deployed correctly:
    - VMs exist and are running
    - NICs are configured with correct subnets
    - Data disk is attached to Worldserver
    - Load balancer backend pools contain VMs

.PARAMETER Environment
    Target environment (dev or prod). Default: dev

.EXAMPLE
    .\Test-Lab.ps1 -Environment dev
#>

[CmdletBinding()]
param(
    [Parameter()]
    [ValidateSet('dev', 'prod')]
    [string]$Environment = 'dev'
)

$ErrorActionPreference = 'Stop'

# Configuration
$rgName = "$Environment-skycraft-swc-rg"
$namePrefix = "$Environment-skycraft-swc"
$passCount = 0
$failCount = 0

Write-Host ""
Write-Host "========================================"  -ForegroundColor Cyan
Write-Host "  Lab 3.2 - Deployment Validation"  -ForegroundColor Cyan
Write-Host "========================================"  -ForegroundColor Cyan
Write-Host ""

# Check Azure CLI login
$account = az account show 2>$null | ConvertFrom-Json
if (-not $account) {
    Write-Error "Not logged into Azure CLI. Run 'az login' first."
    exit 1
}

# ============================================================================
# VM Tests
# ============================================================================
Write-Host "[VMs]" -ForegroundColor Yellow

# Test Auth VM exists and running
Write-Host "  Testing: Auth VM exists and running..." -NoNewline
$authVmState = az vm get-instance-view --name "$namePrefix-auth-vm" --resource-group $rgName --query "instanceView.statuses[1].displayStatus" -o tsv 2>$null
if ($authVmState -eq 'VM running') {
    Write-Host " PASS" -ForegroundColor Green
    $passCount++
} else {
    Write-Host " FAIL (State: $authVmState)" -ForegroundColor Red
    $failCount++
}

# Test World VM exists and running
Write-Host "  Testing: World VM exists and running..." -NoNewline
$worldVmState = az vm get-instance-view --name "$namePrefix-world-vm" --resource-group $rgName --query "instanceView.statuses[1].displayStatus" -o tsv 2>$null
if ($worldVmState -eq 'VM running') {
    Write-Host " PASS" -ForegroundColor Green
    $passCount++
} else {
    Write-Host " FAIL (State: $worldVmState)" -ForegroundColor Red
    $failCount++
}

# Test Auth VM in Zone 1
Write-Host "  Testing: Auth VM in Zone 1..." -NoNewline
$authZone = az vm show --name "$namePrefix-auth-vm" --resource-group $rgName --query "zones[0]" -o tsv 2>$null
if ($authZone -eq '1') {
    Write-Host " PASS" -ForegroundColor Green
    $passCount++
} else {
    Write-Host " FAIL (Zone: $authZone)" -ForegroundColor Red
    $failCount++
}

# Test World VM in Zone 2
Write-Host "  Testing: World VM in Zone 2..." -NoNewline
$worldZone = az vm show --name "$namePrefix-world-vm" --resource-group $rgName --query "zones[0]" -o tsv 2>$null
if ($worldZone -eq '2') {
    Write-Host " PASS" -ForegroundColor Green
    $passCount++
} else {
    Write-Host " FAIL (Zone: $worldZone)" -ForegroundColor Red
    $failCount++
}

# ============================================================================
# NIC Tests
# ============================================================================
Write-Host ""
Write-Host "[NICs]" -ForegroundColor Yellow

# Test Auth NIC in AuthSubnet
Write-Host "  Testing: Auth NIC in AuthSubnet..." -NoNewline
$authSubnet = az network nic show --name "$namePrefix-auth-nic" --resource-group $rgName --query "ipConfigurations[0].subnet.id" -o tsv 2>$null
if ($authSubnet -like "*AuthSubnet*") {
    Write-Host " PASS" -ForegroundColor Green
    $passCount++
} else {
    Write-Host " FAIL" -ForegroundColor Red
    $failCount++
}

# Test World NIC in WorldSubnet
Write-Host "  Testing: World NIC in WorldSubnet..." -NoNewline
$worldSubnet = az network nic show --name "$namePrefix-world-nic" --resource-group $rgName --query "ipConfigurations[0].subnet.id" -o tsv 2>$null
if ($worldSubnet -like "*WorldSubnet*") {
    Write-Host " PASS" -ForegroundColor Green
    $passCount++
} else {
    Write-Host " FAIL" -ForegroundColor Red
    $failCount++
}

# ============================================================================
# Data Disk Tests
# ============================================================================
Write-Host ""
Write-Host "[Data Disks]" -ForegroundColor Yellow

# Test World data disk exists
Write-Host "  Testing: World data disk exists..." -NoNewline
$disk = az disk show --name "$namePrefix-world-datadisk" --resource-group $rgName --query "name" -o tsv 2>$null
if ($disk -eq "$namePrefix-world-datadisk") {
    Write-Host " PASS" -ForegroundColor Green
    $passCount++
} else {
    Write-Host " FAIL" -ForegroundColor Red
    $failCount++
}

# Test Data disk attached to World VM
Write-Host "  Testing: Data disk attached to World VM..." -NoNewline
$attachedDisks = az vm show --name "$namePrefix-world-vm" --resource-group $rgName --query "storageProfile.dataDisks[].managedDisk.id" -o tsv 2>$null
if ($attachedDisks -like "*datadisk*") {
    Write-Host " PASS" -ForegroundColor Green
    $passCount++
} else {
    Write-Host " FAIL" -ForegroundColor Red
    $failCount++
}

# ============================================================================
# Load Balancer Tests
# ============================================================================
Write-Host ""
Write-Host "[Load Balancer]" -ForegroundColor Yellow

# Test Auth NIC in LB backend pool
Write-Host "  Testing: Auth NIC in LB backend pool..." -NoNewline
$authBePool = az network lb address-pool show --lb-name "$namePrefix-lb" --name "$namePrefix-lb-be-auth" --resource-group $rgName --query "backendIPConfigurations[0].id" -o tsv 2>$null
if ($authBePool -like "*auth-nic*") {
    Write-Host " PASS" -ForegroundColor Green
    $passCount++
} else {
    Write-Host " FAIL" -ForegroundColor Red
    $failCount++
}

# Test World NIC in LB backend pool
Write-Host "  Testing: World NIC in LB backend pool..." -NoNewline
$worldBePool = az network lb address-pool show --lb-name "$namePrefix-lb" --name "$namePrefix-lb-be-world" --resource-group $rgName --query "backendIPConfigurations[0].id" -o tsv 2>$null
if ($worldBePool -like "*world-nic*") {
    Write-Host " PASS" -ForegroundColor Green
    $passCount++
} else {
    Write-Host " FAIL" -ForegroundColor Red
    $failCount++
}

# ============================================================================
# Summary
# ============================================================================
Write-Host ""
Write-Host "========================================"  -ForegroundColor Cyan
Write-Host "  Test Results Summary"  -ForegroundColor Cyan
Write-Host "========================================"  -ForegroundColor Cyan
Write-Host "  Passed: $passCount" -ForegroundColor Green
if ($failCount -gt 0) {
    Write-Host "  Failed: $failCount" -ForegroundColor Red
} else {
    Write-Host "  Failed: $failCount" -ForegroundColor Gray
}
Write-Host "========================================"  -ForegroundColor Cyan
Write-Host ""

exit $failCount
