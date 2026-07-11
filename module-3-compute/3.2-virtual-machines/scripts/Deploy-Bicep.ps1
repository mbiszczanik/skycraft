<#
.SYNOPSIS
    Deploys Lab 3.2 Virtual Machines infrastructure using Bicep.

.DESCRIPTION
    This script deploys the Lab 3.2 Bicep templates to Azure, including:
    - Network Interfaces for Auth and World VMs
    - Virtual Machines with SSH key authentication
    - Managed Data Disk for Worldserver
    - Key Vault (if AzureDiskEncryption strategy is selected)

.PARAMETER Environment
    Target environment (dev or prod). Default: dev

.PARAMETER VmSize
    Azure VM size. Default: Standard_B2s

.PARAMETER EncryptionStrategy
    Encryption approach: None, EncryptionAtHost, or AzureDiskEncryption. Default: None

.PARAMETER SshKeyPath
    Path to SSH public key file. Default: $HOME\.ssh\skycraft-dev.pub

.PARAMETER TemplateParameterFile
    Optional path to a .bicepparam file. Defaults to ..\bicep\parameters\<Environment>.bicepparam.

.PARAMETER WhatIf
    Run deployment in what-if mode (dry run)

.EXAMPLE
    .\Deploy-Bicep.ps1 -Environment dev

.EXAMPLE
    .\Deploy-Bicep.ps1 -Environment dev -EncryptionStrategy EncryptionAtHost

.EXAMPLE
    .\Deploy-Bicep.ps1 -Environment dev -EncryptionStrategy AzureDiskEncryption -WhatIf

.NOTES
    Project: SkyCraft
    Lab: 3.2 - Virtual Machines
    Author: Marcin Biszczanik
    Date: 2026-01-11
#>

#Requires -Version 7.0
#Requires -Modules Az.Accounts, Az.Resources, Az.Network, Az.Compute

[CmdletBinding()]
param(
    [Parameter()]
    [ValidateSet('dev', 'prod')]
    [string]$Environment = 'dev',

    [Parameter()]
    [ValidateSet('Standard_B1s', 'Standard_B2s', 'Standard_B2ms', 'Standard_D2s_v3')]
    [string]$VmSize = 'Standard_D2s_v3',

    [Parameter()]
    [ValidateSet('None', 'EncryptionAtHost', 'AzureDiskEncryption')]
    [string]$EncryptionStrategy = 'None',

    [Parameter()]
    [string]$SshKeyPath = "$HOME\.ssh\skycraft-dev.pub",

    [Parameter()]
    [string]$TemplateParameterFile,

    [Parameter()]
    [switch]$WhatIf
)

$ErrorActionPreference = 'Stop'

# Script configuration
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$templatePath = Join-Path $scriptPath "..\bicep\main.bicep"
if (-not $TemplateParameterFile) { $TemplateParameterFile = Join-Path $scriptPath "..\bicep\parameters\$Environment.bicepparam" }
$location = 'swedencentral'
$deploymentName = "lab32-$Environment-$(Get-Date -Format 'yyyyMMdd-HHmmss')"

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  Lab 3.2 - Virtual Machines Deployment" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# Validate prerequisites
Write-Host "[1/5] Validating prerequisites..." -ForegroundColor Yellow

$context = Get-AzContext
if (-not $context) {
    Write-Error "Not logged into Azure. Run Connect-AzAccount first."
    exit 1
}
Write-Host "  ✓ Logged in as: $($context.Account.Id)" -ForegroundColor Green

# Check SSH key exists
if (-not (Test-Path $SshKeyPath)) {
    Write-Error "SSH public key not found at: $SshKeyPath"
    Write-Host "  Generate one with: ssh-keygen -t rsa -b 4096 -f `"$HOME\.ssh\skycraft-dev`" -N `"`""
    exit 1
}
$sshPublicKey = (Get-Content $SshKeyPath -Raw).Trim()
Write-Host "  ✓ SSH public key found" -ForegroundColor Green

# Check if Lab 3.1 resources exist
Write-Host "`n[2/5] Checking Lab 3.1 prerequisites..." -ForegroundColor Yellow
$rgName = "$Environment-skycraft-swc-rg"
$vnetName = "$Environment-skycraft-swc-vnet"
$lbName = "$Environment-skycraft-swc-lb"

$rgExists = Get-AzResourceGroup -Name $rgName -ErrorAction SilentlyContinue
if (-not $rgExists) {
    Write-Error "Resource group '$rgName' not found. Deploy Lab 3.1 first."
    exit 1
}
Write-Host "  ✓ Resource group exists: $rgName" -ForegroundColor Green

