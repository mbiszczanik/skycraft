<#
.SYNOPSIS
    Pester 5 tests for the Lab 1.1 validator's failure count and exit code.

.DESCRIPTION
    Regression cover for issue #241. Test-Lab.ps1 printed [FAIL] for every check that failed and
    then ended "Lab 1.1 validation complete" with exit code 0, so neither a caller reading the exit
    code nor a learner reading the last line could tell a failed validation from a passed one.
    These tests run the real Test-Lab.ps1 in a child pwsh process against a generated stub of the
    Microsoft Graph commands it calls, and assert the observable contract:

      1. A run in which every check passes exits 0, and its summary says 0 failed.
      2. A run in which one check fails - a missing user, a group holding the wrong member, an
         empty group, a member list or a member that cannot be read - exits 1, and its summary
         states the count: exactly 1. A read that fails is reported with the Graph error, never
         as "No members found" or "NOT found in group".
      3. A missing group fails its membership check too, so every run counts the same ten checks.
      4. A run in which every lookup fails with an error (the live reproduction in #241: a Graph
         sign-in that had not completed, "Authentication needed" on every call) counts all ten
         checks as failed and exits 1.
      5. A failed Microsoft Graph sign-in exits 1 before anything is looked up.
      6. A sign-in that "succeeds" without leaving a Graph context (issue #242) still exits 1 with
         an [ERROR] line and runs no check. Asserted on the [ERROR] and the exit code only, not
         on which step reports it, so the test holds both before and after #242 moves the
         failure into Connect-LabGraph.

    Scope limit, as in the cleanup suite next to this one: the child is launched with -Command,
    so these tests prove the failure counter reaches `exit`, not that `pwsh -File` carries the
    code out of the process. That half is issue #104's guard ($Host.SetShouldExit before every
    non-zero exit), enforced repo-wide by tests/Exit-Code-Propagation.Tests.ps1.

    No tenant is needed, and none is used. The script runs through tests/Support/LabScriptStub.psm1
    (issue #112), which imports the real modules first, the stub module last, and aborts the child
    with exit 99 unless every stubbed command resolves to the stub. Every SKYCRAFT_GRAPH_* variable
    and SKYCRAFT_UNATTENDED are cleared for the child, so the script plans the interactive sign-in
    and reuses the stub's Graph context instead of signing in.

.EXAMPLE
    Invoke-Pester -Path .\Test-Lab.Tests.ps1

.NOTES
    Project: SkyCraft
    Lab: 1.1 - Entra Users & Groups
#>

#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..' '..' '..' 'tests' 'Support' 'LabScriptStub.psm1') -Force

    $script:ScriptPath     = (Resolve-Path (Join-Path $PSScriptRoot '..' 'scripts' 'Test-Lab.ps1')).Path
    $script:StubModuleName = 'SkyCraftGraphValidatorStub'
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
        'Get-MgGroup'
        'Get-MgGroupMember'
    )

    # Every Graph command the script calls, recording its own invocation. By default the tenant
    # holds exactly what the lab builds: each user, the guest, and each group with its one expected
    # member. Environment variables take pieces away, so one generated module serves every
    # scenario:
    #   SKYCRAFT_STUB_MISSING      users (by the part of the address before '@', or 'guest') and
    #                              groups (by name) the lookup returns nothing for
    #   SKYCRAFT_STUB_WRONGMEMBER  groups that hold someone other than their expected member
    #   SKYCRAFT_STUB_NOMEMBERS    groups that hold no member at all
    #   SKYCRAFT_STUB_LOOKUPFAIL   '1' makes every user and group lookup fail with an error
    #   SKYCRAFT_STUB_MEMBERFAIL   groups whose member list fails to read with an error
    #   SKYCRAFT_STUB_USERIDFAIL   members (by id) whose lookup by id fails with an error
    #   SKYCRAFT_STUB_EXTRAMEMBER  groups that also hold a nested group and a service principal,
    #                              listed before the expected user; their lookup by user id
    #                              fails with a 404, as /users/{id} does for a non-user
    #   SKYCRAFT_STUB_NOCONTEXT    '1' leaves no Graph context: every Graph read then fails with
    #                              "Authentication needed", as the real cmdlets do
    #   SKYCRAFT_STUB_FAIL         'Connect-MgGraph' makes the sign-in throw
    $script:StubBody = @'
$script:LogPath = $env:SKYCRAFT_STUB_LOG

