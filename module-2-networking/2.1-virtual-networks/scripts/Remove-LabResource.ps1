<#
.SYNOPSIS
    Cleans up resources created in Lab 2.1.

.DESCRIPTION
    This script removes the Hub and Spoke Virtual Networks (Dev/Prod), their peering
    configurations, and Public IPs. It prompts for confirmation unless the -Force switch is used.

    A resource that is genuinely absent is reported as [INFO] and is not an error. A resource
    that exists but cannot be deleted is reported as [ERROR] with the Azure error message, and
    the script exits 1 - so a masked failure cannot be mistaken for a clean cleanup.

    A lookup that fails with an error (a 403, throttling, a transient ARM error) is counted the
    same way: it cannot tell whether the resource is gone, so it is reported as [ERROR] and the
    resource is left alone. Only a lookup that succeeds and finds nothing, or a getter that
    reports the resource as not found, means "absent" - Test-LabNotFoundError tells the two apart
    (issue #255, as #238 did for Lab 5.2).

    Before anything is deleted, a preflight lists the service association links carried by the
    subnets of every lab VNet and reports whether the resource each one names still exists. A
    lab VNet about to be torn down should carry none; a link whose target is gone is an orphan
    that no lab can remove, and it is what makes Remove-AzVirtualNetwork fail with
    InUseSubnetCannotBeDeleted (issue #110). The preflight only reports - it never fails the
    run on its own, so the exit code still reflects what the deletes actually did. A
    preflight lookup that fails is reported as [WARN] and left to the delete steps, which look the
    VNet up again and count a failure there; a link target that could not be looked up is
    reported as unverified, never as orphaned.

.PARAMETER Force
    Skip the confirmation prompt.

.EXAMPLE
    .\Remove-LabResource.ps1
    Prompts for confirmation before deleting resources.

.EXAMPLE
    .\Remove-LabResource.ps1 -Force
    Deletes resources without prompting.

.NOTES
    Project: SkyCraft
    Lab: 2.1 - Virtual Networks
    Author: Marcin Biszczanik
    Version: 2.3.0
    Date: 2026-10-10
#>

#Requires -Version 7.0
#Requires -Modules Az.Accounts, Az.Network, Az.Resources

[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory = $false)]
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
if ($Force) { $ConfirmPreference = 'None' }

Write-Host "=== Lab 2.1 - Resource Cleanup ===" -ForegroundColor Cyan -BackgroundColor Black

# Verify Azure Connection
$context = Get-AzContext
if (-not $context) {
    Write-Host "Not logged in. Please run Connect-AzAccount" -ForegroundColor Red
    $Host.SetShouldExit(1)
    exit 1
}

$hubRgName = "platform-skycraft-swc-rg"
$hubVnetName = "platform-skycraft-swc-vnet"

$devRgName = "dev-skycraft-swc-rg"
$devVnetName = "dev-skycraft-swc-vnet"

$prodRgName = "prod-skycraft-swc-rg"
$prodVnetName = "prod-skycraft-swc-vnet"

# Counts lookups that failed and resources that exist but could not be deleted. Absent
# resources are not failures.
$script:cleanupFailures = 0

$labVnets = @(
    @{ Name = $hubVnetName; Rg = $hubRgName },
    @{ Name = $devVnetName; Rg = $devRgName },
    @{ Name = $prodVnetName; Rg = $prodRgName }
)

# Whether a lookup's error says the resource does not exist, rather than that the lookup failed.
# Get-AzVirtualNetwork, Get-AzPublicIpAddress and Get-AzResource -ResourceId report a missing
# resource as an ARM 404: "The Resource '<type>/<name>' under resource group '<rg>' was not
# found.", code ResourceNotFound; when the group is gone as well, "Resource group '<rg>' could not
# be found.", code ResourceGroupNotFound; with no error body, "Operation returned an invalid status
# code 'NotFound'". The code and the status travel in the message and in Body and Response; the
# Azure.Core clients say "Status: 404 (Not Found)". A missing subscription is a 404 too, but it
# means the context is wrong, not that the resource is gone, so it never reads as "absent".
function Test-LabNotFoundError {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [System.Management.Automation.ErrorRecord]$ErrorRecord
    )

    $evidence = [System.Collections.Generic.List[string]]::new()
    $evidence.Add([string]$ErrorRecord)
    $evidence.Add([string]$ErrorRecord.FullyQualifiedErrorId)
    $status404 = $false
    for ($exception = $ErrorRecord.Exception; $exception; $exception = $exception.InnerException) {
        $evidence.Add([string]$exception.Message)
        foreach ($code in @($exception.Body.Code, $exception.Body.Error.Code, $exception.ErrorCode)) {
            if ($code) { $evidence.Add([string]$code) }
        }
        # ResponseStatusCode: the generated cmdlets' RestException, which may carry no error body.
        foreach ($status in @($exception.Response.StatusCode, $exception.ResponseStatusCode, $exception.Status)) {
            if ("$status" -in @('404', 'NotFound')) { $status404 = $true }
        }
    }
    $text = $evidence -join "`n"

    if ($text -match 'SubscriptionNotFound|subscription .{0,80}(could not be|was not) found') { return $false }
    if ($status404) { return $true }
    return $text -match '\bResource(Group)?NotFound\b|was not found|Resource group .{0,100}could not be found|invalid status code ''NotFound''|\b404 \(Not Found\)'
}

