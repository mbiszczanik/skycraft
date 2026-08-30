<#
.SYNOPSIS
    Pester 5 tests for the lab cycle orchestrator and its teardown.

.DESCRIPTION
    Everything here runs OFFLINE. Not one test needs an Azure context, a credential or a
    subscription, which is what makes the suite runnable in CI and on a machine that has never
    logged in. Anything that would reach Azure goes through one of the engine's injectable probes.

    Three kinds of test, and the split matters:

      MANIFEST INTEGRITY - the manifest is data, and data that disagrees with the scripts it
      describes fails at hour two of a live run rather than here. Every argument it passes is
      checked against the target script's own parameter block, every path it names is checked to
      exist, and every .bicepparam in the repository must be accounted for exactly once.

      ENGINE BEHAVIOUR - ordering, what a failure takes down with it, retry classification, the
      version floor, the JSONL writer. Pure functions over fixture data, so they are fast and they
      test the shipped code rather than a copy of it.

      STANDARDS - issue #73 requires both scripts to meet the gold path. Asserted here rather than
      assumed, because the repository's existing standards tests only scan module-*/**/scripts/.

.EXAMPLE
    Invoke-Pester -Path .\tests\LabCycle.Tests.ps1

.NOTES
    Project: SkyCraft
    Issue:   #73
#>

#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

# ---------------------------------------------------------------------------------------------
# Discovery-time state. Pester 5 runs the file body once to discover tests and again to run them,
# and -ForEach cases must be built during discovery. Anything a case list is derived from
# therefore has to be computed HERE, at file level, not in a BeforeAll - a BeforeAll runs after
# discovery, and a case list built from a variable it sets is empty, which produces a Describe
# with no tests and a run that passes by having asserted nothing.
# ---------------------------------------------------------------------------------------------

$RepoRoot     = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$ToolsDir     = Join-Path $RepoRoot 'tools'
$ManifestPath = Join-Path $ToolsDir 'lab-cycle-manifest.psd1'
$Manifest     = Import-PowerShellDataFile -LiteralPath $ManifestPath

# The order issue #73 states, and the order the v0.8.0 live cycle measured. Held as a literal
# rather than derived from the manifest: a test that computes its expectation from the thing under
# test cannot fail.
$ExpectedOrder = @('1.2', '1.3', '2.1', '2.2', '2.3', '3.1', '3.2', '3.3', '3.4', '4.1', '4.2', '4.3', '4.4', '5.1', '5.2', '5.3')

function Get-ScriptParameterName {
    <#
        Returns the parameter names a script declares. Read from the AST rather than by running
        Get-Help or dot-sourcing, because dot-sourcing a lab script executes it.
    #>
    param([string]$Path)

    $ast = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$null, [ref]$null)
    if (-not $ast.ParamBlock) { return @() }
    @($ast.ParamBlock.Parameters | ForEach-Object { $_.Name.VariablePath.UserPath })
}

# Every argument the manifest passes, flattened into one case per argument, so a failure names the
# phase, the script and the parameter rather than saying 'the manifest is wrong somewhere'.
$ArgumentCases = @(
    foreach ($phase in $Manifest.Phases) {
        if ($phase.Excluded) { continue }
        $labDir = Join-Path (Join-Path $RepoRoot $phase.Lab) 'scripts'

        $steps = @(
            @{ Script = 'Deploy-Bicep.ps1'; Arguments = $phase.Deploy }
            @{ Script = 'Test-Lab.ps1';     Arguments = $phase.Test }
        )
        if ($phase.PostDeploy) {
            $steps += @{ Script = $phase.PostDeploy.Script; Arguments = $phase.PostDeploy.Arguments }
        }
        # RequiresOpsEmail is not in Deploy, because the orchestrator supplies the value. The
        # parameter still has to exist on the script, so it is checked like any other argument.
        if ($phase.RequiresOpsEmail) {
            $steps += @{ Script = 'Deploy-Bicep.ps1'; Arguments = @{ OpsEmail = 'checked-for-existence-only' } }
        }

        foreach ($step in $steps) {
            if (-not $step.Arguments) { continue }
            foreach ($name in $step.Arguments.Keys) {
                @{
                    PhaseId   = $phase.Id
                    Script    = $step.Script
                    Parameter = $name
                    Path      = (Join-Path $labDir $step.Script)
                }
            }
        }
    }
)

$TeardownArgumentCases = @(
    foreach ($entry in $Manifest.Teardowns) {
        $path = Join-Path (Join-Path (Join-Path $RepoRoot $entry.Lab) 'scripts') 'Remove-LabResource.ps1'
        foreach ($invocation in @($entry.Invocations)) {
            foreach ($name in $invocation.Keys) {
                @{ Lab = $entry.Lab; Parameter = $name; Path = $path; Value = $invocation[$name] }
            }
        }
    }
)

$PhasePathCases = @(
    foreach ($phase in $Manifest.Phases) {
        @{
            PhaseId   = $phase.Id
            LabPath   = (Join-Path $RepoRoot $phase.Lab)
            ParamPath = (Join-Path (Join-Path $RepoRoot $phase.Lab) $phase.ParamFile)
        }
    }
)

$ToolScriptCases = @(
    @{ Name = 'Invoke-LabCycle.ps1';  Path = (Join-Path $ToolsDir 'Invoke-LabCycle.ps1') }
    @{ Name = 'Remove-LabCycle.ps1';  Path = (Join-Path $ToolsDir 'Remove-LabCycle.ps1') }
    @{ Name = 'Invoke-LabScript.ps1'; Path = (Join-Path $ToolsDir 'Invoke-LabScript.ps1') }
)

BeforeAll {
    $script:RepoRoot     = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    $script:ToolsDir     = Join-Path $script:RepoRoot 'tools'
    $script:ManifestPath = Join-Path $script:ToolsDir 'lab-cycle-manifest.psd1'
    $script:Manifest     = Import-PowerShellDataFile -LiteralPath $script:ManifestPath
    $script:LivePhases   = @($script:Manifest.Phases | Where-Object { -not $_.Excluded })

    Import-Module (Join-Path $script:ToolsDir 'LabCycle.psm1') -Force

    # Re-declared for the run phase. Pester 5 executes this file once to discover and again to run,
    # and a file-level variable set during discovery is not what an It body reads.
    $script:ExpectedOrder = @('1.2', '1.3', '2.1', '2.2', '2.3', '3.1', '3.2', '3.3', '3.4', '4.1', '4.2', '4.3', '4.4', '5.1', '5.2', '5.3')

    function Get-ScriptParameterName {
        <#
            Returns the parameter names a script declares. Read from the AST rather than by running
            Get-Help or dot-sourcing, because dot-sourcing a lab script executes it.
        #>
        param([string]$Path)

        $ast = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$null, [ref]$null)
        if (-not $ast.ParamBlock) { return @() }
        @($ast.ParamBlock.Parameters | ForEach-Object { $_.Name.VariablePath.UserPath })
    }

    function New-CallCounter {
        <#
            A counter a closure can actually increment.

            $count++ inside a .GetNewClosure() scriptblock does NOT update the captured variable:
            the assignment creates a local in the invocation's own scope, the closure's copy stays
            at its initial value, and a test asserting 'this never ran' then passes without having
            checked anything. Measured here, not assumed - three tests in this file passed that way
            before this helper existed. A hashtable is mutated rather than assigned, so it works.
        #>
        [System.Collections.Hashtable]@{ Count = 0 }
    }

    # A context the engine accepts, so tests that are not about the subscription guard do not have
    # to think about it.
    $script:GoodContext = { [pscustomobject]@{ Subscription = [pscustomobject]@{ Id = 'fixture-subscription'; Name = 'fixture' } } }

    # Every offline engine test writes here rather than into the repository. Asserted separately,
    # because a suite that quietly leaves state files in tools/ is one whose next run starts dirty.
    $script:Scratch = Join-Path ([System.IO.Path]::GetTempPath()) "labcycle-tests-$([guid]::NewGuid().ToString('N'))"
    New-Item -ItemType Directory -Path $script:Scratch -Force | Out-Null

    $script:InvokeCycle = Join-Path $script:ToolsDir 'Invoke-LabCycle.ps1'
    $script:RemoveCycle = Join-Path $script:ToolsDir 'Remove-LabCycle.ps1'

    # Snapshotted BEFORE any test runs, because the question at the end is 'did this suite create
    # one of these', not 'does one exist'. A working tree where somebody has legitimately run a
    # real cycle already holds a state file and a report - both gitignored - and a test that reads
    # the second question as the first fails on a perfectly good checkout. It did.
    $script:RunArtefacts = 'lab-cycle-logs', 'lab-cycle-report.md', '.lab-cycle-lock.json', '.lab-cycle-state.json'
    $script:ArtefactsBefore = @{}
    foreach ($name in $script:RunArtefacts) {
        $script:ArtefactsBefore[$name] = Test-Path -LiteralPath (Join-Path $script:ToolsDir $name)
    }

    # Paths every engine test redirects at, so nothing lands beside the real orchestrator.
    $script:OfflinePaths = @{
        LogDirectory = (Join-Path $script:Scratch 'logs')
        ReportPath   = (Join-Path $script:Scratch 'report.md')
        ResultsPath  = (Join-Path $script:Scratch 'results.jsonl')
        LockPath     = (Join-Path $script:Scratch 'lock.json')
        StatePath    = (Join-Path $script:Scratch 'state.json')
    }

    function New-FixtureManifest {
        <#
            Writes a manifest to the scratch directory and returns its path. Fixture graphs rather
            than the real manifest, so an engine test that wants a failure can have one without
            anything in the repository having to be broken.
        #>
        param([Parameter(Mandatory)][string]$Body, [string]$Name = "manifest-$([guid]::NewGuid().ToString('N')).psd1")

        $path = Join-Path $script:Scratch $Name
        Set-Content -LiteralPath $path -Value $Body
        $path
    }
}

