<#
.SYNOPSIS
    Pester 5 test: a committed lab checklist holds no ticked box.

.DESCRIPTION
    Regression guard for #553. A checklist is a template the learner ticks while doing the lab; a
    committed box that is already ticked makes the checklist claim work nobody did (Lab 5.2 shipped
    with 40 of 63 boxes ticked, #542). The test names the file and the line of every ticked box.

    The detector is tested on a built-in fixture too, so the check cannot pass because it never
    matched anything.

.NOTES
    Project: SkyCraft
#>

#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeDiscovery {
    $discoveryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    $script:checklists = @(
        Get-ChildItem -LiteralPath $discoveryRoot -Directory -Filter 'module-*' |
            ForEach-Object { Get-ChildItem -LiteralPath $_.FullName -Recurse -File -Filter 'lab-checklist-*.md' } |
            Sort-Object FullName |
            ForEach-Object { @{ Name = $_.Name; Path = $_.FullName } }
    )
}

BeforeAll {
    # A ticked box is a list item whose box holds x or X, with any list marker and indent.
    function Get-TickedBoxLine {
        param([Parameter(Mandatory)][AllowEmptyCollection()][AllowEmptyString()][string[]]$Line)
        for ($i = 0; $i -lt $Line.Count; $i++) {
            if ($Line[$i] -match '^\s*(?:[-*+]|\d+[.)])\s+\[[xX]\]') { [pscustomobject]@{ Number = $i + 1; Text = $Line[$i].Trim() } }
        }
    }
}

Describe '#553 lab checklists carry no ticked box' {

    It 'finds the lab checklists it is meant to check' {
        # A discovery that finds nothing would pass every case below without checking anything.
        $root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
        $found = @(Get-ChildItem -LiteralPath $root -Directory -Filter 'module-*' |
                ForEach-Object { Get-ChildItem -LiteralPath $_.FullName -Recurse -File -Filter 'lab-checklist-*.md' })
        $found.Count | Should -BeGreaterOrEqual 17
    }

    It '<Name> holds no ticked box' -ForEach $script:checklists {
        $ticked = @(Get-TickedBoxLine -Line (Get-Content -LiteralPath $Path))
        $ticked | ForEach-Object { "$Name line $($_.Number): $($_.Text)" } | Should -BeNullOrEmpty
    }
}

Describe '#553 the ticked-box detector' {

    It 'reports a ticked box with its line number' {
        $fixture = @('# Checklist', '', '- [ ] open', '- [x] ticked', '- [ ] open again')
        $found = @(Get-TickedBoxLine -Line $fixture)
        $found.Count | Should -Be 1
        $found[0].Number | Should -Be 4
    }

    It 'reports an upper-case X, an indented box and a numbered item' {
        $fixture = @('- [X] upper case', '  - [x] nested', '1. [x] numbered')
        @(Get-TickedBoxLine -Line $fixture).Count | Should -Be 3
    }

    It 'reports nothing for open boxes and for text that only looks like one' {
        $fixture = @('- [ ] open', 'Use `[x]` to tick a box.', '[x] not a list item', '- not a box')
        @(Get-TickedBoxLine -Line $fixture).Count | Should -Be 0
    }
}
