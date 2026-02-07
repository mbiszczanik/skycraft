<#
.SYNOPSIS
    Deploys Lab 4.1 - Storage Accounts infrastructure using Bicep.

.DESCRIPTION
    Deploys storage accounts for SkyCraft environments with environment-specific
    redundancy (LRS/GRS/GZRS). Supports single or all environment deployment.
    Auto-detects existing storage accounts to use appropriate encryption settings.

.PARAMETER Environment
    Target environment: dev, prod, or platform. Ignored if -All is specified.

.PARAMETER All
    Deploy to all environments (platform, dev, prod) simultaneously.

.PARAMETER Location
    Azure region for deployment. Defaults to swedencentral.

.PARAMETER NewDeployment
    Force full encryption settings (keyType, infrastructureEncryption).
    Auto-detected if not specified. Will be overridden to false if accounts exist.

.PARAMETER InfraEncryption
    Enable infrastructure (double) encryption. Only applies to new deployments.
    Cannot be changed after storage account creation.

.PARAMETER WhatIf
    Preview changes without deploying.

.EXAMPLE
    .\Deploy-Bicep.ps1 -Environment dev
    Deploys storage account to development environment.

.EXAMPLE
    .\Deploy-Bicep.ps1 -All
    Deploys storage accounts to all environments.

.EXAMPLE
    .\Deploy-Bicep.ps1 -Environment prod -WhatIf
    Previews production deployment without making changes.

.EXAMPLE
    .\Deploy-Bicep.ps1 -Environment prod -NewDeployment -InfraEncryption
    Creates new production storage with infrastructure (double) encryption.

.NOTES
    Project: SkyCraft
    Lab: 4.1 - Storage Accounts
    Version: 1.1.0
    Date: 2026-02-05
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory = $false)]
    [ValidateSet('dev', 'prod', 'platform')]
    [string]$Environment = 'dev',

    [Parameter(Mandatory = $false)]
    [switch]$All,

    [Parameter(Mandatory = $false)]
    [string]$Location = 'swedencentral',

    [Parameter(Mandatory = $false)]
    [switch]$NewDeployment,

    [Parameter(Mandatory = $false)]
    [switch]$InfraEncryption
)

$ErrorActionPreference = 'Stop'

Write-Host "=== Lab 4.1: Deploy Storage Accounts ===" -ForegroundColor Cyan
Write-Host ""

# 1. Verify Azure Connection
Write-Host "--- Verifying Azure Connection ---" -ForegroundColor Yellow
$context = Get-AzContext
if (-not $context) {
    Write-Host "[ERROR] Not logged in to Azure. Please run Connect-AzAccount." -ForegroundColor Red
    exit 1
}
Write-Host "  -> Connected as: $($context.Account.Id)" -ForegroundColor Green
Write-Host "  -> Subscription: $($context.Subscription.Name)" -ForegroundColor Green

# 2. Verify Resource Groups Exist
Write-Host ""
Write-Host "--- Verifying Resource Groups ---" -ForegroundColor Yellow

$requiredRGs = if ($All) {
    @('platform-skycraft-swc-rg', 'dev-skycraft-swc-rg', 'prod-skycraft-swc-rg')
}
else {
    @("$Environment-skycraft-swc-rg")
}

foreach ($rg in $requiredRGs) {
    $rgExists = Get-AzResourceGroup -Name $rg -ErrorAction SilentlyContinue
    if (-not $rgExists) {
        Write-Host "[ERROR] Resource group '$rg' does not exist." -ForegroundColor Red
        Write-Host "  Create it first or complete Module 1 prerequisites." -ForegroundColor Yellow
        exit 1
    }
    Write-Host "  [OK] Resource group exists: $rg" -ForegroundColor Green
}

# 3. Auto-detect if storage accounts exist (to determine new vs update)
Write-Host ""
Write-Host "--- Checking Existing Resources ---" -ForegroundColor Yellow

$storageAccounts = if ($All) {
    @(
        @{ Name = 'platformskycraftswcsa'; RG = 'platform-skycraft-swc-rg' },
        @{ Name = 'devskycraftswcsa'; RG = 'dev-skycraft-swc-rg' },
        @{ Name = 'prodskycraftswcsa'; RG = 'prod-skycraft-swc-rg' }
    )
}
else {
    @(@{ Name = "${Environment}skycraftswcsa"; RG = "$Environment-skycraft-swc-rg" })
}

$isNewDeployment = $NewDeployment.IsPresent
$existingAccounts = @()

