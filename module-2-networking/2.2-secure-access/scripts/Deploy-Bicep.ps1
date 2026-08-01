<#
.SYNOPSIS
    Deploys Lab 2.2 security resources using Bicep templates.

.DESCRIPTION
    This script acts as the orchestrator for deploying the SkyCraft Lab 2.2 security resources.
    It calls the `main.bicep` template to deploy:
    - Application Security Groups (ASGs)
    - Network Security Groups (NSGs) with secure rules
    - Azure Bastion (Optional, opt in with -DeployBastion)
    
    It enforces project standards including proper tagging.

.PARAMETER Location
    The Azure region deployment target. Default: 'swedencentral'

.PARAMETER ProdResourceGroup
    The production resource group name. Default: 'prod-skycraft-swc-rg'

.PARAMETER PlatformResourceGroup
    The platform resource group name. Default: 'platform-skycraft-swc-rg'

.PARAMETER TemplateParameterFile
    Path to the Bicep parameter file supplying template defaults. Defaults to
    '..\bicep\parameters\main.bicepparam' (relative to this script's folder).
    Script-supplied and computed values are overlaid on top of this file's values.

.EXAMPLE
    .\Deploy-Bicep.ps1
    Deploys to default resource groups in Sweden Central.

.PARAMETER DeployBastion
    Deploy Azure Bastion. Off by default: Bastion carries a standing cost.

.PARAMETER Force
    Run without prompting. Retained for interface consistency across the lab scripts.

.NOTES
    Project: SkyCraft
    Lab: 2.2 - Secure Access
    Author: Ops Team
    Date: 2026-01-03
#>

#Requires -Version 7.0
#Requires -Modules Az.Accounts, Az.Resources

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [ValidateSet('swedencentral', 'northeurope')]
    [string]$Location = 'swedencentral',

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$ProdResourceGroup = 'prod-skycraft-swc-rg',

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$PlatformResourceGroup = 'platform-skycraft-swc-rg',

    [Parameter(Mandatory = $false)]
    [string]$TemplateParameterFile,

    [Parameter(Mandatory = $false)]
    [switch]$DeployBastion,

    [Parameter(Mandatory = $false)]
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

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

if (-not $TemplateParameterFile) {
    $TemplateParameterFile = Join-Path $PSScriptRoot '..\bicep\parameters\main.bicepparam'
}

# Verify Bicep file exists
if (-not (Test-Path $mainBicep)) {
    Write-Host "[ERROR] Bicep file not found: $mainBicep" -ForegroundColor Red
    exit 1
}

# Verify parameter file exists
if (-not (Test-Path $TemplateParameterFile)) {
    Write-Host "[ERROR] Parameter file not found: $TemplateParameterFile" -ForegroundColor Red
    exit 1
}

Write-Host "`nDeploying Lab 2.2 resources..." -ForegroundColor Cyan

# Azure Bastion is optional: it provides secure RDP/SSH without public IPs, at a
# standing cost. Opt in with -DeployBastion; -Force answers "no" without prompting.
$shouldDeployBastion = $DeployBastion.IsPresent
if (-not $Force -and -not $DeployBastion) {
    Write-Host "`n[OPTIONAL] Azure Bastion provides secure RDP/SSH access without public IPs." -ForegroundColor Yellow
    Write-Host "Cost: ~$140/month | Deployment time: ~15 minutes" -ForegroundColor Gray
    Write-Host "  -> Not requested (-DeployBastion absent). Skipping." -ForegroundColor Gray
}
if ($shouldDeployBastion) {
    Write-Host "  -> Bastion will be deployed" -ForegroundColor Green
}
else {
    Write-Host "  -> Bastion deployment skipped" -ForegroundColor Gray
}

try {
    $deploymentName = "Lab-2.2-Secure-access"

    # Start from the values declared in the .bicepparam file (template defaults),
    # then overlay the script-supplied and computed values so a no-argument run
    # deploys exactly what it did before parameter files existed.
    $params = @{}
    $built = az bicep build-params --file $TemplateParameterFile --stdout | ConvertFrom-Json
    if ($LASTEXITCODE -ne 0 -or -not $built.parametersJson) {
        Write-Host "  -> [ERROR] Failed to compile parameter file: $TemplateParameterFile" -ForegroundColor Red
        exit 1
    }
    foreach ($p in ($built.parametersJson | ConvertFrom-Json -AsHashtable).parameters.GetEnumerator()) {
        $params[$p.Key] = $p.Value.value
    }

    # Runtime / script-supplied overrides win.
    $params.parLocation = $Location
    $params.parResourceGroupNameProd = $ProdResourceGroup
    $params.parResourceGroupNamePlatform = $PlatformResourceGroup
    $params.parDeployBastion = $shouldDeployBastion

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
