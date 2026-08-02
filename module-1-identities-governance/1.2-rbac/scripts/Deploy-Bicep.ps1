<#
.SYNOPSIS
    Deploys the Lab 1.2 infrastructure (Resource Groups) using Bicep.

.DESCRIPTION
    This script deploys the required resource groups for SkyCraft Lab 1.2 using the
    'resource-groups.bicep' template. It targets the subscription scope.

.PARAMETER Location
    Azure region for deployment. Default: swedencentral.

.PARAMETER TemplateParameterFile
    Bicep parameter file to deploy. Defaults to the lab's
    bicep/parameters/resource-groups.bicepparam.

.EXAMPLE
    .\Deploy-Bicep.ps1
    Deploys to Sweden Central.

.NOTES
    Project: SkyCraft
    Lab: 1.2 - RBAC
#>

#Requires -Version 7.0
#Requires -Modules Az.Accounts, Az.Resources

[CmdletBinding()]
param(
    [ValidateSet('swedencentral', 'northeurope')]
    [string]$Location = 'swedencentral',

    [Parameter(Mandatory = $false)]
    [string]$TemplateParameterFile
)

$ErrorActionPreference = 'Stop'

if (-not $TemplateParameterFile) {
    $TemplateParameterFile = Join-Path $PSScriptRoot '..\bicep\parameters\resource-groups.bicepparam'
}

Write-Host "=== Lab 1.2: Infrastructure Deployment ===" -ForegroundColor Cyan -BackgroundColor Black

# Check Azure Context. Authentication is the caller's responsibility: in a child process
# with no console, connecting from here blocks until the phase timeout.
$context = Get-AzContext
if (-not $context) {
    Write-Host "  -> [ERROR] Not logged in to Azure. Run Connect-AzAccount first." -ForegroundColor Red
    exit 1
}
Write-Host "Connected to: $($context.Subscription.Name) ($($context.Subscription.Id))" -ForegroundColor Green

# Deployment
$templateFile = Join-Path $PSScriptRoot "..\bicep\resource-groups.bicep"
if (-not (Test-Path $templateFile)) {
    Write-Host "  -> [ERROR] Template file not found at: $templateFile" -ForegroundColor Red
    exit 1
}

if (-not (Test-Path $TemplateParameterFile)) {
    Write-Host "  -> [ERROR] Parameter file not found at: $TemplateParameterFile" -ForegroundColor Red
    exit 1
}

$deploymentName = "Lab-1.2-RBAC-RG-$(Get-Date -Format 'yyyyMMdd-HHmm')"

Write-Host "`nStarting Bicep Deployment..." -ForegroundColor Cyan
Write-Host "  Template: $templateFile" -ForegroundColor Gray
Write-Host "  Parameters: $TemplateParameterFile" -ForegroundColor Gray
Write-Host "  Location: $Location" -ForegroundColor Gray
Write-Host "  DeploymentName: $deploymentName" -ForegroundColor Gray

try {
    # Compile the .bicepparam with the Azure CLI's own Bicep rather than handing the file to Az,
    # which resolves it by shelling out to a bare `bicep` on PATH that `az bicep install` does
    # not provide. This script computes nothing, so there is no overlay: the hashtable is the
    # parameter file and nothing more.
    $params = @{}
    $built = az bicep build-params --file $TemplateParameterFile --stdout | ConvertFrom-Json
    if ($LASTEXITCODE -ne 0 -or -not $built.parametersJson) {
        Write-Host "  -> [ERROR] Failed to compile parameter file: $TemplateParameterFile" -ForegroundColor Red
        exit 1
    }
    foreach ($p in ($built.parametersJson | ConvertFrom-Json -AsHashtable).parameters.GetEnumerator()) {
        $params[$p.Key] = $p.Value.value
    }

    New-AzSubscriptionDeployment `
        -Name $deploymentName `
        -Location $Location `
        -TemplateFile $templateFile `
        -TemplateParameterObject $params `
        -ErrorAction Stop | Out-Null
    
    Write-Host "  -> [SUCCESS] Resource Groups deployed successfully." -ForegroundColor Green
    
    # Verify RGs
    $rgs = @("dev-skycraft-swc-rg", "prod-skycraft-swc-rg", "platform-skycraft-swc-rg")
    foreach($rg in $rgs) {
        if(Get-AzResourceGroup -Name $rg -ErrorAction SilentlyContinue) {
             Write-Host "     - Verified: $rg exists" -ForegroundColor Green
        } else {
             Write-Host "     - Warning: $rg not found after deployment" -ForegroundColor Yellow
        }
    }
}
catch {
    Write-Host "  -> [ERROR] Deployment failed: $_" -ForegroundColor Red
    exit 1
}

Write-Host "`nDeployment Complete." -ForegroundColor Green