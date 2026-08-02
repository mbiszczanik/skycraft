<#
.SYNOPSIS
    Deploys Lab 3.3 Container resources using Bicep templates.

.DESCRIPTION
    This script orchestrates the deployment of SkyCraft Lab 3.3 (Containers).
    
    CRITICAL WORKFLOW:
    1. Bootstraps Azure Container Registry (ACR) first (if not exists).
    2. Imports the required container image (skycraft-auth:v1) from MCR (Microsoft Container Registry).
    3. Executes the main.bicep orchestrator to deploy ACI and ACA.
    
    This multi-step process is required because ACI/ACA depend on the image existing
    in the registry before they can be successfully provisioned.

.PARAMETER Location
    The Azure region deployment target. Default: 'swedencentral'

.PARAMETER ResourceGroupName
    Optional override for the resource group. When omitted, the group comes from the
    .bicepparam file for the chosen -Environment, falling back to main.bicep's default. A value
    that disagrees with the parameter file is rejected: Phase 2 deploys to the file's group, so
    bootstrapping elsewhere would split the lab across two resource groups.

.PARAMETER Environment
    The environment tag. Default: 'dev'

.PARAMETER TemplateParameterFile
    Optional path to a .bicepparam file for the Phase 2 main.bicep deployment.
    Defaults to ..\bicep\parameters\<Environment>.bicepparam.

.EXAMPLE
    .\Deploy-Bicep.ps1
    Deploys to default resource groups.

.NOTES
    Project: SkyCraft
    Lab: 3.3 - Containers
    Author: Antigravity
    Date: 2026-01-31
#>

#Requires -Version 7.0
#Requires -Modules Az.Accounts, Az.Resources, Az.ContainerRegistry

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [ValidateSet('swedencentral', 'northeurope')]
    [string]$Location = 'swedencentral',

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$ResourceGroupName = 'dev-skycraft-swc-rg',

    [Parameter(Mandatory = $false)]
    [ValidateSet('dev', 'prod', 'platform')]
    [string]$Environment = 'dev',

    [Parameter(Mandatory = $false)]
    [string]$TemplateParameterFile
)

$ErrorActionPreference = 'Stop'

if (-not $TemplateParameterFile) { $TemplateParameterFile = Join-Path $PSScriptRoot "..\bicep\parameters\$Environment.bicepparam" }

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

# ==============================================================================
# RESOLVE PARAMETERS (before bootstrapping - Phase 1 must agree with Phase 2)
# ==============================================================================
# Phase 1 creates the resource group and the registry, so it has to use the values Phase 2
# will deploy with. Hydrating afterwards and overlaying static values here is what made
# `-Environment prod` create prod-named containers inside the dev resource group.
$params = @{}
$built = az bicep build-params --file $TemplateParameterFile --stdout | ConvertFrom-Json
if ($LASTEXITCODE -ne 0 -or -not $built.parametersJson) {
    Write-Host "  -> [ERROR] Failed to compile parameter file: $TemplateParameterFile" -ForegroundColor Red
    exit 1
}
foreach ($p in ($built.parametersJson | ConvertFrom-Json -AsHashtable).parameters.GetEnumerator()) {
    $params[$p.Key] = $p.Value.value
}

# Overlay only what this script computes. parResourceGroupName and parAcrName are deliberately
# absent: the parameter file supplies them, and re-asserting them here was the defect.
$params.parLocation    = $Location
$params.parEnvironment = $Environment

# Effective values = compiled template defaults, overridden by the parameter file, then by the
# overlay above. The template-default fallback is load-bearing rather than defensive: a
# .bicepparam sets only what differs from the template, so dev.bicepparam supplies
# parEnvironment alone and both names below would be $null if read from the file directly.
$effective = @{}
foreach ($p in ($built.templateJson | ConvertFrom-Json -AsHashtable).parameters.GetEnumerator()) {
    if ($p.Value.ContainsKey('defaultValue')) { $effective[$p.Key] = $p.Value.defaultValue }
}
foreach ($k in $params.Keys) { $effective[$k] = $params[$k] }

