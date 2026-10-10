<#
.SYNOPSIS
    Pester 5 tests for the Lab 5.3 cleanup: when it reports an object absent, and when it exits 1.

.DESCRIPTION
    Regression cover for issue #290. The cleanup looked every object up with -ErrorAction
    SilentlyContinue, so a lookup that failed - a 403, throttling, a transient ARM error - read as
    "absent"; it printed failures without counting them, and it never exited 1. The worst case was
    step [4/4]: a listing of the platform resource group that failed read as an empty group, and
    the run reported the NWTA-* resources "already removed". These tests run the real
    Remove-LabResource.ps1 in a child pwsh process against a generated stub of the Az commands it
    calls, and assert the observable contract:

      1. Everything the lab created is removed when it is present, and the run exits 0. Nothing in
         the platform resource group but the NWTA-* resources is touched, and no resource group is
         deleted.
      2. An object that is absent - an empty listing, or a getter that reports it not found - is
         not a failure: the run exits 0.
      3. A lookup that fails with an error is an [ERROR], counted, and the run exits 1 without
         reporting absent the object it could not see, or removing anything on the strength of
         it. The stub reports the failure with Write-Error, as the Az getters do, so a script that
         passes -ErrorAction SilentlyContinue swallows it.
      4. A removal that fails is an [ERROR], counted, and the later steps still run: exit 1.

    The decisions the cleanup makes about what to delete are pinned against synthetic input by
    tests/Lab53-Cleanup-Logic.Tests.ps1; which errors mean "not found" by
    tests/Lab-Cleanup-Lookup.Tests.ps1.

    Scope limit, as in the Lab 5.2 suite: the child is launched with -Command, so these tests
    prove the failure counter reaches `exit`, not that `pwsh -File` carries the code out of the
    process. That half is issue #104's guard, enforced by tests/Exit-Code-Propagation.Tests.ps1.

    No subscription is needed, and none is used. The script runs through
    tests/Support/LabScriptStub.psm1 (issue #112), which aborts the child with exit 99 unless every
    stubbed command resolves to the stub.

.EXAMPLE
    Invoke-Pester -Path .\Remove-LabResource.Tests.ps1

.NOTES
    Project: SkyCraft
    Lab: 5.3 - Network Monitoring
#>

#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..' '..' '..' 'tests' 'Support' 'LabScriptStub.psm1') -Force

    $script:ScriptPath     = (Resolve-Path (Join-Path $PSScriptRoot '..' 'scripts' 'Remove-LabResource.ps1')).Path
    $script:StubModuleName = 'SkyCraftLab53CleanupStub'
    # Exactly the script's '#Requires -Modules' line: these are imported for real before the stub.
    $script:RequiredModules = @('Az.Accounts', 'Az.Network', 'Az.Compute', 'Az.Resources')

    # Every Az command the script calls, before #290 and after it, and Remove-AzResourceGroup,
    # which it must never call. The flow log stub accepts both the by-name form the script used
    # before #290 and the listing it uses now, so a revert runs against the stub instead of a
    # subscription.
    $script:StubCommands = @(
        'Get-AzContext'
        'Get-AzResource'
        'Remove-AzResource'
        'Remove-AzNetworkWatcherConnectionMonitor'
        'Get-AzNetworkWatcherFlowLog'
        'Remove-AzNetworkWatcherFlowLog'
        'Get-AzVM'
        'Get-AzVMExtension'
        'Remove-AzVMExtension'
        'Remove-AzResourceGroup'
    )

    # Every command records its own invocation. By default the connection monitor exists with the
    # dev and prod auth VMs as endpoints, each VM carries a tagged NetworkWatcherAgentLinux and an
    # unrelated extension, the lab's flow log feeds Traffic Analytics, and the platform group holds
    # the NWTA-* rule and endpoint next to the workspace. Environment variables change that, so one
    # generated module serves every scenario:
    #   SKYCRAFT_STUB_EMPTY   '1' leaves nothing to find: the monitor and the VMs are reported not
    #                         found, as the real getters do, and the listings are empty
    #   SKYCRAFT_STUB_LOOKUP  '<lookup>=<kind>,...' makes one lookup fail (denied, throttled);
    #                         '<lookup>#<n>=<kind>' only its n-th call
    #   SKYCRAFT_STUB_FAIL    '<command>:<name>,...' makes one removal throw
    # Lookups: 'ConnectionMonitor', 'FlowLogs', 'PlatformResources', 'Get-AzVM:<vm>',
    # 'Get-AzVMExtension:<vm>', 'Tags:<vm>'. A removal is logged as '<command>:<name>'. The kind
    # 'status404' reports a missing object the way Az.Resources can: a status-only 404 (an
    # exception whose inner CloudException carries the 404 response) with no not-found wording.
    # The empty subscription's connection monitor is reported missing that way.
    $script:StubBody = @'
$script:LogPath = $env:SKYCRAFT_STUB_LOG
$script:SubscriptionId = '00000000-0000-0000-0000-000000000000'
$script:Calls = @{}
$script:FlowLogRemoved = $false

# The shape of a status-only 404 from Az.Resources: ResourceManagerCloudException around the SDK's
# CloudException, whose Response carries the status. Neither message says "not found".
if (-not ('SkyCraftLab53Stub.CloudException' -as [type])) {
    Add-Type -TypeDefinition @"
namespace SkyCraftLab53Stub
{
    public class CloudException : System.Exception
    {
        public CloudException(string message) : base(message) { }
        public object Response { get; set; }
    }
    public class ResourceManagerCloudException : System.Exception
    {
        public ResourceManagerCloudException(string message, System.Exception inner) : base(message, inner) { }
    }
}
"@
}

function Get-StubVmId {
    param([string]$ResourceGroupName, [string]$Name)
    "/subscriptions/$($script:SubscriptionId)/resourceGroups/$ResourceGroupName/providers/Microsoft.Compute/virtualMachines/$Name"
}

function Write-StubCall {
    param([string]$Name)
    if ($script:LogPath) { Add-Content -LiteralPath $script:LogPath -Value $Name }
}

function Test-StubEmpty { return $env:SKYCRAFT_STUB_EMPTY -eq '1' }

function Invoke-StubRemoval {
    param([string]$Command, [string]$Name)
    Write-StubCall -Name $Command
    Write-StubCall -Name "${Command}:$Name"
    if (@($env:SKYCRAFT_STUB_FAIL -split ',') -contains "${Command}:$Name") { throw "stub failure: ${Command} $Name" }
}

# How the lookup named here fails, if at all. The failure is reported with Write-Error, as the Az
# getters do, so the caller's -ErrorAction decides what happens to it. -Gone: the real getter
# reports the object as not found in the empty subscription. Returns $true when the lookup failed,
# so the stub returns nothing after it.
function Invoke-StubLookup {
    param([string]$Name, [switch]$Gone, [string]$GoneKind = 'notfound')
    Write-StubCall -Name $Name
    $script:Calls[$Name] = 1 + [int]$script:Calls[$Name]
    $kind = foreach ($entry in @($env:SKYCRAFT_STUB_LOOKUP -split ',')) {
        $key, $value = $entry -split '=', 2
        if ($key -eq $Name -or $key -eq "$Name#$($script:Calls[$Name])") { $value }
    }
    if (-not $kind -and $Gone -and (Test-StubEmpty)) { $kind = $GoneKind }
    switch ($kind) {
        'status404' {
            $inner = [SkyCraftLab53Stub.CloudException]::new('Long running operation failed.')
            $inner.Response = [pscustomobject]@{ StatusCode = [System.Net.HttpStatusCode]::NotFound }
            Write-Error -Exception ([SkyCraftLab53Stub.ResourceManagerCloudException]::new('The request failed.', $inner)) -ErrorId 'StubCloudError'
            return $true
        }
        'denied' {
            Write-Error -ErrorId 'AuthorizationFailed' -Message "The client 'stub' does not have authorization to perform action 'read' over scope '$Name' or the scope is invalid."
            return $true
        }
        'throttled' {
            Write-Error -ErrorId 'TooManyRequests' -Message "Number of 'read' requests exceeded the limit for $Name. Please try again after '17' seconds."
            return $true
        }
        'notfound' {
            Write-Error -ErrorId 'ResourceNotFound' -Message "The Resource 'stub/$Name' under resource group 'stub-rg' was not found. For more details please go to https://aka.ms/ARMResourceNotFoundFix"
            return $true
        }
    }
    return $false
}

function Get-AzContext {
    [CmdletBinding()]
    param()
    [pscustomobject]@{
        Subscription = [pscustomobject]@{ Id = $script:SubscriptionId; Name = 'stub-subscription' }
        Account      = [pscustomobject]@{ Id = 'stub-account' }
    }
}

function Get-AzResource {
    [CmdletBinding()]
    param([string]$ResourceId, [string]$ResourceGroupName, [switch]$ExpandProperties)
    if ($ResourceId -like '*/connectionMonitors/*') {
        if (Invoke-StubLookup -Name 'ConnectionMonitor' -Gone -GoneKind 'status404') { return }
        return [pscustomobject]@{
            Name       = ($ResourceId -split '/')[-1]
            ResourceId = $ResourceId
            Properties = [pscustomobject]@{
                endpoints = @(
                    [pscustomobject]@{ name = 'dev-auth'; resourceId = (Get-StubVmId -ResourceGroupName 'dev-skycraft-swc-rg' -Name 'dev-skycraft-swc-auth-vm') }
                    [pscustomobject]@{ name = 'prod-auth'; resourceId = (Get-StubVmId -ResourceGroupName 'prod-skycraft-swc-rg' -Name 'prod-skycraft-swc-auth-vm') }
                    [pscustomobject]@{ name = 'outside'; address = '203.0.113.10' }
                )
            }
        }
    }
    if ($ResourceId -like '*/extensions/*') {
        $vmName = ($ResourceId -split '/')[-3]
        if (Invoke-StubLookup -Name "Tags:$vmName" -Gone) { return }
        return [pscustomobject]@{ Name = ($ResourceId -split '/')[-1]; ResourceId = $ResourceId; Tags = @{ Project = 'SkyCraft' } }
    }
    if (Invoke-StubLookup -Name 'PlatformResources') { return }
    $rgId = "/subscriptions/$($script:SubscriptionId)/resourceGroups/$ResourceGroupName/providers"
    [pscustomobject]@{ Name = 'platform-skycraft-swc-law'; ResourceType = 'Microsoft.OperationalInsights/workspaces'; ResourceId = "$rgId/Microsoft.OperationalInsights/workspaces/platform-skycraft-swc-law" }
    if (Test-StubEmpty) { return }
    [pscustomobject]@{ Name = 'NWTA-0000-swedencentral'; ResourceType = 'Microsoft.Insights/dataCollectionEndpoints'; ResourceId = "$rgId/Microsoft.Insights/dataCollectionEndpoints/NWTA-0000-swedencentral" }
    [pscustomobject]@{ Name = 'NWTA-0000-swedencentral'; ResourceType = 'Microsoft.Insights/dataCollectionRules'; ResourceId = "$rgId/Microsoft.Insights/dataCollectionRules/NWTA-0000-swedencentral" }
}

function Remove-AzResource {
    [CmdletBinding()]
    param([string]$ResourceId, [switch]$Force)
    $segment = $ResourceId -split '/'
    Invoke-StubRemoval -Command 'Remove-AzResource' -Name "$($segment[-2])/$($segment[-1])"
}

function Remove-AzNetworkWatcherConnectionMonitor {
    [CmdletBinding(SupportsShouldProcess)]
    param([string]$NetworkWatcherName, [string]$ResourceGroupName, [string]$Name)
    Invoke-StubRemoval -Command 'Remove-AzNetworkWatcherConnectionMonitor' -Name $Name
}

function Get-AzNetworkWatcherFlowLog {
    [CmdletBinding()]
    param([string]$NetworkWatcherName, [string]$ResourceGroupName, [string]$Name)
    if (Invoke-StubLookup -Name 'FlowLogs') { return }
    $items = @([pscustomobject]@{
        Name = 'unrelated-flowlog'
        FlowAnalyticsConfiguration = [pscustomobject]@{ NetworkWatcherFlowAnalyticsConfiguration = [pscustomobject]@{ Enabled = $false } }
    })
    if (-not (Test-StubEmpty) -and -not $script:FlowLogRemoved) {
        $items += [pscustomobject]@{
            Name = 'prod-skycraft-swc-vnet-flowlog'
            FlowAnalyticsConfiguration = [pscustomobject]@{ NetworkWatcherFlowAnalyticsConfiguration = [pscustomobject]@{ Enabled = $true } }
        }
    }
    if ($Name) { $items = @($items | Where-Object { $_.Name -eq $Name }) }
    $items
}

function Remove-AzNetworkWatcherFlowLog {
    [CmdletBinding(SupportsShouldProcess)]
    param([string]$NetworkWatcherName, [string]$ResourceGroupName, [string]$Name)
    Invoke-StubRemoval -Command 'Remove-AzNetworkWatcherFlowLog' -Name $Name
    $script:FlowLogRemoved = $true
}

function Get-AzVM {
    [CmdletBinding()]
    param([string]$ResourceGroupName, [string]$Name)
    if (Invoke-StubLookup -Name "Get-AzVM:$Name" -Gone) { return }
    # The world VM is one of the fallback candidates, but this subscription never had it.
    if ($Name -eq 'dev-skycraft-swc-world-vm') {
        Write-Error -ErrorId 'ResourceNotFound' -Message "The Resource 'Microsoft.Compute/virtualMachines/$Name' under resource group '$ResourceGroupName' was not found."
        return
    }
    [pscustomobject]@{ Name = $Name; ResourceGroupName = $ResourceGroupName; Id = (Get-StubVmId -ResourceGroupName $ResourceGroupName -Name $Name) }
}

function Get-AzVMExtension {
    [CmdletBinding()]
    param([string]$ResourceGroupName, [string]$VMName)
    if (Invoke-StubLookup -Name "Get-AzVMExtension:$VMName") { return }
    $vmId = Get-StubVmId -ResourceGroupName $ResourceGroupName -Name $VMName
    [pscustomobject]@{ Name = 'AzureMonitorLinuxAgent'; Publisher = 'Microsoft.Azure.Monitor'; Id = "$vmId/extensions/AzureMonitorLinuxAgent" }
    [pscustomobject]@{ Name = 'NetworkWatcherAgentLinux'; Publisher = 'Microsoft.Azure.NetworkWatcher'; Id = "$vmId/extensions/NetworkWatcherAgentLinux" }
}

function Remove-AzVMExtension {
    [CmdletBinding()]
    param([string]$ResourceGroupName, [string]$VMName, [string]$Name, [switch]$Force)
    Invoke-StubRemoval -Command 'Remove-AzVMExtension' -Name "${VMName}/$Name"
}

function Remove-AzResourceGroup {
    [CmdletBinding()]
    param([string]$Name, [switch]$Force)
    Invoke-StubRemoval -Command 'Remove-AzResourceGroup' -Name $Name
}
'@

    # Runs the real script in a child process with the stubs shadowing the Az commands, and
    # returns the exit code it hands back together with the stub's call log.
    function Invoke-CleanupScript {
        param(
            [pscustomobject]$Stub,
            [string[]]$Fail = @(),
            [string[]]$Lookup = @(),
            [string[]]$ArgumentList = @('-Force'),
            [switch]$Empty
        )

        $logPath = Join-Path $Stub.Directory 'calls.log'
        Remove-Item -LiteralPath $logPath -Force -ErrorAction SilentlyContinue

        $run = Invoke-LabScriptWithStub -Stub $Stub -ScriptPath $script:ScriptPath -ArgumentList $ArgumentList -Environment @{
            SKYCRAFT_STUB_FAIL   = $Fail -join ','
            SKYCRAFT_STUB_LOOKUP = $Lookup -join ','
            SKYCRAFT_STUB_EMPTY  = if ($Empty) { '1' } else { '0' }
            SKYCRAFT_STUB_LOG    = $logPath
        }

        $calls = if (Test-Path -LiteralPath $logPath) { @(Get-Content -LiteralPath $logPath) } else { @() }
        return [pscustomobject]@{
            ExitCode = $run.ExitCode
            Refused  = $run.Refused
            Output   = $run.Output
            Calls    = $calls
        }
    }

    $script:Stub    = Initialize-LabScriptStub -Name $script:StubModuleName -Command $script:StubCommands `
        -Body $script:StubBody -RequiredModule $script:RequiredModules
    $script:StubDir = $script:Stub.Directory

    # A removal the script makes.
    $script:ChangePattern = '^Remove-'
    $script:NwtaRule      = 'Remove-AzResource:dataCollectionRules/NWTA-0000-swedencentral'
    $script:NwtaEndpoint  = 'Remove-AzResource:dataCollectionEndpoints/NWTA-0000-swedencentral'

    # One invocation per scenario, reused by the assertions below - each child process costs
    # several seconds.
    $script:Clean     = Invoke-CleanupScript -Stub $script:Stub
    $script:Nothing   = Invoke-CleanupScript -Stub $script:Stub -Empty
    $script:WhatIf    = Invoke-CleanupScript -Stub $script:Stub -ArgumentList '-WhatIf'
    $script:CmDenied  = Invoke-CleanupScript -Stub $script:Stub -Lookup 'ConnectionMonitor=denied'
    $script:GroupListFails = Invoke-CleanupScript -Stub $script:Stub -Lookup 'PlatformResources=denied'
    $script:TaListFails    = Invoke-CleanupScript -Stub $script:Stub -Lookup 'FlowLogs#2=throttled'
    $script:AgentLookupsFail = Invoke-CleanupScript -Stub $script:Stub -Lookup @(
        'Get-AzVMExtension:dev-skycraft-swc-auth-vm=throttled'
        'Tags:prod-skycraft-swc-auth-vm=denied'
    )
    $script:StepsFail = Invoke-CleanupScript -Stub $script:Stub -Fail @(
        'Remove-AzNetworkWatcherConnectionMonitor:skycraft-hub-spoke-cm'
        'Remove-AzVMExtension:dev-skycraft-swc-auth-vm/NetworkWatcherAgentLinux'
    )

    $script:AllRuns = @(
        $script:Clean, $script:Nothing, $script:WhatIf, $script:CmDenied, $script:GroupListFails,
        $script:TaListFails, $script:AgentLookupsFail, $script:StepsFail
    )
}

AfterAll {
    if ($script:StubDir) { Remove-Item -LiteralPath $script:StubDir -Recurse -Force -ErrorAction SilentlyContinue }
}

Describe 'Lab 5.3 Remove-LabResource.ps1 - test harness' {

    It 'shadows the real Az commands instead of touching a subscription' {
        # Refused is the child exiting 99 before the script ran. Asserted on every scenario: a
        # refusal in one of them is a half-stubbed session, not a scenario-specific failure.
        foreach ($run in $script:AllRuns) {
            $run.Refused | Should -BeFalse -Because "the harness must never fall through to the real Az commands (exit $($run.ExitCode)): $($run.Output)"
        }
    }

    It 'never deletes a resource group, in any scenario' {
        foreach ($run in $script:AllRuns) {
            @($run.Calls | Where-Object { $_ -like 'Remove-AzResourceGroup*' }) | Should -BeNullOrEmpty
        }
    }
}

Describe 'Lab 5.3 Remove-LabResource.ps1 - removes what the lab created' {

    It 'exits 0 when everything is found and removed' {
        $script:Clean.ExitCode | Should -Be 0 -Because "a clean teardown must report success; output was:`n$($script:Clean.Output)"
        $script:Clean.Output   | Should -Match 'Cleanup Complete'
        $script:Clean.Output   | Should -Not -Match '\[ERROR\]'
    }

    It 'removes the monitor, the flow log, the agents on its endpoint VMs and the NWTA-* rule before its endpoint' {
        $calls = $script:Clean.Calls
        $calls | Should -Contain 'Remove-AzNetworkWatcherConnectionMonitor:skycraft-hub-spoke-cm'
        $calls | Should -Contain 'Remove-AzNetworkWatcherFlowLog:prod-skycraft-swc-vnet-flowlog'
        $calls | Should -Contain 'Remove-AzVMExtension:dev-skycraft-swc-auth-vm/NetworkWatcherAgentLinux'
        $calls | Should -Contain 'Remove-AzVMExtension:prod-skycraft-swc-auth-vm/NetworkWatcherAgentLinux'
        $calls | Should -Contain $script:NwtaRule
        $calls | Should -Contain $script:NwtaEndpoint
        [array]::IndexOf($calls, $script:NwtaRule) | Should -BeLessThan ([array]::IndexOf($calls, $script:NwtaEndpoint))
    }

    It 'leaves the other extensions, flow logs and platform resources alone' {
        $calls = $script:Clean.Calls
        @($calls | Where-Object { $_ -match 'AzureMonitorLinuxAgent|unrelated-flowlog|platform-skycraft-swc-law' }) | Should -BeNullOrEmpty
    }
}

