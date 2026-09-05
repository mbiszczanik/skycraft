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
    Azure VM size (B-series v2 or D-series; B v1 is not available in Sweden Central on this subscription). Default: Standard_B2ls_v2

.PARAMETER EncryptionStrategy
    Encryption approach: None, EncryptionAtHost, or AzureDiskEncryption. Default: None

.PARAMETER SshKeyPath
    Path to SSH public key file. Default: $HOME\.ssh\skycraft-dev.pub

.PARAMETER WhatIf
    Previews the deployment with the ARM what-if API and exits. Nothing is created or changed.

.PARAMETER Force
    Skip the confirmation prompt so the script can run non-interactively
    (lab-cycle orchestration, CI). Without it, a session that cannot prompt
    aborts with exit code 2 instead of silently deploying nothing.

.EXAMPLE
    .\Deploy-Bicep.ps1 -Environment dev

.EXAMPLE
    .\Deploy-Bicep.ps1 -Environment dev -EncryptionStrategy EncryptionAtHost

.EXAMPLE
    .\Deploy-Bicep.ps1 -Environment dev -EncryptionStrategy AzureDiskEncryption -WhatIf

.EXAMPLE
    .\Deploy-Bicep.ps1 -Environment dev -Force
    Deploys without prompting - the form to use from an automated caller.

.NOTES
    Project: SkyCraft
    Lab: 3.2 - Virtual Machines
    Author: Marcin Biszczanik
    Date: 2026-01-11
    Exit codes: 0 = success (or -WhatIf preview), 1 = prerequisite or deployment
                failure, 2 = deployment declined or no console to confirm on
                (nothing was deployed).
#>

#Requires -Version 7.0
#Requires -Modules Az.Accounts, Az.Resources, Az.Network, Az.Compute

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingConvertToSecureStringWithPlainText', '',
    Justification = 'SSH public keys are not secrets. SecureString is required because New-AzSubscriptionDeployment passes this value to a @secure() Bicep parameter, which prevents it from appearing in deployment logs.')]
