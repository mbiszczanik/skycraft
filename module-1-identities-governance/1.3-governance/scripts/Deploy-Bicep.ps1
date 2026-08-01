<#
.SYNOPSIS
    Deploys Lab 1.3 Governance (Tags, Policies, Locks) using Bicep.

.DESCRIPTION
    This script orchestrates the deployment of governance controls for SkyCraft Lab 1.3
    by invoking the main.bicep orchestrator.

.PARAMETER Location
    Azure region for deployment. Default: swedencentral.

.PARAMETER AdminEmail
    Email address for the Owner tag. Default: admin@skycraft.com.

.PARAMETER TemplateParameterFile
    Bicep parameter file whose values are merged before the runtime overrides
    (-Location, -AdminEmail). Defaults to bicep/parameters/main.bicepparam.

.EXAMPLE
    .\Deploy-Bicep.ps1 -AdminEmail "malfurion@azureflame.onmicrosoft.com"

.NOTES
    Project: SkyCraft
    Lab: 1.3 - Governance
#>

#Requires -Version 7.0
#Requires -Modules Az.Accounts, Az.Resources

[CmdletBinding()]
param(
    [ValidateSet('swedencentral', 'northeurope')]
    [string]$Location = 'swedencentral',

    [ValidateNotNullOrEmpty()]
    [string]$AdminEmail = 'admin@skycraft.com',

    [Parameter(Mandatory = $false)]
    [string]$TemplateParameterFile
)

$ErrorActionPreference = 'Stop'

if (-not $TemplateParameterFile) {
    $TemplateParameterFile = Join-Path $PSScriptRoot '..\bicep\parameters\main.bicepparam'
}

Write-Host "=== Lab 1.3: Governance Deployment ===" -ForegroundColor Cyan -BackgroundColor Black

# 1. Verify Connection. Authentication is the caller's responsibility: connecting from here
# would block forever inside a non-interactive child process.
$context = Get-AzContext
if (-not $context) {
    Write-Host "  -> [ERROR] Not logged in to Azure. Run Connect-AzAccount first." -ForegroundColor Red
    exit 1
}
Write-Host "Connected to: $($context.Subscription.Name) ($($context.Subscription.Id))" -ForegroundColor Green

# 2. Deployment
$templateFile = Join-Path $PSScriptRoot "..\bicep\main.bicep"
if (-not (Test-Path $templateFile)) {
    Write-Host "  -> [ERROR] Template file not found at: $templateFile" -ForegroundColor Red
    exit 1
}

if (-not (Test-Path $TemplateParameterFile)) {
    Write-Host "  -> [ERROR] Parameter file not found at: $TemplateParameterFile" -ForegroundColor Red
    exit 1
}

$deploymentName = "Lab-1.3-Gov-$(Get-Date -Format 'yyyyMMdd-HHmm')"

Write-Host "`nStarting Bicep Deployment..." -ForegroundColor Cyan
Write-Host "  Template: $templateFile" -ForegroundColor Gray
Write-Host "  Parameters: $TemplateParameterFile" -ForegroundColor Gray
Write-Host "  Location: $Location" -ForegroundColor Gray
Write-Host "  AdminEmail: $AdminEmail" -ForegroundColor Gray

try {
    # Static values from the .bicepparam file...
    $params = @{}
    $built = az bicep build-params --file $TemplateParameterFile --stdout | ConvertFrom-Json
    if ($LASTEXITCODE -ne 0 -or -not $built.parametersJson) {
        Write-Host "  -> [ERROR] Failed to compile parameter file: $TemplateParameterFile" -ForegroundColor Red
        exit 1
    }
    foreach ($p in ($built.parametersJson | ConvertFrom-Json -AsHashtable).parameters.GetEnumerator()) {
        $params[$p.Key] = $p.Value.value
    }

    # ...then runtime overrides win (reproduces the previous no-argument behaviour).
    $params.parLocation = $Location
    $params.parAdminEmail = $AdminEmail

    $deployment = New-AzSubscriptionDeployment `
        -Name $deploymentName `
        -Location $Location `
        -TemplateFile $templateFile `
        -TemplateParameterObject $params `
        -Verbose

    if ($deployment.ProvisioningState -eq 'Succeeded') {
        Write-Host "  -> [SUCCESS] Governance deployment completed." -ForegroundColor Green
        Write-Host "`nDeployment Outputs:" -ForegroundColor Cyan
        $deployment.Outputs | Format-Table -AutoSize
    } else {
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
    Write-Host "  -> [ERROR] Deployment failed: $_" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    exit 1
}

Write-Host "`nDeployment Complete." -ForegroundColor Green
Write-Host "Next Steps:" -ForegroundColor Gray
Write-Host " 1. Run Test-Lab-1.3.ps1 to validate." -ForegroundColor Gray
