<#
.SYNOPSIS
    Deploys Lab 2.2 security resources using Bicep templates.

.DESCRIPTION
    This script acts as the orchestrator for deploying the SkyCraft Lab 2.2 security resources.
    It calls the `main.bicep` template to deploy:
    - Application Security Groups (ASGs)
    - Network Security Groups (NSGs) with secure rules
    - Azure Bastion (Optional, with interactive prompt)
    
    It enforces project standards including proper tagging.

.PARAMETER Location
    The Azure region deployment target. Default: 'swedencentral'

.PARAMETER ProdResourceGroup
    The production resource group name. Default: 'prod-skycraft-swc-rg'

.PARAMETER PlatformResourceGroup
    The platform resource group name. Default: 'platform-skycraft-swc-rg'

.PARAMETER WhatIf
    Previews the deployment with the ARM what-if API and exits. Nothing is created or changed.
    The Bastion prompt is skipped in this mode and the preview is built with Bastion off -
    the same answer an unattended cycle gives, and the one that costs nothing.

.EXAMPLE
    .\Deploy-Bicep.ps1
    Deploys to default resource groups in Sweden Central.

.EXAMPLE
    .\Deploy-Bicep.ps1 -WhatIf
    Previews the ASG/NSG deployment (Bastion off) without changing anything.

.NOTES
    Project: SkyCraft
    Lab: 2.2 - Secure Access
    Author: Ops Team
    Date: 2026-01-03
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
    [string]$ProdResourceGroup = 'prod-skycraft-swc-rg',

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$PlatformResourceGroup = 'platform-skycraft-swc-rg',

    [Parameter(Mandatory = $false)]
    [switch]$WhatIf
)

$ErrorActionPreference = 'Stop'

Write-Host "=== Lab 2.2 - Deploy Security Configuration ===" -ForegroundColor Cyan -BackgroundColor Black

# Verify Azure Connection
$context = Get-AzContext
if (-not $context) {
    Write-Host "Not logged in. Please run Connect-AzAccount" -ForegroundColor Red
    $Host.SetShouldExit(1)
    exit 1
}
Write-Host "Connected to: $($context.Subscription.Name)" -ForegroundColor Green

# Define paths
$bicepPath = Join-Path $PSScriptRoot "..\bicep"
$mainBicep = Join-Path $bicepPath "main.bicep"

# Verify Bicep file exists
if (-not (Test-Path $mainBicep)) {
    Write-Host "[ERROR] Bicep file not found: $mainBicep" -ForegroundColor Red
    $Host.SetShouldExit(1)
    exit 1
}

Write-Host "`nDeploying Lab 2.2 resources..." -ForegroundColor Cyan

# Ask user about Bastion deployment. A what-if run answers the prompt for the caller:
# it changes nothing, so blocking a preview on stdin would only break non-interactive
# callers, and 'no' is the answer that keeps the ~$140/month meter off.
if ($WhatIf) {
    Write-Host "`n[OPTIONAL] Azure Bastion prompt skipped in what-if mode - previewing with Bastion off." -ForegroundColor Gray
    $shouldDeployBastion = $false
}
else {
    Write-Host "`n[OPTIONAL] Azure Bastion provides secure RDP/SSH access without public IPs." -ForegroundColor Yellow
    Write-Host "Cost: ~$140/month | Deployment time: ~15 minutes" -ForegroundColor Gray
    $deployBastion = Read-Host "Do you want to deploy Azure Bastion? (y/N)"

    $shouldDeployBastion = ($deployBastion -eq 'y' -or $deployBastion -eq 'Y')
}

if ($shouldDeployBastion) {
    Write-Host "  -> Bastion will be deployed" -ForegroundColor Green
}
else {
    Write-Host "  -> Bastion deployment skipped" -ForegroundColor Gray
}

try {
    $deploymentName = "Lab-2.2-Secure-access"
    
    $params = @{
        parLocation                  = $Location
        parResourceGroupNameProd     = $ProdResourceGroup
        parResourceGroupNamePlatform = $PlatformResourceGroup
        parDeployBastion             = $shouldDeployBastion
    }

    $deployParams = @{
        Name                    = $deploymentName
        Location                = $Location
        TemplateFile            = $mainBicep
        TemplateParameterObject = $params
        ErrorAction             = 'Stop'
    }

    if ($WhatIf) {
        Write-Host "  Running in what-if mode (dry run)..." -ForegroundColor Cyan
        Get-AzSubscriptionDeploymentWhatIfResult @deployParams
        Write-Host "`n  What-if completed. Review the changes above - nothing was deployed." -ForegroundColor Cyan
        exit 0
    }

    $deployment = New-AzSubscriptionDeployment @deployParams -Verbose

    if ($deployment.ProvisioningState -eq 'Succeeded') {
        Write-Host "`n[SUCCESS] Deployment completed successfully!" -ForegroundColor Green
        Write-Host "`nDeployment Outputs:" -ForegroundColor Cyan
        $deployment.Outputs | Format-Table -AutoSize
    }
    else {
        Write-Host "`n[FAILED] Deployment failed with state: $($deployment.ProvisioningState)" -ForegroundColor Red
    }
}
catch {
    Write-Host "`n[ERROR] Deployment failed with exception:" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    $Host.SetShouldExit(1)
    exit 1
}
