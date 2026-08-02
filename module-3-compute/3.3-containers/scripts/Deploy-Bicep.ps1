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

.PARAMETER Environment
    Selects which .bicepparam file to deploy. Default: 'dev'. The file is authoritative for
    every value it sets, including its own parEnvironment; this switch chooses the file rather
    than overriding it. Passing -TemplateParameterFile for a different environment alongside an
    explicit -Environment is rejected rather than silently resolved.

.PARAMETER TemplateParameterFile
    Optional path to a .bicepparam file. Defaults to ..\bicep\parameters\<Environment>.bicepparam.
    It supplies the resource group and registry that Phase 1 bootstraps as well as the values
    Phase 2 deploys, so both phases are driven by one file.

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

# Overlay only what this script computes. parResourceGroupName, parAcrName and parEnvironment
# are deliberately absent: all three parameter files set them, and re-asserting any of them
# here was the defect. -Location is overlaid because no parameter file sets it, so this is the
# only route by which the caller's choice reaches the deployment.
$params.parLocation = $Location

# Effective values = compiled template defaults, overridden by the parameter file, then by the
# overlay above. Used to resolve the three locals below, which Phase 1 needs before Phase 2
# runs; it is not sent to Azure, $params is. The template-default fallback is load-bearing
# rather than defensive: a .bicepparam sets only what differs from the template, so
# dev.bicepparam supplies parEnvironment alone and the other two would be $null if read from
# the parameter file directly.
$effectiveParams = @{}
foreach ($p in ($built.templateJson | ConvertFrom-Json -AsHashtable).parameters.GetEnumerator()) {
    if ($p.Value.ContainsKey('defaultValue')) { $effectiveParams[$p.Key] = $p.Value.defaultValue }
}
foreach ($k in $params.Keys) { $effectiveParams[$k] = $params[$k] }

# -Environment selects the file; the file then decides. Reject the one combination where the
# two can disagree, rather than letting an explicit -TemplateParameterFile be overridden by an
# -Environment default: that is how prod-named resources came to be tagged Development.
if ($PSBoundParameters.ContainsKey('TemplateParameterFile') -and
    $PSBoundParameters.ContainsKey('Environment') -and
    $Environment -ne $effectiveParams.parEnvironment) {
    Write-Host "[ERROR] -Environment '$Environment' disagrees with parEnvironment '$($effectiveParams.parEnvironment)' in $TemplateParameterFile." -ForegroundColor Red
    Write-Host "        Pass one or the other: -Environment selects a parameter file, it does not override one." -ForegroundColor Red
    exit 1
}

$Environment       = $effectiveParams.parEnvironment
$ResourceGroupName = $effectiveParams.parResourceGroupName
$acrName           = $effectiveParams.parAcrName

# A null here means the template stopped declaring a default for a key the parameter file also
# omits, which would otherwise surface as an obscure ARM error much later.
if (-not $ResourceGroupName -or -not $acrName -or -not $Environment) {
    Write-Host "[ERROR] Could not resolve deployment values from $TemplateParameterFile or main.bicep's defaults." -ForegroundColor Red
    Write-Host "        Environment='$Environment' ResourceGroup='$ResourceGroupName' Registry='$acrName'" -ForegroundColor Red
    exit 1
}

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
            # No Environment tag here, for the same reason the resource group above sets none.
            # acr.bicep's parEnvironmentTag takes the canonical long form ('Development' /
            # 'Production' / 'Platform'); this script only has the short key that selects the
            # parameter file. Computing the long form here would put a second copy of
            # main.bicep:60's mapping in another language with nothing comparing the two.
            # Phase 2 re-declares this registry through main.bicep and tags it correctly.
            New-AzResourceGroupDeployment -ResourceGroupName $ResourceGroupName `
                -TemplateFile $acrBicep `
                -parLocation $Location `
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
