<#
.SYNOPSIS
    Deploys the App Service Lab 3.4 using Bicep.

.DESCRIPTION
    This script deploys the Azure App Service infrastructure defined in main.bicep.
    It targets the 'dev' environment by default.

.PARAMETER Location
    Azure region for deployment. Default: swedencentral.

.PARAMETER Environment
    Target environment (dev, prod). Default: dev.

.EXAMPLE
    .\Deploy-Bicep.ps1 -Environment dev

.NOTES
    Project: SkyCraft
    Date: 2026-01-31
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$Location = 'swedencentral',

    [Parameter(Mandatory = $false)]
    [ValidateSet('dev', 'prod')]
    [string]$Environment = 'dev'
)

$BicepFile = Join-Path $PSScriptRoot "..\bicep\main.bicep"
$DeploymentName = "deploy-lab3.4-$Environment"

Write-Host "=== Lab 3.4 Deployment: App Service ($Environment) ===" -ForegroundColor Cyan

# 1. Verify Connection
$context = Get-AzContext
if (-not $context) {
    Write-Host "Not logged in. Please run Connect-AzAccount." -ForegroundColor Red; exit 1
}

# 2. Deploy Bicep
try {
    Write-Host "Starting Bicep deployment from: $BicepFile" -ForegroundColor Yellow
    
    $params = @{
        parLocation    = $Location
        parEnvironment = $Environment
    }

    New-AzSubscriptionDeployment `
        -Name $DeploymentName `
        -Location $Location `
        -TemplateFile $BicepFile `
        -TemplateParameterObject $params `
        -ErrorAction Stop

    Write-Host "Deployment '$DeploymentName' completed successfully." -ForegroundColor Green
}
catch {
    Write-Host "Deployment failed!" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    exit 1
}