Describe 'Lab 5.3 Remove-LabResource.ps1 - an absent object is not a failure' {

    It 'exits 0 and removes nothing when the getters report everything not found' {
        $run = $script:Nothing
        $run.ExitCode | Should -Be 0 -Because "output was:`n$($run.Output)"
        $run.Output   | Should -Match 'Connection Monitor not found \(already removed\)'
        $run.Output   | Should -Match 'VNet Flow Log not found \(already removed\)'
        $run.Output   | Should -Match 'No NWTA-\* data collection resources found'
        $run.Output   | Should -Not -Match '\[ERROR\]'
        @($run.Calls | Where-Object { $_ -match $script:ChangePattern }) | Should -BeNullOrEmpty
    }

    It 'reads a status-only 404 for the connection monitor as absent' {
        # The empty subscription's monitor is reported missing with no not-found wording at all:
        # only the 404 on the inner CloudException's response says so.
        $run = $script:Nothing
        $run.Calls  | Should -Contain 'ConnectionMonitor'
        $run.Output | Should -Not -Match 'Could not look up Connection Monitor'
        $run.Output | Should -Match 'Connection Monitor not found \(already removed\)'
    }
}

Describe 'Lab 5.3 Remove-LabResource.ps1 - a failed lookup is not "absent" (#290)' {

    It 'exits 1 when the connection monitor could not be looked up, and does not report it removed' {
        $run = $script:CmDenied
        $run.ExitCode | Should -Be 1 -Because "output was:`n$($run.Output)"
        $run.Output   | Should -Match "\[ERROR\] Could not look up Connection Monitor 'skycraft-hub-spoke-cm'[^\r\n]*does not have authorization"
        $run.Output   | Should -Match 'Cleanup finished with 1 failure\(s\)'
        $run.Output   | Should -Not -Match 'Connection Monitor not found'
        $run.Calls    | Should -Not -Contain 'Remove-AzNetworkWatcherConnectionMonitor:skycraft-hub-spoke-cm'
    }

    It 'still runs the later steps, with the candidate VMs standing in for the endpoints it could not read' {
        $calls = $script:CmDenied.Calls
        $calls | Should -Contain 'Remove-AzNetworkWatcherFlowLog:prod-skycraft-swc-vnet-flowlog'
        $calls | Should -Contain 'Remove-AzVMExtension:dev-skycraft-swc-auth-vm/NetworkWatcherAgentLinux'
        $calls | Should -Contain 'Remove-AzVMExtension:prod-skycraft-swc-auth-vm/NetworkWatcherAgentLinux'
        $calls | Should -Contain $script:NwtaRule
    }

    It 'keeps the NWTA-* resources when the platform group could not be listed, instead of reading it as empty' {
        $run = $script:GroupListFails
        $run.ExitCode | Should -Be 1 -Because "output was:`n$($run.Output)"
        $run.Output   | Should -Match "\[ERROR\] Could not look up the resources in 'platform-skycraft-swc-rg'"
        $run.Output   | Should -Match 'Cleanup finished with 1 failure\(s\)'
        $run.Output   | Should -Not -Match 'No NWTA-\* data collection resources found'
        $run.Calls    | Should -Not -Contain $script:NwtaRule
        $run.Calls    | Should -Not -Contain $script:NwtaEndpoint
        # The steps before it still ran.
        $run.Calls    | Should -Contain 'Remove-AzNetworkWatcherFlowLog:prod-skycraft-swc-vnet-flowlog'
    }

    It 'keeps the NWTA-* resources when the flow logs that may feed them could not be listed' {
        $run = $script:TaListFails
        $run.ExitCode | Should -Be 1 -Because "output was:`n$($run.Output)"
        $run.Output   | Should -Match 'Cleanup finished with 1 failure\(s\)'
        $run.Calls    | Should -Contain 'Remove-AzNetworkWatcherFlowLog:prod-skycraft-swc-vnet-flowlog'
        $run.Calls    | Should -Not -Contain $script:NwtaRule
        $run.Calls    | Should -Not -Contain $script:NwtaEndpoint
    }

    It 'leaves an agent alone when its VM''s extensions or its ownership tag could not be read' {
        $run = $script:AgentLookupsFail
        $run.ExitCode | Should -Be 1 -Because "output was:`n$($run.Output)"
        $run.Output   | Should -Match "\[ERROR\] Could not look up the extensions of 'dev-skycraft-swc-auth-vm'"
        $run.Output   | Should -Match '\[ERROR\] Could not look up the tags of NetworkWatcherAgentLinux on prod-skycraft-swc-auth-vm'
        $run.Output   | Should -Match 'Cleanup finished with 2 failure\(s\)'
        $run.Output   | Should -Not -Match 'No NetworkWatcherAgent on'
        @($run.Calls | Where-Object { $_ -like 'Remove-AzVMExtension:*' }) | Should -BeNullOrEmpty
        $run.Calls    | Should -Contain $script:NwtaRule
    }
}

