<#
.SYNOPSIS
    Removes Lab 2.3 DNS zones, VNet links, and dev/prod load balancers.

.DESCRIPTION
    Cleanup script for Lab 2.3. Removes resources in the safe order: public DNS zone,
    both load balancers, private DNS VNet links, private DNS zone. Each removal is
    guarded by a Get-* existence check so the script is idempotent and can be re-run.

    Private DNS VNet link deletion is asynchronous: Remove-AzPrivateDnsVirtualNetworkLink
    returns before ARM has released the link, and deleting the zone too early fails with
    "Cannot delete resource while nested resources exist". The zone deletion is retried on
    that specific error until the links have drained.

    Every step continues on error, so one stuck resource does not strand the rest. A lookup that
    fails (a 403, throttling, a transient ARM error) or a deletion that fails is reported as
    [ERROR] and counted; if anything failed the script exits 1. A resource that does not exist is
    not a failure: only a lookup that succeeds and does not find it, or a getter that reports it
    as not found, means "absent" - Test-LabNotFoundError tells the two apart (issue #255, as #238
    did for Lab 5.2). The private DNS zone stays when its VNet links could not be listed or
    removed: its delete could only fail on the nested links, after a minute of retries.

    Each non-zero exit is paired with $Host.SetShouldExit: a bare "exit 1" is dropped under
    "pwsh -File" for any script that declares #Requires -Modules for a module it has to
    auto-import, and the process would exit 0 with the failure still on screen (issue #104).

.PARAMETER PublicDnsZoneName
    Public DNS zone to delete. Defaults to 'skycraft.example.com'.

.PARAMETER PrivateDnsZoneName
    Private DNS zone to delete. Defaults to 'skycraft.internal'.

.PARAMETER PlatformRG
    Resource group that hosts the DNS zones. Defaults to 'platform-skycraft-swc-rg'.

.PARAMETER DevRG
    Resource group that hosts the dev load balancer. Defaults to 'dev-skycraft-swc-rg'.

.PARAMETER ProdRG
    Resource group that hosts the prod load balancer. Defaults to 'prod-skycraft-swc-rg'.

.PARAMETER DevLbName
    Name of the dev load balancer. Defaults to 'dev-skycraft-swc-lb'.

.PARAMETER ProdLbName
    Name of the prod load balancer. Defaults to 'prod-skycraft-swc-lb'.

.PARAMETER Force
    Skips the confirmation prompt before removing resources.

.EXAMPLE
    .\Remove-LabResource.ps1
    Removes all Lab 2.3 DNS and load balancer resources using the default names.

.NOTES
    Project: SkyCraft
    Lab: 2.3 - Name Resolution & Load Balancing
    Author: Marcin Biszczanik
    Version: 2.2.0
    Date: 2026-10-10
#>

#Requires -Version 7.0
#Requires -Modules Az.Accounts, Az.Dns, Az.Network

[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$PublicDnsZoneName = 'skycraft.example.com',

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$PrivateDnsZoneName = 'skycraft.internal',

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$PlatformRG = 'platform-skycraft-swc-rg',

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

    [switch]$Force
)

$ErrorActionPreference = 'Stop'
if ($Force) { $ConfirmPreference = 'None' }

# Counts lookups that failed and resources that exist but could not be deleted. Absent resources
# are not failures.
$script:cleanupFailures = 0
# Set when the private zone's VNet links could not be listed or one could not be removed; the
# zone then stays (step 4).
$script:privateZoneMustStay = $false

# Whether a lookup's error says the resource does not exist, rather than that the lookup failed.
# Get-AzDnsZone, Get-AzLoadBalancer, Get-AzPrivateDnsZone and Get-AzPrivateDnsVirtualNetworkLink
# (whose zone may be gone) report a missing resource as an ARM 404: "The Resource '<type>/<name>'
# under resource group '<rg>' was not found.", code ResourceNotFound; when the group is gone as
# well, "Resource group '<rg>' could not be found.", code ResourceGroupNotFound; with no error
# body, "Operation returned an invalid status code 'NotFound'". The code and the status travel in
# the message and in Body and Response; the Azure.Core clients say "Status: 404 (Not Found)". A
# missing subscription is a 404 too, but it means the context is wrong, not that the resource is
# gone, so it never reads as "absent".
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
    }
    catch {
        if (Test-LabNotFoundError -ErrorRecord $_) {
            return [pscustomobject]@{ Value = @(); NotFound = $true; Failed = $false }
        }
        $script:cleanupFailures++
        Write-Host "  -> [ERROR] Could not look up $($Target): $_" -ForegroundColor Red
        Write-Host "     A failed lookup is not 'absent': it may still exist, so this counts as a failure." -ForegroundColor Gray
        return [pscustomobject]@{ Value = @(); NotFound = $false; Failed = $true }
    }
}

