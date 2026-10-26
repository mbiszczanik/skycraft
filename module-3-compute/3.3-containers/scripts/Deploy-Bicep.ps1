<#
.SYNOPSIS
    Deploys Lab 3.3 Container resources using Bicep templates.

.DESCRIPTION
    This script orchestrates the deployment of SkyCraft Lab 3.3 (Containers).
    
    CRITICAL WORKFLOW:
    1. Bootstraps Azure Container Registry (ACR) first with bicep\acr.bicep (if not exists).
    2. Imports the required container image (skycraft-auth:v1) from MCR (Microsoft Container Registry).
    3. Executes the main.bicep orchestrator to deploy ACI and ACA.
    
    This multi-step process is required because ACI/ACA depend on the image existing
    in the registry before they can be successfully provisioned.

.PARAMETER Location
    The Azure region deployment target. Default: 'swedencentral'

.PARAMETER Environment
    The environment to deploy: dev, prod or platform. Default: 'dev'. It sets the Environment
    tag and the prefix of every resource name (#121): the resource group, the registry, and -
    inside main.bicep - the container instance, the Container Apps environment and the app.

.PARAMETER ResourceGroupName
    The resource group name. Default: '<Environment>-skycraft-swc-rg'

.PARAMETER AcrName
    The container registry name. Default: '<Environment>skycraftswcacr01'. Registry names are
    global, so override this on a collision; the same value is passed to acr.bicep and main.bicep.

.PARAMETER WhatIf
    Previews the main.bicep deployment with the ARM what-if API and exits. Nothing is created
    or changed - which also means the Phase 1 bootstrap (resource group, ACR, image import) is
    skipped rather than simulated, so the preview needs those prerequisites to already exist.

.EXAMPLE
    .\Deploy-Bicep.ps1
    Deploys the dev resources into dev-skycraft-swc-rg.

.EXAMPLE
    .\Deploy-Bicep.ps1 -Environment prod
    Deploys prodskycraftswcacr01, prod-skycraft-swc-aci-auth, prod-skycraft-swc-cae-02 and
    prod-skycraft-swc-aca-world into prod-skycraft-swc-rg.

.EXAMPLE
    .\Deploy-Bicep.ps1 -WhatIf
    Previews the ACI/ACA orchestrator without bootstrapping or deploying anything.

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

    # Defaults below read $Environment, so it must be declared first.
    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$ResourceGroupName = "$Environment-skycraft-swc-rg",

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$AcrName = "${Environment}skycraftswcacr01",

    [Parameter(Mandatory = $false)]
    [switch]$WhatIf
)

$ErrorActionPreference = 'Stop'
# Exit-Lab ends the script with exit code 0 or 1 and leaves an interactive session open (#257).
Import-Module (Join-Path $PSScriptRoot '../../../tools/LabCommon.psm1') -Force -Verbose:$false

Write-Host "=== Lab 3.3 - Deploy Bicep Configuration ===" -ForegroundColor Cyan -BackgroundColor Black

# Verify Azure Connection
$context = Get-AzContext
if (-not $context) {
    Write-Host "Not logged in. Please run Connect-AzAccount" -ForegroundColor Red
    Exit-Lab -FailureCount 1
}
Write-Host "Connected to: $($context.Subscription.Name)" -ForegroundColor Green
Write-Host "  Environment:    $Environment" -ForegroundColor Gray
Write-Host "  Resource Group: $ResourceGroupName" -ForegroundColor Gray
Write-Host "  Registry:       $AcrName" -ForegroundColor Gray

# Define paths
$bicepPath = Join-Path $PSScriptRoot "..\bicep"
$mainBicep = Join-Path $bicepPath "main.bicep"
$acrBicep = Join-Path $bicepPath "acr.bicep"
$deploymentName = "Lab-3.3-Containers-$Environment"

if (-not (Test-Path $mainBicep)) {
    Write-Host "[ERROR] Bicep file not found: $mainBicep" -ForegroundColor Red
    Exit-Lab -FailureCount 1
}

$deployParams = @{
    Name                    = $deploymentName
    Location                = $Location
    TemplateFile            = $mainBicep
    TemplateParameterObject = @{
        parLocation          = $Location
        parResourceGroupName = $ResourceGroupName
        parEnvironment       = $Environment
        parAcrName           = $AcrName
    }
    ErrorAction             = 'Stop'
}

# An environment deployed by an older version of this template is Consumption-only (no workload
# profiles). main.bicep now declares the Consumption workload profile, and Azure cannot turn one
# type into the other, so the deployment would fail on it after Phase 1. Stop here instead, with
# what to do. The lookup lists the type across the subscription and filters by name and group, so a
# missing resource group reads as "no environment", not as an error. A lookup by -Name without the
# group fails with ResourceNotFound for an environment that exists (seen 2026-10-24).
# The lab's tests/Deploy-Bicep.Tests.ps1 lifts this function out with the parser.
function Get-LabConsumptionOnlyEnvironment {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)] [string]$ResourceGroupName,
        [Parameter(Mandatory = $true)] [string]$Name
    )
    Get-AzResource -ResourceType 'Microsoft.App/managedEnvironments' -ExpandProperties -ErrorAction Stop |
        Where-Object { $_ -and $_.Name -eq $Name -and $_.ResourceGroupName -eq $ResourceGroupName -and -not @($_.Properties.workloadProfiles | Where-Object { $_ }) } |
        Select-Object -First 1
}