AfterAll {
    if ($script:Scratch -and (Test-Path -LiteralPath $script:Scratch)) {
        Remove-Item -LiteralPath $script:Scratch -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# =============================================================================================
# Manifest integrity
# =============================================================================================

Describe 'Manifest - accounts for every parameter file in the repository' {
    It 'has at least one phase, so an empty manifest cannot pass the checks below by vacuity' {
        @($script:Manifest.Phases).Count | Should -BeGreaterThan 0
    }

    It 'names every .bicepparam in the repository exactly once, across Phases and CompileOnly' {
        $onDisk = @(
            Get-ChildItem -Path $script:RepoRoot -Recurse -File -Filter '*.bicepparam' |
                ForEach-Object { $_.FullName.Substring($script:RepoRoot.Length + 1).Replace([char]92, [char]47) }
        ) | Sort-Object

        $claimed = @(
            foreach ($phase in $script:Manifest.Phases) { "$($phase.Lab)/$($phase.ParamFile)" }
            foreach ($entry in @($script:Manifest.CompileOnly)) { "$($entry.Lab)/$($entry.ParamFile)" }
        ) | Sort-Object

        # Compared both ways on purpose. A file on disk that the manifest does not name is coverage
        # nobody knows is missing; a file the manifest names that is not on disk is a phase that
        # will fail on a path.
        ($claimed | Where-Object { $_ -notin $onDisk }) | Should -BeNullOrEmpty -Because 'the manifest names a parameter file that does not exist'
        ($onDisk | Where-Object { $_ -notin $claimed }) | Should -BeNullOrEmpty -Because 'a parameter file exists that the manifest neither deploys nor records as compile-only'
    }

    It 'gives every CompileOnly entry a reason' {
        foreach ($entry in @($script:Manifest.CompileOnly)) {
            $entry.Reason | Should -Not -BeNullOrEmpty -Because "$($entry.Lab)/$($entry.ParamFile) is not deployed, and a count without a reason is not an explanation"
        }
    }

    It 'gives every phase a unique id' {
        $ids = @($script:Manifest.Phases | ForEach-Object { $_.Id })
        ($ids | Sort-Object -Unique).Count | Should -Be $ids.Count
    }
}

Describe 'Manifest - every path it names exists' {
    It "'<PhaseId>' names a lab directory that exists" -ForEach $PhasePathCases {
        Test-Path -LiteralPath $LabPath | Should -BeTrue
    }

    It "'<PhaseId>' names a parameter file that exists" -ForEach $PhasePathCases {
        Test-Path -LiteralPath $ParamPath | Should -BeTrue
    }
}

Describe 'Manifest - every argument is a real parameter of the script it is passed to' {
    It "'<PhaseId>' passes -<Parameter> to <Script>, which declares it" -ForEach $ArgumentCases {
        Test-Path -LiteralPath $Path | Should -BeTrue -Because "the manifest points at $Path"
        (Get-ScriptParameterName -Path $Path) | Should -Contain $Parameter
    }

    It "teardown of <Lab> passes -<Parameter>, which Remove-LabResource.ps1 declares" -ForEach $TeardownArgumentCases {
        Test-Path -LiteralPath $Path | Should -BeTrue
        (Get-ScriptParameterName -Path $Path) | Should -Contain $Parameter
    }
}

Describe 'Manifest - the dependency graph is sound' {
    It 'has no phase depending on an id that is not in the manifest' {
        $ids = @($script:Manifest.Phases | ForEach-Object { $_.Id })
        foreach ($phase in $script:Manifest.Phases) {
            foreach ($dependency in @($phase.DependsOn)) {
                $ids | Should -Contain $dependency -Because "phase $($phase.Id) depends on it"
            }
        }
    }

    It 'orders without throwing, which is what proves it acyclic' {
        { Get-PhaseOrder -Phases $script:LivePhases } | Should -Not -Throw
    }

    It 'produces exactly the order issue #73 states' {
        # The whole point of the declaration-order tie-break. If this fails, the cycle is running
        # an order nobody has verified live, whatever else still passes.
        @(Get-PhaseOrder -Phases $script:LivePhases) | Should -Be $script:ExpectedOrder
    }

    It 'places no phase before something it depends on' {
        $order = @(Get-PhaseOrder -Phases $script:LivePhases)
        $position = @{}
        for ($i = 0; $i -lt $order.Count; $i++) { $position[$order[$i]] = $i }

        foreach ($phase in $script:LivePhases) {
            foreach ($dependency in @($phase.DependsOn)) {
                $position[$dependency] | Should -BeLessThan $position[$phase.Id] -Because "$($phase.Id) depends on $dependency"
            }
        }
    }
}

Describe 'Manifest - teardown covers what the cycle deploys' {
    It 'has a teardown entry for every lab that has a live phase' {
        $deployedLabs = @($script:LivePhases | ForEach-Object { $_.Lab } | Sort-Object -Unique)
        $tornDown     = @($script:Manifest.Teardowns | ForEach-Object { $_.Lab } | Sort-Object -Unique)

        ($deployedLabs | Where-Object { $_ -notin $tornDown }) | Should -BeNullOrEmpty -Because 'a lab the cycle deploys and never removes is what accumulates into the next run''s preflight failure'
    }

    It 'has exactly one teardown entry per lab, never one per phase' {
        $labs = @($script:Manifest.Teardowns | ForEach-Object { $_.Lab })
        ($labs | Sort-Object -Unique).Count | Should -Be $labs.Count -Because 'a second entry for one lab runs its teardown twice, and the second run deletes nothing under $ErrorActionPreference = ''Stop'''
    }

    It 'tears lab 1.3 down first, because it owns the locks' {
        # Not cosmetic ordering. A CanNotDelete lock left in place turns every delete below it into
        # a failure that reads like a permissions problem.
        $script:Manifest.Teardowns[0].Lab | Should -Be 'module-1-identities-governance/1.3-governance'
    }

    It 'gives lab 3.3 a teardown limit above the 20 minutes that killed it' {
        # Set from a measured failure rather than from caution: on 2026-08-30 the Container Apps
        # Environment delete was still running when the old 20-minute limit killed it, and that
        # was the single teardown failure in an otherwise clean cycle. A teardown that reports a
        # failure on every clean run teaches its operator to discount failures.
        $containers = $script:Manifest.Teardowns | Where-Object { $_.Lab -eq 'module-3-compute/3.3-containers' }
        $containers.TimeoutMs | Should -BeGreaterThan 1200000
    }

    It 'tears the remaining labs down in the reverse of the deploy order' {
        $deployOrder = @(Get-PhaseOrder -Phases $script:LivePhases | ForEach-Object {
            ($script:LivePhases | Where-Object { $_.Id -eq $_ }) })

        $byId = @{}
        foreach ($phase in $script:LivePhases) { $byId[$phase.Id] = $phase.Lab }
        $labsInDeployOrder = @(Get-PhaseOrder -Phases $script:LivePhases | ForEach-Object { $byId[$_] })

        $locks    = 'module-1-identities-governance/1.3-governance'
        $expected = @($labsInDeployOrder | Where-Object { $_ -ne $locks })
        [array]::Reverse($expected)

        $actual = @($script:Manifest.Teardowns | ForEach-Object { $_.Lab } | Where-Object { $_ -ne $locks })
        $actual | Should -Be $expected
    }
}

Describe 'Manifest - the soft-delete guards name resources the labs really create' {
    It 'finds each guard''s needle somewhere in the lab it is attributed to' {
        foreach ($guard in @($script:Manifest.SoftDeleteGuards)) {
            $labPath = Join-Path $script:RepoRoot $guard.Lab
            $hit = @(Get-ChildItem -Path $labPath -Recurse -File -Include '*.ps1', '*.bicep', '*.bicepparam' -ErrorAction SilentlyContinue |
                Select-String -SimpleMatch -Pattern $guard.Needle -List)
            $hit | Should -Not -BeNullOrEmpty -Because "guard '$($guard.Name)' claims lab $($guard.Lab) creates it, and nothing in that lab mentions '$($guard.Needle)'"
        }
    }
}

Describe 'Manifest - the residue sweep names Azure''s groups and never Azure''s own' {
    It 'sweeps AzureBackupRG_ by prefix' {
        $script:Manifest.ResidualSweep.BackupResourceGroupPrefix | Should -Be 'AzureBackupRG_'
    }

    It 'never lists NetworkWatcherRG among the resource groups it deletes' {
        # Deleting it would take Network Watcher out for every other workload in the subscription.
        # Lab 5.3's own teardown removes this repository's children from inside it, which is the
        # correct scope.
        @($script:Manifest.ResidualSweep.ResourceGroups) | Should -Not -Contain 'NetworkWatcherRG'
    }

    It 'asserts both vaults absent rather than recording either as expected residue' {
        $kinds = @($script:Manifest.ResidualSweep.AssertAbsent | ForEach-Object { $_.Kind })
        $kinds | Should -Contain 'RecoveryServicesVault'
        $kinds | Should -Contain 'DataProtectionBackupVault'
    }

    It 'records a tooling floor for both az CLI and Az PowerShell' {
        $script:Manifest.ToolingFloor.AzCli | Should -Be '2.75.0'
        $script:Manifest.ToolingFloor.AzPowerShell | Should -Be '7.5.0'
    }
}

Describe 'Manifest - the one lab that still needs a canned answer, and only that one' {
    It 'feeds stdin to lab 2.2 and to nothing else' {
        # 3.2, 5.1, 5.2 and 5.3 all grew a real -Force. The moment 2.2 does too, this test is what
        # says the workaround can go.
        # '$null -ne' rather than plain truthiness: lab 2.2's answers are @(''), a one-element array
        # holding an empty string, and PowerShell unwraps a single-element array before testing it -
        # so `if ($_.StdinAnswers)` is FALSE for exactly the phase this is looking for.
        $withStdin = @($script:Manifest.Phases | Where-Object { $null -ne $_.StdinAnswers } | ForEach-Object { $_.Id })
        $withStdin | Should -Be @('2.2')
    }

    It 'answers the Bastion prompt with the default, which is no' {
        $bastion = $script:Manifest.Phases | Where-Object { $_.Id -eq '2.2' }
        @($bastion.StdinAnswers)[0] | Should -Be '' -Because 'Bastion is the one resource here with a standing hourly cost, and an unattended cycle must not start it'
    }

    It 'passes -Force to every deploy script that declares one and is reached unattended' {
        foreach ($id in '3.2', '5.1', '5.2', '5.3') {
            $phase = $script:Manifest.Phases | Where-Object { $_.Id -eq $id }
            $phase.Deploy.Force | Should -BeTrue -Because "$id prompts without it, and a prompt in an unattended chain is a phase that never runs"
        }
    }
}

# =============================================================================================
# Engine
# =============================================================================================

Describe 'Phase ordering - pure logic, against fixture graphs' {
    It 'returns the declared order when nothing constrains it' {
        $phases = @(
            @{ Id = 'c'; DependsOn = @() }
            @{ Id = 'a'; DependsOn = @() }
            @{ Id = 'b'; DependsOn = @() }
        )
        @(Get-PhaseOrder -Phases $phases) | Should -Be @('c', 'a', 'b')
    }

    It 'puts a dependency first even when it was declared last' {
        $phases = @(
            @{ Id = 'child';  DependsOn = @('parent') }
            @{ Id = 'parent'; DependsOn = @() }
        )
        @(Get-PhaseOrder -Phases $phases) | Should -Be @('parent', 'child')
    }

    It 'lets a phase unblocked mid-walk take its declared place' {
        # The exact shape that made the batch-emitting version produce the wrong order: once 'a' is
        # placed, 'b' and 'z' both become ready, and 'b' must come first because it was declared
        # first - not merely be in the same batch as 'z'.
        $phases = @(
            @{ Id = 'a'; DependsOn = @() }
            @{ Id = 'b'; DependsOn = @('a') }
            @{ Id = 'z'; DependsOn = @() }
        )
        @(Get-PhaseOrder -Phases $phases) | Should -Be @('a', 'b', 'z')
    }

    It 'throws on a cycle, naming the phases that cannot be ordered' {
        $phases = @(
            @{ Id = 'x'; DependsOn = @('y') }
            @{ Id = 'y'; DependsOn = @('x') }
        )
        { Get-PhaseOrder -Phases $phases } | Should -Throw -ExpectedMessage '*x, y*'
    }

    It 'ignores a dependency on an id outside the set, which is what makes -Labs work' {
        $phases = @(@{ Id = '5.2'; DependsOn = @('5.1') })
        @(Get-PhaseOrder -Phases $phases) | Should -Be @('5.2')
    }

    It 'returns nothing for an empty set rather than throwing' {
        @(Get-PhaseOrder -Phases @()).Count | Should -Be 0
    }
}

Describe 'Dependent phases - what a failure takes down with it' {
    BeforeAll {
        $script:Diamond = @(
            @{ Id = 'root';  DependsOn = @() }
            @{ Id = 'left';  DependsOn = @('root') }
            @{ Id = 'right'; DependsOn = @('root') }
            @{ Id = 'join';  DependsOn = @('left', 'right') }
            @{ Id = 'alone'; DependsOn = @() }
        )
    }

    It 'is transitive' {
        @(Get-DependentPhase -Phases $script:Diamond -Id 'root' | Sort-Object) | Should -Be @('join', 'left', 'right')
    }

    It 'leaves an independent branch alone' {
        @(Get-DependentPhase -Phases $script:Diamond -Id 'root') | Should -Not -Contain 'alone'
    }

    It 'walks a diamond once rather than twice' {
        @(Get-DependentPhase -Phases $script:Diamond -Id 'root').Count | Should -Be 3
    }
}

Describe 'Failure classifier - retryable only when the platform asked us to wait' {
    It 'retries <Signal>' -ForEach @(
        @{ Signal = 'SkuNotAvailable' }
        @{ Signal = 'AllocationFailed' }
        @{ Signal = 'TooManyRequests' }
    ) {
        (Get-LabCycleFailureClass -Text "Deployment failed: $Signal in swedencentral").Retryable | Should -BeTrue
    }

    It 'reads Azure''s own Retry-After when it named one' {
        $text = "TooManyRequests`nRetry-After: 90`n"
        (Get-LabCycleFailureClass -Text $text).RetryAfterSeconds | Should -Be 90
    }

    It 'does not retry an assertion failure' {
        (Get-LabCycleFailureClass -Text '[FAIL] expected 3 subnets, found 2').Retryable | Should -BeFalse
    }

    It 'does not retry a policy denial' {
        (Get-LabCycleFailureClass -Text 'RequestDisallowedByPolicy: Enforce-Project-Tag').Retryable | Should -BeFalse
    }

    It 'never retries a timeout, whatever its output happened to contain' {
        # A killed phase says nothing about whether another attempt would finish inside the same
        # limit. The fix is a longer limit, not another forty minutes learning the same thing.
        (Get-LabCycleFailureClass -Text 'TooManyRequests' -TimedOut).Retryable | Should -BeFalse
    }

    It 'does not read a bare 429 out of an unrelated identifier' {
        (Get-LabCycleFailureClass -Text 'resource sku429x not found').Retryable | Should -BeFalse
    }

    It 'returns a definite answer for empty output rather than throwing' {
        (Get-LabCycleFailureClass -Text '').Retryable | Should -BeFalse
    }
}

Describe 'Version comparison - the teardown''s floor' {
    It '<Observed> against <Minimum> is <Expected>' -ForEach @(
        @{ Observed = '2.86.0';  Minimum = '2.75.0'; Expected = $true }
        @{ Observed = '2.75.0';  Minimum = '2.75.0'; Expected = $true }
        @{ Observed = '2.74.9';  Minimum = '2.75.0'; Expected = $false }
        @{ Observed = '14.0.0';  Minimum = '7.5.0';  Expected = $true }
        @{ Observed = '7.5';     Minimum = '7.5.0';  Expected = $true }
        @{ Observed = '2.86.0-preview'; Minimum = '2.75.0'; Expected = $true }
        @{ Observed = '';        Minimum = '2.75.0'; Expected = $false }
        @{ Observed = 'unknown'; Minimum = '2.75.0'; Expected = $false }
    ) {
        Compare-LabCycleVersion -Observed $Observed -Minimum $Minimum | Should -Be $Expected
    }

    It 'treats an unreadable version as not meeting the floor, never as fine' {
        # The direction a version gate must not fail in: a caller that cannot read a version has
        # not established anything.
        Compare-LabCycleVersion -Observed $null -Minimum '2.75.0' | Should -BeFalse
    }
}

Describe 'Tooling floor - what the teardown refuses to start without' {
    It 'passes when both tools are new enough' {
        $checks = Test-LabCycleToolingFloor -MinimumAzCli '2.75.0' -MinimumAzPowerShell '7.5.0' `
            -AzCliVersionProbe { '2.86.0' } -AzPowerShellVersionProbe { '14.0.0' }
        @($checks | Where-Object { -not $_.Ok }) | Should -BeNullOrEmpty
    }

    It 'fails on an old az CLI, and says why it matters' {
        $checks = Test-LabCycleToolingFloor -MinimumAzCli '2.75.0' -MinimumAzPowerShell '7.5.0' `
            -AzCliVersionProbe { '2.60.0' } -AzPowerShellVersionProbe { '14.0.0' }
        $failed = @($checks | Where-Object { -not $_.Ok })
        $failed.Count | Should -Be 1
        $failed[0].Detail | Should -Match 'soft-deleted'
    }

    It 'fails on old Az PowerShell' {
        $checks = Test-LabCycleToolingFloor -MinimumAzCli '2.75.0' -MinimumAzPowerShell '7.5.0' `
            -AzCliVersionProbe { '2.86.0' } -AzPowerShellVersionProbe { '6.0.0' }
        @($checks | Where-Object { -not $_.Ok }).Count | Should -Be 1
    }

    It 'reports both when both are old, rather than stopping at the first' {
        $checks = Test-LabCycleToolingFloor -MinimumAzCli '2.75.0' -MinimumAzPowerShell '7.5.0' `
            -AzCliVersionProbe { '1.0.0' } -AzPowerShellVersionProbe { '1.0.0' }
        @($checks | Where-Object { -not $_.Ok }).Count | Should -Be 2
    }

    It 'fails when a tool is absent rather than treating absence as satisfied' {
        $checks = Test-LabCycleToolingFloor -MinimumAzCli '2.75.0' -MinimumAzPowerShell '7.5.0' `
            -AzCliVersionProbe { $null } -AzPowerShellVersionProbe { '14.0.0' }
        @($checks | Where-Object { -not $_.Ok })[0].Detail | Should -Match 'not found'
    }
}

Describe 'Results file - append-only, one JSON object per line' {
    BeforeEach {
        $script:ResultsFile = Join-Path $script:Scratch "results-$([guid]::NewGuid().ToString('N')).jsonl"
    }

    It 'writes one line per record' {
        Write-LabCycleResultLine -Path $script:ResultsFile -Record @{ Id = '1.2'; Status = 'Succeeded' }
        Write-LabCycleResultLine -Path $script:ResultsFile -Record @{ Id = '1.3'; Status = 'Failed' }

        @(Get-Content -LiteralPath $script:ResultsFile).Count | Should -Be 2
    }

    It 'writes lines that each parse as JSON on their own' {
        # The property that makes a partial file useful: a run killed mid-write costs the last
        # line, not the file.
        Write-LabCycleResultLine -Path $script:ResultsFile -Record @{ Id = '2.1'; Nested = @{ Deep = 'value' } }
        foreach ($line in Get-Content -LiteralPath $script:ResultsFile) {
            { $line | ConvertFrom-Json } | Should -Not -Throw
        }
    }

    It 'appends rather than rewriting' {
        Write-LabCycleResultLine -Path $script:ResultsFile -Record @{ Id = 'first' }
        Write-LabCycleResultLine -Path $script:ResultsFile -Record @{ Id = 'second' }
        (Get-Content -LiteralPath $script:ResultsFile)[0] | Should -Match 'first'
    }

    It 'creates the directory it was pointed at' {
        $nested = Join-Path $script:Scratch "nested-$([guid]::NewGuid().ToString('N'))/results.jsonl"
        Write-LabCycleResultLine -Path $nested -Record @{ Id = 'x' }
        Test-Path -LiteralPath $nested | Should -BeTrue
    }

    It 'writes nothing under -WhatIf' {
        $path = Join-Path $script:Scratch "whatif-$([guid]::NewGuid().ToString('N')).jsonl"
        Write-LabCycleResultLine -Path $path -Record @{ Id = 'x' } -WhatIf
        Test-Path -LiteralPath $path | Should -BeFalse
    }
}

Describe 'Report - says what the run cannot claim, as well as what it did' {
    BeforeEach {
        $script:ReportFile = Join-Path $script:Scratch "report-$([guid]::NewGuid().ToString('N')).md"
    }

    It 'renders a passing assertion set as evidence rather than as a bare count' {
        Write-LabCycleReport -Path $script:ReportFile -SubscriptionId 'fixture' `
            -Assertions @(
                @{ Name = 'RecoveryServicesVault absent'; Ok = $true; Detail = 'platform-skycraft-swc-rsv is gone' }
                @{ Name = 'no AzureBackupRG left'; Ok = $true; Detail = 'none' }
            )

        $text = Get-Content -Raw -LiteralPath $script:ReportFile
        $text | Should -Match '## Teardown assertions'
        $text | Should -Match 'All 2 passed'
        $text | Should -Match 'platform-skycraft-swc-rsv is gone'
    }

    It 'makes a failed assertion impossible to skim past' {
        # The whole reason this section exists: every delete can report success while the
        # subscription disagrees, and that is not residue.
        Write-LabCycleReport -Path $script:ReportFile -SubscriptionId 'fixture' `
            -Assertions @(
                @{ Name = 'RecoveryServicesVault absent'; Ok = $false; Detail = 'it is still there' }
                @{ Name = 'no AzureBackupRG left'; Ok = $true; Detail = 'none' }
            )

        $text = Get-Content -Raw -LiteralPath $script:ReportFile
        $text | Should -Match '\*\*1 of 2 FAILED'
        $text | Should -Match '\*\*FAIL\*\* - RecoveryServicesVault absent'
    }

    It 'says nothing was checked rather than implying everything passed' {
        # A partial teardown asserts nothing. An empty section that read 'All 0 passed' would be
        # a clean bill of health for a check that never ran.
        Write-LabCycleReport -Path $script:ReportFile -SubscriptionId 'fixture' -Assertions @()

        (Get-Content -Raw -LiteralPath $script:ReportFile) | Should -Match 'Not checked'
    }

    It 'calls a teardown timeout a timeout rather than printing a bare exit 124' {
        # 124 is the runner's sentinel. 'Still running when we stopped waiting' and 'the delete
        # failed' send someone to different places - a longer TimeoutMs, or Azure.
        Write-LabCycleReport -Path $script:ReportFile -SubscriptionId 'fixture' `
            -Teardowns @(@{ Lab = 'module-3-compute/3.3-containers'; Status = 'Failed'; ExitCode = 124 })

        (Get-Content -Raw -LiteralPath $script:ReportFile) | Should -Match 'timed out'
    }

    It 'writes nothing under -WhatIf' {
        Write-LabCycleReport -Path $script:ReportFile -SubscriptionId 'fixture' -WhatIf
        Test-Path -LiteralPath $script:ReportFile | Should -BeFalse
    }
}

Describe 'RBAC matcher - only ''*'' is a wildcard, and it spans ''/''' {
    It 'grants through a bare wildcard' {
        Test-LabCycleActionAllowed -Permissions @(@{ actions = @('*'); notActions = @() }) -Action 'Microsoft.Resources/deployments/write' | Should -BeTrue
    }

    It 'grants through a wildcard that spans a slash' {
        Test-LabCycleActionAllowed -Permissions @(@{ actions = @('*/write'); notActions = @() }) -Action 'Microsoft.Resources/deployments/write' | Should -BeTrue
    }

    It 'refuses a read-only principal' {
        Test-LabCycleActionAllowed -Permissions @(@{ actions = @('*/read'); notActions = @() }) -Action 'Microsoft.Resources/deployments/write' | Should -BeFalse
    }

    It 'honours notActions on the same entry' {
        Test-LabCycleActionAllowed -Permissions @(@{ actions = @('*'); notActions = @('Microsoft.Resources/deployments/write') }) -Action 'Microsoft.Resources/deployments/write' | Should -BeFalse
    }

    It 'matches case-insensitively, so a differently-cased notActions still denies' {
        Test-LabCycleActionAllowed -Permissions @(@{ actions = @('*'); notActions = @('MICROSOFT.RESOURCES/*/WRITE') }) -Action 'Microsoft.Resources/deployments/write' | Should -BeFalse
    }

    It 'refuses when no entry grants anything' {
        Test-LabCycleActionAllowed -Permissions @() -Action 'Microsoft.Resources/deployments/write' | Should -BeFalse
    }
}

Describe 'Subscription guard - compares ids, never names' {
    It 'accepts the subscription the run was given' {
        (Test-LabCycleSubscription -SubscriptionId 'fixture-subscription' -ContextProbe $script:GoodContext).Ok | Should -BeTrue
    }

    It 'refuses a different subscription that shares a display name' {
        $other = { [pscustomobject]@{ Subscription = [pscustomobject]@{ Id = 'someone-elses'; Name = 'fixture' } } }
        (Test-LabCycleSubscription -SubscriptionId 'fixture-subscription' -ContextProbe $other).Ok | Should -BeFalse
    }

    It 'refuses when there is no context at all' {
        (Test-LabCycleSubscription -SubscriptionId 'fixture-subscription' -ContextProbe { $null }).Ok | Should -BeFalse
    }
}

# =============================================================================================
# Orchestrator, driven offline through the injected runner
# =============================================================================================

Describe 'Engine - runs phases in order and reports what happened' {
    BeforeAll {
        $script:ChainManifest = New-FixtureManifest -Body @'
@{
    Phases = @(
        @{ Id = 'first';  Lab = 'module-1-identities-governance/1.2-rbac'; ParamFile = 'x'; Deploy = @{}; PostDeploy = $null; Test = @{}; DependsOn = @();         TimeoutMs = 1000; Excluded = $null }
        @{ Id = 'second'; Lab = 'module-1-identities-governance/1.3-governance'; ParamFile = 'x'; Deploy = @{}; PostDeploy = $null; Test = @{}; DependsOn = @('first'); TimeoutMs = 1000; Excluded = $null }
        @{ Id = 'other';  Lab = 'module-2-networking/2.1-virtual-networks'; ParamFile = 'x'; Deploy = @{}; PostDeploy = $null; Test = @{}; DependsOn = @();         TimeoutMs = 1000; Excluded = $null }
    )
    SoftDeleteGuards = @()
    CompileOnly = @()
    Teardowns = @()
}
'@
    }

    It 'runs them in the manifest''s order' {
        $seen = [System.Collections.Generic.List[string]]::new()
        $runner = { param($Invocation) if ($Invocation.Kind -eq 'Deploy') { $seen.Add($Invocation.Phase.Id) }; 0 }.GetNewClosure()

        & $script:InvokeCycle -SubscriptionId 'fixture-subscription' -ManifestPath $script:ChainManifest `
            -PhaseRunner $runner -PreflightRunner { @() } -ContextProbe $script:GoodContext `
            -Yes -SkipCleanup @script:OfflinePaths | Out-Null

        @($seen) | Should -Be @('first', 'second', 'other')
    }

    It 'exits 0 when every phase succeeded' {
        & $script:InvokeCycle -SubscriptionId 'fixture-subscription' -ManifestPath $script:ChainManifest `
            -PhaseRunner { 0 } -PreflightRunner { @() } -ContextProbe $script:GoodContext `
            -Yes -SkipCleanup @script:OfflinePaths | Out-Null
        $LASTEXITCODE | Should -Be 0
    }

    It 'skips what depends on a failure, and nothing else' {
        $result = & $script:InvokeCycle -SubscriptionId 'fixture-subscription' -ManifestPath $script:ChainManifest `
            -PhaseRunner { param($Invocation) if ($Invocation.Phase.Id -eq 'first') { 1 } else { 0 } } `
            -PreflightRunner { @() } -ContextProbe $script:GoodContext -Yes -SkipCleanup @script:OfflinePaths

        ($result.Phases | Where-Object { $_.Id -eq 'second' }).Status | Should -Be 'Skipped'
        ($result.Phases | Where-Object { $_.Id -eq 'other' }).Status  | Should -Be 'Succeeded'
    }

    It 'names the phase that actually failed as the cause of a skip' {
        $result = & $script:InvokeCycle -SubscriptionId 'fixture-subscription' -ManifestPath $script:ChainManifest `
            -PhaseRunner { param($Invocation) if ($Invocation.Phase.Id -eq 'first') { 1 } else { 0 } } `
            -PreflightRunner { @() } -ContextProbe $script:GoodContext -Yes -SkipCleanup @script:OfflinePaths

        ($result.Phases | Where-Object { $_.Id -eq 'second' }).Cause | Should -Be 'first'
    }

    It 'exits with the number of failures, which is the whole point' {
        # A run that reports success while phases failed is invisible from inside the process. This
        # is the assertion that issues #104 and #105 existed for.
        & $script:InvokeCycle -SubscriptionId 'fixture-subscription' -ManifestPath $script:ChainManifest `
            -PhaseRunner { param($Invocation) if ($Invocation.Phase.Id -eq 'other') { 1 } else { 0 } } `
            -PreflightRunner { @() } -ContextProbe $script:GoodContext -Yes -SkipCleanup @script:OfflinePaths | Out-Null
        $LASTEXITCODE | Should -Be 1
    }

    It 'runs deploy then test, and stops the phase at the first non-zero' {
        $kinds = [System.Collections.Generic.List[string]]::new()
        $runner = { param($Invocation) $kinds.Add("$($Invocation.Phase.Id):$($Invocation.Kind)"); if ($Invocation.Kind -eq 'Deploy' -and $Invocation.Phase.Id -eq 'first') { 1 } else { 0 } }.GetNewClosure()

        & $script:InvokeCycle -SubscriptionId 'fixture-subscription' -ManifestPath $script:ChainManifest `
            -PhaseRunner $runner -PreflightRunner { @() } -ContextProbe $script:GoodContext `
            -Yes -SkipCleanup @script:OfflinePaths | Out-Null

        # Validating a deployment that failed reports a second failure for one cause.
        @($kinds) | Should -Not -Contain 'first:Test'
        @($kinds) | Should -Contain 'other:Test'
    }

    It 'writes a JSONL line for every phase, including the skipped one' {
        $results = Join-Path $script:Scratch "jsonl-$([guid]::NewGuid().ToString('N')).jsonl"
        $paths = @{} + $script:OfflinePaths
        $paths.ResultsPath = $results

        & $script:InvokeCycle -SubscriptionId 'fixture-subscription' -ManifestPath $script:ChainManifest `
            -PhaseRunner { param($Invocation) if ($Invocation.Phase.Id -eq 'first') { 1 } else { 0 } } `
            -PreflightRunner { @() } -ContextProbe $script:GoodContext -Yes -SkipCleanup @paths | Out-Null

        $lines = @(Get-Content -LiteralPath $results | ForEach-Object { $_ | ConvertFrom-Json })
        @($lines | ForEach-Object { $_.Id } | Sort-Object) | Should -Be @('first', 'other', 'second')
        ($lines | Where-Object { $_.Id -eq 'second' }).Status | Should -Be 'Skipped'
    }

    It 'refuses a plan it was not confirmed for' {
        & $script:InvokeCycle -SubscriptionId 'fixture-subscription' -ManifestPath $script:ChainManifest `
            -PhaseRunner { 0 } -PreflightRunner { @() } -ContextProbe $script:GoodContext `
            -ConfirmRunner { 'n' } -SkipCleanup @script:OfflinePaths | Out-Null
        $LASTEXITCODE | Should -Be 4
    }

    It 'stops on a failed preflight check without running a phase' {
        $ran = New-CallCounter
        $runner = { $ran.Count++; 0 }.GetNewClosure()
        $failing = { @(@{ Name = 'subscription'; Ok = $false; Detail = 'wrong subscription'; Severity = 'Info' }) }

        & $script:InvokeCycle -SubscriptionId 'fixture-subscription' -ManifestPath $script:ChainManifest `
            -PhaseRunner $runner -PreflightRunner $failing -ContextProbe $script:GoodContext `
            -Yes -SkipCleanup @script:OfflinePaths | Out-Null

        $LASTEXITCODE | Should -Be 3
        $ran.Count | Should -Be 0 -Because 'the later checks assume the earlier ones held, so continuing past one asks a question whose answer cannot be trusted'
    }

    It 'continues past a preflight check that only warns' {
        # Lab 5.1's teardown reserves its Log Analytics name on every clean run. Treating that as
        # fatal would mean a successful run stopped the next one from ever starting.
        $warning = { @(@{ Name = 'leftovers'; Ok = $true; Detail = 'reserved but recoverable'; Severity = 'Warning' }) }
        & $script:InvokeCycle -SubscriptionId 'fixture-subscription' -ManifestPath $script:ChainManifest `
            -PhaseRunner { 0 } -PreflightRunner $warning -ContextProbe $script:GoodContext `
            -Yes -SkipCleanup @script:OfflinePaths | Out-Null
        $LASTEXITCODE | Should -Be 0
    }

    It 'touches nothing on a dry run' {
        $ran = New-CallCounter
        $runner = { $ran.Count++; 0 }.GetNewClosure()
        $result = & $script:InvokeCycle -SubscriptionId 'fixture-subscription' -ManifestPath $script:ChainManifest `
            -PhaseRunner $runner -PreflightRunner { @() } -ContextProbe $script:GoodContext `
            -Yes -DryRun @script:OfflinePaths

        @($result.Phases | Where-Object { $_.Status -eq 'DryRun' }).Count | Should -Be 3
        $ran.Count | Should -Be 0 -Because 'a dry run that deployed anything would be the one mistake -DryRun exists to prevent'
    }

    It 'stops rather than deploying when the subscription drifts mid-run' {
        # The 2026-08-02 incident, as a test: a context that changes identity between phases must
        # end the run, not carry on into whatever subscription it now names.
        $calls = New-CallCounter
        $drifting = {
            $calls.Count++
            $id = if ($calls.Count -le 1) { 'fixture-subscription' } else { 'someone-elses' }
            [pscustomobject]@{ Subscription = [pscustomobject]@{ Id = $id; Name = 'fixture' } }
        }.GetNewClosure()

        { & $script:InvokeCycle -SubscriptionId 'fixture-subscription' -ManifestPath $script:ChainManifest `
            -PhaseRunner { 0 } -PreflightRunner { @() } -ContextProbe $drifting `
            -Yes -SkipCleanup @script:OfflinePaths } | Should -Throw '*drifted*'
    }
}

Describe 'Engine - -Labs' {
    BeforeAll {
        $script:LabsManifest = New-FixtureManifest -Body @'
@{
    Phases = @(
        @{ Id = 'a'; Lab = 'module-1-identities-governance/1.2-rbac'; ParamFile = 'x'; Deploy = @{}; PostDeploy = $null; Test = @{}; DependsOn = @();    TimeoutMs = 1000; Excluded = $null }
        @{ Id = 'b'; Lab = 'module-1-identities-governance/1.3-governance'; ParamFile = 'x'; Deploy = @{}; PostDeploy = $null; Test = @{}; DependsOn = @('a'); TimeoutMs = 1000; Excluded = $null }
    )
    SoftDeleteGuards = @()
    CompileOnly = @()
    Teardowns = @()
}
'@
    }

    It 'runs only what was named' {
        $seen = [System.Collections.Generic.List[string]]::new()
        $runner = { param($Invocation) if ($Invocation.Kind -eq 'Deploy') { $seen.Add($Invocation.Phase.Id) }; 0 }.GetNewClosure()

        & $script:InvokeCycle -SubscriptionId 'fixture-subscription' -ManifestPath $script:LabsManifest `
            -Labs 'b' -PhaseRunner $runner -PreflightRunner { @() } -ContextProbe $script:GoodContext `
            -Yes -SkipCleanup @script:OfflinePaths | Out-Null

        @($seen) | Should -Be @('b')
    }

    It 'treats a dependency outside the selection as already satisfied rather than refusing' {
        # What the switch is for: re-running one lab after fixing it, against what the last run
        # left standing.
        & $script:InvokeCycle -SubscriptionId 'fixture-subscription' -ManifestPath $script:LabsManifest `
            -Labs 'b' -PhaseRunner { 0 } -PreflightRunner { @() } -ContextProbe $script:GoodContext `
            -Yes -SkipCleanup @script:OfflinePaths | Out-Null
        $LASTEXITCODE | Should -Be 0
    }

    It 'refuses a phase id the manifest does not have, rather than silently running nothing' {
        & $script:InvokeCycle -SubscriptionId 'fixture-subscription' -ManifestPath $script:LabsManifest `
            -Labs 'not-a-phase' -PhaseRunner { 0 } -PreflightRunner { @() } -ContextProbe $script:GoodContext `
            -Yes -SkipCleanup @script:OfflinePaths | Out-Null
        $LASTEXITCODE | Should -Be 2
    }
}

Describe 'Engine - -OpsEmail is demanded before the run, not an hour into it' {
    BeforeAll {
        $script:OpsManifest = New-FixtureManifest -Body @'
@{
    Phases = @(
        @{ Id = 'needs-email'; Lab = 'module-5-monitoring-maintenance/5.1-azure-monitor'; ParamFile = 'x'; Deploy = @{ Force = $true }; PostDeploy = $null; Test = @{}; DependsOn = @(); TimeoutMs = 1000; Excluded = $null; RequiresOpsEmail = $true }
        @{ Id = 'does-not';    Lab = 'module-2-networking/2.1-virtual-networks'; ParamFile = 'x'; Deploy = @{}; PostDeploy = $null; Test = @{}; DependsOn = @(); TimeoutMs = 1000; Excluded = $null }
    )
    SoftDeleteGuards = @()
    CompileOnly = @()
    Teardowns = @()
}
'@
    }

    It 'refuses to start when a selected phase needs it and it was not given' {
        & $script:InvokeCycle -SubscriptionId 'fixture-subscription' -ManifestPath $script:OpsManifest `
            -PhaseRunner { 0 } -PreflightRunner { @() } -ContextProbe $script:GoodContext `
            -Yes -SkipCleanup @script:OfflinePaths | Out-Null
        $LASTEXITCODE | Should -Be 2
    }

    It 'does not demand it when the selection has no use for it' {
        & $script:InvokeCycle -SubscriptionId 'fixture-subscription' -ManifestPath $script:OpsManifest `
            -Labs 'does-not' -PhaseRunner { 0 } -PreflightRunner { @() } -ContextProbe $script:GoodContext `
            -Yes -SkipCleanup @script:OfflinePaths | Out-Null
        $LASTEXITCODE | Should -Be 0
    }

    It 'merges it into the deploy arguments of the phase that needs it, and only that phase' {
        $captured = @{}
        $runner = { param($Invocation) if ($Invocation.Kind -eq 'Deploy') { $captured[$Invocation.Phase.Id] = $Invocation.Arguments }; 0 }.GetNewClosure()

        & $script:InvokeCycle -SubscriptionId 'fixture-subscription' -ManifestPath $script:OpsManifest `
            -OpsEmail 'ops@example.com' -PhaseRunner $runner -PreflightRunner { @() } `
            -ContextProbe $script:GoodContext -Yes -SkipCleanup @script:OfflinePaths | Out-Null

        $captured['needs-email'].OpsEmail | Should -Be 'ops@example.com'
        $captured['does-not'].Keys | Should -Not -Contain 'OpsEmail'
    }

    It 'leaves the manifest''s own Deploy hashtable unmutated' {
        # The reason the arguments are copied. A manifest mutated in place carries -OpsEmail into
        # every later read of that phase, including a -Resume in the same process.
        $captured = @{}
        $runner = { param($Invocation) if ($Invocation.Kind -eq 'Deploy') { $captured[$Invocation.Phase.Id] = $Invocation.Phase.Deploy }; 0 }.GetNewClosure()

        & $script:InvokeCycle -SubscriptionId 'fixture-subscription' -ManifestPath $script:OpsManifest `
            -OpsEmail 'ops@example.com' -PhaseRunner $runner -PreflightRunner { @() } `
            -ContextProbe $script:GoodContext -Yes -SkipCleanup @script:OfflinePaths | Out-Null

        $captured['needs-email'].Keys | Should -Not -Contain 'OpsEmail'
    }
}

Describe 'Engine - hands off to the teardown script and carries its answer back' {
    BeforeAll {
        $script:HandoffManifest = New-FixtureManifest -Body @'
@{
    Phases = @(
        @{ Id = 'only'; Lab = 'module-2-networking/2.1-virtual-networks'; ParamFile = 'x'; Deploy = @{}; PostDeploy = $null; Test = @{}; DependsOn = @(); TimeoutMs = 1000; Excluded = $null }
    )
    SoftDeleteGuards = @()
    CompileOnly = @()
    Teardowns = @()
}
'@
        # A stand-in for Remove-LabCycle.ps1. The handoff is what is under test here, not the
        # teardown itself - that has its own Describe below.
        #
        # SupportsShouldProcess is not decoration: the orchestrator passes -Confirm:$false so an
        # unattended cycle does not stop on the teardown's confirmation, and a replacement script
        # that does not declare it fails parameter binding. The first version of this fake did not,
        # and that is how the requirement was found - so any -RemoveScriptPath must honour it.
        $script:FakeRemove = Join-Path $script:Scratch 'Fake-Remove.ps1'
        Set-Content -LiteralPath $script:FakeRemove -Value @'
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$SubscriptionId, [string]$ManifestPath, [string]$LabRoot, [string]$LogDirectory,
    [string]$ResultsPath, [string]$RunId, [string[]]$Labs
)
Set-Content -LiteralPath (Join-Path $LogDirectory 'fake-remove-was-called.txt') -Value $RunId
[pscustomobject]@{
    Teardowns  = @(@{ Lab = 'module-2-networking/2.1-virtual-networks'; Status = 'Removed'; ExitCode = 0 })
    LeftBehind = @(@{ Lab = '(sweep)'; What = 'something'; Why = 'a reason' })
    Assertions = @(
        @{ Name = 'RecoveryServicesVault absent'; Ok = $true;  Detail = 'gone' }
        @{ Name = 'lab resource group absent';    Ok = $false; Detail = "'dev-skycraft-swc-rg' still exists" }
    )
}
'@
    }

    It 'calls the teardown script when -SkipCleanup was not passed' {
        $logs = Join-Path $script:Scratch "handoff-$([guid]::NewGuid().ToString('N'))"
        New-Item -ItemType Directory -Path $logs -Force | Out-Null
        $paths = @{} + $script:OfflinePaths
        $paths.LogDirectory = $logs

        & $script:InvokeCycle -SubscriptionId 'fixture-subscription' -ManifestPath $script:HandoffManifest `
            -PhaseRunner { 0 } -PreflightRunner { @() } -ContextProbe $script:GoodContext `
            -RemoveScriptPath $script:FakeRemove -Yes @paths | Out-Null

        Test-Path -LiteralPath (Join-Path $logs 'fake-remove-was-called.txt') | Should -BeTrue
    }

    It 'does not call it under -SkipCleanup' {
        $logs = Join-Path $script:Scratch "handoff-$([guid]::NewGuid().ToString('N'))"
        New-Item -ItemType Directory -Path $logs -Force | Out-Null
        $paths = @{} + $script:OfflinePaths
        $paths.LogDirectory = $logs

        & $script:InvokeCycle -SubscriptionId 'fixture-subscription' -ManifestPath $script:HandoffManifest `
            -PhaseRunner { 0 } -PreflightRunner { @() } -ContextProbe $script:GoodContext `
            -RemoveScriptPath $script:FakeRemove -Yes -SkipCleanup @paths | Out-Null

        Test-Path -LiteralPath (Join-Path $logs 'fake-remove-was-called.txt') | Should -BeFalse
    }

    It 'carries the teardown''s assertions into its own result and report' {
        $report = Join-Path $script:Scratch "handoff-report-$([guid]::NewGuid().ToString('N')).md"
        $logs = Join-Path $script:Scratch "handoff-$([guid]::NewGuid().ToString('N'))"
        New-Item -ItemType Directory -Path $logs -Force | Out-Null
        $paths = @{} + $script:OfflinePaths
        $paths.LogDirectory = $logs
        $paths.ReportPath = $report

        $result = & $script:InvokeCycle -SubscriptionId 'fixture-subscription' -ManifestPath $script:HandoffManifest `
            -PhaseRunner { 0 } -PreflightRunner { @() } -ContextProbe $script:GoodContext `
            -RemoveScriptPath $script:FakeRemove -Yes @paths

        $result.AssertionFailedCount | Should -Be 1
        (Get-Content -Raw -LiteralPath $report) | Should -Match '\*\*FAIL\*\* - lab resource group absent'
    }

    It 'keeps a failed teardown assertion out of the deploy exit code' {
        # 'The lab failed' and 'the lab could not be removed' are different facts with different
        # remedies. The assertion is reported loudly; it does not turn a clean deploy into a
        # failed one.
        # Its own log directory, created up front: the fake writes its marker there, and unlike a
        # real teardown it does not create the directory first.
        $logs = Join-Path $script:Scratch "handoff-$([guid]::NewGuid().ToString('N'))"
        New-Item -ItemType Directory -Path $logs -Force | Out-Null
        $paths = @{} + $script:OfflinePaths
        $paths.LogDirectory = $logs

        & $script:InvokeCycle -SubscriptionId 'fixture-subscription' -ManifestPath $script:HandoffManifest `
            -PhaseRunner { 0 } -PreflightRunner { @() } -ContextProbe $script:GoodContext `
            -RemoveScriptPath $script:FakeRemove -Yes @paths | Out-Null

        $LASTEXITCODE | Should -Be 0
    }
}

Describe 'Engine - stdin answers reach the runner' {
    It 'passes the manifest''s canned answers through to the step' {
        $manifest = New-FixtureManifest -Body @'
@{
    Phases = @(
        @{ Id = 'prompts'; Lab = 'module-2-networking/2.2-secure-access'; ParamFile = 'x'; Deploy = @{}; PostDeploy = $null; Test = @{}; DependsOn = @(); TimeoutMs = 1000; StdinAnswers = @(''); Excluded = $null }
    )
    SoftDeleteGuards = @()
    CompileOnly = @()
    Teardowns = @()
}
'@
        $captured = $null
        $runner = { param($Invocation) if ($Invocation.Kind -eq 'Deploy') { $captured = $Invocation.StdinAnswers }; 0 }.GetNewClosure()

        & $script:InvokeCycle -SubscriptionId 'fixture-subscription' -ManifestPath $manifest `
            -PhaseRunner $runner -PreflightRunner { @() } -ContextProbe $script:GoodContext `
            -Yes -SkipCleanup @script:OfflinePaths | Out-Null

        @($captured).Count | Should -Be 1
    }
}

Describe 'Process runner - carries a real exit code back, and feeds stdin' {
    BeforeAll {
        $script:Shim = Join-Path $script:ToolsDir 'Invoke-LabScript.ps1'
        $script:FixtureDir = Join-Path $script:Scratch 'fixtures'
        New-Item -ItemType Directory -Path $script:FixtureDir -Force | Out-Null

        # Declares '#Requires -Modules', which is the whole reason the shim exists: launched with
        # 'pwsh -File' directly, this script's exit code is discarded and the process reports 0.
        Set-Content -LiteralPath (Join-Path $script:FixtureDir 'exits-seven.ps1') -Value @'
#Requires -Version 7.0
#Requires -Modules Microsoft.PowerShell.Utility
Write-Host 'about to fail'
exit 7
'@
        Set-Content -LiteralPath (Join-Path $script:FixtureDir 'echoes-answer.ps1') -Value @'
#Requires -Version 7.0
$answer = Read-Host 'say something'
Write-Host "answered:[$answer]"
exit 0
'@
        Set-Content -LiteralPath (Join-Path $script:FixtureDir 'takes-argument.ps1') -Value @'
#Requires -Version 7.0
param([string]$Environment)
Write-Host "environment:[$Environment]"
exit 0
'@
    }

    It 'returns the target''s real exit code, which pwsh -File would have discarded' {
        $result = Invoke-LabScriptProcess -ShimPath $script:Shim `
            -ScriptPath (Join-Path $script:FixtureDir 'exits-seven.ps1') `
            -WorkingDirectory $script:FixtureDir -TimeoutMs 60000 `
            -TranscriptPath (Join-Path $script:Scratch 'exits-seven.log')

        $result.ExitCode | Should -Be 7
    }

    It 'writes a transcript containing what the target printed' {
        $transcript = Join-Path $script:Scratch 'transcript.log'
        Invoke-LabScriptProcess -ShimPath $script:Shim `
            -ScriptPath (Join-Path $script:FixtureDir 'exits-seven.ps1') `
            -WorkingDirectory $script:FixtureDir -TimeoutMs 60000 -TranscriptPath $transcript | Out-Null

        (Get-Content -Raw -LiteralPath $transcript) | Should -Match 'about to fail'
    }

    It 'feeds a canned answer to a Read-Host rather than leaving it to end-of-file' {
        # The one thing lab 2.2 needs. Read-Host on a closed stdin throws under
        # $ErrorActionPreference = 'Stop', so an unfed prompt fails on the prompt rather than on
        # anything to do with the lab.
        $result = Invoke-LabScriptProcess -ShimPath $script:Shim `
            -ScriptPath (Join-Path $script:FixtureDir 'echoes-answer.ps1') `
            -WorkingDirectory $script:FixtureDir -TimeoutMs 60000 `
            -TranscriptPath (Join-Path $script:Scratch 'answered.log') `
            -StdinAnswers @('n')

        $result.ExitCode | Should -Be 0
        $result.Output | Should -Match 'answered:\[n\]'
    }

    It 'splats named arguments rather than quoting them onto a command line' {
        $result = Invoke-LabScriptProcess -ShimPath $script:Shim `
            -ScriptPath (Join-Path $script:FixtureDir 'takes-argument.ps1') `
            -Arguments @{ Environment = 'platform' } `
            -WorkingDirectory $script:FixtureDir -TimeoutMs 60000 `
            -TranscriptPath (Join-Path $script:Scratch 'argument.log')

        $result.Output | Should -Match 'environment:\[platform\]'
    }
}

# =============================================================================================
# Teardown
# =============================================================================================

Describe 'Teardown - order, failure handling and -WhatIf' {
    BeforeAll {
        $script:TeardownManifest = New-FixtureManifest -Body @'
@{
    Phases = @(
        @{ Id = '1.3'; Lab = 'module-1-identities-governance/1.3-governance'; ParamFile = 'x'; Deploy = @{}; PostDeploy = $null; Test = @{}; DependsOn = @(); TimeoutMs = 1000; Excluded = $null }
        @{ Id = '2.1'; Lab = 'module-2-networking/2.1-virtual-networks';      ParamFile = 'x'; Deploy = @{}; PostDeploy = $null; Test = @{}; DependsOn = @(); TimeoutMs = 1000; Excluded = $null }
    )
    SoftDeleteGuards = @()
    CompileOnly = @()
    Teardowns = @(
        @{ Lab = 'module-1-identities-governance/1.3-governance'; Invocations = @(@{ Force = $true }); TimeoutMs = 1000 }
        @{ Lab = 'module-2-networking/2.1-virtual-networks';      Invocations = @(@{ Force = $true }); TimeoutMs = 1000
           LeavesBehind = @(@{ What = 'a name'; Why = 'a reason' }) }
    )
    ResidualSweep = @{
        BackupResourceGroupPrefix = 'AzureBackupRG_'
        AssertAbsent = @(
            @{ Kind = 'RecoveryServicesVault'; Name = 'platform-skycraft-swc-rsv'; ResourceGroup = 'platform-skycraft-swc-rg' }
        )
        ResourceGroups = @('dev-skycraft-swc-rg')
    }
    ToolingFloor = @{ AzCli = '2.75.0'; AzPowerShell = '7.5.0' }
}
'@
        # A clean subscription, as the probes see it after a successful teardown.
        $script:CleanProbes = @{
            ContextProbe             = $script:GoodContext
            ToolingFloorRunner       = { @() }
            BackupResourceGroupProbe = { @() }
            ResourceGroupProbe       = { $null }
            VaultProbe               = { $null }
            ResourceGroupRemover     = { $null }
        }
    }

    It 'runs lab 1.3 first, because it owns the locks' {
        $seen = [System.Collections.Generic.List[string]]::new()
        $runner = { param($Invocation) $seen.Add($Invocation.Lab); 0 }.GetNewClosure()

        & $script:RemoveCycle -SubscriptionId 'fixture-subscription' -ManifestPath $script:TeardownManifest `
            -TeardownRunner $runner -Confirm:$false `
            -LogDirectory $script:OfflinePaths.LogDirectory -ResultsPath $script:OfflinePaths.ResultsPath `
            @script:CleanProbes | Out-Null

        $seen[0] | Should -Be 'module-1-identities-governance/1.3-governance'
    }

    It 'exits 0 on a clean teardown' {
        & $script:RemoveCycle -SubscriptionId 'fixture-subscription' -ManifestPath $script:TeardownManifest `
            -TeardownRunner { 0 } -Confirm:$false `
            -LogDirectory $script:OfflinePaths.LogDirectory -ResultsPath $script:OfflinePaths.ResultsPath `
            @script:CleanProbes | Out-Null
        $LASTEXITCODE | Should -Be 0
    }

    It 'keeps going after a lab fails, and still removes the rest' {
        # Leaving the other labs standing because the first delete failed is how a subscription
        # accumulates the leftovers that block the next run's preflight.
        $seen = [System.Collections.Generic.List[string]]::new()
        $runner = { param($Invocation) $seen.Add($Invocation.Lab); if ($seen.Count -eq 1) { 1 } else { 0 } }.GetNewClosure()

        $result = & $script:RemoveCycle -SubscriptionId 'fixture-subscription' -ManifestPath $script:TeardownManifest `
            -TeardownRunner $runner -Confirm:$false `
            -LogDirectory $script:OfflinePaths.LogDirectory -ResultsPath $script:OfflinePaths.ResultsPath `
            @script:CleanProbes

        $seen.Count | Should -Be 2
        $result.TeardownFailedCount | Should -Be 1
    }

    It 'exits with the failure count' {
        & $script:RemoveCycle -SubscriptionId 'fixture-subscription' -ManifestPath $script:TeardownManifest `
            -TeardownRunner { 1 } -Confirm:$false `
            -LogDirectory $script:OfflinePaths.LogDirectory -ResultsPath $script:OfflinePaths.ResultsPath `
            @script:CleanProbes | Out-Null
        $LASTEXITCODE | Should -Be 2
    }

    It 'reports documented residue without counting it as a failure' {
        $result = & $script:RemoveCycle -SubscriptionId 'fixture-subscription' -ManifestPath $script:TeardownManifest `
            -TeardownRunner { 0 } -Confirm:$false `
            -LogDirectory $script:OfflinePaths.LogDirectory -ResultsPath $script:OfflinePaths.ResultsPath `
            @script:CleanProbes

        @($result.LeftBehind).Count | Should -Be 1
        $result.TeardownFailedCount | Should -Be 0
    }

    It 'deletes nothing under -WhatIf' {
        $ran = New-CallCounter
        $runner = { $ran.Count++; 0 }.GetNewClosure()
        $deleted = New-CallCounter
        $remover = { $deleted.Count++; $null }.GetNewClosure()

        $probes = @{} + $script:CleanProbes
        $probes.ResourceGroupRemover = $remover
        $probes.ResourceGroupProbe   = { 'still here' }
        $probes.BackupResourceGroupProbe = { @(@{ Name = 'AzureBackupRG_swedencentral_1'; ResourceTypes = @('Microsoft.Compute/restorePointCollections') }) }

        & $script:RemoveCycle -SubscriptionId 'fixture-subscription' -ManifestPath $script:TeardownManifest `
            -TeardownRunner $runner -WhatIf `
            -LogDirectory $script:OfflinePaths.LogDirectory -ResultsPath $script:OfflinePaths.ResultsPath `
            @probes | Out-Null

        $ran.Count | Should -Be 0 -Because '-WhatIf must not run a lab''s teardown script'
        $deleted.Count | Should -Be 0 -Because '-WhatIf must not delete a resource group'
    }

    It 'refuses to start on an out-of-date az CLI, and deletes nothing' {
        $ran = New-CallCounter
        $runner = { $ran.Count++; 0 }.GetNewClosure()
        $probes = @{} + $script:CleanProbes
        $probes.ToolingFloorRunner = { @(@{ Name = 'az CLI version'; Ok = $false; Detail = 'too old'; Severity = 'Info' }) }

        & $script:RemoveCycle -SubscriptionId 'fixture-subscription' -ManifestPath $script:TeardownManifest `
            -TeardownRunner $runner -Confirm:$false `
            -LogDirectory $script:OfflinePaths.LogDirectory -ResultsPath $script:OfflinePaths.ResultsPath `
            @probes | Out-Null

        $LASTEXITCODE | Should -Be 3
        $ran.Count | Should -Be 0 -Because 'learning this after fifteen labs have been removed is the failure the up-front check exists to prevent'
    }

    It 'refuses to start when the context is on the wrong subscription' {
        $probes = @{} + $script:CleanProbes
        $probes.ContextProbe = { [pscustomobject]@{ Subscription = [pscustomobject]@{ Id = 'someone-elses'; Name = 'fixture' } } }

        & $script:RemoveCycle -SubscriptionId 'fixture-subscription' -ManifestPath $script:TeardownManifest `
            -TeardownRunner { 0 } -Confirm:$false `
            -LogDirectory $script:OfflinePaths.LogDirectory -ResultsPath $script:OfflinePaths.ResultsPath `
            @probes | Out-Null

        $LASTEXITCODE | Should -Be 3
    }
}

Describe 'Teardown - the residue sweep' {
    BeforeAll {
        $script:SweepManifest = New-FixtureManifest -Body @'
@{
    Phases = @()
    SoftDeleteGuards = @()
    CompileOnly = @()
    Teardowns = @()
    ResidualSweep = @{
        BackupResourceGroupPrefix = 'AzureBackupRG_'
        AssertAbsent = @(
            @{ Kind = 'RecoveryServicesVault'; Name = 'platform-skycraft-swc-rsv'; ResourceGroup = 'platform-skycraft-swc-rg' }
        )
        ResourceGroups = @('dev-skycraft-swc-rg')
    }
    ToolingFloor = @{ AzCli = '2.75.0'; AzPowerShell = '7.5.0' }
}
'@
        $script:SweepBase = @{
            ContextProbe       = $script:GoodContext
            ToolingFloorRunner = { @() }
            TeardownRunner     = { 0 }
        }
    }

    It 'deletes an AzureBackupRG group that holds only restore point collections' {
        $deleted = [System.Collections.Generic.List[string]]::new()
        $probes = @{} + $script:SweepBase
        $probes.BackupResourceGroupProbe = { @(@{ Name = 'AzureBackupRG_swedencentral_1'; ResourceTypes = @('Microsoft.Compute/restorePointCollections') }) }
        $probes.ResourceGroupRemover = { param($Name) $deleted.Add($Name); $null }.GetNewClosure()
        $probes.ResourceGroupProbe = { $null }
        $probes.VaultProbe = { $null }

        & $script:RemoveCycle -SubscriptionId 'fixture-subscription' -ManifestPath $script:SweepManifest `
            -Confirm:$false -LogDirectory $script:OfflinePaths.LogDirectory `
            -ResultsPath $script:OfflinePaths.ResultsPath @probes | Out-Null

        @($deleted) | Should -Contain 'AzureBackupRG_swedencentral_1'
    }

    It 'leaves an AzureBackupRG group holding anything else standing, and says so' {
        # A group by that name holding something else is not the group the rule means. Deleting it
        # on a name match would be the sweep doing the exact damage it exists to prevent.
        $deleted = [System.Collections.Generic.List[string]]::new()
        $probes = @{} + $script:SweepBase
        $probes.BackupResourceGroupProbe = { @(@{ Name = 'AzureBackupRG_swedencentral_1'; ResourceTypes = @('Microsoft.Compute/restorePointCollections', 'Microsoft.Storage/storageAccounts') }) }
        $probes.ResourceGroupRemover = { param($Name) $deleted.Add($Name); $null }.GetNewClosure()
        $probes.ResourceGroupProbe = { $null }
        $probes.VaultProbe = { $null }

        $result = & $script:RemoveCycle -SubscriptionId 'fixture-subscription' -ManifestPath $script:SweepManifest `
            -Confirm:$false -LogDirectory $script:OfflinePaths.LogDirectory `
            -ResultsPath $script:OfflinePaths.ResultsPath @probes

        @($deleted) | Should -Not -Contain 'AzureBackupRG_swedencentral_1'
        @($result.LeftBehind | Where-Object { $_.What -match 'AzureBackupRG' }).Count | Should -Be 1
    }

    It 'fails when a vault survived, rather than recording it as expected residue' {
        # The correction issue #73 carries: a surviving vault is a failure. Treating it as residue
        # is how this repository spent months believing in a 14-day wait that was not there.
        $probes = @{} + $script:SweepBase
        $probes.BackupResourceGroupProbe = { @() }
        $probes.ResourceGroupRemover = { $null }
        $probes.ResourceGroupProbe = { $null }
        $probes.VaultProbe = { 'the vault is still here' }

        $result = & $script:RemoveCycle -SubscriptionId 'fixture-subscription' -ManifestPath $script:SweepManifest `
            -Confirm:$false -LogDirectory $script:OfflinePaths.LogDirectory `
            -ResultsPath $script:OfflinePaths.ResultsPath @probes

        $result.AssertionFailedCount | Should -BeGreaterThan 0
        $LASTEXITCODE | Should -BeGreaterThan 0
    }

    It 'fails when a lab resource group survived' {
        $probes = @{} + $script:SweepBase
        $probes.BackupResourceGroupProbe = { @() }
        $probes.ResourceGroupRemover = { $null }
        # Present before the delete and still present after it: a delete that reported success and
        # did not happen.
        $probes.ResourceGroupProbe = { 'still here' }
        $probes.VaultProbe = { $null }

        $result = & $script:RemoveCycle -SubscriptionId 'fixture-subscription' -ManifestPath $script:SweepManifest `
            -Confirm:$false -LogDirectory $script:OfflinePaths.LogDirectory `
            -ResultsPath $script:OfflinePaths.ResultsPath @probes

        $result.AssertionFailedCount | Should -BeGreaterThan 0
    }

    It 'passes every assertion on a subscription that really is clean' {
        $probes = @{} + $script:SweepBase
        $probes.BackupResourceGroupProbe = { @() }
        $probes.ResourceGroupRemover = { $null }
        $probes.ResourceGroupProbe = { $null }
        $probes.VaultProbe = { $null }

        $result = & $script:RemoveCycle -SubscriptionId 'fixture-subscription' -ManifestPath $script:SweepManifest `
            -Confirm:$false -LogDirectory $script:OfflinePaths.LogDirectory `
            -ResultsPath $script:OfflinePaths.ResultsPath @probes

        $result.AssertionFailedCount | Should -Be 0
        @($result.Assertions | Where-Object { -not $_.Ok }) | Should -BeNullOrEmpty
    }

    It 'skips the sweep and the assertions for a partial teardown' {
        # A subscription that still holds the other labs on purpose is not one to assert empty.
        $deleted = New-CallCounter
        $partialManifest = New-FixtureManifest -Body @'
@{
    Phases = @(
        @{ Id = '2.1'; Lab = 'module-2-networking/2.1-virtual-networks'; ParamFile = 'x'; Deploy = @{}; PostDeploy = $null; Test = @{}; DependsOn = @(); TimeoutMs = 1000; Excluded = $null }
    )
    SoftDeleteGuards = @()
    CompileOnly = @()
    Teardowns = @(
        @{ Lab = 'module-2-networking/2.1-virtual-networks'; Invocations = @(@{ Force = $true }); TimeoutMs = 1000 }
    )
    ResidualSweep = @{
        BackupResourceGroupPrefix = 'AzureBackupRG_'
        AssertAbsent = @(@{ Kind = 'RecoveryServicesVault'; Name = 'platform-skycraft-swc-rsv'; ResourceGroup = 'platform-skycraft-swc-rg' })
        ResourceGroups = @('dev-skycraft-swc-rg')
    }
    ToolingFloor = @{ AzCli = '2.75.0'; AzPowerShell = '7.5.0' }
}
'@
        $probes = @{} + $script:SweepBase
        $probes.BackupResourceGroupProbe = { @() }
        $probes.ResourceGroupRemover = { $deleted.Count++; $null }.GetNewClosure()
        $probes.ResourceGroupProbe = { 'still here' }
        $probes.VaultProbe = { 'still here' }

        $result = & $script:RemoveCycle -SubscriptionId 'fixture-subscription' -ManifestPath $partialManifest `
            -Labs '2.1' -Confirm:$false -LogDirectory $script:OfflinePaths.LogDirectory `
            -ResultsPath $script:OfflinePaths.ResultsPath @probes

        $deleted.Count | Should -Be 0
        @($result.Assertions).Count | Should -Be 0
        $LASTEXITCODE | Should -Be 0
    }
}

# =============================================================================================
# Gold-path standards, which issue #73 requires of both scripts
# =============================================================================================

Describe 'Gold-path standards for the orchestrator scripts' {
    It '<Name> carries Comment-Based Help' -ForEach $ToolScriptCases {
        $head = (Get-Content -LiteralPath $Path -TotalCount 60) -join "`n"
        $head | Should -Match '\.SYNOPSIS'
        $head | Should -Match '\.DESCRIPTION'
    }

    It '<Name> names the project in .NOTES' -ForEach $ToolScriptCases {
        (Get-Content -Raw -LiteralPath $Path) | Should -Match '\.NOTES'
    }

    It '<Name> declares #Requires -Version 7.0' -ForEach $ToolScriptCases {
        (Get-Content -Raw -LiteralPath $Path) | Should -Match '(?m)^#Requires -Version 7\.0\s*$'
    }

    It '<Name> declares [CmdletBinding()]' -ForEach $ToolScriptCases {
        (Get-Content -Raw -LiteralPath $Path) | Should -Match '\[CmdletBinding\('
    }

    It '<Name> sets $ErrorActionPreference to Stop' -ForEach $ToolScriptCases {
        (Get-Content -Raw -LiteralPath $Path) | Should -Match "ErrorActionPreference\s*=\s*'Stop'"
    }

    It 'Remove-LabCycle.ps1 supports ShouldProcess' {
        (Get-Content -Raw -LiteralPath (Join-Path $script:ToolsDir 'Remove-LabCycle.ps1')) |
            Should -Match '\[CmdletBinding\(SupportsShouldProcess\)\]'
    }

    It 'Remove-LabCycle.ps1 calls no Read-Host' {
        # It runs unattended at the end of a multi-hour cycle. A prompt there is a teardown that
        # silently never happened.
        #
        # Read from the AST rather than by grepping the file, because the script's own help
        # explains that it contains no Read-Host - and a text match cannot tell an explanation
        # from a call. The first version of this test failed on that sentence.
        $ast = [System.Management.Automation.Language.Parser]::ParseFile(
            (Join-Path $script:ToolsDir 'Remove-LabCycle.ps1'), [ref]$null, [ref]$null)

        $calls = @($ast.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.CommandAst] -and
            $node.GetCommandName() -eq 'Read-Host'
        }, $true))

        $calls | Should -BeNullOrEmpty
    }

    It 'the launcher shim declares no #Requires -Modules, which is the entire reason it works' {
        # A script carrying '#Requires -Modules' launched with 'pwsh -File' has its exit code
        # discarded. The shim exists to be the one process that does not.
        (Get-Content -Raw -LiteralPath (Join-Path $script:ToolsDir 'Invoke-LabScript.ps1')) |
            Should -Not -Match '(?m)^#Requires -Modules'
    }

    It 'both orchestrator scripts set the exit code through $Host.SetShouldExit as well as exit' {
        foreach ($name in 'Invoke-LabCycle.ps1', 'Remove-LabCycle.ps1') {
            (Get-Content -Raw -LiteralPath (Join-Path $script:ToolsDir $name)) |
                Should -Match 'SetShouldExit' -Because "$name reports a count that a caller has to be able to read"
        }
    }
}

