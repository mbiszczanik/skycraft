<#
.SYNOPSIS
    Pester 5 wrapper that runs the Python unit tests of the screenshot age report (tools/screenshot-age).

.DESCRIPTION
    The report tool is standard-library Python, so its unittest file under
    tools/screenshot-age/tests/ runs as one It here and the existing CI job, which runs every
    Pester file under tests/, covers it without a new step. Python is started with -B so that no
    __pycache__ is written into the working tree.

.EXAMPLE
    Invoke-Pester -Path .\tests\Screenshot-Age-Python.Tests.ps1

.NOTES
    Project: SkyCraft
    Issue:   #486
#>

#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    $script:Python   = if ($IsWindows) { 'python' } else { 'python3' }
}

Describe 'tools/screenshot-age Python unit tests (report)' {
    It 'pass' {
        Push-Location $script:RepoRoot
        try {
            $output = & $script:Python -B -m unittest discover -s tools/screenshot-age/tests -v 2>&1 | Out-String
            $exitCode = $LASTEXITCODE
        } finally { Pop-Location }
        $exitCode | Should -Be 0 -Because "the unit tests must pass. Output:`n$output"
    }
}
