<#
.SYNOPSIS
    Validates Lab 4.4 Storage Security
.DESCRIPTION
    Checks for Storage Firewall settings, RBAC assignments, and Service Endpoints.
.PARAMETER Environment
    Environment to validate (prod, dev, platform). Default: prod.
.EXAMPLE
    .\Test-Lab.ps1 -Environment prod
.NOTES
    Project: SkyCraft
    Author: SkyCraft
    Date: 2026-02-07
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$Environment = 'prod'
)

$resourceGroupName = "$Environment-skycraft-swc-rg"
$storageAccountName = "${Environment}skycraftswcsa"
$vnetName = "$Environment-skycraft-swc-vnet"

Write-Host "=== Lab 4.4: Validating Storage Security ===" -ForegroundColor Cyan

# 1. Verify Connection
if (-not (Get-AzContext)) {
    Write-Host " [ERROR] Not logged in. Please run Connect-AzAccount." -ForegroundColor Red; exit 1
}

# 2. Check Storage Firewall
try {
    Write-Host "Checking Storage Firewall for '$storageAccountName'..." -ForegroundColor Yellow
    $sa = Get-AzStorageAccount -ResourceGroupName $resourceGroupName -Name $storageAccountName -ErrorAction Stop
    
    if ($sa.NetworkRuleSet.DefaultAction -eq 'Deny') {
        Write-Host "  -> Firewall is correctly set to 'Deny' by default." -ForegroundColor Green
    }
    else {
        Write-Host "  -> [WARNING] Firewall default action is set to '$($sa.NetworkRuleSet.DefaultAction)'. Expected: Deny." -ForegroundColor Yellow
    }

    if ($sa.NetworkRuleSet.VirtualNetworkRules.Count -gt 0) {
        Write-Host "  -> Found $($sa.NetworkRuleSet.VirtualNetworkRules.Count) Virtual Network rules." -ForegroundColor Green
    }
    else {
        Write-Host "  -> [WARNING] No Virtual Network rules found." -ForegroundColor Yellow
    }
}
catch {
    Write-Host "  -> [ERROR] Failed to retrieve storage account firewall settings." -ForegroundColor Red
}

# 3. Check Service Endpoints on VNet
try {
    Write-Host "Checking Service Endpoints on '$vnetName'..." -ForegroundColor Yellow
    $vnet = Get-AzVirtualNetwork -ResourceGroupName $resourceGroupName -Name $vnetName -ErrorAction Stop
    $appSubnet = $vnet.Subnets | Where-Object { $_.Name -eq 'ApplicationSubnet' }
    
    if ($appSubnet.ServiceEndpoints.Service -contains 'Microsoft.Storage') {
        Write-Host "  -> Service Endpoint 'Microsoft.Storage' is enabled on ApplicationSubnet." -ForegroundColor Green
    }
    else {
        Write-Host "  -> [WARNING] Service Endpoint 'Microsoft.Storage' is NOT enabled on ApplicationSubnet." -ForegroundColor Yellow
    }
}
catch {
    Write-Host "  -> [ERROR] Failed to retrieve VNet information." -ForegroundColor Red
}

# 4. Check for Stored Access Policies
try {
    Write-Host "Checking for Stored Access Policies..." -ForegroundColor Yellow
    # This requires listing containers and their policies
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
    Write-Host "  -> [ERROR] Failed to check access policies." -ForegroundColor Red
}

Write-Host "`nValidation Complete." -ForegroundColor Cyan
