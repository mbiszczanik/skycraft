<#
.SYNOPSIS
    Pester 5 tests for the Lab 1.3 validator's failure count, exit code and lock check.

.DESCRIPTION
    Regression cover for issue #254. Test-Lab.ps1 printed [FAIL] for every check that failed and
    then ended "Validation Complete." with exit code 0, so the lab cycle read a failed validation
    as a passed one. These tests run the real Test-Lab.ps1 in a child pwsh process against a
    generated stub of the Az commands it calls, and assert the observable contract:

      1. A run in which every check passes exits 0, and its summary says 0 failed.
      2. A run in which one check fails - a missing policy assignment, a resource group without
         a lock, a wrong Project tag, a resource group with no tags at all - exits 1, and its
         summary states the count: exactly 1. A missing resource group fails both checks that
         read it, its tags and its lock: exactly 2.
      3. A run in which every lookup fails with an error counts each check as failed and exits 1:
         a lookup that failed must not read as a pass.
      4. A run with no one signed in exits 1 before anything is looked up.
      5. Budgets are a manual check: their absence, or a budget lookup that fails, neither fails
         validation nor counts as a pass - and a failed lookup is not reported as "found".
      6. A lock check passes only for the guide's lock: its name, level CanNotDelete, applied to
         the group itself (issue #258). A ReadOnly lock, a lock under another name, a lock on a
         resource inside the group or on the subscription above it, or a lock lookup that fails
         each fail that one check, and the [FAIL] line says what was found. The scope comparison
         ignores case, as ARM ids do.
      7. A policy check finds its assignment whichever path made it (issue #330): the fixed name
         the Bicep path sets, or the display name a learner types into the Portal's Assignment
         name, next to a generated resource name. An assignment inherited from a management
         group or of another definition does not count, and two assignments that both match
         fail the check: the cleanup removes neither.
      8. The Modify assignment Inherit-Project-Tag (issue #350) is a fourth policy check, found
         by its own definition: it passes with tagName Project and a system-assigned identity,
         and fails when it is missing, inherits another tag, or has no managed identity. It
         never stands in for Enforce-Project-Tag.

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
    Lab: 1.3 - Governance
#>

#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..' '..' '..' 'tests' 'Support' 'LabScriptStub.psm1') -Force

    $script:ScriptPath     = (Resolve-Path (Join-Path $PSScriptRoot '..' 'scripts' 'Test-Lab.ps1')).Path
    $script:StubModuleName = 'SkyCraftLab13ValidatorStub'
    # Exactly the script's '#Requires -Modules' line: these are imported for real before the stub.
    $script:RequiredModules = @('Az.Accounts', 'Az.Resources', 'Az.Billing')

    $script:StubCommands = @(
        'Get-AzContext'
        'Get-AzResourceGroup'
        'Get-AzPolicyAssignment'
        'Get-AzResourceLock'
        'Get-AzConsumptionBudget'
    )

    # Every Az command the script calls, recording its own invocation. By default the
    # subscription holds exactly what the lab builds: the three tagged resource groups, the four
    # policy assignments, the guide's CanNotDelete lock on prod and platform, and one budget.
    # Environment variables take pieces away, so one generated module serves every scenario:
    #   SKYCRAFT_STUB_NOCONTEXT       '1' leaves no Az context, as when no one is signed in
    #   SKYCRAFT_STUB_MISSINGRG       resource groups that do not exist: the group and lock
    #                                 lookups fail for them, as the real cmdlets do
    #   SKYCRAFT_STUB_NOTAGS          resource groups that carry no tag at all
    #   SKYCRAFT_STUB_WRONGTAG        resource groups whose Project tag is not 'SkyCraft'
    #   SKYCRAFT_STUB_INHERITTAG      the tagName Inherit-Project-Tag carries (default 'Project')
    #   SKYCRAFT_STUB_INHERITIDENTITY 'none' leaves Inherit-Project-Tag without a managed identity
    #   SKYCRAFT_STUB_POLICYSET       who made the four policy assignments: 'bicep' (the default:
    #                                 fixed names), 'portal' (generated names, the guide's names
    #                                 as display names), 'scripted' (fixed names, the guide's
    #                                 names as display names: the Bicep and script paths since
    #                                 issue #406) or 'both' (two of each)
    #   SKYCRAFT_STUB_MISSINGPOLICY   policy assignments (by the guide's name) left out of the
    #                                 listing
    #   SKYCRAFT_STUB_NOLOCK          resource groups that carry no lock
    #   SKYCRAFT_STUB_LOCKKIND        'group=kind' pairs that change the one lock a group returns:
    #                                 'readonly' gives it level ReadOnly, 'wrongname' another
    #                                 name, 'child' puts it on a resource inside the group,
    #                                 'subscription' on the subscription above it, and 'fail'
    #                                 makes that group's lock lookup fail
    #   SKYCRAFT_STUB_LOOKUPFAIL      '1' makes every resource, policy and lock lookup fail
    #   SKYCRAFT_STUB_BUDGET          'none' returns no budget, 'fail' makes the lookup fail
    $script:StubBody = @'
$script:LogPath = $env:SKYCRAFT_STUB_LOG

function Write-StubCall {
    param([string]$Name)
    if ($script:LogPath) { Add-Content -LiteralPath $script:LogPath -Value $Name }
}

function Test-StubListed {
    param([string]$Variable, [string]$Name)
    if (-not $Name) { return $false }
    return (@([System.Environment]::GetEnvironmentVariable($Variable) -split ',') -contains $Name)
}

function Test-StubLookupFail { return $env:SKYCRAFT_STUB_LOOKUPFAIL -eq '1' }

function Get-StubLockKind {
    param([string]$Name)
    foreach ($pair in @($env:SKYCRAFT_STUB_LOCKKIND -split ',')) {
        $group, $kind = $pair -split '=', 2
        if ($group -and $group -eq $Name) { return $kind }
    }
}

function Get-AzContext {
    [CmdletBinding()]
    param()
    if ($env:SKYCRAFT_STUB_NOCONTEXT -eq '1') { return }
    [pscustomobject]@{
        Subscription = [pscustomobject]@{ Id = '00000000-0000-0000-0000-000000000000'; Name = 'stub-subscription' }
    }
}

function Get-AzResourceGroup {
    [CmdletBinding()]
    param([string]$Name, [Parameter(ValueFromRemainingArguments)]$Rest)
    Write-StubCall -Name 'Get-AzResourceGroup'
    if (Test-StubLookupFail) { Write-Error 'stub lookup failure: Get-AzResourceGroup'; return }
    if (Test-StubListed -Variable 'SKYCRAFT_STUB_MISSINGRG' -Name $Name) {
        Write-Error "Provided resource group does not exist. (stub: $Name)"
        return
    }
    if (Test-StubListed -Variable 'SKYCRAFT_STUB_NOTAGS' -Name $Name) {
        return [pscustomobject]@{ ResourceGroupName = $Name; Tags = $null }
    }
    $project = if (Test-StubListed -Variable 'SKYCRAFT_STUB_WRONGTAG' -Name $Name) { 'SomethingElse' } else { 'SkyCraft' }
    [pscustomobject]@{
        ResourceGroupName = $Name
        Tags              = @{ Project = $project; Environment = 'Development' }
    }
}

# Shaped like Get-AzPolicyAssignment's output in Az.Resources 7 and later. The Modify assignment
# (Inherit-Project-Tag) carries its tagName under Parameter and a system-assigned identity at the
# top level, as the real cmdlet returns them.
function New-StubAssignment {
    param([string]$Name, [string]$DisplayName, [string]$Definition, [string]$Scope, [switch]$Modify)
    $assignment = [pscustomobject]@{
        Name               = $Name
        DisplayName        = $DisplayName
        PolicyDefinitionId = "/providers/Microsoft.Authorization/policyDefinitions/$Definition"
        Scope              = $Scope
        Id                 = "$Scope/providers/Microsoft.Authorization/policyAssignments/$Name"
    }
    if ($Modify) {
        $tagName = if ($null -ne $env:SKYCRAFT_STUB_INHERITTAG -and $env:SKYCRAFT_STUB_INHERITTAG -ne '') { $env:SKYCRAFT_STUB_INHERITTAG } else { 'Project' }
        $noIdentity = $env:SKYCRAFT_STUB_INHERITIDENTITY -eq 'none'
        $assignment | Add-Member -NotePropertyName Parameter -NotePropertyValue ([pscustomobject]@{ tagName = [pscustomobject]@{ value = $tagName } })
        $assignment | Add-Member -NotePropertyName IdentityType -NotePropertyValue $(if ($noIdentity) { 'None' } else { 'SystemAssigned' })
        $assignment | Add-Member -NotePropertyName IdentityPrincipalId -NotePropertyValue $(if ($noIdentity) { $null } else { '11111111-1111-1111-1111-111111111111' })
    }
    $assignment
}

# Lists the assignments that apply to the subscription, as the real cmdlet does for -Scope with
# no -Name: the lab's four, made by the Bicep path, the Portal or both, plus one inherited from a
# management group under the guide's name and an unrelated one under a guide display name.
function Get-AzPolicyAssignment {
    [CmdletBinding()]
    param([string]$Name, [string]$Scope, [Parameter(ValueFromRemainingArguments)]$Rest)
    Write-StubCall -Name 'Get-AzPolicyAssignment'
    if (Test-StubLookupFail) { Write-Error 'stub lookup failure: Get-AzPolicyAssignment'; return }
    if ($Name) { throw "stub: the lab looks assignments up by listing the scope, not by name ($Name)" }

    $lab = @(
        @{ Name = 'Require-Environment-Tag-RG'; Bicep = 'Require Environment Tag on Resource Groups'; Definition = '96670d01-0a4d-4649-9c89-2d3abc0a5025'; Portal = 'aaaaaaaaaaaaaaaaaaaaaaa1' }
        @{ Name = 'Enforce-Project-Tag'; Bicep = 'Enforce Project Tag Value'; Definition = '1e30110a-5ceb-460c-a204-c1c3969c6d62'; Portal = 'aaaaaaaaaaaaaaaaaaaaaaa2' }
        @{ Name = 'Inherit-Project-Tag'; Bicep = 'Inherit Project Tag from Resource Group'; Definition = 'ea3f2387-9b95-492a-a190-fcdc54f7b070'; Portal = 'aaaaaaaaaaaaaaaaaaaaaaa4'; Modify = $true }
        @{ Name = 'Restrict-Azure-Regions'; Bicep = 'Restrict to Allowed Regions'; Definition = 'e56962a6-4747-49cd-b67b-bf8b01975c4c'; Portal = 'aaaaaaaaaaaaaaaaaaaaaaa3' }
    )
    $set = if ($env:SKYCRAFT_STUB_POLICYSET) { $env:SKYCRAFT_STUB_POLICYSET } else { 'bicep' }
    foreach ($assignment in $lab) {
        if (Test-StubListed -Variable 'SKYCRAFT_STUB_MISSINGPOLICY' -Name $assignment.Name) { continue }
        $modify = [bool]$assignment.Modify
        if ($set -in 'bicep', 'both') {
            New-StubAssignment -Name $assignment.Name -DisplayName $assignment.Bicep -Definition $assignment.Definition -Scope $Scope -Modify:$modify
        }
        if ($set -eq 'scripted') {
            New-StubAssignment -Name $assignment.Name -DisplayName $assignment.Name -Definition $assignment.Definition -Scope $Scope -Modify:$modify
        }
        if ($set -in 'portal', 'both') {
            New-StubAssignment -Name $assignment.Portal -DisplayName $assignment.Name -Definition $assignment.Definition -Scope $Scope -Modify:$modify
        }
    }
    New-StubAssignment -Name 'Enforce-Project-Tag' -DisplayName 'Enforce Project Tag Value' -Definition '1e30110a-5ceb-460c-a204-c1c3969c6d62' `
        -Scope '/providers/Microsoft.Management/managementGroups/stub-mg'
    New-StubAssignment -Name 'bbbbbbbbbbbbbbbbbbbbbbb1' -DisplayName 'Restrict-Azure-Regions' -Definition '00000000-0000-0000-0000-00000000beef' -Scope $Scope
}

function Get-AzResourceLock {
    [CmdletBinding()]
    param([string]$ResourceGroupName, [Parameter(ValueFromRemainingArguments)]$Rest)
    Write-StubCall -Name 'Get-AzResourceLock'
    if (Test-StubLookupFail) { Write-Error 'stub lookup failure: Get-AzResourceLock'; return }
    if (Test-StubListed -Variable 'SKYCRAFT_STUB_MISSINGRG' -Name $ResourceGroupName) {
        Write-Error "Resource group '$ResourceGroupName' could not be found. (stub)"
        return
    }
    if (Test-StubListed -Variable 'SKYCRAFT_STUB_NOLOCK' -Name $ResourceGroupName) { return }
    $kind = Get-StubLockKind -Name $ResourceGroupName
    if ($kind -eq 'fail') { Write-Error "stub lookup failure: Get-AzResourceLock on $ResourceGroupName"; return }

    $lockName = "lock-no-delete-$(($ResourceGroupName -split '-')[0])"
    $level    = 'CanNotDelete'
    $subscriptionScope = '/subscriptions/00000000-0000-0000-0000-000000000000'
    # ARM ids do not keep one casing: the platform group's lock comes back with 'resourcegroups'
    # in lower case, so the default run proves the scope comparison ignores case.
    $groupSegment = if ($ResourceGroupName -like 'platform-*') { 'resourcegroups' } else { 'resourceGroups' }
    $scope    = "$subscriptionScope/$groupSegment/$ResourceGroupName"
    switch ($kind) {
        'readonly'     { $level = 'ReadOnly' }
        'wrongname'    { $lockName = 'my-lock' }
        'child'        { $scope = "$scope/providers/Microsoft.Storage/storageAccounts/stubstorage" }
        'subscription' { $scope = $subscriptionScope }
    }
    # Shaped like the real cmdlet's output: a generic object whose level and notes sit under
    # Properties, with no top-level Level, and whose LockId says where the lock is applied.
    $lockId = "$scope/providers/Microsoft.Authorization/locks/$lockName"
    [pscustomobject]@{
        Name              = $lockName
        ResourceId        = $lockId
        ResourceGroupName = $ResourceGroupName
        LockId            = $lockId
        Properties        = [pscustomobject]@{ level = $level; notes = 'Cannot delete resource or child resources.' }
    }
}

function Get-AzConsumptionBudget {
    [CmdletBinding()]
    param([Parameter(ValueFromRemainingArguments)]$Rest)
    Write-StubCall -Name 'Get-AzConsumptionBudget'
    switch ($env:SKYCRAFT_STUB_BUDGET) {
        'none' { return }
        'fail' { Write-Error 'stub lookup failure: Get-AzConsumptionBudget'; return }
    }
    [pscustomobject]@{ Name = 'SkyCraft-Monthly-Budget'; Amount = 50; Unit = 'EUR' }
}
'@

    # Runs the real script in a child process with the stubs shadowing the Az commands, and
    # returns the exit code it hands back together with the stub's call log.
    function Invoke-ValidatorScript {
        param(
            [pscustomobject]$Stub,
            [string[]]$MissingResourceGroup = @(),
            [string[]]$NoTags = @(),
            [string[]]$WrongTag = @(),
            [string[]]$MissingPolicy = @(),
            [ValidateSet('bicep', 'portal', 'scripted', 'both')]
            [string]$PolicySet = 'bicep',
            [string[]]$NoLock = @(),
            [hashtable]$LockKind = @{},
            [ValidateSet('present', 'none', 'fail')]
            [string]$Budget = 'present',
            [string]$InheritTag = '',
            [switch]$InheritNoIdentity,
            [switch]$LookupFail,
            [switch]$NoContext
        )

        $logPath = Join-Path $Stub.Directory 'calls.log'
        Remove-Item -LiteralPath $logPath -Force -ErrorAction SilentlyContinue

        $run = Invoke-LabScriptWithStub -Stub $Stub -ScriptPath $script:ScriptPath -Environment @{
            SKYCRAFT_STUB_MISSINGRG     = $MissingResourceGroup -join ','
            SKYCRAFT_STUB_NOTAGS        = $NoTags -join ','
            SKYCRAFT_STUB_WRONGTAG      = $WrongTag -join ','
            SKYCRAFT_STUB_MISSINGPOLICY = $MissingPolicy -join ','
            SKYCRAFT_STUB_POLICYSET     = $PolicySet
            SKYCRAFT_STUB_NOLOCK        = $NoLock -join ','
            SKYCRAFT_STUB_LOCKKIND      = ($LockKind.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join ','
            SKYCRAFT_STUB_BUDGET        = $Budget
            SKYCRAFT_STUB_INHERITTAG    = $InheritTag
            SKYCRAFT_STUB_INHERITIDENTITY = if ($InheritNoIdentity) { 'none' } else { 'system' }
            SKYCRAFT_STUB_LOOKUPFAIL    = if ($LookupFail) { '1' } else { '0' }
            SKYCRAFT_STUB_NOCONTEXT     = if ($NoContext) { '1' } else { '0' }
            SKYCRAFT_STUB_LOG           = $logPath
        }

        $calls = if (Test-Path -LiteralPath $logPath) { @(Get-Content -LiteralPath $logPath) } else { @() }
        return [pscustomobject]@{
            ExitCode  = $run.ExitCode
            Refused   = $run.Refused
            Output    = $run.Output
            Calls     = $calls
            # Check lines only: the summary's own "see the [FAIL] lines" pointer is not a check.
            FailLines = ([regex]::Matches($run.Output, '\[FAIL\]')).Count - ([regex]::Matches($run.Output, 'See the \[FAIL\] lines')).Count
            OkLines   = ([regex]::Matches($run.Output, '\[OK\]')).Count
        }
    }

    $script:Stub    = Initialize-LabScriptStub -Name $script:StubModuleName -Command $script:StubCommands `
        -Body $script:StubBody -RequiredModule $script:RequiredModules
    $script:StubDir = $script:Stub.Directory

    # One invocation per scenario, reused by the assertions below - each child process costs
    # several seconds.
    $script:AllPass       = Invoke-ValidatorScript -Stub $script:Stub
    $script:PolicyMissing = Invoke-ValidatorScript -Stub $script:Stub -MissingPolicy 'Enforce-Project-Tag'
    $script:LockMissing   = Invoke-ValidatorScript -Stub $script:Stub -NoLock 'platform-skycraft-swc-rg'
    $script:WrongTag      = Invoke-ValidatorScript -Stub $script:Stub -WrongTag 'prod-skycraft-swc-rg'
    $script:NoTags        = Invoke-ValidatorScript -Stub $script:Stub -NoTags 'dev-skycraft-swc-rg'
    $script:RgMissing     = Invoke-ValidatorScript -Stub $script:Stub -MissingResourceGroup 'prod-skycraft-swc-rg'
    $script:LookupsFail   = Invoke-ValidatorScript -Stub $script:Stub -LookupFail
    $script:NoContext     = Invoke-ValidatorScript -Stub $script:Stub -NoContext
    $script:NoBudget      = Invoke-ValidatorScript -Stub $script:Stub -Budget 'none'
    $script:BudgetFails   = Invoke-ValidatorScript -Stub $script:Stub -Budget 'fail'
    $script:LockReadOnly  = Invoke-ValidatorScript -Stub $script:Stub -LockKind @{ 'prod-skycraft-swc-rg' = 'readonly' }
    $script:LockWrongName = Invoke-ValidatorScript -Stub $script:Stub -LockKind @{ 'prod-skycraft-swc-rg' = 'wrongname' }
    $script:LockOnChild   = Invoke-ValidatorScript -Stub $script:Stub -LockKind @{ 'platform-skycraft-swc-rg' = 'child' }
    $script:LockOnSub     = Invoke-ValidatorScript -Stub $script:Stub -LockKind @{ 'prod-skycraft-swc-rg' = 'subscription' }
    $script:LockReadFails = Invoke-ValidatorScript -Stub $script:Stub -LockKind @{ 'prod-skycraft-swc-rg' = 'fail' }
    $script:PortalMade    = Invoke-ValidatorScript -Stub $script:Stub -PolicySet 'portal'
    $script:ScriptMade    = Invoke-ValidatorScript -Stub $script:Stub -PolicySet 'scripted'
    $script:TwoSets       = Invoke-ValidatorScript -Stub $script:Stub -PolicySet 'both'
    $script:InheritMissing    = Invoke-ValidatorScript -Stub $script:Stub -MissingPolicy 'Inherit-Project-Tag'
    $script:InheritWrongTag   = Invoke-ValidatorScript -Stub $script:Stub -InheritTag 'Environment'
    $script:InheritNoIdentity = Invoke-ValidatorScript -Stub $script:Stub -PolicySet 'portal' -InheritNoIdentity

    $script:AllRuns = @(
        $script:AllPass, $script:PolicyMissing, $script:LockMissing, $script:WrongTag,
        $script:NoTags, $script:RgMissing, $script:LookupsFail, $script:NoContext, $script:NoBudget, $script:BudgetFails,
        $script:LockReadOnly, $script:LockWrongName, $script:LockOnChild, $script:LockOnSub, $script:LockReadFails,
        $script:PortalMade, $script:ScriptMade, $script:TwoSets, $script:InheritMissing, $script:InheritWrongTag, $script:InheritNoIdentity
    )
}

AfterAll {
    if ($script:StubDir) { Remove-Item -LiteralPath $script:StubDir -Recurse -Force -ErrorAction SilentlyContinue }
}

Describe 'Lab 1.3 Test-Lab.ps1 - test harness' {

    It 'shadows the real Az commands instead of touching a subscription' {
        # Refused is the child exiting 99 before the script ran. Asserted on every scenario: a
        # refusal in one of them is a half-stubbed session, not a scenario-specific failure.
        foreach ($run in $script:AllRuns) {
            $run.Refused | Should -BeFalse -Because "the harness must never fall through to the real Az commands (exit $($run.ExitCode)): $($run.Output)"
        }
    }
}

Describe 'Lab 1.3 Test-Lab.ps1 - failures are counted and set the exit code (#254)' {

    It 'exits 0 and reports 0 failed when every check passes' {
        $run = $script:AllPass
        $run.ExitCode | Should -Be 0 -Because "a passing validation must report success; output was:`n$($run.Output)"
        $run.FailLines | Should -Be 0
        # Three tags, four policy assignments, two locks.
        $run.OkLines | Should -Be 9
        $run.Output | Should -Match 'Passed: 9\b'
        $run.Output | Should -Match 'Failed: 0\b'
        $run.Output | Should -Match 'validation passed'
        $run.Output | Should -Not -Match 'validation failed'
    }

    It 'exits 1 and reports 1 failed when one policy assignment is missing' {
        $run = $script:PolicyMissing
        $run.ExitCode | Should -Be 1 -Because "a missing policy assignment must not look like a passed validation; output was:`n$($run.Output)"
        # The assignment inherited from a management group under the same name, and the unrelated
        # one under a guide display name, are both in the listing and must not stand in for it.
        $run.Output | Should -Match "Policy: Enforce-Project-Tag \[FAIL\] Not found\. Expected an assignment of 'Require a tag and its value on resources' on the subscription itself, named 'Enforce-Project-Tag' \(resource name or display name\), step 1\.3\.8\."
        $run.FailLines | Should -Be 1
        $run.Output | Should -Match 'Passed: 8\b'
        $run.Output | Should -Match 'Failed: 1\b'
        $run.Output | Should -Match 'validation failed: 1 check\(s\) failed'
        $run.Output | Should -Not -Match 'validation passed'
    }

    It 'exits 1 and reports 1 failed when a resource group carries no lock' {
        $run = $script:LockMissing
        $run.ExitCode | Should -Be 1 -Because "output was:`n$($run.Output)"
        $run.Output | Should -Match 'Lock on platform-skycraft-swc-rg \[FAIL\] Not found'
        $run.FailLines | Should -Be 1
        $run.Output | Should -Match 'Failed: 1\b'
    }

    It 'exits 1 and reports 1 failed when a resource group has the wrong Project tag' {
        $run = $script:WrongTag
        $run.ExitCode | Should -Be 1 -Because "output was:`n$($run.Output)"
        $run.Output | Should -Match "Checking prod-skycraft-swc-rg\.\.\. \[FAIL\] Missing or incorrect 'Project' tag"
        $run.FailLines | Should -Be 1
        $run.Output | Should -Match 'Failed: 1\b'
    }

    It 'exits 1 and reports 1 failed when a resource group carries no tags at all' {
        $run = $script:NoTags
        $run.ExitCode | Should -Be 1 -Because "output was:`n$($run.Output)"
        $run.Output | Should -Match 'Checking dev-skycraft-swc-rg\.\.\. \[FAIL\] No tags found'
        $run.FailLines | Should -Be 1
        $run.Output | Should -Match 'Passed: 8\b'
        $run.Output | Should -Match 'Failed: 1\b'
    }

    It 'exits 1 and counts both checks that read a missing resource group, and nothing else' {
        # One group gone, everything else in place - unlike the every-lookup-fails case below.
        # prod carries a tag check and a lock check; both fail, and the other seven still pass.
        $run = $script:RgMissing
        $run.ExitCode | Should -Be 1 -Because "a missing resource group must not look like a passed validation; output was:`n$($run.Output)"
        $run.Output | Should -Match 'Checking prod-skycraft-swc-rg\.\.\. \[FAIL\] Not found or unreadable'
        $run.Output | Should -Match 'Lock on prod-skycraft-swc-rg \[FAIL\] Could not read locks'
        $run.FailLines | Should -Be 2
        $run.OkLines | Should -Be 7
        $run.Output | Should -Match 'Passed: 7\b'
        $run.Output | Should -Match 'Failed: 2\b'
        $run.Output | Should -Match 'validation failed: 2 check\(s\) failed'
    }

    It 'counts every check whose lookup fails with an error as failed, and exits 1' {
        # The policy and lock lookups used -ErrorAction SilentlyContinue: a lookup that failed
        # must be a failed check that says why, never a pass.
        $run = $script:LookupsFail
        $run.ExitCode | Should -Be 1 -Because "output was:`n$($run.Output)"
        $run.OkLines | Should -Be 0
        $run.FailLines | Should -Be 9
        $run.Output | Should -Match 'Passed: 0\b'
        $run.Output | Should -Match 'Failed: 9\b'
        $run.Output | Should -Match 'stub lookup failure: Get-AzPolicyAssignment'
        $run.Output | Should -Match 'stub lookup failure: Get-AzResourceLock'
    }
}

Describe 'Lab 1.3 Test-Lab.ps1 - no one signed in is a failed validation' {

    It 'exits 1 with an [ERROR] and looks nothing up' {
        $run = $script:NoContext
        $run.ExitCode | Should -Be 1 -Because "an unrun validation must not pass; output was:`n$($run.Output)"
        $run.Output | Should -Match '\[ERROR\] Not logged in'
        $run.Output | Should -Not -Match '\[OK\]'
        $run.Calls | Should -BeNullOrEmpty
    }
}

Describe 'Lab 1.3 Test-Lab.ps1 - budgets are a manual check, not counted' {

    It 'lists a budget it finds as [INFO], not as a counted [OK]' {
        $run = $script:AllPass
        $run.Output | Should -Match '\[INFO\] Budget found: SkyCraft-Monthly-Budget'
        $run.Output | Should -Match 'manual check, not counted'
        $run.OkLines | Should -Be 9 -Because 'the nine counted checks are the only [OK] lines'
    }

    It 'exits 0 with the same count when no budget exists' {
        $run = $script:NoBudget
        $run.ExitCode | Should -Be 0 -Because "a missing budget is not a failed check; output was:`n$($run.Output)"
        $run.Output | Should -Match '\[INFO\] No budgets found'
        $run.Output | Should -Match 'Passed: 9\b'
        $run.Output | Should -Match 'Failed: 0\b'
    }

    It 'reports a budget lookup that fails as unreadable, not as found or absent, and exits 0' {
        $run = $script:BudgetFails
        $run.ExitCode | Should -Be 0 -Because "output was:`n$($run.Output)"
        $run.Output | Should -Match '\[INFO\] Budgets could not be read: stub lookup failure'
        $run.Output | Should -Not -Match 'Budget found'
        $run.Output | Should -Not -Match 'No budgets found'
        $run.Output | Should -Match 'Passed: 9\b'
    }
}

Describe 'Lab 1.3 Test-Lab.ps1 - a lock check passes only for the guide''s lock (#258)' {

    It 'passes the guide''s CanNotDelete lock on each group and names it' {
        # The stub carries the level under Properties only, as the real cmdlet does: a check that
        # read a top-level Level would print an empty level here. The platform lock's id spells
        # 'resourcegroups' in lower case, so its [OK] also proves the scope match ignores case.
        $run = $script:AllPass
        $run.Output | Should -Match 'Lock on prod-skycraft-swc-rg : lock-no-delete-prod \(CanNotDelete\) \[OK\]'
        $run.Output | Should -Match 'Lock on platform-skycraft-swc-rg : lock-no-delete-platform \(CanNotDelete\) \[OK\]'
    }

    It 'fails a ReadOnly lock under the guide''s name, and says which level it found' {
        $run = $script:LockReadOnly
        $run.ExitCode | Should -Be 1 -Because "a ReadOnly lock is not the lock step 1.3.11 creates; output was:`n$($run.Output)"
        $run.Output | Should -Match 'Lock on prod-skycraft-swc-rg \[FAIL\] lock-no-delete-prod has level ReadOnly\. Expected lock-no-delete-prod \(CanNotDelete\) on the group, step 1\.3\.11\.'
        $run.FailLines | Should -Be 1
        $run.OkLines | Should -Be 8
        $run.Output | Should -Match 'Failed: 1\b'
    }

    It 'fails a lock under another name, and lists the locks the group carries' {
        # Remove-LabResource.ps1 removes the guide's names only: a lock under any other name
        # would pass the validator and then outlive the cleanup.
        $run = $script:LockWrongName
        $run.ExitCode | Should -Be 1 -Because "output was:`n$($run.Output)"
        $run.Output | Should -Match 'Lock on prod-skycraft-swc-rg \[FAIL\] No lock named lock-no-delete-prod; the group carries: my-lock \(CanNotDelete\)\.'
        $run.FailLines | Should -Be 1
        $run.OkLines | Should -Be 8
        $run.Output | Should -Match 'Failed: 1\b'
    }

    It 'does not count a lock on a resource inside the group, and says where it found it' {
        # Get-AzResourceLock -ResourceGroupName returns locks on child resources too; such a lock
        # does not stop anyone deleting the group.
        $run = $script:LockOnChild
        $run.ExitCode | Should -Be 1 -Because "output was:`n$($run.Output)"
        $run.Output | Should -Match 'Lock on platform-skycraft-swc-rg \[FAIL\] Not found on the group itself; locks elsewhere do not count: lock-no-delete-platform \(CanNotDelete\) at /subscriptions/[^ ]+/resourceGroups/platform-skycraft-swc-rg/providers/Microsoft\.Storage/storageAccounts/stubstorage\.'
        $run.Output | Should -Match 'step 1\.3\.13\.'
        $run.FailLines | Should -Be 1
        $run.OkLines | Should -Be 8
        $run.Output | Should -Match 'Failed: 1\b'
    }

    It 'does not count a lock on the subscription above the group' {
        # In a shared subscription this is the likeliest false pass: Get-AzResourceLock
        # -ResourceGroupName also returns locks inherited from the subscription.
        $run = $script:LockOnSub
        $run.ExitCode | Should -Be 1 -Because "output was:`n$($run.Output)"
        $run.Output | Should -Match 'Lock on prod-skycraft-swc-rg \[FAIL\] Not found on the group itself; locks elsewhere do not count: lock-no-delete-prod \(CanNotDelete\) at /subscriptions/00000000-0000-0000-0000-000000000000\. Expected'
        $run.FailLines | Should -Be 1
        $run.OkLines | Should -Be 8
        $run.Output | Should -Match 'Failed: 1\b'
    }

    It 'counts a lock lookup that fails as a failed check, not as a missing lock' {
        $run = $script:LockReadFails
        $run.ExitCode | Should -Be 1 -Because "output was:`n$($run.Output)"
        $run.Output | Should -Match 'Lock on prod-skycraft-swc-rg \[FAIL\] Could not read locks: stub lookup failure: Get-AzResourceLock on prod-skycraft-swc-rg'
        $run.Output | Should -Not -Match 'Lock on prod-skycraft-swc-rg \[FAIL\] Not found'
        $run.FailLines | Should -Be 1
        $run.OkLines | Should -Be 8
        $run.Output | Should -Match 'Failed: 1\b'
    }
}

Describe 'Lab 1.3 Test-Lab.ps1 - finds the policy assignments whichever path made them (#330)' {

    It 'passes the Bicep-made assignments, found by their fixed names' {
        $run = $script:AllPass
        $run.Output | Should -Match "Policy: Require-Environment-Tag-RG : 'Require Environment Tag on Resource Groups' \(name Require-Environment-Tag-RG\) \[OK\]"
        $run.Output | Should -Match "Policy: Restrict-Azure-Regions : 'Restrict to Allowed Regions' \(name Restrict-Azure-Regions\) \[OK\]"
    }

    It 'passes the Portal-made assignments, found by the display names the learner typed' {
        # The Portal's Assignment name sets only the display name; the resource name is generated.
        $run = $script:PortalMade
        $run.ExitCode | Should -Be 0 -Because "a learner who took the Portal path built what the guide asks for; output was:`n$($run.Output)"
        $run.Output | Should -Match "Policy: Require-Environment-Tag-RG : 'Require-Environment-Tag-RG' \(name aaaaaaaaaaaaaaaaaaaaaaa1\) \[OK\]"
        $run.Output | Should -Match "Policy: Enforce-Project-Tag : 'Enforce-Project-Tag' \(name aaaaaaaaaaaaaaaaaaaaaaa2\) \[OK\]"
        $run.Output | Should -Match "Policy: Restrict-Azure-Regions : 'Restrict-Azure-Regions' \(name aaaaaaaaaaaaaaaaaaaaaaa3\) \[OK\]"
        $run.Output | Should -Match "Policy: Inherit-Project-Tag : 'Inherit-Project-Tag' \(name aaaaaaaaaaaaaaaaaaaaaaa4\) \[OK\]"
        $run.Output | Should -Match 'Passed: 9\b'
    }

    It 'passes the assignments the Bicep and script paths make since #406: fixed names, the guide''s display names' {
        $run = $script:ScriptMade
        $run.ExitCode | Should -Be 0 -Because "output was:`n$($run.Output)"
        $run.Output | Should -Match "Policy: Enforce-Project-Tag : 'Enforce-Project-Tag' \(name Enforce-Project-Tag\) \[OK\]"
        $run.Output | Should -Match "Policy: Inherit-Project-Tag : 'Inherit-Project-Tag' \(name Inherit-Project-Tag\) \[OK\]"
        $run.Output | Should -Match 'Passed: 9\b'
    }

    It 'lists the subscription''s assignments once, rather than reading each by name' {
        @($script:AllPass.Calls | Where-Object { $_ -eq 'Get-AzPolicyAssignment' }).Count | Should -Be 1
    }

    It 'fails each assignment made twice, and names both, because the cleanup removes neither' {
        $run = $script:TwoSets
        $run.ExitCode | Should -Be 1 -Because "output was:`n$($run.Output)"
        $run.Output | Should -Match "Policy: Enforce-Project-Tag \[FAIL\] 2 assignments match: 'Enforce Project Tag Value' \(name Enforce-Project-Tag\), 'Enforce-Project-Tag' \(name aaaaaaaaaaaaaaaaaaaaaaa2\)\. Keep one and delete the others"
        $run.FailLines | Should -Be 4
        $run.OkLines | Should -Be 5
        $run.Output | Should -Match 'Failed: 4\b'
    }
}

Describe 'Lab 1.3 Test-Lab.ps1 - checks the Modify assignment Inherit-Project-Tag (#350)' {

    It 'passes the Bicep-made Inherit-Project-Tag, with tagName Project and a system-assigned identity' {
        $script:AllPass.Output | Should -Match "Policy: Inherit-Project-Tag : 'Inherit Project Tag from Resource Group' \(name Inherit-Project-Tag\) \[OK\]"
    }

    It 'does not count Inherit-Project-Tag as a second Enforce-Project-Tag' {
        # Both carry the Project tag; the definition tells them apart, so neither check sees two.
        $script:AllPass.Output | Should -Match "Policy: Enforce-Project-Tag : 'Enforce Project Tag Value' \(name Enforce-Project-Tag\) \[OK\]"
        $script:AllPass.Output | Should -Not -Match 'assignments match'
    }

    It 'fails when Inherit-Project-Tag is missing, and names its definition and step' {
        $run = $script:InheritMissing
        $run.ExitCode | Should -Be 1 -Because "output was:`n$($run.Output)"
        $run.Output | Should -Match "Policy: Inherit-Project-Tag \[FAIL\] Not found\. Expected an assignment of 'Inherit a tag from the resource group if missing' on the subscription itself, named 'Inherit-Project-Tag' \(resource name or display name\), step 1\.3\.8\."
        $run.FailLines | Should -Be 1
        $run.OkLines | Should -Be 8
        $run.Output | Should -Match 'Failed: 1\b'
    }

    It 'fails an Inherit-Project-Tag that inherits another tag' {
        $run = $script:InheritWrongTag
        $run.ExitCode | Should -Be 1 -Because "output was:`n$($run.Output)"
        $run.Output | Should -Match "Policy: Inherit-Project-Tag : 'Inherit Project Tag from Resource Group' \(name Inherit-Project-Tag\) \[FAIL\] parameter tagName is 'Environment', expected 'Project'\. See step 1\.3\.8\."
        $run.FailLines | Should -Be 1
        $run.OkLines | Should -Be 8
    }

    It 'fails an Inherit-Project-Tag without a managed identity' {
        $run = $script:InheritNoIdentity
        $run.ExitCode | Should -Be 1 -Because "output was:`n$($run.Output)"
        $run.Output | Should -Match "Policy: Inherit-Project-Tag : 'Inherit-Project-Tag' \(name aaaaaaaaaaaaaaaaaaaaaaa4\) \[FAIL\] it has no managed identity, expected a system-assigned managed identity \(a Modify policy needs one\)\. See step 1\.3\.8\."
        $run.FailLines | Should -Be 1
        $run.OkLines | Should -Be 8
    }
}