# Runs one lookup with -ErrorAction Stop inside $Lookup, and returns what it found:
#   Value     the lookup's output, as an array - empty when the resource is absent
#   NotFound  the getter reported the resource as not found (Test-LabNotFoundError)
#   Failed    the lookup failed any other way: it is reported as [ERROR] and counted, because it
#             cannot tell whether the resource is gone, and the caller leaves the resource alone
function Invoke-LabLookup {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Target,

        [Parameter(Mandatory = $true)]
        [scriptblock]$Lookup
    )

    try {
        $value = @(& $Lookup)
        return [pscustomobject]@{ Value = $value; NotFound = $false; Failed = $false }
    } catch {
        if (Test-LabNotFoundError -ErrorRecord $_) {
            return [pscustomobject]@{ Value = @(); NotFound = $true; Failed = $false }
        }
        $script:cleanupFailures++
        Write-Host "  - [ERROR] Could not look up $($Target): $_" -ForegroundColor Red
        Write-Host "    A failed lookup is not 'absent': it may still exist, so this counts as a failure." -ForegroundColor Gray
        return [pscustomobject]@{ Value = @(); NotFound = $false; Failed = $true }
    }
}

function Get-SubnetServiceLink {
    <#
    .SYNOPSIS
        Lists every service association link carried by the subnets of a VNet.

    .DESCRIPTION
        Flattens $Vnet.Subnets[].ServiceAssociationLinks into one finding per link so the caller
        can report them without walking the object graph again.

        Emits one finding per link and nothing at all when the VNet is $null, carries no
        subnets, or carries no links. Callers wrap the call in @() before reading .Count:
        an internal unary-comma wrapper would make @(Get-SubnetServiceLink ...) report 1 for
        every result, empty ones included.

    .NOTES
        Internal helper for Remove-LabResource.ps1 (issue #110).
    #>
    [CmdletBinding()]
    [OutputType([System.Object[]])]
    param(
        [Parameter(Mandatory)][AllowNull()]$Vnet
    )

    $findings = @()
    if (-not $Vnet) { return $findings }

    foreach ($subnet in @($Vnet.Subnets)) {
        if (-not $subnet) { continue }
        foreach ($link in @($subnet.ServiceAssociationLinks)) {
            if (-not $link) { continue }
            $findings += [PSCustomObject]@{
                VnetName         = $Vnet.Name
                SubnetName       = $subnet.Name
                LinkName         = $link.Name
                LinkedResourceId = $link.Link
                AllowDelete      = [bool]$link.AllowDelete
            }
        }
    }

    return $findings
}

function Format-ServiceLinkFinding {
    <#
    .SYNOPSIS
        Renders one service association link finding as a single report line.

    .DESCRIPTION
        Kept separate from the Azure lookup so the wording can be checked without a subscription.

        $LinkedResourceExists is $true when the resource the link names still resolves, $false
        when it does not - a true orphan, which is the case that blocks the VNet delete - and
        $null when it could not be determined.

    .NOTES
        Internal helper for Remove-LabResource.ps1 (issue #110).
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]$Link,
        [Parameter(Mandatory)][AllowNull()][object]$LinkedResourceExists
    )

    $state = if ($null -eq $LinkedResourceExists) { 'target unverified' }
    elseif ($LinkedResourceExists) { 'target still exists' }
    else { 'ORPHANED - target no longer exists' }

    return "$($Link.VnetName)/$($Link.SubnetName) carries serviceAssociationLink '$($Link.LinkName)' -> $($Link.LinkedResourceId) ($state, allowDelete=$($Link.AllowDelete))"
}