Describe 'The offline suite must not write into the repository' {
    It 'creates no run artefact beside the orchestrator that was not already there' {
        # Every engine test above redirects its paths at the scratch directory. This is what
        # catches one that forgot.
        #
        # WHAT IS ASSERTED IS THE CHANGE, not the presence. A working tree where somebody has run
        # a real cycle legitimately holds tools/.lab-cycle-state.json and tools/lab-cycle-report.md
        # - both gitignored, both none of this suite's business. Comparing against the snapshot
        # taken before the first test distinguishes 'this suite wrote it' from 'it was already
        # here', which is the only distinction that matters. Asserting absence outright made this
        # test fail on a checkout where the orchestrator had simply been used.
        $created = @(
            foreach ($name in $script:RunArtefacts) {
                $now = Test-Path -LiteralPath (Join-Path $script:ToolsDir $name)
                if ($now -and -not $script:ArtefactsBefore[$name]) { $name }
            }
        )

        $created | Should -BeNullOrEmpty -Because 'a test suite that writes into tools/ leaves the next real run starting dirty'
    }

    It 'is checking a non-empty set of artefacts, so the check above cannot pass by vacuity' {
        # A difference-based assertion over an empty list passes for ever and asserts nothing. This
        # is the guard against the snapshot silently failing to populate - which is exactly the
        # failure mode that makes a green suite worth less than no suite.
        @($script:RunArtefacts).Count | Should -BeGreaterThan 0
        $script:ArtefactsBefore.Keys.Count | Should -Be @($script:RunArtefacts).Count
    }
}
