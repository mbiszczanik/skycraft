<#
.SYNOPSIS
    Removes Lab 5.3 Network Monitoring & Diagnostics resources.

.DESCRIPTION
    Cleans up Lab 5.3 network monitoring resources in the following order:
    1. Connection Monitor (skycraft-hub-spoke-cm)
    2. VNet Flow Log (prod-skycraft-swc-vnet-flowlog)
    3. NetworkWatcherAgent extension on the connection monitor endpoint VMs
       (the VMs themselves belong to Lab 3.2 and are left in place)
    4. Traffic Analytics data collection rule and endpoint (NWTA-*) that Azure
       creates in the platform resource group when Traffic Analytics is enabled

    Every step continues on error, so one stuck object does not strand the rest. A lookup that
    fails (a 403, throttling, a transient error) or a removal that fails is reported as [ERROR] and
    counted; if anything failed the script exits 1. An object that does not exist is not a
    failure: only a lookup that succeeds and does not find it, or a getter that reports it as not
    found, means "absent" - Test-LabNotFoundError tells the two apart (issue #290; the script used
    to look everything up with -ErrorAction SilentlyContinue, printed failures without counting
    them, and always exited 0).

    The flow logs are listed and picked by name, once to remove the lab's own and once more for
    step 4. The NWTA-* resources are removed only after both listings succeeded: while a flow log
    may still feed Traffic Analytics they are in use, and a listing of the platform resource group
    that failed is not an empty group - nothing is deleted on the strength of it. An agent whose
    ownership tag could not be read is left in place.

    Each non-zero exit is paired with $Host.SetShouldExit: a bare "exit 1" is dropped under
    "pwsh -File" for any script that declares #Requires -Modules for a module it has to
    auto-import, and the process would exit 0 with the failure still on screen (issue #104).

    Note: This does NOT remove infrastructure from earlier labs (VMs, VNets,
    Storage Accounts, Log Analytics Workspace, or the Network Watcher itself,
    which Azure provisions once per region and shares across the subscription).

.PARAMETER Force
    Skip confirmation prompts.

.EXAMPLE
    .\Remove-LabResource.ps1

.EXAMPLE
    .\Remove-LabResource.ps1 -Force

.NOTES
    Project: SkyCraft
    Author: SkyCraft
    Date: 2026-04-06
#>

#Requires -Version 7.0
#Requires -Modules Az.Accounts, Az.Network, Az.Compute, Az.Resources

[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter()]
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
if ($Force) { $ConfirmPreference = 'None' }

# Counts lookups that failed and objects that exist but could not be removed. Absent objects are
# not failures.
$script:cleanupFailures = 0

# Configuration
$networkWatcherRg      = 'NetworkWatcherRG'
$networkWatcherName    = 'NetworkWatcher_swedencentral'
$connectionMonitorName = 'skycraft-hub-spoke-cm'
$flowLogName           = 'prod-skycraft-swc-vnet-flowlog'
$platformRg            = 'platform-skycraft-swc-rg'
$location              = 'swedencentral'

# VMs Deploy-Bicep.ps1 can pick as connection monitor endpoints. Only used as a
# fallback when the connection monitor is already gone and its endpoints — the
# authoritative list of VMs that received the agent — can no longer be read.
$candidateVms = @(
    @{ ResourceGroupName = 'prod-skycraft-swc-rg'; Name = 'prod-skycraft-swc-auth-vm' }
    @{ ResourceGroupName = 'dev-skycraft-swc-rg';  Name = 'dev-skycraft-swc-auth-vm' }
    @{ ResourceGroupName = 'dev-skycraft-swc-rg';  Name = 'dev-skycraft-swc-world-vm' }
)

# ── Decision helpers ──────────────────────────────────────────────────────
# These four functions hold every choice this script makes about *what* to
# delete; everything below them only performs the Azure I/O. They stay in this
# file rather than a shared module, so the lab is still runnable and readable
# on its own (docs/powershell-standards.md §7.3) — but as named functions,
# tests/Lab53-Cleanup-Logic.Tests.ps1 can lift them out with the PowerShell
# parser and exercise them against synthetic input. That matters most for the
# NWTA-* selection: Traffic Analytics only materializes those resources after
# processing real flow data for a sustained period, so no live environment can
# be made to produce them on demand.

function Get-VirtualMachineEndpointId {
    <#
    .SYNOPSIS
        Returns the virtual machine resource IDs among a connection monitor's endpoints.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter()]
        [object[]]$Endpoint
    )

    # Emits the IDs one by one, as a PowerShell function does; every caller
    # collects them with @(...) so a single match is still a one-item array.
    $vmId = [System.Collections.Generic.List[string]]::new()
    foreach ($item in @($Endpoint)) {
        if ($item.resourceId -like '*/providers/Microsoft.Compute/virtualMachines/*') {
            $vmId.Add([string]$item.resourceId)
        }
    }
    return $vmId.ToArray()
}