$vnetExists = Get-AzVirtualNetwork -Name $vnetName -ResourceGroupName $rgName -ErrorAction SilentlyContinue
if (-not $vnetExists) {
    Write-Error "VNet '$vnetName' not found. Deploy Lab 3.1 first."
    exit 1
}
Write-Host "  ✓ VNet exists: $vnetName" -ForegroundColor Green

$lbExists = Get-AzLoadBalancer -Name $lbName -ResourceGroupName $rgName -ErrorAction SilentlyContinue
if (-not $lbExists) {
    Write-Error "Load Balancer '$lbName' not found. Deploy Lab 3.1 first."
    exit 1
}
Write-Host "  ✓ Load Balancer exists: $lbName" -ForegroundColor Green

# Display deployment configuration
Write-Host "`n[3/5] Deployment Configuration:" -ForegroundColor Yellow
Write-Host "  Environment:          $Environment"
Write-Host "  VM Size:              $VmSize"
Write-Host "  Encryption Strategy:  $EncryptionStrategy"
Write-Host "  Location:             $location"
Write-Host "  Template:             $templatePath"
Write-Host "  Deployment Name:      $deploymentName"

# Confirm deployment
if (-not $WhatIf) {
    $confirm = Read-Host "`nProceed with deployment? (y/N)"
    if ($confirm -ne 'y') {
        Write-Host "Deployment cancelled." -ForegroundColor Yellow
        exit 0
    }
}

# Run deployment
Write-Host "`n[4/5] Running deployment..." -ForegroundColor Yellow

try {
    Write-Host "  Params: $TemplateParameterFile" -ForegroundColor Gray

    # Load base values from the per-environment .bicepparam file, then overlay the
    # exact script-supplied / generated values (keeps a no-argument run identical
    # to before, including the runtime SSH key placeholder override).
    $tp = @{}
    $built = (bicep build-params $TemplateParameterFile --stdout | ConvertFrom-Json)
    if ($built.parametersJson) {
        ($built.parametersJson | ConvertFrom-Json).parameters.PSObject.Properties | ForEach-Object { $tp[$_.Name] = $_.Value.value }
    }
    $tp.parEnvironment = $Environment
    $tp.parVmSize = $VmSize
    $tp.parEncryptionStrategy = $EncryptionStrategy
    # SSH public keys are not secrets; pass as a plain string. Az cannot serialize a
    # SecureString inside -TemplateParameterObject ("Unable to serialize secure string value").
    $tp.parSshPublicKey = $sshPublicKey

    $deployParams = @{
        Name                    = $deploymentName
        Location                = $location
        TemplateFile            = $templatePath
        TemplateParameterObject = $tp
        ErrorAction             = 'Stop'
    }

    if ($WhatIf) {
        Write-Host "  What-if mode: run 'az deployment sub what-if' for ARM preview. Skipping deployment." -ForegroundColor Cyan
        exit 0
    } else {
        $deployment = New-AzSubscriptionDeployment @deployParams

        if ($deployment.ProvisioningState -ne 'Succeeded') {
            Write-Host "`n[FAILED] Deployment failed with state: $($deployment.ProvisioningState)" -ForegroundColor Red
            exit 1
        }

        Write-Host "`n[5/5] Deployment Results:" -ForegroundColor Yellow
        Write-Host "  ✓ Deployment succeeded!" -ForegroundColor Green
        Write-Host "`n  Outputs:"
        Write-Host "    Auth VM:          $($deployment.Outputs['outAuthVmName'].Value)"
        Write-Host "    World VM:         $($deployment.Outputs['outWorldVmName'].Value)"
        Write-Host "    Auth Private IP:  $($deployment.Outputs['outAuthNicPrivateIp'].Value)"
        Write-Host "    World Private IP: $($deployment.Outputs['outWorldNicPrivateIp'].Value)"
        Write-Host "    Encryption:       $($deployment.Outputs['outEncryptionStrategy'].Value)"

        if ($EncryptionStrategy -eq 'AzureDiskEncryption') {
            Write-Host "`n  Azure Disk Encryption requires additional step:" -ForegroundColor Yellow
            Write-Host "     Run: .\Enable-Encryption.ps1 -Environment $Environment"
        }
    }
}
catch {
    Write-Error "Deployment failed: $($_.Exception.Message)"
    exit 1
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  Deployment Complete" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan
