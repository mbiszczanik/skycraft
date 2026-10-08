<#
.SYNOPSIS
    Pester 5 tests: every guide drift recording refers only to steps and labels its guide has.

.DESCRIPTION
    tools/guide-drift/recordings/lab-X.Y.json is the committed memory of supervised runs
    (issue #189). A guide edit that renames a portal label must update the recording in the same
    PR, or the next run asks the person again for something already decided - or worse, replays
    a click on the wrong thing. This suite parses each recording's guide with parse.py and
    requires every recorded step id and label to exist there.

    A field value parse.py marks '"literal": false' (an instruction such as 'Click the "..."
    button', or a value with a bracket token) is never typed by the runner unless the recording
    resolves it (issue #202). So for every field of the guide with that mark, the recording must
    give the field a valueOverride, or placeholders that make the value a literal by parse.py's
    own rule (value_is_literal) - for '[yourtenant]' in an address, a placeholder for the token.
    A guide edit that adds such a value fails here instead of in a live run.

    It also keeps tenant data out of this public repository: for every recording, no e-mail
    address, tenant domain or GUID, and only query-free portal.azure.com blade addresses; for lab
    1.1, the tenant prefix and the guest address of step 1.1.5 are environment references.

.EXAMPLE
    Invoke-Pester -Path .\tests\Guide-Drift-Recording.Tests.ps1

.NOTES
    Project: SkyCraft
    Issue:   #189, #202
#>

#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$Parser   = Join-Path $RepoRoot 'tools/guide-drift/parse.py'
$Python   = if ($IsWindows) { 'python' } else { 'python3' }
# Prints, as a JSON array, parse.value_is_literal() of each string in the JSON array file argv[2],
# so this suite applies the parser's own rule rather than a copy of it.
$LiteralCheck = 'import json, sys; sys.path.insert(0, sys.argv[1]); from parse import value_is_literal; ' +
    'print(json.dumps([value_is_literal(v) for v in json.loads(open(sys.argv[2], ''rb'').read())]))'

$RecordingCases = Get-ChildItem -Path (Join-Path $RepoRoot 'tools/guide-drift/recordings') -Filter 'lab-*.json' |
    ForEach-Object {
        $file      = $_
        $raw       = Get-Content -Raw -LiteralPath $file.FullName
        $recording = $raw | ConvertFrom-Json
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

        # Per parsed step: the labels run.py asks the decider about (navigation/action labels and
        # field labels; never tag names, the runner does not look tags up by label) and the keys a
        # value override can name (field labels and tag names).
        $stepById  = @{}
        $actLabels = @{}
        $valueKeys = @{}
        $allValues = [System.Collections.Generic.List[string]]::new()
        if ($parsed) {
            foreach ($step in @($parsed.steps)) {
                $stepById[$step.id] = $step
                $actLabels[$step.id] = @($step.items | ForEach-Object {
                        if ($_.kind -eq 'field') { $_.label } elseif ($_.kind -ne 'tag') { $_.labels }
                    })
                $valueKeys[$step.id] = @($step.items | ForEach-Object {
                        if ($_.kind -eq 'field') { $_.label } elseif ($_.kind -eq 'tag') { $_.name }
                    })
                foreach ($item in @($step.items)) {
                    if ($item.kind -in 'field', 'tag' -and $item.value) { $allValues.Add([string]$item.value) }
                }
            }
        }

        $malformed = @(
            foreach ($prop in $recording.steps.PSObject.Properties) {
                $labelsObject = $prop.Value.labels
                if ($null -ne $labelsObject) {
                    foreach ($entry in @($labelsObject.PSObject.Properties)) {
                        $d = $entry.Value
                        if ($d.decision -cnotin 'use', 'ignore', 'gone') { "step $($prop.Name) label '$($entry.Name)': decision '$($d.decision)'" }
                        if ($d.decision -ceq 'use' -and (-not $d.name -or -not $d.role)) { "step $($prop.Name) label '$($entry.Name)': 'use' needs a name and a role" }
                        if ($d.decision -ceq 'use' -and $d.severity -and $d.severity -cnotin 'misleading', 'cosmetic') { "step $($prop.Name) label '$($entry.Name)': severity '$($d.severity)'" }
                    }
                }
                $result = $prop.Value.result
                if ($null -ne $result -and ($result.text -isnot [string] -or [string]::IsNullOrWhiteSpace($result.text))) {
                    "step $($prop.Name): result must be null or an object with a non-empty text"
                }
            }
        )

        $missing = @(
            foreach ($prop in $recording.steps.PSObject.Properties) {
                $id = $prop.Name
                if (-not $stepById.ContainsKey($id)) { "step $id is not in the guide"; continue }
                if ($stepById[$id].portal -eq $false) { "step $id is not a portal step, so its entry is never used" }
                $labelsObject = $prop.Value.labels
                if ($null -ne $labelsObject) {
                    foreach ($label in @($labelsObject.PSObject.Properties | ForEach-Object { $_.Name })) {
                        if ($actLabels[$id] -cnotcontains $label) { "step $id label '$label' is not in the guide" }
                    }
                }
                $overrides = $prop.Value.valueOverrides
                if ($null -ne $overrides) {
                    foreach ($key in @($overrides.PSObject.Properties | ForEach-Object { $_.Name })) {
                        if ($valueKeys[$id] -cnotcontains $key) { "step $id override '$key' is not a field or tag of the step" }
                    }
                }
            }
            if ($parsed -and $null -ne $recording.placeholders) {
                foreach ($key in @($recording.placeholders.PSObject.Properties | ForEach-Object { $_.Name })) {
                    if (-not @($allValues | Where-Object { $_.Contains($key) })) { "placeholder '$key' appears in no field or tag value of the guide" }
                }
            }
        )

        # Every field the guide marks '"literal": false' needs a valueOverride, or placeholders
        # that leave a literal (#202). The placeholders are applied as written ('${NAME}'), as
        # the environment is not set here; parse.py decides what is literal.
        $unresolved = @()
        if ($parsed) {
            $pending = [System.Collections.Generic.List[object]]::new()
            foreach ($step in @($parsed.steps)) {
                foreach ($item in @($step.items)) {
                    if ($item.kind -ne 'field' -or $item.literal -ne $false) { continue }
                    $overrides = if ($recording.steps.PSObject.Properties.Name -ccontains $step.id) { $recording.steps.($step.id).valueOverrides }
                    if ($null -ne $overrides -and @($overrides.PSObject.Properties.Name) -ccontains $item.label) { continue }
                    $value = [string]$item.value
                    if ($null -ne $recording.placeholders) {
                        foreach ($placeholder in @($recording.placeholders.PSObject.Properties)) {
                            $value = $value.Replace($placeholder.Name, [string]$placeholder.Value)
                        }
                    }
                    $pending.Add([pscustomobject]@{ step = $step.id; label = $item.label; guideValue = [string]$item.value; value = $value })
                }
            }
            if ($pending.Count -gt 0) {
                $valuesFile = [System.IO.Path]::GetTempFileName()
                try {
                    ConvertTo-Json -InputObject @($pending.value) | Set-Content -Encoding utf8 -LiteralPath $valuesFile
                    $literal = @(& $Python -B -c $LiteralCheck (Join-Path $RepoRoot 'tools/guide-drift') $valuesFile | ConvertFrom-Json)
                } finally { Remove-Item -LiteralPath $valuesFile -ErrorAction SilentlyContinue }
                $unresolved = @(
                    for ($i = 0; $i -lt $pending.Count; $i++) {
                        if ($literal[$i] -ne $true) {
                            "step $($pending[$i].step) field '$($pending[$i].label)': '$($pending[$i].guideValue)' is not a literal; add a valueOverride, or a placeholder for each [token]"
                        }
                    }
                )
            }
        }

        # A recorded address is the Portal's URL for a blade. The runner redacts tenant domain,
        # tenant id, GUIDs and query strings before it saves one; this is the backstop.
        $badUrls = @(
            foreach ($prop in $recording.steps.PSObject.Properties) {
                $url = $prop.Value.viewUrl
                if ($null -eq $url) { continue }
                if ($url -isnot [string] -or -not $url.StartsWith('https://portal.azure.com/#', [System.StringComparison]::Ordinal)) { "step $($prop.Name) viewUrl does not start with https://portal.azure.com/#" }
                elseif ($url.Contains('@') -or $url.Contains('?')) { "step $($prop.Name) viewUrl contains '@' or '?'" }
            }
        )

        @{
            file        = $file.Name
            lab         = $recording.lab
            guidePath   = $guidePath
            guideExists = (Test-Path -LiteralPath $guidePath)
            parsed      = [bool]$parsed
            labMatches  = [bool]($parsed -and $recording.lab -eq $parsed.lab)
            nameMatches = ($file.BaseName -ceq "lab-$($recording.lab)")
            missing     = $missing
            unresolved  = $unresolved
            malformed   = $malformed
            badUrls     = $badUrls
            raw         = $raw
        }
    }

Describe 'Guide drift recordings - every one refers to a real guide' {
    It 'has recordings to check' -ForEach @(@{ count = @($RecordingCases).Count }) {
        $count | Should -BeGreaterThan 0
    }

    It "'<file>' is named lab-<lab>.json and names a guide that exists, parses and carries its lab number" -ForEach $RecordingCases {
        $nameMatches | Should -BeTrue -Because "the file name must be lab-$lab.json"
        $guideExists | Should -BeTrue -Because "the guide '$guidePath' must exist"
        $parsed      | Should -BeTrue -Because "parse.py must parse '$guidePath'"
        $labMatches  | Should -BeTrue -Because "the guide's lab number must be $lab"
    }

    It "'<file>' refers only to steps, labels, fields and placeholders the parser finds in that guide" -ForEach $RecordingCases {
        $missing | Should -BeNullOrEmpty -Because ($missing -join '; ')
    }
}

Describe 'Guide drift recordings - every value the runner types is a literal' {
    It "'<file>' resolves every field its guide marks literal: false, by a valueOverride or placeholders" -ForEach $RecordingCases {
        $unresolved | Should -BeNullOrEmpty -Because ($unresolved -join '; ')
    }
}

Describe 'Guide drift recordings - every decision is one replay can act on' {
    It "'<file>' records only use (with name and role), ignore or gone decisions and a well-formed result" -ForEach $RecordingCases {
        # ReplayDecider indexes entry['decision'] and entry['name'] directly, so a missing key
        # raises KeyError, and a use entry without a role matches any role. An unrecognised
        # decision value is treated as no answer. A hand edit that breaks the shape must fail here,
        # not in the middle of a supervised run.
        $malformed | Should -BeNullOrEmpty -Because ($malformed -join '; ')
    }
}

Describe 'Guide drift recordings - nothing tenant-specific is literal (this repository is public)' {
    It "'<file>' contains no e-mail address" -ForEach $RecordingCases {
        ($raw -match '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}') | Should -BeFalse -Because 'an address belongs in the environment (${NAME}), not in a public file'
    }

    It "'<file>' contains no literal tenant domain" -ForEach $RecordingCases {
        # [yourtenant].onmicrosoft.com and ${...}.onmicrosoft.com are fine: ] and } are not matched.
        # The match is asserted as a boolean so a failure never prints the recording into a CI log.
        ($raw -match '[A-Za-z0-9-]+\.onmicrosoft\.com') | Should -BeFalse -Because 'a tenant domain belongs in the environment (${NAME}), not in a public file'
    }

    It "'<file>' contains no GUID" -ForEach $RecordingCases {
        ($raw -match '[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}') | Should -BeFalse -Because 'a tenant, subscription or object id must not be recorded'
    }

    It "'<file>' contains no guest user principal name" -ForEach $RecordingCases {
        # A guest UPN ('me_example.com#EXT#@[tenantdomain]') passes the e-mail check once the
        # tenant domain is redacted, yet still names a real person; the runner records it as
        # ${NAME|upn} instead.
        ($raw -match '#EXT#') | Should -BeFalse -Because 'a guest address belongs in the environment (${NAME}), not in a public file'
    }

    It "'<file>' records only portal.azure.com blade addresses without query or tenant" -ForEach $RecordingCases {
        $badUrls | Should -BeNullOrEmpty -Because ($badUrls -join '; ')
    }
}

Describe 'Guide drift recording for lab 1.1 - tenant values come from the environment' {
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
}
