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

#Requires -Version 7.0
#Requires -Modules Az.Accounts, Az.App, Az.ContainerInstance, Az.ContainerRegistry

[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory = $false)]
    [switch]$Force,

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$ResourceGroupName = 'dev-skycraft-swc-rg'
)

$ErrorActionPreference = 'Stop'
if ($Force) { $ConfirmPreference = 'None' }

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

# Summary of resources targeted for deletion
Write-Host "This will delete the following resources from $($ResourceGroupName):" -ForegroundColor Yellow
foreach ($res in $resourcesToDelete) {
    Write-Host " - [$($res.Type)] $($res.Name)" -ForegroundColor Gray
}

Write-Host "`nStarting cleanup..." -ForegroundColor Cyan

# 1. Remove ACA
Write-Host "Removing Container App: dev-skycraft-swc-aca-world-02..." -ForegroundColor Yellow
# Using az cli for ACA deletion to be safe or Az module
if ($PSCmdlet.ShouldProcess("dev-skycraft-swc-aca-world-02", "Remove Container App")) {
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
}

# 2. Remove ACA Environment
Write-Host "Removing Container Apps Environment: dev-skycraft-swc-cae-02..." -ForegroundColor Yellow
if ($PSCmdlet.ShouldProcess("dev-skycraft-swc-cae-02", "Remove Container Apps Environment")) {
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
}

# 3. Remove ACI
Write-Host "Removing Container Instance: dev-skycraft-swc-aci-auth..." -ForegroundColor Yellow
if ($PSCmdlet.ShouldProcess("dev-skycraft-swc-aci-auth", "Remove Container Instance")) {
    try {
        Remove-AzContainerGroup -Name "dev-skycraft-swc-aci-auth" -ResourceGroupName $ResourceGroupName -ErrorAction Stop | Out-Null
        Write-Host "  -> Deleted" -ForegroundColor Green
    } catch {
        Write-Host "  -> [INFO] Not found or already deleted." -ForegroundColor Gray
    }
}

# 4. Remove ACR
Write-Host "Removing Container Registry: devskycraftswcacr01..." -ForegroundColor Yellow
if ($PSCmdlet.ShouldProcess("devskycraftswcacr01", "Remove Container Registry")) {
    try {
        Remove-AzContainerRegistry -Name "devskycraftswcacr01" -ResourceGroupName $ResourceGroupName -ErrorAction Stop | Out-Null
        Write-Host "  -> Deleted" -ForegroundColor Green
    } catch {
        Write-Host "  -> [INFO] Not found or already deleted." -ForegroundColor Gray
    }
}

Write-Host "`nCleanup Complete." -ForegroundColor Green
