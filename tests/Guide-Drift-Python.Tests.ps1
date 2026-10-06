<#
.SYNOPSIS
    Pester 5 wrapper that runs every Python unit test of the guide drift tool (tools/guide-drift).

.DESCRIPTION
    The guide drift tool is Python, and the repository has no pytest, so its unit tests are
    stdlib unittest files under tools/guide-drift/tests/: test_decide.py (decide.py, the boundary
    every "label not found" decision passes through), test_redact.py (recording.py: redaction,
    environment references, values, atomic writes) and test_runner.py (run.py's bookkeeping:
    state, resume, failure prompts, decisions, summary). This file discovers and runs all of them
    as one It, so the existing CI job, which runs every Pester file under tests/, covers them on
    the ubuntu-latest runner without a new step and without Playwright (test_runner.py stubs it).
    Python is started with -B so that no __pycache__ is written into the working tree.

.EXAMPLE
    Invoke-Pester -Path .\tests\Guide-Drift-Python.Tests.ps1

.NOTES
    Project: SkyCraft
    Issue:   #189
#>

#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    $script:Python   = if ($IsWindows) { 'python' } else { 'python3' }
}

Describe 'tools/guide-drift Python unit tests (decide, redact, runner)' {
    It 'pass' {
        Push-Location $script:RepoRoot
        try {
            $output = & $script:Python -B -m unittest discover -s tools/guide-drift/tests -v 2>&1 | Out-String
            $exitCode = $LASTEXITCODE
        } finally { Pop-Location }
        $exitCode | Should -Be 0 -Because "the unit tests must pass. Output:`n$output"
    }
}