Write-Host "=== Lab 2.3 Cleanup Script ===" -ForegroundColor Cyan -BackgroundColor Black

# 1. Verify Azure Connection
$context = Get-AzContext
if (-not $context) {
    Write-Host "Not logged in. Please run Connect-AzAccount" -ForegroundColor Red
    $Host.SetShouldExit(1)
    exit 1
}

# 2. Cleanup Public DNS
Write-Host "`n=== Cleaning up Public DNS ===" -ForegroundColor Cyan
$publicZoneLookup = Invoke-LabLookup -Target "public DNS zone $PublicDnsZoneName" -Lookup {
    Get-AzDnsZone -ResourceGroupName $PlatformRG -Name $PublicDnsZoneName -ErrorAction Stop
}
if ($publicZoneLookup.Value.Count -gt 0) {
    if ($PSCmdlet.ShouldProcess($PublicDnsZoneName, 'Remove public DNS zone')) {
        Write-Host "Removing Public DNS Zone: $PublicDnsZoneName..." -ForegroundColor Yellow
        try {
            Remove-AzDnsZone -ResourceGroupName $PlatformRG -Name $PublicDnsZoneName -Confirm:$false -ErrorAction Stop
            Write-Host "  -> Deleted" -ForegroundColor Green
        }
        catch {
            $script:cleanupFailures++
            Write-Host "  -> [ERROR] Could not delete the public DNS zone: $_" -ForegroundColor Red
        }
    }
} elseif (-not $publicZoneLookup.Failed) {
    Write-Host "  -> Public Zone not found" -ForegroundColor Gray
}

# 3. Cleanup Load Balancers
Write-Host "`n=== Cleaning up Load Balancers ===" -ForegroundColor Cyan

# Dev LB
$devLbLookup = Invoke-LabLookup -Target "load balancer $DevLbName" -Lookup {
    Get-AzLoadBalancer -ResourceGroupName $DevRG -Name $DevLbName -ErrorAction Stop
}
if ($devLbLookup.Value.Count -gt 0) {
    if ($PSCmdlet.ShouldProcess($DevLbName, 'Remove load balancer')) {
        Write-Host "Removing Dev Load Balancer: $DevLbName..." -ForegroundColor Yellow
        try {
            Remove-AzLoadBalancer -ResourceGroupName $DevRG -Name $DevLbName -Force -ErrorAction Stop
            Write-Host "  -> Deleted" -ForegroundColor Green
        }
        catch {
            $script:cleanupFailures++
            Write-Host "  -> [ERROR] Could not delete load balancer ${DevLbName}: $_" -ForegroundColor Red
        }
    }
} elseif (-not $devLbLookup.Failed) {
    Write-Host "  -> Dev LB not found" -ForegroundColor Gray
}

# Prod LB
$prodLbLookup = Invoke-LabLookup -Target "load balancer $ProdLbName" -Lookup {
    Get-AzLoadBalancer -ResourceGroupName $ProdRG -Name $ProdLbName -ErrorAction Stop
}
if ($prodLbLookup.Value.Count -gt 0) {
    if ($PSCmdlet.ShouldProcess($ProdLbName, 'Remove load balancer')) {
        Write-Host "Removing Prod Load Balancer: $ProdLbName..." -ForegroundColor Yellow
        try {
            Remove-AzLoadBalancer -ResourceGroupName $ProdRG -Name $ProdLbName -Force -ErrorAction Stop
            Write-Host "  -> Deleted" -ForegroundColor Green
        }
        catch {
            $script:cleanupFailures++
            Write-Host "  -> [ERROR] Could not delete load balancer ${ProdLbName}: $_" -ForegroundColor Red
        }
    }
} elseif (-not $prodLbLookup.Failed) {
    Write-Host "  -> Prod LB not found" -ForegroundColor Gray
}

