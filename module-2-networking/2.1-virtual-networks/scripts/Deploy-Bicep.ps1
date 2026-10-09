<#
.SYNOPSIS
    Deploys Lab 2.1 networking resources using Bicep templates.

.DESCRIPTION
    This script orchestrates the deployment of the Hub-and-Spoke networking topology
    for SkyCraft Lab 2.1. It calls the main.bicep template (Azure Verified Modules) to create:
    - Platform (Hub) Virtual Network with 2 subnets (AzureBastionSubnet, GatewaySubnet).
    - Development and Production (Spoke) Virtual Networks with 4 subnets each.
    - Bi-directional Hub-Spoke VNet peering and the two Load Balancer Public IPs.

    The script is safe to re-run on a subscription where later labs already stand, for example
    to add the dev spoke next to an existing hub and prod (issue #188). Before deploying it looks
    up the three VNets and the two public IPs, and passes what it finds to the template:
    - a VNet that already exists is not redeployed. A VNet deployment removes the peerings it
      does not list and replaces each subnet it does list with exactly what it declares; the AVM
      VNet module lists no peerings, so redeploying would delete and recreate every peering, and
      re-declared subnets would lose the NSGs and service endpoints Lab 2.2 attached (and a
      portal-made App Service delegation would be renamed);
    - only the subnets an existing VNet lacks are added, as child resources of that VNet;
    - public IPs that already exist are left untouched (zones and SKU cannot change after
      creation).
    Missing VNets, subnets and public IPs, and all four peerings, are deployed; a peering that
    already exists with the same settings is unchanged. A lookup that fails for any reason other
    than "not found" stops the script before anything is deployed.

.PARAMETER Location
    The Azure region deployment target. Default: 'swedencentral'

.PARAMETER ProdResourceGroup
    The production resource group name. Default: 'prod-skycraft-swc-rg'

.PARAMETER DevResourceGroup
    The development resource group name. Default: 'dev-skycraft-swc-rg'

.PARAMETER PlatformResourceGroup
    The platform resource group name. Default: 'platform-skycraft-swc-rg'

.PARAMETER WhatIf
    Previews the deployment with the ARM what-if API and exits. Nothing is created or changed.

.EXAMPLE
    .\Deploy-Bicep.ps1
    Deploys to default resource groups in Sweden Central.

.EXAMPLE
    .\Deploy-Bicep.ps1 -WhatIf
    Previews the hub-and-spoke deployment without changing anything. On a subscription where hub
    and prod already stand, only the missing resources appear as changes.

.NOTES
    Project: SkyCraft
    Lab: 2.1 - Virtual Networks
    Author: Marcin Biszczanik
    Date: 2026-01-04
#>

#Requires -Version 7.0
#Requires -Modules Az.Accounts, Az.Resources, Az.Network

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [ValidateSet('swedencentral', 'northeurope')]
    [string]$Location = 'swedencentral',

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$ProdResourceGroup = 'prod-skycraft-swc-rg',

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$DevResourceGroup = 'dev-skycraft-swc-rg',

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$PlatformResourceGroup = 'platform-skycraft-swc-rg',

    [Parameter(Mandatory = $false)]
    [switch]$WhatIf
)

$ErrorActionPreference = 'Stop'

# Runs an Az lookup and returns its result, or $null when the resource (or its resource group)
# does not exist. Any other failure is rethrown: treating "could not read it" as "absent" would
# re-declare subnets that stand, which is exactly the overwrite the lookup is there to prevent.
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

# The names of a VNet's subnets, or nothing for a VNet that does not exist. Wrap the call in
# @(...) to get an array in every case.
function Get-SubnetName {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        [object]$Vnet
    )

    if ($null -eq $Vnet) { return }
    foreach ($subnet in @($Vnet.Subnets)) {
        if ($subnet -and $subnet.Name) { [string]$subnet.Name }
    }
}

Write-Host "=== Lab 2.1 - Deploy Networking Configuration ===" -ForegroundColor Cyan -BackgroundColor Black

# Verify Azure Connection
$context = Get-AzContext
if (-not $context) {
    Write-Host "Not logged in. Please run Connect-AzAccount" -ForegroundColor Red
    $Host.SetShouldExit(1)
    exit 1
}
Write-Host "Connected to: $($context.Subscription.Name)" -ForegroundColor Green

# Define paths
$bicepPath = Join-Path $PSScriptRoot "..\bicep"
$mainBicep = Join-Path $bicepPath "main.bicep"

# Verify Bicep file exists
if (-not (Test-Path $mainBicep)) {
    Write-Host "[ERROR] Bicep file not found: $mainBicep" -ForegroundColor Red
    $Host.SetShouldExit(1)
    exit 1
}

Write-Host "`nDeploying Lab 2.1 Resources..." -ForegroundColor Cyan