Describe 'Lab 5.3 Remove-LabResource.ps1 - a failed removal is counted' {

    It 'exits 1 and counts each removal that failed' {
        $run = $script:StepsFail
        $run.ExitCode | Should -Be 1 -Because "output was:`n$($run.Output)"
        $run.Output   | Should -Match '\[ERROR\] Failed to remove Connection Monitor'
        $run.Output   | Should -Match '\[ERROR\] Failed to remove NetworkWatcherAgent from dev-skycraft-swc-auth-vm'
        $run.Output   | Should -Match 'Cleanup finished with 2 failure\(s\)'
        $run.Output   | Should -Not -Match 'Cleanup Complete'
    }

    It 'keeps going after a failed removal' {
        $calls = $script:StepsFail.Calls
        $calls | Should -Contain 'Remove-AzNetworkWatcherFlowLog:prod-skycraft-swc-vnet-flowlog'
        $calls | Should -Contain 'Remove-AzVMExtension:prod-skycraft-swc-auth-vm/NetworkWatcherAgentLinux'
        $calls | Should -Contain $script:NwtaRule
        $calls | Should -Contain $script:NwtaEndpoint
    }
}

Describe 'Lab 5.3 Remove-LabResource.ps1 - -WhatIf' {

    It 'looks everything up and removes nothing' {
        $run = $script:WhatIf
        $run.ExitCode | Should -Be 0 -Because "output was:`n$($run.Output)"
        @($run.Calls | Where-Object { $_ -match $script:ChangePattern }) | Should -BeNullOrEmpty
        $run.Calls    | Should -Contain 'ConnectionMonitor'
        $run.Output   | Should -Match 'What if: .*skycraft-hub-spoke-cm'
        $run.Output   | Should -Match 'What if: .*NetworkWatcherAgentLinux'
        # The flow log was not removed, so it still feeds Traffic Analytics and step [4/4] leaves
        # the NWTA-* resources alone.
        $run.Output   | Should -Match 'still use Traffic Analytics'
    }
}
