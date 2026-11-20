<#
.SYNOPSIS
    Pester 5 test: docs/lab-parity.md agrees with the lab guides in what a machine can see.

.DESCRIPTION
    Issue #362 keeps the known gaps between the Portal, script and Bicep paths in one reference,
    docs/lab-parity.md. A reference nobody checks goes stale. This test fails when

      - a lab that has a guide has no "Lab X.Y" section or no row in the step-count table;
      - a step count in the table differs from the count computed from the guide now (the
        regenerate command is in the document: tools/Get-LabParityCounts.ps1 -AsMarkdown);
      - an issue reference is malformed (a leading zero, a letter glued to the number);
      - a gap row names no issue reference at all.

    The checker is also run on fixtures (a missing section, a wrong count, an empty document, an
    empty guide scan), so a pass cannot come from a scan that matched nothing. No network: it
    checks the format of issue numbers, not whether they exist.

.EXAMPLE
    Invoke-Pester -CI -Path .\tests\Lab-Parity-Doc.Tests.ps1

.NOTES
    Project: SkyCraft
#>

#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    $script:docPath = Join-Path $script:repoRoot 'docs/lab-parity.md'
    $script:countTool = Join-Path $script:repoRoot 'tools/Get-LabParityCounts.ps1'

    # Returns one string per problem; an empty result means the document is consistent.
    function Get-ParityProblem {
        param(
            [Parameter(Mandatory)][AllowEmptyCollection()][AllowEmptyString()][string[]]$DocLine,
            [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$GuideCount
        )
        $problems = [System.Collections.Generic.List[string]]::new()
        if ($GuideCount.Count -eq 0) { $problems.Add('no lab guide was scanned, so nothing could be compared') }

        # Drop fenced blocks first: a command sample is not a claim.
        $kept = [System.Collections.Generic.List[string]]::new()
        $inFence = $false
        foreach ($text in $DocLine) {
            if ($text -match '^\s*(`{3,}|~{3,})') { $inFence = -not $inFence; continue }
            if (-not $inFence) { $kept.Add($text) }
        }

        $rows = @{}
        foreach ($text in $kept) {
            if ($text -match '^\|\s*(\d+\.\d+)\s*\|\s*(\d+)\s*\|\s*(\d+)\s*\|\s*(\d+)\s*\|\s*$') {
                $rows[$Matches[1]] = @([int]$Matches[2], [int]$Matches[3], [int]$Matches[4])
            }
        }
        if ($rows.Count -eq 0) { $problems.Add('the step-count table has no row') }

        foreach ($guide in $GuideCount) {
            $lab = $guide.Lab
            $heading = @($kept | Where-Object { $_ -match ('^#{2,3}\s+Lab\s+' + [regex]::Escape($lab) + '\s*$') })
            if ($heading.Count -eq 0) { $problems.Add("Lab ${lab}: no section 'Lab $lab'") }
            if (-not $rows.ContainsKey($lab)) {
                $problems.Add("Lab ${lab}: no row in the step-count table")
                continue
            }
            $want = @($guide.Steps, $guide.WithPowerShell, $guide.CliOnly)
            $have = $rows[$lab]
            if (($want -join '/') -ne ($have -join '/')) {
                $problems.Add("Lab ${lab}: table says steps/with PowerShell/CLI only = $($have -join '/'), guide says $($want -join '/')")
            }
        }
        foreach ($lab in $rows.Keys) {
            if (-not @($GuideCount | Where-Object { $_.Lab -eq $lab })) { $problems.Add("Lab ${lab}: a table row for a lab with no guide") }
        }

        $refCount = 0
        foreach ($text in $kept) {
            foreach ($m in [regex]::Matches($text, '#\w+')) {
                # An issue reference is # plus digits without a leading zero; anchors such as
                # #step-1 do not occur in this document, so any other # word is a defect.
                if ($m.Value -match '^#[1-9]\d{0,5}$') { $refCount++ }
                else { $problems.Add("malformed issue reference '$($m.Value)' in: $($text.Trim())") }
            }
        }
        if ($refCount -eq 0) { $problems.Add('the document holds no issue reference') }

        $inGaps = $false
        foreach ($text in $kept) {
            if ($text -match '^##\s+') { $inGaps = ($text -match 'Known gaps per lab'); continue }
            if (-not $inGaps) { continue }
            if ($text -notmatch '^\|') { continue }
            if ($text -match '^\|\s*(Gap\b|-{3})') { continue }
            if ($text -notmatch '#[1-9]\d*') { $problems.Add("gap row names no issue: $($text.Trim())") }
        }
        if (-not ($kept | Where-Object { $_ -match '^##\s+.*Known gaps per lab' })) {
            $problems.Add("no section 'Known gaps per lab'")
        }
        $problems
    }

    function Get-FixtureDoc {
        param([string[]]$Lab = @('1.1', '1.2'), [int]$Steps = 5)
        $doc = @('# Doc', '', '## 2. Step counts', '', '| Lab | Steps | With PowerShell | CLI only |', '| --- | --- | --- | --- |')
        foreach ($l in $Lab) { $doc += "| $l | $Steps | 1 | 0 |" }
        $doc += @('', '## 3. Known gaps per lab', '')
        foreach ($l in $Lab) { $doc += @("### Lab $l", '', '| Gap | Tracked in | State |', '| --- | --- | --- |', '| A gap. | #12 | Open. |', '') }
        $doc
    }

    $script:fixtureGuides = @(
        [pscustomobject]@{ Lab = '1.1'; Steps = 5; WithPowerShell = 1; CliOnly = 0 }
        [pscustomobject]@{ Lab = '1.2'; Steps = 5; WithPowerShell = 1; CliOnly = 0 }
    )
}