try {
    $deploymentName = "Lab-2.1-Virtual-Networks"

    # What already stands. The VNet and public IP names are main.bicep's defaults.
    Write-Host "`nLooking up existing networks and public IPs..." -ForegroundColor Cyan

    $vnetTargets = [ordered]@{
        hub  = @{ ResourceGroup = $PlatformResourceGroup; Name = 'platform-skycraft-swc-vnet' }
        dev  = @{ ResourceGroup = $DevResourceGroup; Name = 'dev-skycraft-swc-vnet' }
        prod = @{ ResourceGroup = $ProdResourceGroup; Name = 'prod-skycraft-swc-vnet' }
    }
    $vnetExists = @{}
    $existingSubnets = @{}
    foreach ($target in $vnetTargets.GetEnumerator()) {
        $vnet = Find-ExistingResource -Lookup {
            Get-AzVirtualNetwork -ResourceGroupName $target.Value.ResourceGroup -Name $target.Value.Name -ErrorAction Stop
        }
        $names = [string[]]@(Get-SubnetName -Vnet $vnet)
        $vnetExists[$target.Key] = $null -ne $vnet
        $existingSubnets[$target.Key] = $names
        if ($null -eq $vnet) {
            Write-Host "  - $($target.Value.Name) not found: created with all its subnets." -ForegroundColor Gray
        }
        else {
            $kept = if ($names.Count -gt 0) { $names -join ', ' } else { 'none' }
            Write-Host "  - $($target.Value.Name) exists: not redeployed; existing subnets left as they are: $kept" -ForegroundColor Gray
        }
    }

    $pipExists = @{}
    foreach ($pip in @(
            @{ Key = 'dev'; ResourceGroup = $DevResourceGroup; Name = 'dev-skycraft-swc-lb-pip' }
            @{ Key = 'prod'; ResourceGroup = $ProdResourceGroup; Name = 'prod-skycraft-swc-lb-pip' }
        )) {
        $found = Find-ExistingResource -Lookup {
            Get-AzPublicIpAddress -ResourceGroupName $pip.ResourceGroup -Name $pip.Name -ErrorAction Stop
        }
        $pipExists[$pip.Key] = $null -ne $found
        $state = if ($pipExists[$pip.Key]) { 'exists: left untouched' } else { 'not found: created' }
        Write-Host "  - $($pip.Name) $state." -ForegroundColor Gray
    }

    $params = @{
        parLocation                  = $Location
        parResourceGroupNameProd     = $ProdResourceGroup
        parResourceGroupNameDev      = $DevResourceGroup
        parResourceGroupNamePlatform = $PlatformResourceGroup
        parHubVnetExists             = $vnetExists['hub']
        parDevVnetExists             = $vnetExists['dev']
        parProdVnetExists            = $vnetExists['prod']
        parExistingSubnets           = $existingSubnets
        parDevLbPipExists            = $pipExists['dev']
        parProdLbPipExists           = $pipExists['prod']
    }

    $deployParams = @{
        Name                    = $deploymentName
        Location                = $Location
        TemplateFile            = $mainBicep
        TemplateParameterObject = $params
        ErrorAction             = 'Stop'
    }

    if ($WhatIf) {
        Write-Host "  Running in what-if mode (dry run)..." -ForegroundColor Cyan
        Get-AzSubscriptionDeploymentWhatIfResult @deployParams
        Write-Host "`n  What-if completed. Review the changes above - nothing was deployed." -ForegroundColor Cyan
        exit 0
    }

    $deployment = New-AzSubscriptionDeployment @deployParams -Verbose

    if ($deployment.ProvisioningState -eq 'Succeeded') {
        Write-Host "`n[SUCCESS] Deployment completed successfully!" -ForegroundColor Green
        Write-Host "`nDeployment Outputs:" -ForegroundColor Cyan
        $deployment.Outputs | Format-Table -AutoSize
    }
    else {
        Write-Host "`n[FAILED] Deployment failed with state: $($deployment.ProvisioningState)" -ForegroundColor Red
        if ($deployment.Error) {
            Write-Host "Error Code: $($deployment.Error.Code)" -ForegroundColor Red
            Write-Host "Error Message: $($deployment.Error.Message)" -ForegroundColor Red
            Write-Host "Error Target: $($deployment.Error.Target)" -ForegroundColor Red
            if ($deployment.Error.Details) {
                foreach ($detail in $deployment.Error.Details) {
                    Write-Host "  - Detail Code: $($detail.Code)" -ForegroundColor Red
                    Write-Host "  - Detail Message: $($detail.Message)" -ForegroundColor Red
                }
            }
        }

        # Get operations
        $ops = Get-AzSubscriptionDeploymentOperation -DeploymentName $deploymentName
        $failedOps = $ops | Where-Object { $_.ProvisioningState -eq "Failed" }
        foreach ($op in $failedOps) {
            Write-Host "Failed Operation: $($op.Properties.TargetResource.ResourceName)" -ForegroundColor Yellow
            Write-Host "Status Message: $($op.Properties.StatusMessage)" -ForegroundColor Red
        }
        $Host.SetShouldExit(1)
        exit 1
    }
}
catch {
    Write-Host "`n[ERROR] Deployment failed with exception:" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    $Host.SetShouldExit(1)
    exit 1
}

Write-Host "`nNext Step: Run .\Test-Lab.ps1 to verify the configuration." -ForegroundColor Yellow
