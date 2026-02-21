<#
.SYNOPSIS
    Validates Lab 4.4 Storage Security
.DESCRIPTION
    Checks for Storage Firewall settings, Service Endpoints, dev-assets container,
    Stored Access Policies, and RBAC assignments.
.PARAMETER Environment
    Environment to validate (prod, dev, platform). Default: prod.
.EXAMPLE
    .\Test-Lab.ps1 -Environment prod
.NOTES
    Project: SkyCraft
    Author: SkyCraft
    Date: 2026-02-21
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
        Write-Host "  -> [WARNING] Firewall default action is '$($sa.NetworkRuleSet.DefaultAction)'. Expected: Deny." -ForegroundColor Yellow
    }

    if ($sa.NetworkRuleSet.VirtualNetworkRules.Count -gt 0) {
        Write-Host "  -> Found $($sa.NetworkRuleSet.VirtualNetworkRules.Count) Virtual Network rule(s)." -ForegroundColor Green
    }
    else {
        Write-Host "  -> [WARNING] No Virtual Network rules found." -ForegroundColor Yellow
    }

    if ($sa.NetworkRuleSet.IpRules.Count -gt 0) {
        Write-Host "  -> Found $($sa.NetworkRuleSet.IpRules.Count) IP rule(s)." -ForegroundColor Green
    }
    else {
        Write-Host "  -> [INFO] No IP rules configured." -ForegroundColor Gray
    }
}
catch {
    Write-Host "  -> [ERROR] Failed to retrieve storage account firewall settings." -ForegroundColor Red
    return
}

# 3. Check Service Endpoints on VNet
try {
    Write-Host "Checking Service Endpoints on '$vnetName/WorldSubnet'..." -ForegroundColor Yellow
    $vnet = Get-AzVirtualNetwork -ResourceGroupName $resourceGroupName -Name $vnetName -ErrorAction Stop
    $worldSubnet = $vnet.Subnets | Where-Object { $_.Name -eq 'WorldSubnet' }

    if ($worldSubnet.ServiceEndpoints.Service -contains 'Microsoft.Storage') {
        Write-Host "  -> Service Endpoint 'Microsoft.Storage' is enabled on WorldSubnet." -ForegroundColor Green
    }
    else {
        Write-Host "  -> [WARNING] Service Endpoint 'Microsoft.Storage' is NOT enabled on WorldSubnet." -ForegroundColor Yellow
    }
}
catch {
    Write-Host "  -> [ERROR] Failed to retrieve VNet information." -ForegroundColor Red
}

# 4. Check dev-assets container
try {
    Write-Host "Checking for 'dev-assets' container..." -ForegroundColor Yellow
    $container = Get-AzStorageContainer -Name 'dev-assets' -Context $sa.Context -ErrorAction SilentlyContinue
    if ($container) {
        Write-Host "  -> Container 'dev-assets' exists (Access: $($container.PublicAccess))." -ForegroundColor Green
    }
    else {
        Write-Host "  -> [MISSING] Container 'dev-assets' not found." -ForegroundColor Red
    }
}
catch {
    Write-Host "  -> [ERROR] Could not check containers (firewall may be blocking)." -ForegroundColor Red
}

# 5. Check for Stored Access Policies
try {
    Write-Host "Checking for Stored Access Policies on 'dev-assets'..." -ForegroundColor Yellow
    $policies = Get-AzStorageContainerStoredAccessPolicy -Container 'dev-assets' -Context $sa.Context -ErrorAction SilentlyContinue
    if ($policies) {
        foreach ($policy in $policies) {
            Write-Host "  -> Found Policy '$($policy.Policy)' (Permissions: $($policy.Permission))" -ForegroundColor Green
        }
    }
    else {
        Write-Host "  -> [INFO] No stored access policies found (expected after revocation test)." -ForegroundColor Gray
    }
}
catch {
    Write-Host "  -> [INFO] Could not check policies (firewall may be blocking or container absent)." -ForegroundColor Gray
}

# 6. Check RBAC Assignment
try {
    Write-Host "Checking RBAC 'Storage Blob Data Contributor' assignments..." -ForegroundColor Yellow
    $storageId = $sa.Id
    $assignments = Get-AzRoleAssignment -Scope $storageId |
    Where-Object RoleDefinitionName -eq 'Storage Blob Data Contributor'

    if ($assignments) {
        foreach ($assignment in $assignments) {
            Write-Host "  -> Assigned to: $($assignment.DisplayName) ($($assignment.SignInName))" -ForegroundColor Green
        }
    }
    else {
        Write-Host "  -> [WARNING] No 'Storage Blob Data Contributor' assignments found." -ForegroundColor Yellow
    }
}
catch {
    Write-Host "  -> [ERROR] Failed to check RBAC assignments." -ForegroundColor Red
}

Write-Host "`nValidation Complete." -ForegroundColor Cyan