if ($PSBoundParameters.ContainsKey('ResourceGroupName') -and $ResourceGroupName -ne $effective.parResourceGroupName) {
    Write-Host "[ERROR] -ResourceGroupName '$ResourceGroupName' disagrees with '$($effective.parResourceGroupName)' from $TemplateParameterFile." -ForegroundColor Red
    Write-Host "        Phase 2 deploys to the parameter file's group, so bootstrapping elsewhere would split the lab across two groups." -ForegroundColor Red
    exit 1
}
$ResourceGroupName = $effective.parResourceGroupName
$acrName           = $effective.parAcrName

Write-Host "  Environment:    $Environment" -ForegroundColor Gray
Write-Host "  Resource Group: $ResourceGroupName" -ForegroundColor Gray
Write-Host "  Registry:       $acrName" -ForegroundColor Gray

# Ensure RG exists (needed for module deployment / bootstrapping)
try {
    if (-not (Get-AzResourceGroup -Name $ResourceGroupName -ErrorAction SilentlyContinue)) {
        Write-Host "Creating Resource Group: $ResourceGroupName..." -ForegroundColor Yellow
        # No Environment tag here. main.bicep:60 maps parEnvironment to the canonical long form
        # and sets it on this group at :72, so Phase 2 tags it correctly. Setting it from
        # PowerShell would put a second copy of that mapping in another language, with nothing
        # comparing the two.
        New-AzResourceGroup -Name $ResourceGroupName -Location $Location `
            -Tag @{ Project = 'SkyCraft'; CostCenter = 'MSDN'; Owner = 'admin@skycraft.com' } -ErrorAction Stop | Out-Null
    }
} catch {
    Write-Host "[ERROR] Failed to create Resource Group: $_" -ForegroundColor Red
    exit 1
}

# ==============================================================================
# PHASE 1: BOOTSTRAP ACR & IMAGE
# ==============================================================================
Write-Host "`n=== Phase 1: Bootstrapping Prerequisites ===" -ForegroundColor Cyan

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

$acrWasBootstrapped = $false
if (-not $repoExists) {
    $acrWasBootstrapped = $true
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
        # Import prebuilt aci-helloworld from MCR instead of `az acr build` — Az PowerShell has no build-from-source cmdlet; functionally equivalent runnable web image.
        Import-AzContainerRegistryImage -ResourceGroupName $ResourceGroupName -RegistryName $acrName `
            -SourceRegistryUri 'mcr.microsoft.com' -SourceImage 'azuredocs/aci-helloworld:latest' `
            -TargetTag 'skycraft-auth:v1' -ErrorAction Stop | Out-Null
        Write-Host "  -> Image Build Success" -ForegroundColor Green
    } catch {
        Write-Host "[ERROR] Failed to build image: $_" -ForegroundColor Red
        exit 1
    }
}

# Azure Container Apps resolves ACR via Azure internal DNS. When the ACR is freshly
# created the DNS entry may not have propagated to 100.100.x.x resolvers yet, causing
# ACA to fail with 'no such host'. Wait 90s to let propagation complete.
if ($acrWasBootstrapped) {
    Write-Host "`n  Waiting 90 seconds for ACR DNS propagation before ACA deployment..." -ForegroundColor Gray
    Start-Sleep -Seconds 90
}

# ==============================================================================
# PHASE 2: MAIN DEPLOYMENT (ORCHESTRATOR)
# ==============================================================================
Write-Host "`n=== Phase 2: Orchestrated Deployment (main.bicep) ===" -ForegroundColor Cyan

try {
    Write-Host "Params: $TemplateParameterFile" -ForegroundColor Gray

    # $params was hydrated and overlaid before Phase 1, so both phases deploy one set of
    # values. Re-hydrating here would reintroduce the split this task removed.

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
        exit 1
    }
}
catch {
    Write-Host "`n[ERROR] Deployment failed with exception:" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    exit 1
}

Write-Host "`nNext Step: Run .\Test-Lab.ps1 to verify the configuration." -ForegroundColor Yellow
