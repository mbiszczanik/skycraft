<#
.SYNOPSIS
    Pester 5 tests for the Lab 1.2 validator's failure count and exit code.

.DESCRIPTION
    Regression cover for issue #254. Test-Lab.ps1 printed [FAIL] for every check that failed and
    then ended "Validation complete." with exit code 0, and when no one was signed in it left
    with 'return' - exit 0 as well - so the lab cycle read a failed or unrun validation as a
    passed one. These tests run the real Test-Lab.ps1 in a child pwsh process against a generated
    stub of the Az commands it calls, and assert the observable contract:

      1. A run in which every check passes exits 0, and its summary says 0 failed.
      2. A run in which one check fails - a missing resource group, a missing role assignment -
         exits 1, and its summary states the count: exactly 1.
      3. A run in which every role-assignment lookup fails with an error counts each of those
         checks as failed: a lookup that failed must not read as a pass.
      4. A run with no one signed in exits 1 before anything is looked up.
      5. -SkipRoleAssignments (what the lab cycle passes) checks the resource groups only, does
         not count the role checks, and exits 0 when the resource groups are there.

    Scope limit, as in the Lab 1.1 suite: the child is launched with -Command, so these tests
    prove the failure counter reaches `exit`, not that `pwsh -File` carries the code out of the
    process. That half is issue #104's guard ($Host.SetShouldExit before every non-zero exit),
    enforced repo-wide by tests/Exit-Code-Propagation.Tests.ps1.

    No subscription is needed, and none is used. The script runs through
    tests/Support/LabScriptStub.psm1 (issue #112), which imports the real modules first, the stub
    module last, and aborts the child with exit 99 unless every stubbed command resolves to the
    stub.

.EXAMPLE
    Invoke-Pester -Path .\Test-Lab.Tests.ps1

.NOTES
    Project: SkyCraft
    Lab: 1.2 - RBAC
#>

#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..' '..' '..' 'tests' 'Support' 'LabScriptStub.psm1') -Force

    $script:ScriptPath     = (Resolve-Path (Join-Path $PSScriptRoot '..' 'scripts' 'Test-Lab.ps1')).Path
    $script:StubModuleName = 'SkyCraftLab12ValidatorStub'
    # Exactly the script's '#Requires -Modules' line: these are imported for real before the stub.
    $script:RequiredModules = @('Az.Accounts', 'Az.Resources')

    $script:StubCommands = @(
        'Get-AzContext'
        'Get-AzResourceGroup'
        'Get-AzRoleAssignment'
    )

    # Every Az command the script calls, recording its own invocation. By default the
    # subscription holds exactly what the lab builds: the three resource groups and the five role
    # assignments. Environment variables take pieces away, so one generated module serves every
    # scenario:
    #   SKYCRAFT_STUB_NOCONTEXT       '1' leaves no Az context, as when no one is signed in
    #   SKYCRAFT_STUB_MISSINGRG       resource groups (by name) the lookup fails for, as the real
    #                                 cmdlet does for a group that does not exist
    #   SKYCRAFT_STUB_MISSINGROLE     role assignments left out, by key: owner, developers,
    #                                 testers-dev, testers-prod, partner
    #   SKYCRAFT_STUB_ROLELOOKUPFAIL  '1' makes every role-assignment lookup fail with an error
    $script:StubBody = @'
$script:LogPath = $env:SKYCRAFT_STUB_LOG
$script:SubId   = '00000000-0000-0000-0000-000000000000'

function Write-StubCall {
    param([string]$Name)
    if ($script:LogPath) { Add-Content -LiteralPath $script:LogPath -Value $Name }
}

function Test-StubListed {
    param([string]$Variable, [string]$Name)
    if (-not $Name) { return $false }
    return (@([System.Environment]::GetEnvironmentVariable($Variable) -split ',') -contains $Name)
}

function New-StubAssignment {
    param([string]$Key, [string]$Role, [string]$SignInName, [string]$DisplayName)
    if (Test-StubListed -Variable 'SKYCRAFT_STUB_MISSINGROLE' -Name $Key) { return }
    [pscustomobject]@{ RoleDefinitionName = $Role; SignInName = $SignInName; DisplayName = $DisplayName }
}

function Get-AzContext {
    [CmdletBinding()]
    param()
    if ($env:SKYCRAFT_STUB_NOCONTEXT -eq '1') { return }
    [pscustomobject]@{
        Subscription = [pscustomobject]@{ Id = $script:SubId; Name = 'stub-subscription' }
    }
}

function Get-AzResourceGroup {
    [CmdletBinding()]
    param([string]$Name, [Parameter(ValueFromRemainingArguments)]$Rest)
    Write-StubCall -Name 'Get-AzResourceGroup'
    if (Test-StubListed -Variable 'SKYCRAFT_STUB_MISSINGRG' -Name $Name) {
        Write-Error "Provided resource group does not exist. (stub: $Name)"
        return
    }
    [pscustomobject]@{ ResourceGroupName = $Name; Location = 'swedencentral' }
}

# Returns what the real cmdlet returns for a scope: the assignments made there plus the ones
# inherited from above. The operator's own Owner assignment on the subscription is always among
# them, so a scope never comes back empty just because a lab assignment is missing.
function Get-AzRoleAssignment {
    [CmdletBinding()]
    param([string]$Scope, [Parameter(ValueFromRemainingArguments)]$Rest)
    Write-StubCall -Name 'Get-AzRoleAssignment'
    if ($env:SKYCRAFT_STUB_ROLELOOKUPFAIL -eq '1') { Write-Error 'stub lookup failure: Get-AzRoleAssignment'; return }

    $sub = "/subscriptions/$script:SubId"
    [pscustomobject]@{ RoleDefinitionName = 'Owner'; SignInName = 'operator@contoso.example'; DisplayName = 'Operator' }
    New-StubAssignment -Key 'owner' -Role 'Owner' -SignInName 'malfurion.stormrage@contoso.example' -DisplayName 'Malfurion Stormrage'

    switch ($Scope) {
        "$sub/resourceGroups/dev-skycraft-swc-rg" {
            New-StubAssignment -Key 'developers'  -Role 'Contributor' -DisplayName 'SkyCraft-Developers'
            New-StubAssignment -Key 'testers-dev' -Role 'Reader'      -DisplayName 'SkyCraft-Testers'
        }
        "$sub/resourceGroups/prod-skycraft-swc-rg" {
            New-StubAssignment -Key 'testers-prod' -Role 'Reader' -DisplayName 'SkyCraft-Testers'
        }
        "$sub/resourceGroups/platform-skycraft-swc-rg" {
            New-StubAssignment -Key 'partner' -Role 'Reader' -SignInName 'istormrage_example.com#EXT#@contoso.example' -DisplayName 'Illidan Stormrage'
        }
    }
}
'@

    # Runs the real script in a child process with the stubs shadowing the Az commands, and
    # returns the exit code it hands back together with the stub's call log.
    function Invoke-ValidatorScript {
        param(
            [pscustomobject]$Stub,
            [string[]]$MissingResourceGroup = @(),
            [string[]]$MissingRole = @(),
            [switch]$RoleLookupFail,
            [switch]$NoContext,
            [string[]]$ArgumentList = @()
        )

        $logPath = Join-Path $Stub.Directory 'calls.log'
        Remove-Item -LiteralPath $logPath -Force -ErrorAction SilentlyContinue

        $run = Invoke-LabScriptWithStub -Stub $Stub -ScriptPath $script:ScriptPath -ArgumentList $ArgumentList -Environment @{
            SKYCRAFT_STUB_MISSINGRG      = $MissingResourceGroup -join ','
            SKYCRAFT_STUB_MISSINGROLE    = $MissingRole -join ','
            SKYCRAFT_STUB_ROLELOOKUPFAIL = if ($RoleLookupFail) { '1' } else { '0' }
            SKYCRAFT_STUB_NOCONTEXT      = if ($NoContext) { '1' } else { '0' }
            SKYCRAFT_STUB_LOG            = $logPath
        }

        $calls = if (Test-Path -LiteralPath $logPath) { @(Get-Content -LiteralPath $logPath) } else { @() }
        return [pscustomobject]@{
            ExitCode  = $run.ExitCode
            Refused   = $run.Refused
            Output    = $run.Output
            Calls     = $calls
            # Check lines only: the summary's own "see the [FAIL] lines" pointer is not a check.
            FailLines = ([regex]::Matches($run.Output, '(?m)(^|\.\.\.\s*)\[FAIL\]')).Count
        }
    }

    $script:Stub    = Initialize-LabScriptStub -Name $script:StubModuleName -Command $script:StubCommands `
        -Body $script:StubBody -RequiredModule $script:RequiredModules
    $script:StubDir = $script:Stub.Directory

    # One invocation per scenario, reused by the assertions below - each child process costs
    # several seconds.
    $script:AllPass        = Invoke-ValidatorScript -Stub $script:Stub
    $script:RgMissing      = Invoke-ValidatorScript -Stub $script:Stub -MissingResourceGroup 'platform-skycraft-swc-rg'
    $script:RoleMissing    = Invoke-ValidatorScript -Stub $script:Stub -MissingRole 'testers-prod'
    $script:RoleLookupFail = Invoke-ValidatorScript -Stub $script:Stub -RoleLookupFail
    $script:NoContext      = Invoke-ValidatorScript -Stub $script:Stub -NoContext
    # The lab cycle's run: resource groups deployed, no role assignment made.
    $script:CycleRun       = Invoke-ValidatorScript -Stub $script:Stub -ArgumentList '-SkipRoleAssignments' `
        -MissingRole 'owner', 'developers', 'testers-dev', 'testers-prod', 'partner'
    $script:CycleRgMissing = Invoke-ValidatorScript -Stub $script:Stub -ArgumentList '-SkipRoleAssignments' `
        -MissingResourceGroup 'dev-skycraft-swc-rg'

    $script:AllRuns = @(
        $script:AllPass, $script:RgMissing, $script:RoleMissing, $script:RoleLookupFail,
        $script:NoContext, $script:CycleRun, $script:CycleRgMissing
    )
}

AfterAll {
    if ($script:StubDir) { Remove-Item -LiteralPath $script:StubDir -Recurse -Force -ErrorAction SilentlyContinue }
}

Describe 'Lab 1.2 Test-Lab.ps1 - test harness' {

    It 'shadows the real Az commands instead of touching a subscription' {
        # Refused is the child exiting 99 before the script ran. Asserted on every scenario: a
        # refusal in one of them is a half-stubbed session, not a scenario-specific failure.
        foreach ($run in $script:AllRuns) {
            $run.Refused | Should -BeFalse -Because "the harness must never fall through to the real Az commands (exit $($run.ExitCode)): $($run.Output)"
        }
    }
}

Describe 'Lab 1.2 Test-Lab.ps1 - failures are counted and set the exit code (#254)' {

    It 'exits 0 and reports 0 failed when every check passes' {
        $run = $script:AllPass
        $run.ExitCode | Should -Be 0 -Because "a passing validation must report success; output was:`n$($run.Output)"
        $run.FailLines | Should -Be 0
        # Three resource groups and five role assignments.
        $run.Output | Should -Match 'Passed: 8\b'
        $run.Output | Should -Match 'Failed: 0\b'
        $run.Output | Should -Match 'validation passed'
        $run.Output | Should -Not -Match 'validation failed'
    }

    It 'exits 1 and reports 1 failed when one resource group is missing' {
        $run = $script:RgMissing
        $run.ExitCode | Should -Be 1 -Because "a missing resource group must not look like a passed validation; output was:`n$($run.Output)"
        $run.Output | Should -Match '\[FAIL\] Resource Group missing or unreadable: platform-skycraft-swc-rg'
        $run.FailLines | Should -Be 1
        $run.Output | Should -Match 'Passed: 7\b'
        $run.Output | Should -Match 'Failed: 1\b'
        $run.Output | Should -Match 'validation failed: 1 check\(s\) failed'
        $run.Output | Should -Not -Match 'validation passed'
    }

    It 'exits 1 and reports 1 failed when one role assignment is missing' {
        $run = $script:RoleMissing
        $run.ExitCode | Should -Be 1 -Because "output was:`n$($run.Output)"
        $run.Output | Should -Match "Testers Group \(Prod\)\.\.\. \[FAIL\] Expected Assignment 'Reader' for 'SkyCraft-Testers' NOT found"
        $run.FailLines | Should -Be 1
        $run.Output | Should -Match 'Passed: 7\b'
        $run.Output | Should -Match 'Failed: 1\b'
    }

    It 'counts every role check whose lookup fails with an error as failed, and exits 1' {
        # The lookup used -ErrorAction SilentlyContinue and its error path printed an uncounted
        # [ERROR]: a lookup that failed must be a failed check, not a pass and not nothing.
        $run = $script:RoleLookupFail
        $run.ExitCode | Should -Be 1 -Because "output was:`n$($run.Output)"
        ([regex]::Matches($run.Output, '\[FAIL\] Could not read role assignments')).Count | Should -Be 5
        $run.Output | Should -Not -Match "\[OK\] Found '"
        $run.Output | Should -Match 'Passed: 3\b'
        $run.Output | Should -Match 'Failed: 5\b'
    }
}

