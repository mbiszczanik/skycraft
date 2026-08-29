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

.NOTES
    Project: SkyCraft
    Lab: 3.2 - Virtual Machines
    Author: Marcin Biszczanik
    Date: 2026-01-11
#>

#Requires -Version 7.0
#Requires -Modules Az.Accounts, Az.Compute, Az.Network

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

# Verify Azure context
$context = Get-AzContext
if (-not $context) {
    Write-Error "Not logged into Azure. Run Connect-AzAccount first."
    $Host.SetShouldExit(1)
    exit 1
}

# ============================================================================
# VM Tests
# ============================================================================
Write-Host "[VMs]" -ForegroundColor Yellow

# Test Auth VM exists and running
# Note: Get-AzVM -Name -Status returns an instance view whose power state lives in
# .Statuses (Code 'PowerState/running' -> DisplayStatus 'VM running'); there is no
# direct .PowerState property on this object.
Write-Host "  Testing: Auth VM exists and running..." -NoNewline
$authIv = Get-AzVM -ResourceGroupName $rgName -Name "$namePrefix-auth-vm" -Status -ErrorAction SilentlyContinue
$authState = ($authIv.Statuses | Where-Object { $_.Code -like 'PowerState/*' }).DisplayStatus
if ($authState -eq 'VM running') {
    Write-Host " PASS" -ForegroundColor Green
    $passCount++
} else {
    Write-Host " FAIL (State: $authState)" -ForegroundColor Red
    $failCount++
}

# Test World VM exists and running
Write-Host "  Testing: World VM exists and running..." -NoNewline
$worldIv = Get-AzVM -ResourceGroupName $rgName -Name "$namePrefix-world-vm" -Status -ErrorAction SilentlyContinue
$worldState = ($worldIv.Statuses | Where-Object { $_.Code -like 'PowerState/*' }).DisplayStatus
if ($worldState -eq 'VM running') {
    Write-Host " PASS" -ForegroundColor Green
    $passCount++
} else {
    Write-Host " FAIL (State: $worldState)" -ForegroundColor Red
    $failCount++
}

# Test Auth VM in Zone 1
Write-Host "  Testing: Auth VM in Zone 1..." -NoNewline
$authZone = (Get-AzVM -ResourceGroupName $rgName -Name "$namePrefix-auth-vm" -ErrorAction SilentlyContinue).Zones[0]
if ($authZone -eq '1') {
    Write-Host " PASS" -ForegroundColor Green
    $passCount++
} else {
    Write-Host " FAIL (Zone: $authZone)" -ForegroundColor Red
    $failCount++
}

# Test World VM in Zone 2
Write-Host "  Testing: World VM in Zone 2..." -NoNewline
$worldZone = (Get-AzVM -ResourceGroupName $rgName -Name "$namePrefix-world-vm" -ErrorAction SilentlyContinue).Zones[0]
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
$authSubnet = (Get-AzNetworkInterface -ResourceGroupName $rgName -Name "$namePrefix-auth-nic" -ErrorAction SilentlyContinue).IpConfigurations[0].Subnet.Id
if ($authSubnet -like "*AuthSubnet*") {
    Write-Host " PASS" -ForegroundColor Green
    $passCount++
} else {
    Write-Host " FAIL" -ForegroundColor Red
    $failCount++
}

# Test World NIC in WorldSubnet
Write-Host "  Testing: World NIC in WorldSubnet..." -NoNewline
$worldSubnet = (Get-AzNetworkInterface -ResourceGroupName $rgName -Name "$namePrefix-world-nic" -ErrorAction SilentlyContinue).IpConfigurations[0].Subnet.Id
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
$disk = Get-AzDisk -ResourceGroupName $rgName -DiskName "$namePrefix-world-datadisk" -ErrorAction SilentlyContinue
if ($disk -and $disk.Name -eq "$namePrefix-world-datadisk") {
    Write-Host " PASS" -ForegroundColor Green
    $passCount++
} else {
    Write-Host " FAIL" -ForegroundColor Red
    $failCount++
}

# Test Data disk attached to World VM
Write-Host "  Testing: Data disk attached to World VM..." -NoNewline
$attachedDisks = (Get-AzVM -ResourceGroupName $rgName -Name "$namePrefix-world-vm" -ErrorAction SilentlyContinue).StorageProfile.DataDisks.ManagedDisk.Id
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

$lb = Get-AzLoadBalancer -ResourceGroupName $rgName -Name "$namePrefix-lb" -ErrorAction SilentlyContinue

# Test Auth NIC in LB backend pool
Write-Host "  Testing: Auth NIC in LB backend pool..." -NoNewline
$authBePool = ($lb.BackendAddressPools | Where-Object { $_.Name -eq "$namePrefix-lb-be-auth" }).BackendIpConfigurations[0].Id
if ($authBePool -like "*auth-nic*") {
    Write-Host " PASS" -ForegroundColor Green
    $passCount++
} else {
    Write-Host " FAIL" -ForegroundColor Red
    $failCount++
}

# Test World NIC in LB backend pool
Write-Host "  Testing: World NIC in LB backend pool..." -NoNewline
$worldBePool = ($lb.BackendAddressPools | Where-Object { $_.Name -eq "$namePrefix-lb-be-world" }).BackendIpConfigurations[0].Id
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

$Host.SetShouldExit($failCount)
exit $failCount
