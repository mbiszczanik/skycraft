<#
.SYNOPSIS
    Pester 5 tests: every guide drift recording refers only to steps and labels its guide has.

.DESCRIPTION
    tools/guide-drift/recordings/lab-X.Y.json is the committed memory of supervised runs
    (issue #189). A guide edit that renames a portal label must update the recording in the same
    PR, or the next run asks the person again for something already decided - or worse, replays
    a click on the wrong thing. This suite parses each recording's guide with parse.py and
    requires every recorded step id and label to exist there.

    It also pins the two values that must never be literal in this public repository: the
    tenant prefix placeholder and the guest address of step 1.1.5 are environment references.

.EXAMPLE
    Invoke-Pester -Path .\tests\Guide-Drift-Recording.Tests.ps1

.NOTES
    Project: SkyCraft
    Issue:   #189
#>

#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$Parser   = Join-Path $RepoRoot 'tools/guide-drift/parse.py'
$Python   = if ($IsWindows) { 'python' } else { 'python3' }

$RecordingCases = Get-ChildItem -Path (Join-Path $RepoRoot 'tools/guide-drift/recordings') -Filter 'lab-*.json' |
    ForEach-Object {
        $recording = Get-Content -Raw -LiteralPath $_.FullName | ConvertFrom-Json
        $guidePath = Join-Path $RepoRoot $recording.guide
        # Read through --out, never stdout: on Windows a piped stdout is decoded with the console
        # code page, and guides contain characters outside it (see Guide-Drift-Parser.Tests.ps1).
        $parsed = $null
        if (Test-Path -LiteralPath $guidePath) {
            $out = [System.IO.Path]::GetTempFileName()
            try {
                & $Python $Parser $guidePath --out $out --repo-root $RepoRoot
                if ($LASTEXITCODE -eq 0) { $parsed = Get-Content -Raw -Encoding utf8 -LiteralPath $out | ConvertFrom-Json }
            } finally { Remove-Item -LiteralPath $out -ErrorAction SilentlyContinue }
        }
        $labelsByStep = @{}
        foreach ($step in @($parsed.steps)) {
            $labelsByStep[$step.id] = @($step.items | ForEach-Object { if ($_.kind -eq 'field') { $_.label } elseif ($_.kind -eq 'tag') { $_.name } else { $_.labels } })
        }
        $malformed = @(
            foreach ($prop in $recording.steps.PSObject.Properties) {
                foreach ($entry in @($prop.Value.labels.PSObject.Properties)) {
                    $d = $entry.Value
                    if ($d.decision -cnotin 'use', 'ignore', 'gone') { "step $($prop.Name) label '$($entry.Name)': decision '$($d.decision)'" }
                    if ($d.decision -ceq 'use' -and (-not $d.name -or -not $d.role)) { "step $($prop.Name) label '$($entry.Name)': 'use' needs a name and a role" }
                    if ($d.decision -ceq 'use' -and $d.severity -and $d.severity -cnotin 'misleading', 'cosmetic') { "step $($prop.Name) label '$($entry.Name)': severity '$($d.severity)'" }
                }
            }
        )
        $missing = @(
            foreach ($prop in $recording.steps.PSObject.Properties) {
                $id = $prop.Name
                if (-not $labelsByStep.ContainsKey($id)) { "step $id is not in the guide"; continue }
                foreach ($label in @($prop.Value.labels.PSObject.Properties | ForEach-Object { $_.Name })) {
                    if ($labelsByStep[$id] -cnotcontains $label) { "step $id label '$label' is not in the guide" }
                }
                foreach ($field in @($prop.Value.valueOverrides.PSObject.Properties | ForEach-Object { $_.Name })) {
                    if ($labelsByStep[$id] -cnotcontains $field) { "step $id override '$field' is not a field of the step" }
                }
            }
        )
        @{
            file        = $_.Name
            lab         = $recording.lab
            guideExists = (Test-Path -LiteralPath $guidePath)
            labMatches  = ($recording.lab -eq $parsed.lab)
            missing     = $missing
            malformed   = $malformed
            recording   = $recording
        }
    }

Describe 'Guide drift recordings - every one refers to a real guide' {
    It 'has recordings to check' -ForEach @(@{ count = @($RecordingCases).Count }) {
        $count | Should -BeGreaterThan 0
    }

    It "'<file>' names a guide that exists and carries its lab number" -ForEach $RecordingCases {
        $guideExists | Should -BeTrue
        $labMatches  | Should -BeTrue
    }

    It "'<file>' refers only to steps, labels and fields the parser finds in that guide" -ForEach $RecordingCases {
        $missing | Should -BeNullOrEmpty -Because ($missing -join '; ')
    }
}

Describe 'Guide drift recordings - every decision is one replay can act on' {
    It "'<file>' records only use (with name and role), ignore or gone decisions" -ForEach $RecordingCases {
        # ReplayDecider treats anything else as no answer (or, without a role, as any role), so a
        # hand edit that breaks the shape would silently send the run back to asking - or worse.
        $malformed | Should -BeNullOrEmpty -Because ($malformed -join '; ')
    }
}

Describe 'Guide drift recording for lab 1.1 - nothing tenant-specific is literal' {
    BeforeAll {
        $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
        $script:Lab11 = Get-Content -Raw -LiteralPath (Join-Path $repoRoot 'tools/guide-drift/recordings/lab-1.1.json') | ConvertFrom-Json
    }

    It 'replaces [yourtenant] from the environment' {
        $script:Lab11.placeholders.'[yourtenant]' | Should -Be '${SKYCRAFT_GUIDE_DRIFT_TENANT_PREFIX}'
    }

    It 'overrides the guest address of step 1.1.5 from the environment' {
        $script:Lab11.steps.'1.1.5'.valueOverrides.Email | Should -Be '${SKYCRAFT_GUIDE_DRIFT_GUEST_EMAIL}'
    }

    It 'contains no literal e-mail address' {
        (Get-Content -Raw -LiteralPath (Join-Path (Resolve-Path (Join-Path $PSScriptRoot '..')).Path 'tools/guide-drift/recordings/lab-1.1.json')) |
            Should -Not -Match '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}'
    }
}
