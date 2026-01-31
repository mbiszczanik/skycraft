<#
.SYNOPSIS
    Cleans up resources created in Lab 3.3.

.DESCRIPTION
    This script removes the Container Registry, Container Instance, and Container Apps 
    created for Lab 3.3. It preserves the Resource Group (dev-skycraft-swc-rg) as it 
    may contain resources from other labs (e.g., VNets).

.PARAMETER Force
    Skip the confirmation prompt.

.PARAMETER ResourceGroupName
    The resource group name. Default: 'dev-skycraft-swc-rg'

.EXAMPLE
    .\Remove-LabResource.ps1
    Prompts for confirmation before deleting resources.

.NOTES
    Project: SkyCraft
    Lab: 3.3 - Containers
    Author: Antigravity
    Date: 2026-01-31
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [switch]$Force,

    [Parameter(Mandatory = $false)]
    [string]$ResourceGroupName = 'dev-skycraft-swc-rg'
)

Write-Host "=== Lab 3.3 - Resource Cleanup ===" -ForegroundColor Cyan -BackgroundColor Black

# Verify Azure Connection
$context = Get-AzContext
if (-not $context) {
    Write-Host "Not logged in. Please run Connect-AzAccount" -ForegroundColor Red
    exit 1
}

$resourcesToDelete = @(
    @{ Name = "dev-skycraft-swc-aca-world-02"; Type = "Container App" },
    @{ Name = "dev-skycraft-swc-cae-02"; Type = "Container Apps Environment" },
    @{ Name = "dev-skycraft-swc-aci-auth"; Type = "Container Instance" },
    @{ Name = "devskycraftswcacr01"; Type = "Container Registry" }
)

# Confirmation
if (-not $Force) {
    Write-Host "This will delete the following resources from $($ResourceGroupName):" -ForegroundColor Yellow
    foreach ($res in $resourcesToDelete) {
        Write-Host " - [$($res.Type)] $($res.Name)" -ForegroundColor Gray
    }
    
    $confirm = Read-Host "Are you sure? (y/N)"
    if ($confirm -notmatch "^y$") {
        Write-Host "Cleanup cancelled." -ForegroundColor Yellow
        exit 0
    }
}

Write-Host "`nStarting cleanup..." -ForegroundColor Cyan

# 1. Remove ACA
Write-Host "Removing Container App: dev-skycraft-swc-aca-world-02..." -ForegroundColor Yellow
# Using az cli for ACA deletion to be safe or Az module
try {
    # Try Az module first if available, else CLI
    if (Get-Command Remove-AzContainerApp -ErrorAction SilentlyContinue) {
        Remove-AzContainerApp -Name "dev-skycraft-swc-aca-world-02" -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue | Out-Null
        Write-Host "  -> Deleted (via Az)" -ForegroundColor Green
    } else {
        # Fallback to CLI
        az containerapp delete --name "dev-skycraft-swc-aca-world-02" --resource-group $ResourceGroupName --yes --output none
        Write-Host "  -> Deleted (via CLI)" -ForegroundColor Green
    }
} catch {
    Write-Host "  -> [INFO] Not found or already deleted." -ForegroundColor Gray
}

# 2. Remove ACA Environment
Write-Host "Removing Container Apps Environment: dev-skycraft-swc-cae-02..." -ForegroundColor Yellow
try {
    if (Get-Command Remove-AzContainerAppManagedEnvironment -ErrorAction SilentlyContinue) {
        Remove-AzContainerAppManagedEnvironment -Name "dev-skycraft-swc-cae-02" -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue | Out-Null
         Write-Host "  -> Deleted (via Az)" -ForegroundColor Green
    } else {
         az containerapp env delete --name "dev-skycraft-swc-cae-02" --resource-group $ResourceGroupName --yes --output none
         Write-Host "  -> Deleted (via CLI)" -ForegroundColor Green
    }
} catch {
    Write-Host "  -> [INFO] Not found or already deleted." -ForegroundColor Gray
}

# 3. Remove ACI
Write-Host "Removing Container Instance: dev-skycraft-swc-aci-auth..." -ForegroundColor Yellow
try {
    Remove-AzContainerGroup -Name "dev-skycraft-swc-aci-auth" -ResourceGroupName $ResourceGroupName -ErrorAction Stop | Out-Null
    Write-Host "  -> Deleted" -ForegroundColor Green
} catch {
    Write-Host "  -> [INFO] Not found or already deleted." -ForegroundColor Gray
}

# 4. Remove ACR
Write-Host "Removing Container Registry: devskycraftswcacr01..." -ForegroundColor Yellow
try {
    Remove-AzContainerRegistry -Name "devskycraftswcacr01" -ResourceGroupName $ResourceGroupName -ErrorAction Stop | Out-Null
    Write-Host "  -> Deleted" -ForegroundColor Green
} catch {
    Write-Host "  -> [INFO] Not found or already deleted." -ForegroundColor Gray
}

Write-Host "`nCleanup Complete." -ForegroundColor Green
