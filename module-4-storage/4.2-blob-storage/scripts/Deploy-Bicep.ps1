<#
.SYNOPSIS
    Deploys Lab 4.2 Infrastructure (Blob Storage Implementation).

.DESCRIPTION
    Deploys the Bicep template for Lab 4.2, configuring production and development storage accounts.
    Updates existing accounts from Lab 4.1 with new features (containers, lifecycle, versioning).

.PARAMETER Location
    Azure region for deployment. Default: swedencentral

.PARAMETER WhatIf
    Previews the deployment with the ARM what-if API and exits. Nothing is created or changed.

.EXAMPLE
    .\Deploy-Bicep.ps1 -Location "swedencentral"

.EXAMPLE
    .\Deploy-Bicep.ps1 -WhatIf
    Previews the blob storage deployment without changing anything.

.NOTES
    Project: SkyCraft
    Author: SkyCraft
    Version: 1.0.0
#>

#Requires -Version 7.0
#Requires -Modules Az.Accounts, Az.Resources

[CmdletBinding()]
param(
    [ValidateSet('swedencentral', 'northeurope')]
    [string]$Location = 'swedencentral',

    [switch]$WhatIf
)

$ErrorActionPreference = 'Stop'
$ScriptPath = $PSScriptRoot
$TemplateFile = Join-Path $ScriptPath "../bicep/main.bicep"

Write-Host "=== Lab 4.2: Deploying Blob Storage Infrastructure ===" -ForegroundColor Cyan

# 1. Verify Login
$context = Get-AzContext
if (-not $context) {
    Write-Host "Not logged in. Please run Connect-AzAccount." -ForegroundColor Red; $Host.SetShouldExit(1); exit 1
}

# 2. Check Template Existence
if (-not (Test-Path $TemplateFile)) {
    Write-Host "Template file not found: $TemplateFile" -ForegroundColor Red; $Host.SetShouldExit(1); exit 1
}

# 3. Deploy
try {
    Write-Host "Deploying to Subscription scope..." -ForegroundColor Yellow
    
    $deployParams = @{
        Name                    = "lab-4.2-deploy-$(Get-Date -Format 'yyyyMMdd-HHmm')"
        Location                = $Location
        TemplateFile            = $TemplateFile
        TemplateParameterObject = @{ parLocation = $Location }
        ErrorAction             = 'Stop'
    }

    if ($WhatIf) {
        Write-Host "  Running in what-if mode (dry run)..." -ForegroundColor Cyan
        Get-AzSubscriptionDeploymentWhatIfResult @deployParams
        Write-Host "`n  What-if completed. Review the changes above - nothing was deployed." -ForegroundColor Cyan
        exit 0
    }

    $deployment = New-AzSubscriptionDeployment @deployParams -WarningAction SilentlyContinue

    if ($deployment.ProvisioningState -ne 'Succeeded') {
        Write-Host "[FAILED] Deployment failed with state: $($deployment.ProvisioningState)" -ForegroundColor Red
        $Host.SetShouldExit(1)
        exit 1
    }

    Write-Host "Deployment Successful!" -ForegroundColor Green
    
    # Output important info
    if ($deployment.Outputs) {
        Write-Host "`nDeployment Outputs:" -ForegroundColor Cyan
        $deployment.Outputs.Keys | ForEach-Object {
            Write-Host "  $_ : $($deployment.Outputs[$_].Value)"
        }
    }
}
catch {
    Write-Host "Deployment Failed!" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    $Host.SetShouldExit(1)
    exit 1
}
