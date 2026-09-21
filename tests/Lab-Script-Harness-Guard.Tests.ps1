<#
.SYNOPSIS
    Pester 5 tests asserting no suite can run a lab script in a child pwsh against the real Az.

.DESCRIPTION
    Guards the rule in docs/powershell-standards.md section 6 ("Suites that run a lab script in a
    child process"), added for issue #112. A Pester suite that launches the real
    Remove-LabResource.ps1 (or any other lab script) in a child pwsh must stub every Az command
    the script calls, and two PowerShell behaviours make that fail silently: pwsh prepends its
    own module directories to any inherited PSModulePath, and '#Requires -Modules' re-imports
    the real modules after a stub, where a function-exporting module such as Az.DataProtection
    wins. Neither raises an error. The child just runs the teardown against whatever
    subscription Get-AzContext returns, and as long as the inventory matches nothing, the suite
    is green.

    tests/Support/LabScriptStub.psm1 is the one supported way to do this: real modules first,
    stub last, assert every stubbed name resolves to the stub, exit 99 otherwise. Two things
    have to stay true for that to keep protecting the repository:

      1. Every suite that launches pwsh at a lab script goes through the helper (or carries
         the same assertion and exit inline). Checked statically over every tracked suite.
      2. The helper's refusal actually fires. Checked behaviourally: a stub that fails to
         define a command it claims to export makes the child exit 99 without running the
         script, with or without Az installed.

    Suites are enumerated with 'git ls-files' so an untracked scratch file cannot fail the run.

.EXAMPLE
    Invoke-Pester -Path .\tests\Lab-Script-Harness-Guard.Tests.ps1

.NOTES
    Project: SkyCraft
    Issue: #112
#>

#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

# Discovery-phase data: -ForEach evaluates here, not in BeforeAll. The classifier lives in the
# helper module so this suite and the helper cannot drift apart; it is imported again in
# BeforeAll because a run-phase block cannot see discovery-phase state.
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
Import-Module (Join-Path $PSScriptRoot 'Support' 'LabScriptStub.psm1') -Force

Push-Location $RepoRoot
try {
    $AllSuites = @(git ls-files -- '*.Tests.ps1' | ForEach-Object { $_ -replace '\\', '/' })
} finally { Pop-Location }

$SuiteCases = @(
    foreach ($suite in $AllSuites) {
        $verdict = Test-LabScriptHarnessText -Text (Get-Content -Raw -LiteralPath (Join-Path $RepoRoot $suite))
        @{ suite = $suite; isHarness = $verdict.IsHarness; guarded = $verdict.Guarded; launchesChild = $verdict.LaunchesChild }
    }
)
$HarnessCases = @($SuiteCases | Where-Object { $_.isHarness })

Describe 'Lab-script harness guard - static rule' {

    BeforeAll {
        Import-Module (Join-Path $PSScriptRoot 'Support' 'LabScriptStub.psm1') -Force
    }

    It 'recognises the Lab 5.2 suite as a child-process harness' -ForEach @(@{ harnesses = @($HarnessCases.suite) }) {
        # The one known harness must be a case, or the rule below is vacuous.
        $harnesses | Should -Contain 'module-5-monitoring-maintenance/5.2-business-continuity/tests/Remove-LabResource.Tests.ps1'
    }

    It "'<suite>' runs its lab script through tests/Support/LabScriptStub.psm1" -ForEach $HarnessCases {
        $guarded | Should -BeTrue `
            -Because 'a child pwsh binds the real Az cmdlets unless the stub is imported last and asserted (powershell-standards.md section 6, issue #112)'
    }

    It 'flags a suite that launches pwsh at a lab script without the helper or the inline guard' {
        $unguarded = @'
$scriptPath = Join-Path $PSScriptRoot '..' 'scripts' 'Remove-LabResource.ps1'
$output = & pwsh -NoProfile -Command "& '$scriptPath' -Force"
'@
        $verdict = Test-LabScriptHarnessText -Text $unguarded
        $verdict.LaunchesChild | Should -BeTrue
        $verdict.IsHarness     | Should -BeTrue
        $verdict.Guarded       | Should -BeFalse
    }

    It 'accepts the inline form only when both the Source assertion and exit 99 are present' {
        $assertionOnly = '$bad = $names | Where-Object { (Get-Command $_).Source -ne "Stub" }'
        $exitOnly      = "if (`$bad) { exit 99 }"
        (Test-LabScriptHarnessText -Text $assertionOnly).Guarded | Should -BeFalse
        (Test-LabScriptHarnessText -Text $exitOnly).Guarded      | Should -BeFalse
        (Test-LabScriptHarnessText -Text ($assertionOnly + "`n" + $exitOnly)).Guarded | Should -BeTrue
    }

    It 'treats a mention of pwsh in a comment or a test name as no launch' {
        $verdict = Test-LabScriptHarnessText -Text @'
# A script launched with 'pwsh -File' loses its exit code.
It 'returns what pwsh -File would have discarded' { }
'@
        $verdict.LaunchesChild | Should -BeFalse
    }

    # These suites launch pwsh, at tools/ scripts with no Az surface or at $TestDrive fixtures.
    # They must not be flagged, or the rule becomes noise that gets deleted.
    It "'<suite>' launches pwsh at a tools script or a fixture and is not a harness" -ForEach @(
        $SuiteCases | Where-Object {
            $_.suite -in 'tests/Avm-Module-Update.Tests.ps1', 'tests/DryRun-Pester-Gate.Tests.ps1',
                         'tests/Exit-Code-Propagation.Tests.ps1', 'tests/Workflow-Exit-Gating.Tests.ps1'
        }
    ) {
        $launchesChild | Should -BeTrue -Because 'the case exists to prove a tools/fixture launch is not flagged'
        $isHarness     | Should -BeFalse
    }

    It "'<suite>' names lab scripts but never launches pwsh itself, so it is not a harness" -ForEach @(
        $SuiteCases | Where-Object { $_.suite -eq 'tests/LabCycle.Tests.ps1' }
    ) {
        $launchesChild | Should -BeFalse
        $isHarness     | Should -BeFalse
    }
}

