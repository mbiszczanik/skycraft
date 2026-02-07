<#
.SYNOPSIS
    Deploys Lab 4.3 Environment
.DESCRIPTION
    Deploys the Storage Account and File Services required for Azure Files lab.
    Targets the Production environment by default to demonstrate GRS and protection features.
.PARAMETER Location
    Azure region for deployment. Default: swedencentral.
.PARAMETER Environment
    Target environment (prod, dev, platform). Default: prod.
.EXAMPLE
    .\Deploy-Bicep.ps1 -Environment prod
.NOTES
    Project: SkyCraft
    Author: SkyCraft
    Date: 2026-02-07
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$Location = 'swedencentral',

    [Parameter(Mandatory = $false)]
    [string]$Environment = 'prod'
)

Write-Host "=== Lab 4.3: Deploying Azure Files Infrastructure ===" -ForegroundColor Cyan

# 1. Verify Connection
$context = Get-AzContext
if (-not $context) {
    Write-Host " [ERROR] Not logged in. Please run Connect-AzAccount." -ForegroundColor Red; exit 1
}

# 2. Deploy Bicep
try {
    Write-Host "Deploying main.bicep to subscription level..." -ForegroundColor Yellow
    
    $deployment = New-AzSubscriptionDeployment `
        -Name "lab-4.3-deploy-$(Get-Date -Format 'yyyyMMdd-HHmm')" `
        -Location $Location `
        -TemplateFile "..\bicep\main.bicep" `
        -parLocation $Location `
        -parEnvironment $Environment `
        -ErrorAction Stop

    Write-Host "`nSuccessfully deployed Lab 4.3 resources!" -ForegroundColor Green
    Write-Host "  -> Storage Account: $($deployment.Outputs.outStorageAccountName.Value)" -ForegroundColor Green
    Write-Host "  -> Resource ID:     $($deployment.Outputs.outStorageAccountId.Value)" -ForegroundColor Green
}
catch {
    Write-Host "`n [ERROR] Deployment failed!" -ForegroundColor Red
    Write-Host "  -> Cause: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
