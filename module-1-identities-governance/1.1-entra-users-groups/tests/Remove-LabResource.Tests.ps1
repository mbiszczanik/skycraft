<#
.SYNOPSIS
    Pester 5 tests for the Lab 1.1 cleanup script's failure reporting and exit code.

.DESCRIPTION
    Regression cover for issue #194, the Lab 1.1 twin of Lab 5.2's #105. The script caught every
    failed user, guest and group deletion, printed [ERROR] and carried on - then exited 0, so a
    caller that reads the exit code (tools/Invoke-GuideDrift.ps1) saw a clean teardown while
    objects were left behind. These tests run the real Remove-LabResource.ps1 in a child pwsh
    process against a generated stub of the Microsoft Graph commands it calls, and assert the
    observable contract:

      1. A clean run, a run with nothing to delete and a -WhatIf run exit 0.
      2. A run in which any deletion fails exits 1 - asserted on the exit code, not on the printed
         message - and every failure is counted.
      3. A failure does not stop the run: the later deletions are still attempted.
      4. A failed Microsoft Graph sign-in still exits 1 before anything is looked up.
      5. A lookup that fails with an error is an [ERROR], counted like a failed deletion, so the
         run exits 1 (issue #227). Only a lookup that succeeds and returns nothing is "not found".
         The stub reports a failed lookup with Write-Error, as the Graph cmdlets do, so a script
         that passes -ErrorAction SilentlyContinue swallows it - the defect #227 describes.

    Scope limit, as in Lab 5.2's suite: the child is launched with -Command, so these tests prove
    the failure counter reaches `exit`, not that `pwsh -File` carries the code out of the process.
    That half is issue #104's guard ($Host.SetShouldExit before every non-zero exit), enforced
    repo-wide by tests/Exit-Code-Propagation.Tests.ps1.

    No tenant is needed, and none is used. The script runs through tests/Support/LabScriptStub.psm1
    (issue #112), which imports the real modules first, the stub module last, and aborts the child
    with exit 99 unless every stubbed command resolves to the stub. The Microsoft.Graph commands
    are functions, like Az.DataProtection's, so that ordering is what keeps them shadowed. Every
    SKYCRAFT_GRAPH_* variable and SKYCRAFT_UNATTENDED are cleared for the child, so the script
    plans the interactive sign-in and reuses the stub's Graph context instead of signing in.

.EXAMPLE
    Invoke-Pester -Path .\Remove-LabResource.Tests.ps1

.NOTES
    Project: SkyCraft
    Lab: 1.1 - Entra Users & Groups
#>

#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..' '..' '..' 'tests' 'Support' 'LabScriptStub.psm1') -Force

    $script:ScriptPath     = (Resolve-Path (Join-Path $PSScriptRoot '..' 'scripts' 'Remove-LabResource.ps1')).Path
    $script:StubModuleName = 'SkyCraftGraphStub'
    # Exactly the script's '#Requires -Modules' line: these are imported for real before the stub.
    $script:RequiredModules = @(
        'Microsoft.Graph.Authentication'
        'Microsoft.Graph.Users'
        'Microsoft.Graph.Groups'
        'Microsoft.Graph.Identity.DirectoryManagement'
    )

    $script:StubCommands = @(
        'Get-MgContext'
        'Connect-MgGraph'
        'Disconnect-MgGraph'
        'Get-MgDomain'
        'Get-MgUser'
        'Remove-MgUser'
        'Get-MgGroup'
        'Remove-MgGroup'
    )

    # Every Graph command the script calls, recording its own invocation and optionally throwing.
    # Behaviour is driven by environment variables so one generated module serves every scenario.
    # A user found by UserPrincipalName is a 'member', one found by Mail is the 'guest': the gate
    # names a kind, not an address, so the scenarios do not depend on which addresses the lab uses.
    $script:StubBody = @'
$script:LogPath = $env:SKYCRAFT_STUB_LOG

function Write-StubCall {
    param([string]$Name)
    if ($script:LogPath) { Add-Content -LiteralPath $script:LogPath -Value $Name }
}

function Invoke-StubGate {
    param([string]$Name)
    Write-StubCall -Name $Name
    if (@($env:SKYCRAFT_STUB_FAIL -split ',') -contains $Name) { throw "stub failure: $Name" }
}

# Whether the lookup named here should fail. The lookup itself reports the failure with
# Write-Error, as the Graph cmdlets do, so the caller's -ErrorAction decides what happens to it.
function Test-StubLookupFails {
    param([string]$Name)
    Write-StubCall -Name $Name
    return (@($env:SKYCRAFT_STUB_FAIL -split ',') -contains $Name)
}

function Test-StubEmpty { return $env:SKYCRAFT_STUB_EMPTY -eq '1' }

function Get-MgContext {
    [CmdletBinding()]
    param()
    if ($env:SKYCRAFT_STUB_NOCONTEXT -eq '1') { return }
    [pscustomobject]@{
        TenantId = '00000000-0000-0000-0000-000000000000'
        Account  = 'stub-admin@contoso.example'
        AppName  = $null
    }
}

function Connect-MgGraph {
    [CmdletBinding()]
    param([Parameter(ValueFromRemainingArguments)]$Rest)
    Invoke-StubGate -Name 'Connect-MgGraph'
}

function Disconnect-MgGraph {
    [CmdletBinding()]
    param()
}

function Get-MgDomain {
    [CmdletBinding()]
    param([Parameter(ValueFromRemainingArguments)]$Rest)
    [pscustomobject]@{ Id = 'contoso.example'; IsDefault = $true; IsInitial = $true }
}

function Get-MgUser {
    [CmdletBinding()]
    param([string]$Filter, [Parameter(ValueFromRemainingArguments)]$Rest)
    Write-StubCall -Name 'Get-MgUser'
    $kind = if ($Filter -match '^\s*Mail\b') { 'guest' } else { 'member' }
    if (Test-StubLookupFails -Name "Get-MgUser:$kind") { Write-Error "stub lookup failure: Get-MgUser:$kind"; return }
    if (Test-StubEmpty) { return }
    [pscustomobject]@{ Id = $kind }
}

function Remove-MgUser {
    [CmdletBinding()]
    param([string]$UserId)
    Write-StubCall -Name 'Remove-MgUser'
    Invoke-StubGate -Name "Remove-MgUser:$UserId"
}

function Get-MgGroup {
    [CmdletBinding()]
    param([string]$Filter, [Parameter(ValueFromRemainingArguments)]$Rest)
    if (Test-StubLookupFails -Name 'Get-MgGroup') { Write-Error 'stub lookup failure: Get-MgGroup'; return }
    if (Test-StubEmpty) { return }
    [pscustomobject]@{ Id = 'group' }
}

function Remove-MgGroup {
    [CmdletBinding()]
    param([string]$GroupId)
    Invoke-StubGate -Name 'Remove-MgGroup'
}
'@

    # Runs the real script in a child process with the stubs shadowing the Graph commands, and
    # returns the exit code it hands back together with the stub's call log.
    function Invoke-CleanupScript {
        param(
            [pscustomobject]$Stub,
            [string[]]$Fail = @(),
            [switch]$Empty,
            [switch]$NoContext,
            [string[]]$ArgumentList = @('-Force')
        )

        $logPath = Join-Path $Stub.Directory 'calls.log'
        Remove-Item -LiteralPath $logPath -Force -ErrorAction SilentlyContinue

        $run = Invoke-LabScriptWithStub -Stub $Stub -ScriptPath $script:ScriptPath -ArgumentList $ArgumentList -Environment @{
            SKYCRAFT_STUB_FAIL             = $Fail -join ','
            SKYCRAFT_STUB_EMPTY            = if ($Empty) { '1' } else { '0' }
            SKYCRAFT_STUB_NOCONTEXT        = if ($NoContext) { '1' } else { '0' }
            SKYCRAFT_STUB_LOG              = $logPath
            # Interactive plan, so the script reuses the stub's context instead of signing in.
            SKYCRAFT_GRAPH_TENANT_ID       = ''
            SKYCRAFT_GRAPH_CLIENT_ID       = ''
            SKYCRAFT_GRAPH_CLIENT_SECRET   = ''
            SKYCRAFT_GRAPH_CERT_THUMBPRINT = ''
            SKYCRAFT_UNATTENDED            = ''
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
    $script:Clean        = Invoke-CleanupScript -Stub $script:Stub
    $script:Nothing      = Invoke-CleanupScript -Stub $script:Stub -Empty
    $script:Preview      = Invoke-CleanupScript -Stub $script:Stub -ArgumentList '-WhatIf'
    $script:GroupsStuck  = Invoke-CleanupScript -Stub $script:Stub -Fail 'Remove-MgGroup'
    $script:GuestStuck   = Invoke-CleanupScript -Stub $script:Stub -Fail 'Remove-MgUser:guest'
    $script:MembersStuck = Invoke-CleanupScript -Stub $script:Stub -Fail 'Remove-MgUser:member'
    $script:SignInFails  = Invoke-CleanupScript -Stub $script:Stub -NoContext -Fail 'Connect-MgGraph'
    $script:MembersUnreadable = Invoke-CleanupScript -Stub $script:Stub -Fail 'Get-MgUser:member'
    $script:GuestUnreadable   = Invoke-CleanupScript -Stub $script:Stub -Fail 'Get-MgUser:guest'
    $script:GroupsUnreadable  = Invoke-CleanupScript -Stub $script:Stub -Fail 'Get-MgGroup'

    $script:AllRuns = @(
        $script:Clean, $script:Nothing, $script:Preview, $script:GroupsStuck, $script:GuestStuck,
        $script:MembersStuck, $script:SignInFails, $script:MembersUnreadable, $script:GuestUnreadable,
        $script:GroupsUnreadable
    )
}

AfterAll {
    if ($script:StubDir) { Remove-Item -LiteralPath $script:StubDir -Recurse -Force -ErrorAction SilentlyContinue }
}

Describe 'Lab 1.1 Remove-LabResource.ps1 - test harness' {

    It 'shadows the real Microsoft Graph commands instead of touching a tenant' {
        # Refused is the child exiting 99 before the script ran. Asserted on every scenario: a
        # refusal in one of them is a half-stubbed session, not a scenario-specific failure.
        foreach ($run in $script:AllRuns) {
            $run.Refused | Should -BeFalse -Because "the harness must never fall through to the real Graph commands (exit $($run.ExitCode)): $($run.Output)"
        }
    }
}

Describe 'Lab 1.1 Remove-LabResource.ps1 - exit code contract (#194)' {

    It 'exits 0 when every deletion succeeds' {
        $script:Clean.ExitCode | Should -Be 0 -Because "a clean teardown must report success; output was:`n$($script:Clean.Output)"
        @($script:Clean.Calls | Where-Object { $_ -eq 'Remove-MgUser' }).Count | Should -Be 4
        @($script:Clean.Calls | Where-Object { $_ -eq 'Remove-MgGroup' }).Count | Should -Be 3
        $script:Clean.Output | Should -Match 'Cleanup Complete'
    }

    It 'exits 0 when there is nothing to delete' {
        $script:Nothing.ExitCode | Should -Be 0 -Because "an absent object is not a failure; output was:`n$($script:Nothing.Output)"
        $script:Nothing.Calls | Should -Not -Contain 'Remove-MgUser'
        $script:Nothing.Calls | Should -Not -Contain 'Remove-MgGroup'
    }

    It 'exits 0 and deletes nothing under -WhatIf' {
        $script:Preview.ExitCode | Should -Be 0 -Because "a skipped deletion is not a failed one; output was:`n$($script:Preview.Output)"
        $script:Preview.Calls | Should -Not -Contain 'Remove-MgUser'
        $script:Preview.Calls | Should -Not -Contain 'Remove-MgGroup'
    }

    It 'exits 1 when the groups exist but cannot be deleted (the reproduction in #194)' {
        $script:GroupsStuck.ExitCode | Should -Be 1 -Because "objects left behind must not look like a clean cleanup; output was:`n$($script:GroupsStuck.Output)"
        $script:GroupsStuck.Output | Should -Match 'Cleanup finished with 3 failure\(s\)'
        ([regex]::Matches($script:GroupsStuck.Output, '\[ERROR\] Failed to delete group')).Count | Should -Be 3
        $script:GroupsStuck.Output | Should -Not -Match 'Cleanup Complete'
    }

    It 'exits 1 when the guest cannot be deleted, and still deletes the groups' {
        $script:GuestStuck.ExitCode | Should -Be 1 -Because "output was:`n$($script:GuestStuck.Output)"
        $script:GuestStuck.Output | Should -Match '\[ERROR\] Failed to delete guest'
        $script:GuestStuck.Output | Should -Match 'Cleanup finished with 1 failure\(s\)'
        @($script:GuestStuck.Calls | Where-Object { $_ -eq 'Remove-MgGroup' }).Count | Should -Be 3
    }

    It 'counts every failed user and keeps going to the guest and the groups' {
        $script:MembersStuck.ExitCode | Should -Be 1 -Because "output was:`n$($script:MembersStuck.Output)"
        $script:MembersStuck.Output | Should -Match 'Cleanup finished with 3 failure\(s\)'
        $script:MembersStuck.Calls | Should -Contain 'Remove-MgUser:guest'
        @($script:MembersStuck.Calls | Where-Object { $_ -eq 'Remove-MgGroup' }).Count | Should -Be 3
    }

    It 'reports a failed deletion as [ERROR], never [WARNING]' {
        foreach ($run in @($script:GroupsStuck, $script:GuestStuck, $script:MembersStuck)) {
            $run.Output | Should -Not -Match '\[WARNING\] Failed to delete'
        }
    }

    It 'still exits 1 when the Microsoft Graph sign-in fails, before looking anything up' {
        $script:SignInFails.ExitCode | Should -Be 1 -Because "output was:`n$($script:SignInFails.Output)"
        $script:SignInFails.Output | Should -Match '\[ERROR\] Failed to connect to Microsoft Graph'
        $script:SignInFails.Calls | Should -Not -Contain 'Get-MgUser'
    }
}

Describe 'Lab 1.1 Remove-LabResource.ps1 - a failed lookup is not "not found" (#227)' {

    It 'reports a lookup that found nothing as not found, and exits 0' {
        $script:Nothing.Output | Should -Match '\[INFO\] User not found'
        $script:Nothing.Output | Should -Match '\[INFO\] Guest not found'
        $script:Nothing.Output | Should -Match '\[INFO\] Group not found'
        $script:Nothing.Output | Should -Not -Match '\[ERROR\]'
    }

    It 'exits 1 when the users cannot be looked up, and still goes on to the guest and the groups' {
        $run = $script:MembersUnreadable
        $run.ExitCode | Should -Be 1 -Because "a user that may still exist must not look like a clean cleanup; output was:`n$($run.Output)"
        ([regex]::Matches($run.Output, '\[ERROR\] Could not look up user')).Count | Should -Be 3
        $run.Output | Should -Not -Match '\[INFO\] User not found'
        $run.Output | Should -Match 'Cleanup finished with 3 failure\(s\)'
        $run.Calls | Should -Contain 'Remove-MgUser:guest'
        @($run.Calls | Where-Object { $_ -eq 'Remove-MgGroup' }).Count | Should -Be 3
    }

    It 'exits 1 when the guest cannot be looked up, and still deletes the groups' {
        $run = $script:GuestUnreadable
        $run.ExitCode | Should -Be 1 -Because "output was:`n$($run.Output)"
        $run.Output | Should -Match '\[ERROR\] Could not look up guest'
        $run.Output | Should -Not -Match '\[INFO\] Guest not found'
        $run.Output | Should -Match 'Cleanup finished with 1 failure\(s\)'
        $run.Calls | Should -Not -Contain 'Remove-MgUser:guest'
        @($run.Calls | Where-Object { $_ -eq 'Remove-MgGroup' }).Count | Should -Be 3
    }

    It 'exits 1 when the groups cannot be looked up' {
        $run = $script:GroupsUnreadable
        $run.ExitCode | Should -Be 1 -Because "output was:`n$($run.Output)"
        ([regex]::Matches($run.Output, '\[ERROR\] Could not look up group')).Count | Should -Be 3
        $run.Output | Should -Not -Match '\[INFO\] Group not found'
        $run.Output | Should -Match 'Cleanup finished with 3 failure\(s\)'
        $run.Calls | Should -Not -Contain 'Remove-MgGroup'
    }

    It 'carries the Microsoft Graph error into the [ERROR] line' {
        $script:GuestUnreadable.Output | Should -Match '\[ERROR\] Could not look up guest [^\r\n]*stub lookup failure: Get-MgUser:guest'
    }
}
