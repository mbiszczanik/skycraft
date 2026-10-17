<#
.SYNOPSIS
    Pester 5 test: a lab script's exit code reaches its caller, and a learner's session stays open.

.DESCRIPTION
    Regression guard for issues #104 and #257.

    #104: PowerShell 7 drops the exit code of a script that is run as `pwsh -File` when that
    script declares `#Requires -Modules` for a module it has to auto-import - Az.Accounts
    qualifies. The `exit <code>` statement still unwinds the script, but the host never applies
    the code, so the process exits 0 and the automated lab cycle reads a failed run as clean.
    `$Host.SetShouldExit(<code>)` before the `exit` carries the code out.

    #257: `$Host.SetShouldExit` asks the host to end the whole process. Called from a script the
    learner ran at the prompt (a lab's validator, as the guides say), it closes their
    PowerShell window - even with code 0, after a passing run.

    Every lab script therefore ends through Exit-Lab (tools/LabCommon.psm1): exit 1 when the
    failure count is above zero, 0 otherwise, with $Host.SetShouldExit only when the script is
    the entry point of a `pwsh -File` process. This file enforces that contract:

      - structurally, over every lab script (module-*/**/scripts/*.ps1 and scripts/*.ps1): no
        direct $Host.SetShouldExit, no non-zero `exit` (`exit $failCount` included, which wraps
        to 0 at 256 failures), and every script that calls Exit-Lab imports the module by a path
        relative to $PSScriptRoot that resolves to tools/LabCommon.psm1, before the first call;
      - for the entry-point decision, every command-line shape it has to tell apart;
      - behaviourally, with real pwsh processes and no Azure: `pwsh -File` returns 1 for a failed
        run, an interactive session keeps running after the script with $LASTEXITCODE 1, and
        `-Command` and the lab cycle's launcher shim (tools/Invoke-LabScript.ps1) see 1 too.

    THE TOOLS KEEP THE OLD RULE (#124). The maintainer tools under tools/ are process entry points
    with exit codes above 1 (the lab cycle reports a count), not lab scripts. A tools script that
    declares `#Requires -Modules` must still precede every non-zero `exit` with a matching
    $Host.SetShouldExit; today none declares one, and tools/Invoke-LabScript.ps1 exists to be the
    one process with no module requirement (tests/LabCycle.Tests.ps1 holds it to that).

.EXAMPLE
    Invoke-Pester -Path .\tests\Exit-Code-Propagation.Tests.ps1

.NOTES
    Project: SkyCraft
#>

#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

$RepoRoot      = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$LabCommonPath = Join-Path $RepoRoot 'tools/LabCommon.psm1'

# Whether the #104 fault can reach a script at all: it needs a module to auto-import. Read from
# the parsed requirements rather than matched with a regex, so that a '#Requires' line quoted in
# the help block is not mistaken for a declaration.
function Test-RequiresModule {
    param([string]$Text)

    $ast = [System.Management.Automation.Language.Parser]::ParseInput($Text, [ref]$null, [ref]$null)
    $requirements = $ast.ScriptRequirements

    return ($null -ne $requirements -and @($requirements.RequiredModules).Count -gt 0)
}

# Every non-zero `exit` site in a tools script, with the statement that precedes it. Parsed
# rather than regex-matched so that `exit` inside a string or a comment is not counted.
function Get-ExitSite {
    param([string]$Path)

    $ast = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$null, [ref]$null)

    foreach ($exit in $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.ExitStatementAst] }, $true)) {

        $code = if ($exit.Pipeline) { $exit.Pipeline.Extent.Text.Trim() } else { '0' }
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

# How a lab script ends, read from its syntax tree: direct $Host.SetShouldExit calls, non-zero
# exits, Exit-Lab calls and the LabCommon import. -ScriptDirectory resolves the import path the
# way $PSScriptRoot would at run time.
function Get-LabExitShape {
    param(
        [Parameter(Mandatory)][string]$Text,
        [Parameter(Mandatory)][string]$ScriptDirectory
    )

    $ast = [System.Management.Automation.Language.Parser]::ParseInput($Text, [ref]$null, [ref]$null)

    $setShouldExit = @($ast.FindAll({ param($n)
        $n -is [System.Management.Automation.Language.InvokeMemberExpressionAst] -and
        $n.Member.Extent.Text -eq 'SetShouldExit'
    }, $true) | ForEach-Object { "line $($_.Extent.StartLineNumber): $($_.Extent.Text)" })

    $nonZeroExit = @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.ExitStatementAst] }, $true) |
        Where-Object { $_.Pipeline -and $_.Pipeline.Extent.Text.Trim() -ne '0' } |
        ForEach-Object { "line $($_.Extent.StartLineNumber): $($_.Extent.Text)" })

    $exitLab = @($ast.FindAll({ param($n)
        $n -is [System.Management.Automation.Language.CommandAst] -and $n.GetCommandName() -eq 'Exit-Lab'
    }, $true))

    $import = @($ast.FindAll({ param($n)
        $n -is [System.Management.Automation.Language.CommandAst] -and $n.GetCommandName() -eq 'Import-Module' -and
        $n.Extent.Text -match 'LabCommon\.psm1'
    }, $true)) | Select-Object -First 1

    # The path the import names, with $PSScriptRoot standing for the script's own directory.
    $resolved = $null
    if ($import -and $import.Extent.Text -match "Join-Path \`$PSScriptRoot '(?<relative>[^']+)'") {
        $resolved = [System.IO.Path]::GetFullPath((Join-Path $ScriptDirectory $Matches['relative']))
    }

    [PSCustomObject]@{
        SetShouldExit  = $setShouldExit
        NonZeroExit    = $nonZeroExit
        ExitLabCount   = $exitLab.Count
        FirstExitLabAt = if ($exitLab.Count) { ($exitLab | Measure-Object -Property { $_.Extent.StartOffset } -Minimum).Minimum } else { $null }
        ImportAt       = if ($import) { $import.Extent.StartOffset } else { $null }
        ImportPath     = $resolved
    }
}

# Lab scripts: module directories first, then recurse - `Get-ChildItem -Path 'module-*' -Recurse
# -File -Filter` returns nothing on pwsh 7.6 - plus the repository-level scripts/ (the resource
# audit, run at the prompt like a lab script).
$LabScriptFiles = @(
    Get-ChildItem -LiteralPath $RepoRoot -Directory -Filter 'module-*' |
        ForEach-Object { Get-ChildItem -LiteralPath $_.FullName -Recurse -File -Filter '*.ps1' } |
        Where-Object { $_.Directory.Name -eq 'scripts' }
    Get-ChildItem -LiteralPath (Join-Path $RepoRoot 'scripts') -File -Filter '*.ps1'
)

$LabCases = foreach ($item in $LabScriptFiles) {
    $shape = Get-LabExitShape -Text (Get-Content -Raw -LiteralPath $item.FullName) -ScriptDirectory $item.DirectoryName
    @{
        file           = $item.FullName.Substring($RepoRoot.Length + 1) -replace '\\', '/'
        setShouldExit  = $shape.SetShouldExit
        nonZeroExit    = $shape.NonZeroExit
        exitLabCount   = $shape.ExitLabCount
        firstExitLabAt = $shape.FirstExitLabAt
        importAt       = $shape.ImportAt
        importPath     = $shape.ImportPath
        labCommonPath  = $LabCommonPath
    }
}
$ExitLabCases = @($LabCases | Where-Object { $_.exitLabCount -gt 0 })

# Tools that declare a module requirement keep the #104 guard (none do today).
$ToolExitCases = Get-ChildItem -LiteralPath (Join-Path $RepoRoot 'tools') -File -Filter '*.ps1' |
    Where-Object { Test-RequiresModule -Text (Get-Content -Raw -LiteralPath $_.FullName) } |
    ForEach-Object {
        $file = $_.FullName.Substring($RepoRoot.Length + 1) -replace '\\', '/'
        foreach ($site in Get-ExitSite -Path $_.FullName) {
            @{ file = $file; line = $site.Line; code = $site.Code; previous = $site.Previous }
        }
    }

# Fixtures that hold the structural rule to failing what it is there to fail.
$FixtureDirectory = Join-Path $RepoRoot 'module-0-fixture/0.1-fixture/scripts'
$FixtureImport    = "Import-Module (Join-Path `$PSScriptRoot '../../../tools/LabCommon.psm1') -Force -Verbose:`$false"
$FixtureCases = @(
    @{ name = 'the #104 idiom is a direct SetShouldExit'
       shape = Get-LabExitShape -ScriptDirectory $FixtureDirectory -Text "`$Host.SetShouldExit(1)`nexit 1"
       property = 'SetShouldExit'; expected = 1 }
    @{ name = 'the #104 idiom is a non-zero exit'
       shape = Get-LabExitShape -ScriptDirectory $FixtureDirectory -Text "`$Host.SetShouldExit(1)`nexit 1"
       property = 'NonZeroExit'; expected = 1 }
    @{ name = 'exit $failCount is a non-zero exit'
       shape = Get-LabExitShape -ScriptDirectory $FixtureDirectory -Text 'exit $failCount'
       property = 'NonZeroExit'; expected = 1 }
    @{ name = 'exit 0 is not a non-zero exit'
       shape = Get-LabExitShape -ScriptDirectory $FixtureDirectory -Text 'exit 0'
       property = 'NonZeroExit'; expected = 0 }
    @{ name = 'SetShouldExit quoted in a comment is not a call'
       shape = Get-LabExitShape -ScriptDirectory $FixtureDirectory -Text "# `$Host.SetShouldExit(1)`nExit-Lab -FailureCount 1"
       property = 'SetShouldExit'; expected = 0 }
)

$ImportFixtures = @(
    @{ name = 'an Exit-Lab with no import has no import'
       shape = Get-LabExitShape -ScriptDirectory $FixtureDirectory -Text 'Exit-Lab -FailureCount 1'
       check = { param($s) $null -eq $s.ImportAt } }
    @{ name = 'an import after the first Exit-Lab comes too late'
       shape = Get-LabExitShape -ScriptDirectory $FixtureDirectory -Text "Exit-Lab -FailureCount 1`n$FixtureImport"
       check = { param($s) $s.ImportAt -gt $s.FirstExitLabAt } }
    @{ name = 'the standard import resolves to tools/LabCommon.psm1 from a lab scripts folder'
       shape = Get-LabExitShape -ScriptDirectory $FixtureDirectory -Text "$FixtureImport`nExit-Lab -FailureCount 1"
       check = { param($s) $s.ImportPath -eq [System.IO.Path]::GetFullPath((Join-Path $RepoRoot 'tools/LabCommon.psm1')) } }
)

# Discovery and run are separate phases in Pester 5: what the It blocks need at run time is set
# up again here.
BeforeAll {
    $RepoRoot      = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    $script:LabCommonPath = Join-Path $RepoRoot 'tools/LabCommon.psm1'

    function Test-RequiresModule {
        param([string]$Text)

        $ast = [System.Management.Automation.Language.Parser]::ParseInput($Text, [ref]$null, [ref]$null)
        $requirements = $ast.ScriptRequirements

        return ($null -ne $requirements -and @($requirements.RequiredModules).Count -gt 0)
    }
}

Describe 'SkyCraft PowerShell - every lab script ends through Exit-Lab (#257)' {

    It 'has lab scripts in scope to check' -ForEach @(@{ count = @($LabCases).Count; withExitLab = $ExitLabCases.Count }) {
        # A filter that matches nothing produces a Describe that passes by asserting nothing.
        $count | Should -BeGreaterThan 0
        $withExitLab | Should -BeGreaterThan 0
    }

    It "'<file>' calls no `$Host.SetShouldExit" -ForEach $LabCases {
        # Called at the prompt, it closes the learner's PowerShell session (#257). Exit-Lab calls
        # it only when the script is the entry point of a pwsh -File process.
        $setShouldExit | Should -BeNullOrEmpty -Because 'a lab script ends with Exit-Lab -FailureCount <n> (tools/LabCommon.psm1)'
    }

    It "'<file>' has no non-zero exit" -ForEach $LabCases {
        # A bare `exit 1` loses its code under pwsh -File (#104), and `exit $failCount` wraps to 0
        # at 256 failures (#257). `exit 0` and a bare `exit` are the success path.
        $nonZeroExit | Should -BeNullOrEmpty -Because 'a lab script ends with Exit-Lab -FailureCount <n> (tools/LabCommon.psm1)'
    }

    It "'<file>' imports tools/LabCommon.psm1 by a path relative to `$PSScriptRoot, before its first Exit-Lab" -ForEach $ExitLabCases {
        $importAt | Should -Not -BeNullOrEmpty -Because "Import-Module (Join-Path `$PSScriptRoot '<relative>/tools/LabCommon.psm1') makes Exit-Lab available"
        $importPath | Should -Be ([System.IO.Path]::GetFullPath($labCommonPath)) -Because 'the path must hold in any clone, Cloud Shell included'
        $importAt | Should -BeLessThan $firstExitLabAt
    }
}

Describe 'SkyCraft PowerShell - the lab script rule fails what it is there to fail' {

    It '<name>' -ForEach $FixtureCases {
        @($shape.$property).Count | Should -Be $expected
    }

    It '<name>' -ForEach $ImportFixtures {
        & $check $shape | Should -BeTrue
    }
}

Describe 'SkyCraft PowerShell - a tools script declaring #Requires -Modules guards a non-zero exit (#104)' {

    It "'<file>':<line> guards 'exit <code>' with `$Host.SetShouldExit(<code>)" -ForEach $ToolExitCases {
        $previous | Should -Match '^\$Host\.SetShouldExit\('

        $argument = [regex]::Match($previous, '^\$Host\.SetShouldExit\((?<arg>.*)\)$').Groups['arg'].Value.Trim()
        $argument | Should -BeExactly $code -Because 'the guard must carry the same code the exit does'
    }

    It "the lab cycle launcher shim, as it ships, declares no module requirement (#124)" {
        Test-RequiresModule -Text (Get-Content -Raw -LiteralPath (Join-Path $RepoRoot 'tools/Invoke-LabScript.ps1')) |
            Should -BeFalse
    }

    It "a '#Requires -Modules' line quoted in a help block is not a declaration" {
        $text = @('<#', '.DESCRIPTION', '    #Requires -Modules Az.Accounts', '#>', '#Requires -Version 7.0', 'exit 1') -join "`n"
        Test-RequiresModule -Text $text | Should -BeFalse
        Test-RequiresModule -Text "#Requires -Modules Az.Accounts`nexit 1" | Should -BeTrue
    }
}

Describe 'SkyCraft PowerShell - Exit-Lab tells the entry point of a pwsh -File process from everything else' {

    BeforeAll {
        $script:LabCommon = Import-Module $LabCommonPath -Force -PassThru
        $script:Lab  = if ($IsWindows) { 'C:\repo\module-1\1.1\scripts\Lab-Fixture.ps1' } else { '/repo/module-1/1.1/scripts/Lab-Fixture.ps1' }
        $script:Shim = if ($IsWindows) { 'C:\repo\tools\Invoke-LabScript.ps1' } else { '/repo/tools/Invoke-LabScript.ps1' }
    }

    AfterAll {
        Remove-Module -ModuleInfo $script:LabCommon -Force -ErrorAction SilentlyContinue
    }

    It '<name>' -ForEach @(
        @{ name = 'pwsh -File <lab script> is the entry point';                 cmd = @('pwsh', '-NoProfile', '-File', 'LAB');                 outer = 'LAB';  expected = $true }
        @{ name = 'pwsh -f <lab script> is the entry point';                    cmd = @('pwsh', '-f', 'LAB');                                  outer = 'LAB';  expected = $true }
        @{ name = 'pwsh <lab script>, with -File implied, is the entry point';  cmd = @('pwsh', '-NoProfile', 'LAB');                          outer = 'LAB';  expected = $true }
        @{ name = 'a switch value before -File does not hide it';               cmd = @('pwsh', '-ExecutionPolicy', 'Bypass', '-File', 'LAB'); outer = 'LAB';  expected = $true }
        @{ name = 'a -NoExit after the script path belongs to the script';      cmd = @('pwsh', '-File', 'LAB', '-NoExit');                    outer = 'LAB';  expected = $true }
        @{ name = 'pwsh -NoExit -File keeps the session, so it is not';         cmd = @('pwsh', '-NoExit', '-File', 'LAB');                    outer = 'LAB';  expected = $false }
        @{ name = 'pwsh -noe -File keeps the session, so it is not';            cmd = @('pwsh', '-noe', '-File', 'LAB');                       outer = 'LAB';  expected = $false }
        @{ name = 'pwsh -Command runs typed text, so it is not';                cmd = @('pwsh', '-Command', '& LAB');                          outer = 'LAB';  expected = $false }
        @{ name = 'pwsh -c runs typed text, so it is not';                      cmd = @('pwsh', '-c', '& LAB');                                outer = 'LAB';  expected = $false }
        @{ name = 'pwsh -EncodedCommand runs typed text, so it is not';         cmd = @('pwsh', '-EncodedCommand', 'AAAA');                    outer = 'LAB';  expected = $false }
        @{ name = 'an interactive prompt is not';                               cmd = @('pwsh');                                               outer = '';     expected = $false }
        @{ name = 'a lab script run by the launcher shim is not';               cmd = @('pwsh', '-NoProfile', '-File', 'SHIM');                outer = 'SHIM'; expected = $false }
        @{ name = 'a lab script typed at a -Command prompt is not';             cmd = @('pwsh', '-NoProfile', '-NoExit', '-Command', '-');     outer = '';     expected = $false }
    ) {
        $commandLine = $cmd | ForEach-Object { $_ -replace '^LAB$', $script:Lab -replace '^SHIM$', $script:Shim -replace '& LAB', "& $($script:Lab)" }
        $outermost   = switch ($outer) { 'LAB' { $script:Lab } 'SHIM' { $script:Shim } default { '' } }

        $result = & $script:LabCommon {
            param($c, $o, $l) Test-LabProcessEntryPoint -CommandLineArgs $c -OutermostScript $o -CallerScript $l
        } $commandLine $outermost $script:Lab

        $result | Should -Be $expected
    }

    It 'exports Exit-Lab and nothing else yet' {
        @($script:LabCommon.ExportedFunctions.Keys) | Should -Be @('Exit-Lab')
    }
}

Describe 'SkyCraft PowerShell - Exit-Lab reaches both callers (real pwsh processes, no Azure)' {

    BeforeAll {
        $script:Pwsh  = (Get-Process -Id $PID).Path
        $script:HasAz = [bool](Get-Module -ListAvailable -Name Az.Accounts)

        # A lab-shaped script: it declares Az.Accounts where it is installed - the condition the
        # #104 fault needs - and ends the way every lab script does.
        $requires = if ($script:HasAz) { '#Requires -Modules Az.Accounts' } else { '' }
        $script:LabScript = Join-Path $TestDrive 'Lab-Fixture.ps1'
        @(
            '#Requires -Version 7.0'
            $requires
            '[CmdletBinding()]'
            'param([int]$Count)'
            "`$ErrorActionPreference = 'Stop'"
            "Import-Module '$LabCommonPath' -Force -Verbose:`$false"
            'Write-Host "lab: $Count failure(s)"'
            'Exit-Lab -FailureCount $Count'
        ) | Set-Content -LiteralPath $script:LabScript -Encoding utf8

        # The #104 idiom the lab scripts used before #257, for the control case.
        $script:OldIdiom = Join-Path $TestDrive 'Old-Idiom.ps1'
        @(
            '#Requires -Version 7.0'
            'Write-Host "old idiom"'
            '$Host.SetShouldExit(1)'
            'exit 1'
        ) | Set-Content -LiteralPath $script:OldIdiom -Encoding utf8

        # Commands fed on stdin to a session that stays open (-NoExit), as a learner types them.
        function Invoke-InteractiveSession {
            param([string[]]$Line)
            $text = ($Line + 'exit 0') -join "`n"
            ($text | & $script:Pwsh -NoProfile -NoLogo -NoExit -Command - 2>&1 | Out-String)
        }
    }

    It 'pwsh -File returns 1 to its caller for a failed run' -Skip:(-not [bool](Get-Module -ListAvailable -Name Az.Accounts)) {
        # The #104 case: without SetShouldExit, a script declaring Az.Accounts exits 0 here.
        & $script:Pwsh -NoProfile -File $script:LabScript -Count 3 | Out-Null
        $LASTEXITCODE | Should -Be 1
    }

    It 'pwsh -File returns 0 for a passing run and 1, not 0, for 256 failures' {
        & $script:Pwsh -NoProfile -File $script:LabScript -Count 0 | Out-Null
        $LASTEXITCODE | Should -Be 0

        & $script:Pwsh -NoProfile -File $script:LabScript -Count 256 | Out-Null
        $LASTEXITCODE | Should -Be 1 -Because 'exit $failCount would wrap to 0 here'
    }

    It 'an interactive session keeps running after a failed run, with $LASTEXITCODE 1 (the #257 repro)' {
        $output = Invoke-InteractiveSession -Line @(
            "& '$($script:LabScript)' -Count 3"
            'Write-Host "MARKER after the script, LASTEXITCODE=$LASTEXITCODE"'
        )
        $output | Should -Match 'MARKER after the script, LASTEXITCODE=1' -Because "the session must survive the script; output was:`n$output"
    }

    It 'an interactive session keeps running after a passing run, with $LASTEXITCODE 0' {
        $output = Invoke-InteractiveSession -Line @(
            "& '$($script:LabScript)' -Count 0"
            'Write-Host "MARKER after the script, LASTEXITCODE=$LASTEXITCODE"'
        )
        $output | Should -Match 'MARKER after the script, LASTEXITCODE=0' -Because "output was:`n$output"
    }

    It 'control: the old SetShouldExit idiom ends the same session before the next command' {
        # Proves the case above can fail: this is what #257 reported.
        $output = Invoke-InteractiveSession -Line @(
            "& '$($script:OldIdiom)'"
            'Write-Host "MARKER after the script"'
        )
        $output | Should -Match 'old idiom'
        $output | Should -Not -Match 'MARKER after the script'
    }

    It 'pwsh -Command runs the next statement and the process reports the code' {
        $output = & $script:Pwsh -NoProfile -Command "& '$($script:LabScript)' -Count 3; Write-Host ""MARKER LASTEXITCODE=`$LASTEXITCODE""" 2>&1 | Out-String
        $output | Should -Match 'MARKER LASTEXITCODE=1'

        & $script:Pwsh -NoProfile -Command "& '$($script:LabScript)' -Count 3" | Out-Null
        $LASTEXITCODE | Should -Be 1
    }

    It 'the lab cycle launcher shim (pwsh -File tools/Invoke-LabScript.ps1) returns the code' {
        $shim = Join-Path $RepoRoot 'tools/Invoke-LabScript.ps1'

        & $script:Pwsh -NoProfile -File $shim -TargetScript $script:LabScript -ArgumentJson '{"Count":3}' | Out-Null
        $LASTEXITCODE | Should -Be 1

        & $script:Pwsh -NoProfile -File $shim -TargetScript $script:LabScript -ArgumentJson '{"Count":0}' | Out-Null
        $LASTEXITCODE | Should -Be 0
    }
}