# Preflight. Diagnostic only - it never touches $script:cleanupFailures, so a reported link
# cannot turn an otherwise clean run red, and a delete that then fails still reports itself. For
# the same reason its lookups do not go through Invoke-LabLookup, which counts: a VNet it could not
# look up is looked up again, and counted, by the delete steps below.
Write-Host "`nPreflight: service association links on lab subnets..." -ForegroundColor Cyan
$orphanedLinkCount = 0

foreach ($lab in $labVnets) {
    $preflightVnet = $null
    try {
        $preflightVnet = Get-AzVirtualNetwork -Name $lab.Name -ResourceGroupName $lab.Rg -ErrorAction Stop
    } catch {
        if (-not (Test-LabNotFoundError -ErrorRecord $_)) {
            Write-Host "  - [WARN] VNet $($lab.Name) could not be looked up - not checked: $_" -ForegroundColor Yellow
            continue
        }
    }
    if (-not $preflightVnet) {
        Write-Host "  - [INFO] VNet $($lab.Name) not found - nothing to check." -ForegroundColor Gray
        continue
    }

    $links = @(Get-SubnetServiceLink -Vnet $preflightVnet)
    if ($links.Count -eq 0) {
        Write-Host "  - [OK] $($lab.Name) carries no service association links." -ForegroundColor Green
        continue
    }

    foreach ($link in $links) {
        # Only a lookup that reports the target as not found proves it gone; any other failure
        # leaves it unverified, rather than calling a link whose target may still exist an orphan.
        $targetExists = $null
        try {
            $targetExists = [bool](Get-AzResource -ResourceId $link.LinkedResourceId -ErrorAction Stop)
        } catch {
            $targetExists = if (Test-LabNotFoundError -ErrorRecord $_) { $false } else { $null }
        }

        if ($targetExists -eq $false) { $orphanedLinkCount++ }
        Write-Host "  - [WARN] $(Format-ServiceLinkFinding -Link $link -LinkedResourceExists $targetExists)" -ForegroundColor Yellow
    }
}

if ($orphanedLinkCount -gt 0) {
    Write-Host "  -> $orphanedLinkCount orphaned link(s). The VNet delete below will fail with" -ForegroundColor Yellow
    Write-Host "     InUseSubnetCannotBeDeleted until the owning resource provider releases them." -ForegroundColor Yellow
    Write-Host "     Remediation: issue #110." -ForegroundColor Yellow
}

Write-Host "`nStarting cleanup..." -ForegroundColor Cyan

# Each VNet is looked up once, here, and the result serves both steps below. A VNet that could not
# be looked up is one [ERROR], counted by Invoke-LabLookup, and neither its peerings nor the VNet
# itself are touched (#255).
$vnetLookups = @{}
foreach ($lab in $labVnets) {
    $vnetLookups[$lab.Name] = Invoke-LabLookup -Target "VNet $($lab.Name)" -Lookup {
        Get-AzVirtualNetwork -Name $lab.Name -ResourceGroupName $lab.Rg -ErrorAction Stop
    }
}

# Function to remove peerings
function Remove-VNetPeering {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param($VnetName, $RgName, $Lookup)
    Write-Host "Removing peerings on $VnetName..." -ForegroundColor Yellow
    $vnet = $Lookup.Value | Select-Object -First 1
    try {
        if ($vnet) {
            # No name filter: SkyCraft peerings are named hub-to-dev / dev-to-hub etc., and every peering
            # on a lab VNet is lab state. Leaving the spoke side behind is what caused
            # RemotePeeringIsDisconnected on the next Lab 2.1 deployment during the #87 live cycle.
            $peerings = $vnet.VirtualNetworkPeerings
            foreach ($p in $peerings) {
                if ($PSCmdlet.ShouldProcess("$VnetName/$($p.Name)", 'Remove VNet peering')) {
                    Write-Host "  -> Deleting $($p.Name)" -ForegroundColor Gray
                    Remove-AzVirtualNetworkPeering -VirtualNetworkName $VnetName -ResourceGroupName $RgName -Name $p.Name -Force -ErrorAction Stop
                }
            }
        }
    } catch {
        $script:cleanupFailures++
        Write-Host "  - [ERROR] Failed to remove peering on ${VnetName}: $($_.Exception.Message)" -ForegroundColor Red
    }
}

