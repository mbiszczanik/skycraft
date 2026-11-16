<#
.SYNOPSIS
    Pester 5 wrapper that runs the Python unit tests of the unused-images report (tools/unused-images).

.DESCRIPTION
    The report is stdlib Python, so its unittest file runs as one It and the existing CI job
    covers it without a new step. Python is started with -B so no __pycache__ lands in the tree.

.EXAMPLE
    Invoke-Pester -Path .\tests\Unused-Images-Python.Tests.ps1

.NOTES
    Project: SkyCraft
    Issue:   #487
#>

#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    $script:Python   = if ($IsWindows) { 'python' } else { 'python3' }
}

Describe 'tools/unused-images Python unit tests (report)' {
    It 'pass' {
        Push-Location $script:RepoRoot
        try {
            $output = & $script:Python -B -m unittest discover -s tools/unused-images/tests -v 2>&1 | Out-String
            $exitCode = $LASTEXITCODE
        } finally { Pop-Location }
        $exitCode | Should -Be 0 -Because "the unit tests must pass. Output:`n$output"
    }
}
