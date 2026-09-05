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
      - structurally, that every non-zero `exit` in a script declaring `#Requires -Modules` is
        preceded by a matching $Host.SetShouldExit call, so the guard cannot be dropped by a
        later edit;
      - behaviourally, that the idiom really does carry the code through `pwsh -File` on the
        PowerShell and Az.Accounts actually installed on this machine.

    THE RULE FOLLOWS THE DECLARATION, NOT THE DIRECTORY (#124). A script that declares no
    `#Requires -Modules` has no module to auto-import, so `pwsh -File` carries its exit code out
    unaided and there is nothing for the guard to guard. tools/Invoke-LabScript.ps1 is the case
    that forced the point: the lab cycle's launcher shim exists precisely to be the one process
    with no module requirement - tests/LabCycle.Tests.ps1 enforces that it stays that way, and
    verifies behaviourally that a target exiting 7 arrives as 7 - and a rule scoped by directory
    demanded a $Host.SetShouldExit on all three of its exits. Every lab script declares the Az
    modules it imports and is checked exactly as before, and a tools script that adds a module
    requirement later is covered again the moment it does.

.EXAMPLE
    Invoke-Pester -Path .\tests\Exit-Code-Propagation.Tests.ps1

.NOTES
    Project: SkyCraft
#>

#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path

# Whether the fault this file guards against can reach a script at all: it needs a module to
# auto-import. Read from the parsed requirements rather than matched with a regex, so that a
# '#Requires' line quoted in the help block is not mistaken for a declaration.
function Test-RequiresModule {
    param([string]$Text)

    $ast = [System.Management.Automation.Language.Parser]::ParseInput($Text, [ref]$null, [ref]$null)
    $requirements = $ast.ScriptRequirements

    return ($null -ne $requirements -and @($requirements.RequiredModules).Count -gt 0)
}

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
             Where-Object { Test-RequiresModule -Text (Get-Content -Raw -LiteralPath $_.FullName) } |
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

$DeclaresModule = @(
    '#Requires -Version 7.0'
    '#Requires -Modules Az.Accounts'
    'exit 1'
) -join "`n"

$DeclaresVersionOnly = @(
    '#Requires -Version 7.0'
    'exit 1'
) -join "`n"

$QuotesRequiresInHelp = @(
    '<#'
    '.SYNOPSIS'
    '    A script whose help block shows the declaration it does not make.'
    '.DESCRIPTION'
    '    #Requires -Modules Az.Accounts'
    '.NOTES'
    '    Project: SkyCraft'
    '#>'
    '#Requires -Version 7.0'
    'exit 1'
) -join "`n"

$ScopeCases = @(
    @{
        name     = "a script declaring '#Requires -Modules' is in scope"
        inScope  = Test-RequiresModule -Text $DeclaresModule
        expected = $true
    }
    @{
        name     = "a script declaring only '#Requires -Version' is out of scope"
        inScope  = Test-RequiresModule -Text $DeclaresVersionOnly
        expected = $false
    }
    @{
        name     = "a '#Requires -Modules' line quoted in the help block is not a declaration"
        inScope  = Test-RequiresModule -Text $QuotesRequiresInHelp
        expected = $false
    }
    @{
        name     = 'the lab cycle launcher shim, as it ships, is out of scope'
        inScope  = Test-RequiresModule -Text (Get-Content -Raw -LiteralPath (Join-Path $RepoRoot 'tools/Invoke-LabScript.ps1'))
        expected = $false
    }
)

Describe 'SkyCraft PowerShell - a non-zero exit reaches the process exit code' {

    It 'has exit sites in scope to check' -ForEach @(@{ count = @($ExitCases).Count }) {
        # A filter that matches nothing produces a Describe that passes by asserting nothing.
        $count | Should -BeGreaterThan 0
    }

    It "'<file>':<line> guards 'exit <code>' with `$Host.SetShouldExit(<code>)" -ForEach $ExitCases {
        # `pwsh -File` discards `exit <code>` from a script that declares #Requires -Modules
        # for an auto-imported module (issue #104), so the code must be set on the host too.
        $previous | Should -Match '^\$Host\.SetShouldExit\('

        $argument = [regex]::Match($previous, '^\$Host\.SetShouldExit\((?<arg>.*)\)$').Groups['arg'].Value.Trim()
        $argument | Should -BeExactly $code -Because 'the guard must carry the same code the exit does'
    }
}

Describe 'SkyCraft PowerShell - the rule covers the scripts the fault can reach' {

    # The scope was narrowed in #124; these hold it to the condition the .DESCRIPTION names, in
    # both directions.
    It '<name>' -ForEach $ScopeCases {
        $inScope | Should -Be $expected
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
