<#
.SYNOPSIS
    Deploys Lab 3.1 Infrastructure Resources (Bicep).

.DESCRIPTION
    This script orchestrates the deployment of SkyCraft infrastructure (VNets, NSGs, LBs).
    It handles SSH Key generation and passes it to the Bicep template.

.PARAMETER Location
    The Azure region deployment target. Default: 'swedencentral'

.PARAMETER Environment
    Target environment (dev, prod). Default: 'dev'

.PARAMETER WhatIf
    If specified, runs What-If analysis instead of deploying.

.EXAMPLE
    .\Deploy-Infra.ps1 -Environment dev
    Deploys the Development environment.

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
    exit 1
}
Write-Host "Connected to: $($context.Subscription.Name)" -ForegroundColor Green

# 2. Deploy Bicep
$bicepPath = Join-Path $PSScriptRoot "..\bicep\main.bicep"
$paramPath = Join-Path $PSScriptRoot "..\bicep\parameters\$Environment.bicepparam"

if (-not (Test-Path $bicepPath)) { Write-Host "Bicep file missing: $bicepPath" -ForegroundColor Red; exit 1 }

$deploymentName = "SkyCraft-$Environment-$(Get-Date -Format 'yyyyMMdd-HHmm')"

Write-Host "`nStarting Deployment: $deploymentName" -ForegroundColor Cyan
Write-Host "Template: $bicepPath" -ForegroundColor Gray
Write-Host "Params:   $paramPath" -ForegroundColor Gray

try {
    # Compile the .bicepparam with the Azure CLI's own Bicep rather than handing the file to Az,
    # which resolves it by shelling out to a bare `bicep` on PATH that `az bicep install` does
    # not provide. This script computes nothing, so there is no overlay: the hashtable is the
    # parameter file and nothing more.
    $params = @{}
    $built = az bicep build-params --file $paramPath --stdout | ConvertFrom-Json
    if ($LASTEXITCODE -ne 0 -or -not $built.parametersJson) {
        Write-Host "  -> [ERROR] Failed to compile parameter file: $paramPath" -ForegroundColor Red
        exit 1
    }
    foreach ($p in ($built.parametersJson | ConvertFrom-Json -AsHashtable).parameters.GetEnumerator()) {
        $params[$p.Key] = $p.Value.value
    }

    $commonArgs = @{
        Name                    = $deploymentName
        Location                = $Location
        TemplateFile            = $bicepPath
        TemplateParameterObject = $params
    }

    if ($WhatIf) {
        Write-Host "Running What-If Analysis..." -ForegroundColor Yellow
        New-AzSubscriptionDeployment @commonArgs -WhatIf
    }
    else {
        Write-Host "Deploying..." -ForegroundColor Yellow
        $dep = New-AzSubscriptionDeployment @commonArgs
        
        if ($dep.ProvisioningState -eq 'Succeeded') {
            Write-Host "`n[SUCCESS] Deployment complete!" -ForegroundColor Green
            $dep.Outputs | Format-Table -AutoSize
        }
        else {
            Write-Host "`n[FAILED] State: $($dep.ProvisioningState)" -ForegroundColor Red
            exit 1
        }
    }
}
catch {
    Write-Host "`n[ERROR] Deployment failed!" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    exit 1
}