[CmdletBinding()]
param(
    [Parameter()]
    [ValidateSet('dev', 'prod')]
    [string]$Environment = 'dev',

    [Parameter()]
    [ValidateSet('Standard_B2ls_v2', 'Standard_B2als_v2', 'Standard_B2s_v2', 'Standard_B2as_v2', 'Standard_D2s_v3', 'Standard_D4s_v3')]
    [string]$VmSize = 'Standard_B2ls_v2',

    [Parameter()]
    [ValidateSet('None', 'EncryptionAtHost', 'AzureDiskEncryption')]
    [string]$EncryptionStrategy = 'None',

    [Parameter()]
    [string]$SshKeyPath = "$HOME\.ssh\skycraft-dev.pub",

    [Parameter()]
    [switch]$WhatIf,

    [Parameter()]
    [switch]$Force
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

$context = Get-AzContext
if (-not $context) {
    Write-Error "Not logged into Azure. Run Connect-AzAccount first."
    $Host.SetShouldExit(1)
    exit 1
}
Write-Host "  ✓ Logged in as: $($context.Account.Id)" -ForegroundColor Green

# Check SSH key exists
if (-not (Test-Path $SshKeyPath)) {
    Write-Error "SSH public key not found at: $SshKeyPath"
    Write-Host "  Generate one with: ssh-keygen -t rsa -b 4096 -f `"$HOME\.ssh\skycraft-dev`" -N `"`""
    $Host.SetShouldExit(1)
    exit 1
}
$sshPublicKey = (Get-Content $SshKeyPath -Raw).Trim()
$sshPublicKeySecure = ConvertTo-SecureString -String $sshPublicKey -AsPlainText -Force
Write-Host "  ✓ SSH public key found" -ForegroundColor Green

# Check if Lab 3.1 resources exist
Write-Host "`n[2/5] Checking Lab 3.1 prerequisites..." -ForegroundColor Yellow
$rgName = "$Environment-skycraft-swc-rg"
$vnetName = "$Environment-skycraft-swc-vnet"
$lbName = "$Environment-skycraft-swc-lb"

$rgExists = Get-AzResourceGroup -Name $rgName -ErrorAction SilentlyContinue
if (-not $rgExists) {
    Write-Error "Resource group '$rgName' not found. Deploy Lab 3.1 first."
    $Host.SetShouldExit(1)
    exit 1
}
Write-Host "  ✓ Resource group exists: $rgName" -ForegroundColor Green

$vnetExists = Get-AzVirtualNetwork -Name $vnetName -ResourceGroupName $rgName -ErrorAction SilentlyContinue
if (-not $vnetExists) {
    Write-Error "VNet '$vnetName' not found. Deploy Lab 3.1 first."
    $Host.SetShouldExit(1)
    exit 1
}
Write-Host "  ✓ VNet exists: $vnetName" -ForegroundColor Green

$lbExists = Get-AzLoadBalancer -Name $lbName -ResourceGroupName $rgName -ErrorAction SilentlyContinue
if (-not $lbExists) {
    Write-Error "Load Balancer '$lbName' not found. Deploy Lab 3.1 first."
    $Host.SetShouldExit(1)
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
# The prompt must never be answered by a stream: a confirmation read from stdin
# returns an empty answer at EOF, which used to cancel the deployment and still
# exit 0 - an automated caller then treated the skipped deployment as a success.
# Automation passes -Force; every other outcome (declined, or no console to ask
# on) exits 2 and deploys nothing.
if (-not $WhatIf -and -not $Force) {
    $choices = [System.Management.Automation.Host.ChoiceDescription[]]@(
        [System.Management.Automation.Host.ChoiceDescription]::new('&Yes', 'Deploy the resources listed above.')
        [System.Management.Automation.Host.ChoiceDescription]::new('&No', 'Cancel. Nothing is deployed.')
    )

    try {
        $answer = $Host.UI.PromptForChoice('Lab 3.2 - Virtual Machines', "`nProceed with deployment?", $choices, 1)
    }
    catch {
        Write-Host "`n[ABORTED] Cannot ask for confirmation: this session has no interactive console." -ForegroundColor Red
        Write-Host "  Re-run with -Force to deploy non-interactively. Deployment cancelled." -ForegroundColor Gray
        Write-Verbose "PromptForChoice failed: $($_.Exception.Message)"
        $Host.SetShouldExit(2)
        exit 2
    }

    if ($answer -ne 0) {
        Write-Host "Deployment cancelled." -ForegroundColor Yellow
        $Host.SetShouldExit(2)
        exit 2
    }
}

# Run deployment
Write-Host "`n[4/5] Running deployment..." -ForegroundColor Yellow

try {
    $deployParams = @{
        Name                = $deploymentName
        Location            = $location
        TemplateFile        = $templatePath
        parEnvironment      = $Environment
        parVmSize           = $VmSize
        parEncryptionStrategy = $EncryptionStrategy
        parSshPublicKey     = $sshPublicKeySecure
        ErrorAction         = 'Stop'
    }

    if ($WhatIf) {
        Write-Host "  Running in what-if mode (dry run)..." -ForegroundColor Cyan
        Get-AzSubscriptionDeploymentWhatIfResult @deployParams
        Write-Host "`n  What-if completed. Review the changes above - nothing was deployed." -ForegroundColor Cyan
        exit 0
    } else {
        $deployment = New-AzSubscriptionDeployment @deployParams

        if ($deployment.ProvisioningState -ne 'Succeeded') {
            Write-Host "`n[FAILED] Deployment failed with state: $($deployment.ProvisioningState)" -ForegroundColor Red
            $Host.SetShouldExit(1)
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
    $Host.SetShouldExit(1)
    exit 1
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  Deployment Complete" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan
