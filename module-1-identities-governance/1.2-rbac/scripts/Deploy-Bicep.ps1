<#
.SYNOPSIS
    Deploys the Lab 1.2 infrastructure (Resource Groups) using Bicep.

.DESCRIPTION
    This script deploys the required resource groups for SkyCraft Lab 1.2 using the
    'resource-groups.bicep' template. It targets the subscription scope.

.PARAMETER Location
    Azure region for deployment. Default: swedencentral.

.EXAMPLE
    .\Deploy-Bicep.ps1
    Deploys to Sweden Central.

.NOTES
    Project: SkyCraft
    Lab: 1.2 - RBAC
#>

[CmdletBinding()]
param(
    [string]$Location = 'swedencentral'
)

$ErrorActionPreference = 'Stop'

Write-Host "=== Lab 1.2: Infrastructure Deployment ===" -ForegroundColor Cyan -BackgroundColor Black

# Check Azure Context
try {
    $context = Get-AzContext
    if (-not $context) {
        Write-Host "Checking Azure connection..." -ForegroundColor Yellow
        $context = Connect-AzAccount -ErrorAction Stop
    }
    Write-Host "Connected to: $($context.Subscription.Name) ($($context.Subscription.Id))" -ForegroundColor Green
}
catch {
    Write-Host "  -> [ERROR] Failed to connect to Azure: $_" -ForegroundColor Red
    exit 1
}

# Deployment
$templateFile = Join-Path $PSScriptRoot "..\bicep\resource-groups.bicep"
if (-not (Test-Path $templateFile)) {
    Write-Host "  -> [ERROR] Template file not found at: $templateFile" -ForegroundColor Red
    exit 1
}

$deploymentName = "Lab-1.2-RBAC-RG-$(Get-Date -Format 'yyyyMMdd-HHmm')"

Write-Host "`nStarting Bicep Deployment..." -ForegroundColor Cyan
Write-Host "  Template: $templateFile" -ForegroundColor Gray
Write-Host "  Location: $Location" -ForegroundColor Gray
Write-Host "  DeploymentName: $deploymentName" -ForegroundColor Gray

try {
    New-AzSubscriptionDeployment `
        -Name $deploymentName `
        -Location $Location `
        -TemplateFile $templateFile `
        -ErrorAction Stop | Out-Null
    
    Write-Host "  -> [SUCCESS] Resource Groups deployed successfully." -ForegroundColor Green
    
    # Verify RGs
    $rgs = @("dev-skycraft-swc-rg", "prod-skycraft-swc-rg", "platform-skycraft-swc-rg")
    foreach($rg in $rgs) {
        if(Get-AzResourceGroup -Name $rg -ErrorAction SilentlyContinue) {
             Write-Host "     - Verified: $rg exists" -ForegroundColor Green
        } else {
             Write-Host "     - Warning: $rg not found after deployment" -ForegroundColor Yellow
        }
    }
}
catch {
    Write-Host "  -> [ERROR] Deployment failed: $_" -ForegroundColor Red
    exit 1
}

Write-Host "`nDeployment Complete." -ForegroundColor Green