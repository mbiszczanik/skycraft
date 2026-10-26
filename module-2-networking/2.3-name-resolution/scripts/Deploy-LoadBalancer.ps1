<#
.SYNOPSIS
    Deploys Lab 2.3 Load Balancer resources using native PowerShell cmdlets.

.DESCRIPTION
    Tasks performed:
    1. Deploy Standard Public Load Balancer for Dev.
    2. Deploy Standard Public Load Balancer for Prod.
    3. Configure Backend Pools (world, auth and the egress pool 'be-outbound'), Health Probes,
       and Load Balancing Rules (outbound SNAT disabled on the rules, which Azure requires once
       an outbound rule uses the frontend IP).
    4. Configure one Outbound Rule for the egress pool (protocol All, 8000 ports per instance) -
       the Module 3 VMs' only path to the internet, since the Lab 2.1 subnets are private. A
       frontend IP takes only one outbound rule with an overlapping protocol, so Lab 3.2 puts
       every VM NIC into 'be-outbound' besides its role pool.

.PARAMETER Owner
    Value of the canonical Owner tag. Default: 'mbiszczanik'. Mirrors parOwner in the Bicep path.

.NOTES
    Project: SkyCraft
    Lab: 2.3 - Name Resolution & Load Balancing
    Author: Marcin Biszczanik
    Date: 2026-01-11
#>

#Requires -Version 7.0
#Requires -Modules Az.Accounts, Az.Network

[CmdletBinding()]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Deploy script; idempotent Get-before-New guards cover ShouldProcess intent.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Location', Justification = 'Consumed inside New-SkyCraftLB via parent-scope resolution; PSSA nested-scope false positive.')]
param(
    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$Owner = 'mbiszczanik',

    [Parameter(Mandatory = $false)]
    [ValidateSet('swedencentral', 'northeurope')]
    [string]$Location = 'swedencentral',

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$DevRG = 'dev-skycraft-swc-rg',

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$ProdRG = 'prod-skycraft-swc-rg',

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$DevLbName = 'dev-skycraft-swc-lb',

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$ProdLbName = 'prod-skycraft-swc-lb',

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$DevPipName = 'dev-skycraft-swc-lb-pip',

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$ProdPipName = 'prod-skycraft-swc-lb-pip'
)

$ErrorActionPreference = 'Stop'
# Exit-Lab ends the script with exit code 0 or 1 and leaves an interactive session open (#257).
Import-Module (Join-Path $PSScriptRoot '../../../tools/LabCommon.psm1') -Force -Verbose:$false

Write-Host "=== Lab 2.3 - Deploy Load Balancers (PowerShell) ===" -ForegroundColor Cyan -BackgroundColor Black

# 1. Verify Azure Connection
$context = Get-AzContext
if (-not $context) {
    Write-Host "Not logged in. Please run Connect-AzAccount" -ForegroundColor Red
    Exit-Lab -FailureCount 1
}

$Tags = @{
    Project     = 'SkyCraft'
    CostCenter  = 'MSDN'
    Owner       = $Owner
}