function ConvertTo-VmTarget {
    <#
    .SYNOPSIS
        Turns virtual machine resource IDs into the resource group / name pairs the cleanup works with.
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string[]]$VmResourceId
    )

    foreach ($id in (@($VmResourceId) | Where-Object { $_ } | Select-Object -Unique)) {
        $segment = $id -split '/'
        [PSCustomObject]@{
            Id                = $id
            ResourceGroupName = $segment[4]
            Name              = $segment[-1]
        }
    }
}

function Test-LabOwnedExtension {
    <#
    .SYNOPSIS
        Tells whether a NetworkWatcherAgent extension was installed by this lab.

    .DESCRIPTION
        Deploy-Bicep.ps1 tags every agent it installs with Project=SkyCraft and
        skips a VM that already carries one, so an untagged agent came from
        somewhere else and has to be left to its owner.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter()]
        [object]$Tag
    )

    return ($Tag.Project -eq 'SkyCraft')
}

function Select-TrafficAnalyticsResource {
    <#
    .SYNOPSIS
        Picks the NWTA-* data collection resources to delete, in deletion order.

    .DESCRIPTION
        Returns nothing while any flow log still feeds Traffic Analytics. The
        descending sort puts dataCollectionRules before dataCollectionEndpoints,
        because the rule references the endpoint and has to go first.
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [object[]]$Resource,

        [Parameter()]
        [int]$TrafficAnalyticsFlowLogCount = 0
    )

    if ($TrafficAnalyticsFlowLogCount -gt 0) { return @() }

    return @(@($Resource) | Where-Object {
            $_.Name -like 'NWTA-*' -and
            $_.ResourceType -in @('Microsoft.Insights/dataCollectionRules', 'Microsoft.Insights/dataCollectionEndpoints')
        } | Sort-Object ResourceType -Descending)
}

# ── Lookup helpers ────────────────────────────────────────────────────────

# Whether a lookup's error says the object does not exist, rather than that the lookup failed.
# Get-AzResource -ResourceId and Get-AzVM report a missing resource as an ARM 404: "The Resource
# '<type>/<name>' under resource group '<rg>' was not found.", code ResourceNotFound, or - for a
# connection monitor whose Network Watcher is gone - ParentResourceNotFound with the same 404
# status; when the group is gone as well, "Resource group '<rg>' could not be found.", code
# ResourceGroupNotFound. Az.Network wraps the SDK's CloudException, which keeps the 404 status, as
# the inner exception. The flow logs, the VM extensions and the platform group's resources are
# listed, so a missing one is an empty match. The Azure.Core clients say "Status: 404 (Not
# Found)". A missing subscription is a 404 too, but it means the context is wrong, not that the
# object is gone, so it never reads as "absent".
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
#   Value     the lookup's output, as an array - empty when the object is absent
#   NotFound  the getter reported the object as not found (Test-LabNotFoundError)
#   Failed    the lookup failed any other way: it is reported as [ERROR] and counted, because it
#             cannot tell whether the object is gone, and the caller leaves the object alone
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

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  Lab 5.3 - Resource Cleanup" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

