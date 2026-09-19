<#
.SYNOPSIS
    Pester 5 tests asserting every Pester suite in the repository is one CI actually runs.

.DESCRIPTION
    Guards the rule in docs/powershell-standards.md section 6 ("Where a suite lives"), added
    for issue #77. The pester job in .github/workflows/lint.yml ran only tests/, so the four
    lab-local suites under module-*/**/tests/ were executed only when someone remembered to
    invoke them by hand - and one of them (Module 1's Readme-Architecture.Tests.ps1) kept
    asserting a Mermaid block after ADR-0004 had replaced it with an SVG, with nothing to
    notice. Two things have to stay true for that not to recur:

      1. The workflow's Pester step discovers module-*/**/tests/*.Tests.ps1 in addition to
         tests/, and installs the Bicep CLI first because Lab 3.1's suite compiles through
         'az bicep build'.
      2. Every tracked *.Tests.ps1 sits in one of those two places. A suite anywhere else
         would match neither path and would never run.

    Suites are enumerated with 'git ls-files' so an untracked scratch file cannot fail the
    run, and matched separator-agnostically so the result is the same on Windows and on the
    ubuntu-latest runner.

.EXAMPLE
    Invoke-Pester -Path .\tests\Pester-Discovery.Tests.ps1

.NOTES
    Project: SkyCraft
#>

#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

# Discovery-phase data: -ForEach evaluates here, not in BeforeAll.
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path

Push-Location $RepoRoot
try {
    $SuiteCases = @(git ls-files -- '*.Tests.ps1' | ForEach-Object { @{ suite = ($_ -replace '\\', '/') } })
} finally { Pop-Location }

Describe 'Pester discovery - every suite lives where CI looks' {
    It 'finds the suites to check' -ForEach @(@{ count = $SuiteCases.Count }) {
        # An enumerator that silently matches nothing would make the case below vacuous.
        $count | Should -BeGreaterThan 0
    }

    It "'<suite>' is under tests/ or module-*/**/tests/" -ForEach $SuiteCases {
        $suite | Should -Match '^(tests/[^/]+|module-[^/]+/(?:[^/]+/)*tests/[^/]+)\.Tests\.ps1$' `
            -Because 'lint.yml runs tests/ and module-*/**/tests/*.Tests.ps1 and nothing else (powershell-standards.md section 6)'
    }
}

Describe 'Pester discovery - the workflow runs both locations' {
    BeforeAll {
        # Resolved again here: a BeforeAll cannot read the file-level $RepoRoot above.
        $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
        $workflow = Get-Content -Raw -LiteralPath (Join-Path $repoRoot '.github' 'workflows' 'lint.yml')

        # The pester job is the block from its key up to the next top-level job key.
        $script:PesterJob = [regex]::Match($workflow, '(?ms)^  pester:\r?\n(?<body>.*?)(?=^  \w+:)').Groups['body'].Value
    }

    It 'has a pester job with a Pester step' {
        $script:PesterJob | Should -Match 'Invoke-Pester'
    }

    It 'passes tests/ and the discovered lab-local suites to Invoke-Pester' {
        $script:PesterJob | Should -Match "Invoke-Pester -Path \(@\('\./tests'\) \+ \`$labSuites\)"
    }

    It 'discovers exactly the tracked module-*/**/tests/*.Tests.ps1 files' {
        # The discovery line is lifted from the workflow and executed, not pattern-matched:
        # `Get-ChildItem -Path 'module-*' -Recurse -File -Filter '*.Tests.ps1'` reads as
        # correct and returns nothing on pwsh 7.6, which no regex would have caught.
        $line = [regex]::Match($script:PesterJob, '(?m)^\s*\$labSuites = (?<expr>.+)$').Groups['expr'].Value
        $line | Should -Not -BeNullOrEmpty -Because 'the step must assign the discovered suites to $labSuites'

        Push-Location $repoRoot
        try {
            $expected = @(git ls-files -- 'module-*/*.Tests.ps1' | ForEach-Object { $_ -replace '\\', '/' } | Sort-Object)
            $found    = @(& ([scriptblock]::Create($line)) |
                             ForEach-Object { ($_ -replace '\\', '/').Substring($repoRoot.Length + 1) } |
                             Sort-Object)
        } finally { Pop-Location }

        $expected.Count | Should -BeGreaterThan 0
        $found | Should -Be $expected
    }

    It 'installs the Bicep CLI before the suites run (Lab 3.1 compiles through az bicep build)' {
        $script:PesterJob | Should -Match 'az bicep install'
        $script:PesterJob.IndexOf('az bicep install') | Should -BeLessThan $script:PesterJob.IndexOf('Invoke-Pester')
    }
}
