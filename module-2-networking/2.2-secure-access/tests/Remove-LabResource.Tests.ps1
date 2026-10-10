<#
.SYNOPSIS
    Pester 5 tests for the Lab 2.2 cleanup: when it reports a resource absent, and when it exits 1.

.DESCRIPTION
    Regression cover for issue #255. The cleanup looked Azure Bastion and its public IP up with
    -ErrorAction SilentlyContinue, so a lookup that failed (a 403, throttling) read as "does not
    exist"; it deleted the NSGs and ASGs with -ErrorAction SilentlyContinue and printed "Success"
    whatever happened; and it exited 0 even when a removal threw. These tests run the real
    Remove-LabResource.ps1 in a child pwsh process against a generated stub of the Az commands it
    calls, and assert the observable contract:

      1. Bastion, its public IP, the seven NSGs (dissociated from their subnets first) and the
         six ASGs are removed when present, and the run exits 0.
      2. A resource reported as not found is not a failure: the run exits 0.
      3. A lookup that fails with an error is an [ERROR], counted, and the run exits 1 without
         touching or reporting absent the resource it could not see. The stub reports the failure
         with Write-Error, as the Az getters do, so a script that passes -ErrorAction
         SilentlyContinue swallows it - the defect #255 describes.
      4. A removal that fails is an [ERROR], counted, and the later steps still run: exit 1.
      5. The -RemoveBastion / -RemoveNSGs / -RemoveASGs switches still narrow the run.

    Which errors mean "not found" is pinned for every cleanup that carries the helpers by
    tests/Lab-Cleanup-Lookup.Tests.ps1.

    Scope limit, as in the Lab 5.2 suite: the child is launched with -Command, so these tests
    prove the failure counter reaches `exit`, not that `pwsh -File` carries the code out of the
    process. That half is issue #104's guard, enforced by tests/Exit-Code-Propagation.Tests.ps1.

    No subscription is needed, and none is used. The script runs through
    tests/Support/LabScriptStub.psm1 (issue #112), which aborts the child with exit 99 unless every
    stubbed command resolves to the stub. Start-Sleep is stubbed too, so the settle wait costs
    nothing.

.EXAMPLE
    Invoke-Pester -Path .\Remove-LabResource.Tests.ps1

.NOTES
    Project: SkyCraft
    Lab: 2.2 - Secure Access
#>

#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..' '..' '..' 'tests' 'Support' 'LabScriptStub.psm1') -Force

    $script:ScriptPath     = (Resolve-Path (Join-Path $PSScriptRoot '..' 'scripts' 'Remove-LabResource.ps1')).Path
    $script:StubModuleName = 'SkyCraftLab22CleanupStub'
    # Exactly the script's '#Requires -Modules' line: these are imported for real before the stub.
    $script:RequiredModules = @('Az.Accounts', 'Az.Network')

    $script:StubCommands = @(
        'Get-AzContext'
        'Get-AzBastion'
        'Remove-AzBastion'
        'Get-AzPublicIpAddress'
        'Remove-AzPublicIpAddress'
        'Get-AzVirtualNetwork'
        'Set-AzVirtualNetwork'
        'Get-AzNetworkSecurityGroup'
        'Remove-AzNetworkSecurityGroup'
        'Get-AzApplicationSecurityGroup'
        'Remove-AzApplicationSecurityGroup'
        'Start-Sleep'
    )

    # Every command the script calls, recording its own invocation. By default the subscription
    # holds everything the lab creates: Bastion and its public IP, the NSGs - each associated
    # with a subnet of its environment's VNet - and the ASGs. Environment variables change that,
    # so one generated module serves every scenario:
    #   SKYCRAFT_STUB_EMPTY   '1' leaves nothing to find: every named getter reports
    #                         ResourceNotFound, as the real ones do, and the VNets carry no NSG
    #   SKYCRAFT_STUB_LOOKUP  '<lookup>=<kind>,...' makes one lookup fail (denied, throttled) or
    #                         report its resource not found (notfound, rgnotfound)
    #   SKYCRAFT_STUB_FAIL    '<command>:<name>,...' makes one removal (or VNet update) throw
    # A lookup is named after its command and the resource it reads ('Get-AzBastion:<name>',
    # 'Get-AzNetworkSecurityGroup:<name>', ...); the VNet listing is 'Get-AzVirtualNetwork'.
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
# lookup failed, so the stub returns nothing after it. -Named lookups report a missing resource
# as not found when the subscription is empty; the VNet listing just comes back empty.
function Invoke-StubLookup {
    param([string]$Name, [string]$ResourceGroup = 'platform-skycraft-swc-rg', [switch]$Named)
    Write-StubCall -Name $Name
    $kind = foreach ($entry in @($env:SKYCRAFT_STUB_LOOKUP -split ',')) {
        $key, $value = $entry -split '=', 2
        if ($key -eq $Name) { $value }
    }
    if (-not $kind -and $Named -and (Test-StubEmpty)) { $kind = 'notfound' }
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

function Get-AzBastion {
    [CmdletBinding()]
    param([string]$ResourceGroupName, [string]$Name)
    if (Invoke-StubLookup -Name "Get-AzBastion:$Name" -ResourceGroup $ResourceGroupName -Named) { return }
    [pscustomobject]@{ Name = $Name }
}

function Remove-AzBastion {
    [CmdletBinding()]
    param([string]$ResourceGroupName, [string]$Name, [switch]$Force)
    Invoke-StubRemoval -Command 'Remove-AzBastion' -Name $Name
}

function Get-AzPublicIpAddress {
    [CmdletBinding()]
    param([string]$ResourceGroupName, [string]$Name)
    if (Invoke-StubLookup -Name "Get-AzPublicIpAddress:$Name" -ResourceGroup $ResourceGroupName -Named) { return }
    [pscustomobject]@{ Name = $Name }
}

function Remove-AzPublicIpAddress {
    [CmdletBinding()]
    param([string]$ResourceGroupName, [string]$Name, [switch]$Force)
    Invoke-StubRemoval -Command 'Remove-AzPublicIpAddress' -Name $Name
}

function Get-AzVirtualNetwork {
    [CmdletBinding()]
    param()
    if (Invoke-StubLookup -Name 'Get-AzVirtualNetwork') { return }
    foreach ($envName in 'dev', 'prod') {
        $nsgId = if (Test-StubEmpty) { $null } else {
            "/subscriptions/0/resourceGroups/$envName-skycraft-swc-rg/providers/Microsoft.Network/networkSecurityGroups/$envName-skycraft-swc-auth-nsg"
        }
        $subnet = [pscustomobject]@{
            Name                 = 'AuthSubnet'
            NetworkSecurityGroup = if ($nsgId) { [pscustomobject]@{ Id = $nsgId } } else { $null }
        }
        [pscustomobject]@{ Name = "$envName-skycraft-swc-vnet"; Subnets = @($subnet) }
    }
}

function Set-AzVirtualNetwork {
    [CmdletBinding()]
    param([Parameter(ValueFromPipeline = $true)]$VirtualNetwork)
    process { Invoke-StubRemoval -Command 'Set-AzVirtualNetwork' -Name $VirtualNetwork.Name }
}

function Get-AzNetworkSecurityGroup {
    [CmdletBinding()]
    param([string]$ResourceGroupName, [string]$Name)
    if (Invoke-StubLookup -Name "Get-AzNetworkSecurityGroup:$Name" -ResourceGroup $ResourceGroupName -Named) { return }
    [pscustomobject]@{ Name = $Name }
}

function Remove-AzNetworkSecurityGroup {
    [CmdletBinding()]
    param([string]$ResourceGroupName, [string]$Name, [switch]$Force)
    Invoke-StubRemoval -Command 'Remove-AzNetworkSecurityGroup' -Name $Name
}

function Get-AzApplicationSecurityGroup {
    [CmdletBinding()]
    param([string]$ResourceGroupName, [string]$Name)
    if (Invoke-StubLookup -Name "Get-AzApplicationSecurityGroup:$Name" -ResourceGroup $ResourceGroupName -Named) { return }
    [pscustomobject]@{ Name = $Name }
}

function Remove-AzApplicationSecurityGroup {
    [CmdletBinding()]
    param([string]$ResourceGroupName, [string]$Name, [switch]$Force)
    Invoke-StubRemoval -Command 'Remove-AzApplicationSecurityGroup' -Name $Name
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

    $script:Nsgs = @(
        'dev-skycraft-swc-auth-nsg', 'dev-skycraft-swc-world-nsg', 'dev-skycraft-swc-db-nsg',
        'prod-skycraft-swc-auth-nsg', 'prod-skycraft-swc-world-nsg', 'prod-skycraft-swc-db-nsg',
        'platform-skycraft-swc-nsg'
    )
    $script:Asgs = @(
        'dev-skycraft-swc-asg-auth', 'dev-skycraft-swc-asg-world', 'dev-skycraft-swc-asg-db',
        'prod-skycraft-swc-asg-auth', 'prod-skycraft-swc-asg-world', 'prod-skycraft-swc-asg-db'
    )

    # One invocation per scenario, reused by the assertions below - each child process costs
    # several seconds.
    $script:Clean   = Invoke-CleanupScript -Stub $script:Stub
    $script:Nothing = Invoke-CleanupScript -Stub $script:Stub -Empty
    $script:NotFound = Invoke-CleanupScript -Stub $script:Stub -Lookup @(
        'Get-AzBastion:platform-skycraft-swc-bas=notfound'
        'Get-AzNetworkSecurityGroup:dev-skycraft-swc-db-nsg=rgnotfound'
    )
    $script:LookupsFail = Invoke-CleanupScript -Stub $script:Stub -Lookup @(
        'Get-AzBastion:platform-skycraft-swc-bas=denied'
        'Get-AzVirtualNetwork=throttled'
        'Get-AzNetworkSecurityGroup:prod-skycraft-swc-db-nsg=denied'
        'Get-AzApplicationSecurityGroup:dev-skycraft-swc-asg-world=throttled'
    )
    $script:RemovalsFail = Invoke-CleanupScript -Stub $script:Stub -Fail @(
        'Remove-AzBastion:platform-skycraft-swc-bas'
        'Set-AzVirtualNetwork:dev-skycraft-swc-vnet'
        'Remove-AzNetworkSecurityGroup:prod-skycraft-swc-world-nsg'
        'Remove-AzApplicationSecurityGroup:prod-skycraft-swc-asg-db'
    )
    $script:BastionOnly = Invoke-CleanupScript -Stub $script:Stub -ArgumentList '-RemoveBastion', '-Force'

    $script:AllRuns = @(
        $script:Clean, $script:Nothing, $script:NotFound, $script:LookupsFail, $script:RemovalsFail,
        $script:BastionOnly
    )
}

AfterAll {
    if ($script:StubDir) { Remove-Item -LiteralPath $script:StubDir -Recurse -Force -ErrorAction SilentlyContinue }
}

Describe 'Lab 2.2 Remove-LabResource.ps1 - test harness' {

    It 'shadows the real Az commands instead of touching a subscription' {
        # Refused is the child exiting 99 before the script ran. Asserted on every scenario: a
        # refusal in one of them is a half-stubbed session, not a scenario-specific failure.
        foreach ($run in $script:AllRuns) {
            $run.Refused | Should -BeFalse -Because "the harness must never fall through to the real Az commands (exit $($run.ExitCode)): $($run.Output)"
        }
    }
}

Describe 'Lab 2.2 Remove-LabResource.ps1 - removes what the lab creates' {

    It 'exits 0 when every resource is found and removed' {
        $script:Clean.ExitCode | Should -Be 0 -Because "a clean teardown must report success; output was:`n$($script:Clean.Output)"
        $script:Clean.Output   | Should -Match 'Cleanup Complete'
        $script:Clean.Output   | Should -Not -Match '\[ERROR\]'
    }

    It 'removes Bastion, its public IP, every NSG and every ASG' {
        $script:Clean.Calls | Should -Contain 'Remove-AzBastion:platform-skycraft-swc-bas'
        $script:Clean.Calls | Should -Contain 'Remove-AzPublicIpAddress:platform-skycraft-swc-bas-pip'
        foreach ($nsg in $script:Nsgs) { $script:Clean.Calls | Should -Contain "Remove-AzNetworkSecurityGroup:$nsg" }
        foreach ($asg in $script:Asgs) { $script:Clean.Calls | Should -Contain "Remove-AzApplicationSecurityGroup:$asg" }
    }

    It 'dissociates the NSGs from their subnets before deleting them' {
        $calls    = $script:Clean.Calls
        $dissoc   = [array]::IndexOf($calls, 'Set-AzVirtualNetwork:prod-skycraft-swc-vnet')
        $firstNsg = [array]::IndexOf($calls, 'Remove-AzNetworkSecurityGroup')
        $calls    | Should -Contain 'Set-AzVirtualNetwork:dev-skycraft-swc-vnet'
        $dissoc   | Should -BeGreaterThan -1
        $firstNsg | Should -BeGreaterThan $dissoc
    }
}

Describe 'Lab 2.2 Remove-LabResource.ps1 - an absent resource is not a failure' {

    It 'exits 0 and removes nothing when every getter reports not found' {
        $run = $script:Nothing
        $run.ExitCode | Should -Be 0 -Because "nothing to remove is a clean teardown; output was:`n$($run.Output)"
        $run.Output | Should -Not -Match '\[ERROR\]'
        $run.Output | Should -Match 'Cleanup Complete'
        $run.Output | Should -Match 'Bastion does not exist, skipping'
        $run.Output | Should -Match 'Bastion Public IP does not exist, skipping'
        $run.Output | Should -Match 'NSG does not exist, skipping'
        $run.Output | Should -Match 'ASG does not exist, skipping'
        @($run.Calls | Where-Object { $_ -match '^(Remove|Set)-' }) | Should -BeNullOrEmpty
    }

    It 'skips the resources reported as not found, and removes the rest' {
        $run = $script:NotFound
        $run.ExitCode | Should -Be 0 -Because "output was:`n$($run.Output)"
        $run.Output | Should -Not -Match '\[ERROR\]'
        $run.Calls  | Should -Not -Contain 'Remove-AzBastion'
        $run.Calls  | Should -Not -Contain 'Remove-AzNetworkSecurityGroup:dev-skycraft-swc-db-nsg'
        $run.Calls  | Should -Contain 'Remove-AzNetworkSecurityGroup:prod-skycraft-swc-db-nsg'
        $run.Calls  | Should -Contain 'Remove-AzPublicIpAddress:platform-skycraft-swc-bas-pip'
    }
}

Describe 'Lab 2.2 Remove-LabResource.ps1 - a failed lookup is not "absent" (#255)' {

    It 'exits 1, counts each failed lookup and carries the Azure error' {
        $run = $script:LookupsFail
        $run.ExitCode | Should -Be 1 -Because "a resource that may still exist must not look like a clean cleanup; output was:`n$($run.Output)"
        $run.Output | Should -Match '\[ERROR\] Could not look up Bastion platform-skycraft-swc-bas[^\r\n]*does not have authorization'
        $run.Output | Should -Match '\[ERROR\] Could not look up the virtual networks in the subscription[^\r\n]*requests exceeded the limit'
        $run.Output | Should -Match '\[ERROR\] Could not look up NSG prod-skycraft-swc-db-nsg'
        $run.Output | Should -Match '\[ERROR\] Could not look up ASG dev-skycraft-swc-asg-world'
        $run.Output | Should -Match 'Cleanup finished with 4 failure\(s\)'
        $run.Output | Should -Not -Match 'Cleanup Complete'
    }

    It 'does not report what it could not see as absent, and removes none of it' {
        $run = $script:LookupsFail
        $run.Output | Should -Not -Match 'Bastion does not exist'
        $run.Calls  | Should -Not -Contain 'Remove-AzBastion'
        $run.Calls  | Should -Not -Contain 'Remove-AzNetworkSecurityGroup:prod-skycraft-swc-db-nsg'
        $run.Calls  | Should -Not -Contain 'Remove-AzApplicationSecurityGroup:dev-skycraft-swc-asg-world'
        # Without the VNet listing nothing can be dissociated.
        @($run.Calls | Where-Object { $_ -match '^Set-AzVirtualNetwork' }) | Should -BeNullOrEmpty
    }

    It 'still removes everything it could look up' {
        $run = $script:LookupsFail
        $run.Calls | Should -Contain 'Remove-AzPublicIpAddress:platform-skycraft-swc-bas-pip'
        $run.Calls | Should -Contain 'Remove-AzNetworkSecurityGroup:dev-skycraft-swc-db-nsg'
        $run.Calls | Should -Contain 'Remove-AzApplicationSecurityGroup:prod-skycraft-swc-asg-db'
    }
}

Describe 'Lab 2.2 Remove-LabResource.ps1 - a failed removal is counted' {

    It 'exits 1 and counts each removal that failed, which it used to report as success' {
        $run = $script:RemovalsFail
        $run.ExitCode | Should -Be 1 -Because "a stuck resource must not look like a clean cleanup; output was:`n$($run.Output)"
        $run.Output | Should -Match '\[ERROR\] Failed to remove Bastion'
        $run.Output | Should -Match '\[ERROR\] Could not dissociate the NSGs from dev-skycraft-swc-vnet'
        $run.Output | Should -Match '\[ERROR\] Could not delete prod-skycraft-swc-world-nsg: stub failure'
        $run.Output | Should -Match '\[ERROR\] Could not delete prod-skycraft-swc-asg-db: stub failure'
        $run.Output | Should -Match 'Cleanup finished with 4 failure\(s\)'
        $run.Output | Should -Not -Match 'Cleanup Complete'
    }

    It 'keeps going after a failed removal' {
        $run = $script:RemovalsFail
        $run.Calls | Should -Contain 'Remove-AzPublicIpAddress:platform-skycraft-swc-bas-pip'
        $run.Calls | Should -Contain 'Remove-AzNetworkSecurityGroup:platform-skycraft-swc-nsg'
        $run.Calls | Should -Contain 'Remove-AzApplicationSecurityGroup:prod-skycraft-swc-asg-world'
    }
}

Describe 'Lab 2.2 Remove-LabResource.ps1 - the component switches still narrow the run' {

    It 'removes only Bastion and its public IP with -RemoveBastion' {
        $run = $script:BastionOnly
        $run.ExitCode | Should -Be 0 -Because "output was:`n$($run.Output)"
        $run.Calls | Should -Contain 'Remove-AzBastion:platform-skycraft-swc-bas'
        @($run.Calls | Where-Object { $_ -match 'SecurityGroup' }) | Should -BeNullOrEmpty
    }
}
