<#
.SYNOPSIS
    Deploys Lab 3.1 Infrastructure Resources (Bicep).

.DESCRIPTION
    This script orchestrates the deployment of SkyCraft infrastructure (VNets, NSGs, LBs).
    It deploys main.bicep with the environment's .bicepparam file (dev or prod).

.PARAMETER Location
    The Azure region deployment target. Default: 'swedencentral'

.PARAMETER Environment
    Target environment (dev, prod). Default: 'dev'

.PARAMETER WhatIf
    Previews the deployment with the ARM what-if API and exits. Nothing is created or changed.

.EXAMPLE
    .\Deploy-Bicep.ps1 -Environment dev
    Deploys the Development environment.

.EXAMPLE
    .\Deploy-Bicep.ps1 -Environment dev -WhatIf
    Previews the Development deployment without changing anything.

.NOTES
    Project: SkyCraft
    Lab: 3.1 - Infrastructure as Code
    Date: 2026-01-12
#>

#Requires -Version 7.0
#Requires -Modules Az.Accounts, Az.Resources

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [ValidateSet('swedencentral', 'northeurope')]
    [string]$Location = 'swedencentral',

    [Parameter(Mandatory = $false)]
    [ValidateSet('dev', 'prod')]
    [string]$Environment = 'dev',

    [Parameter(Mandatory = $false)]
    [switch]$WhatIf
)

$ErrorActionPreference = 'Stop'

Write-Host "=== Lab 3.1 - Deploy Infrastructure ($Environment) ===" -ForegroundColor Cyan

# 1. Verify Azure Connection
$context = Get-AzContext
if (-not $context) {
    Write-Host "Not logged in. Please run Connect-AzAccount" -ForegroundColor Red
    $Host.SetShouldExit(1)
    exit 1
}
Write-Host "Connected to: $($context.Subscription.Name)" -ForegroundColor Green

# 2. Deploy Bicep
$bicepPath = Join-Path $PSScriptRoot "..\bicep\main.bicep"
$paramPath = Join-Path $PSScriptRoot "..\bicep\parameters\$Environment.bicepparam"

if (-not (Test-Path $bicepPath)) { Write-Host "Bicep file missing: $bicepPath" -ForegroundColor Red; $Host.SetShouldExit(1); exit 1 }

$deploymentName = "SkyCraft-$Environment-$(Get-Date -Format 'yyyyMMdd-HHmm')"

Write-Host "`nStarting Deployment: $deploymentName" -ForegroundColor Cyan
Write-Host "Template: $bicepPath" -ForegroundColor Gray
Write-Host "Params:   $paramPath" -ForegroundColor Gray

try {
    
    $deployParams = @{
        Name                  = $deploymentName
        Location              = $Location
        TemplateFile          = $bicepPath
        TemplateParameterFile = $paramPath
        ErrorAction           = 'Stop'
    }

    if ($WhatIf) {
        Write-Host "Running in what-if mode (dry run)..." -ForegroundColor Cyan
        Get-AzSubscriptionDeploymentWhatIfResult @deployParams
        Write-Host "`nWhat-if completed. Review the changes above - nothing was deployed." -ForegroundColor Cyan
    }
    else {
        Write-Host "Deploying..." -ForegroundColor Yellow
        $dep = New-AzSubscriptionDeployment @deployParams
        
        if ($dep.ProvisioningState -eq 'Succeeded') {
            Write-Host "`n[SUCCESS] Deployment complete!" -ForegroundColor Green
            $dep.Outputs | Format-Table -AutoSize
        }
        else {
            Write-Host "`n[FAILED] State: $($dep.ProvisioningState)" -ForegroundColor Red
        }
    }
}
catch {
    Write-Host "`n[ERROR] Deployment failed!" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    $Host.SetShouldExit(1)
    exit 1
}
