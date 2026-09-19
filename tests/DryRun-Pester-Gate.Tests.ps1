<#
.SYNOPSIS
    Pester 5 test: tools/Invoke-DryRun.ps1 runs the offline Pester suites and gates on them.

.DESCRIPTION
    Regression guard for issue #137 (the documented pre-push gate never ran Pester).

    docs/dry-run-harness.md calls Invoke-DryRun.ps1 "the single local gate to run before
    pushing" and says it mirrors every CI check that needs no Azure sign-in. The Pester
    suites - tests/ and module-*/**/tests/*.Tests.ps1 - need nothing beyond the Pester
    module, yet the harness listed them as out of scope. While the CI gate was open (#128)
    that left nothing at all standing between a broken standards test and main.

    This file holds the harness to the same contract as the CI step:
      - a 'Pester' check exists and is selected by default;
      - a failing test in tests/ fails the gate;
      - a failing lab-local suite under module-*/**/tests/ fails the gate, so a suite that
        only ever ran by hand (#77) cannot happen again on the dev box;
      - an empty discovery fails the gate rather than passing as a green run.

    The harness is launched in a child pwsh, for two reasons: Pester 5 does not support
    Invoke-Pester nested inside a running Invoke-Pester, and the whole point of the check
    is the process exit code the caller sees.

.EXAMPLE
    Invoke-Pester -Path .\tests\DryRun-Pester-Gate.Tests.ps1

.NOTES
    Project: SkyCraft
#>

#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

Describe 'SkyCraft dry run - the Pester check is part of the gate' {

    BeforeAll {
        # Resolved here, not at file level: an It or BeforeAll body reads neither the discovery
        # nor the run pass's file-level state in Pester 5.
        $script:Harness = (Resolve-Path (Join-Path $PSScriptRoot '../tools/Invoke-DryRun.ps1')).Path
        $script:Ast = [System.Management.Automation.Language.Parser]::ParseFile($script:Harness, [ref]$null, [ref]$null)
        $script:CheckParameter = $script:Ast.ParamBlock.Parameters | Where-Object { $_.Name.VariablePath.UserPath -eq 'Check' }
        $script:HarnessText = Get-Content -Raw -LiteralPath $script:Harness
    }

    It "accepts 'Pester' as a -Check value" {
        $validateSet = $script:CheckParameter.Attributes |
            Where-Object { $_.TypeName.GetReflectionType() -eq [ValidateSet] }
        @($validateSet.PositionalArguments | ForEach-Object { $_.Value }) | Should -Contain 'Pester'
    }

    It "selects 'Pester' by default, so a plain run covers it" {
        $defaults = @($script:CheckParameter.DefaultValue.FindAll({ param($n)
            $n -is [System.Management.Automation.Language.StringConstantExpressionAst] }, $true) |
            ForEach-Object { $_.Value })
        $defaults | Should -Contain 'Pester'
    }

    It 'no longer lists Pester as out of scope' {
        # The closing message told the reader Pester was not the harness's job. Once the check
        # exists, that sentence would be the one thing on screen contradicting the summary above it.
        $script:HarnessText | Should -Not -Match 'Out of scope here[^\r\n]*Pester'
        $script:HarnessText | Should -Not -Match 'CI still runs Pester'
    }
}

Describe 'SkyCraft dry run - the Pester check gates on the suites it finds' {

    BeforeAll {
        $script:Pwsh    = (Get-Process -Id $PID).Path
        $script:Harness = (Resolve-Path (Join-Path $PSScriptRoot '../tools/Invoke-DryRun.ps1')).Path

        # A minimal repository root: only the folders the Pester check discovers.
        function Initialize-FixtureRepo {
            param(
                [string[]]$RepoWide  = @(),
                [string[]]$LabLocal  = @()
            )

            $root = Join-Path $TestDrive ('repo-{0}' -f [guid]::NewGuid().ToString('n'))
            New-Item -ItemType Directory -Path (Join-Path $root 'tests') -Force | Out-Null

            $i = 0
            foreach ($body in $RepoWide) {
                $i++
                $body | Set-Content -LiteralPath (Join-Path $root "tests/Fixture$i.Tests.ps1") -Encoding utf8
            }

            $labDir = Join-Path $root 'module-9-fixture/9.1-fixture/tests'
            if ($LabLocal.Count -gt 0) { New-Item -ItemType Directory -Path $labDir -Force | Out-Null }
            $i = 0
            foreach ($body in $LabLocal) {
                $i++
                $body | Set-Content -LiteralPath (Join-Path $labDir "Lab$i.Tests.ps1") -Encoding utf8
            }

            return $root
        }

        function Invoke-HarnessPesterCheck {
            param([string]$Root)

            $output = & $script:Pwsh -NoProfile -File $script:Harness -RepoRoot $Root -Check Pester 2>&1 | Out-String
            [PSCustomObject]@{ ExitCode = $LASTEXITCODE; Output = $output }
        }

        $script:Passing = "Describe 'fixture' { It 'passes' { 1 | Should -Be 1 } }"
        $script:Failing = "Describe 'fixture' { It 'fails' { 1 | Should -Be 2 } }"
    }

    It 'exits 0 when every discovered suite passes' {
        $run = Invoke-HarnessPesterCheck -Root (Initialize-FixtureRepo -RepoWide $script:Passing -LabLocal $script:Passing)
        $run.ExitCode | Should -Be 0 -Because $run.Output
    }

    It 'exits 1 when a repo-wide test in tests/ fails' {
        $run = Invoke-HarnessPesterCheck -Root (Initialize-FixtureRepo -RepoWide $script:Failing)
        $run.ExitCode | Should -Be 1 -Because $run.Output
        $run.Output   | Should -Match '(?m)^Pester:' -Because 'the failure must be attributed to the Pester check in the summary'
    }

    It 'exits 1 when a lab-local suite under module-*/**/tests/ fails' {
        # The lab-local suites are the ones that only ever ran by hand (#77). CI now runs them;
        # the local gate has to as well.
        $run = Invoke-HarnessPesterCheck -Root (Initialize-FixtureRepo -RepoWide $script:Passing -LabLocal $script:Failing)
        $run.ExitCode | Should -Be 1 -Because $run.Output
        $run.Output   | Should -Match '(?m)^Pester:'
    }

    It 'exits 1 when no test file is discovered at all' {
        # An empty discovery is a broken discovery, not a clean run - the same rule the CI
        # step applies to its module-* glob.
        $run = Invoke-HarnessPesterCheck -Root (Initialize-FixtureRepo)
        $run.ExitCode | Should -Be 1 -Because $run.Output
        $run.Output   | Should -Match '(?m)^Pester:'
    }
}