Describe 'Lab 1.2 Test-Lab.ps1 - no one signed in is a failed validation (#254)' {

    It 'exits 1 with an [ERROR] and looks nothing up' {
        # It used to leave with 'return', which is exit 0.
        $run = $script:NoContext
        $run.ExitCode | Should -Be 1 -Because "an unrun validation must not pass; output was:`n$($run.Output)"
        $run.Output | Should -Match '\[ERROR\] Not logged in'
        $run.Output | Should -Not -Match '\[OK\]'
        $run.Output | Should -Not -Match 'validation passed'
        $run.Calls | Should -Not -Contain 'Get-AzResourceGroup'
        $run.Calls | Should -Not -Contain 'Get-AzRoleAssignment'
    }
}

Describe 'Lab 1.2 Test-Lab.ps1 -SkipRoleAssignments - the lab cycle''s run' {

    It 'checks the resource groups only and exits 0 when they exist, with no role assignment made' {
        $run = $script:CycleRun
        $run.ExitCode | Should -Be 0 -Because "the cycle deploys no role assignment; output was:`n$($run.Output)"
        $run.Output | Should -Match '\[SKIP\] 5 role-assignment checks not run'
        $run.Calls | Should -Not -Contain 'Get-AzRoleAssignment'
        $run.Output | Should -Match 'Passed: 3\b'
        $run.Output | Should -Match 'Failed: 0\b'
    }

    It 'still exits 1 when a resource group is missing' {
        $run = $script:CycleRgMissing
        $run.ExitCode | Should -Be 1 -Because "output was:`n$($run.Output)"
        $run.FailLines | Should -Be 1
        $run.Output | Should -Match 'Failed: 1\b'
    }
}
