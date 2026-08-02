<#
.SYNOPSIS
    Deploys Lab 4.2 Infrastructure (Blob Storage Implementation).

.DESCRIPTION
    Deploys the Bicep template for Lab 4.2, configuring production and development storage accounts.
    Updates existing accounts from Lab 4.1 with new features (containers, lifecycle, versioning).

.PARAMETER Location
    Azure region for deployment. Default: swedencentral

.EXAMPLE
    .\Deploy-Bicep.ps1 -Location "swedencentral"

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

    [Parameter(Mandatory = $false)]
    [string]$TemplateParameterFile
)

$ErrorActionPreference = 'Stop'
$ScriptPath = $PSScriptRoot
$TemplateFile = Join-Path $ScriptPath "../bicep/main.bicep"

# Backward-compatible parameter-file resolution (non-environment lab).
if (-not $TemplateParameterFile) {
    $TemplateParameterFile = Join-Path $ScriptPath "../bicep/parameters/main.bicepparam"
}

Write-Host "=== Lab 4.2: Deploying Blob Storage Infrastructure ===" -ForegroundColor Cyan

# 1. Verify Login
$context = Get-AzContext
if (-not $context) {
    Write-Host "Not logged in. Please run Connect-AzAccount." -ForegroundColor Red; exit 1
}

# 2. Check Template Existence
if (-not (Test-Path $TemplateFile)) {
    Write-Host "Template file not found: $TemplateFile" -ForegroundColor Red; exit 1
}

# 3. Deploy
try {
    Write-Host "Deploying to Subscription scope..." -ForegroundColor Yellow
    
    # Compile the .bicepparam with the Azure CLI's own Bicep rather than handing the file to Az,
    # which resolves it by shelling out to a bare `bicep` on PATH that `az bicep install` does
    # not provide. This script computes nothing, so there is no overlay: the hashtable is the
    # parameter file and nothing more.
    $params = @{}
    $built = az bicep build-params --file $TemplateParameterFile --stdout | ConvertFrom-Json
    if ($LASTEXITCODE -ne 0 -or -not $built.parametersJson) {
        Write-Host "  -> [ERROR] Failed to compile parameter file: $TemplateParameterFile" -ForegroundColor Red
        exit 1
    }
    foreach ($p in ($built.parametersJson | ConvertFrom-Json -AsHashtable).parameters.GetEnumerator()) {
        $params[$p.Key] = $p.Value.value
    }

    $deployment = New-AzSubscriptionDeployment `
        -Name "lab-4.2-deploy-$(Get-Date -Format 'yyyyMMdd-HHmm')" `
        -Location $Location `
        -TemplateFile $TemplateFile `
        -TemplateParameterObject $params `
        -WarningAction SilentlyContinue

    if ($deployment.ProvisioningState -ne 'Succeeded') {
        Write-Host "[FAILED] Deployment failed with state: $($deployment.ProvisioningState)" -ForegroundColor Red
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
    exit 1
}