Describe 'Lab-script harness guard - the helper refuses a half-stubbed child' {

    BeforeAll {
        Import-Module (Join-Path $PSScriptRoot 'Support' 'LabScriptStub.psm1') -Force

        # A stand-in lab script: declares a real Az module, calls one Az command, reports
        # through its exit code whether it saw the stub, and leaves a marker in the output so
        # the refusal test can prove the script never started.
        $script:Target = Join-Path $TestDrive 'Fake-LabScript.ps1'
        @'
#Requires -Modules Az.Accounts
Write-Host 'TARGET-RAN'
$context = Get-AzContext
if ($context.Name -ne 'stub-context') { exit 5 }
exit 7
'@ | Set-Content -LiteralPath $script:Target -Encoding utf8

        $script:Stubs = [System.Collections.Generic.List[object]]::new()
    }

    AfterAll {
        foreach ($stub in $script:Stubs) {
            Remove-Item -LiteralPath $stub.Directory -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'runs the script and returns its exit code when every command resolves to the stub' {
        $stub = Initialize-LabScriptStub -Name 'SkyCraftGuardStub' -Command 'Get-AzContext' -RequiredModule 'Az.Accounts' `
            -Body "function Get-AzContext { [pscustomobject]@{ Name = 'stub-context' } }"
        $script:Stubs.Add($stub)

        $run = Invoke-LabScriptWithStub -Stub $stub -ScriptPath $script:Target

        $run.Refused  | Should -BeFalse -Because "output was:`n$($run.Output)"
        $run.ExitCode | Should -Be 7 -Because "the script saw the stub context and exited 7; output was:`n$($run.Output)"
        $run.Output   | Should -Match 'TARGET-RAN'
    }

    It 'exits 99 without running the script when a claimed command does not resolve to the stub' {
        # The stub claims Get-AzContext but never defines it, so the name resolves to the real
        # Az.Accounts where one is installed and to nothing where it is not. Both must refuse:
        # this is exactly the half-stubbed session that issue #112 describes.
        $stub = Initialize-LabScriptStub -Name 'SkyCraftGuardStub' -Command 'Get-AzContext' -RequiredModule 'Az.Accounts' `
            -Body "function Get-AzUnrelated { 'never called' }"
        $script:Stubs.Add($stub)

        $run = Invoke-LabScriptWithStub -Stub $stub -ScriptPath $script:Target

        $run.Refused  | Should -BeTrue -Because "output was:`n$($run.Output)"
        $run.ExitCode | Should -Be 99
        $run.Output   | Should -Match '\[HARNESS\] Az stubs are not in effect for: Get-AzContext'
        $run.Output   | Should -Not -Match 'TARGET-RAN' -Because 'the refusal must happen before the script starts'
    }

    It 'passes the environment to the child and restores it afterwards' {
        $stub = Initialize-LabScriptStub -Name 'SkyCraftGuardStub' -Command 'Get-AzContext' -RequiredModule 'Az.Accounts' `
            -Body "function Get-AzContext { [pscustomobject]@{ Name = `$env:SKYCRAFT_GUARD_CONTEXT } }"
        $script:Stubs.Add($stub)
        $env:SKYCRAFT_GUARD_CONTEXT = 'before'
        $savedModulePath = $env:PSModulePath

        $run = Invoke-LabScriptWithStub -Stub $stub -ScriptPath $script:Target -Environment @{ SKYCRAFT_GUARD_CONTEXT = 'stub-context' }

        $run.ExitCode               | Should -Be 7 -Because "output was:`n$($run.Output)"
        $env:SKYCRAFT_GUARD_CONTEXT | Should -Be 'before'
        $env:PSModulePath           | Should -Be $savedModulePath
        Remove-Item Env:\SKYCRAFT_GUARD_CONTEXT -ErrorAction SilentlyContinue
    }
}
