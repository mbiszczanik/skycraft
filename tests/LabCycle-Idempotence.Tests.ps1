<#
.SYNOPSIS
    Pester 5 tests for the -IdempotencePass switch of tools/Invoke-LabCycle.ps1 (#525).

.DESCRIPTION
    Runs the real Invoke-LabCycle.ps1 against a fixture manifest with a fake PhaseRunner, so
    nothing here starts a lab script or reaches Azure. The isolation is the one
    tests/LabCycle.Tests.ps1 applies (tests/Support/LabCycleIsolation.psm1): every [scriptblock]
    parameter of the orchestrators gets a poisoned default and every Az command they name is
    shadowed by a global function that records its name before it throws. The last test fails if
    anything reached one.

    Covered: the switch off, both second runs passing, the second Deploy failing, the second Test
    failing, a failed first run, and -DryRun. A finding must leave the phase status, its
    dependents and the exit code as they were.

.EXAMPLE
    Invoke-Pester -CI -Path .\tests\LabCycle-Idempotence.Tests.ps1

.NOTES
    Project: SkyCraft
    Issue:   #525
#>

#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

Import-Module (Join-Path (Join-Path $PSScriptRoot 'Support') 'LabCycleIsolation.psm1') -Force

BeforeAll {
    $script:ToolsDir   = Join-Path (Resolve-Path (Join-Path $PSScriptRoot '..')).Path 'tools'
    $script:InvokeCycle = Join-Path $script:ToolsDir 'Invoke-LabCycle.ps1'
    Import-Module (Join-Path (Join-Path $PSScriptRoot 'Support') 'LabCycleIsolation.psm1') -Force

    # -- Isolation, as in tests/LabCycle.Tests.ps1 (#152) ----------------------------------------
    $script:PoisonLedger = [System.Collections.Generic.List[string]]::new()
    function Get-Poison {
        param([Parameter(Mandatory)][string]$Name)
        $ledger = $script:PoisonLedger
        $label  = $Name
        { $ledger.Add($label); throw "LabCycle-Idempotence.Tests reached '$label', a real default that talks to Azure or starts a lab script. Override it in the call." }.GetNewClosure()
    }

    $orchestrators = @((Join-Path $script:ToolsDir 'Invoke-LabCycle.ps1'), (Join-Path $script:ToolsDir 'Remove-LabCycle.ps1'))
    $defaults = @{}
    foreach ($key in @($global:PSDefaultParameterValues.Keys)) { $defaults[$key] = $global:PSDefaultParameterValues[$key] }
    foreach ($key in @(Get-LabCycleScriptblockParameter -Path $orchestrators | ForEach-Object { $_.Key })) {
        $poison = Get-Poison -Name $key
        $defaults[$key] = { $poison }.GetNewClosure()
    }
    $script:PSDefaultParameterValues = $defaults

    $script:AzCommands = @(Get-LabCycleAzCommand -Path ($orchestrators + (Join-Path $script:ToolsDir 'LabCycle.psm1')))
    foreach ($name in $script:AzCommands) {
        Set-Item -LiteralPath "Function:\global:$name" -Value (Get-Poison -Name $name)
    }

    $script:GoodContext = { [pscustomobject]@{ Subscription = [pscustomobject]@{ Id = 'fixture-subscription'; Name = 'fixture' } } }

    $script:Scratch = Join-Path ([System.IO.Path]::GetTempPath()) "labcycle-idem-$([guid]::NewGuid().ToString('N'))"
    New-Item -ItemType Directory -Path $script:Scratch -Force | Out-Null

    # 'beta' depends on 'alpha' and 'staged' has a PostDeploy step, so a rerun that reached a
    # dependent or repeated PostDeploy shows up in the call list. 'noval' has its Test excluded.
    $script:ManifestPath = Join-Path $script:Scratch 'manifest.psd1'
    Set-Content -LiteralPath $script:ManifestPath -Value @'
@{
    Phases = @(
        @{ Id = 'alpha';  Lab = 'module-1-identities-governance/1.2-rbac'; ParamFile = 'x'; Deploy = @{ Marker = 'deploy-arg' }; PostDeploy = $null; Test = @{ Marker = 'test-arg' }; DependsOn = @(); TimeoutMs = 1000; Excluded = $null }
        @{ Id = 'beta';   Lab = 'module-1-identities-governance/1.3-governance'; ParamFile = 'x'; Deploy = @{}; PostDeploy = $null; Test = @{}; DependsOn = @('alpha'); TimeoutMs = 1000; Excluded = $null }
        @{ Id = 'staged'; Lab = 'module-5-monitoring-maintenance/5.2-business-continuity'; ParamFile = 'x'; Deploy = @{}; PostDeploy = @{ Script = 'New-LabBlobBackup.ps1'; Arguments = @{} }; Test = @{}; DependsOn = @(); TimeoutMs = 1000; Excluded = $null }
        @{ Id = 'noval';  Lab = 'module-2-networking/2.1-virtual-networks'; ParamFile = 'x'; Deploy = @{}; PostDeploy = $null; Test = $null; TestExcluded = 'fixture: not checkable here'; DependsOn = @(); TimeoutMs = 1000; Excluded = $null }
    )
    SoftDeleteGuards = @()
    CompileOnly = @()
    Teardowns = @()
}
'@

    # A runner that records every call as 'phase:Kind:pass' and returns the exit code the Fail map
    # names for that key (default 0). Locals are copied before the closure, which the analyzer follows.
    function New-FakeRunner {
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseShouldProcessForStateChangingFunctions", "", Justification = "Builds an in-memory fake.")]
        [CmdletBinding()]
        param([hashtable]$Fail = @{})
        $seen = [System.Collections.Generic.List[string]]::new()
        $args2 = [System.Collections.Generic.List[hashtable]]::new()
        $failures = $Fail
        $runner = {
            param($Invocation)
            $key = "$($Invocation.Phase.Id):$($Invocation.Kind):$($Invocation.Pass)"
            $seen.Add($key)
            $args2.Add(@{ Key = $key; Arguments = $Invocation.Arguments })
            if ($failures.ContainsKey($key)) { return [int]$failures[$key] }
            0
        }.GetNewClosure()
        @{ Runner = $runner; Seen = $seen; Arguments = $args2 }
    }

    function Invoke-FixtureCycle {
        param([hashtable]$Fake, [switch]$IdempotencePass, [switch]$DryRun)
        $name = [guid]::NewGuid().ToString('N')
        $paths = @{
            LogDirectory = (Join-Path $script:Scratch "logs-$name")
            ReportPath   = (Join-Path $script:Scratch "report-$name.md")
            ResultsPath  = (Join-Path $script:Scratch "results-$name.jsonl")
            LockPath     = (Join-Path $script:Scratch "lock-$name.json")
            StatePath    = (Join-Path $script:Scratch "state-$name.json")
        }
        $result = & $script:InvokeCycle -SubscriptionId 'fixture-subscription' -ManifestPath $script:ManifestPath `
            -PhaseRunner $Fake.Runner -PreflightRunner { @() } -ContextProbe $script:GoodContext `
            -Yes -SkipCleanup -IdempotencePass:$IdempotencePass -DryRun:$DryRun @paths
        $exit = $LASTEXITCODE
        $lines = if (Test-Path -LiteralPath $paths.ResultsPath) { @(Get-Content -LiteralPath $paths.ResultsPath | ForEach-Object { $_ | ConvertFrom-Json }) } else { @() }
        @{
            Result = $result; Exit = $exit; Lines = $lines
            Report = (Get-Content -Raw -LiteralPath $paths.ReportPath)
            Idempotence = @($lines | Where-Object { $_.Kind -eq 'Idempotence' })
        }
    }

    function Get-Phase {
        param($Run, [string]$Id)
        $Run.Result.Phases | Where-Object { $_.Id -eq $Id }
    }
}

AfterAll {
    if ($script:Scratch -and (Test-Path -LiteralPath $script:Scratch)) {
        Remove-Item -LiteralPath $script:Scratch -Recurse -Force -ErrorAction SilentlyContinue
    }
    # Unqualified, as in tests/LabCycle.Tests.ps1: Remove-Item ignores 'global:' on the Function drive.
    foreach ($name in @($script:AzCommands)) {
        Remove-Item -LiteralPath "Function:\$name" -ErrorAction SilentlyContinue
    }
}

Describe 'Idempotence pass off (the default)' {
    BeforeAll {
        $script:Fake = New-FakeRunner
        $script:Off  = Invoke-FixtureCycle -Fake $script:Fake
    }

    It 'runs exactly the steps it ran before, every one as pass 1' {
        @($script:Fake.Seen) | Should -Be @(
            'alpha:Deploy:1', 'alpha:Test:1', 'beta:Deploy:1', 'beta:Test:1',
            'staged:Deploy:1', 'staged:PostDeploy:1', 'staged:Test:1', 'noval:Deploy:1'
        )
    }

    It 'writes no idempotence record and no Idempotence section' {
        @($script:Off.Idempotence).Count | Should -Be 0
        @($script:Off.Result.Idempotence).Count | Should -Be 0
        $script:Off.Report | Should -Not -Match '## Idempotence'
        $script:Off.Exit | Should -Be 0
    }
}

Describe 'Idempotence pass on, both second runs exit 0' {
    BeforeAll {
        $script:Fake = New-FakeRunner
        $script:Run  = Invoke-FixtureCycle -Fake $script:Fake -IdempotencePass
    }

    It 'reruns Deploy and then Test of each phase, after its first run and before the next phase' {
        @($script:Fake.Seen) | Should -Be @(
            'alpha:Deploy:1', 'alpha:Test:1', 'alpha:Deploy:2', 'alpha:Test:2',
            'beta:Deploy:1', 'beta:Test:1', 'beta:Deploy:2', 'beta:Test:2',
            'staged:Deploy:1', 'staged:PostDeploy:1', 'staged:Test:1', 'staged:Deploy:2', 'staged:Test:2',
            'noval:Deploy:1', 'noval:Deploy:2'
        )
    }

    It 'does not repeat PostDeploy' {
        @($script:Fake.Seen | Where-Object { $_ -like '*:PostDeploy:*' }).Count | Should -Be 1
    }

    It 'passes the second run the same arguments as the first' {
        $deploy1 = $script:Fake.Arguments | Where-Object { $_.Key -eq 'alpha:Deploy:1' }
        $deploy2 = $script:Fake.Arguments | Where-Object { $_.Key -eq 'alpha:Deploy:2' }
        $test1   = $script:Fake.Arguments | Where-Object { $_.Key -eq 'alpha:Test:1' }
        $test2   = $script:Fake.Arguments | Where-Object { $_.Key -eq 'alpha:Test:2' }
        $deploy2.Arguments.Marker | Should -Be 'deploy-arg'
        $deploy2.Arguments.Marker | Should -Be $deploy1.Arguments.Marker
        $test2.Arguments.Marker   | Should -Be $test1.Arguments.Marker
    }

    It 'records every rerun lab as Idempotent in the results file and the report' {
        @($script:Run.Idempotence).Count | Should -Be 4
        @($script:Run.Idempotence | Where-Object { $_.Status -ne 'Idempotent' }).Count | Should -Be 0
        $alpha = $script:Run.Idempotence | Where-Object { $_.Id -eq 'alpha' }
        $alpha.DeployExitCode | Should -Be 0
        $alpha.TestExitCode   | Should -Be 0
        $script:Run.Report | Should -Match '## Idempotence'
        $script:Run.Report | Should -Match '\| alpha \| .* \| Idempotent \| 0 \| 0 \|'
        $script:Run.Report | Should -Not -Match 'NotIdempotent \|'
    }

    It 'leaves the phase results and the exit code as in a run without the switch' {
        @($script:Run.Result.Phases | Where-Object { $_.Status -eq 'Succeeded' }).Count | Should -Be 4
        $script:Run.Result.FailedCount | Should -Be 0
        $script:Run.Exit | Should -Be 0
    }
}

Describe 'Idempotence pass on, the second Deploy exits non-zero' {
    BeforeAll {
        $script:Fake = New-FakeRunner -Fail @{ 'alpha:Deploy:2' = 5 }
        $script:Run  = Invoke-FixtureCycle -Fake $script:Fake -IdempotencePass
    }

    It 'records NotIdempotent with both exit codes, in the results file and in the report' {
        $alpha = $script:Run.Idempotence | Where-Object { $_.Id -eq 'alpha' }
        $alpha.Status         | Should -Be 'NotIdempotent'
        $alpha.DeployExitCode | Should -Be 5
        $alpha.TestExitCode   | Should -Be 0
        $script:Run.Report | Should -Match '\| alpha \| .* \| NotIdempotent \| 5 \| 0 \|'
    }

    It 'does not report that lab as an idempotence pass, and keeps the other labs as passes' {
        @($script:Run.Idempotence | Where-Object { $_.Id -eq 'alpha' -and $_.Status -eq 'Idempotent' }).Count | Should -Be 0
        @($script:Run.Idempotence | Where-Object { $_.Status -eq 'Idempotent' }).Count | Should -Be 3
    }

    It 'leaves the first-run status, the dependents and the exit code unchanged' {
        (Get-Phase $script:Run 'alpha').Status | Should -Be 'Succeeded'
        (Get-Phase $script:Run 'beta').Status  | Should -Be 'Succeeded'
        @($script:Fake.Seen) | Should -Contain 'beta:Deploy:1'
        $script:Run.Result.FailedCount  | Should -Be 0
        $script:Run.Result.SkippedCount | Should -Be 0
        $script:Run.Exit | Should -Be 0
    }
}

Describe 'Idempotence pass on, the second Test exits non-zero' {
    BeforeAll {
        $script:Fake = New-FakeRunner -Fail @{ 'staged:Test:2' = 7 }
        $script:Run  = Invoke-FixtureCycle -Fake $script:Fake -IdempotencePass
    }

    It 'records NotIdempotent with both exit codes' {
        $staged = $script:Run.Idempotence | Where-Object { $_.Id -eq 'staged' }
        $staged.Status         | Should -Be 'NotIdempotent'
        $staged.DeployExitCode | Should -Be 0
        $staged.TestExitCode   | Should -Be 7
        $script:Run.Report | Should -Match '\| staged \| .* \| NotIdempotent \| 0 \| 7 \|'
    }

    It 'leaves the first-run status and the exit code unchanged' {
        (Get-Phase $script:Run 'staged').Status | Should -Be 'Succeeded'
        $script:Run.Result.FailedCount | Should -Be 0
        $script:Run.Exit | Should -Be 0
    }
}

Describe 'Idempotence pass on, the first run did not succeed' {
    It 'starts no second run for a phase whose Deploy failed, and still skips its dependent' {
        $fake = New-FakeRunner -Fail @{ 'alpha:Deploy:1' = 1 }
        $run  = Invoke-FixtureCycle -Fake $fake -IdempotencePass

        @($fake.Seen | Where-Object { $_ -like 'alpha:*:2' }).Count | Should -Be 0
        @($run.Idempotence | Where-Object { $_.Id -eq 'alpha' }).Count | Should -Be 0
        (Get-Phase $run 'alpha').Status | Should -Be 'Failed'
        (Get-Phase $run 'beta').Status  | Should -Be 'Skipped'
        @($fake.Seen | Where-Object { $_ -like 'beta:*' }).Count | Should -Be 0
        $run.Exit | Should -Be 1
    }

    It 'starts no second run for a phase whose Test failed, and counts it in the exit code as before' {
        $fake = New-FakeRunner -Fail @{ 'alpha:Test:1' = 1 }
        $run  = Invoke-FixtureCycle -Fake $fake -IdempotencePass

        @($fake.Seen | Where-Object { $_ -like 'alpha:*:2' }).Count | Should -Be 0
        @($run.Idempotence | Where-Object { $_.Id -eq 'alpha' }).Count | Should -Be 0
        (Get-Phase $run 'alpha').Status | Should -Be 'Failed(Test)'
        @($run.Idempotence | Where-Object { $_.Id -eq 'beta' }).Count | Should -Be 1
        $run.Exit | Should -Be 1
    }
}

Describe 'Idempotence pass with -DryRun' {
    It 'runs no step at all, so no idempotence step either' {
        $fake = New-FakeRunner
        $run  = Invoke-FixtureCycle -Fake $fake -IdempotencePass -DryRun

        @($fake.Seen).Count | Should -Be 0
        @($run.Idempotence).Count | Should -Be 0
        @($run.Result.Idempotence).Count | Should -Be 0
        $run.Report | Should -Not -Match '## Idempotence'
    }
}

Describe 'Isolation - no test reached a real default' {
    It 'recorded no hit on a poisoned parameter default or Az command' {
        @($script:PoisonLedger) | Should -BeNullOrEmpty
    }
}
