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

.PARAMETER AppName
    The web app name. Default: '<Environment>-skycraft-swc-app01'. Web app names are unique per
    region across Azure, so override this on a collision, and pass the same name to Test-Lab.ps1
    and Remove-LabResource.ps1.

.PARAMETER WhatIf
    Previews the deployment with the ARM what-if API and exits. Nothing is created or changed.

.EXAMPLE
    .\Deploy-Bicep.ps1 -Environment dev

.EXAMPLE
    .\Deploy-Bicep.ps1 -AppName dev-skycraft-swc-app01-ab
    Deploys the web app under a name of your own, when the default is taken.

.EXAMPLE
    .\Deploy-Bicep.ps1 -Environment dev -WhatIf
    Previews the App Service deployment without changing anything.

.NOTES
    Project: SkyCraft
    Date: 2026-01-31
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

    # The default reads $Environment, so it must be declared first.
    [Parameter(Mandatory = $false)]
    [ValidatePattern('^[a-zA-Z0-9][a-zA-Z0-9-]{0,58}[a-zA-Z0-9]$')]
    [string]$AppName = "$Environment-skycraft-swc-app01",

    [Parameter(Mandatory = $false)]
    [switch]$WhatIf
)

$ErrorActionPreference = 'Stop'
# Exit-Lab ends the script with exit code 0 or 1 and leaves an interactive session open (#257).
Import-Module (Join-Path $PSScriptRoot '../../../tools/LabCommon.psm1') -Force -Verbose:$false

$BicepFile = Join-Path $PSScriptRoot "..\bicep\main.bicep"
$DeploymentName = "deploy-lab3.4-$Environment"

Write-Host "=== Lab 3.4 Deployment: App Service ($Environment) ===" -ForegroundColor Cyan

# 1. Verify Connection
$context = Get-AzContext
if (-not $context) {
    Write-Host "Not logged in. Please run Connect-AzAccount." -ForegroundColor Red; Exit-Lab -FailureCount 1
}
$ResourceGroupName = "$Environment-skycraft-swc-rg"
Write-Host "  Web app: $AppName" -ForegroundColor Gray

# 2. A taken app name otherwise fails the deployment after the plan is created (#438).
$appOwned = [bool](Get-AzResource -ResourceGroupName $ResourceGroupName -ResourceType 'Microsoft.Web/sites' -Name $AppName -ErrorAction SilentlyContinue)
if (-not (Test-LabGlobalName -Kind WebApp -Name $AppName -ParameterName 'AppName' -Owned $appOwned -Location $Location)) {
    Exit-Lab -FailureCount 1
}

# 3. Deploy Bicep
try {
    Write-Host "Starting Bicep deployment from: $BicepFile" -ForegroundColor Yellow
    
    $params = @{
        parLocation          = $Location
        parEnvironment       = $Environment
        parResourceGroupName = $ResourceGroupName
        parVnetName          = "$Environment-skycraft-swc-vnet"
        parAppName           = $AppName
    }

    $deployParams = @{
        Name                    = $DeploymentName
        Location                = $Location
        TemplateFile            = $BicepFile
        TemplateParameterObject = $params
        ErrorAction             = 'Stop'
    }

    if ($WhatIf) {
        Write-Host "  Running in what-if mode (dry run)..." -ForegroundColor Cyan
        Get-AzSubscriptionDeploymentWhatIfResult @deployParams
        Write-Host "`n  What-if completed. Review the changes above - nothing was deployed." -ForegroundColor Cyan
        Exit-Lab -FailureCount 0
    }

    $deployment = New-AzSubscriptionDeployment @deployParams

    if ($deployment.ProvisioningState -ne 'Succeeded') {
        Write-Host "[FAILED] Deployment failed with state: $($deployment.ProvisioningState)" -ForegroundColor Red
        Exit-Lab -FailureCount 1
    }

    Write-Host "Deployment '$DeploymentName' completed successfully." -ForegroundColor Green
}
catch {
    Write-Host "Deployment failed!" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    Exit-Lab -FailureCount 1
}
Exit-Lab -FailureCount 0
