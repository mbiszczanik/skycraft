<#
.SYNOPSIS
    Deploys Lab 2.3 Load Balancer resources using native PowerShell cmdlets.

.DESCRIPTION
    Tasks performed:
    1. Deploy Standard Public Load Balancer for Dev.
    2. Deploy Standard Public Load Balancer for Prod.
    3. Configure Backend Pools, Health Probes, and Rules.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$Location = 'swedencentral',

    [Parameter(Mandatory = $false)]
    [string]$DevRG = 'dev-skycraft-swc-rg',

    [Parameter(Mandatory = $false)]
    [string]$ProdRG = 'prod-skycraft-swc-rg',

    [Parameter(Mandatory = $false)]
    [string]$DevLbName = 'dev-skycraft-swc-lb',

    [Parameter(Mandatory = $false)]
    [string]$ProdLbName = 'prod-skycraft-swc-lb',

    [Parameter(Mandatory = $false)]
    [string]$DevPipName = 'dev-skycraft-swc-lb-pip',

    [Parameter(Mandatory = $false)]
    [string]$ProdPipName = 'prod-skycraft-swc-lb-pip'
)

Write-Host "=== Lab 2.3 - Deploy Load Balancers (PowerShell) ===" -ForegroundColor Cyan -BackgroundColor Black

# 1. Verify Azure Connection
$context = Get-AzContext
if (-not $context) {
    Write-Host "Not logged in. Please run Connect-AzAccount" -ForegroundColor Red
    exit 1
}

$Tags = @{
    Project     = 'SkyCraft'
    CostCenter  = 'MSDN'
}

function New-SkyCraftLB {
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

    # Create Health Probes
    $probeWorld = New-AzLoadBalancerProbeConfig -Name "$LbName-probe-world" -Protocol Tcp -Port 8085 -IntervalInSeconds 15 -ProbeCount 2
    $probeAuth = New-AzLoadBalancerProbeConfig -Name "$LbName-probe-auth" -Protocol Tcp -Port 3724 -IntervalInSeconds 15 -ProbeCount 2

    # Create Load Balancing Rules
    $ruleWorld = New-AzLoadBalancerRuleConfig -Name "$LbName-rule-world" -FrontendIpConfiguration $feIp -BackendAddressPool $bePoolWorld -Probe $probeWorld -Protocol Tcp -FrontendPort 8085 -BackendPort 8085 -IdleTimeoutInMinutes 4 -EnableTcpReset
    $ruleAuth = New-AzLoadBalancerRuleConfig -Name "$LbName-rule-auth" -FrontendIpConfiguration $feIp -BackendAddressPool $bePoolAuth -Probe $probeAuth -Protocol Tcp -FrontendPort 3724 -BackendPort 3724 -IdleTimeoutInMinutes 4 -EnableTcpReset

    # Create/Update Load Balancer
    if ($existingLb) {
        # Update existing object logic is complex with pure objects, easiest is to recreate config
        # Or Set-AzLoadBalancer if we modify the object. 
        # For simple labs, New-AzLoadBalancer overwrites/updates.
        New-AzLoadBalancer -ResourceGroupName $ResourceGroupName -Name $LbName -Location $Location -Sku Standard -LoadBalancingRule $ruleWorld, $ruleAuth -FrontendIpConfiguration $feIp -BackendAddressPool $bePoolWorld, $bePoolAuth -Probe $probeWorld, $probeAuth -Tag $lbTags -Force | Out-Null
        Write-Host "  -> Load Balancer updated successfully." -ForegroundColor Green
    } else {
        New-AzLoadBalancer -ResourceGroupName $ResourceGroupName -Name $LbName -Location $Location -Sku Standard -LoadBalancingRule $ruleWorld, $ruleAuth -FrontendIpConfiguration $feIp -BackendAddressPool $bePoolWorld, $bePoolAuth -Probe $probeWorld, $probeAuth -Tag $lbTags -Force | Out-Null
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
