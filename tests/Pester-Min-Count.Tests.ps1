<#
.SYNOPSIS
    Pester 5 test: the CI Pester job gates on a minimum number of discovered tests.

.DESCRIPTION
    Regression guard for #544. A discovery regression that drops most suites must not stay green.
    Checks that tests/.pester-min-count holds one positive integer and that the Pester job in
    .github/workflows/lint.yml reads it and fails the job below it.

.NOTES
    Project: SkyCraft
#>

#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    $script:root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    $script:floorPath = Join-Path $script:root 'tests/.pester-min-count'
    $script:lint = Get-Content -LiteralPath (Join-Path $script:root '.github/workflows/lint.yml') -Raw
}

Describe '#544 minimum Pester test count' {

    It 'tests/.pester-min-count exists' {
        Test-Path -LiteralPath $script:floorPath | Should -BeTrue
    }

    It 'tests/.pester-min-count holds one positive integer' {
        $text = (Get-Content -LiteralPath $script:floorPath -Raw).Trim()
        $text | Should -Match '^[1-9]\d*$'
    }

    It 'lint.yml reads the floor file' {
        $script:lint | Should -Match 'tests/\.pester-min-count'
    }

    It 'lint.yml fails the job when TotalCount is below the floor, through the explicit exit' {
        $script:lint | Should -Match '\$result\.TotalCount\s+-lt\s+\$minCount'
        $m = [regex]::Match($script:lint, '\$result\.TotalCount\s+-lt\s+\$minCount\)\s*\{(?<body>.*?)\n\s*\}', 'Singleline')
        $m.Success | Should -BeTrue
        $m.Groups['body'].Value | Should -Match 'SetShouldExit\(1\)'
        $m.Groups['body'].Value | Should -Match 'exit 1'
    }
}
