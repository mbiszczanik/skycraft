<#
.SYNOPSIS
    Deploys Lab 2.3 name resolution and load balancer infrastructure via Bicep.

.DESCRIPTION
    Runs an Azure subscription-scoped deployment of the Lab 2.3 main.bicep template, which
    provisions public and private DNS zones, VNet links, A/CNAME records, and dev/prod load
    balancers. The deployment name is stamped with the current timestamp so successive runs
    do not overwrite each other in the deployment history.

.PARAMETER Location
    The Azure region for the subscription-scoped deployment. Defaults to 'swedencentral'.

.PARAMETER TemplateFile
    Path to the Bicep template to deploy. Defaults to '..\bicep\main.bicep' (relative to
    this script's folder).

.PARAMETER TemplateParameterFile
    Path to the Bicep parameter file supplying template defaults. Defaults to
    '..\bicep\parameters\main.bicepparam' (relative to this script's folder).
    This script supplies no per-template overrides, so the file is passed directly.

.EXAMPLE
    .\Deploy-Bicep.ps1
    Deploys the default main.bicep to Sweden Central using the current Az context.

.NOTES
    Project: SkyCraft
    Lab: 2.3 - Name Resolution & Load Balancing
    Author: Marcin Biszczanik
    Date: 2026-01-11
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
    [string]$TemplateFile = '..\bicep\main.bicep',

    [Parameter(Mandatory = $false)]
    [string]$TemplateParameterFile
)

$ErrorActionPreference = 'Stop'

$deploymentName = "Lab-2.3-DNS-$(Get-Date -Format 'yyyyMMdd-HHmm')"

if (-not $TemplateParameterFile) {
    $TemplateParameterFile = Join-Path $PSScriptRoot '..\bicep\parameters\main.bicepparam'
}

Write-Host "=== Lab 2.3 - Deploy Bicep (DNS) ===" -ForegroundColor Cyan -BackgroundColor Black

# Verify Bicep File
if (-not (Test-Path $TemplateFile)) {
    Write-Host "Error: Template file not found at $TemplateFile" -ForegroundColor Red
    exit 1
}

# Verify parameter file
if (-not (Test-Path $TemplateParameterFile)) {
    Write-Host "Error: Parameter file not found at $TemplateParameterFile" -ForegroundColor Red
    exit 1
}

Write-Host "Starting deployment: $deploymentName..." -ForegroundColor Yellow

try {
    # This script supplies no per-template overrides, so the parameter file is
    # passed straight through. A no-argument run therefore deploys exactly what it
    # did before parameter files existed (all template defaults).
    $deployment = New-AzDeployment `
        -Name $deploymentName `
        -Location $Location `
        -TemplateFile $TemplateFile `
        -TemplateParameterFile $TemplateParameterFile `
        -Verbose

    if ($deployment.ProvisioningState -ne 'Succeeded') {
        Write-Host "`n[FAILED] Deployment failed with state: $($deployment.ProvisioningState)" -ForegroundColor Red
        exit 1
    }

    Write-Host "`n[OK] Deployment completed successfully!" -ForegroundColor Green
}
catch {
    Write-Host "`n[ERROR] Deployment failed: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
