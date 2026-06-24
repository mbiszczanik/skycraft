<#
.SYNOPSIS
    Removes Lab 4.3 Resources
.DESCRIPTION
    Deletes the resource group and all contained resources for Lab 4.3.
.PARAMETER Environment
    The environment to clean up (prod, dev, platform). Default: prod.
.PARAMETER Force
    Skip confirmation prompt.
.EXAMPLE
    .\Remove-LabResource.ps1 -Environment prod -Force
.NOTES
    Project: SkyCraft
    Author: SkyCraft
    Date: 2026-02-07
#>

#Requires -Version 7.0
#Requires -Modules Az.Accounts, Az.Resources

[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory = $false)]
    [ValidateSet('prod', 'dev', 'platform')]
    [string]$Environment = 'prod',

    [Parameter(Mandatory = $false)]
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
if ($Force) { $ConfirmPreference = 'None' }

$resourceGroupName = "$Environment-skycraft-swc-rg"

Write-Host "=== Lab 4.3: Cleaning Up Lab Resources ===" -ForegroundColor Cyan

# 1. Verify Connection
if (-not (Get-AzContext)) {
    Write-Host " [ERROR] Not logged in. Please run Connect-AzAccount." -ForegroundColor Red; exit 1
}

# 2. Confirm Deletion
if (-not (Get-AzResourceGroup -Name $resourceGroupName -ErrorAction SilentlyContinue)) {
    Write-Host " [INFO] Resource group '$resourceGroupName' does not exist. Skipping." -ForegroundColor Gray
    exit 0
}

# 3. Delete Resource Group
try {
    if ($PSCmdlet.ShouldProcess($resourceGroupName, 'Remove resource group')) {
        Write-Host "Removing resource group '$resourceGroupName'..." -ForegroundColor Yellow
        Remove-AzResourceGroup -Name $resourceGroupName -Force -ErrorAction Stop
        Write-Host "  -> Successfully removed resource group." -ForegroundColor Green
    }
}
catch {
    Write-Host "  -> [ERROR] Failed to remove resource group." -ForegroundColor Red
    Write-Host "  -> Cause: $($_.Exception.Message)" -ForegroundColor Red
}