function New-SkyCraftLB {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Internal helper; parent script guards idempotency via Get-before-New.')]
    param (
        [string]$ResourceGroupName,
        [string]$LbName,
        [string]$PipName,
        [string]$Environment
    )

    Write-Host "`n--- Deploying Load Balancer: $LbName ($Environment) ---" -ForegroundColor Cyan
    
    $lbTags = $Tags.Clone()
    $lbTags['Environment'] = $Environment

    # Check for existing LB
    $existingLb = Get-AzLoadBalancer -ResourceGroupName $ResourceGroupName -Name $LbName -ErrorAction SilentlyContinue
    if ($existingLb) {
        Write-Host "  -> Load Balancer already exists. Updating..." -ForegroundColor Gray
    }

    # Get or Create Public IP
    $pip = Get-AzPublicIpAddress -ResourceGroupName $ResourceGroupName -Name $PipName -ErrorAction SilentlyContinue
    if (-not $pip) {
        Write-Host "  -> Public IP '$PipName' not found. Creating..." -ForegroundColor Yellow
        $pip = New-AzPublicIpAddress -ResourceGroupName $ResourceGroupName -Name $PipName -Location $Location -Sku Standard -AllocationMethod Static -Force
        Write-Host "  -> Created Public IP: $PipName" -ForegroundColor Green
    } else {
        Write-Host "  -> Public IP found: $PipName" -ForegroundColor Gray
    }

    # Create Frontend IP Config
    $frontendName = "$LbName-frontend"
    $feIp = New-AzLoadBalancerFrontendIpConfig -Name $frontendName -PublicIpAddress $pip

    # Create Backend Pools
    $bePoolWorld = New-AzLoadBalancerBackendAddressPoolConfig -Name "$LbName-be-world"
    $bePoolAuth = New-AzLoadBalancerBackendAddressPoolConfig -Name "$LbName-be-auth"
    $bePoolOutbound = New-AzLoadBalancerBackendAddressPoolConfig -Name "$LbName-be-outbound"

    # Create Health Probes
    $probeWorld = New-AzLoadBalancerProbeConfig -Name "$LbName-probe-world" -Protocol Tcp -Port 8085 -IntervalInSeconds 15 -ProbeCount 2 -ProbeThreshold 1
    $probeAuth = New-AzLoadBalancerProbeConfig -Name "$LbName-probe-auth" -Protocol Tcp -Port 3724 -IntervalInSeconds 15 -ProbeCount 2 -ProbeThreshold 1

    # Create Load Balancing Rules
    # Outbound SNAT is disabled on the rules: egress comes from the outbound rule below, and Azure
    # refuses SNAT on a rule whose frontend IP an outbound rule uses.
    $ruleWorld = New-AzLoadBalancerRuleConfig -Name "$LbName-rule-world" -FrontendIpConfiguration $feIp -BackendAddressPool $bePoolWorld -Probe $probeWorld -Protocol Tcp -FrontendPort 8085 -BackendPort 8085 -IdleTimeoutInMinutes 4 -EnableTcpReset -DisableOutboundSNAT
    $ruleAuth = New-AzLoadBalancerRuleConfig -Name "$LbName-rule-auth" -FrontendIpConfiguration $feIp -BackendAddressPool $bePoolAuth -Probe $probeAuth -Protocol Tcp -FrontendPort 3724 -BackendPort 3724 -IdleTimeoutInMinutes 4 -EnableTcpReset -DisableOutboundSNAT

    # Create the Outbound Rule - one per frontend IP (a second one with an overlapping protocol is
    # refused), for the egress pool, with manual port allocation: the frontend offers 63,984
    # ports, so 8000 per instance admits 7 instances (Module 3 puts at most 2 VMs here).
    $outbound = New-AzLoadBalancerOutboundRuleConfig -Name "$LbName-outbound" -FrontendIpConfiguration $feIp -BackendAddressPool $bePoolOutbound -Protocol All -IdleTimeoutInMinutes 4 -EnableTcpReset -AllocatedOutboundPort 8000

    # Create/Update Load Balancer
    if ($existingLb) {
        # Update existing object logic is complex with pure objects, easiest is to recreate config
        # Or Set-AzLoadBalancer if we modify the object. 
        # For simple labs, New-AzLoadBalancer overwrites/updates.
        New-AzLoadBalancer -ResourceGroupName $ResourceGroupName -Name $LbName -Location $Location -Sku Standard -LoadBalancingRule $ruleWorld, $ruleAuth -FrontendIpConfiguration $feIp -BackendAddressPool $bePoolWorld, $bePoolAuth, $bePoolOutbound -Probe $probeWorld, $probeAuth -OutboundRule $outbound -Tag $lbTags -Force | Out-Null
        Write-Host "  -> Load Balancer updated successfully." -ForegroundColor Green
    } else {
        New-AzLoadBalancer -ResourceGroupName $ResourceGroupName -Name $LbName -Location $Location -Sku Standard -LoadBalancingRule $ruleWorld, $ruleAuth -FrontendIpConfiguration $feIp -BackendAddressPool $bePoolWorld, $bePoolAuth, $bePoolOutbound -Probe $probeWorld, $probeAuth -OutboundRule $outbound -Tag $lbTags -Force | Out-Null
        Write-Host "  -> Load Balancer created successfully." -ForegroundColor Green
    }
}

# Deploy Dev LB
New-SkyCraftLB -ResourceGroupName $DevRG -LbName $DevLbName -PipName $DevPipName -Environment 'Development'

# Deploy Prod LB
New-SkyCraftLB -ResourceGroupName $ProdRG -LbName $ProdLbName -PipName $ProdPipName -Environment 'Production'

# Cleanup temp artifact
if (Test-Path "lb.json") { Remove-Item "lb.json" }

Write-Host "`n=== Load Balancer Deployment Complete ===" -ForegroundColor Cyan -BackgroundColor Black
Exit-Lab -FailureCount 0
