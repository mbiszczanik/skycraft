<#
.SYNOPSIS
    Pester 5 wrapper that runs the Python unit tests of tools/guide-drift/decide.py.

.DESCRIPTION
    decide.py is the one boundary every "label not found" decision of the guide drift tool passes
    through: replay from the committed recording, or ask the person at the keyboard. Its tests are
    stdlib unittest (tools/guide-drift/tests/test_decide.py), because the tool is Python and the
    repository has no pytest. This file runs them as one It so that the existing CI job, which
    runs every Pester file under tests/, covers them on the ubuntu-latest runner without a new
    step. Python is started with -B so that no __pycache__ is written into the working tree.

.EXAMPLE
    Invoke-Pester -Path .\tests\Guide-Drift-Decide.Tests.ps1

.NOTES
    Project: SkyCraft
    Issue:   #189
#>

#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    $script:Python   = if ($IsWindows) { 'python' } else { 'python3' }
}

Describe 'tools/guide-drift/decide.py' {
    It 'passes its unit tests' {
        Push-Location $script:RepoRoot
        try {
            $output = & $script:Python -B -m unittest discover -s tools/guide-drift/tests -v 2>&1 | Out-String
            $exitCode = $LASTEXITCODE
        } finally { Pop-Location }
        $exitCode | Should -Be 0 -Because "the unit tests must pass. Output:`n$output"
    }
}
