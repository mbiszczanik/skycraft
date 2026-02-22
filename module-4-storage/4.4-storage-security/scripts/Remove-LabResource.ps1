<#
.SYNOPSIS
    Removes Lab 4.4 Security Configuration
.DESCRIPTION
    Reverts storage firewall to allow-all, removes the dev-assets container,
    and cleans up RBAC role assignments created during the lab.
    Does NOT delete the storage account (owned by Lab 4.1).
.PARAMETER Environment
    The environment to clean up (prod, dev, platform). Default: prod.
.PARAMETER Force
    Skip confirmation prompt.
.EXAMPLE
    .\Remove-LabResource.ps1 -Environment prod -Force
.NOTES
    Project: SkyCraft
    Author: SkyCraft
    Date: 2026-02-21
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$Environment = 'prod',

    [Parameter(Mandatory = $false)]
    [switch]$Force
)

$resourceGroupName = "$Environment-skycraft-swc-rg"
$storageAccountName = "${Environment}skycraftswcsa"
$vnetName = "$Environment-skycraft-swc-vnet"

Write-Host "=== Lab 4.4: Cleaning Up Security Configuration ===" -ForegroundColor Cyan

# 1. Verify Connection
if (-not (Get-AzContext)) {
    Write-Host " [ERROR] Not logged in. Please run Connect-AzAccount." -ForegroundColor Red; exit 1
}

# 2. Confirm
if (-not $Force) {
    $confirm = Read-Host "This will revert firewall rules and delete the 'dev-assets' container. Continue? (y/n)"
    if ($confirm -ne 'y') {
        Write-Host "Cleanup cancelled." -ForegroundColor Gray
        exit 0
    }
}

# 3. Revert Storage Firewall to Allow
try {
    Write-Host "Reverting storage firewall to 'Allow' default..." -ForegroundColor Yellow
    Update-AzStorageAccountNetworkRuleSet -ResourceGroupName $resourceGroupName `
        -Name $storageAccountName `
        -DefaultAction Allow -ErrorAction Stop
    Write-Host "  -> Firewall reverted to 'Allow'." -ForegroundColor Green
}
catch {
    Write-Host "  -> [ERROR] Failed to revert firewall." -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
}

# 4. Remove dev-assets container
try {
    Write-Host "Removing 'dev-assets' container..." -ForegroundColor Yellow
    $sa = Get-AzStorageAccount -ResourceGroupName $resourceGroupName -Name $storageAccountName -ErrorAction Stop
    Remove-AzStorageContainer -Name 'dev-assets' -Context $sa.Context -Force -ErrorAction Stop
    Write-Host "  -> Container 'dev-assets' removed." -ForegroundColor Green
}
catch {
    Write-Host "  -> [INFO] Container 'dev-assets' not found or already removed." -ForegroundColor Gray
}

# 5. Remove RBAC assignments (Storage Blob Data Contributor)
try {
    Write-Host "Removing 'Storage Blob Data Contributor' role assignments..." -ForegroundColor Yellow
    $storageId = (Get-AzStorageAccount -ResourceGroupName $resourceGroupName -Name $storageAccountName).Id
    $assignments = Get-AzRoleAssignment -Scope $storageId |
        Where-Object RoleDefinitionName -eq 'Storage Blob Data Contributor'

    if ($assignments) {
        foreach ($assignment in $assignments) {
            Remove-AzRoleAssignment -ObjectId $assignment.ObjectId `
                -RoleDefinitionName 'Storage Blob Data Contributor' `
                -Scope $storageId -ErrorAction Stop
            Write-Host "  -> Removed assignment for '$($assignment.DisplayName)'." -ForegroundColor Green
        }
    }
    else {
        Write-Host "  -> [INFO] No 'Storage Blob Data Contributor' assignments found." -ForegroundColor Gray
    }
}
catch {
    Write-Host "  -> [ERROR] Failed to remove RBAC assignments." -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
}

# 6. Remove Service Endpoint from subnet
try {
    Write-Host "Removing 'Microsoft.Storage' service endpoint from 'WorldSubnet'..." -ForegroundColor Yellow
    $vnet = Get-AzVirtualNetwork -ResourceGroupName $resourceGroupName -Name $vnetName -ErrorAction Stop
    $subnet = Get-AzVirtualNetworkSubnetConfig -Name 'WorldSubnet' -VirtualNetwork $vnet -ErrorAction Stop

    $endpoints = $subnet.ServiceEndpoints | Where-Object Service -ne 'Microsoft.Storage'
    Set-AzVirtualNetworkSubnetConfig -Name 'WorldSubnet' `
        -VirtualNetwork $vnet `
        -AddressPrefix $subnet.AddressPrefix `
        -ServiceEndpoint ($endpoints.Service) -ErrorAction Stop | Out-Null
    $vnet | Set-AzVirtualNetwork -ErrorAction Stop | Out-Null
    Write-Host "  -> Service endpoint removed from WorldSubnet." -ForegroundColor Green
}
catch {
    Write-Host "  -> [INFO] Could not remove service endpoint (may not exist)." -ForegroundColor Gray
}

Write-Host "`nCleanup Complete." -ForegroundColor Cyan
