<#
.SYNOPSIS
    Deploys Lab 3.3 Container resources using Bicep templates.

.DESCRIPTION
    This script orchestrates the deployment of SkyCraft Lab 3.3 (Containers).
    
    CRITICAL WORKFLOW:
    1. Bootstraps Azure Container Registry (ACR) first (if not exists).
    2. Builds the required container image (skycraft-auth:v1) using ACR Tasks.
    3. Executes the main.bicep orchestrator to deploy ACI and ACA.
    
    This multi-step process is required because ACI/ACA depend on the image existing
    in the registry before they can be successfully provisioned.

.PARAMETER Location
    The Azure region deployment target. Default: 'swedencentral'

.PARAMETER ResourceGroupName
    The resource group name. Default: 'dev-skycraft-swc-rg'

.PARAMETER Environment
    The environment tag. Default: 'dev'

.EXAMPLE
    .\Deploy-Bicep.ps1
    Deploys to default resource groups.

.NOTES
    Project: SkyCraft
    Lab: 3.3 - Containers
    Author: Antigravity
    Date: 2026-01-31
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$Location = 'swedencentral',

    [Parameter(Mandatory = $false)]
    [string]$ResourceGroupName = 'dev-skycraft-swc-rg',

    [Parameter(Mandatory = $false)]
    [string]$Environment = 'dev'
)

Write-Host "=== Lab 3.3 - Deploy Bicep Configuration ===" -ForegroundColor Cyan -BackgroundColor Black

# Verify Azure Connection
$context = Get-AzContext
if (-not $context) {
    Write-Host "Not logged in. Please run Connect-AzAccount" -ForegroundColor Red
    exit 1
}
Write-Host "Connected to: $($context.Subscription.Name)" -ForegroundColor Green

# Define paths
$bicepPath = Join-Path $PSScriptRoot "..\bicep"
$mainBicep = Join-Path $bicepPath "main.bicep"
$acrBicep = Join-Path $bicepPath "modules\acr.bicep"
$deploymentName = "Lab-3.3-Containers"

if (-not (Test-Path $mainBicep)) {
    Write-Host "[ERROR] Bicep file not found: $mainBicep" -ForegroundColor Red
    exit 1
}

# Ensure RG exists (needed for module deployment / bootstrapping)
try {
    if (-not (Get-AzResourceGroup -Name $ResourceGroupName -ErrorAction SilentlyContinue)) {
        Write-Host "Creating Resource Group: $ResourceGroupName..." -ForegroundColor Yellow
        New-AzResourceGroup -Name $ResourceGroupName -Location $Location -Tag @{ Project = 'SkyCraft' } -ErrorAction Stop | Out-Null
    }
} catch {
    Write-Host "[ERROR] Failed to create Resource Group: $_" -ForegroundColor Red
    exit 1
}

# ==============================================================================
# PHASE 1: BOOTSTRAP ACR & IMAGE
# ==============================================================================
Write-Host "`n=== Phase 1: Bootstrapping Prerequisites ===" -ForegroundColor Cyan
$acrName = "devskycraftswcacr01" # Should match main.bicep default or param

# Check if we need to bootstrap image
$repoExists = $false
$acrExists = Get-AzContainerRegistry -ResourceGroupName $ResourceGroupName -Name $acrName -ErrorAction SilentlyContinue
if ($acrExists) {
    # Check if image exists
    $repos = Get-AzContainerRegistryRepository -RegistryName $acrName -ErrorAction SilentlyContinue
    if ($repos -contains "skycraft-auth") {
        $repoExists = $true
        Write-Host "  -> ACR and Image already exist. Skipping bootstrap." -ForegroundColor Green
    }
}

if (-not $repoExists) {
    if (-not $acrExists) {
        Write-Host "Deploying ACR (Bootstrap)..." -ForegroundColor Yellow
        try {
            New-AzResourceGroupDeployment -ResourceGroupName $ResourceGroupName `
                -TemplateFile $acrBicep `
                -parLocation $Location `
                -parEnvironment $Environment `
                -parAcrName $acrName `
                -ErrorAction Stop | Out-Null
        } catch {
            Write-Host "[ERROR] ACR Bootstrap Failed: $_" -ForegroundColor Red
            exit 1
        }
    }

    Write-Host "Building Container Image (This may take 1-2 mins)..." -ForegroundColor Yellow
    try {
        az acr build --registry $acrName --image "skycraft-auth:v1" "https://github.com/Azure-Samples/aci-helloworld.git" --output none
        if ($LASTEXITCODE -eq 0) {
            Write-Host "  -> Image Build Success" -ForegroundColor Green
        } else {
            throw "Build command failed"
        }
    } catch {
        Write-Host "[ERROR] Failed to build image: $_" -ForegroundColor Red
        exit 1
    }
}

# ==============================================================================
# PHASE 2: MAIN DEPLOYMENT (ORCHESTRATOR)
# ==============================================================================
Write-Host "`n=== Phase 2: Orchestrated Deployment (main.bicep) ===" -ForegroundColor Cyan

try {
    $params = @{
        parLocation        = $Location
        parResourceGroupName = $ResourceGroupName
        parEnvironment     = $Environment
        parAcrName         = $acrName
    }

    $deployment = New-AzSubscriptionDeployment `
        -Name $deploymentName `
        -Location $Location `
        -TemplateFile $mainBicep `
        -TemplateParameterObject $params `
        -Verbose

    if ($deployment.ProvisioningState -eq 'Succeeded') {
        Write-Host "`n[SUCCESS] Deployment completed successfully!" -ForegroundColor Green
        Write-Host "`nDeployment Outputs:" -ForegroundColor Cyan
        $deployment.Outputs | Format-Table -AutoSize
    }
    else {
        Write-Host "`n[FAILED] Deployment failed with state: $($deployment.ProvisioningState)" -ForegroundColor Red
        # Error handling logic omitted for brevity, similar to template
    }
}
catch {
    Write-Host "`n[ERROR] Deployment failed with exception:" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    exit 1
}

Write-Host "`nNext Step: Run .\Test-Lab.ps1 to verify the configuration." -ForegroundColor Yellow
