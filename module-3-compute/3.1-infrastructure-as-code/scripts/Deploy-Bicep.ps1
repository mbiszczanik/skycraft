<#
.SYNOPSIS
    Deploys Lab 3.1 Infrastructure Resources (Bicep).

.DESCRIPTION
    This script orchestrates the deployment of SkyCraft infrastructure (VNets, NSGs, LBs).
    It handles SSH Key generation and passes it to the Bicep template.

.PARAMETER Location
    The Azure region deployment target. Default: 'swedencentral'

.PARAMETER Environment
    Target environment (dev, prod). Default: 'dev'

.PARAMETER WhatIf
    If specified, runs What-If analysis instead of deploying.

.EXAMPLE
    .\Deploy-Infra.ps1 -Environment dev
    Deploys the Development environment.

.NOTES
    Project: SkyCraft
    Lab: 3.1 - Infrastructure as Code
    Date: 2026-01-12
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$Location = 'swedencentral',

    [Parameter(Mandatory = $false)]
    [ValidateSet('dev', 'prod')]
    [string]$Environment = 'dev',

    [Parameter(Mandatory = $false)]
    [switch]$WhatIf
)

Write-Host "=== Lab 3.1 - Deploy Infrastructure ($Environment) ===" -ForegroundColor Cyan

# 1. Verify Azure Connection
$context = Get-AzContext
if (-not $context) {
    Write-Host "Not logged in. Please run Connect-AzAccount" -ForegroundColor Red
    exit 1
}
Write-Host "Connected to: $($context.Subscription.Name)" -ForegroundColor Green

# 2. Handle SSH Key - REMOVED per requirements
# SSH Key logic removed as it is not needed for Lab 3.1 infrastructure-only deployment.

# 3. Deploy Bicep
$bicepPath = Join-Path $PSScriptRoot "..\bicep\main.bicep"
$paramPath = Join-Path $PSScriptRoot "..\bicep\parameters\$Environment.bicepparam"

if (-not (Test-Path $bicepPath)) { Write-Host "Bicep file missing: $bicepPath" -ForegroundColor Red; exit 1 }

$deploymentName = "SkyCraft-$Environment-$(Get-Date -Format 'yyyyMMdd-HHmm')"

Write-Host "`nStarting Deployment: $deploymentName" -ForegroundColor Cyan
Write-Host "Template: $bicepPath" -ForegroundColor Gray
Write-Host "Params:   $paramPath" -ForegroundColor Gray

try {
    # Override sshPublicKey in parameter file
    # Note: .bicepparam files typically shouldn't be modified on fly, but for labs we pass key dynamically
    # Since 'using' param files, we can pass --parameters twice: once for file, once for override
    
    $commonArgs = @{
        Name                  = $deploymentName
        Location              = $Location
        TemplateFile          = $bicepPath
        TemplateParameterFile = $paramPath
    }

    if ($WhatIf) {
        Write-Host "Running What-If Analysis..." -ForegroundColor Yellow
        New-AzSubscriptionDeployment @commonArgs -WhatIf
    }
    else {
        Write-Host "Deploying..." -ForegroundColor Yellow
        $dep = New-AzSubscriptionDeployment @commonArgs
        
        if ($dep.ProvisioningState -eq 'Succeeded') {
            Write-Host "`n[SUCCESS] Deployment complete!" -ForegroundColor Green
            $dep.Outputs | Format-Table -AutoSize
        }
        else {
            Write-Host "`n[FAILED] State: $($dep.ProvisioningState)" -ForegroundColor Red
        }
    }
}
catch {
    Write-Host "`n[ERROR] Deployment failed!" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    exit 1
}