$context = Get-AzContext
if (-not $context) {
    Write-Host "  [ERROR] Not logged into Azure. Run 'Connect-AzAccount' first." -ForegroundColor Red
    $Host.SetShouldExit(1)
    exit 1
}
Write-Host "  Account: $($context.Account.Id)" -ForegroundColor Gray

$connectionMonitorResourceId = "/subscriptions/$($context.Subscription.Id)/resourceGroups/$networkWatcherRg/providers/Microsoft.Network/networkWatchers/$networkWatcherName/connectionMonitors/$connectionMonitorName"

Write-Host "`n  The following resources will be removed:" -ForegroundColor Yellow
Write-Host "    - Connection Monitor:  $connectionMonitorName (location: $location)"
Write-Host "    - VNet Flow Log:       $flowLogName (location: $location)"
Write-Host "    - VM extension:        NetworkWatcherAgent on the connection monitor endpoint VMs"
Write-Host "    - Traffic Analytics:   NWTA-* data collection rule + endpoint in $platformRg"

# ── [1/4] Remove Connection Monitor ───────────────────────────────────────
Write-Host "`n[1/4] Removing Connection Monitor '$connectionMonitorName'..." -ForegroundColor Yellow
$endpointVmIds = @()
# Read the raw ARM body before deleting: its AzureVM endpoints name the VMs that carry the
# NetworkWatcherAgent extension removed in step [3/4], and they cannot be read once the monitor is
# gone.
$cmLookup = Invoke-LabLookup -Target "Connection Monitor '$connectionMonitorName'" -Lookup {
    Get-AzResource -ResourceId $connectionMonitorResourceId -ExpandProperties -ErrorAction Stop
}
$cmResource = $cmLookup.Value | Select-Object -First 1
if ($cmResource) {
    $endpointVmIds = @(Get-VirtualMachineEndpointId -Endpoint $cmResource.Properties.endpoints)
    if ($PSCmdlet.ShouldProcess($connectionMonitorName, 'Remove Connection Monitor')) {
        try {
            Remove-AzNetworkWatcherConnectionMonitor -NetworkWatcherName $networkWatcherName -ResourceGroupName $networkWatcherRg -Name $connectionMonitorName -Confirm:$false -ErrorAction Stop | Out-Null
            Write-Host "  ✓ Connection Monitor removed: $connectionMonitorName" -ForegroundColor Green
        } catch {
            $script:cleanupFailures++
            Write-Host "  [ERROR] Failed to remove Connection Monitor: $($_.Exception.Message)" -ForegroundColor Red
        }
    }
} elseif (-not $cmLookup.Failed) {
    Write-Host "  ✓ Connection Monitor not found (already removed): $connectionMonitorName" -ForegroundColor Gray
}

# ── [2/4] Remove VNet Flow Log ────────────────────────────────────────────
# Listed and picked by name: the listing of a Network Watcher that is gone reports a 404, and a
# missing flow log is an empty match rather than an error to interpret.
Write-Host "`n[2/4] Removing VNet Flow Log '$flowLogName'..." -ForegroundColor Yellow
$flowLogLookup = Invoke-LabLookup -Target "the flow logs of '$networkWatcherName'" -Lookup {
    Get-AzNetworkWatcherFlowLog -NetworkWatcherName $networkWatcherName -ResourceGroupName $networkWatcherRg -ErrorAction Stop
}
if ($flowLogLookup.Value | Where-Object { $_.Name -eq $flowLogName }) {
    if ($PSCmdlet.ShouldProcess($flowLogName, 'Remove VNet Flow Log')) {
        try {
            Remove-AzNetworkWatcherFlowLog -NetworkWatcherName $networkWatcherName -ResourceGroupName $networkWatcherRg -Name $flowLogName -Confirm:$false -ErrorAction Stop | Out-Null
            Write-Host "  ✓ VNet Flow Log removed: $flowLogName" -ForegroundColor Green
        } catch {
            $script:cleanupFailures++
            Write-Host "  [ERROR] Failed to remove VNet Flow Log: $($_.Exception.Message)" -ForegroundColor Red
        }
    }
} elseif (-not $flowLogLookup.Failed) {
    Write-Host "  ✓ VNet Flow Log not found (already removed): $flowLogName" -ForegroundColor Gray
}

