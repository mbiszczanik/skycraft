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
.PARAMETER WhatIf
    Previews the deployment with the ARM what-if API and exits. Nothing is created or changed.
.EXAMPLE
    .\Deploy-Bicep.ps1 -Environment prod
.EXAMPLE
    .\Deploy-Bicep.ps1 -Environment prod -WhatIf
    Previews the Azure Files deployment without changing anything.
.NOTES
    Project: SkyCraft
    Author: SkyCraft
    Date: 2026-02-07
#>

#Requires -Version 7.0
#Requires -Modules Az.Accounts, Az.Resources

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [ValidateSet('swedencentral', 'northeurope')]
    [string]$Location = 'swedencentral',

    [Parameter(Mandatory = $false)]
    [ValidateSet('prod', 'dev', 'platform')]
    [string]$Environment = 'prod',

    [Parameter(Mandatory = $false)]
    [switch]$WhatIf
)

$ErrorActionPreference = 'Stop'

Write-Host "=== Lab 4.3: Deploying Azure Files Infrastructure ===" -ForegroundColor Cyan

# 1. Verify Connection
$context = Get-AzContext
if (-not $context) {
    Write-Host " [ERROR] Not logged in. Please run Connect-AzAccount." -ForegroundColor Red; $Host.SetShouldExit(1); exit 1
}

# 2. Deploy Bicep
try {
    Write-Host "Deploying main.bicep to subscription level..." -ForegroundColor Yellow
    
    $deployParams = @{
        Name           = "lab-4.3-deploy-$(Get-Date -Format 'yyyyMMdd-HHmm')"
        Location       = $Location
        TemplateFile   = (Join-Path $PSScriptRoot "..\bicep\main.bicep")
        parLocation    = $Location
        parEnvironment = $Environment
        ErrorAction    = 'Stop'
    }

    if ($WhatIf) {
        Write-Host "  Running in what-if mode (dry run)..." -ForegroundColor Cyan
        Get-AzSubscriptionDeploymentWhatIfResult @deployParams
        Write-Host "`n  What-if completed. Review the changes above - nothing was deployed." -ForegroundColor Cyan
        exit 0
    }

    $deployment = New-AzSubscriptionDeployment @deployParams

    if ($deployment.ProvisioningState -ne 'Succeeded') {
        Write-Host "`n [FAILED] Deployment failed with state: $($deployment.ProvisioningState)" -ForegroundColor Red
        $Host.SetShouldExit(1)
        exit 1
    }

    Write-Host "`nSuccessfully deployed Lab 4.3 resources!" -ForegroundColor Green
    if ($deployment.Outputs) {
        Write-Host "  -> Storage Account: $($deployment.Outputs.outStorageAccountName.Value)" -ForegroundColor Green
        Write-Host "  -> Resource ID:     $($deployment.Outputs.outStorageAccountId.Value)" -ForegroundColor Green
    }
}
catch {
    Write-Host "`n [ERROR] Deployment failed!" -ForegroundColor Red
    Write-Host "  -> Cause: $($_.Exception.Message)" -ForegroundColor Red
    $Host.SetShouldExit(1)
    exit 1
}
