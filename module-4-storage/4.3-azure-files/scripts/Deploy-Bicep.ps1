<#
.SYNOPSIS
    Deploys Lab 4.3 Environment
.DESCRIPTION
    Deploys the Storage Account and File Services required for Azure Files lab.
.NOTES
    Project: SkyCraft
    Author: SkyCraft Team
    Date: 2026-02-07
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$Location = 'swedencentral',

    [Parameter(Mandatory = $false)]
    [string]$ResourceGroupName = 'prod-skycraft-swc-rg'
)

Write-Host "=== Lab 4.3: Deploying Infrastructure ===" -ForegroundColor Cyan

# 1. Verify Connection
$context = Get-AzContext
if (-not $context) {
    Write-Host "Not logged in. Please run Connect-AzAccount." -ForegroundColor Red; exit 1
}

# 2. Deploy Bicep
try {
    Write-Host "Deploying main.bicep to subscription..." -ForegroundColor Yellow
    
    $deployment = New-AzSubscriptionDeployment `
        -Name "lab-4.3-deploy-$(Get-Date -Format 'yyyyMMdd-HHmm')" `
        -Location $Location `
        -TemplateFile "..\bicep\main.bicep" `
        -parLocation $Location `
        -parResourceGroupName $ResourceGroupName `
        -ErrorAction Stop

    Write-Host "Deployment Successful!" -ForegroundColor Green
    Write-Host "Storage Account Name: $($deployment.Outputs.outStorageAccountName.Value)" -ForegroundColor Green
}
catch {
    Write-Host "Deployment Failed!" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    exit 1
}