# ── [3/4] Remove the NetworkWatcherAgent extensions ───────────────────────
# Deploy-Bicep.ps1 installs NetworkWatcherAgentLinux on both connection monitor
# endpoint VMs — a VM endpoint cannot be probed without it. No other lab uses
# the agent, so cleanup removes it here instead of letting it survive until
# Lab 3.2 deletes the VMs themselves.
Write-Host "`n[3/4] Removing NetworkWatcherAgent extensions..." -ForegroundColor Yellow

# The candidates stand in for the monitor's endpoints when those cannot be read: the monitor is
# gone, or its lookup failed. A candidate that could not be looked up is already counted.
$vmFound = @{}
if ($endpointVmIds.Count -eq 0) {
    foreach ($candidate in $candidateVms) {
        $candidateLookup = Invoke-LabLookup -Target "VM '$($candidate.Name)'" -Lookup {
            Get-AzVM -ResourceGroupName $candidate.ResourceGroupName -Name $candidate.Name -ErrorAction Stop
        }
        $candidateVm = $candidateLookup.Value | Select-Object -First 1
        if ($candidateVm) {
            $endpointVmIds += $candidateVm.Id
            $vmFound[[string]$candidateVm.Id] = $true
        }
    }
}

$agentTargets = @(ConvertTo-VmTarget -VmResourceId $endpointVmIds)
if ($agentTargets.Count -eq 0) {
    Write-Host "  ✓ No connection monitor endpoint VMs found - nothing to remove" -ForegroundColor Gray
}

foreach ($target in $agentTargets) {
    $vmRg   = $target.ResourceGroupName
    $vmName = $target.Name
    if (-not $vmFound.ContainsKey([string]$target.Id)) {
        $vmLookup = Invoke-LabLookup -Target "VM '$vmName'" -Lookup {
            Get-AzVM -ResourceGroupName $vmRg -Name $vmName -ErrorAction Stop
        }
        if ($vmLookup.Failed) { continue }
        if (-not $vmLookup.Value) {
            Write-Host "  ✓ VM not found (already removed): $vmName" -ForegroundColor Gray
            continue
        }
    }
    $extensionLookup = Invoke-LabLookup -Target "the extensions of '$vmName'" -Lookup {
        Get-AzVMExtension -ResourceGroupName $vmRg -VMName $vmName -ErrorAction Stop
    }
    if ($extensionLookup.Failed) { continue }
    $agents = @($extensionLookup.Value | Where-Object { $_.Publisher -eq 'Microsoft.Azure.NetworkWatcher' })
    if ($agents.Count -eq 0) {
        Write-Host "  ✓ No NetworkWatcherAgent on $vmName (already removed)" -ForegroundColor Gray
        continue
    }
    foreach ($agent in $agents) {
        # The ownership tag decides whether the agent is the lab's to remove. A tag that could not
        # be read leaves the agent in place; one that is gone with its extension leaves nothing.
        $tagLookup = Invoke-LabLookup -Target "the tags of $($agent.Name) on $vmName" -Lookup {
            Get-AzResource -ResourceId $agent.Id -ErrorAction Stop
        }
        if ($tagLookup.Failed) { continue }
        $agentResource = $tagLookup.Value | Select-Object -First 1
        if (-not $agentResource) {
            Write-Host "  ✓ $($agent.Name) on $vmName not found (already removed)" -ForegroundColor Gray
            continue
        }
        if (-not (Test-LabOwnedExtension -Tag $agentResource.Tags)) {
            Write-Host "  [SKIP] $($agent.Name) on $vmName is not tagged Project=SkyCraft - left in place" -ForegroundColor Gray
            continue
        }
        if ($PSCmdlet.ShouldProcess("$vmName/$($agent.Name)", 'Remove VM extension')) {
            try {
                Remove-AzVMExtension -ResourceGroupName $vmRg -VMName $vmName -Name $agent.Name -Force -ErrorAction Stop | Out-Null
                Write-Host "  ✓ NetworkWatcherAgent removed from $vmName" -ForegroundColor Green
            } catch {
                $script:cleanupFailures++
                Write-Host "  [ERROR] Failed to remove NetworkWatcherAgent from ${vmName}: $($_.Exception.Message)" -ForegroundColor Red
            }
        }
    }
}

