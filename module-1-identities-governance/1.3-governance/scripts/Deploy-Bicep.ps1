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

.EXAMPLE
    .\Deploy-Bicep.ps1 -AdminEmail "malfurion@azureflame.onmicrosoft.com"

.NOTES
    Project: SkyCraft
    Lab: 1.3 - Governance
#>

[CmdletBinding()]
param(
    [string]$Location = 'swedencentral',
    [string]$AdminEmail = 'admin@skycraft.com'
)

$ErrorActionPreference = 'Stop'

Write-Host "=== Lab 1.3: Governance Deployment ===" -ForegroundColor Cyan -BackgroundColor Black

# 1. Verify Connection
try {
    $context = Get-AzContext
    if (-not $context) {
        Write-Host "Checking Azure connection..." -ForegroundColor Yellow
        $context = Connect-AzAccount -ErrorAction Stop
    }
    Write-Host "Connected to: $($context.Subscription.Name) ($($context.Subscription.Id))" -ForegroundColor Green
}
catch {
    Write-Host "  -> [ERROR] Failed to connect to Azure: $_" -ForegroundColor Red
    exit 1
}

# 2. Deployment
$templateFile = Join-Path $PSScriptRoot "..\bicep\main.bicep"
if (-not (Test-Path $templateFile)) {
    Write-Host "  -> [ERROR] Template file not found at: $templateFile" -ForegroundColor Red
    exit 1
}

$deploymentName = "Lab-1.3-Gov-$(Get-Date -Format 'yyyyMMdd-HHmm')"

Write-Host "`nStarting Bicep Deployment..." -ForegroundColor Cyan
Write-Host "  Template: $templateFile" -ForegroundColor Gray
Write-Host "  Location: $Location" -ForegroundColor Gray
Write-Host "  AdminEmail: $AdminEmail" -ForegroundColor Gray

try {
    $params = @{
        parLocation   = $Location
        parAdminEmail = $AdminEmail
    }

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