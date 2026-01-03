<#
.SYNOPSIS
    Deploys Lab 2.2 security resources using Bicep templates.

.DESCRIPTION
    This script acts as the orchestrator for deploying the SkyCraft Lab 2.2 security resources.
    It calls the `main.bicep` template to deploy:
    - Application Security Groups (ASGs)
    - Network Security Groups (NSGs) with secure rules
    - Azure Bastion (Optional, with interactive prompt)
    
    It enforces project standards including proper tagging.

.PARAMETER Location
    The Azure region deployment target. Default: 'swedencentral'

.PARAMETER ProdResourceGroup
    The production resource group name. Default: 'prod-skycraft-swc-rg'

.PARAMETER PlatformResourceGroup
    The platform resource group name. Default: 'platform-skycraft-swc-rg'

.EXAMPLE
    .\Deploy-Bicep.ps1
    Deploys to default resource groups in Sweden Central.

.NOTES
    Project: SkyCraft
    Lab: 2.2 - Secure Access
    Author: Ops Team
    Date: 2026-01-03
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$Location = 'swedencentral',

    [Parameter(Mandatory = $false)]
    [string]$ProdResourceGroup = 'prod-skycraft-swc-rg',

    [Parameter(Mandatory = $false)]
    [string]$PlatformResourceGroup = 'platform-skycraft-swc-rg'
)

Write-Host "=== Lab 2.2 - Deploy Security Configuration ===" -ForegroundColor Cyan -BackgroundColor Black

# Verify Azure Connection
$context = Get-AzContext
if (-not $context) {
    Write-Host "Not logged in. Please run Connect-AzAccount" -ForegroundColor Red
    exit 1
}
Write-Host "Connected to: $($context.Subscription.Name)" -ForegroundColor Green

# Define paths
$bicepPath = Join-Path $PSScriptRoot "..\bicep"
$mainBicep = Join-Path $bicepPath "main.bicep"

# Verify Bicep file exists
if (-not (Test-Path $mainBicep)) {
    Write-Host "[ERROR] Bicep file not found: $mainBicep" -ForegroundColor Red
    exit 1
}

Write-Host "`nDeploying Lab 2.2 resources..." -ForegroundColor Cyan

# Ask user about Bastion deployment
Write-Host "`n[OPTIONAL] Azure Bastion provides secure RDP/SSH access without public IPs." -ForegroundColor Yellow
Write-Host "Cost: ~$140/month | Deployment time: ~15 minutes" -ForegroundColor Gray
$deployBastion = Read-Host "Do you want to deploy Azure Bastion? (y/N)"

$shouldDeployBastion = ($deployBastion -eq 'y' -or $deployBastion -eq 'Y')

if ($shouldDeployBastion) {
    Write-Host "  -> Bastion will be deployed" -ForegroundColor Green
}
else {
    Write-Host "  -> Bastion deployment skipped" -ForegroundColor Gray
}

try {
    $deploymentName = "Lab-2.2-Secure-access"
    
    $params = @{
        parLocation                  = $Location
        parResourceGroupNameProd     = $ProdResourceGroup
        parResourceGroupNamePlatform = $PlatformResourceGroup
        parDeployBastion             = $shouldDeployBastion
    }

    $deployment = New-AzSubscriptionDeployment `
        -Name $deploymentName `
        -Location $Location `
        -TemplateFile $mainBicep `
        -TemplateParameterObject $params `
        -Verbose

    if ($deployment.ProvisioningState -eq 'Succeeded') {
        Write-Host "`n[SUCCESS] Deployment completed successfully!" -ForegroundColor Green
        Write-Host "`nDeployment Outputs:" -ForegroundColor Cyan
        $deployment.Outputs | Format-Table -AutoSize
    }
    else {
        Write-Host "`n[FAILED] Deployment failed with state: $($deployment.ProvisioningState)" -ForegroundColor Red
    }
}
catch {
    Write-Host "`n[ERROR] Deployment failed with exception:" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    exit 1
}
