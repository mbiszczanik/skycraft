<#
.SYNOPSIS
    Pester 5 tests: every guide drift recording refers only to steps and labels its guide has.

.DESCRIPTION
    tools/guide-drift/recordings/lab-X.Y.json is the committed memory of supervised runs
    (issue #189). A guide edit that renames a portal label must update the recording in the same
    PR, or the next run asks the person again for something already decided - or worse, replays
    a click on the wrong thing. This suite parses each recording's guide with parse.py and
    requires every recorded step id and label to exist there, as a label the runner asks about:
    a resource name that a navigation chain gives in a code span is opened by name and never
    asked about, so a decision for one is rejected (issue #199).

    A field value parse.py marks '"literal": false' (an instruction such as 'Click the "..."
    button', or a value with a bracket token) is never typed by the runner unless the recording
    resolves it (issue #202). So for every field of the guide with that mark, the runner's own
    decision (recording.field_action) must be to type it: the recording gives the field a
    valueOverride, or placeholders that make the value a literal - for '[yourtenant]' in an
    address, a placeholder for the token. A guide edit that adds such a value fails here
    instead of in a live run.

    It also keeps tenant data out of this public repository: for every recording, no e-mail
    address, tenant domain or GUID, and only query-free portal.azure.com blade addresses; for lab
    1.1, the tenant prefix and the guest address of step 1.1.5 are environment references.

.EXAMPLE
    Invoke-Pester -Path .\tests\Guide-Drift-Recording.Tests.ps1

.NOTES
    Project: SkyCraft
    Issue:   #189, #199, #202
#>

#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$Parser   = Join-Path $RepoRoot 'tools/guide-drift/parse.py'
$Python   = if ($IsWindows) { 'python' } else { 'python3' }
# Prints, as a JSON array, every field of the parsed guide (argv[3]) that is marked
# '"literal": false' and that recording.field_action - the runner's own decision - would report
# rather than type with the recording (argv[2]). Each '${NAME}' the recording refers to is set to
# a dummy value first, as the environment is not set here and expand_env stops on a missing name.
$FieldActionCheck = @'
import json, os, sys
from pathlib import Path
sys.path.insert(0, sys.argv[1])
from recording import env_names, field_action
recording = json.loads(Path(sys.argv[2]).read_bytes())
steps = json.loads(Path(sys.argv[3]).read_bytes())['steps']
os.environ.update({name: 'guide-drift-test' for name in env_names(recording)})
reported = []
for step in steps:
    for item in step['items']:
        if item['kind'] == 'field' and item.get('literal', True) is False:
            action = field_action(recording, step, item)[0]
            if action in ('instruction', 'unresolved'):
                reported.append({'step': step['id'], 'label': item['label'], 'value': item['value'], 'action': action})
print(json.dumps(reported))
'@

# The labels of one parsed step: those run.py asks the decider about ('decided': navigation and
# action labels and field labels; never tag names, which the runner does not look up by label),
# or the resource names a chain gives in code spans ('resource', #199), which the runner opens by
# name and never asks about, so a recorded decision for one would never be used.
function Get-StepLabel {
    param([object]$Step, [ValidateSet('decided', 'resource')][string]$Kind)
    foreach ($item in @($Step.items)) {
        if ($item.kind -eq 'tag') { continue }
        if ($item.kind -eq 'field') {
            if ($Kind -eq 'decided') { $item.label }
            continue
        }
        $labels    = @($item.labels)
        $resources = @($item.resources | Where-Object { $null -ne $_ })
        for ($i = 0; $i -lt $labels.Count; $i++) {
            if (($resources -contains $i) -eq ($Kind -eq 'resource')) { $labels[$i] }
        }
    }
}

# Why a recorded decision for $Label in the parsed $Step can never be used; nothing when it can.
function Get-LabelProblem {
    param([object]$Step, [string]$Label)
    if (@(Get-StepLabel -Step $Step -Kind decided) -ccontains $Label) { return }
    if (@(Get-StepLabel -Step $Step -Kind resource) -ccontains $Label) {
        "step $($Step.id) label '$Label' is a resource name, which the runner opens by name and never asks about"
    } else {
        "step $($Step.id) label '$Label' is not in the guide"
    }
}

# Get-LabelProblem on a parsed step with a chain that names a resource, an action, a field and a
# tag. Computed here, at discovery: It blocks cannot call file-scope functions.
$LabelFixture = [pscustomobject]@{ id = '9.9.1'; items = @(
        [pscustomobject]@{ kind = 'navigation'; labels = @('Load balancers', 'dev-skycraft-swc-lb', 'Backend pools'); resources = @(1) }
        [pscustomobject]@{ kind = 'action'; labels = @('Save') }
        [pscustomobject]@{ kind = 'field'; label = 'Name'; value = 'x' }
        [pscustomobject]@{ kind = 'tag'; name = 'Project'; value = 'SkyCraft' }
    )
}
$LabelRuleCases = @(
    @{ label = 'Backend pools'; problem = '' }
    @{ label = 'Save'; problem = '' }
    @{ label = 'Name'; problem = '' }
    @{ label = 'dev-skycraft-swc-lb'; problem = "step 9.9.1 label 'dev-skycraft-swc-lb' is a resource name, which the runner opens by name and never asks about" }
    @{ label = 'Project'; problem = "step 9.9.1 label 'Project' is not in the guide" }
) | ForEach-Object { $_.actual = @(Get-LabelProblem -Step $LabelFixture -Label $_.label) -join '; '; $_ }

$RecordingCases = Get-ChildItem -Path (Join-Path $RepoRoot 'tools/guide-drift/recordings') -Filter 'lab-*.json' |
    ForEach-Object {
        $file      = $_
        $raw       = Get-Content -Raw -LiteralPath $file.FullName
        $recording = $raw | ConvertFrom-Json
        $guidePath = Join-Path $RepoRoot $recording.guide
        # Read through --out, never stdout: on Windows a piped stdout is decoded with the console
        # code page, and guides contain characters outside it (see Guide-Drift-Parser.Tests.ps1).
        $parsed   = $null
        $reported = @()
        if (Test-Path -LiteralPath $guidePath) {
            $out = [System.IO.Path]::GetTempFileName()
            try {
                & $Python $Parser $guidePath --out $out --repo-root $RepoRoot
                if ($LASTEXITCODE -eq 0) {
                    $parsed = Get-Content -Raw -Encoding utf8 -LiteralPath $out | ConvertFrom-Json
                    # json.dumps escapes non-ASCII, so the console code page cannot garble stdout.
                    $reportedJson = & $Python -B -c $FieldActionCheck (Join-Path $RepoRoot 'tools/guide-drift') $file.FullName $out
                    if ($LASTEXITCODE -ne 0) {
                        throw "the field_action check of '$($file.Name)' failed (python exit code $LASTEXITCODE)"
                    }
                    $reported = @(($reportedJson -join "`n") | ConvertFrom-Json)
                }
            } finally { Remove-Item -LiteralPath $out -ErrorAction SilentlyContinue }
        }

        # Per parsed step: the step itself (its labels are checked by Get-LabelProblem), the keys a
        # value override can name (field labels and tag names), and every text a placeholder can
        # appear in (field and tag values, and resource names, #199).
        $stepById  = @{}
        $valueKeys = @{}
        $allValues = [System.Collections.Generic.List[string]]::new()
        if ($parsed) {
            foreach ($step in @($parsed.steps)) {
                $stepById[$step.id] = $step
                $valueKeys[$step.id] = @($step.items | ForEach-Object {
                        if ($_.kind -eq 'field') { $_.label } elseif ($_.kind -eq 'tag') { $_.name }
                    })
                foreach ($item in @($step.items)) {
                    if ($item.kind -in 'field', 'tag' -and $item.value) { $allValues.Add([string]$item.value) }
                }
                foreach ($name in @(Get-StepLabel -Step $step -Kind resource)) { $allValues.Add([string]$name) }
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
                        Get-LabelProblem -Step $stepById[$id] -Label $label
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
                    if (-not @($allValues | Where-Object { $_.Contains($key) })) { "placeholder '$key' appears in no field value, tag value or resource name of the guide" }
                }
            }
        )

        # Every field the guide marks '"literal": false' needs a valueOverride, or placeholders
        # that leave a literal (#202): field_action, run in Python above, reports the others.
        $unresolved = @(
            foreach ($field in $reported) {
                "step $($field.step) field '$($field.label)': '$($field.value)' would be reported as $($field.action), not typed; add a valueOverride, or a placeholder for each [token]"
            }
        )

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

Describe 'Guide drift recordings - a decision is recorded only for a label the runner asks about' {
    It "reports a recorded decision for '<label>' as '<problem>' (empty: it can be replayed)" -ForEach $LabelRuleCases {
        # A resource name (#199) is opened by name and never asked about, so a hand-written
        # decision for it fails here instead of passing and never being replayed.
        $actual | Should -Be $problem
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
