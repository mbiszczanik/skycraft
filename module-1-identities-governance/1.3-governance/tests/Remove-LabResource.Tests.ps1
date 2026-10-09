<#
.SYNOPSIS
    Pester 5 tests for the Lab 1.3 cleanup: what it removes, and when it exits 1.

.DESCRIPTION
    Regression cover for issue #252. The cleanup removed only the two locks and the three policy
    assignments, so the two budgets, the Advisor alert and its action group stayed behind, and it
    looked everything up with -ErrorAction SilentlyContinue and exited 0 even when a removal
    failed. These tests run the real Remove-LabResource.ps1 in a child pwsh process against a
    generated stub of the Az commands it calls, and assert the observable contract:

      1. Every object the guide creates is removed when it is present: the locks, the policy
         assignments, the subscription and resource group budgets, the Advisor alert, and its
         action group (under the current name, and the one used before #225). An unrelated
         action group in the same resource group is left alone.
      2. An object that is absent - an empty listing, a policy assignment reported as not
         found, or a resource group that is gone - is not a failure: the run exits 0.
      3. A lookup that fails with an error is an [ERROR], counted, and the run exits 1 without
         touching the object it could not see. The stub reports the failure with Write-Error, as
         the Az getters do, so a script that passes -ErrorAction SilentlyContinue swallows it.
      4. A removal that fails is an [ERROR], counted, and the later steps still run: exit 1.
      5. -WhatIf removes nothing and does not wait for lock propagation.
      6. Which errors mean "not found" is pinned by lifting Test-LabNotFoundError out of the
         script with the parser and running it on one error per shape.

    Scope limit, as in the Lab 5.2 suite: the child is launched with -Command, so these tests
    prove the failure counter reaches `exit`, not that `pwsh -File` carries the code out of the
    process. That half is issue #104's guard ($Host.SetShouldExit before every non-zero exit),
    enforced repo-wide by tests/Exit-Code-Propagation.Tests.ps1.

    No subscription is needed, and none is used. The script runs through
    tests/Support/LabScriptStub.psm1 (issue #112), which imports the real modules first, the stub
    module last, and aborts the child with exit 99 unless every stubbed command resolves to the
    stub. Start-Sleep is stubbed too, so the 45-second lock propagation wait costs nothing.

.EXAMPLE
    Invoke-Pester -Path .\Remove-LabResource.Tests.ps1

.NOTES
    Project: SkyCraft
    Lab: 1.3 - Governance
#>

#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..' '..' '..' 'tests' 'Support' 'LabScriptStub.psm1') -Force

    $script:ScriptPath     = (Resolve-Path (Join-Path $PSScriptRoot '..' 'scripts' 'Remove-LabResource.ps1')).Path
    $script:StubModuleName = 'SkyCraftLab13CleanupStub'
    # Exactly the script's '#Requires -Modules' line: these are imported for real before the stub.
    $script:RequiredModules = @('Az.Accounts', 'Az.Resources', 'Az.Billing', 'Az.Monitor')

    $script:StubCommands = @(
        'Get-AzContext'
        'Get-AzResourceLock'
        'Remove-AzResourceLock'
        'Get-AzPolicyAssignment'
        'Remove-AzPolicyAssignment'
        'Get-AzConsumptionBudget'
        'Remove-AzConsumptionBudget'
        'Get-AzActivityLogAlert'
        'Remove-AzActivityLogAlert'
        'Get-AzActionGroup'
        'Remove-AzActionGroup'
        'Start-Sleep'
    )

    # Every command the script calls, recording its own invocation. By default the subscription
    # holds everything the guide creates, plus an unrelated action group in prod-skycraft-swc-rg.
    # Environment variables change that, so one generated module serves every scenario:
    #   SKYCRAFT_STUB_EMPTY   '1' leaves nothing to find: the listings come back empty and
    #                         Get-AzPolicyAssignment reports PolicyAssignmentNotFound, as the
    #                         real cmdlet does for a name that is not assigned
    #   SKYCRAFT_STUB_LOOKUP  '<lookup>=<kind>,...' makes one lookup fail (denied, throttled) or
    #                         report its resource group gone (rgnotfound)
    #   SKYCRAFT_STUB_FAIL    '<Remove-command>:<name>,...' makes one removal throw
    # A lookup is named after its command and what it reads: 'Get-AzResourceLock:<rg>',
    # 'Get-AzPolicyAssignment:<name>', 'Get-AzConsumptionBudget:<rg or subscription>',
    # 'Get-AzActivityLogAlert:<rg>', 'Get-AzActionGroup:<rg>'. A removal is logged both bare and
    # with the object's name, so the assertions can be generic or precise.
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
        'rgnotfound' {
            Write-Error -ErrorId 'ResourceGroupNotFound' -Message "Resource group 'prod-skycraft-swc-rg' could not be found."
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

function Get-AzResourceLock {
    [CmdletBinding()]
    param([string]$ResourceGroupName, [Parameter(ValueFromRemainingArguments)]$Rest)
    if (Invoke-StubLookup -Name "Get-AzResourceLock:$ResourceGroupName") { return }
    if (Test-StubEmpty) { return }
    $suffix = ($ResourceGroupName -split '-')[0]
    [pscustomobject]@{ Name = "lock-no-delete-$suffix"; ResourceGroupName = $ResourceGroupName }
}

function Remove-AzResourceLock {
    [CmdletBinding()]
    param([string]$ResourceGroupName, [string]$LockName, [switch]$Force)
    Invoke-StubRemoval -Command 'Remove-AzResourceLock' -Name $LockName
}

function Get-AzPolicyAssignment {
    [CmdletBinding()]
    param([string]$Name, [string]$Scope, [Parameter(ValueFromRemainingArguments)]$Rest)
    if (Invoke-StubLookup -Name "Get-AzPolicyAssignment:$Name") { return }
    if (Test-StubEmpty) {
        Write-Error -ErrorId 'PolicyAssignmentNotFound' -Message "PolicyAssignmentNotFound : The policy assignment '$Name' is not found."
        return
    }
    [pscustomobject]@{ Name = $Name; Scope = $Scope }
}

function Remove-AzPolicyAssignment {
    [CmdletBinding()]
    param([string]$Name, [string]$Scope)
    Invoke-StubRemoval -Command 'Remove-AzPolicyAssignment' -Name $Name
}

function Get-AzConsumptionBudget {
    [CmdletBinding()]
    param([string]$ResourceGroupName, [string]$Name)
    $scope = if ($ResourceGroupName) { $ResourceGroupName } else { 'subscription' }
    if (Invoke-StubLookup -Name "Get-AzConsumptionBudget:$scope") { return }
    if (Test-StubEmpty) { return }
    if ($ResourceGroupName) {
        [pscustomobject]@{ Name = 'SkyCraft-Prod-Monthly' }
    } else {
        # A subscription listing can hold budgets this lab did not create.
        [pscustomobject]@{ Name = 'SkyCraft-Monthly-Budget' }
        [pscustomobject]@{ Name = 'Someone-Elses-Budget' }
    }
}

function Remove-AzConsumptionBudget {
    [CmdletBinding()]
    param([string]$Name, [string]$ResourceGroupName)
    $scope = if ($ResourceGroupName) { $ResourceGroupName } else { 'subscription' }
    Write-StubCall -Name "Remove-AzConsumptionBudget@${scope}:$Name"
    Invoke-StubRemoval -Command 'Remove-AzConsumptionBudget' -Name $Name
}

function Get-AzActivityLogAlert {
    [CmdletBinding()]
    param([string]$ResourceGroupName)
    if (Invoke-StubLookup -Name "Get-AzActivityLogAlert:$ResourceGroupName") { return }
    if (Test-StubEmpty) { return }
    [pscustomobject]@{ Name = 'Advisor-Cost-Recommendations' }
}

function Remove-AzActivityLogAlert {
    [CmdletBinding()]
    param([string]$ResourceGroupName, [string]$Name)
    Invoke-StubRemoval -Command 'Remove-AzActivityLogAlert' -Name $Name
}

function Get-AzActionGroup {
    [CmdletBinding()]
    param([string]$ResourceGroupName)
    if (Invoke-StubLookup -Name "Get-AzActionGroup:$ResourceGroupName") { return }
    if (Test-StubEmpty) { return }
    [pscustomobject]@{ Name = 'skycraft-advisor-ag' }
    # The name step 1.3.21 gave the action group before #225.
    [pscustomobject]@{ Name = 'prod-skycraft-swc-rg' }
    [pscustomobject]@{ Name = 'unrelated-ag' }
}

function Remove-AzActionGroup {
    [CmdletBinding()]
    param([string]$ResourceGroupName, [string]$Name)
    Invoke-StubRemoval -Command 'Remove-AzActionGroup' -Name $Name
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

    # One invocation per scenario, reused by the assertions below - each child process costs
    # several seconds.
    $script:Clean   = Invoke-CleanupScript -Stub $script:Stub
    $script:Nothing = Invoke-CleanupScript -Stub $script:Stub -Empty
    $script:WhatIf  = Invoke-CleanupScript -Stub $script:Stub -ArgumentList '-WhatIf'
    # prod-skycraft-swc-rg is gone (a later lab's cleanup deleted it); the rest is in place.
    $script:ProdGone = Invoke-CleanupScript -Stub $script:Stub -Lookup @(
        'Get-AzResourceLock:prod-skycraft-swc-rg=rgnotfound'
        'Get-AzConsumptionBudget:prod-skycraft-swc-rg=rgnotfound'
        'Get-AzActivityLogAlert:prod-skycraft-swc-rg=rgnotfound'
        'Get-AzActionGroup:prod-skycraft-swc-rg=rgnotfound'
    )
    $script:NewLookupsFail = Invoke-CleanupScript -Stub $script:Stub -Lookup @(
        'Get-AzConsumptionBudget:subscription=denied'
        'Get-AzConsumptionBudget:prod-skycraft-swc-rg=throttled'
        'Get-AzActivityLogAlert:prod-skycraft-swc-rg=denied'
        'Get-AzActionGroup:prod-skycraft-swc-rg=throttled'
    )
    $script:OldLookupsFail = Invoke-CleanupScript -Stub $script:Stub -Lookup @(
        'Get-AzResourceLock:prod-skycraft-swc-rg=denied'
        'Get-AzPolicyAssignment:Enforce-Project-Tag=throttled'
    )
    $script:NewRemovalsFail = Invoke-CleanupScript -Stub $script:Stub -Fail @(
        'Remove-AzConsumptionBudget:SkyCraft-Monthly-Budget'
        'Remove-AzActivityLogAlert:Advisor-Cost-Recommendations'
        'Remove-AzActionGroup:skycraft-advisor-ag'
    )
    $script:OldRemovalsFail = Invoke-CleanupScript -Stub $script:Stub -Fail @(
        'Remove-AzResourceLock:lock-no-delete-prod'
        'Remove-AzPolicyAssignment:Restrict-Azure-Regions'
    )

    $script:AllRuns = @(
        $script:Clean, $script:Nothing, $script:WhatIf, $script:ProdGone, $script:NewLookupsFail,
        $script:OldLookupsFail, $script:NewRemovalsFail, $script:OldRemovalsFail
    )
}

AfterAll {
    if ($script:StubDir) { Remove-Item -LiteralPath $script:StubDir -Recurse -Force -ErrorAction SilentlyContinue }
}

Describe 'Lab 1.3 Remove-LabResource.ps1 - test harness' {

    It 'shadows the real Az commands instead of touching a subscription' {
        # Refused is the child exiting 99 before the script ran. Asserted on every scenario: a
        # refusal in one of them is a half-stubbed session, not a scenario-specific failure.
        foreach ($run in $script:AllRuns) {
            $run.Refused | Should -BeFalse -Because "the harness must never fall through to the real Az commands (exit $($run.ExitCode)): $($run.Output)"
        }
    }
}

Describe 'Lab 1.3 Remove-LabResource.ps1 - removes everything the guide creates (#252)' {

    It 'exits 0 when every object is found and removed' {
        $script:Clean.ExitCode | Should -Be 0 -Because "a clean teardown must report success; output was:`n$($script:Clean.Output)"
        $script:Clean.Output   | Should -Match 'Cleanup complete'
        $script:Clean.Output   | Should -Not -Match '\[ERROR\]'
    }

    It 'still removes both locks and all three policy assignments' {
        foreach ($call in 'Remove-AzResourceLock:lock-no-delete-prod', 'Remove-AzResourceLock:lock-no-delete-platform',
                'Remove-AzPolicyAssignment:Require-Environment-Tag-RG', 'Remove-AzPolicyAssignment:Enforce-Project-Tag',
                'Remove-AzPolicyAssignment:Restrict-Azure-Regions') {
            $script:Clean.Calls | Should -Contain $call
        }
    }

    It 'removes the subscription budget from the subscription (step 1.3.14)' {
        $script:Clean.Calls  | Should -Contain 'Remove-AzConsumptionBudget@subscription:SkyCraft-Monthly-Budget'
        $script:Clean.Output | Should -Match '\[SUCCESS\] Removed budget: SkyCraft-Monthly-Budget'
    }

    It 'removes the resource group budget from prod-skycraft-swc-rg (step 1.3.16)' {
        $script:Clean.Calls  | Should -Contain 'Remove-AzConsumptionBudget@prod-skycraft-swc-rg:SkyCraft-Prod-Monthly'
        $script:Clean.Output | Should -Match '\[SUCCESS\] Removed budget: SkyCraft-Prod-Monthly'
    }

    It 'leaves a budget the lab did not create alone' {
        $script:Clean.Calls | Should -Not -Contain 'Remove-AzConsumptionBudget:Someone-Elses-Budget'
    }

    It 'removes the Advisor alert (step 1.3.21)' {
        $script:Clean.Calls  | Should -Contain 'Remove-AzActivityLogAlert:Advisor-Cost-Recommendations'
        $script:Clean.Output | Should -Match '\[SUCCESS\] Removed Advisor alert: Advisor-Cost-Recommendations'
    }

    It 'removes the action group, under its current name and the one used before #225' {
        $script:Clean.Calls  | Should -Contain 'Remove-AzActionGroup:skycraft-advisor-ag'
        $script:Clean.Calls  | Should -Contain 'Remove-AzActionGroup:prod-skycraft-swc-rg'
        $script:Clean.Output | Should -Match '\[SUCCESS\] Removed action group: skycraft-advisor-ag'
    }

    It 'leaves an unrelated action group in the same resource group alone' {
        $script:Clean.Calls | Should -Not -Contain 'Remove-AzActionGroup:unrelated-ag'
    }

    It 'removes the Advisor alert before its action group, and both after the locks' {
        $calls = $script:Clean.Calls
        $lock  = [array]::LastIndexOf($calls, 'Remove-AzResourceLock:lock-no-delete-prod')
        $sleep = [array]::IndexOf($calls, 'Start-Sleep:45')
        $alert = [array]::IndexOf($calls, 'Remove-AzActivityLogAlert:Advisor-Cost-Recommendations')
        $group = [array]::IndexOf($calls, 'Remove-AzActionGroup:skycraft-advisor-ag')
        $rgBudget = [array]::IndexOf($calls, 'Remove-AzConsumptionBudget:SkyCraft-Prod-Monthly')
        $sleep    | Should -BeGreaterThan $lock
        $rgBudget | Should -BeGreaterThan $sleep
        $alert    | Should -BeGreaterThan $sleep
        $group    | Should -BeGreaterThan $alert
    }
}

Describe 'Lab 1.3 Remove-LabResource.ps1 - an absent object is not a failure (#252)' {

    It 'exits 0 and removes nothing when nothing is there' {
        $run = $script:Nothing
        $run.ExitCode | Should -Be 0 -Because "nothing to remove is a clean teardown; output was:`n$($run.Output)"
        $run.Output | Should -Not -Match '\[ERROR\]'
        $run.Output | Should -Match 'Cleanup complete'
        @($run.Calls | Where-Object { $_ -match '^Remove-' }) | Should -BeNullOrEmpty
    }

    It 'reports each absent object as not found' {
        $run = $script:Nothing
        $run.Output | Should -Match 'Lock lock-no-delete-prod not found'
        $run.Output | Should -Match 'Policy Enforce-Project-Tag not found'
        $run.Output | Should -Match 'Budget SkyCraft-Monthly-Budget not found'
        $run.Output | Should -Match 'Budget SkyCraft-Prod-Monthly not found'
        $run.Output | Should -Match 'Advisor alert Advisor-Cost-Recommendations not found'
        $run.Output | Should -Match 'Action group skycraft-advisor-ag not found'
    }

    It 'does not wait for lock propagation when no lock was removed' {
        $script:Nothing.Calls | Should -Not -Contain 'Start-Sleep:45'
        $script:Clean.Calls   | Should -Contain 'Start-Sleep:45'
    }

    It 'exits 0 when prod-skycraft-swc-rg is already gone, and still cleans up the rest' {
        $run = $script:ProdGone
        $run.ExitCode | Should -Be 0 -Because "a group that is gone holds nothing to remove; output was:`n$($run.Output)"
        $run.Output | Should -Not -Match '\[ERROR\]'
        $run.Calls  | Should -Not -Contain 'Remove-AzResourceLock:lock-no-delete-prod'
        $run.Calls  | Should -Not -Contain 'Remove-AzConsumptionBudget:SkyCraft-Prod-Monthly'
        $run.Calls  | Should -Not -Contain 'Remove-AzActivityLogAlert'
        $run.Calls  | Should -Not -Contain 'Remove-AzActionGroup'
        $run.Calls  | Should -Contain 'Remove-AzResourceLock:lock-no-delete-platform'
        $run.Calls  | Should -Contain 'Remove-AzConsumptionBudget:SkyCraft-Monthly-Budget'
    }
}

Describe 'Lab 1.3 Remove-LabResource.ps1 - a failed lookup is not "absent" (#252)' {

    It 'exits 1 and counts each budget, alert and action group lookup that failed' {
        $run = $script:NewLookupsFail
        $run.ExitCode | Should -Be 1 -Because "an object that may still exist must not look like a clean cleanup; output was:`n$($run.Output)"
        $run.Output | Should -Match '\[ERROR\] Could not look up budget SkyCraft-Monthly-Budget on the subscription[^\r\n]*does not have authorization'
        $run.Output | Should -Match '\[ERROR\] Could not look up budget SkyCraft-Prod-Monthly on prod-skycraft-swc-rg[^\r\n]*requests exceeded the limit'
        $run.Output | Should -Match '\[ERROR\] Could not look up Advisor alert Advisor-Cost-Recommendations in prod-skycraft-swc-rg'
        $run.Output | Should -Match '\[ERROR\] Could not look up the action groups in prod-skycraft-swc-rg'
        $run.Output | Should -Match 'Cleanup finished with 4 failure\(s\)'
        $run.Output | Should -Not -Match 'Cleanup complete'
        $run.Output | Should -Not -Match 'Budget SkyCraft-Monthly-Budget not found'
    }

    It 'removes nothing it could not look up, and still runs every other step' {
        $run = $script:NewLookupsFail
        $run.Calls | Should -Not -Contain 'Remove-AzConsumptionBudget'
        $run.Calls | Should -Not -Contain 'Remove-AzActivityLogAlert'
        $run.Calls | Should -Not -Contain 'Remove-AzActionGroup'
        $run.Calls | Should -Contain 'Remove-AzResourceLock:lock-no-delete-prod'
        $run.Calls | Should -Contain 'Remove-AzPolicyAssignment:Restrict-Azure-Regions'
    }

    It 'counts a lock or policy lookup that failed, which it used to read as "not found"' {
        $run = $script:OldLookupsFail
        $run.ExitCode | Should -Be 1 -Because "output was:`n$($run.Output)"
        $run.Output | Should -Match '\[ERROR\] Could not look up lock lock-no-delete-prod on prod-skycraft-swc-rg'
        $run.Output | Should -Match '\[ERROR\] Could not look up policy assignment Enforce-Project-Tag'
        $run.Output | Should -Not -Match 'Lock lock-no-delete-prod not found'
        $run.Output | Should -Match 'Cleanup finished with 2 failure\(s\)'
        $run.Calls  | Should -Not -Contain 'Remove-AzResourceLock:lock-no-delete-prod'
        $run.Calls  | Should -Not -Contain 'Remove-AzPolicyAssignment:Enforce-Project-Tag'
        $run.Calls  | Should -Contain 'Remove-AzActionGroup:skycraft-advisor-ag'
    }
}

Describe 'Lab 1.3 Remove-LabResource.ps1 - a failed removal is counted (#252)' {

    It 'exits 1 and counts each budget, alert and action group it could not remove' {
        $run = $script:NewRemovalsFail
        $run.ExitCode | Should -Be 1 -Because "a stuck object must not look like a clean cleanup; output was:`n$($run.Output)"
        $run.Output | Should -Match '\[ERROR\] Failed to remove budget SkyCraft-Monthly-Budget'
        $run.Output | Should -Match '\[ERROR\] Failed to remove Advisor alert Advisor-Cost-Recommendations'
        $run.Output | Should -Match '\[ERROR\] Failed to remove action group skycraft-advisor-ag'
        $run.Output | Should -Match 'Cleanup finished with 3 failure\(s\)'
        $run.Output | Should -Not -Match 'Cleanup complete'
    }

    It 'keeps going after a failed removal' {
        $run = $script:NewRemovalsFail
        $run.Calls | Should -Contain 'Remove-AzConsumptionBudget:SkyCraft-Prod-Monthly'
        $run.Calls | Should -Contain 'Remove-AzActionGroup:skycraft-advisor-ag'
        $run.Calls | Should -Contain 'Remove-AzActionGroup:prod-skycraft-swc-rg'
    }

    It 'exits 1 when a lock or a policy assignment cannot be removed, which it used to report as success' {
        $run = $script:OldRemovalsFail
        $run.ExitCode | Should -Be 1 -Because "output was:`n$($run.Output)"
        $run.Output | Should -Match '\[ERROR\] Failed to remove lock lock-no-delete-prod'
        $run.Output | Should -Match '\[ERROR\] Failed to remove policy Restrict-Azure-Regions'
        $run.Output | Should -Match 'Cleanup finished with 2 failure\(s\)'
        $run.Calls  | Should -Contain 'Remove-AzActivityLogAlert:Advisor-Cost-Recommendations'
    }
}

Describe 'Lab 1.3 Remove-LabResource.ps1 - -WhatIf' {

    It 'looks everything up, removes nothing and does not wait' {
        $run = $script:WhatIf
        $run.ExitCode | Should -Be 0 -Because "output was:`n$($run.Output)"
        @($run.Calls | Where-Object { $_ -match '^(Remove-|Start-Sleep)' }) | Should -BeNullOrEmpty
        $run.Calls  | Should -Contain 'Get-AzConsumptionBudget:subscription'
        $run.Calls  | Should -Contain 'Get-AzActionGroup:prod-skycraft-swc-rg'
        $run.Output | Should -Match 'What if: .*SkyCraft-Monthly-Budget'
        $run.Output | Should -Match 'What if: .*Advisor-Cost-Recommendations'
    }
}

Describe 'Lab 1.3 Remove-LabResource.ps1 - which lookup errors mean "not found"' {

    BeforeAll {
        # Lift the helpers with the parser: the script body never runs, so nothing is looked up.
        $parseError = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($script:ScriptPath, [ref]$null, [ref]$parseError)
        if ($parseError) { throw "Remove-LabResource.ps1 does not parse: $($parseError[0].Message)" }
        $script:LiftedName = @()
        foreach ($function in $ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $false)) {
            . ([scriptblock]::Create($function.Extent.Text))
            $script:LiftedName += $function.Name
        }

        # The shape of the SDK exceptions the getters raise: the ARM error code in Body and the
        # status in Response (Get-AzConsumptionBudget), ResponseStatusCode (generated cmdlets) or
        # HttpStatus (Get-AzResourceLock).
        if (-not ('SkyCraftLab13StubAzureException' -as [type])) {
            Add-Type -TypeDefinition @'
public class SkyCraftLab13StubAzureException : System.Exception
{
    public SkyCraftLab13StubAzureException(string message) : base(message) { }
    public object Body { get; set; }
    public object Response { get; set; }
    public object ResponseStatusCode { get; set; }
    public object HttpStatus { get; set; }
}
'@
        }

        function Get-LookupErrorFixture {
            param(
                [string]$Message = 'Operation failed.',
                [string]$ErrorId = 'StubError',
                [string]$Code,
                [object]$StatusCode,
                [object]$ResponseStatusCode,
                [object]$HttpStatus
            )
            $exception = [SkyCraftLab13StubAzureException]::new($Message)
            if ($Code) { $exception.Body = [pscustomobject]@{ Code = $Code } }
            if ($null -ne $StatusCode) { $exception.Response = [pscustomobject]@{ StatusCode = $StatusCode } }
            if ($null -ne $ResponseStatusCode) { $exception.ResponseStatusCode = $ResponseStatusCode }
            if ($null -ne $HttpStatus) { $exception.HttpStatus = $HttpStatus }
            [System.Management.Automation.ErrorRecord]::new($exception, $ErrorId, 'InvalidOperation', $null)
        }
    }

    It 'lifts Test-LabNotFoundError and Invoke-LabLookup out of the script' {
        $script:LiftedName | Should -Contain 'Test-LabNotFoundError'
        $script:LiftedName | Should -Contain 'Invoke-LabLookup'
    }

    It 'reads <Shape> as not found' -ForEach @(
        @{ Shape  = 'a policy assignment that is not assigned (PolicyAssignmentNotFound)'
           Record = { Get-LookupErrorFixture -ErrorId 'PolicyAssignmentNotFound,Get-AzPolicyAssignment' -Message "The policy assignment 'Enforce-Project-Tag' is not found." } }
        @{ Shape  = 'the PolicyAssignmentNotFound code in the message only'
           Record = { Get-LookupErrorFixture -Message "PolicyAssignmentNotFound : The policy assignment 'Enforce-Project-Tag' is not found." } }
        @{ Shape  = 'a resource group that is gone (ResourceGroupNotFound message)'
           Record = { Get-LookupErrorFixture -Message "Resource group 'prod-skycraft-swc-rg' could not be found." } }
        @{ Shape  = 'a 404 HttpStatus (Get-AzResourceLock)'
           Record = { Get-LookupErrorFixture -HttpStatus ([System.Net.HttpStatusCode]::NotFound) } }
        @{ Shape  = 'a 404 on the response with no error body (Get-AzConsumptionBudget)'
           Record = { Get-LookupErrorFixture -StatusCode ([System.Net.HttpStatusCode]::NotFound) -Message "Operation returned an invalid status code 'NotFound'" } }
        @{ Shape  = 'a 404 on a generated cmdlet RestException (Get-AzActionGroup)'
           Record = { Get-LookupErrorFixture -ResponseStatusCode ([System.Net.HttpStatusCode]::NotFound) } }
    ) {
        Test-LabNotFoundError -ErrorRecord (& $Record) | Should -BeTrue
    }

    It 'reads <Shape> as a failed lookup' -ForEach @(
        @{ Shape  = 'a 403 AuthorizationFailed'
           Record = { Get-LookupErrorFixture -ErrorId 'AuthorizationFailed' -Code 'AuthorizationFailed' -StatusCode ([System.Net.HttpStatusCode]::Forbidden) -Message "The client 'stub' does not have authorization to perform action 'Microsoft.Consumption/budgets/read' over scope '/subscriptions/0' or the scope is invalid." } }
        @{ Shape  = 'a 403 HttpStatus (Get-AzResourceLock)'
           Record = { Get-LookupErrorFixture -HttpStatus ([System.Net.HttpStatusCode]::Forbidden) } }
        @{ Shape  = 'a 429 throttling response'
           Record = { Get-LookupErrorFixture -ErrorId 'TooManyRequests' -ResponseStatusCode 429 -Message "Number of 'read' requests exceeded. Please try again after '17' seconds." } }
        @{ Shape  = 'a transient transport error'
           Record = { Get-LookupErrorFixture -Message 'An error occurred while sending the request.' } }
        @{ Shape  = 'a missing subscription, although ARM answers it with 404'
           Record = { Get-LookupErrorFixture -Code 'SubscriptionNotFound' -StatusCode ([System.Net.HttpStatusCode]::NotFound) -Message "The subscription '00000000-0000-0000-0000-000000000000' could not be found." } }
    ) {
        Test-LabNotFoundError -ErrorRecord (& $Record) | Should -BeFalse
    }
}
