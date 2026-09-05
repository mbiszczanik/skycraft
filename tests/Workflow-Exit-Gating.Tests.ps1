<#
.SYNOPSIS
    Pester 5 test: a failing `pwsh` step in a GitHub Actions workflow fails the job.

.DESCRIPTION
    Regression guard for issue #128 (the Pester CI job reported 5 failures and still
    concluded `success`, so the standards suite gated nothing).

    GitHub runs a `shell: pwsh` step as `pwsh -command ". '<step>.ps1'"`. That host does
    not carry an `exit <code>` through verbatim - it reports the exit code the host was
    last told to use. `$Host.SetShouldExit(0)` pins that value for the rest of the process,
    and a later `exit 1` does not lift it.

    The standards suite pins it on every run: tests/LabCycle.Tests.ps1 invokes
    tools/Invoke-LabCycle.ps1 and tools/Remove-LabCycle.ps1 in-process with `&`, and both
    scripts end with `$Host.SetShouldExit($failedCount)` - 0 on the success paths those
    tests exercise. By the time Pester reaches its own `exit $failedCount`, the step
    process is already committed to exiting 0. The idiom this repository adopted to make
    lab scripts report failure (#104) is what silently disarmed its own CI gate.

    The fix is the other half of that same idiom: a gating step sets the code on the host
    immediately before the `exit`, exactly as tests/Exit-Code-Propagation.Tests.ps1
    requires of the lab scripts.

    This file enforces both halves of that contract:
      - structurally, that every non-zero `exit` in a `shell: pwsh` workflow step is
        preceded by a matching $Host.SetShouldExit call, and that a step running Pester
        decides the outcome itself rather than trusting Pester's `-CI` exit;
      - behaviourally, that a bare `exit` really is swallowed after $Host.SetShouldExit(0)
        on this host, and that the guard really does override it.

.EXAMPLE
    Invoke-Pester -Path .\tests\Workflow-Exit-Gating.Tests.ps1

.NOTES
    Project: SkyCraft
#>

#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

$RepoRoot     = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$WorkflowsDir = Join-Path $RepoRoot '.github/workflows'

# The `shell: pwsh` steps of a workflow file, with the body of their `run:` block dedented
# back to column 0 so it can be handed to the PowerShell parser.
#
# Hand-rolled rather than parsed with a YAML module: the CI job installs nothing but Pester,
# and the shape being read here is a fixed three keys of a step, not arbitrary YAML.
function Get-PwshRunStep {
    param([string]$Path)

    $lines  = [System.IO.File]::ReadAllLines($Path)
    $blocks = [System.Collections.Generic.List[object]]::new()
    $open   = $null

    function Get-Indent([string]$Line) { ($Line -replace '^(\s*).*$', '$1').Length }

    foreach ($line in $lines) {

        $blank  = [string]::IsNullOrWhiteSpace($line)
        $indent = if ($blank) { -1 } else { Get-Indent $line }

        # A list item at the indent of the open step - or any dedent past it - closes it.
        if ($null -ne $open -and -not $blank -and $indent -le $open.Indent) {
            $blocks.Add($open)
            $open = $null
        }

        if (-not $blank -and $line -match '^\s*-\s') {
            $open = [PSCustomObject]@{ Indent = $indent; Lines = [System.Collections.Generic.List[string]]::new() }
        }

        if ($null -ne $open) { $open.Lines.Add($line) }
    }
    if ($null -ne $open) { $blocks.Add($open) }

    foreach ($block in $blocks) {

        $text = $block.Lines -join "`n"
        if ($text -notmatch '(?m)^\s*shell:\s*pwsh\s*$') { continue }

        $runIndex = -1
        for ($i = 0; $i -lt $block.Lines.Count; $i++) {
            if ($block.Lines[$i] -match '^\s*run:\s*\|') { $runIndex = $i; break }
        }
        if ($runIndex -lt 0) { continue }

        $runIndent = Get-Indent $block.Lines[$runIndex]
        $body      = [System.Collections.Generic.List[string]]::new()
        for ($i = $runIndex + 1; $i -lt $block.Lines.Count; $i++) {
            $line = $block.Lines[$i]
            if ([string]::IsNullOrWhiteSpace($line)) { $body.Add(''); continue }
            if ((Get-Indent $line) -le $runIndent) { break }
            $body.Add($line)
        }
        if ($body.Count -eq 0) { continue }

        $dedent = ($body | Where-Object { $_ -ne '' } | ForEach-Object { Get-Indent $_ } | Measure-Object -Minimum).Minimum
        $script = ($body | ForEach-Object { if ($_ -eq '') { '' } else { $_.Substring($dedent) } }) -join "`n"

        $name = if ($text -match '(?m)^\s*-?\s*name:\s*(?<name>.+?)\s*$') { $Matches.name } else { '(unnamed)' }

        [PSCustomObject]@{
            Name   = $name
            Script = $script
        }
    }
}

# Every non-zero `exit` in a step body, with the statement that precedes it. Parsed rather
# than regex-matched so that `exit` inside a string or a comment is not counted.
function Get-ExitSite {
    param([string]$Script)

    $ast = [System.Management.Automation.Language.Parser]::ParseInput($Script, [ref]$null, [ref]$null)

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

$WorkflowSteps = @(
    Get-ChildItem -Path $WorkflowsDir -File -Filter '*.yml' | ForEach-Object {
        $file = $_.Name
        foreach ($step in Get-PwshRunStep -Path $_.FullName) {
            [PSCustomObject]@{ File = $file; Step = $step.Name; Script = $step.Script }
        }
    }
)

$ExitCases = @(
    foreach ($step in $WorkflowSteps) {
        foreach ($site in Get-ExitSite -Script $step.Script) {
            @{
                file     = $step.File
                step     = $step.Step
                line     = $site.Line
                code     = $site.Code
                previous = $site.Previous
            }
        }
    }
)

$PesterSteps = @(
    $WorkflowSteps |
        Where-Object { $_.Script -match 'Invoke-Pester' } |
        ForEach-Object { @{ file = $_.File; step = $_.Step; script = $_.Script } }
)

Describe 'SkyCraft CI - a failing pwsh workflow step fails the job' {

    # The count is passed in rather than read from the file-level variable: Pester 5 runs
    # this file once to discover and again to execute, and an It body reads neither run's
    # file-level state.
    It 'finds the pwsh steps to check' -ForEach @(@{ count = $WorkflowSteps.Count }) {
        # A parser that silently matches nothing would make every case below vacuous.
        $count | Should -BeGreaterThan 0
    }

    It "'<file>' step '<step>':<line> guards 'exit <code>' with `$Host.SetShouldExit(<code>)" -ForEach $ExitCases {
        # `pwsh -command` reports the code the host was last given, and the standards suite
        # leaves $Host.SetShouldExit(0) behind on every run (issue #128), so a bare `exit`
        # in a gating step is not a gate.
        $previous | Should -Match '^\$Host\.SetShouldExit\('

        $argument = [regex]::Match($previous, '^\$Host\.SetShouldExit\((?<arg>.*)\)$').Groups['arg'].Value.Trim()
        $argument | Should -BeExactly $code -Because 'the guard must carry the same code the exit does'
    }

    It "'<file>' step '<step>' decides the Pester outcome itself" -ForEach $PesterSteps {
        # Pester's own `-CI` exit is subject to exactly the same host pinning, so the step
        # has to read the result and gate on it explicitly.
        $script | Should -Match '\bFailedCount\b' -Because 'the step must read the failure count rather than trust an exit code'
        $script | Should -Match '\$Host\.SetShouldExit\('
    }
}

Describe 'SkyCraft CI - the pwsh host really does pin its exit code' {

    BeforeAll {
        $script:Pwsh = (Get-Process -Id $PID).Path

        # Run the fragment the way GitHub runs a `shell: pwsh` step. In a child process:
        # calling $Host.SetShouldExit in this one is what breaks the gate in the first place.
        function Invoke-AsWorkflowStep {
            param([string[]]$Body)

            $file = Join-Path $TestDrive ('step-{0}.ps1' -f [guid]::NewGuid())
            $Body | Set-Content -LiteralPath $file -Encoding utf8

            & $script:Pwsh -NoProfile -Command ". '$file'" | Out-Null
            $LASTEXITCODE
        }
    }

    It 'swallows a bare exit once $Host.SetShouldExit(0) has been called' {
        Invoke-AsWorkflowStep -Body @(
            '$Host.SetShouldExit(0)'
            'exit 1'
        ) | Should -Be 0 -Because 'this is the fault issue #128 describes'
    }

    It 'carries the failure out when the exit is guarded' {
        Invoke-AsWorkflowStep -Body @(
            '$Host.SetShouldExit(0)'
            '$Host.SetShouldExit(1)'
            'exit 1'
        ) | Should -Be 1
    }
}
