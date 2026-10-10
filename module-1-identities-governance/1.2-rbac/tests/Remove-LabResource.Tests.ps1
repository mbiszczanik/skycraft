<#
.SYNOPSIS
    Pester 5 tests for the Lab 1.2 cleanup: when it reports an object absent, and when it exits 1.

.DESCRIPTION
    Regression cover for issue #255. The cleanup looked the Owner role assignment and the resource
    groups up with -ErrorAction SilentlyContinue, so a lookup that failed (a 403, throttling)
    read as "not found", and it exited 0 even when a removal failed. These tests run the real
    Remove-LabResource.ps1 in a child pwsh process against a generated stub of the Az commands it
    calls, and assert the observable contract:

      1. Everything the lab creates is removed when it is present, and the run exits 0.
      2. An object that is absent - an empty listing - is not a failure: the run exits 0.
      3. A lookup that fails with an error is an [ERROR], counted, and the run exits 1 without
         touching or reporting absent the object it could not see. The stub reports the failure
         with Write-Error, as the Az getters do, so a script that passes -ErrorAction
         SilentlyContinue swallows it - the defect #255 describes.
      4. A removal that fails is an [ERROR], counted, and the later steps still run: exit 1.

    Which errors mean "not found" is pinned for every cleanup that carries the helpers by
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
    Lab: 1.2 - RBAC
#>