# The member each group is expected to hold, and the display name each member resolves to.
$script:GroupMember = @{
    'SkyCraft-Admins'     = 'malfurion.stormrage'
    'SkyCraft-Developers' = 'khadgar.archmage'
    'SkyCraft-Testers'    = 'chromie.timewalker'
}
$script:DisplayName = @{
    'malfurion.stormrage' = 'Malfurion Stormrage'
    'khadgar.archmage'    = 'Khadgar Archmage'
    'chromie.timewalker'  = 'Chromie Timewalker'
    'someone.else'        = 'Someone Else'
}

function Write-StubCall {
    param([string]$Name)
    if ($script:LogPath) { Add-Content -LiteralPath $script:LogPath -Value $Name }
}

function Test-StubListed {
    param([string]$Variable, [string]$Name)
    if (-not $Name) { return $false }
    return (@([System.Environment]::GetEnvironmentVariable($Variable) -split ',') -contains $Name)
}

function Test-StubSignedIn { return $env:SKYCRAFT_STUB_NOCONTEXT -ne '1' }

function Get-MgContext {
    [CmdletBinding()]
    param()
    if (-not (Test-StubSignedIn)) { return }
    [pscustomobject]@{
        TenantId = '00000000-0000-0000-0000-000000000000'
        Account  = 'stub-admin@contoso.example'
        AppName  = $null
    }
}

# Without SKYCRAFT_STUB_FAIL it returns without an error and, under SKYCRAFT_STUB_NOCONTEXT,
# without a context too - the shape issue #242 describes.
function Connect-MgGraph {
    [CmdletBinding()]
    param([Parameter(ValueFromRemainingArguments)]$Rest)
    Write-StubCall -Name 'Connect-MgGraph'
    if (Test-StubListed -Variable 'SKYCRAFT_STUB_FAIL' -Name 'Connect-MgGraph') { throw 'stub failure: Connect-MgGraph' }
}

function Disconnect-MgGraph {
    [CmdletBinding()]
    param()
}

function Get-MgDomain {
    [CmdletBinding()]
    param([Parameter(ValueFromRemainingArguments)]$Rest)
    Write-StubCall -Name 'Get-MgDomain'
    if (-not (Test-StubSignedIn)) { Write-Error 'Authentication needed. Please call Connect-MgGraph.'; return }
    [pscustomobject]@{ Id = 'contoso.example'; IsDefault = $true; IsInitial = $true }
}

function Get-MgUser {
    [CmdletBinding()]
    param([string]$Filter, [string]$UserId, [Parameter(ValueFromRemainingArguments)]$Rest)
    Write-StubCall -Name 'Get-MgUser'
    if (-not (Test-StubSignedIn)) { Write-Error 'Authentication needed. Please call Connect-MgGraph.'; return }

    # A member lookup by id, as the membership check makes.
    if ($UserId) {
        if (Test-StubListed -Variable 'SKYCRAFT_STUB_USERIDFAIL' -Name $UserId) { Write-Error "stub lookup failure: Get-MgUser -UserId $UserId"; return }
        if (-not $script:DisplayName.ContainsKey($UserId)) { Write-Error "[Request_ResourceNotFound] Resource '$UserId' does not exist (stub 404)"; return }
        return [pscustomobject]@{
            Id                = $UserId
            DisplayName       = $script:DisplayName[$UserId]
            UserPrincipalName = "$UserId@contoso.example"
        }
    }

    if ($env:SKYCRAFT_STUB_LOOKUPFAIL -eq '1') { Write-Error 'stub lookup failure: Get-MgUser'; return }

    $key = if ($Filter -match '^\s*Mail\b') { 'guest' } else { [regex]::Match($Filter, "'([^'@]+)@").Groups[1].Value }
    if (Test-StubListed -Variable 'SKYCRAFT_STUB_MISSING' -Name $key) { return }

    $displayName = if ($script:DisplayName.ContainsKey($key)) { $script:DisplayName[$key] } else { $key }
    [pscustomobject]@{ Id = $key; DisplayName = $displayName }
}

function Get-MgGroup {
    [CmdletBinding()]
    param([string]$Filter, [Parameter(ValueFromRemainingArguments)]$Rest)
    Write-StubCall -Name 'Get-MgGroup'
    if (-not (Test-StubSignedIn)) { Write-Error 'Authentication needed. Please call Connect-MgGraph.'; return }
    if ($env:SKYCRAFT_STUB_LOOKUPFAIL -eq '1') { Write-Error 'stub lookup failure: Get-MgGroup'; return }

    $name = [regex]::Match($Filter, "'([^']+)'").Groups[1].Value
    if (Test-StubListed -Variable 'SKYCRAFT_STUB_MISSING' -Name $name) { return }
    [pscustomobject]@{ Id = $name; DisplayName = $name }
}

