<#
.SYNOPSIS
    Pester 5 tests for the Lab 2.1 cleanup: when it reports a resource absent, and when it exits 1.

.DESCRIPTION
    Regression cover for issue #255. The cleanup looked the VNets and the load balancer public IPs
    up with -ErrorAction SilentlyContinue, so a lookup that failed (a 403, throttling) read as
    "not found or already deleted": the resource was skipped and the run could exit 0 while it
    still existed. The preflight did the same to the target of a service association link, and
    reported a link whose target it merely could not read as ORPHANED. These tests run the real
    Remove-LabResource.ps1 in a child pwsh process against a generated stub of the Az commands it
    calls, and assert the observable contract:

      1. Every lab VNet (with its peerings) and both public IPs are removed, and the run exits 0.
      2. A resource reported as not found, or one that is not there at all, is not a failure: the
         run exits 0.
      3. A lookup that fails with an error is an [ERROR], counted, and the run exits 1 without
         touching or reporting absent the resource it could not see. The stub reports the failure
         with Write-Error, as the Az getters do, so a script that passes -ErrorAction
         SilentlyContinue swallows it - the defect #255 describes.
      4. A removal that fails is an [ERROR], counted, and the later steps still run: exit 1.
      5. The preflight stays diagnostic (issue #110): a VNet it cannot read is a [WARN], not a
         failure, and a link target it cannot read is "unverified", never "ORPHANED".

    The preflight's pure helpers are pinned by tests/Lab21-Subnet-Link-Preflight.Tests.ps1, and
    which errors mean "not found" by tests/Lab-Cleanup-Lookup.Tests.ps1.

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
    Lab: 2.1 - Virtual Networks
#>

#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..' '..' '..' 'tests' 'Support' 'LabScriptStub.psm1') -Force

    $script:ScriptPath     = (Resolve-Path (Join-Path $PSScriptRoot '..' 'scripts' 'Remove-LabResource.ps1')).Path
    $script:StubModuleName = 'SkyCraftLab21CleanupStub'
    # Exactly the script's '#Requires -Modules' line: these are imported for real before the stub.
    $script:RequiredModules = @('Az.Accounts', 'Az.Network', 'Az.Resources')

    $script:StubCommands = @(
        'Get-AzContext'
        'Get-AzVirtualNetwork'
        'Remove-AzVirtualNetworkPeering'
        'Remove-AzVirtualNetwork'
        'Get-AzPublicIpAddress'
        'Remove-AzPublicIpAddress'
        'Get-AzResource'
    )

    # Every command the script calls, recording its own invocation. By default the subscription
    # holds the three lab VNets, peered hub-and-spoke, and both load balancer public IPs.
    # Environment variables change that, so one generated module serves every scenario:
    #   SKYCRAFT_STUB_EMPTY   '1' leaves nothing to find: every getter reports ResourceNotFound,
    #                         as the real ones do for a name that does not exist
    #   SKYCRAFT_STUB_LINK    '1' puts a service association link on the prod AppServiceSubnet,
    #                         naming an App Service Plan that Get-AzResource is asked about
    #   SKYCRAFT_STUB_LOOKUP  '<lookup>=<kind>,...' makes one lookup fail (denied, throttled) or
    #                         report its resource not found (notfound, rgnotfound)
    #   SKYCRAFT_STUB_FAIL    '<Remove-command>:<name>,...' makes one removal throw
    # A lookup is named after its command and the resource it reads: 'Get-AzVirtualNetwork:<vnet>',
    # 'Get-AzPublicIpAddress:<pip>', 'Get-AzResource:<last id segment>'. A VNet is read up to three
    # times - preflight, peerings, delete - and every read follows the same entry.
    $script:StubBody = @'
$script:LogPath = $env:SKYCRAFT_STUB_LOG

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
    param([string]$Name, [string]$ResourceGroup = 'prod-skycraft-swc-rg')
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

function Get-AzVirtualNetwork {
    [CmdletBinding()]
    param([string]$Name, [string]$ResourceGroupName)
    if (Invoke-StubLookup -Name "Get-AzVirtualNetwork:$Name" -ResourceGroup $ResourceGroupName) { return }
    $peerings = switch -Wildcard ($Name) {
        'platform-*' { 'hub-to-dev', 'hub-to-prod' }
        'dev-*'      { 'dev-to-hub' }
        'prod-*'     { 'prod-to-hub' }
    }
    $links = @()
    if ($Name -like 'prod-*' -and $env:SKYCRAFT_STUB_LINK -eq '1') {
        $links = @([pscustomobject]@{
            Name        = 'AppServiceLink'
            Link        = '/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/prod-skycraft-swc-rg/providers/Microsoft.Web/serverfarms/prod-skycraft-swc-asp'
            AllowDelete = $false
        })
    }
    [pscustomobject]@{
        Name                   = $Name
        VirtualNetworkPeerings = @($peerings | ForEach-Object { [pscustomobject]@{ Name = $_ } })
        Subnets                = @([pscustomobject]@{ Name = 'AppServiceSubnet'; ServiceAssociationLinks = $links })
    }
}

function Remove-AzVirtualNetworkPeering {
    [CmdletBinding()]
    param([string]$VirtualNetworkName, [string]$ResourceGroupName, [string]$Name, [switch]$Force)
    Invoke-StubRemoval -Command 'Remove-AzVirtualNetworkPeering' -Name "$VirtualNetworkName/$Name"
}

function Remove-AzVirtualNetwork {
    [CmdletBinding()]
    param([string]$Name, [string]$ResourceGroupName, [switch]$Force)
    Invoke-StubRemoval -Command 'Remove-AzVirtualNetwork' -Name $Name
}

function Get-AzPublicIpAddress {
    [CmdletBinding()]
    param([string]$Name, [string]$ResourceGroupName)
    if (Invoke-StubLookup -Name "Get-AzPublicIpAddress:$Name" -ResourceGroup $ResourceGroupName) { return }
    [pscustomobject]@{ Name = $Name }
}

function Remove-AzPublicIpAddress {
    [CmdletBinding()]
    param([string]$Name, [string]$ResourceGroupName, [switch]$Force)
    Invoke-StubRemoval -Command 'Remove-AzPublicIpAddress' -Name $Name
}

function Get-AzResource {
    [CmdletBinding()]
    param([string]$ResourceId)
    if (Invoke-StubLookup -Name "Get-AzResource:$(($ResourceId -split '/')[-1])") { return }
    [pscustomobject]@{ ResourceId = $ResourceId }
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
            [switch]$Empty,
            [switch]$Link
        )

        $logPath = Join-Path $Stub.Directory 'calls.log'
        Remove-Item -LiteralPath $logPath -Force -ErrorAction SilentlyContinue

        $run = Invoke-LabScriptWithStub -Stub $Stub -ScriptPath $script:ScriptPath -ArgumentList $ArgumentList -Environment @{
            SKYCRAFT_STUB_FAIL   = $Fail -join ','
            SKYCRAFT_STUB_LOOKUP = $Lookup -join ','
            SKYCRAFT_STUB_EMPTY  = if ($Empty) { '1' } else { '0' }
            SKYCRAFT_STUB_LINK   = if ($Link) { '1' } else { '0' }
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
    $script:Nothing = Invoke-CleanupScript -Stub $script:Stub -Empty
    $script:NotFound = Invoke-CleanupScript -Stub $script:Stub -Lookup @(
        'Get-AzVirtualNetwork:dev-skycraft-swc-vnet=notfound'
        'Get-AzPublicIpAddress:prod-skycraft-swc-lb-pip=rgnotfound'
    )
    $script:LookupsFail = Invoke-CleanupScript -Stub $script:Stub -Lookup @(
        'Get-AzVirtualNetwork:prod-skycraft-swc-vnet=denied'
        'Get-AzPublicIpAddress:dev-skycraft-swc-lb-pip=throttled'
    )
    $script:RemovalsFail = Invoke-CleanupScript -Stub $script:Stub -Fail @(
        'Remove-AzVirtualNetwork:prod-skycraft-swc-vnet'
        'Remove-AzPublicIpAddress:dev-skycraft-swc-lb-pip'
    )
    $script:LinkOrphaned   = Invoke-CleanupScript -Stub $script:Stub -Link -Lookup 'Get-AzResource:prod-skycraft-swc-asp=notfound'
    $script:LinkUnverified = Invoke-CleanupScript -Stub $script:Stub -Link -Lookup 'Get-AzResource:prod-skycraft-swc-asp=denied'

    $script:AllRuns = @(
        $script:Clean, $script:Nothing, $script:NotFound, $script:LookupsFail, $script:RemovalsFail,
        $script:LinkOrphaned, $script:LinkUnverified
    )
}

AfterAll {
    if ($script:StubDir) { Remove-Item -LiteralPath $script:StubDir -Recurse -Force -ErrorAction SilentlyContinue }
}

Describe 'Lab 2.1 Remove-LabResource.ps1 - test harness' {

    It 'shadows the real Az commands instead of touching a subscription' {
        # Refused is the child exiting 99 before the script ran. Asserted on every scenario: a
        # refusal in one of them is a half-stubbed session, not a scenario-specific failure.
        foreach ($run in $script:AllRuns) {
            $run.Refused | Should -BeFalse -Because "the harness must never fall through to the real Az commands (exit $($run.ExitCode)): $($run.Output)"
        }
    }
}

Describe 'Lab 2.1 Remove-LabResource.ps1 - removes what the lab creates' {

    It 'exits 0 when every resource is found and removed' {
        $script:Clean.ExitCode | Should -Be 0 -Because "a clean teardown must report success; output was:`n$($script:Clean.Output)"
        $script:Clean.Output   | Should -Match 'Cleanup Complete'
        $script:Clean.Output   | Should -Not -Match '\[ERROR\]'
    }

    It 'removes every peering, the three VNets and both public IPs' {
        foreach ($call in 'Remove-AzVirtualNetworkPeering:platform-skycraft-swc-vnet/hub-to-dev',
                'Remove-AzVirtualNetworkPeering:platform-skycraft-swc-vnet/hub-to-prod',
                'Remove-AzVirtualNetworkPeering:dev-skycraft-swc-vnet/dev-to-hub',
                'Remove-AzVirtualNetworkPeering:prod-skycraft-swc-vnet/prod-to-hub',
                'Remove-AzVirtualNetwork:platform-skycraft-swc-vnet', 'Remove-AzVirtualNetwork:dev-skycraft-swc-vnet',
                'Remove-AzVirtualNetwork:prod-skycraft-swc-vnet',
                'Remove-AzPublicIpAddress:dev-skycraft-swc-lb-pip', 'Remove-AzPublicIpAddress:prod-skycraft-swc-lb-pip') {
            $script:Clean.Calls | Should -Contain $call
        }
    }
}

Describe 'Lab 2.1 Remove-LabResource.ps1 - an absent resource is not a failure' {

    It 'exits 0 and removes nothing when every getter reports not found' {
        $run = $script:Nothing
        $run.ExitCode | Should -Be 0 -Because "nothing to remove is a clean teardown; output was:`n$($run.Output)"
        $run.Output | Should -Not -Match '\[ERROR\]'
        $run.Output | Should -Match 'Cleanup Complete'
        $run.Output | Should -Match 'VNet prod-skycraft-swc-vnet not found or already deleted'
        $run.Output | Should -Match 'PIP dev-skycraft-swc-lb-pip not found or already deleted'
        @($run.Calls | Where-Object { $_ -match '^Remove-' }) | Should -BeNullOrEmpty
    }

    It 'skips a VNet and a public IP reported as not found, and removes the rest' {
        $run = $script:NotFound
        $run.ExitCode | Should -Be 0 -Because "output was:`n$($run.Output)"
        $run.Output | Should -Not -Match '\[ERROR\]'
        $run.Output | Should -Match 'VNet dev-skycraft-swc-vnet not found or already deleted'
        $run.Output | Should -Match 'PIP prod-skycraft-swc-lb-pip not found or already deleted'
        $run.Calls  | Should -Not -Contain 'Remove-AzVirtualNetwork:dev-skycraft-swc-vnet'
        $run.Calls  | Should -Not -Contain 'Remove-AzPublicIpAddress:prod-skycraft-swc-lb-pip'
        $run.Calls  | Should -Contain 'Remove-AzVirtualNetwork:prod-skycraft-swc-vnet'
        $run.Calls  | Should -Contain 'Remove-AzPublicIpAddress:dev-skycraft-swc-lb-pip'
    }
}

Describe 'Lab 2.1 Remove-LabResource.ps1 - a failed lookup is not "absent" (#255)' {

    It 'exits 1, counts each failed lookup and carries the Azure error' {
        $run = $script:LookupsFail
        $run.ExitCode | Should -Be 1 -Because "a resource that may still exist must not look like a clean cleanup; output was:`n$($run.Output)"
        $run.Output | Should -Match '\[ERROR\] Could not look up VNet prod-skycraft-swc-vnet[^\r\n]*does not have authorization'
        $run.Output | Should -Match '\[ERROR\] Could not look up PIP dev-skycraft-swc-lb-pip[^\r\n]*requests exceeded the limit'
        # The prod VNet counts twice: once for its peerings, once for the VNet itself.
        $run.Output | Should -Match 'Cleanup finished with 3 failure\(s\)'
        $run.Output | Should -Not -Match 'Cleanup Complete'
    }

    It 'does not report what it could not see as not found, and removes none of it' {
        $run = $script:LookupsFail
        $run.Output | Should -Not -Match 'VNet prod-skycraft-swc-vnet not found'
        $run.Output | Should -Not -Match 'PIP dev-skycraft-swc-lb-pip not found'
        $run.Calls  | Should -Not -Contain 'Remove-AzVirtualNetwork:prod-skycraft-swc-vnet'
        $run.Calls  | Should -Not -Contain 'Remove-AzVirtualNetworkPeering:prod-skycraft-swc-vnet/prod-to-hub'
        $run.Calls  | Should -Not -Contain 'Remove-AzPublicIpAddress:dev-skycraft-swc-lb-pip'
    }

    It 'still removes everything it could look up' {
        $run = $script:LookupsFail
        $run.Calls | Should -Contain 'Remove-AzVirtualNetwork:platform-skycraft-swc-vnet'
        $run.Calls | Should -Contain 'Remove-AzVirtualNetwork:dev-skycraft-swc-vnet'
        $run.Calls | Should -Contain 'Remove-AzPublicIpAddress:prod-skycraft-swc-lb-pip'
    }

    It 'keeps the preflight diagnostic: a VNet it cannot read is a warning, counted only by the deletes' {
        $script:LookupsFail.Output | Should -Match '\[WARN\] VNet prod-skycraft-swc-vnet could not be looked up - not checked'
    }
}

Describe 'Lab 2.1 Remove-LabResource.ps1 - a failed removal is counted' {

    It 'exits 1 and counts each removal that failed' {
        $run = $script:RemovalsFail
        $run.ExitCode | Should -Be 1 -Because "a stuck resource must not look like a clean cleanup; output was:`n$($run.Output)"
        $run.Output | Should -Match '\[ERROR\] Failed to remove VNet prod-skycraft-swc-vnet: stub failure'
        $run.Output | Should -Match '\[ERROR\] Failed to remove PIP dev-skycraft-swc-lb-pip: stub failure'
        $run.Output | Should -Match 'Cleanup finished with 2 failure\(s\)'
        $run.Calls  | Should -Contain 'Remove-AzPublicIpAddress:prod-skycraft-swc-lb-pip'
    }
}

Describe 'Lab 2.1 Remove-LabResource.ps1 - the preflight tells an orphan from an unreadable target (#110, #255)' {

    It 'calls a link whose target is reported as not found an orphan' {
        $run = $script:LinkOrphaned
        $run.Output | Should -Match 'AppServiceSubnet carries serviceAssociationLink [^\r\n]*ORPHANED'
        $run.Output | Should -Match '1 orphaned link\(s\)'
    }

    It 'reports a link whose target cannot be looked up as unverified, not orphaned' {
        $run = $script:LinkUnverified
        $run.Output | Should -Match 'AppServiceSubnet carries serviceAssociationLink [^\r\n]*target unverified'
        $run.Output | Should -Not -Match 'ORPHANED'
        $run.Output | Should -Not -Match 'orphaned link\(s\)'
    }

    It 'never changes the exit code on its own' {
        $script:LinkOrphaned.ExitCode   | Should -Be 0 -Because "output was:`n$($script:LinkOrphaned.Output)"
        $script:LinkUnverified.ExitCode | Should -Be 0 -Because "output was:`n$($script:LinkUnverified.Output)"
    }
}
