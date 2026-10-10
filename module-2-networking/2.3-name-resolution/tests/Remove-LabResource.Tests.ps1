<#
.SYNOPSIS
    Pester 5 tests for the Lab 2.3 cleanup: when it reports a resource absent, and when it exits 1.

.DESCRIPTION
    Regression cover for issue #255. The cleanup looked the DNS zones, the load balancers and the
    private zone's VNet links up with -ErrorAction SilentlyContinue, so a lookup that failed (a
    403, throttling) read as "not found", and only the private zone's delete could make it exit
    1. These tests run the real Remove-LabResource.ps1 in a child pwsh process against a
    generated stub of the Az commands it calls, and assert the observable contract:

      1. The public zone, both load balancers, the private zone's VNet links and the private
         zone are removed when present, and the run exits 0.
      2. A resource reported as not found is not a failure: the run exits 0.
      3. A lookup that fails with an error is an [ERROR], counted, and the run exits 1 without
         touching or reporting absent the resource it could not see. The stub reports the failure
         with Write-Error, as the Az getters do, so a script that passes -ErrorAction
         SilentlyContinue swallows it - the defect #255 describes.
      4. A removal that fails is an [ERROR], counted, and the later steps still run: exit 1.
      5. The private zone stays while its VNet links could not be listed or removed, and its
         delete is still retried only on the nested-resource error (#97).
      6. -WhatIf looks everything up and removes nothing.

    Which errors mean "not found" is pinned for every cleanup that carries the helpers by
    tests/Lab-Cleanup-Lookup.Tests.ps1.

    Scope limit, as in the Lab 5.2 suite: the child is launched with -Command, so these tests
    prove the failure counter reaches `exit`, not that `pwsh -File` carries the code out of the
    process. That half is issue #104's guard, enforced by tests/Exit-Code-Propagation.Tests.ps1.

    No subscription is needed, and none is used. The script runs through
    tests/Support/LabScriptStub.psm1 (issue #112), which aborts the child with exit 99 unless every
    stubbed command resolves to the stub. Start-Sleep is stubbed too, so the retry wait costs
    nothing.

.EXAMPLE
    Invoke-Pester -Path .\Remove-LabResource.Tests.ps1

.NOTES
    Project: SkyCraft
    Lab: 2.3 - Name Resolution & Load Balancing
#>

#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..' '..' '..' 'tests' 'Support' 'LabScriptStub.psm1') -Force

    $script:ScriptPath     = (Resolve-Path (Join-Path $PSScriptRoot '..' 'scripts' 'Remove-LabResource.ps1')).Path
    $script:StubModuleName = 'SkyCraftLab23CleanupStub'
    # Exactly the script's '#Requires -Modules' line: these are imported for real before the stub.
    # The private DNS commands come from Az.PrivateDns, which the line does not name; the stub
    # exports them, so they resolve to it all the same.
    $script:RequiredModules = @('Az.Accounts', 'Az.Dns', 'Az.Network')

    $script:StubCommands = @(
        'Get-AzContext'
        'Get-AzDnsZone'
        'Remove-AzDnsZone'
        'Get-AzLoadBalancer'
        'Remove-AzLoadBalancer'
        'Get-AzPrivateDnsVirtualNetworkLink'
        'Remove-AzPrivateDnsVirtualNetworkLink'
        'Get-AzPrivateDnsZone'
        'Remove-AzPrivateDnsZone'
        'Start-Sleep'
    )

    # Every command the script calls, recording its own invocation. By default the subscription
    # holds everything the lab creates: the public zone, both load balancers, the private zone
    # and its two VNet links. Environment variables change that, so one generated module serves
    # every scenario:
    #   SKYCRAFT_STUB_EMPTY   '1' leaves nothing to find: every getter reports ResourceNotFound,
    #                         as the real ones do for a name (or a zone) that does not exist
    #   SKYCRAFT_STUB_LOOKUP  '<lookup>=<kind>,...' makes one lookup fail (denied, throttled) or
    #                         report its resource not found (notfound, rgnotfound)
    #   SKYCRAFT_STUB_FAIL    '<Remove-command>:<name>,...' makes one removal throw
    #   SKYCRAFT_STUB_NESTED  '<n>' makes the private zone delete fail the first n times with the
    #                         nested-resource error ARM returns while the links drain
    # A lookup is named after its command and the resource it reads: 'Get-AzDnsZone:<zone>',
    # 'Get-AzLoadBalancer:<lb>', 'Get-AzPrivateDnsVirtualNetworkLink:<zone>',
    # 'Get-AzPrivateDnsZone:<zone>'.
    $script:StubBody = @'
$script:LogPath = $env:SKYCRAFT_STUB_LOG
$script:ZoneDeleteAttempts = 0

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

# How the lookup named here fails, if at all. The failure is reported with Write-Error, as the
# Az getters do, so the caller's -ErrorAction decides what happens to it. Returns $true when the
# lookup failed, so the stub returns nothing after it.
function Invoke-StubLookup {
    param([string]$Name, [string]$ResourceGroup = 'platform-skycraft-swc-rg')
    Write-StubCall -Name $Name
    $kind = foreach ($entry in @($env:SKYCRAFT_STUB_LOOKUP -split ',')) {
        $key, $value = $entry -split '=', 2
        if ($key -eq $Name) { $value }
    }
    if (-not $kind -and (Test-StubEmpty)) { $kind = 'notfound' }
    switch ($kind) {
        'denied' {
            Write-Error -ErrorId 'AuthorizationFailed' -Message "The client 'stub' does not have authorization to perform action 'read' over scope '$Name' or the scope is invalid."
            return $true
        }
        'throttled' {
            Write-Error -ErrorId 'TooManyRequests' -Message "Number of 'read' requests exceeded the limit for $Name. Please try again after '17' seconds."
            return $true
        }
        'notfound' {
            Write-Error -ErrorId 'ResourceNotFound' -Message "The Resource 'Microsoft.Network/stubs/$(($Name -split ':')[-1])' under resource group '$ResourceGroup' was not found. For more details please go to https://aka.ms/ARMResourceNotFoundFix"
            return $true
        }
        'rgnotfound' {
            Write-Error -ErrorId 'ResourceGroupNotFound' -Message "Resource group '$ResourceGroup' could not be found."
            return $true
        }
    }
    return $false
}

function Get-AzContext {
    [CmdletBinding()]
    param()
    [pscustomobject]@{
        Subscription = [pscustomobject]@{ Id = '00000000-0000-0000-0000-000000000000'; Name = 'stub-subscription' }
    }
}

function Get-AzDnsZone {
    [CmdletBinding()]
    param([string]$ResourceGroupName, [string]$Name)
    if (Invoke-StubLookup -Name "Get-AzDnsZone:$Name" -ResourceGroup $ResourceGroupName) { return }
    [pscustomobject]@{ Name = $Name }
}

function Remove-AzDnsZone {
    # -Confirm:$false is passed, so the stub has to accept it.
    [CmdletBinding(SupportsShouldProcess)]
    param([string]$ResourceGroupName, [string]$Name)
    Invoke-StubRemoval -Command 'Remove-AzDnsZone' -Name $Name
}

function Get-AzLoadBalancer {
    [CmdletBinding()]
    param([string]$ResourceGroupName, [string]$Name)
    if (Invoke-StubLookup -Name "Get-AzLoadBalancer:$Name" -ResourceGroup $ResourceGroupName) { return }
    [pscustomobject]@{ Name = $Name }
}

function Remove-AzLoadBalancer {
    [CmdletBinding()]
    param([string]$ResourceGroupName, [string]$Name, [switch]$Force)
    Invoke-StubRemoval -Command 'Remove-AzLoadBalancer' -Name $Name
}

function Get-AzPrivateDnsVirtualNetworkLink {
    [CmdletBinding()]
    param([string]$ResourceGroupName, [string]$ZoneName)
    if (Invoke-StubLookup -Name "Get-AzPrivateDnsVirtualNetworkLink:$ZoneName" -ResourceGroup $ResourceGroupName) { return }
    [pscustomobject]@{ Name = 'dev-vnet-link' }
    [pscustomobject]@{ Name = 'prod-vnet-link' }
}

function Remove-AzPrivateDnsVirtualNetworkLink {
    # -Confirm:$false is passed, so the stub has to accept it.
    [CmdletBinding(SupportsShouldProcess)]
    param([string]$ResourceGroupName, [string]$ZoneName, [string]$Name)
    Invoke-StubRemoval -Command 'Remove-AzPrivateDnsVirtualNetworkLink' -Name $Name
}

function Get-AzPrivateDnsZone {
    [CmdletBinding()]
    param([string]$ResourceGroupName, [string]$Name)
    if (Invoke-StubLookup -Name "Get-AzPrivateDnsZone:$Name" -ResourceGroup $ResourceGroupName) { return }
    [pscustomobject]@{ Name = $Name }
}

function Remove-AzPrivateDnsZone {
    # -Confirm:$false is passed, so the stub has to accept it.
    [CmdletBinding(SupportsShouldProcess)]
    param([string]$ResourceGroupName, [string]$Name)
    $script:ZoneDeleteAttempts++
    if ($script:ZoneDeleteAttempts -le [int]$env:SKYCRAFT_STUB_NESTED) {
        Write-StubCall -Name 'Remove-AzPrivateDnsZone:nested'
        throw "Cannot delete resource while nested resources exist. Some existing nested resource IDs are: 'virtualNetworkLinks/dev-vnet-link'."
    }
    Invoke-StubRemoval -Command 'Remove-AzPrivateDnsZone' -Name $Name
}

function Start-Sleep {
    [CmdletBinding()]
    param([int]$Seconds)
    Write-StubCall -Name "Start-Sleep:$Seconds"
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
            [int]$Nested = 0,
            [switch]$Empty
        )

        $logPath = Join-Path $Stub.Directory 'calls.log'
        Remove-Item -LiteralPath $logPath -Force -ErrorAction SilentlyContinue

        $run = Invoke-LabScriptWithStub -Stub $Stub -ScriptPath $script:ScriptPath -ArgumentList $ArgumentList -Environment @{
            SKYCRAFT_STUB_FAIL   = $Fail -join ','
            SKYCRAFT_STUB_LOOKUP = $Lookup -join ','
            SKYCRAFT_STUB_EMPTY  = if ($Empty) { '1' } else { '0' }
            SKYCRAFT_STUB_NESTED = [string]$Nested
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

    # One invocation per scenario, reused by the assertions below - each child process costs
    # several seconds.
    $script:Clean   = Invoke-CleanupScript -Stub $script:Stub
    $script:WhatIf  = Invoke-CleanupScript -Stub $script:Stub -ArgumentList '-WhatIf'
    $script:Nothing = Invoke-CleanupScript -Stub $script:Stub -Empty
    $script:NotFound = Invoke-CleanupScript -Stub $script:Stub -Lookup @(
        'Get-AzDnsZone:skycraft.example.com=notfound'
        'Get-AzLoadBalancer:prod-skycraft-swc-lb=rgnotfound'
    )
    $script:LookupsFail = Invoke-CleanupScript -Stub $script:Stub -Lookup @(
        'Get-AzDnsZone:skycraft.example.com=denied'
        'Get-AzLoadBalancer:dev-skycraft-swc-lb=throttled'
        'Get-AzPrivateDnsVirtualNetworkLink:skycraft.internal=denied'
    )
    $script:ZoneDenied = Invoke-CleanupScript -Stub $script:Stub -Lookup 'Get-AzPrivateDnsZone:skycraft.internal=denied'
    $script:RemovalsFail = Invoke-CleanupScript -Stub $script:Stub -Fail @(
        'Remove-AzDnsZone:skycraft.example.com'
        'Remove-AzLoadBalancer:dev-skycraft-swc-lb'
        'Remove-AzPrivateDnsVirtualNetworkLink:dev-vnet-link'
    )
    $script:ZoneStuck = Invoke-CleanupScript -Stub $script:Stub -Fail 'Remove-AzPrivateDnsZone:skycraft.internal'
    $script:Draining  = Invoke-CleanupScript -Stub $script:Stub -Nested 2

    $script:AllRuns = @(
        $script:Clean, $script:WhatIf, $script:Nothing, $script:NotFound, $script:LookupsFail, $script:ZoneDenied,
        $script:RemovalsFail, $script:ZoneStuck, $script:Draining
    )
}

AfterAll {
    if ($script:StubDir) { Remove-Item -LiteralPath $script:StubDir -Recurse -Force -ErrorAction SilentlyContinue }
}

Describe 'Lab 2.3 Remove-LabResource.ps1 - test harness' {

    It 'shadows the real Az commands instead of touching a subscription' {
        # Refused is the child exiting 99 before the script ran. Asserted on every scenario: a
        # refusal in one of them is a half-stubbed session, not a scenario-specific failure.
        foreach ($run in $script:AllRuns) {
            $run.Refused | Should -BeFalse -Because "the harness must never fall through to the real Az commands (exit $($run.ExitCode)): $($run.Output)"
        }
    }
}

Describe 'Lab 2.3 Remove-LabResource.ps1 - removes what the lab creates' {

    It 'exits 0 when every resource is found and removed' {
        $script:Clean.ExitCode | Should -Be 0 -Because "a clean teardown must report success; output was:`n$($script:Clean.Output)"
        $script:Clean.Output   | Should -Match 'Cleanup Complete'
        $script:Clean.Output   | Should -Not -Match '\[ERROR\]'
    }

    It 'removes the public zone, both load balancers, the VNet links and then the private zone' {
        $calls = $script:Clean.Calls
        foreach ($call in 'Remove-AzDnsZone:skycraft.example.com', 'Remove-AzLoadBalancer:dev-skycraft-swc-lb',
                'Remove-AzLoadBalancer:prod-skycraft-swc-lb', 'Remove-AzPrivateDnsVirtualNetworkLink:dev-vnet-link',
                'Remove-AzPrivateDnsVirtualNetworkLink:prod-vnet-link', 'Remove-AzPrivateDnsZone:skycraft.internal') {
            $calls | Should -Contain $call
        }
        [array]::IndexOf($calls, 'Remove-AzPrivateDnsZone:skycraft.internal') |
            Should -BeGreaterThan ([array]::IndexOf($calls, 'Remove-AzPrivateDnsVirtualNetworkLink:prod-vnet-link'))
    }
}

Describe 'Lab 2.3 Remove-LabResource.ps1 - an absent resource is not a failure' {

    It 'exits 0 and removes nothing when every getter reports not found' {
        $run = $script:Nothing
        $run.ExitCode | Should -Be 0 -Because "nothing to remove is a clean teardown; output was:`n$($run.Output)"
        $run.Output | Should -Not -Match '\[ERROR\]'
        $run.Output | Should -Match 'Cleanup Complete'
        foreach ($line in 'Public Zone not found', 'Dev LB not found', 'Prod LB not found', 'Private Zone not found') {
            $run.Output | Should -Match $line
        }
        @($run.Calls | Where-Object { $_ -match '^Remove-' }) | Should -BeNullOrEmpty
    }

    It 'skips the resources reported as not found, and removes the rest' {
        $run = $script:NotFound
        $run.ExitCode | Should -Be 0 -Because "output was:`n$($run.Output)"
        $run.Output | Should -Not -Match '\[ERROR\]'
        $run.Output | Should -Match 'Public Zone not found'
        $run.Output | Should -Match 'Prod LB not found'
        $run.Calls  | Should -Not -Contain 'Remove-AzDnsZone'
        $run.Calls  | Should -Not -Contain 'Remove-AzLoadBalancer:prod-skycraft-swc-lb'
        $run.Calls  | Should -Contain 'Remove-AzLoadBalancer:dev-skycraft-swc-lb'
        $run.Calls  | Should -Contain 'Remove-AzPrivateDnsZone:skycraft.internal'
    }
}

Describe 'Lab 2.3 Remove-LabResource.ps1 - a failed lookup is not "absent" (#255)' {

    It 'exits 1, counts each failed lookup and carries the Azure error' {
        $run = $script:LookupsFail
        $run.ExitCode | Should -Be 1 -Because "a resource that may still exist must not look like a clean cleanup; output was:`n$($run.Output)"
        $run.Output | Should -Match '\[ERROR\] Could not look up public DNS zone skycraft\.example\.com[^\r\n]*does not have authorization'
        $run.Output | Should -Match '\[ERROR\] Could not look up load balancer dev-skycraft-swc-lb[^\r\n]*requests exceeded the limit'
        $run.Output | Should -Match '\[ERROR\] Could not look up the VNet links of skycraft\.internal'
        $run.Output | Should -Match 'Cleanup finished with 3 failure\(s\)'
        $run.Output | Should -Not -Match 'Cleanup Complete'
    }

    It 'does not report what it could not see as not found, and removes none of it' {
        $run = $script:LookupsFail
        $run.Output | Should -Not -Match 'Public Zone not found'
        $run.Output | Should -Not -Match 'Dev LB not found'
        $run.Calls  | Should -Not -Contain 'Remove-AzDnsZone'
        $run.Calls  | Should -Not -Contain 'Remove-AzLoadBalancer:dev-skycraft-swc-lb'
        $run.Calls  | Should -Contain 'Remove-AzLoadBalancer:prod-skycraft-swc-lb'
    }

    It 'keeps the private zone when its VNet links could not be listed' {
        $run = $script:LookupsFail
        $run.Calls  | Should -Not -Contain 'Remove-AzPrivateDnsZone'
        $run.Output | Should -Match 'skycraft\.internal left in place - its VNet links could not be listed or removed'
    }

    It 'counts a private zone it could not look up, and does not report it absent' {
        $run = $script:ZoneDenied
        $run.ExitCode | Should -Be 1 -Because "output was:`n$($run.Output)"
        $run.Output | Should -Match '\[ERROR\] Could not look up private DNS zone skycraft\.internal'
        $run.Output | Should -Not -Match 'Private Zone not found'
        $run.Output | Should -Match 'Cleanup finished with 1 failure\(s\)'
        $run.Calls  | Should -Not -Contain 'Remove-AzPrivateDnsZone'
    }
}

Describe 'Lab 2.3 Remove-LabResource.ps1 - a failed removal is counted' {

    It 'exits 1 and counts each removal that failed, and keeps going' {
        $run = $script:RemovalsFail
        $run.ExitCode | Should -Be 1 -Because "a stuck resource must not look like a clean cleanup; output was:`n$($run.Output)"
        $run.Output | Should -Match '\[ERROR\] Could not delete the public DNS zone: stub failure'
        $run.Output | Should -Match '\[ERROR\] Could not delete load balancer dev-skycraft-swc-lb: stub failure'
        $run.Output | Should -Match '\[ERROR\] Could not delete link dev-vnet-link: stub failure'
        $run.Output | Should -Match 'Cleanup finished with 3 failure\(s\)'
        $run.Calls  | Should -Contain 'Remove-AzLoadBalancer:prod-skycraft-swc-lb'
        $run.Calls  | Should -Contain 'Remove-AzPrivateDnsVirtualNetworkLink:prod-vnet-link'
    }

    It 'keeps the private zone when one of its VNet links could not be removed' {
        $script:RemovalsFail.Calls  | Should -Not -Contain 'Remove-AzPrivateDnsZone'
        $script:RemovalsFail.Output | Should -Match 'skycraft\.internal left in place'
    }

    It 'counts a private zone delete that fails with anything but the nested-resource error' {
        $run = $script:ZoneStuck
        $run.ExitCode | Should -Be 1 -Because "output was:`n$($run.Output)"
        $run.Output | Should -Match '\[ERROR\] Could not delete the private DNS zone: stub failure'
        $run.Output | Should -Match 'Cleanup finished with 1 failure\(s\)'
        @($run.Calls | Where-Object { $_ -like 'Start-Sleep:*' }) | Should -BeNullOrEmpty -Because 'only the nested-resource error is retried (#97)'
    }

    It 'still retries the private zone delete while the VNet links drain (#97)' {
        $run = $script:Draining
        $run.ExitCode | Should -Be 0 -Because "output was:`n$($run.Output)"
        @($run.Calls | Where-Object { $_ -eq 'Remove-AzPrivateDnsZone:nested' }).Count | Should -Be 2
        $run.Calls  | Should -Contain 'Remove-AzPrivateDnsZone:skycraft.internal'
        $run.Output | Should -Match 'VNet links still draining, retrying'
    }
}

Describe 'Lab 2.3 Remove-LabResource.ps1 - -WhatIf' {

    It 'looks everything up and removes nothing' {
        $run = $script:WhatIf
        $run.ExitCode | Should -Be 0 -Because "output was:`n$($run.Output)"
        @($run.Calls | Where-Object { $_ -match '^Remove-' }) | Should -BeNullOrEmpty
        $run.Calls  | Should -Contain 'Get-AzDnsZone:skycraft.example.com'
        $run.Calls  | Should -Contain 'Get-AzPrivateDnsZone:skycraft.internal'
        $run.Output | Should -Match 'What if: .*dev-skycraft-swc-lb'
        $run.Output | Should -Match 'What if: .*skycraft\.internal'
    }
}
