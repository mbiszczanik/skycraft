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

.PARAMETER WhatIf
    Run deployment in what-if mode (dry run)

.EXAMPLE
    .\Deploy-Bicep.ps1 -Environment dev
    
.EXAMPLE
    .\Deploy-Bicep.ps1 -Environment dev -EncryptionStrategy EncryptionAtHost

.EXAMPLE
    .\Deploy-Bicep.ps1 -Environment dev -EncryptionStrategy AzureDiskEncryption -WhatIf
#>

[CmdletBinding()]
param(
    [Parameter()]
    [ValidateSet('dev', 'prod')]
    [string]$Environment = 'dev',

    [Parameter()]
    [ValidateSet('Standard_B1s', 'Standard_B2s', 'Standard_B2ms', 'Standard_D2s_v3')]
    [string]$VmSize = 'Standard_B2s',

    [Parameter()]
    [ValidateSet('None', 'EncryptionAtHost', 'AzureDiskEncryption')]
    [string]$EncryptionStrategy = 'None',

    [Parameter()]
    [string]$SshKeyPath = "$HOME\.ssh\skycraft-dev.pub",

    [Parameter()]
    [switch]$WhatIf
)

$ErrorActionPreference = 'Stop'

# Script configuration
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$templatePath = Join-Path $scriptPath "..\bicep\main.bicep"
$location = 'swedencentral'
$deploymentName = "lab32-$Environment-$(Get-Date -Format 'yyyyMMdd-HHmmss')"

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  Lab 3.2 - Virtual Machines Deployment" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# Validate prerequisites
Write-Host "[1/5] Validating prerequisites..." -ForegroundColor Yellow

# Check Azure CLI login
$account = az account show 2>$null | ConvertFrom-Json
if (-not $account) {
    Write-Error "Not logged into Azure CLI. Run 'az login' first."
    exit 1
}
Write-Host "  ✓ Logged in as: $($account.user.name)" -ForegroundColor Green

# Check SSH key exists
if (-not (Test-Path $SshKeyPath)) {
    Write-Error "SSH public key not found at: $SshKeyPath"
    Write-Host "  Generate one with: ssh-keygen -t rsa -b 4096 -f `"$HOME\.ssh\skycraft-dev`" -N `"`""
    exit 1
}
$sshPublicKey = Get-Content $SshKeyPath -Raw
Write-Host "  ✓ SSH public key found" -ForegroundColor Green

# Check if Lab 3.1 resources exist
Write-Host "`n[2/5] Checking Lab 3.1 prerequisites..." -ForegroundColor Yellow
$rgName = "$Environment-skycraft-swc-rg"
$vnetName = "$Environment-skycraft-swc-vnet"
$lbName = "$Environment-skycraft-swc-lb"

$rgExists = az group show --name $rgName 2>$null
if (-not $rgExists) {
    Write-Error "Resource group '$rgName' not found. Deploy Lab 3.1 first."
    exit 1
}
Write-Host "  ✓ Resource group exists: $rgName" -ForegroundColor Green

$vnetExists = az network vnet show --name $vnetName --resource-group $rgName 2>$null
if (-not $vnetExists) {
    Write-Error "VNet '$vnetName' not found. Deploy Lab 3.1 first."
    exit 1
}
Write-Host "  ✓ VNet exists: $vnetName" -ForegroundColor Green

$lbExists = az network lb show --name $lbName --resource-group $rgName 2>$null
if (-not $lbExists) {
    Write-Error "Load Balancer '$lbName' not found. Deploy Lab 3.1 first."
    exit 1
}
Write-Host "  ✓ Load Balancer exists: $lbName" -ForegroundColor Green

# Check Encryption at Host feature registration if needed
if ($EncryptionStrategy -eq 'EncryptionAtHost') {
    Write-Host "`n[2.5/5] Checking Encryption at Host feature registration..." -ForegroundColor Yellow
    $featureState = az feature show --name EncryptionAtHost --namespace Microsoft.Compute --query "properties.state" -o tsv 2>$null
    if ($featureState -ne 'Registered') {
        Write-Warning "Encryption at Host feature is not registered (state: $featureState)"
        Write-Host "  Register with: az feature register --name EncryptionAtHost --namespace Microsoft.Compute"
        Write-Host "  Then propagate: az provider register --namespace Microsoft.Compute"
        $continue = Read-Host "Continue anyway? (y/N)"
        if ($continue -ne 'y') {
            exit 1
        }
    } else {
        Write-Host "  ✓ Encryption at Host feature is registered" -ForegroundColor Green
    }
}

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

$deployArgs = @(
    'deployment', 'sub', 'create'
    '--name', $deploymentName
    '--location', $location
    '--template-file', $templatePath
    '--parameters', "parEnvironment=$Environment"
    '--parameters', "parVmSize=$VmSize"
    '--parameters', "parEncryptionStrategy=$EncryptionStrategy"
    '--parameters', "parSshPublicKey=$sshPublicKey"
)

if ($WhatIf) {
    Write-Host "  Running in what-if mode (dry run)..." -ForegroundColor Cyan
    $deployArgs[1] = 'sub'
    $deployArgs[2] = 'what-if'
}

$result = az @deployArgs 2>&1
$exitCode = $LASTEXITCODE

if ($exitCode -ne 0) {
    Write-Error "Deployment failed with exit code $exitCode"
    Write-Host $result -ForegroundColor Red
    exit $exitCode
}

# Display results
Write-Host "`n[5/5] Deployment Results:" -ForegroundColor Yellow
if ($WhatIf) {
    Write-Host $result
    Write-Host "`n  What-if completed. Review changes above." -ForegroundColor Cyan
} else {
    $deployment = $result | ConvertFrom-Json
    Write-Host "  ✓ Deployment succeeded!" -ForegroundColor Green
    Write-Host "`n  Outputs:"
    Write-Host "    Auth VM:          $($deployment.properties.outputs.outAuthVmName.value)"
    Write-Host "    World VM:         $($deployment.properties.outputs.outWorldVmName.value)"
    Write-Host "    Auth Private IP:  $($deployment.properties.outputs.outAuthNicPrivateIp.value)"
    Write-Host "    World Private IP: $($deployment.properties.outputs.outWorldNicPrivateIp.value)"
    Write-Host "    Encryption:       $($deployment.properties.outputs.outEncryptionStrategy.value)"
    
    if ($EncryptionStrategy -eq 'AzureDiskEncryption') {
        Write-Host "`n  ⚠️  Azure Disk Encryption requires additional step:" -ForegroundColor Yellow
        Write-Host "     Run: .\Enable-Encryption.ps1 -Environment $Environment"
    }
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  Deployment Complete" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan
