<#
.SYNOPSIS
    Deploys Lab 3.1 Compute Resources (Bicep).

.DESCRIPTION
    This script deploys the SkyCraft Linux Virtual Machines (Auth and World servers).
    It handles SSH Key generation (or loading from file) and passes it to the Bicep template.

.PARAMETER Location
    The Azure region deployment target. Default: 'swedencentral'

.PARAMETER ProdResourceGroup
    The production resource group name. Default: 'prod-skycraft-swc-rg'

.PARAMETER SshKeyPath
    Path to the SSH Public Key file. If not provided, it will check ~/.ssh/id_rsa.pub or prompt to generate.

.EXAMPLE
    .\Deploy-Compute.ps1
    Deploys using default SSH key location.

.NOTES
    Project: SkyCraft
    Lab: 3.1 - Infrastructure as Code
    Author: Marcin Biszczanik
    Date: 2026-01-09
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$Location = 'swedencentral',

    [Parameter(Mandatory = $false)]
    [string]$ProdResourceGroup = 'prod-skycraft-swc-rg',

    [Parameter(Mandatory = $false)]
    [string]$SshKeyPath
)

Write-Host "=== Lab 3.1 - Deploy Compute Infrastructure ===" -ForegroundColor Cyan -BackgroundColor Black

# 1. Verify Azure Connection
$context = Get-AzContext
if (-not $context) {
    Write-Host "Not logged in. Please run Connect-AzAccount" -ForegroundColor Red
    exit 1
}
Write-Host "Connected to: $($context.Subscription.Name)" -ForegroundColor Green

# 2. Handle SSH Key
$sshPublicKey = ""

if ([string]::IsNullOrWhiteSpace($SshKeyPath)) {
    # Check default location
    $defaultKeyPath = "$HOME\.ssh\id_rsa.pub"
    if (Test-Path $defaultKeyPath) {
        Write-Host "Using default SSH key: $defaultKeyPath" -ForegroundColor Gray
        $SshKeyPath = $defaultKeyPath
    }
    else {
        # Check if user wants to generate one
        Write-Host "SSH Key not found at default location ($defaultKeyPath)." -ForegroundColor Yellow
        $gen = Read-Host "Do you want to generate a new SSH Key pair? (y/n)"
        if ($gen -eq 'y') {
            if (-not (Test-Path "$HOME\.ssh")) { New-Item -ItemType Directory -Path "$HOME\.ssh" | Out-Null }
            ssh-keygen -t rsa -b 4096 -f "$HOME\.ssh\id_rsa" -q -N ""
            Write-Host "Generated new key pair at $HOME\.ssh\id_rsa" -ForegroundColor Green
            $SshKeyPath = $defaultKeyPath
        }
        else {
            Write-Host "[ERROR] SSH Public Key is required for Linux VMs." -ForegroundColor Red
            exit 1
        }
    }
}

$sshPublicKey = Get-Content -Path $SshKeyPath -Raw
if ([string]::IsNullOrWhiteSpace($sshPublicKey)) {
    Write-Host "[ERROR] SSH Key file is empty: $SshKeyPath" -ForegroundColor Red
    exit 1
}

# 3. Deploy Bicep
$bicepPath = Join-Path $PSScriptRoot "..\bicep\main.bicep"
if (-not (Test-Path $bicepPath)) {
    Write-Host "[ERROR] Bicep file not found: $bicepPath" -ForegroundColor Red
    exit 1
}

Write-Host "`nDeploying Compute Resources..." -ForegroundColor Cyan

try {
    $deploymentName = "Lab-3.1-Compute-$(Get-Date -Format 'yyyyMMdd-HHmm')"
    
    $params = @{
        parLocation              = $Location
        parResourceGroupNameProd = $ProdResourceGroup
        parAdminPublicKey        = $sshPublicKey
    }

    $deployment = New-AzSubscriptionDeployment `
        -Name $deploymentName `
        -Location $Location `
        -TemplateFile $bicepPath `
        -TemplateParameterObject $params `
        -Verbose

    if ($deployment.ProvisioningState -eq 'Succeeded') {
        Write-Host "`n[SUCCESS] Deployment completed successfully!" -ForegroundColor Green
        Write-Host "`nDeployment Outputs:" -ForegroundColor Cyan
        $deployment.Outputs | Format-Table -AutoSize
        
        Write-Host "`nNext Steps:"
        Write-Host "1. Verify VMs are running in the Portal."
        Write-Host "2. Connect via Bastion using the private IPs listed above."
        Write-Host "   Example: ssh -i $HOME\.ssh\id_rsa skycraftadmin@<Private-IP>"
    }
    else {
        Write-Host "`n[FAILED] Deployment failed with state: $($deployment.ProvisioningState)" -ForegroundColor Red
    }
}
catch {
    Write-Host "`n[ERROR] Deployment failed with exception:" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    exit 1
}