Remove-VNetPeering -VnetName $hubVnetName -RgName $hubRgName -Lookup $vnetLookups[$hubVnetName]
Remove-VNetPeering -VnetName $devVnetName -RgName $devRgName -Lookup $vnetLookups[$devVnetName]
Remove-VNetPeering -VnetName $prodVnetName -RgName $prodRgName -Lookup $vnetLookups[$prodVnetName]

# Function to remove VNet
function Remove-VNet {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param($VnetName, $RgName, $Lookup)

    # Probe first. A bare catch reported every failure as "not found or already deleted", which
    # hid a real InUseSubnetCannotBeDeleted on the prod VNet during the #93 live cycle (#96). The
    # probe is the lookup made before the peerings were removed. One that failed is no proof of
    # absence either (#255): it was counted there, and the VNet is left alone.
    if ($Lookup.Failed) { return }
    $vnet = $Lookup.Value | Select-Object -First 1
    if (-not $vnet) {
        Write-Host "  - [INFO] VNet $VnetName not found or already deleted." -ForegroundColor Gray
        return
    }

    try {
        Write-Host "Removing VNet: $VnetName..." -ForegroundColor Yellow
        if ($PSCmdlet.ShouldProcess($VnetName, 'Remove virtual network')) {
            Remove-AzVirtualNetwork -Name $VnetName -ResourceGroupName $RgName -Force -ErrorAction Stop
            Write-Host "  -> Success" -ForegroundColor Green
        }
    } catch {
        $script:cleanupFailures++
        Write-Host "  - [ERROR] Failed to remove VNet ${VnetName}: $($_.Exception.Message)" -ForegroundColor Red
    }
}

Remove-VNet -VnetName $hubVnetName -RgName $hubRgName -Lookup $vnetLookups[$hubVnetName]
Remove-VNet -VnetName $devVnetName -RgName $devRgName -Lookup $vnetLookups[$devVnetName]
Remove-VNet -VnetName $prodVnetName -RgName $prodRgName -Lookup $vnetLookups[$prodVnetName]

# Check for and remove PIPs
$pips = @(
    @{"Name"="dev-skycraft-swc-lb-pip"; "RG"=$devRgName},
    @{"Name"="prod-skycraft-swc-lb-pip"; "RG"=$prodRgName}
)

foreach ($pip in $pips) {
    $pipLookup = Invoke-LabLookup -Target "PIP $($pip.Name)" -Lookup {
        Get-AzPublicIpAddress -Name $pip.Name -ResourceGroupName $pip.RG -ErrorAction Stop
    }
    if ($pipLookup.Failed) { continue }
    if ($pipLookup.Value.Count -eq 0) {
        Write-Host "  - [INFO] PIP $($pip.Name) not found or already deleted." -ForegroundColor Gray
        continue
    }

    try {
        Write-Host "Removing Public IP: $($pip.Name)..." -ForegroundColor Yellow
        if ($PSCmdlet.ShouldProcess($pip.Name, 'Remove public IP address')) {
            Remove-AzPublicIpAddress -Name $pip.Name -ResourceGroupName $pip.RG -Force -ErrorAction Stop
            Write-Host "  -> Success" -ForegroundColor Green
        }
    } catch {
        $script:cleanupFailures++
        Write-Host "  - [ERROR] Failed to remove PIP $($pip.Name): $($_.Exception.Message)" -ForegroundColor Red
    }
}

if ($script:cleanupFailures -gt 0) {
    Write-Host "`nCleanup finished with $($script:cleanupFailures) failure(s) - see the [ERROR] lines above." -ForegroundColor Red
    $Host.SetShouldExit(1)
    exit 1
}

Write-Host "`nCleanup Complete." -ForegroundColor Green
