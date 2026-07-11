<#
.SYNOPSIS
    Deploys Lab 2.1 networking resources using Bicep templates.

.DESCRIPTION
    This script orchestrates the deployment of the Hub-and-Spoke networking topology 
    for SkyCraft Lab 2.1. It calls the main.bicep template to create:
    - Platform (Hub) Virtual Network with 4 subnets.
    - Production (Spoke) Virtual Network with 3 subnets.
    - Bi-directional VNet Peering.

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

.NOTES
    Project: SkyCraft
    Lab: 2.1 - Virtual Networks
    Author: Marcin Biszczanik
    Date: 2026-01-04
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
    [string]$DevResourceGroup = 'dev-skycraft-swc-rg',

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$PlatformResourceGroup = 'platform-skycraft-swc-rg',

    [Parameter(Mandatory = $false)]
    [string]$TemplateParameterFile
)

$ErrorActionPreference = 'Stop'

Write-Host "=== Lab 2.1 - Deploy Networking Configuration ===" -ForegroundColor Cyan -BackgroundColor Black

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

Write-Host "`nDeploying Lab 2.1 Resources..." -ForegroundColor Cyan

try {
    $deploymentName = "Lab-2.1-Virtual-Networks"

    # Start from the values declared in the .bicepparam file (template defaults),
    # then overlay the script-supplied values so a no-argument run deploys exactly
    # what it did before parameter files existed.
    $params = @{}
    $built = (bicep build-params $TemplateParameterFile --stdout | ConvertFrom-Json)
    if ($built.parametersJson) {
        ($built.parametersJson | ConvertFrom-Json).parameters.PSObject.Properties | ForEach-Object {
            $params[$_.Name] = $_.Value.value
        }
    }

    # Runtime / script-supplied overrides win.
    $params.parLocation = $Location
    $params.parResourceGroupNameProd = $ProdResourceGroup
    $params.parResourceGroupNameDev = $DevResourceGroup
    $params.parResourceGroupNamePlatform = $PlatformResourceGroup

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
        if ($deployment.Error) {
            Write-Host "Error Code: $($deployment.Error.Code)" -ForegroundColor Red
            Write-Host "Error Message: $($deployment.Error.Message)" -ForegroundColor Red
            Write-Host "Error Target: $($deployment.Error.Target)" -ForegroundColor Red
            if ($deployment.Error.Details) {
                foreach ($detail in $deployment.Error.Details) {
                    Write-Host "  - Detail Code: $($detail.Code)" -ForegroundColor Red
                    Write-Host "  - Detail Message: $($detail.Message)" -ForegroundColor Red
                }
            }
        }

        # Get operations
        $ops = Get-AzSubscriptionDeploymentOperation -DeploymentName $deploymentName
        $failedOps = $ops | Where-Object { $_.ProvisioningState -eq "Failed" }
        foreach ($op in $failedOps) {
            Write-Host "Failed Operation: $($op.Properties.TargetResource.ResourceName)" -ForegroundColor Yellow
            Write-Host "Status Message: $($op.Properties.StatusMessage)" -ForegroundColor Red
        }
        exit 1
    }
}
catch {
    Write-Host "`n[ERROR] Deployment failed with exception:" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    exit 1
}

Write-Host "`nNext Step: Run .\Test-Lab.ps1 to verify the configuration." -ForegroundColor Yellow
