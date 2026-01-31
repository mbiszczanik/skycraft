<#
.SYNOPSIS
    Validates the configuration of Lab 3.3 Container resources.

.DESCRIPTION
    This script runs validation checks against the deployed SkyCraft Lab 3.3 resources:
    - Azure Container Registry (ACR) and Image existence.
    - Azure Container Instance (ACI) running state and accessibility.
    - Azure Container Apps (ACA) running state, scaling config, and accessibility.

.PARAMETER ResourceGroupName
    The resource group name. Default: 'dev-skycraft-swc-rg'

.EXAMPLE
    .\Test-Lab.ps1
    Runs all validation checks and outputs results.

.NOTES
    Project: SkyCraft
    Lab: 3.3 - Containers
    Author: Antigravity
    Date: 2026-01-31
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$ResourceGroupName = 'dev-skycraft-swc-rg'
)

Write-Host "=== Lab 3.3 Validation Script ===" -ForegroundColor Cyan -BackgroundColor Black

# Check Azure Connection
$context = Get-AzContext
if (-not $context) {
    Write-Host "Not logged in. Please run Connect-AzAccount" -ForegroundColor Red
    exit 1
}
Write-Host "Connected to: $($context.Subscription.Name)" -ForegroundColor Green

# 1. Validate ACR
Write-Host "`n=== 1. Validating Azure Container Registry ===" -ForegroundColor Cyan
$acrName = "devskycraftswcacr01"
$imageName = "skycraft-auth"
$imageTag = "v1"

try {
    # Use CLI for reliable property access
    $acrJson = az acr show --name $acrName --resource-group $ResourceGroupName --output json 2>$null | ConvertFrom-Json
    if ($acrJson) {
        Write-Host "[OK] ACR found: $acrName" -ForegroundColor Green
        
        if ($acrJson.sku.name -eq "Standard") {
            Write-Host "  - SKU Standard verified" -ForegroundColor Green
        } else {
            Write-Host "  - [FAIL] SKU is $($acrJson.sku.name) (Expected: Standard)" -ForegroundColor Red
        }

        if ($acrJson.adminUserEnabled) {
            Write-Host "  - Admin User Enabled" -ForegroundColor Green
        } else {
            Write-Host "  - [FAIL] Admin User Not Enabled" -ForegroundColor Red
        }

        # Check Image
        $repos = az acr repository list --name $acrName --output json 2>$null | ConvertFrom-Json
        if ($repos -contains $imageName) {
            Write-Host "  - [OK] Repository '$imageName' found" -ForegroundColor Green
        } else {
            Write-Host "  - [FAIL] Repository '$imageName' not found" -ForegroundColor Red
        }
    } else {
        throw "ACR not found via CLI"
    }
} catch {
    Write-Host "[FAIL] ACR $acrName check failed: $_" -ForegroundColor Red
}

# 2. Validate ACI
Write-Host "`n=== 2. Validating Azure Container Instance ===" -ForegroundColor Cyan
$aciName = "dev-skycraft-swc-aci-auth"

try {
    $aci = Get-AzContainerGroup -ResourceGroupName $ResourceGroupName -Name $aciName -ErrorAction Stop
    Write-Host "[OK] ACI found: $aciName" -ForegroundColor Green

    if ($aci.ProvisioningState -eq "Succeeded") {
        Write-Host "  - Provisioning State: Succeeded" -ForegroundColor Green
    } else {
        Write-Host "  - [WARNING] Provisioning State is $($aci.ProvisioningState)" -ForegroundColor Yellow
    }

    if ($aci.IpAddress.Ip) {
        Write-Host "  - Public IP: $($aci.IpAddress.Ip)" -ForegroundColor Green
        Write-Host "  - FQDN: $($aci.IpAddress.Fqdn)" -ForegroundColor Green
    } else {
        Write-Host "  - [FAIL] No Public IP assigned" -ForegroundColor Red
    }

} catch {
    Write-Host "[FAIL] ACI $aciName not found" -ForegroundColor Red
}

# 3. Validate ACA
Write-Host "`n=== 3. Validating Azure Container Apps ===" -ForegroundColor Cyan
$acaName = "dev-skycraft-swc-aca-world-02"
$caeName = "dev-skycraft-swc-cae-02"

# Using CLI for ACA as Az PS module availability varies
try {
    $acaJson = az containerapp show --name $acaName --resource-group $ResourceGroupName --output json 2>$null | ConvertFrom-Json
    
    if ($acaJson) {
        Write-Host "[OK] ACA found: $acaName" -ForegroundColor Green
        
        if ($acaJson.properties.provisioningState -eq "Succeeded") {
            Write-Host "  - Provisioning State: Succeeded" -ForegroundColor Green
        } else {
            Write-Host "  - [FAIL] Provisioning State: $($acaJson.properties.provisioningState)" -ForegroundColor Red
        }

        if ($acaJson.properties.configuration.ingress.external) {
            Write-Host "  - Ingress: External (Enabled)" -ForegroundColor Green
            Write-Host "  - FQDN: https://$($acaJson.properties.configuration.ingress.fqdn)" -ForegroundColor Cyan
        } else {
            Write-Host "  - [FAIL] Ingress not configured correctly" -ForegroundColor Red
        }

        # Check Scaling
        $scaleRules = $acaJson.properties.template.scale.rules
        $httpRule = $scaleRules | Where-Object { $_.http.metadata.concurrentRequests -eq '10' }
        if ($httpRule) {
            Write-Host "  - Scaling Rule 'http-load' (10 concurrent) verified" -ForegroundColor Green
        } else {
            Write-Host "  - [FAIL] Scaling rule not matching requirements" -ForegroundColor Red
        }

        # Validate Image Tag
        $containerImage = $acaJson.properties.template.containers[0].image
        if ($containerImage -match ":$imageTag$") {
             Write-Host "  - Image Tag '$imageTag' verified" -ForegroundColor Green
        } else {
             Write-Host "  - [FAIL] Image Tag mismatch. Found: $containerImage" -ForegroundColor Red
        }

        # Validate Environment
        $envId = $acaJson.properties.managedEnvironmentId
        if ($envId -match $caeName) {
             Write-Host "  - Managed Environment '$caeName' verified" -ForegroundColor Green
        } else {
             Write-Host "  - [FAIL] Managed Environment mismatch. Found: $envId" -ForegroundColor Red
        }

    } else {
        Write-Host "[FAIL] ACA $acaName not found" -ForegroundColor Red
    }
} catch {
    Write-Host "[FAIL] Error checking ACA: $_" -ForegroundColor Red
}

Write-Host "`nValidation checks complete." -ForegroundColor Cyan
