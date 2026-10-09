<#
.SYNOPSIS
    Deploys Lab 3.1 Infrastructure Resources (Bicep).

.DESCRIPTION
    This script orchestrates the deployment of SkyCraft infrastructure (VNets, NSGs, LBs).
    It deploys main.bicep with the environment's .bicepparam file (dev or prod).

    Before deploying it looks up the hub VNet (platform-skycraft-swc-vnet) and the dev VNet
    (dev-skycraft-swc-vnet). A VNet that already exists - after Module 2, or after an earlier run
    of this lab - is referenced by the template instead of redeployed. A VNet deployment removes the
    peerings it does not list and replaces each subnet it does list with exactly what it declares,
    and the lab's network module lists every subnet and no peerings: redeploying would remove
    hub-to-prod, hub-to-dev and dev-to-hub, and on the dev VNet would also swap the NSGs and drop
    the service endpoints Lab 2.2 attached (issue #188). Deploying main.bicep with a parameter file
    directly, without this script, leaves the flags unset and does redeploy both VNets. The lookup result
    reaches the parameter files through SKYCRAFT_HUB_VNET_EXISTS and SKYCRAFT_DEV_VNET_EXISTS, which
    the script sets for the deployment and removes afterwards. A lookup that fails for any reason
    other than "not found" stops the script, so an unreadable VNet is never redeployed by mistake.

.PARAMETER Location
    The Azure region deployment target. Default: 'swedencentral'

.PARAMETER Environment
    Target environment (dev, prod). Default: 'dev'

.PARAMETER WhatIf
    Previews the deployment with the ARM what-if API and exits. Nothing is created or changed.

.EXAMPLE
    .\Deploy-Bicep.ps1 -Environment dev
    Deploys the Development environment.

.EXAMPLE
    .\Deploy-Bicep.ps1 -Environment dev -WhatIf
    Previews the Development deployment without changing anything. On a subscription where
    Module 2 already built the hub and dev VNets, neither VNet appears as a change.

.NOTES
    Project: SkyCraft
    Lab: 3.1 - Infrastructure as Code
    Date: 2026-01-12
#>

#Requires -Version 7.0
#Requires -Modules Az.Accounts, Az.Resources, Az.Network

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [ValidateSet('swedencentral', 'northeurope')]
    [string]$Location = 'swedencentral',

    [Parameter(Mandatory = $false)]
    [ValidateSet('dev', 'prod')]
    [string]$Environment = 'dev',

    [Parameter(Mandatory = $false)]
    [switch]$WhatIf
)

$ErrorActionPreference = 'Stop'

# Runs an Az lookup and returns its result, or $null when the resource (or its resource group)
# does not exist. Any other failure is rethrown: treating "could not read it" as "absent" would
# redeploy a VNet that stands, which is exactly the overwrite the lookup is there to prevent.
function Find-ExistingResource {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [scriptblock]$Lookup
    )

    try {
        & $Lookup
    }
    catch {
        if (Test-NotFoundError -ErrorRecord $_) { return $null }
        throw
    }
}

# True when an Az error record says the resource or its resource group does not exist.
function Test-NotFoundError {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [System.Management.Automation.ErrorRecord]$ErrorRecord
    )

    $text = "$($ErrorRecord.Exception.Message) $($ErrorRecord.FullyQualifiedErrorId)"
    return [bool]($text -match '\bResourceNotFound\b|\bResourceGroupNotFound\b|StatusCode:\s*404|was not found|could not be found')
}

Write-Host "=== Lab 3.1 - Deploy Infrastructure ($Environment) ===" -ForegroundColor Cyan

# 1. Verify Azure Connection
$context = Get-AzContext
if (-not $context) {
    Write-Host "Not logged in. Please run Connect-AzAccount" -ForegroundColor Red
    $Host.SetShouldExit(1)
    exit 1
}
Write-Host "Connected to: $($context.Subscription.Name)" -ForegroundColor Green

# 2. Deploy Bicep
$bicepPath = Join-Path $PSScriptRoot "..\bicep\main.bicep"
$paramPath = Join-Path $PSScriptRoot "..\bicep\parameters\$Environment.bicepparam"

if (-not (Test-Path $bicepPath)) { Write-Host "Bicep file missing: $bicepPath" -ForegroundColor Red; $Host.SetShouldExit(1); exit 1 }

$deploymentName = "SkyCraft-$Environment-$(Get-Date -Format 'yyyyMMdd-HHmm')"

Write-Host "`nStarting Deployment: $deploymentName" -ForegroundColor Cyan
Write-Host "Template: $bicepPath" -ForegroundColor Gray
Write-Host "Params:   $paramPath" -ForegroundColor Gray

# The VNets main.bicep declares, by the names its network module gives them.
$existenceFlags = [ordered]@{
    SKYCRAFT_HUB_VNET_EXISTS = @{ ResourceGroup = 'platform-skycraft-swc-rg'; Name = 'platform-skycraft-swc-vnet' }
    SKYCRAFT_DEV_VNET_EXISTS = @{ ResourceGroup = 'dev-skycraft-swc-rg'; Name = 'dev-skycraft-swc-vnet' }
}

try {
    Write-Host "`nLooking up existing VNets..." -ForegroundColor Cyan
    foreach ($flag in $existenceFlags.GetEnumerator()) {
        $vnet = Find-ExistingResource -Lookup {
            Get-AzVirtualNetwork -ResourceGroupName $flag.Value.ResourceGroup -Name $flag.Value.Name -ErrorAction Stop
        }
        $exists = $null -ne $vnet
        Set-Item -Path "Env:$($flag.Key)" -Value $exists.ToString().ToLowerInvariant()
        if ($exists) {
            Write-Host "  - $($flag.Value.Name) exists: referenced, not redeployed (its peerings stay)." -ForegroundColor Gray
        }
        else {
            Write-Host "  - $($flag.Value.Name) not found: this deployment creates it." -ForegroundColor Gray
        }
    }

    $deployParams = @{
        Name                  = $deploymentName
        Location              = $Location
        TemplateFile          = $bicepPath
        TemplateParameterFile = $paramPath
        ErrorAction           = 'Stop'
    }

    if ($WhatIf) {
        Write-Host "Running in what-if mode (dry run)..." -ForegroundColor Cyan
        Get-AzSubscriptionDeploymentWhatIfResult @deployParams
        Write-Host "`nWhat-if completed. Review the changes above - nothing was deployed." -ForegroundColor Cyan
    }
    else {
        Write-Host "Deploying..." -ForegroundColor Yellow
        $dep = New-AzSubscriptionDeployment @deployParams

        if ($dep.ProvisioningState -eq 'Succeeded') {
            Write-Host "`n[SUCCESS] Deployment complete!" -ForegroundColor Green
            $dep.Outputs | Format-Table -AutoSize
        }
        else {
            Write-Host "`n[FAILED] State: $($dep.ProvisioningState)" -ForegroundColor Red
            $Host.SetShouldExit(1)
            exit 1
        }
    }
}
catch {
    Write-Host "`n[ERROR] Deployment failed!" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    $Host.SetShouldExit(1)
    exit 1
}
finally {
    # The flags describe this run only; a later direct deployment must not inherit them.
    foreach ($name in $existenceFlags.Keys) {
        Remove-Item -Path "Env:$name" -ErrorAction SilentlyContinue
    }
}
