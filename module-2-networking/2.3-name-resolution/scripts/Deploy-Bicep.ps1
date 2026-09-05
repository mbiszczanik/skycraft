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

.PARAMETER WhatIf
    Previews the deployment with the ARM what-if API and exits. Nothing is created or changed.

.EXAMPLE
    .\Deploy-Bicep.ps1
    Deploys the default main.bicep to Sweden Central using the current Az context.

.EXAMPLE
    .\Deploy-Bicep.ps1 -WhatIf
    Previews the DNS and load balancer deployment without changing anything.

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

    # Anchored to $PSScriptRoot, not the current directory - the bare relative default made this
    # the only script in the repository that had to be run from its own scripts/ folder (#75).
    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$TemplateFile = (Join-Path $PSScriptRoot '..\bicep\main.bicep'),

    [Parameter(Mandatory = $false)]
    [switch]$WhatIf
)

$ErrorActionPreference = 'Stop'

$deploymentName = "Lab-2.3-DNS-$(Get-Date -Format 'yyyyMMdd-HHmm')"

Write-Host "=== Lab 2.3 - Deploy Bicep (DNS) ===" -ForegroundColor Cyan -BackgroundColor Black

# Verify Bicep File
if (-not (Test-Path $TemplateFile)) {
    Write-Host "Error: Template file not found at $TemplateFile" -ForegroundColor Red
    $Host.SetShouldExit(1)
    exit 1
}

Write-Host "Starting deployment: $deploymentName..." -ForegroundColor Yellow

try {
    $deployParams = @{
        Name         = $deploymentName
        Location     = $Location
        TemplateFile = $TemplateFile
        ErrorAction  = 'Stop'
    }

    if ($WhatIf) {
        Write-Host "  Running in what-if mode (dry run)..." -ForegroundColor Cyan
        Get-AzSubscriptionDeploymentWhatIfResult @deployParams
        Write-Host "`n  What-if completed. Review the changes above - nothing was deployed." -ForegroundColor Cyan
        exit 0
    }

    $deployment = New-AzDeployment @deployParams -Verbose

    if ($deployment.ProvisioningState -ne 'Succeeded') {
        Write-Host "`n[FAILED] Deployment failed with state: $($deployment.ProvisioningState)" -ForegroundColor Red
        $Host.SetShouldExit(1)
        exit 1
    }

    Write-Host "`n[OK] Deployment completed successfully!" -ForegroundColor Green
}
catch {
    Write-Host "`n[ERROR] Deployment failed: $($_.Exception.Message)" -ForegroundColor Red
    $Host.SetShouldExit(1)
    exit 1
}
