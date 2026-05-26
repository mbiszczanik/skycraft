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

.EXAMPLE
    .\Deploy-Bicep.ps1
    Deploys the default main.bicep to Sweden Central using the current Az context.

.NOTES
    Project: SkyCraft
    Lab: 2.3 - Name Resolution & Load Balancing
    Author: Marcin Biszczanik
    Date: 2026-01-11
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$Location = 'swedencentral',

    [Parameter(Mandatory = $false)]
    [string]$TemplateFile = '..\bicep\main.bicep'
)

$deploymentName = "Lab-2.3-DNS-$(Get-Date -Format 'yyyyMMdd-HHmm')"

Write-Host "=== Lab 2.3 - Deploy Bicep (DNS) ===" -ForegroundColor Cyan -BackgroundColor Black

# Verify Bicep File
if (-not (Test-Path $TemplateFile)) {
    Write-Host "Error: Template file not found at $TemplateFile" -ForegroundColor Red
    exit 1
}

Write-Host "Starting deployment: $deploymentName..." -ForegroundColor Yellow

try {
    New-AzDeployment `
        -Name $deploymentName `
        -Location $Location `
        -TemplateFile $TemplateFile `
        -Verbose
    
    Write-Host "`n[OK] Deployment completed successfully!" -ForegroundColor Green
}
catch {
    Write-Host "`n[ERROR] Deployment failed: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
