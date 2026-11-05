<#
.SYNOPSIS
    Deploys Lab 2.3 name resolution and load balancer infrastructure via Bicep.

.DESCRIPTION
    Runs an Azure subscription-scoped deployment of the Lab 2.3 main.bicep template, which
    provisions public and private DNS zones, VNet links, A/CNAME records, and dev/prod load
    balancers. The deployment name is stamped with the current timestamp so successive runs
    do not overwrite each other in the deployment history.

.PARAMETER Location
    The Azure region for the subscription-scoped deployment. Defaults to 'swedencentral'.

.PARAMETER TemplateFile
    Path to the Bicep template to deploy. Defaults to '..\bicep\main.bicep' (relative to
    this script's folder).

.PARAMETER WhatIf
    Previews the deployment with the ARM what-if API and exits. Nothing is created or changed.

.EXAMPLE
    .\Deploy-Bicep.ps1
    Deploys the default main.bicep to Sweden Central using the current Az context.

.EXAMPLE
    .\Deploy-Bicep.ps1 -WhatIf
    Previews the DNS and load balancer deployment without changing anything.

.NOTES
    Project: SkyCraft
    Lab: 2.3 - Name Resolution & Load Balancing
    Author: Marcin Biszczanik
    Date: 2026-01-11
#>

#Requires -Version 7.0
#Requires -Modules Az.Accounts, Az.Resources

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [ValidateSet('swedencentral', 'northeurope')]
    [string]$Location = 'swedencentral',

    # Anchored to $PSScriptRoot, not the current directory - the bare relative default made this
    # the only script in the repository that had to be run from its own scripts/ folder (#75).
    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$TemplateFile = (Join-Path $PSScriptRoot '..\bicep\main.bicep'),

    [Parameter(Mandatory = $false)]
    [switch]$WhatIf
)

$ErrorActionPreference = 'Stop'
# Exit-Lab ends the script with exit code 0 or 1 and leaves an interactive session open (#257).
Import-Module (Join-Path $PSScriptRoot '../../../tools/LabCommon.psm1') -Force -Verbose:$false

# A terminating error under Stop ends the script through Exit-Lab, so a re-run at the prompt sees exit 1 (#398).
trap { Write-Host "[ERROR] $($_.Exception.Message)" -ForegroundColor Red; Exit-Lab -FailureCount 1 }

$deploymentName = "Lab-2.3-DNS-$(Get-Date -Format 'yyyyMMdd-HHmm')"

Write-Host "=== Lab 2.3 - Deploy Bicep (DNS) ===" -ForegroundColor Cyan -BackgroundColor Black

# Verify Bicep File
if (-not (Test-Path $TemplateFile)) {
    Write-Host "Error: Template file not found at $TemplateFile" -ForegroundColor Red
    Exit-Lab -FailureCount 1
}

# A link made for a dev or prod VNet that was deleted and created again no longer serves it, and
# the deployment is refused when it writes that link (Conflict, "delete all the stale virtual
# network links", #444). Delete it first; the deployment recreates it.
$privateZoneName = 'skycraft.internal'
try {
    $staleLinks = @(Get-LabDnsLink -ResourceGroupName 'platform-skycraft-swc-rg' | Where-Object { $_.Stale -and $_.Name -like "$privateZoneName/*" })
} catch {
    Write-Host "[ERROR] Could not check the VNet links of ${privateZoneName}: $($_.Exception.Message)" -ForegroundColor Red
    Exit-Lab -FailureCount 1
}
foreach ($staleLink in $staleLinks) {
    if ($WhatIf) {
        Write-Host "  [INFO] Link $($staleLink.Name) was made for a VNet created again since; a deployment deletes it first." -ForegroundColor Yellow
        continue
    }
    Write-Host "  Deleting link $($staleLink.Name): its VNet was created again after it, so it no longer serves that VNet..." -ForegroundColor Yellow
    try {
        Remove-LabDnsLink -Id $staleLink.Id -Confirm:$false
    } catch {
        Write-Host "[ERROR] Could not delete the stale link $($staleLink.Name): $($_.Exception.Message)" -ForegroundColor Red
        Exit-Lab -FailureCount 1
    }
}

# A load balancer whose backend pools already hold VM NICs (Lab 3.2) cannot be written again:
# Azure refuses a pool write that changes NIC-based members, ModificationOfNICIpConfigBackendPoolNotSupported
# (#352). Such a balancer is left as it stands and the rest of the lab is deployed. A lookup that
# fails for any reason other than "not found" stops the script: it must not read as "no members".
$lbTargets = [ordered]@{
    dev  = @{ ResourceGroup = 'dev-skycraft-swc-rg'; Name = 'dev-skycraft-swc-lb' }
    prod = @{ ResourceGroup = 'prod-skycraft-swc-rg'; Name = 'prod-skycraft-swc-lb' }
}
$deployLb = @{}
foreach ($target in $lbTargets.GetEnumerator()) {
    $lb = $null
    try {
        $lb = Get-AzLoadBalancer -ResourceGroupName $target.Value.ResourceGroup -Name $target.Value.Name -ErrorAction Stop
    } catch {
        $text = "$($_.Exception.Message) $($_.FullyQualifiedErrorId)"
        if ($text -notmatch '\bResourceNotFound\b|\bResourceGroupNotFound\b|StatusCode:\s*404|was not found|could not be found|NotFound') {
            Write-Host "[ERROR] Could not read load balancer $($target.Value.Name): $($_.Exception.Message)" -ForegroundColor Red
            Exit-Lab -FailureCount 1
        }
    }
    $members = if ($lb) { @($lb.BackendAddressPools | ForEach-Object { $_.BackendIpConfigurations } | Where-Object { $_ }).Count } else { 0 }
    $deployLb[$target.Key] = ($members -eq 0)
    if ($members -gt 0) {
        Write-Host "  - $($target.Value.Name) has $members VM NIC(s) in its backend pools: left as it stands, not redeployed. To change its pools, remove the NICs from them first (Lab 3.2 cleanup) or edit the pools in the Portal." -ForegroundColor Yellow
    }
}

Write-Host "Starting deployment: $deploymentName..." -ForegroundColor Yellow

try {
    $deployParams = @{
        Name                    = $deploymentName
        Location                = $Location
        TemplateFile            = $TemplateFile
        TemplateParameterObject = @{
            parDeployDevLb  = $deployLb['dev']
            parDeployProdLb = $deployLb['prod']
        }
        ErrorAction             = 'Stop'
    }

    if ($WhatIf) {
        Write-Host "  Running in what-if mode (dry run)..." -ForegroundColor Cyan
        Get-AzSubscriptionDeploymentWhatIfResult @deployParams
        Write-Host "`n  What-if completed. Review the changes above - nothing was deployed." -ForegroundColor Cyan
        exit 0
    }

    $deployment = New-AzDeployment @deployParams -Verbose

    if ($deployment.ProvisioningState -ne 'Succeeded') {
        Write-Host "`n[FAILED] Deployment failed with state: $($deployment.ProvisioningState)" -ForegroundColor Red
        Exit-Lab -FailureCount 1
    }

    Write-Host "`n[OK] Deployment completed successfully!" -ForegroundColor Green
}
catch {
    Write-Host "`n[ERROR] Deployment failed: $($_.Exception.Message)" -ForegroundColor Red
    Exit-Lab -FailureCount 1
}

Exit-Lab -FailureCount 0