foreach ($sa in $storageAccounts) {
    $existing = Get-AzStorageAccount -ResourceGroupName $sa.RG -Name $sa.Name -ErrorAction SilentlyContinue
    if ($existing) {
        $existingAccounts += $sa.Name
        Write-Host "  [EXISTS] $($sa.Name)" -ForegroundColor Gray
    }
    else {
        Write-Host "  [NEW] $($sa.Name) will be created" -ForegroundColor Yellow
        if (-not $NewDeployment.IsPresent) {
            $isNewDeployment = $true
        }
    }
}

if ($existingAccounts.Count -gt 0 -and $NewDeployment.IsPresent) {
    Write-Host ""
    Write-Host "[WARNING] -NewDeployment specified but accounts exist. Using UPDATE mode to avoid errors." -ForegroundColor Yellow
    $isNewDeployment = $false
}

# 4. Set Deployment Parameters
Write-Host ""
Write-Host "--- Deployment Configuration ---" -ForegroundColor Yellow

$templateFile = Join-Path $PSScriptRoot "..\bicep\main.bicep"
$deploymentName = "lab41-storage-$(Get-Date -Format 'yyyyMMddHHmmss')"

$deploymentParams = @{
    parLocation                       = $Location
    parDeployAllEnvironments          = $All.IsPresent
    parEnvironment                    = $Environment
    parEnableBlobSoftDelete           = $true
    parBlobSoftDeleteDays             = 7
    parEnableContainerSoftDelete      = $true
    parEnableFileSoftDelete           = $true
    parIsNewDeployment                = $isNewDeployment
    parEnableInfrastructureEncryption = $InfraEncryption.IsPresent
}

Write-Host "  Template: $templateFile"
Write-Host "  Location: $Location"
Write-Host "  Environment(s): $(if ($All) { 'ALL (platform, dev, prod)' } else { $Environment })"
Write-Host "  Deployment Mode: $(if ($isNewDeployment) { 'NEW (full encryption settings)' } else { 'UPDATE (compatible settings)' })"
Write-Host "  Infrastructure Encryption: $(if ($InfraEncryption) { 'Enabled' } else { 'Disabled' })"
Write-Host "  Soft Delete: Enabled (7 days)"

# 4. Deploy
Write-Host ""
Write-Host "--- Deploying Bicep Template ---" -ForegroundColor Yellow

try {
    if ($PSCmdlet.ShouldProcess("Storage accounts", "Deploy")) {
        $deployment = New-AzSubscriptionDeployment `
            -Name $deploymentName `
            -Location $Location `
            -TemplateFile $templateFile `
            -TemplateParameterObject $deploymentParams `
            -ErrorAction Stop

        Write-Host ""
        Write-Host "=== Deployment Complete ===" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "--- Deployment Outputs ---" -ForegroundColor Yellow
        
        if ($deployment.Outputs.outDeployedEnvironments) {
            $envs = $deployment.Outputs.outDeployedEnvironments.Value
            Write-Host "  Deployed Environments: $($envs -join ', ')" -ForegroundColor Green
        }

        if ($All -or $Environment -eq 'platform') {
            if ($deployment.Outputs.outPlatformStorageAccountName.Value -ne 'not-deployed') {
                Write-Host "  Platform Storage: $($deployment.Outputs.outPlatformStorageAccountName.Value)" -ForegroundColor Green
            }
        }
        
        if ($All -or $Environment -eq 'dev') {
            if ($deployment.Outputs.outDevStorageAccountName.Value -ne 'not-deployed') {
                Write-Host "  Dev Storage: $($deployment.Outputs.outDevStorageAccountName.Value)" -ForegroundColor Green
            }
        }
        
        if ($All -or $Environment -eq 'prod') {
            if ($deployment.Outputs.outProdStorageAccountName.Value -ne 'not-deployed') {
                Write-Host "  Prod Storage: $($deployment.Outputs.outProdStorageAccountName.Value)" -ForegroundColor Green
            }
        }

        Write-Host ""
        Write-Host "Deployment Name: $deploymentName" -ForegroundColor Gray
        Write-Host "Provisioning State: $($deployment.ProvisioningState)" -ForegroundColor Green
    }
}
catch {
    Write-Host ""
    Write-Host "[ERROR] Deployment failed!" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    
    # Show detailed error if available
    if ($_.Exception.InnerException) {
        Write-Host ""
        Write-Host "Details: $($_.Exception.InnerException.Message)" -ForegroundColor Red
    }
    
    exit 1
}

Write-Host ""
Write-Host "=== Next Steps ===" -ForegroundColor Cyan
Write-Host "1. Run .\scripts\Test-Lab.ps1 to validate deployment" -ForegroundColor White
Write-Host "2. Proceed to Lab 4.2: Blob Storage" -ForegroundColor White