# ── [4/4] Remove the Traffic Analytics DCR / DCE ──────────────────────────
# Enabling Traffic Analytics makes Azure create an NWTA-<workspace-guid>-<region>
# data collection rule and endpoint next to the workspace. They are Azure's own
# artifacts — main.bicep never declares them — and they survive the flow log, so
# cleanup removes them once no flow log feeds them any more.
Write-Host "`n[4/4] Removing Traffic Analytics data collection resources..." -ForegroundColor Yellow

# Listed again, after step [2/4]: a flow log that still feeds Traffic Analytics keeps the NWTA-*
# resources in use. A listing that failed cannot say that none does, so nothing is removed.
$taFlowLogLookup = Invoke-LabLookup -Target "the flow logs of '$networkWatcherName' that feed Traffic Analytics" -Lookup {
    Get-AzNetworkWatcherFlowLog -NetworkWatcherName $networkWatcherName -ResourceGroupName $networkWatcherRg -ErrorAction Stop
}
$taFlowLogs = @($taFlowLogLookup.Value |
    Where-Object { $_.FlowAnalyticsConfiguration.NetworkWatcherFlowAnalyticsConfiguration.Enabled -eq $true })

if ($taFlowLogLookup.Failed) {
    Write-Host "  [SKIP] NWTA-* resources left in place - the flow logs that may still feed them could not be listed" -ForegroundColor Yellow
} elseif ($taFlowLogs.Count -gt 0) {
    Write-Host "  [SKIP] $($taFlowLogs.Count) flow log(s) still use Traffic Analytics - NWTA-* resources left in place" -ForegroundColor Yellow
} else {
    # Only a listing that succeeded says what the group holds. One that failed is not an empty
    # group: it is counted, and nothing is removed on the strength of it.
    $platformLookup = Invoke-LabLookup -Target "the resources in '$platformRg'" -Lookup {
        Get-AzResource -ResourceGroupName $platformRg -ErrorAction Stop
    }
    if ($platformLookup.Failed) {
        Write-Host "  [SKIP] NWTA-* resources not checked - '$platformRg' could not be listed" -ForegroundColor Yellow
    } else {
        $taResources = @(Select-TrafficAnalyticsResource -Resource $platformLookup.Value -TrafficAnalyticsFlowLogCount $taFlowLogs.Count)
        if ($taResources.Count -eq 0) {
            Write-Host "  ✓ No NWTA-* data collection resources found (already removed)" -ForegroundColor Gray
        }
        foreach ($taResource in $taResources) {
            $taKind = ($taResource.ResourceType -split '/')[-1]
            if ($PSCmdlet.ShouldProcess($taResource.Name, "Remove Traffic Analytics $taKind")) {
                try {
                    Remove-AzResource -ResourceId $taResource.ResourceId -Force -ErrorAction Stop | Out-Null
                    Write-Host "  ✓ Traffic Analytics $taKind removed: $($taResource.Name)" -ForegroundColor Green
                } catch {
                    $script:cleanupFailures++
                    Write-Host "  [ERROR] Failed to remove $($taResource.Name): $($_.Exception.Message)" -ForegroundColor Red
                }
            }
        }
    }
}

Write-Host "`n========================================" -ForegroundColor Cyan
if ($script:cleanupFailures -gt 0) {
    Write-Host "  Cleanup finished with $($script:cleanupFailures) failure(s)" -ForegroundColor Red
    Write-Host "  See the [ERROR] lines above. What could not be looked up or removed may still exist." -ForegroundColor Gray
    Write-Host "========================================`n" -ForegroundColor Cyan
    $Host.SetShouldExit(1)
    exit 1
}
Write-Host "  Cleanup Complete" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan
