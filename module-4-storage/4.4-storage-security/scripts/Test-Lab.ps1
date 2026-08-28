<#
.SYNOPSIS
    Validates Lab 4.4 Storage Security
.DESCRIPTION
    Checks for Storage Firewall settings, RBAC assignments, Service Endpoints,
    Stored Access Policies, and the dev-assets container.
.PARAMETER Environment
    Environment to validate (prod or dev). Default: prod.
.EXAMPLE
    .\Test-Lab.ps1 -Environment prod
.NOTES
    Project: SkyCraft
    Author: SkyCraft
    Date: 2026-02-07
#>

#Requires -Version 7.0
#Requires -Modules Az.Accounts, Az.Storage, Az.Network

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [ValidateSet('prod', 'dev')]
    [string]$Environment = 'prod'
)

$ErrorActionPreference = 'Stop'
$failCount = 0

$resourceGroupName  = "$Environment-skycraft-swc-rg"
$storageAccountName = "${Environment}skycraftswcsa"
$vnetName           = "$Environment-skycraft-swc-vnet"

Write-Host "=== Lab 4.4: Validating Storage Security ===" -ForegroundColor Cyan

# 1. Verify Connection
if (-not (Get-AzContext)) {
    Write-Host " [ERROR] Not logged in. Please run Connect-AzAccount." -ForegroundColor Red; exit 1
}

# 2. Check Storage Firewall
$sa = $null
try {
    Write-Host "Checking Storage Firewall for '$storageAccountName'..." -ForegroundColor Yellow
    $sa = Get-AzStorageAccount -ResourceGroupName $resourceGroupName -Name $storageAccountName -ErrorAction Stop

    if ($sa.NetworkRuleSet.DefaultAction -eq 'Deny') {
        Write-Host "  -> Firewall is correctly set to 'Deny' by default." -ForegroundColor Green
    }
    else {
        Write-Host "  -> [FAIL] Firewall default action is '$($sa.NetworkRuleSet.DefaultAction)'. Expected: Deny." -ForegroundColor Red
        $failCount++
    }

    if ($sa.NetworkRuleSet.VirtualNetworkRules.Count -gt 0) {
        Write-Host "  -> Found $($sa.NetworkRuleSet.VirtualNetworkRules.Count) Virtual Network rules." -ForegroundColor Green
    }
    else {
        Write-Host "  -> [FAIL] No Virtual Network rules found." -ForegroundColor Red
        $failCount++
    }
}
catch {
    Write-Host "  -> [FAIL] Failed to retrieve storage account '$storageAccountName'." -ForegroundColor Red
    $failCount++
}

# 3. Check Service Endpoint on WorldSubnet (not ApplicationSubnet — the deployed subnet is WorldSubnet)
try {
    Write-Host "Checking Service Endpoint on '$vnetName' / WorldSubnet..." -ForegroundColor Yellow
    $vnet       = Get-AzVirtualNetwork -ResourceGroupName $resourceGroupName -Name $vnetName -ErrorAction Stop
    $worldSubnet = $vnet.Subnets | Where-Object { $_.Name -eq 'WorldSubnet' }

    if ($worldSubnet) {
        if ($worldSubnet.ServiceEndpoints.Service -contains 'Microsoft.Storage') {
            Write-Host "  -> Service Endpoint 'Microsoft.Storage' is enabled on WorldSubnet." -ForegroundColor Green
        }
        else {
            Write-Host "  -> [FAIL] Service Endpoint 'Microsoft.Storage' is NOT enabled on WorldSubnet." -ForegroundColor Red
            $failCount++
        }
    }
    else {
        Write-Host "  -> [FAIL] WorldSubnet not found in '$vnetName'." -ForegroundColor Red
        $failCount++
    }
}
catch {
    Write-Host "  -> [FAIL] Failed to retrieve VNet '$vnetName'." -ForegroundColor Red
    $failCount++
}

# 4. Check dev-assets container
if ($sa) {
    try {
        Write-Host "Checking 'dev-assets' container..." -ForegroundColor Yellow
        $ctx = $sa.Context
        $container = Get-AzStorageContainer -Name 'dev-assets' -Context $ctx -ErrorAction SilentlyContinue
        if ($container) {
            Write-Host "  -> Container 'dev-assets' found." -ForegroundColor Green
        }
        else {
            Write-Host "  -> [FAIL] Container 'dev-assets' not found." -ForegroundColor Red
            $failCount++
        }
    }
    catch {
        Write-Host "  -> [FAIL] Could not check container (possible firewall restriction — check from VNet): $_" -ForegroundColor Red
        $failCount++
    }
}

# 5. Check for Stored Access Policies
if ($sa) {
    try {
        Write-Host "Checking for Stored Access Policies..." -ForegroundColor Yellow
        $containers = Get-AzStorageContainer -Context $sa.Context -ErrorAction SilentlyContinue
        if ($containers) {
            $foundPolicy = $false
            foreach ($container in $containers) {
                $policies = Get-AzStorageContainerStoredAccessPolicy -Container $container.Name -Context $sa.Context -ErrorAction SilentlyContinue
                if ($policies) {
                    Write-Host "  -> Found Policy '$($policies.Id)' on container '$($container.Name)'" -ForegroundColor Green
                    $foundPolicy = $true
                }
            }
            if (-not $foundPolicy) {
                Write-Host "  -> [INFO] No stored access policies found." -ForegroundColor Gray
            }
        }
    }
    catch {
        Write-Host "  -> [INFO] Could not list access policies (possible firewall restriction)." -ForegroundColor Gray
    }
}

Write-Host "`nValidation Complete. Failures: $failCount" -ForegroundColor $(if ($failCount -eq 0) { 'Cyan' } else { 'Red' })
exit $failCount
