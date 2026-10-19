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
      2. A run in which one role assignment is missing exits 1, and its summary states the
         count: exactly 1. A missing resource group fails its own check and leaves the role
         check at its scope with no assignment at all; both are counted: exactly 2.
      3. A run in which every role-assignment lookup fails with an error counts each of those
         checks as failed: a lookup that failed must not read as a pass.
      4. A run with no one signed in exits 1 before anything is looked up.
      5. -SkipRoleAssignments (what the lab cycle passes) checks the resource groups only, does
         not count the role checks, and exits 0 when the resource groups are there.
      6. An Owner assignment for Malfurion with a condition is a failed check (#325): the lab's
         has none.
      7. The role assignments are read through the ARM role assignments API (issue #397), never
         through Get-AzRoleAssignment, which calls Microsoft Graph; only the principals are
         looked up in Entra ID. When that lookup cannot reach Graph, each role check fails and
         names the sign-in that provides it; a principal that is missing or held twice fails its
         check without that hint, since signing in again would not help.

    Scope limit, as in the Lab 1.1 suite: the child is launched with -Command, so these tests
    prove the failure counter reaches `exit`, not that `pwsh -File` carries the code out of the
    process. That half is Exit-Lab's (tools/LabCommon.psm1, issues #104 and #257), proven with
    real pwsh processes by tests/Exit-Code-Propagation.Tests.ps1.

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
        'Get-AzADUser'
        'Get-AzADGroup'
        'Invoke-AzRestMethod'
    )

    # Every Az command the script calls, recording its own invocation. By default the
    # subscription holds exactly what the lab builds: the three resource groups and the five role
    # assignments, next to the operator's own Owner assignment and a Reader for SkyCraft-Testers
    # on the subscription, which every resource group inherits but which is not the lab's
    # resource-group assignment. The role assignments are served by the ARM role assignments API
    # fake from tests/Support/LabScriptStub.psm1 (issue #397), which calls Get-StubRoleAssignment.
    # Environment variables take pieces away, so one generated module serves every scenario:
    #   SKYCRAFT_STUB_NOCONTEXT       '1' leaves no Az context, as when no one is signed in
    #   SKYCRAFT_STUB_MISSINGRG       resource groups (by name) that do not exist: the group
    #                                 lookup fails, as the real cmdlet does, and ARM answers a role
    #                                 assignment listing at the group's scope with 404
    #   SKYCRAFT_STUB_MISSINGROLE     role assignments left out, by key: owner, developers,
    #                                 testers-dev, testers-prod, partner
    #   SKYCRAFT_STUB_ROLELOOKUPFAIL  '1' makes every role assignment listing fail (HTTP 403)
    #   SKYCRAFT_STUB_GRAPHFAIL       '1' makes every Entra ID lookup fail the way Az does when the
    #                                 tenant wants interaction before it issues a Graph token
    #   SKYCRAFT_STUB_MISSINGPRINCIPAL  principals (by name) the directory does not hold
    #   SKYCRAFT_STUB_OWNERCONDITION  '1' gives Malfurion's Owner assignment a condition, as any
    #                                 Conditions-tab option but "Allow user to assign all roles"
    #                                 does in the Portal (#325)
    #   SKYCRAFT_STUB_DUPLICATEPRINCIPAL  principals (by name) the directory holds twice
    $script:StubBody = @'
$script:LogPath = $env:SKYCRAFT_STUB_LOG
$script:SubId   = '00000000-0000-0000-0000-000000000000'
$script:Principal = @{
    'malfurion.stormrage'     = 'aaaaaaaa-0000-0000-0000-000000000001'
    'SkyCraft-Developers'     = 'aaaaaaaa-0000-0000-0000-000000000002'
    'SkyCraft-Testers'        = 'aaaaaaaa-0000-0000-0000-000000000003'
    'istormrage@illidari.com' = 'aaaaaaaa-0000-0000-0000-000000000004'
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

# The directory lookups Az makes through Microsoft Graph with its own token.
function Find-StubPrincipal {
    param([string]$Name)
    if ($env:SKYCRAFT_STUB_GRAPHFAIL -eq '1') {
        throw 'Authentication failed against resource MicrosoftGraphEndpointResourceId. User interaction is required. (stub)'
    }
    if (Test-StubListed -Variable 'SKYCRAFT_STUB_MISSINGPRINCIPAL' -Name $Name) { return }
    [pscustomobject]@{ Id = $script:Principal[$Name]; DisplayName = $Name }
    if (Test-StubListed -Variable 'SKYCRAFT_STUB_DUPLICATEPRINCIPAL' -Name $Name) {
        [pscustomobject]@{ Id = 'cccccccc-0000-0000-0000-000000000009'; DisplayName = $Name }
    }
}

function Get-AzADUser {
    [CmdletBinding()]
    param([string]$Filter)
    Write-StubCall -Name "Get-AzADUser|$Filter"
    switch ($Filter) {
        "startsWith(userPrincipalName,'malfurion.stormrage@')" { Find-StubPrincipal -Name 'malfurion.stormrage' }
        "mail eq 'istormrage@illidari.com'" { Find-StubPrincipal -Name 'istormrage@illidari.com' }
        default { throw "stub: unexpected Get-AzADUser filter '$Filter'" }
    }
}

function Get-AzADGroup {
    [CmdletBinding()]
    param([string]$DisplayName)
    Write-StubCall -Name "Get-AzADGroup|$DisplayName"
    if ($DisplayName -notin 'SkyCraft-Developers', 'SkyCraft-Testers') { throw "stub: unexpected group '$DisplayName'" }
    Find-StubPrincipal -Name $DisplayName
}

# What ARM lists for a scope: the assignments at it, above it and below it. A resource group that
# does not exist is a 404.
function Get-StubRoleAssignment {
    [CmdletBinding()]
    param([string]$Scope, [string]$PrincipalId)
    Write-StubCall -Name 'Get-RoleAssignment'
    if ($env:SKYCRAFT_STUB_ROLELOOKUPFAIL -eq '1') {
        Write-Error -ErrorId 'AuthorizationFailed' -Message "The client 'stub' does not have authorization to perform action 'Microsoft.Authorization/roleAssignments/read' over scope '$Scope'."
        return
    }
    if ($Scope -match '/resourceGroups/([^/]+)$' -and (Test-StubListed -Variable 'SKYCRAFT_STUB_MISSINGRG' -Name $Matches[1])) {
        Write-Error -ErrorId 'ResourceGroupNotFound' -Message "Resource group '$($Matches[1])' could not be found."
        return
    }

    $sub = "/subscriptions/$script:SubId"
    # ARM returns a condition as a string in properties.condition; the validator only asks whether
    # there is one, so any non-empty text stands for the Portal's options.
    $ownerCondition = if ($env:SKYCRAFT_STUB_OWNERCONDITION -eq '1') { "((!(ActionMatches{'Microsoft.Authorization/roleAssignments/write'})))" } else { '' }
    $all = @(
        @{ Key = 'operator';     Name = 'ra-0'; Principal = 'bbbbbbbb-0000-0000-0000-000000000099'; Role = '8e3af657-a8ff-443c-a75c-2fe8c4bcb635'; Scope = $sub }
        @{ Key = 'owner';        Name = 'ra-1'; Principal = $script:Principal['malfurion.stormrage']; Role = '8e3af657-a8ff-443c-a75c-2fe8c4bcb635'; Scope = $sub; Condition = $ownerCondition }
        @{ Key = 'developers';   Name = 'ra-2'; Principal = $script:Principal['SkyCraft-Developers']; Role = 'b24988ac-6180-42a0-ab88-20f7382dd24c'; Scope = "$sub/resourceGroups/dev-skycraft-swc-rg"; Type = 'Group' }
        @{ Key = 'testers-dev';  Name = 'ra-3'; Principal = $script:Principal['SkyCraft-Testers']; Role = 'acdd72a7-3385-48ef-bd42-f606fba81ae7'; Scope = "$sub/resourceGroups/dev-skycraft-swc-rg"; Type = 'Group' }
        @{ Key = 'testers-prod'; Name = 'ra-4'; Principal = $script:Principal['SkyCraft-Testers']; Role = 'acdd72a7-3385-48ef-bd42-f606fba81ae7'; Scope = "$sub/resourceGroups/prod-skycraft-swc-rg"; Type = 'Group' }
        @{ Key = 'partner';      Name = 'ra-5'; Principal = $script:Principal['istormrage@illidari.com']; Role = 'acdd72a7-3385-48ef-bd42-f606fba81ae7'; Scope = "$sub/resourceGroups/platform-skycraft-swc-rg" }
        @{ Key = 'inherited';    Name = 'ra-6'; Principal = $script:Principal['SkyCraft-Testers']; Role = 'acdd72a7-3385-48ef-bd42-f606fba81ae7'; Scope = $sub; Type = 'Group' }
    )
    foreach ($entry in $all) {
        if (Test-StubListed -Variable 'SKYCRAFT_STUB_MISSINGROLE' -Name $entry.Key) { continue }
        $related = $entry.Scope -eq $Scope -or $Scope -like "$($entry.Scope)/*" -or $entry.Scope -like "$Scope/*"
        if (-not $related) { continue }
        [pscustomobject]@{ Name = $entry.Name; Scope = $entry.Scope; PrincipalId = $entry.Principal; RoleDefinitionId = $entry.Role; PrincipalType = $(if ($entry.Type) { $entry.Type } else { 'User' }); Condition = $entry.Condition }
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
            [switch]$OwnerCondition,
            [switch]$GraphFail,
            [string[]]$MissingPrincipal = @(),
            [string[]]$DuplicatePrincipal = @(),
            [switch]$NoContext,
            [string[]]$ArgumentList = @()
        )

        $logPath = Join-Path $Stub.Directory 'calls.log'
        Remove-Item -LiteralPath $logPath -Force -ErrorAction SilentlyContinue

        $run = Invoke-LabScriptWithStub -Stub $Stub -ScriptPath $script:ScriptPath -ArgumentList $ArgumentList -Environment @{
            SKYCRAFT_STUB_MISSINGRG      = $MissingResourceGroup -join ','
            SKYCRAFT_STUB_MISSINGROLE    = $MissingRole -join ','
            SKYCRAFT_STUB_ROLELOOKUPFAIL = if ($RoleLookupFail) { '1' } else { '0' }
            SKYCRAFT_STUB_OWNERCONDITION = if ($OwnerCondition) { '1' } else { '0' }
            SKYCRAFT_STUB_GRAPHFAIL      = if ($GraphFail) { '1' } else { '0' }
            SKYCRAFT_STUB_MISSINGPRINCIPAL = $MissingPrincipal -join ','
            SKYCRAFT_STUB_DUPLICATEPRINCIPAL = $DuplicatePrincipal -join ','
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
        -Body ($script:StubBody + (Get-LabArmRoleAssignmentStub)) -RequiredModule $script:RequiredModules
    $script:StubDir = $script:Stub.Directory

    # One invocation per scenario, reused by the assertions below - each child process costs
    # several seconds.
    $script:AllPass        = Invoke-ValidatorScript -Stub $script:Stub
    $script:RgMissing      = Invoke-ValidatorScript -Stub $script:Stub -MissingResourceGroup 'platform-skycraft-swc-rg'
    $script:RoleMissing    = Invoke-ValidatorScript -Stub $script:Stub -MissingRole 'testers-prod'
    $script:RoleLookupFail = Invoke-ValidatorScript -Stub $script:Stub -RoleLookupFail
    $script:OwnerCondition = Invoke-ValidatorScript -Stub $script:Stub -OwnerCondition
    # The Az sign-in cannot get a Graph token without interaction (issue #397).
    $script:GraphFail      = Invoke-ValidatorScript -Stub $script:Stub -GraphFail
    $script:NoDevelopers   = Invoke-ValidatorScript -Stub $script:Stub -MissingPrincipal 'SkyCraft-Developers'
    $script:TwoDevelopers  = Invoke-ValidatorScript -Stub $script:Stub -DuplicatePrincipal 'SkyCraft-Developers'
    $script:NoContext      = Invoke-ValidatorScript -Stub $script:Stub -NoContext
    # The lab cycle's run: resource groups deployed, no role assignment made.
    $script:CycleRun       = Invoke-ValidatorScript -Stub $script:Stub -ArgumentList '-SkipRoleAssignments' `
        -MissingRole 'owner', 'developers', 'testers-dev', 'testers-prod', 'partner'
    $script:CycleRgMissing = Invoke-ValidatorScript -Stub $script:Stub -ArgumentList '-SkipRoleAssignments' `
        -MissingResourceGroup 'dev-skycraft-swc-rg'

    $script:AllRuns = @(
        $script:AllPass, $script:RgMissing, $script:RoleMissing, $script:RoleLookupFail,
        $script:OwnerCondition, $script:NoContext, $script:CycleRun, $script:CycleRgMissing, $script:GraphFail, $script:NoDevelopers,
        $script:TwoDevelopers
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

    It 'exits 1 and counts both the missing resource group and the role check at its scope' {
        # ARM answers a role assignment listing at a resource group that does not exist with 404:
        # the External Partner check must be a counted [FAIL] like any other, never a pass.
        $run = $script:RgMissing
        $run.ExitCode | Should -Be 1 -Because "a missing resource group must not look like a passed validation; output was:`n$($run.Output)"
        $run.Output | Should -Match '\[FAIL\] Resource Group missing or unreadable: platform-skycraft-swc-rg'
        $run.Output | Should -Match 'External Partner\.\.\. \[FAIL\] Could not read role assignments at scope[^\r\n]*HTTP 404 \(ResourceGroupNotFound\)'
        $run.FailLines | Should -Be 2
        $run.Output | Should -Match 'Passed: 6\b'
        $run.Output | Should -Match 'Failed: 2\b'
        $run.Output | Should -Match 'validation failed: 2 check\(s\) failed'
        $run.Output | Should -Not -Match 'validation passed'
    }

    It 'exits 1 and reports 1 failed when one role assignment is missing' {
        # The Testers' Reader on the subscription, which the prod group inherits, is not the
        # prod-group assignment the lab makes: the check matches the exact scope.
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
        ([regex]::Matches($run.Output, '\[FAIL\] Could not read role assignments at scope[^\r\n]*HTTP 403 \(AuthorizationFailed\)')).Count | Should -Be 5
        $run.Output | Should -Not -Match "\[OK\] Found '"
        $run.Output | Should -Match 'Passed: 3\b'
        $run.Output | Should -Match 'Failed: 5\b'
    }

    It 'fails an Owner assignment for Malfurion that carries a condition, and exits 1 (#325)' {
        # Any Conditions-tab option but "Allow user to assign all roles" adds a condition; the
        # Bicep, the script and guide step 1.2.4 create the assignment without one.
        $run = $script:OwnerCondition
        $run.ExitCode | Should -Be 1 -Because "output was:`n$($run.Output)"
        $run.Output | Should -Match "Malfurion \(Admin\)\.\.\. \[FAIL\] 'Owner' assignment found, but with a condition"
        $run.FailLines | Should -Be 1
        $run.Output | Should -Match 'Passed: 7\b'
        $run.Output | Should -Match 'Failed: 1\b'
    }
}

Describe 'Lab 1.2 Test-Lab.ps1 - role assignments without Microsoft Graph (#397)' {

    It 'reads the role assignments through the ARM API, once per check, filtered by principal' {
        # Get-RoleAssignment is logged by the ARM fake's callback: Invoke-AzRestMethod, not the
        # Az role cmdlets (which the stub does not define, so a call to them would reach the real
        # module and fail the harness check).
        @($script:AllPass.Calls | Where-Object { $_ -eq 'Get-RoleAssignment' }).Count | Should -Be 5
    }

    It 'looks each principal up once, by the names Lab 1.1 gives them' {
        $calls = $script:AllPass.Calls
        $calls | Should -Contain "Get-AzADUser|startsWith(userPrincipalName,'malfurion.stormrage@')"
        $calls | Should -Contain "Get-AzADUser|mail eq 'istormrage@illidari.com'"
        @($calls | Where-Object { $_ -eq 'Get-AzADGroup|SkyCraft-Testers' }).Count | Should -Be 1
        @($calls | Where-Object { $_ -eq 'Get-AzADGroup|SkyCraft-Developers' }).Count | Should -Be 1
    }

    It 'fails every role check, names the sign-in that provides Graph, and reads no role assignment, when Graph is out of reach' {
        $run = $script:GraphFail
        $run.ExitCode | Should -Be 1 -Because "output was:`n$($run.Output)"
        ([regex]::Matches($run.Output, "\[FAIL\] Could not look up '[^']+' in Entra ID: [^\r\n]*MicrosoftGraphEndpointResourceId[^\r\n]*Connect-AzAccount -AuthScope MicrosoftGraphEndpointResourceId")).Count | Should -Be 5
        $run.Output | Should -Match 'Passed: 3\b'
        $run.Output | Should -Match 'Failed: 5\b'
        $run.Calls | Should -Not -Contain 'Get-RoleAssignment'
    }

    It 'fails the check of a principal Lab 1.1 did not create, and still checks the rest' {
        $run = $script:NoDevelopers
        $run.ExitCode | Should -Be 1 -Because "output was:`n$($run.Output)"
        $run.Output | Should -Match "Developers Group\.\.\. \[FAIL\] 'SkyCraft-Developers' not found in Entra ID\. Complete Lab 1\.1 first\."
        $run.Output | Should -Not -Match 'AuthScope' -Because 'signing in again does not create a principal'
        $run.Output | Should -Match 'Passed: 7\b'
        $run.Output | Should -Match 'Failed: 1\b'
    }

    It 'fails the check of a principal the directory holds twice, without naming the Graph sign-in' {
        # The lookup worked: the hint would send the learner to sign in again for nothing.
        $run = $script:TwoDevelopers
        $run.ExitCode | Should -Be 1 -Because "output was:`n$($run.Output)"
        $run.Output | Should -Match "Developers Group\.\.\. \[FAIL\] 'SkyCraft-Developers' matched 2 principals in Entra ID; expected exactly one\."
        $run.Output | Should -Not -Match 'AuthScope'
        $run.Output | Should -Match 'Passed: 7\b'
        $run.Output | Should -Match 'Failed: 1\b'
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
        $run.Calls | Should -Not -Contain 'Get-RoleAssignment'
        @($run.Calls | Where-Object { $_ -like 'Get-AzAD*' }) | Should -BeNullOrEmpty
    }
}

Describe 'Lab 1.2 Test-Lab.ps1 -SkipRoleAssignments - the lab cycle''s run' {

    It 'checks the resource groups only and exits 0 when they exist, with no role assignment made' {
        $run = $script:CycleRun
        $run.ExitCode | Should -Be 0 -Because "the cycle deploys no role assignment; output was:`n$($run.Output)"
        $run.Output | Should -Match '\[SKIP\] 5 role-assignment checks not run'
        $run.Calls | Should -Not -Contain 'Get-RoleAssignment'
        @($run.Calls | Where-Object { $_ -like 'Get-AzAD*' }) | Should -BeNullOrEmpty -Because 'the lab cycle''s run needs no Microsoft Graph'
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