Describe '#362 docs/lab-parity.md agrees with the guides' {

    BeforeAll {
        $script:guideCount = @(& $script:countTool -Root $script:repoRoot)
        $script:problems = @(Get-ParityProblem -DocLine (Get-Content -LiteralPath $script:docPath) -GuideCount $script:guideCount)
    }

    It 'scans the lab guides it is meant to compare' {
        $script:guideCount.Count | Should -BeGreaterOrEqual 17
    }

    It 'has no stale count, missing section, malformed issue reference or unlinked gap row' {
        $script:problems | Should -BeNullOrEmpty
    }

    It 'states the command that regenerates the counts' {
        (Get-Content -LiteralPath $script:docPath -Raw) | Should -Match 'Get-LabParityCounts\.ps1 -AsMarkdown'
    }
}

Describe '#362 the parity checker fails on a document that went stale' {

    It 'accepts a consistent fixture' {
        $found = @(Get-ParityProblem -DocLine (Get-FixtureDoc) -GuideCount $script:fixtureGuides)
        $found | Should -BeNullOrEmpty
    }

    It 'names a lab whose section is missing' {
        $doc = Get-FixtureDoc | Where-Object { $_ -ne '### Lab 1.2' }
        $found = @(Get-ParityProblem -DocLine $doc -GuideCount $script:fixtureGuides)
        $found | Should -Contain "Lab 1.2: no section 'Lab 1.2'"
    }

    It 'names a lab whose count differs from the guide' {
        $doc = Get-FixtureDoc -Steps 4
        $found = @(Get-ParityProblem -DocLine $doc -GuideCount $script:fixtureGuides)
        $found.Count | Should -Be 2
        $found[0] | Should -Match 'Lab 1\.1: table says .* = 4/1/0, guide says 5/1/0'
    }

    It 'names a lab that has a guide but no table row' {
        $doc = Get-FixtureDoc | Where-Object { $_ -notmatch '^\| 1\.2 \|' }
        $found = @(Get-ParityProblem -DocLine $doc -GuideCount $script:fixtureGuides)
        $found | Should -Contain 'Lab 1.2: no row in the step-count table'
    }

    It 'names a table row for a lab without a guide' {
        $found = @(Get-ParityProblem -DocLine (Get-FixtureDoc -Lab '1.1', '1.2', '9.9') -GuideCount $script:fixtureGuides)
        $found | Should -Contain 'Lab 9.9: a table row for a lab with no guide'
    }

    It 'rejects a malformed issue reference' {
        $doc = (Get-FixtureDoc) + '| Gap | #0123 | Open. |'
        $found = @(Get-ParityProblem -DocLine $doc -GuideCount $script:fixtureGuides)
        ($found -join "`n") | Should -Match "malformed issue reference '#0123'"
    }

    It 'rejects a gap row that names no issue' {
        $doc = Get-FixtureDoc
        $index = [array]::IndexOf($doc, '| A gap. | #12 | Open. |')
        $doc[$index] = '| A gap. | none | Open. |'
        $found = @(Get-ParityProblem -DocLine $doc -GuideCount $script:fixtureGuides)
        ($found -join "`n") | Should -Match 'gap row names no issue: \| A gap\. \| none'
    }

    It 'fails on an empty document' {
        $found = @(Get-ParityProblem -DocLine @() -GuideCount $script:fixtureGuides)
        $found | Should -Contain 'the step-count table has no row'
        $found | Should -Contain 'the document holds no issue reference'
    }

    It 'fails when no guide was scanned' {
        $found = @(Get-ParityProblem -DocLine (Get-FixtureDoc) -GuideCount @())
        $found | Should -Contain 'no lab guide was scanned, so nothing could be compared'
    }

    It 'ignores a command sample inside a fence' {
        $doc = (Get-FixtureDoc) + @('```powershell', '| 1.1 | 99 | 99 | 99 |', '#bad', '```')
        $found = @(Get-ParityProblem -DocLine $doc -GuideCount $script:fixtureGuides)
        $found | Should -BeNullOrEmpty
    }
}
