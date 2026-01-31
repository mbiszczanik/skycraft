<#
.SYNOPSIS
    Deploys Lab 3.3 Container resources using Bicep and Azure CLI.

.DESCRIPTION
    This script orchestrates the deployment of SkyCraft Lab 3.3 (Containers).
    It performs the following steps:
    1. Validate Azure connection.
    2. Create/Update the Resource Group.
    3. Deploy Azure Container Registry (ACR) via Bicep.
    4. Build and push the container image (skycraft-auth:v1) using ACR Tasks.
    5. Deploy Azure Container Instance (ACI) via Bicep.
    6. Deploy Azure Container Apps (ACA) via Bicep.

.PARAMETER Location
    The Azure region deployment target. Default: 'swedencentral'

.PARAMETER ResourceGroupName
    The resource group name. Default: 'dev-skycraft-swc-rg'

.EXAMPLE
    .\Deploy-Containers.ps1
    Deploys all resources to the default resource group and location.

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
    [string]$ResourceGroupName = 'dev-skycraft-swc-rg'
)

Write-Host "=== Lab 3.3 - Deploy Container Resources ===" -ForegroundColor Cyan -BackgroundColor Black

# 1. Verify Azure Connection
$context = Get-AzContext
if (-not $context) {
    Write-Host "Not logged in. Please run Connect-AzAccount" -ForegroundColor Red
    exit 1
}
Write-Host "Connected to: $($context.Subscription.Name)" -ForegroundColor Green

# 2. Create/Update Resource Group
Write-Host "`n=== Task 1: Ensure Resource Group ===" -ForegroundColor Cyan
try {
    $rg = Get-AzResourceGroup -Name $ResourceGroupName -ErrorAction SilentlyContinue
    if (-not $rg) {
        Write-Host "Creating Resource Group: $ResourceGroupName..." -ForegroundColor Yellow
        New-AzResourceGroup -Name $ResourceGroupName -Location $Location -Tag @{ Project = 'SkyCraft'; Environment = 'Development' } -ErrorAction Stop | Out-Null
        Write-Host "  -> Created $ResourceGroupName" -ForegroundColor Green
    } else {
        Write-Host "  -> Found existing Resource Group: $ResourceGroupName" -ForegroundColor Green
    }
} catch {
    Write-Host "  -> [ERROR] Failed to check/create Resource Group: $_" -ForegroundColor Red
    exit 1
}

# 3. Deploy ACR
Write-Host "`n=== Task 2: Deploy Azure Container Registry ===" -ForegroundColor Cyan
$acrName = "devskycraftswcacr01"
$acrTemplatePath = Join-Path $PSScriptRoot "..\bicep\modules\acr.bicep"

if (-not (Test-Path $acrTemplatePath)) {
    Write-Host "  -> [ERROR] Bicep template not found at $acrTemplatePath" -ForegroundColor Red
    exit 1
}

Write-Host "Deploying ACR: $acrName..." -ForegroundColor Yellow
try {
    $acrDeploy = New-AzResourceGroupDeployment -ResourceGroupName $ResourceGroupName `
        -TemplateFile $acrTemplatePath `
        -Name "deploy-acr-$(Get-Date -Format 'yyyyMMddHHmm')" `
        -parLocation $Location `
        -parAcrName $acrName `
        -ErrorAction Stop

    Write-Host "  -> Deployment Successful" -ForegroundColor Green
} catch {
    Write-Host "  -> [ERROR] ACR Deployment Failed: $_" -ForegroundColor Red
    exit 1
}

# 4. Build Image
Write-Host "`n=== Task 3: Build Container Image ===" -ForegroundColor Cyan
$imageName = "skycraft-auth:v1"
$gitSource = "https://github.com/Azure-Samples/aci-helloworld.git"

Write-Host "Building image '$imageName' in ACR '$acrName'..." -ForegroundColor Yellow
Write-Host "This typically takes 1-2 minutes..." -ForegroundColor Gray

try {
    # Using az cli for build as it's imperative and not supported by Bicep natively checks
    # Check if image exists usually, but we force build for the lab ensure it's fresh
    az acr build --registry $acrName --image $imageName $gitSource --output none
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  -> Image built successfully" -ForegroundColor Green
    } else {
        throw "ACR Build command returned failure code."
    }
} catch {
    Write-Host "  -> [ERROR] Failed to build image: $_" -ForegroundColor Red
    # Continue? No, subsequent steps fail.
    exit 1
}

# 5. Deploy ACI
Write-Host "`n=== Task 4: Deploy Azure Container Instance ===" -ForegroundColor Cyan
$aciName = "dev-skycraft-swc-aci-auth"
$aciTemplatePath = Join-Path $PSScriptRoot "..\bicep\modules\aci.bicep"

Write-Host "Deploying ACI: $aciName..." -ForegroundColor Yellow
try {
    $aciDeploy = New-AzResourceGroupDeployment -ResourceGroupName $ResourceGroupName `
        -TemplateFile $aciTemplatePath `
        -Name "deploy-aci-$(Get-Date -Format 'yyyyMMddHHmm')" `
        -parLocation $Location `
        -parAcrName $acrName `
        -parAciName $aciName `
        -parImage "skycraft-auth:v1" `
        -ErrorAction Stop

    Write-Host "  -> Deployment Successful" -ForegroundColor Green
    if ($aciDeploy.Outputs.outAciFqdn) {
        Write-Host "  -> ACI FQDN: $($aciDeploy.Outputs.outAciFqdn.Value)" -ForegroundColor Cyan
    }
} catch {
    Write-Host "  -> [ERROR] ACI Deployment Failed: $_" -ForegroundColor Red
    exit 1
}

# 6. Deploy ACA
Write-Host "`n=== Task 5: Deploy Azure Container Apps ===" -ForegroundColor Cyan
$caeName = "dev-skycraft-swc-cae"
$acaName = "dev-skycraft-swc-aca-world"
$acaTemplatePath = Join-Path $PSScriptRoot "..\bicep\modules\containerapps.bicep"

Write-Host "Deploying ACA: $acaName..." -ForegroundColor Yellow
try {
    $acaDeploy = New-AzResourceGroupDeployment -ResourceGroupName $ResourceGroupName `
        -TemplateFile $acaTemplatePath `
        -Name "deploy-aca-$(Get-Date -Format 'yyyyMMddHHmm')" `
        -parLocation $Location `
        -parAcrName $acrName `
        -parCaeName $caeName `
        -parAcaName $acaName `
        -parImage "skycraft-auth:v1" `
        -ErrorAction Stop

    Write-Host "  -> Deployment Successful" -ForegroundColor Green
    if ($acaDeploy.Outputs.outAcaFqdn) {
        Write-Host "  -> ACA FQDN: https://$($acaDeploy.Outputs.outAcaFqdn.Value)" -ForegroundColor Cyan
    }
} catch {
    Write-Host "  -> [ERROR] ACA Deployment Failed: $_" -ForegroundColor Red
    exit 1
}

Write-Host "`n=== Deployment Complete ===" -ForegroundColor Cyan -BackgroundColor Black
Write-Host "Run Test-Lab.ps1 to verify the container resources" -ForegroundColor Green