#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..' '..' '..' 'tests' 'Support' 'LabScriptStub.psm1') -Force

    $script:ScriptPath     = (Resolve-Path (Join-Path $PSScriptRoot '..' 'scripts' 'Remove-LabResource.ps1')).Path
    $script:StubModuleName = 'SkyCraftLab12CleanupStub'
    # Exactly the script's '#Requires -Modules' line: these are imported for real before the stub.
    $script:RequiredModules = @('Az.Accounts', 'Az.Resources')

    $script:StubCommands = @(
        'Get-AzContext'
        'Get-AzRoleAssignment'
        'Remove-AzRoleAssignment'
        'Get-AzResourceGroup'
        'Remove-AzResourceGroup'
    )

    # Every command the script calls, recording its own invocation. By default the subscription
    # holds everything the lab creates, plus an unrelated Owner assignment. Environment variables
    # change that, so one generated module serves every scenario:
    #   SKYCRAFT_STUB_EMPTY   '1' leaves nothing to find: the listings come back empty
    #   SKYCRAFT_STUB_LOOKUP  '<lookup>=<kind>,...' makes one lookup fail (denied, throttled)
    #   SKYCRAFT_STUB_FAIL    '<Remove-command>:<name>,...' makes one removal throw
    # A removal is logged both bare and with the object's name.
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
    param([string]$Name)
    Write-StubCall -Name $Name
    $kind = foreach ($entry in @($env:SKYCRAFT_STUB_LOOKUP -split ',')) {
        $key, $value = $entry -split '=', 2
        if ($key -eq $Name) { $value }
    }
    switch ($kind) {
        'denied' {
            Write-Error -ErrorId 'AuthorizationFailed' -Message "The client 'stub' does not have authorization to perform action 'read' over scope '$Name' or the scope is invalid."
            return $true
        }
        'throttled' {
            Write-Error -ErrorId 'TooManyRequests' -Message "Number of 'read' requests exceeded the limit for $Name. Please try again after '17' seconds."
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

function Get-AzRoleAssignment {
    [CmdletBinding()]
    param([string]$Scope, [switch]$IncludeClassicAdministrators)
    if (Invoke-StubLookup -Name 'Get-AzRoleAssignment') { return }
    # Someone else's Owner assignment is in every listing; only Malfurion's is the lab's.
    [pscustomobject]@{ SignInName = 'someone.else@contoso.example'; RoleDefinitionName = 'Owner'; ObjectId = '22222222-2222-2222-2222-222222222222' }
    if (Test-StubEmpty) { return }
    [pscustomobject]@{ SignInName = 'malfurion.stormrage@contoso.example'; RoleDefinitionName = 'Owner'; ObjectId = '11111111-1111-1111-1111-111111111111' }
}

function Remove-AzRoleAssignment {
    [CmdletBinding()]
    param([string]$ObjectId, [string]$RoleDefinitionName, [string]$Scope)
    Invoke-StubRemoval -Command 'Remove-AzRoleAssignment' -Name $ObjectId
}

function Get-AzResourceGroup {
    [CmdletBinding()]
    param([string]$Name)
    if (Invoke-StubLookup -Name 'Get-AzResourceGroup') { return }
    # A group the lab did not create is in every listing.
    [pscustomobject]@{ ResourceGroupName = 'NetworkWatcherRG' }
    if (Test-StubEmpty) { return }
    foreach ($rg in 'dev-skycraft-swc-rg', 'prod-skycraft-swc-rg', 'platform-skycraft-swc-rg') {
        [pscustomobject]@{ ResourceGroupName = $rg }
    }
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

    # One invocation per scenario, reused by the assertions below - each child process costs
    # several seconds.
    $script:Clean   = Invoke-CleanupScript -Stub $script:Stub
    $script:Nothing = Invoke-CleanupScript -Stub $script:Stub -Empty
    $script:WhatIf  = Invoke-CleanupScript -Stub $script:Stub -ArgumentList '-WhatIf'
    $script:LookupsFail = Invoke-CleanupScript -Stub $script:Stub -Lookup @(
        'Get-AzRoleAssignment=denied'
        'Get-AzResourceGroup=throttled'
    )
    $script:AssignmentDenied = Invoke-CleanupScript -Stub $script:Stub -Lookup 'Get-AzRoleAssignment=denied'
    $script:RemovalsFail = Invoke-CleanupScript -Stub $script:Stub -Fail @(
        'Remove-AzRoleAssignment:11111111-1111-1111-1111-111111111111'
        'Remove-AzResourceGroup:dev-skycraft-swc-rg'
    )

    $script:AllRuns = @(
        $script:Clean, $script:Nothing, $script:WhatIf, $script:LookupsFail, $script:AssignmentDenied,
        $script:RemovalsFail
    )
}

AfterAll {
    if ($script:StubDir) { Remove-Item -LiteralPath $script:StubDir -Recurse -Force -ErrorAction SilentlyContinue }
}

Describe 'Lab 1.2 Remove-LabResource.ps1 - test harness' {

    It 'shadows the real Az commands instead of touching a subscription' {
        # Refused is the child exiting 99 before the script ran. Asserted on every scenario: a
        # refusal in one of them is a half-stubbed session, not a scenario-specific failure.
        foreach ($run in $script:AllRuns) {
            $run.Refused | Should -BeFalse -Because "the harness must never fall through to the real Az commands (exit $($run.ExitCode)): $($run.Output)"
        }
    }
}

Describe 'Lab 1.2 Remove-LabResource.ps1 - removes what the lab creates' {

    It 'exits 0 when every object is found and removed' {
        $script:Clean.ExitCode | Should -Be 0 -Because "a clean teardown must report success; output was:`n$($script:Clean.Output)"
        $script:Clean.Output   | Should -Match 'Cleanup complete'
        $script:Clean.Output   | Should -Not -Match '\[ERROR\]'
    }

    It 'removes Malfurion''s Owner assignment and nobody else''s' {
        $script:Clean.Calls | Should -Contain 'Remove-AzRoleAssignment:11111111-1111-1111-1111-111111111111'
        $script:Clean.Calls | Should -Not -Contain 'Remove-AzRoleAssignment:22222222-2222-2222-2222-222222222222'
    }

    It 'deletes the three lab resource groups and no other' {
        foreach ($rg in 'dev-skycraft-swc-rg', 'prod-skycraft-swc-rg', 'platform-skycraft-swc-rg') {
            $script:Clean.Calls | Should -Contain "Remove-AzResourceGroup:$rg"
        }
        $script:Clean.Calls | Should -Not -Contain 'Remove-AzResourceGroup:NetworkWatcherRG'
    }
}

Describe 'Lab 1.2 Remove-LabResource.ps1 - an absent object is not a failure' {

    It 'exits 0 and removes nothing when nothing is there' {
        $run = $script:Nothing
        $run.ExitCode | Should -Be 0 -Because "nothing to remove is a clean teardown; output was:`n$($run.Output)"
        $run.Output | Should -Not -Match '\[ERROR\]'
        $run.Output | Should -Match 'Cleanup complete'
        @($run.Calls | Where-Object { $_ -match '^Remove-' }) | Should -BeNullOrEmpty
    }

    It 'reports each absent object as not found' {
        $run = $script:Nothing
        $run.Output | Should -Match 'Assignment not found'
        $run.Output | Should -Match 'dev-skycraft-swc-rg not found'
        $run.Output | Should -Match 'platform-skycraft-swc-rg not found'
    }
}

Describe 'Lab 1.2 Remove-LabResource.ps1 - a failed lookup is not "absent" (#255)' {

    It 'exits 1, counts each failed lookup and carries the Azure error' {
        $run = $script:LookupsFail
        $run.ExitCode | Should -Be 1 -Because "an object that may still exist must not look like a clean cleanup; output was:`n$($run.Output)"
        $run.Output | Should -Match '\[ERROR\] Could not look up the role assignments on /subscriptions/[^\r\n]*does not have authorization'
        $run.Output | Should -Match '\[ERROR\] Could not look up the resource groups in the subscription[^\r\n]*requests exceeded the limit'
        $run.Output | Should -Match 'Cleanup finished with 2 failure\(s\)'
        $run.Output | Should -Not -Match 'Cleanup complete'
    }

    It 'does not report what it could not see as not found, and removes none of it' {
        $run = $script:LookupsFail
        $run.Output | Should -Not -Match 'Assignment not found'
        $run.Output | Should -Not -Match 'skycraft-swc-rg not found'
        @($run.Calls | Where-Object { $_ -match '^Remove-' }) | Should -BeNullOrEmpty
    }

    It 'still deletes the resource groups when only the role assignments could not be looked up' {
        $run = $script:AssignmentDenied
        $run.ExitCode | Should -Be 1 -Because "output was:`n$($run.Output)"
        $run.Output | Should -Match 'Cleanup finished with 1 failure\(s\)'
        $run.Calls  | Should -Contain 'Remove-AzResourceGroup:dev-skycraft-swc-rg'
        $run.Calls  | Should -Contain 'Remove-AzResourceGroup:platform-skycraft-swc-rg'
    }
}

Describe 'Lab 1.2 Remove-LabResource.ps1 - a failed removal is counted' {

    It 'exits 1 and counts each removal that failed' {
        $run = $script:RemovalsFail
        $run.ExitCode | Should -Be 1 -Because "a stuck object must not look like a clean cleanup; output was:`n$($run.Output)"
        $run.Output | Should -Match '\[ERROR\] Failed to remove role: stub failure'
        $run.Output | Should -Match '\[ERROR\] Failed to delete dev-skycraft-swc-rg: stub failure'
        $run.Output | Should -Match 'Cleanup finished with 2 failure\(s\)'
        $run.Output | Should -Not -Match 'Cleanup complete'
    }

    It 'keeps going after a failed removal' {
        $script:RemovalsFail.Calls | Should -Contain 'Remove-AzResourceGroup:prod-skycraft-swc-rg'
        $script:RemovalsFail.Calls | Should -Contain 'Remove-AzResourceGroup:platform-skycraft-swc-rg'
    }
}

Describe 'Lab 1.2 Remove-LabResource.ps1 - -WhatIf' {

    It 'looks everything up and removes nothing' {
        $run = $script:WhatIf
        $run.ExitCode | Should -Be 0 -Because "output was:`n$($run.Output)"
        @($run.Calls | Where-Object { $_ -match '^Remove-' }) | Should -BeNullOrEmpty
        $run.Calls  | Should -Contain 'Get-AzRoleAssignment'
        $run.Calls  | Should -Contain 'Get-AzResourceGroup'
        $run.Output | Should -Match 'What if: .*prod-skycraft-swc-rg'
    }
}
