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
    [string]$TemplateParameterFile
)

$ErrorActionPreference = 'Stop'

Write-Host "=== Lab 4.3: Deploying Azure Files Infrastructure ===" -ForegroundColor Cyan

# 1. Verify Connection
$context = Get-AzContext
if (-not $context) {
    Write-Host " [ERROR] Not logged in. Please run Connect-AzAccount." -ForegroundColor Red; exit 1
}

# 2. Resolve parameter file (backward-compatible) and hydrate parameters.
if (-not $TemplateParameterFile) {
    $TemplateParameterFile = Join-Path $PSScriptRoot "..\bicep\parameters\$Environment.bicepparam"
}

$deploymentParams = @{}
$built = az bicep build-params --file $TemplateParameterFile --stdout | ConvertFrom-Json
if ($LASTEXITCODE -ne 0 -or -not $built.parametersJson) {
    Write-Host "  -> [ERROR] Failed to compile parameter file: $TemplateParameterFile" -ForegroundColor Red
    exit 1
}
foreach ($p in ($built.parametersJson | ConvertFrom-Json -AsHashtable).parameters.GetEnumerator()) {
    $deploymentParams[$p.Key] = $p.Value.value
}

# Overlay the exact values this script has always set.
$deploymentParams.parLocation = $Location
$deploymentParams.parEnvironment = $Environment

# 3. Deploy Bicep
try {
    Write-Host "Deploying main.bicep to subscription level..." -ForegroundColor Yellow

    $deployment = New-AzSubscriptionDeployment `
        -Name "lab-4.3-deploy-$(Get-Date -Format 'yyyyMMdd-HHmm')" `
        -Location $Location `
        -TemplateFile (Join-Path $PSScriptRoot "..\bicep\main.bicep") `
        -TemplateParameterObject $deploymentParams `
        -ErrorAction Stop

    if ($deployment.ProvisioningState -ne 'Succeeded') {
        Write-Host "`n [FAILED] Deployment failed with state: $($deployment.ProvisioningState)" -ForegroundColor Red
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
    exit 1
}
