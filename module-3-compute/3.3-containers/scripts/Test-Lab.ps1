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

#Requires -Version 7.0
#Requires -Modules Az.Accounts, Az.ContainerRegistry, Az.ContainerInstance, Az.Resources

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$ResourceGroupName = 'dev-skycraft-swc-rg'
)

$ErrorActionPreference = 'Stop'
$failCount = 0

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

$acr = Get-AzContainerRegistry -ResourceGroupName $ResourceGroupName -Name $acrName -ErrorAction SilentlyContinue
if ($acr) {
    Write-Host "[OK] ACR found: $acrName" -ForegroundColor Green

    if ($acr.SkuName -eq "Standard") {
        Write-Host "  - SKU Standard verified" -ForegroundColor Green
    } else {
        Write-Host "  - [FAIL] SKU is $($acr.SkuName) (Expected: Standard)" -ForegroundColor Red
        $failCount++
    }

    if ($acr.AdminUserEnabled) {
        Write-Host "  - Admin User Enabled" -ForegroundColor Green
    } else {
        Write-Host "  - [FAIL] Admin User Not Enabled" -ForegroundColor Red
        $failCount++
    }

    # Check Image
    $repos = Get-AzContainerRegistryRepository -RegistryName $acrName -ErrorAction SilentlyContinue
    if ($repos -contains $imageName) {
        Write-Host "  - [OK] Repository '$imageName' found" -ForegroundColor Green
    } else {
        Write-Host "  - [FAIL] Repository '$imageName' not found" -ForegroundColor Red
        $failCount++
    }
} else {
    Write-Host "[FAIL] ACR $acrName not found" -ForegroundColor Red
    $failCount++
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
        Write-Host "  - [FAIL] Provisioning State is $($aci.ProvisioningState) (Expected: Succeeded)" -ForegroundColor Red
        $failCount++
    }

    if ($aci.IpAddress.Ip) {
        Write-Host "  - Public IP: $($aci.IpAddress.Ip)" -ForegroundColor Green
        Write-Host "  - FQDN: $($aci.IpAddress.Fqdn)" -ForegroundColor Green
    } else {
        Write-Host "  - [FAIL] No Public IP assigned" -ForegroundColor Red
        $failCount++
    }

} catch {
    Write-Host "[FAIL] ACI $aciName not found" -ForegroundColor Red
    $failCount++
}

# 3. Validate ACA
Write-Host "`n=== 3. Validating Azure Container Apps ===" -ForegroundColor Cyan
$acaName = "dev-skycraft-swc-aca-world-02"
$caeName = "dev-skycraft-swc-cae-02"

# Generic ARM lookup (no native Az cmdlet for Container Apps in base modules)
$aca = Get-AzResource -ResourceGroupName $ResourceGroupName -ResourceType 'Microsoft.App/containerApps' -Name $acaName -ExpandProperties -ErrorAction SilentlyContinue
if ($aca) {
    Write-Host "[OK] ACA found: $acaName" -ForegroundColor Green
    $props = $aca.Properties

    if ($props.provisioningState -eq "Succeeded") {
        Write-Host "  - Provisioning State: Succeeded" -ForegroundColor Green
    } else {
        Write-Host "  - [FAIL] Provisioning State: $($props.provisioningState)" -ForegroundColor Red
        $failCount++
    }

    if ($props.configuration.ingress.external) {
        Write-Host "  - Ingress: External (Enabled)" -ForegroundColor Green
        Write-Host "  - FQDN: https://$($props.configuration.ingress.fqdn)" -ForegroundColor Cyan
    } else {
        Write-Host "  - [FAIL] Ingress not configured correctly" -ForegroundColor Red
        $failCount++
    }

    # Check Scaling
    $scaleRules = $props.template.scale.rules
    $httpRule = $scaleRules | Where-Object { $_.http.metadata.concurrentRequests -eq '10' }
    if ($httpRule) {
        Write-Host "  - Scaling Rule 'http-load' (10 concurrent) verified" -ForegroundColor Green
    } else {
        Write-Host "  - [FAIL] Scaling rule not matching requirements" -ForegroundColor Red
        $failCount++
    }

    # Validate Image Tag
    $containerImage = $props.template.containers[0].image
    if ($containerImage -match ":$imageTag$") {
        Write-Host "  - Image Tag '$imageTag' verified" -ForegroundColor Green
    } else {
        Write-Host "  - [FAIL] Image Tag mismatch. Found: $containerImage" -ForegroundColor Red
        $failCount++
    }

    # Validate Environment
    $envId = $props.managedEnvironmentId
    if ($envId -match $caeName) {
        Write-Host "  - Managed Environment '$caeName' verified" -ForegroundColor Green
    } else {
        Write-Host "  - [FAIL] Managed Environment mismatch. Found: $envId" -ForegroundColor Red
        $failCount++
    }

} else {
    Write-Host "[FAIL] ACA $acaName not found" -ForegroundColor Red
    $failCount++
}

Write-Host "`n=== Validation Summary ===" -ForegroundColor Cyan
if ($failCount -eq 0) {
    Write-Host "All Lab 3.3 checks passed." -ForegroundColor Green
} else {
    Write-Host "Lab 3.3 validation found $failCount issue(s)." -ForegroundColor Red
}

exit $failCount