# A directoryObject as Get-MgGroupMember returns it: the derived type is only in AdditionalProperties.
function New-StubMember {
    param([string]$Id, [string]$Type = '#microsoft.graph.user')
    [pscustomobject]@{ Id = $Id; AdditionalProperties = @{ '@odata.type' = $Type } }
}

function Get-MgGroupMember {
    [CmdletBinding()]
    param([string]$GroupId, [switch]$All, [Parameter(ValueFromRemainingArguments)]$Rest)
    Write-StubCall -Name 'Get-MgGroupMember'
    if (Test-StubListed -Variable 'SKYCRAFT_STUB_MEMBERFAIL' -Name $GroupId) { Write-Error "stub lookup failure: Get-MgGroupMember $GroupId"; return }
    if (Test-StubListed -Variable 'SKYCRAFT_STUB_NOMEMBERS' -Name $GroupId) { return }
    if (Test-StubListed -Variable 'SKYCRAFT_STUB_WRONGMEMBER' -Name $GroupId) { return New-StubMember -Id 'someone.else' }
    if (Test-StubListed -Variable 'SKYCRAFT_STUB_EXTRAMEMBER' -Name $GroupId) {
        New-StubMember -Id 'nested-group' -Type '#microsoft.graph.group'
        New-StubMember -Id 'service-principal' -Type '#microsoft.graph.servicePrincipal'
    }
    New-StubMember -Id $script:GroupMember[$GroupId]
}
'@

    # Runs the real script in a child process with the stubs shadowing the Graph commands, and
    # returns the exit code it hands back together with the stub's call log.
    function Invoke-ValidatorScript {
        param(
            [pscustomobject]$Stub,
            [string[]]$Missing = @(),
            [string[]]$WrongMember = @(),
            [string[]]$NoMembers = @(),
            [string[]]$MemberFail = @(),
            [string[]]$UserIdFail = @(),
            [string[]]$ExtraMember = @(),
            [string[]]$Fail = @(),
            [switch]$LookupFail,
            [switch]$NoContext
        )

        $logPath = Join-Path $Stub.Directory 'calls.log'
        Remove-Item -LiteralPath $logPath -Force -ErrorAction SilentlyContinue

        $run = Invoke-LabScriptWithStub -Stub $Stub -ScriptPath $script:ScriptPath -Environment @{
            SKYCRAFT_STUB_MISSING          = $Missing -join ','
            SKYCRAFT_STUB_WRONGMEMBER      = $WrongMember -join ','
            SKYCRAFT_STUB_NOMEMBERS        = $NoMembers -join ','
            SKYCRAFT_STUB_MEMBERFAIL       = $MemberFail -join ','
            SKYCRAFT_STUB_USERIDFAIL       = $UserIdFail -join ','
            SKYCRAFT_STUB_EXTRAMEMBER      = $ExtraMember -join ','
            SKYCRAFT_STUB_FAIL             = $Fail -join ','
            SKYCRAFT_STUB_LOOKUPFAIL       = if ($LookupFail) { '1' } else { '0' }
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
            ExitCode  = $run.ExitCode
            Refused   = $run.Refused
            Output    = $run.Output
            Calls     = $calls
            # Check lines only: the summary's own "see the [FAIL] lines" pointer is not a check.
            FailLines = ([regex]::Matches($run.Output, '(?m)^\s*(->\s*)?\[FAIL\]')).Count
        }
    }

    $script:Stub    = Initialize-LabScriptStub -Name $script:StubModuleName -Command $script:StubCommands `
        -Body $script:StubBody -RequiredModule $script:RequiredModules
    $script:StubDir = $script:Stub.Directory

    # One invocation per scenario, reused by the assertions below - each child process costs
    # several seconds.
    $script:AllPass      = Invoke-ValidatorScript -Stub $script:Stub
    $script:UserMissing  = Invoke-ValidatorScript -Stub $script:Stub -Missing 'khadgar.archmage'
    $script:GuestMissing = Invoke-ValidatorScript -Stub $script:Stub -Missing 'guest'
    $script:WrongMember  = Invoke-ValidatorScript -Stub $script:Stub -WrongMember 'SkyCraft-Testers'
    $script:EmptyGroup   = Invoke-ValidatorScript -Stub $script:Stub -NoMembers 'SkyCraft-Admins'
    $script:GroupMissing = Invoke-ValidatorScript -Stub $script:Stub -Missing 'SkyCraft-Developers'
    $script:MembersUnreadable = Invoke-ValidatorScript -Stub $script:Stub -MemberFail 'SkyCraft-Admins'
    $script:MemberUnreadable  = Invoke-ValidatorScript -Stub $script:Stub -UserIdFail 'chromie.timewalker'
    $script:MixedMembers = Invoke-ValidatorScript -Stub $script:Stub -ExtraMember 'SkyCraft-Developers'
    $script:LookupsFail  = Invoke-ValidatorScript -Stub $script:Stub -LookupFail
    $script:SignInFails  = Invoke-ValidatorScript -Stub $script:Stub -NoContext -Fail 'Connect-MgGraph'
    $script:NoContext    = Invoke-ValidatorScript -Stub $script:Stub -NoContext

    $script:AllRuns = @(
        $script:AllPass, $script:UserMissing, $script:GuestMissing, $script:WrongMember,
        $script:EmptyGroup, $script:GroupMissing, $script:MembersUnreadable, $script:MemberUnreadable,
        $script:MixedMembers, $script:LookupsFail, $script:SignInFails, $script:NoContext
    )
}

AfterAll {
    if ($script:StubDir) { Remove-Item -LiteralPath $script:StubDir -Recurse -Force -ErrorAction SilentlyContinue }
}

Describe 'Lab 1.1 Test-Lab.ps1 - test harness' {

    It 'shadows the real Microsoft Graph commands instead of touching a tenant' {
        # Refused is the child exiting 99 before the script ran. Asserted on every scenario: a
        # refusal in one of them is a half-stubbed session, not a scenario-specific failure.
        foreach ($run in $script:AllRuns) {
            $run.Refused | Should -BeFalse -Because "the harness must never fall through to the real Graph commands (exit $($run.ExitCode)): $($run.Output)"
        }
    }
}

Describe 'Lab 1.1 Test-Lab.ps1 - failures are counted and set the exit code (#241)' {

    It 'exits 0 and reports 0 failed when every check passes' {
        $run = $script:AllPass
        $run.ExitCode | Should -Be 0 -Because "a passing validation must report success; output was:`n$($run.Output)"
        $run.FailLines | Should -Be 0
        # Four users (three members and the guest), three groups, three memberships.
        $run.Output | Should -Match 'Passed: 10\b'
        $run.Output | Should -Match 'Failed: 0\b'
        $run.Output | Should -Match 'validation passed'
        $run.Output | Should -Not -Match 'validation failed'
    }

    It 'exits 1 and reports 1 failed when one user is missing' {
        $run = $script:UserMissing
        $run.ExitCode | Should -Be 1 -Because "a missing user must not look like a passed validation; output was:`n$($run.Output)"
        $run.Output | Should -Match '\[FAIL\] User missing: khadgar\.archmage@'
        $run.FailLines | Should -Be 1
        $run.Output | Should -Match 'Passed: 9\b'
        $run.Output | Should -Match 'Failed: 1\b'
        $run.Output | Should -Match 'validation failed: 1 check\(s\) failed'
        $run.Output | Should -Not -Match 'validation passed'
    }

    It 'exits 1 and reports 1 failed when the guest is missing' {
        $run = $script:GuestMissing
        $run.ExitCode | Should -Be 1 -Because "output was:`n$($run.Output)"
        $run.FailLines | Should -Be 1
        $run.Output | Should -Match 'Failed: 1\b'
    }

    It 'exits 1 and reports 1 failed when a group holds someone other than its expected member' {
        $run = $script:WrongMember
        $run.ExitCode | Should -Be 1 -Because "output was:`n$($run.Output)"
        $run.Output | Should -Match '\[FAIL\] Verify: Chromie Timewalker NOT found in group'
        $run.FailLines | Should -Be 1
        $run.Output | Should -Match 'Failed: 1\b'
    }

    It 'exits 1 and reports 1 failed when a group has no members at all' {
        # It used to print [WARNING] and count nothing: the expected member is still missing.
        $run = $script:EmptyGroup
        $run.ExitCode | Should -Be 1 -Because "an empty group is missing its member; output was:`n$($run.Output)"
        $run.Output | Should -Match '\[FAIL\] No members found - expected Malfurion Stormrage'
        $run.FailLines | Should -Be 1
        $run.Output | Should -Match 'Failed: 1\b'
    }

    It 'fails both checks of a missing group, so the total stays at ten' {
        $run = $script:GroupMissing
        $run.ExitCode | Should -Be 1 -Because "output was:`n$($run.Output)"
        $run.Output | Should -Match '\[FAIL\] Group missing: SkyCraft-Developers'
        $run.Output | Should -Match '\[FAIL\] Membership of SkyCraft-Developers: group not found or not readable'
        $run.FailLines | Should -Be 2
        $run.Output | Should -Match 'Passed: 8\b'
        $run.Output | Should -Match 'Failed: 2\b'
    }

    It 'reports a member list that cannot be read with the Graph error, as 1 failed check' {
        $run = $script:MembersUnreadable
        $run.ExitCode | Should -Be 1 -Because "a refused read must not pass for an empty group; output was:`n$($run.Output)"
        $run.Output | Should -Match '\[FAIL\] Error checking members of SkyCraft-Admins: [^\r\n]*stub lookup failure: Get-MgGroupMember'
        $run.Output | Should -Not -Match 'No members found'
        $run.FailLines | Should -Be 1
        $run.Output | Should -Match 'Failed: 1\b'
    }

    It 'reports a member that cannot be looked up with the Graph error, as 1 failed check' {
        $run = $script:MemberUnreadable
        $run.ExitCode | Should -Be 1 -Because "a refused read must not pass for a missing member; output was:`n$($run.Output)"
        $run.Output | Should -Match '\[FAIL\] Error checking members of SkyCraft-Testers: [^\r\n]*stub lookup failure: Get-MgUser -UserId chromie\.timewalker'
        $run.Output | Should -Not -Match 'NOT found in group'
        $run.FailLines | Should -Be 1
        $run.Output | Should -Match 'Failed: 1\b'
    }

    It 'skips a nested group and a service principal held next to the expected user, and passes' {
        # Neither has a /users/{id}; looking them up as users would 404 and fail a group that
        # does hold its expected member.
        $run = $script:MixedMembers
        $run.ExitCode | Should -Be 0 -Because "output was:`n$($run.Output)"
        $run.Output | Should -Match 'nested-group \(#microsoft\.graph\.group\) - not a user, skipped'
        $run.Output | Should -Match 'service-principal \(#microsoft\.graph\.servicePrincipal\) - not a user, skipped'
        $run.Output | Should -Match '\[OK\] Verify: Khadgar Archmage is a member'
        $run.Output | Should -Not -Match 'Request_ResourceNotFound'
        $run.FailLines | Should -Be 0
        $run.Output | Should -Match 'Passed: 10\b'
        $run.Output | Should -Match 'Failed: 0\b'
    }

    It 'counts every check whose lookup fails with an error, and exits 1 (the reproduction in #241)' {
        $run = $script:LookupsFail
        $run.ExitCode | Should -Be 1 -Because "output was:`n$($run.Output)"
        # Four users, three groups, and the three memberships of groups that could not be read.
        ([regex]::Matches($run.Output, '\[FAIL\] Error checking user')).Count | Should -Be 4
        ([regex]::Matches($run.Output, '\[FAIL\] Error checking group')).Count | Should -Be 3
        ([regex]::Matches($run.Output, '\[FAIL\] Membership of [^:]+: group not found or not readable')).Count | Should -Be 3
        $run.FailLines | Should -Be 10
        $run.Output | Should -Match 'Passed: 0\b'
        $run.Output | Should -Match 'Failed: 10\b'
        $run.Output | Should -Match 'validation failed: 10 check\(s\) failed'
        $run.Output | Should -Not -Match 'validation complete|validation passed'
    }
}

Describe 'Lab 1.1 Test-Lab.ps1 - a sign-in that fails is a failed validation' {

    It 'exits 1 when the Microsoft Graph sign-in throws, before looking anything up' {
        $run = $script:SignInFails
        $run.ExitCode | Should -Be 1 -Because "output was:`n$($run.Output)"
        $run.Output | Should -Match '\[ERROR\] Failed to connect to Microsoft Graph'
        $run.Calls | Should -Not -Contain 'Get-MgUser'
        $run.Calls | Should -Not -Contain 'Get-MgGroup'
    }

    It 'exits 1 with an [ERROR] when the sign-in leaves no Graph context, and runs no check (#242)' {
        $run = $script:NoContext
        $run.ExitCode | Should -Be 1 -Because "a sign-in that did not complete must not pass; output was:`n$($run.Output)"
        $run.Output | Should -Match '\[ERROR\]'
        $run.Output | Should -Not -Match '\[OK\]'
        $run.Output | Should -Not -Match 'validation passed'
        $run.Calls | Should -Not -Contain 'Get-MgUser'
        $run.Calls | Should -Not -Contain 'Get-MgGroup'
    }
}
