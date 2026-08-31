<#
.SYNOPSIS
    Pester 5 test: a non-zero `exit` in an automation script reaches the process exit code.

.DESCRIPTION
    Regression guard for issue #104 (Lab 2.1 cleanup reported failures but exited 0).

    PowerShell 7 drops the exit code of a script that is run as `pwsh -File` when that
    script declares `#Requires -Modules` for a module it has to auto-import - every Az.*
    module in this repository qualifies. The `exit <code>` statement still unwinds the
    script (its `finally` blocks run, its output is flushed), but the host never applies
    the code, so the process exits 0. The same script exits correctly when it is dot-called
    or invoked with `-Command`, which is why the fault only shows up in the automated lab
    cycle - exactly where a masked failure is most expensive.

    The supported workaround is to set the code on the host explicitly, immediately before
    the `exit`:

        $Host.SetShouldExit(1)
        exit 1

    This file enforces both halves of that contract:
      - structurally, that every non-zero `exit` in module-*/scripts/*.ps1 is preceded by a
        matching $Host.SetShouldExit call, so the guard cannot be dropped by a later edit;
      - behaviourally, that the idiom really does carry the code through `pwsh -File` on the
        PowerShell and Az.Accounts actually installed on this machine.

.EXAMPLE
    Invoke-Pester -Path .\tests\Exit-Code-Propagation.Tests.ps1

.NOTES
    Project: SkyCraft
#>

#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path

# Every non-zero `exit` site in the automation scripts, with the statement that precedes it.
# Parsed rather than regex-matched so that `exit` inside a string or a comment is not counted
# and the preceding statement is identified reliably.
function Get-ExitSite {
    param([string]$Path)

    $tokens = $null
    $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$tokens, [ref]$errors)

    foreach ($exit in $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.ExitStatementAst] }, $true)) {

        $code = if ($exit.Pipeline) { $exit.Pipeline.Extent.Text.Trim() } else { '0' }

        # `exit 0` is the success path - it needs no guard, because 0 is what a dropped
        # exit code degrades to anyway.
        if ($code -eq '0') { continue }

        $statements = @($exit.Parent.Statements)
        $index = -1
        for ($i = 0; $i -lt $statements.Count; $i++) {
            if ($statements[$i].Extent.StartOffset -eq $exit.Extent.StartOffset) { $index = $i; break }
        }

        $previous = if ($index -gt 0) { $statements[$index - 1].Extent.Text.Trim() } else { '' }

        [PSCustomObject]@{
            Line     = $exit.Extent.StartLineNumber
            Code     = $code
            Previous = $previous
        }
    }
}

# Path matching is separator-agnostic so the suite runs identically on the Windows dev box
# and the Linux CI runner.
$ExitCases = Get-ChildItem -Path $RepoRoot -Recurse -File -Filter '*.ps1' |
             Where-Object { (($_.FullName.Substring($RepoRoot.Length + 1)) -replace '\\', '/') -match '^(module-\d.*/)?(scripts|tools)/' } |
             ForEach-Object {
                 $file = $_.FullName.Substring($RepoRoot.Length + 1) -replace '\\', '/'
                 foreach ($site in Get-ExitSite -Path $_.FullName) {
                     @{
                         file     = $file
                         line     = $site.Line
                         code     = $site.Code
                         previous = $site.Previous
                     }
                 }
             }

Describe 'SkyCraft PowerShell - a non-zero exit reaches the process exit code' {

    It "'<file>':<line> guards 'exit <code>' with `$Host.SetShouldExit(<code>)" -ForEach $ExitCases {
        # `pwsh -File` discards `exit <code>` from a script that declares #Requires -Modules
        # for an auto-imported module (issue #104), so the code must be set on the host too.
        $previous | Should -Match '^\$Host\.SetShouldExit\('

        $argument = [regex]::Match($previous, '^\$Host\.SetShouldExit\((?<arg>.*)\)$').Groups['arg'].Value.Trim()
        $argument | Should -BeExactly $code -Because 'the guard must carry the same code the exit does'
    }
}

Describe 'SkyCraft PowerShell - the SetShouldExit idiom still works on this host' {

    BeforeAll {
        $script:Pwsh = (Get-Process -Id $PID).Path
    }

    # Skipped where Az.Accounts is absent (CI), because the fault this guards against only
    # appears when #Requires has a module to auto-import.
    It 'carries a non-zero exit code out of a #Requires -Modules script run as pwsh -File' -Skip:(-not [bool](Get-Module -ListAvailable -Name Az.Accounts)) {
        $guarded = Join-Path $TestDrive 'guarded.ps1'
        @(
            '#Requires -Version 7.0'
            '#Requires -Modules Az.Accounts'
            '$Host.SetShouldExit(3)'
            'exit 3'
        ) | Set-Content -LiteralPath $guarded -Encoding utf8

        & $script:Pwsh -NoProfile -File $guarded | Out-Null
        $LASTEXITCODE | Should -Be 3
    }
}
