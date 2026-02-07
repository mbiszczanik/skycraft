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

[CmdletBinding()]
param(
    [string]$Location = 'swedencentral'
)

$ErrorActionPreference = 'Stop'
$ScriptPath = $PSScriptRoot
$TemplateFile = Join-Path $ScriptPath "../bicep/main.bicep"

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
    
    $deployment = New-AzSubscriptionDeployment `
        -Name "lab-4.2-deploy-$(Get-Date -Format 'yyyyMMdd-HHmm')" `
        -Location $Location `
        -TemplateFile $TemplateFile `
        -WarningAction SilentlyContinue

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
