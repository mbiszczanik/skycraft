#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }
<#
.SYNOPSIS
    Pester 5 test: every lab guide numbers its steps consecutively, starting at 1, with no
    number used twice.

.DESCRIPTION
    Issues #149 and #150 found guides whose step headings did not match the sequence a learner
    expects: Lab 2.1 jumped from Step 2.1.12 to Step 2.1.14 after a step was removed and only its
    immediate successor renumbered, and Lab 3.2 used Step 3.2.10 and Step 3.2.20 twice each after
    steps were inserted without renumbering what followed. A learner (or a course that cites the
    guide by step number) cannot tell whether material is missing or which of two headings is
    meant. docs/lab-guide-standards.md requires "Steps numbered sequentially"; nothing enforced it.

    This test reads every module-*/X.Y-*/lab-guide-X.Y.md, collects the headings of the form

        ### Step X.Y.N: Title

    in document order, and requires the N values to be exactly 1, 2, 3, ... with no gap and no
    repeat. It also requires the X.Y prefix of every step to be the lab's own number, so a step
    pasted from another guide is caught. Fenced code blocks are stripped first so that a heading
    quoted inside a snippet does not count.

.EXAMPLE
    Invoke-Pester -Path .\tests\Guide-Step-Numbering.Tests.ps1

.NOTES
    Project: SkyCraft
#>

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path

# Computed at discovery, as the other tests in this directory do, so the It block needs nothing
# from the file scope.
$GuideCases = Get-ChildItem -Path $RepoRoot -Directory -Filter 'module-*' |
    Get-ChildItem -Directory |
    Where-Object { $_.Name -match '^\d+\.\d+-' } |
    ForEach-Object {
        $num   = [regex]::Match($_.Name, '^\d+\.\d+').Value
        $guide = Join-Path $_.FullName "lab-guide-$num.md"
        if (-not (Test-Path -LiteralPath $guide)) { return }
        $text  = Get-Content -Raw -LiteralPath $guide
        $text  = [regex]::Replace($text, '(?ms)^[ \t]*(`{3,}|~{3,}).*?^[ \t]*\1[ \t]*\r?$', '')   # CRLF-safe
        $steps = [regex]::Matches($text, '(?m)^#{2,4}[ \t]+Step[ \t]+(?<lab>\d+\.\d+)\.(?<n>\d+)\b') |
            ForEach-Object { [pscustomobject]@{ Lab = $_.Groups['lab'].Value; N = [int]$_.Groups['n'].Value } }
        $actual   = @($steps | ForEach-Object { "$($_.Lab).$($_.N)" })
        $expected = @(1..[math]::Max($steps.Count, 1) | ForEach-Object { "$num.$_" })
        @{
            lab      = $_.Name
            count    = $steps.Count
            actual   = $actual
            expected = $expected
            wrong    = @(0..($actual.Count - 1) | Where-Object { $actual[$_] -ne $expected[$_] } |
                            ForEach-Object { "heading $($_ + 1) is 'Step $($actual[$_])', expected 'Step $($expected[$_])'" })
        }
    }

Describe 'Lab guide steps are numbered consecutively' {
    It "'<lab>' guide has at least one 'Step X.Y.N' heading" -ForEach $GuideCases {
        $count | Should -BeGreaterThan 0 -Because "a lab guide without numbered steps has nothing for a learner to follow"
    }

    It "'<lab>' guide numbers its steps 1..N with no gap or repeat" -ForEach $GuideCases {
        $wrong | Should -BeNullOrEmpty -Because "a learner following '$lab' cannot tell a gap or a duplicate from missing material: $($wrong -join '; ')"
    }
}