# 4. Cleanup Private DNS Links & Zone
Write-Host "`n=== Cleaning up Private DNS ===" -ForegroundColor Cyan

# Links. A zone whose links could not be listed or removed stays (see the zone step below).
$linkLookup = Invoke-LabLookup -Target "the VNet links of $PrivateDnsZoneName" -Lookup {
    Get-AzPrivateDnsVirtualNetworkLink -ResourceGroupName $PlatformRG -ZoneName $PrivateDnsZoneName -ErrorAction Stop
}
if ($linkLookup.Failed) { $script:privateZoneMustStay = $true }
foreach ($link in $linkLookup.Value) {
    if ($PSCmdlet.ShouldProcess($link.Name, 'Remove private DNS VNet link')) {
        Write-Host "Removing link: $($link.Name)..." -ForegroundColor Yellow
        try {
            Remove-AzPrivateDnsVirtualNetworkLink -ResourceGroupName $PlatformRG -ZoneName $PrivateDnsZoneName -Name $link.Name -Confirm:$false -ErrorAction Stop
            Write-Host "  -> Deleted" -ForegroundColor Green
        }
        catch {
            $script:cleanupFailures++
            $script:privateZoneMustStay = $true
            Write-Host "  -> [ERROR] Could not delete link $($link.Name): $_" -ForegroundColor Red
        }
    }
}

# Zone. While a link may still be there, the delete could only fail on it after a minute of
# retries, so the zone is left for a rerun; the [ERROR] above already makes this run exit 1.
$privateZoneLookup = Invoke-LabLookup -Target "private DNS zone $PrivateDnsZoneName" -Lookup {
    Get-AzPrivateDnsZone -ResourceGroupName $PlatformRG -Name $PrivateDnsZoneName -ErrorAction Stop
}
if ($privateZoneLookup.Value.Count -gt 0) {
    if ($script:privateZoneMustStay) {
        Write-Host "  -> [INFO] $PrivateDnsZoneName left in place - its VNet links could not be listed or removed (see the [ERROR] above)." -ForegroundColor Gray
    }
    elseif ($PSCmdlet.ShouldProcess($PrivateDnsZoneName, 'Remove private DNS zone')) {
        Write-Host "Removing Private DNS Zone: $PrivateDnsZoneName..." -ForegroundColor Yellow

        # Link deletion is asynchronous, and ARM still counts the links as nested resources for
        # a few seconds after Get-AzPrivateDnsVirtualNetworkLink has stopped returning them - so
        # polling the link list is not a reliable signal. Retry the delete itself on exactly the
        # nested-resource error instead; anything else fails immediately (#97).
        $maxAttempts = 12
        $delaySeconds = 5

        for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
            try {
                Remove-AzPrivateDnsZone -ResourceGroupName $PlatformRG -Name $PrivateDnsZoneName -Confirm:$false -ErrorAction Stop
                Write-Host "  -> Deleted" -ForegroundColor Green
                break
            }
            catch {
                if ($_.Exception.Message -notmatch 'nested resource') {
                    $script:cleanupFailures++
                    Write-Host "  -> [ERROR] Could not delete the private DNS zone: $($_.Exception.Message)" -ForegroundColor Red
                    break
                }

                if ($attempt -eq $maxAttempts) {
                    $script:cleanupFailures++
                    Write-Host "  -> [ERROR] VNet links were still draining after $($maxAttempts * $delaySeconds)s. Re-run this script." -ForegroundColor Red
                    break
                }

                Write-Host "  -> VNet links still draining, retrying in ${delaySeconds}s ($attempt/$maxAttempts)..." -ForegroundColor Gray
                Start-Sleep -Seconds $delaySeconds
            }
        }
    }
} elseif (-not $privateZoneLookup.Failed) {
    Write-Host "  -> Private Zone not found" -ForegroundColor Gray
}

if ($script:cleanupFailures -gt 0) {
    Write-Host "`nCleanup finished with $($script:cleanupFailures) failure(s) - see the [ERROR] lines above." -ForegroundColor Red
    $Host.SetShouldExit(1)
    exit 1
}

Write-Host "`n=== Cleanup Complete ===" -ForegroundColor Green
