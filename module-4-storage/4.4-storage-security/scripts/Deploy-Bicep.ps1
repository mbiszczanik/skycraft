<#
.SYNOPSIS
    Deploys Lab 4.4 Storage Security
.DESCRIPTION
    Deploys storage firewall rules, VNet integration, and dev-assets container.
    Requires existing storage account (Lab 4.1) and VNet (Lab 2.1).
.PARAMETER Location
    Azure region for deployment. Default: swedencentral.
.PARAMETER Environment
    Target environment (prod, dev, platform). Default: prod.
.PARAMETER ClientIp
    Your client IP to allow through the firewall. Auto-detected if omitted.
.EXAMPLE
    .\Deploy-Bicep.ps1 -Environment prod
.NOTES
    Project: SkyCraft
    Author: SkyCraft
    Date: 2026-02-21
#>

#Requires -Version 7.0
#Requires -Modules Az.Accounts, Az.Resources

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [ValidateSet('swedencentral', 'northeurope')]
    [string]$Location = 'swedencentral',

    [Parameter(Mandatory = $false)]
    [ValidateSet('prod', 'dev', 'platform')]
    [string]$Environment = 'prod',

    [Parameter(Mandatory = $false)]
    [string]$ClientIp = '',

    [Parameter(Mandatory = $false)]
    [string]$TemplateParameterFile
)

$ErrorActionPreference = 'Stop'

Write-Host "=== Lab 4.4: Deploying Storage Security ===" -ForegroundColor Cyan

# 1. Verify Connection
$context = Get-AzContext
if (-not $context) {
    Write-Host " [ERROR] Not logged in. Please run Connect-AzAccount." -ForegroundColor Red; exit 1
}

# 2. Auto-detect client IP if not provided
if ([string]::IsNullOrWhiteSpace($ClientIp)) {
    try {
        Write-Host "Auto-detecting client IP..." -ForegroundColor Yellow
        $ClientIp = (Invoke-RestMethod -Uri 'https://api.ipify.org' -TimeoutSec 5).Trim()
        Write-Host "  -> Detected: $ClientIp" -ForegroundColor Green
    }
    catch {
        Write-Host "  -> [WARNING] Could not auto-detect IP. Firewall will not include client IP rule." -ForegroundColor Yellow
        $ClientIp = ''
    }
}

# 3. Resolve parameter file (backward-compatible) and hydrate parameters.
if (-not $TemplateParameterFile) {
    $TemplateParameterFile = Join-Path $PSScriptRoot "..\bicep\parameters\$Environment.bicepparam"
}

$deploymentParams = @{}
$built = az bicep build-params --file $TemplateParameterFile --stdout | ConvertFrom-Json
if ($LASTEXITCODE -ne 0 -or -not $built.parametersJson) {
    Write-Host "  -> [ERROR] Failed to compile parameter file: $TemplateParameterFile" -ForegroundColor Red
    exit 1
}
foreach ($p in ($built.parametersJson | ConvertFrom-Json -AsHashtable).parameters.GetEnumerator()) {
    $deploymentParams[$p.Key] = $p.Value.value
}

# Overlay the exact values this script has always set. parClientIp is a runtime
# override (auto-detected above) and is never stored in the parameter file.
$deploymentParams.parLocation = $Location
$deploymentParams.parEnvironment = $Environment
$deploymentParams.parClientIp = $ClientIp

# 4. Deploy Bicep
try {
    Write-Host "Deploying main.bicep to subscription level..." -ForegroundColor Yellow

    $deployment = New-AzSubscriptionDeployment `
        -Name "lab-4.4-deploy-$(Get-Date -Format 'yyyyMMdd-HHmm')" `
        -Location $Location `
        -TemplateFile (Join-Path $PSScriptRoot "..\bicep\main.bicep") `
        -TemplateParameterObject $deploymentParams `
        -ErrorAction Stop

    if ($deployment.ProvisioningState -ne 'Succeeded') {
        Write-Host "`n [FAILED] Deployment failed with state: $($deployment.ProvisioningState)" -ForegroundColor Red
        exit 1
    }

    Write-Host "`nSuccessfully deployed Lab 4.4 security configuration!" -ForegroundColor Green
    Write-Host "  -> Storage Account: $($deployment.Outputs.outStorageAccountId.Value)" -ForegroundColor Green
    Write-Host "  -> Container:       $($deployment.Outputs.outContainerName.Value)" -ForegroundColor Green
    Write-Host "  -> Firewall:        $($deployment.Outputs.outFirewallDefaultAction.Value)" -ForegroundColor Green
}
catch {
    Write-Host "`n [ERROR] Deployment failed!" -ForegroundColor Red
    Write-Host "  -> Cause: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