$caeName = "$Environment-skycraft-swc-cae-02"   # main.bicep's parCaeName default
try {
    $legacyCae = Get-LabConsumptionOnlyEnvironment -ResourceGroupName $ResourceGroupName -Name $caeName
} catch {
    Write-Host "[ERROR] Could not check for an existing Container Apps environment '$caeName': $_" -ForegroundColor Red
    Exit-Lab -FailureCount 1
}
if ($legacyCae) {
    Write-Host "[ERROR] The Container Apps environment '$caeName' in $ResourceGroupName is a Consumption-only environment, deployed by an older version of this lab." -ForegroundColor Red
    Write-Host "  This template creates a Workload profiles environment (the type the Portal creates), and Azure cannot change an environment's type." -ForegroundColor Gray
    Write-Host "  Delete it first - .\Remove-LabResource.ps1 -Environment $Environment -ResourceGroupName $ResourceGroupName removes the app, the environment (up to 25 minutes) and the rest of the lab - then run this script again." -ForegroundColor Gray
    Exit-Lab -FailureCount 1
}

# What-if runs before Phase 1: bootstrapping the registry and importing the image are real
# changes, so a preview must not perform them. The preview covers main.bicep only.
if ($WhatIf) {
    Write-Host "`nRunning in what-if mode (dry run)..." -ForegroundColor Cyan
    Write-Host "  Phase 1 (resource group, ACR bootstrap, image import) is skipped, not simulated." -ForegroundColor Gray
    Get-AzSubscriptionDeploymentWhatIfResult @deployParams
    Write-Host "`nWhat-if completed. Review the changes above - nothing was deployed." -ForegroundColor Cyan
    Exit-Lab -FailureCount 0
}

# Ensure RG exists (needed for module deployment / bootstrapping)
try {
    if (-not (Get-AzResourceGroup -Name $ResourceGroupName -ErrorAction SilentlyContinue)) {
        Write-Host "Creating Resource Group: $ResourceGroupName..." -ForegroundColor Yellow
        $envTag = @{ dev = 'Development'; prod = 'Production'; platform = 'Platform' }[$Environment]
        New-AzResourceGroup -Name $ResourceGroupName -Location $Location `
            -Tag @{ Project = 'SkyCraft'; Environment = $envTag; CostCenter = 'MSDN'; Owner = 'mbiszczanik' } -ErrorAction Stop | Out-Null
    }
} catch {
    Write-Host "[ERROR] Failed to create Resource Group: $_" -ForegroundColor Red
    Exit-Lab -FailureCount 1
}

# ==============================================================================
# PHASE 1: BOOTSTRAP ACR & IMAGE
# ==============================================================================
Write-Host "`n=== Phase 1: Bootstrapping Prerequisites ===" -ForegroundColor Cyan

# Check if we need to bootstrap image
$repoExists = $false
$acrExists = Get-AzContainerRegistry -ResourceGroupName $ResourceGroupName -Name $AcrName -ErrorAction SilentlyContinue
if ($acrExists) {
    # Check if image exists
    $repos = Get-AzContainerRegistryRepository -RegistryName $AcrName -ErrorAction SilentlyContinue
    if ($repos -contains "skycraft-auth") {
        $repoExists = $true
        Write-Host "  -> ACR and Image already exist. Skipping bootstrap." -ForegroundColor Green
    }
}

$acrWasBootstrapped = $false
if (-not $repoExists) {
    if (-not $acrExists) {
        $acrWasBootstrapped = $true    # only a brand-new registry needs the DNS wait
        Write-Host "Deploying ACR (Bootstrap)..." -ForegroundColor Yellow
        try {
            $acrDeployment = New-AzResourceGroupDeployment -ResourceGroupName $ResourceGroupName `
                -TemplateFile $acrBicep `
                -parLocation $Location `
                -parEnvironment $Environment `
                -parAcrName $AcrName `
                -ErrorAction Stop

            if ($acrDeployment.ProvisioningState -ne 'Succeeded') {
                Write-Host "[ERROR] ACR Bootstrap finished with state: $($acrDeployment.ProvisioningState)" -ForegroundColor Red
                Exit-Lab -FailureCount 1
            }
        } catch {
            Write-Host "[ERROR] ACR Bootstrap Failed: $_" -ForegroundColor Red
            Exit-Lab -FailureCount 1
        }
    }

    Write-Host "Building Container Image (This may take 1-2 mins)..." -ForegroundColor Yellow
    try {
        # Import prebuilt aci-helloworld from MCR instead of `az acr build` — Az PowerShell has no build-from-source cmdlet; functionally equivalent runnable web image.
        Import-AzContainerRegistryImage -ResourceGroupName $ResourceGroupName -RegistryName $AcrName `
            -SourceRegistryUri 'mcr.microsoft.com' -SourceImage 'azuredocs/aci-helloworld:latest' `
            -TargetTag 'skycraft-auth:v1' -ErrorAction Stop | Out-Null
        Write-Host "  -> Image Build Success" -ForegroundColor Green
    } catch {
        Write-Host "[ERROR] Failed to build image: $_" -ForegroundColor Red
        Exit-Lab -FailureCount 1
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
    $deployment = New-AzSubscriptionDeployment @deployParams -Verbose

    if ($deployment.ProvisioningState -eq 'Succeeded') {
        Write-Host "`n[SUCCESS] Deployment completed successfully!" -ForegroundColor Green
        Write-Host "`nDeployment Outputs:" -ForegroundColor Cyan
        $deployment.Outputs | Format-Table -AutoSize
    }
    else {
        Write-Host "`n[FAILED] Deployment failed with state: $($deployment.ProvisioningState)" -ForegroundColor Red
        Exit-Lab -FailureCount 1
    }
}
catch {
    Write-Host "`n[ERROR] Deployment failed with exception:" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    Exit-Lab -FailureCount 1
}

Write-Host "`nNext Step: Run .\Test-Lab.ps1 to verify the configuration." -ForegroundColor Yellow
Exit-Lab -FailureCount 0
