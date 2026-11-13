<#
.SYNOPSIS
    CI gate: lab guides, validators and the lab-cycle manifest must agree (offline, no Azure).

.DESCRIPTION
    The agent Portal passes of Modules 2 to 5 found most defects in the repository text alone: a
    validator that fails on an unset property, a guide whose Prerequisites do not match what the
    lab-cycle graph needs, a guide that does not say what it leaves behind. This script holds the
    checks that catch those classes on every change (issues #363, #364, #362). Each finding names
    its check, the file and the evidence line.

      NullUnsafeComparison  A lab's Test-Lab.ps1 compares an object property with -eq $false or
                            -ne $false. A property the learner never touched in the Portal is
                            often $null while the Bicep writes false, so the comparison counts
                            an unset property as a violation (or as a pass). Use -not $x or
                            $x -ne $true.
      PrerequisiteEdges     Every DependsOn edge of a lab in tools/lab-cycle-manifest.psd1 is named
                            ('Lab X.Y') in the Prerequisites section of that lab's guide, and the
                            guide has a Prerequisites section.
      LeavesBehindSection   Every lab guide has a section titled "What This Lab Leaves Behind".
      ValidatorResourceName A literal resource name (dev-skycraft-swc-rg, platformskycraftswcsa ...)
                            in a lab's Test-Lab.ps1 appears in that lab's guide or in the guide of
                            a lab it depends on in the manifest. A name only the Bicep creates
                            fails a learner who built the lab in the Portal (#363 check 2, #355).

    A finding is allowed only through tools/lab-consistency-allowlist.psd1, where every entry
    names its check, its file, a Match (the evidence line's text, so a moved line stays allowed)
    and a reason. The gate fails when
      - a finding is not on the allowlist;
      - an allowlist entry matches no finding (a stale entry hides nothing and must go);
      - it found no guide, no validator or no manifest phase (an empty scan is not a pass);
      - the allowlist is malformed or holds an entry without a reason.

.PARAMETER RepoRoot
    The repository to check. Default: the parent of this script's folder.

.PARAMETER AllowlistPath
    The allowlist. Default: tools/lab-consistency-allowlist.psd1 next to this script.

.PARAMETER Update
    Prints allowlist entries for the current findings, in the allowlist's format, and exits 0.

.EXAMPLE
    pwsh -NoProfile -File tools/Test-LabConsistency.ps1

.NOTES
    Project: SkyCraft
    Issues: #363, #364, #362
#>

#Requires -Version 7.0

[CmdletBinding()]
param(
    [string]$RepoRoot = (Split-Path -Parent $PSScriptRoot),
    [string]$AllowlistPath = (Join-Path $PSScriptRoot 'lab-consistency-allowlist.psd1'),
    [switch]$Update
)

$ErrorActionPreference = 'Stop'

function Write-GateFailure {
    param([string]$Message)
    Write-Host "  [FAIL] $Message" -ForegroundColor Red
}

function Get-LabFile {
    param([string]$Pattern)
    @(Get-ChildItem -LiteralPath $RepoRoot -Directory -Filter 'module-*' |
        ForEach-Object { Get-ChildItem -LiteralPath $_.FullName -Recurse -File -Filter $Pattern } |
        ForEach-Object { ([System.IO.Path]::GetRelativePath($RepoRoot, $_.FullName)) -replace '\\', '/' } |
        Sort-Object)
}

function Import-Allowlist {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { throw "The allowlist '$Path' does not exist." }
    $data = Import-PowerShellDataFile -LiteralPath $Path
    if (-not $data.ContainsKey('Allow')) { throw "The allowlist '$Path' has no 'Allow' section." }
    foreach ($entry in @($data.Allow)) {
        foreach ($key in 'Check', 'File', 'Match', 'Reason') {
            if (-not $entry[$key] -or -not "$($entry[$key])".Trim()) { throw "An allowlist entry has no $key." }
        }
    }
    return $data
}

try {
    $allowlist = Import-Allowlist -Path $AllowlistPath
} catch {
    Write-GateFailure $_.Exception.Message
    exit 1
}

$manifestPath = Join-Path $RepoRoot 'tools/lab-cycle-manifest.psd1'
if (-not (Test-Path -LiteralPath $manifestPath)) {
    Write-GateFailure "The lab-cycle manifest '$manifestPath' does not exist."
    exit 1
}
$phases = @((Import-PowerShellDataFile -LiteralPath $manifestPath).Phases)

$guides = Get-LabFile -Pattern 'lab-guide-*.md'
$validators = @(Get-LabFile -Pattern 'Test-Lab.ps1' | Where-Object { $_ -like '*/scripts/Test-Lab.ps1' })

$findings = [System.Collections.Generic.List[object]]::new()
function Add-Finding {
    param([string]$Check, [string]$File, [string]$Match, [string]$Detail)
    $findings.Add([pscustomobject]@{ Check = $Check; File = $File; Match = $Match; Detail = $Detail })
}

# NullUnsafeComparison
$nullUnsafe = [regex]'(\.\w+|\))\s+-(eq|ne)\s+\$false\b'
foreach ($file in $validators) {
    $lines = @(Get-Content -LiteralPath (Join-Path $RepoRoot $file))
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($nullUnsafe.IsMatch($lines[$i])) {
            Add-Finding -Check 'NullUnsafeComparison' -File $file -Match $lines[$i].Trim() `
                -Detail "line $($i + 1): a property compared with -eq/-ne `$false; use -not `$x or `$x -ne `$true"
        }
    }
}

# PrerequisiteEdges and LeavesBehindSection
foreach ($phase in $phases) {
    $labId = $phase.Id
    $labFolder = $phase.Lab
    $guide = $guides | Where-Object { $_ -like "$labFolder/lab-guide-*.md" } | Select-Object -First 1
    if (-not $guide) { Add-Finding -Check 'PrerequisiteEdges' -File "$labFolder/lab-guide-$labId.md" -Match 'guide' -Detail 'the lab has no guide file'; continue }

    $text = Get-Content -LiteralPath (Join-Path $RepoRoot $guide) -Raw
    $section = [regex]::Match($text, '(?ms)^##\s+\S*\s*Prerequisites\s*$(?<body>.*?)(?=^##\s)')
    foreach ($edge in @($phase.DependsOn)) {
        if (-not $section.Success) {
            Add-Finding -Check 'PrerequisiteEdges' -File $guide -Match $edge -Detail "no Prerequisites section, so the dependency on Lab $edge is not named"
        } elseif ($section.Groups['body'].Value -notmatch "\bLab\s+$([regex]::Escape($edge))\b") {
            Add-Finding -Check 'PrerequisiteEdges' -File $guide -Match $edge -Detail "the lab-cycle manifest makes Lab $labId depend on Lab $edge, and the Prerequisites section does not name it"
        }
    }
}

# Every guide, including a lab the cycle does not build (Lab 1.1).
foreach ($guide in $guides) {
    $text = Get-Content -LiteralPath (Join-Path $RepoRoot $guide) -Raw
    if ($text -notmatch '(?im)^##\s+.*leaves\s+behind') {
        Add-Finding -Check 'LeavesBehindSection' -File $guide -Match 'section' -Detail 'no "What This Lab Leaves Behind" section'
    }
}

# ValidatorResourceName: a literal resource name a validator looks up must appear in the guide of
# its lab or in the guide of a lab it depends on (#363 check 2, #355). A name only the Bicep creates
# fails a learner who built the lab in the Portal.
$edges = @{}
foreach ($phase in $phases) { $edges[$phase.Id] = @($phase.DependsOn) }
$guideById = @{}
foreach ($guide in $guides) {
    $idMatch = [regex]::Match($guide, '/(\d\.\d)-[^/]+/lab-guide-')
    if ($idMatch.Success) { $guideById[$idMatch.Groups[1].Value] = Get-Content -LiteralPath (Join-Path $RepoRoot $guide) -Raw }
}
function Get-DependencyClosure {
    param([string]$Id)
    $seen = [System.Collections.Generic.HashSet[string]]::new()
    $queue = [System.Collections.Generic.Queue[string]]::new()
    $queue.Enqueue($Id)
    while ($queue.Count) {
        foreach ($dependency in @($edges[$queue.Dequeue()])) {
            if ($dependency -and $seen.Add($dependency)) { $queue.Enqueue($dependency) }
        }
    }
    return $seen
}
$resourceName = [regex]'["'']([a-z0-9]+(?:-[a-z0-9]+)*-(?:rg|vnet|vm|kv|law|nsg|lb|sa|bas|pip|asg|app\d*|acr|rsv|bv|cm|dcr|ag)[a-z0-9-]*)["'']'
foreach ($file in $validators) {
    $idMatch = [regex]::Match($file, '/(\d\.\d)-[^/]+/scripts/')
    if (-not $idMatch.Success) { continue }
    $labId = $idMatch.Groups[1].Value
    $parts = @([string]$guideById[$labId]) + @(@(Get-DependencyClosure -Id $labId) | ForEach-Object { [string]$guideById[$_] })
    $corpus = $parts -join "`n"
    $names = @(Get-Content -LiteralPath (Join-Path $RepoRoot $file) | ForEach-Object { $resourceName.Matches($_) } | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
    foreach ($name in $names) {
        if (-not $corpus.Contains($name)) {
            Add-Finding -Check 'ValidatorResourceName' -File $file -Match $name `
                -Detail "the validator looks up '$name', which no step of Lab $labId or of a lab it depends on creates or names"
        }
    }
}

if ($Update) {
    foreach ($f in $findings) {
        Write-Host ("        @{{ Check = '{0}'; File = '{1}'; Match = '{2}'; Reason = 'TODO' }}" -f $f.Check, $f.File, ($f.Match -replace "'", "''"))
    }
    exit 0
}

# Match findings with allowlist entries.
$used = [System.Collections.Generic.HashSet[int]]::new()
$open = [System.Collections.Generic.List[object]]::new()
foreach ($f in $findings) {
    $hit = $false
    $entries = @($allowlist.Allow)
    for ($i = 0; $i -lt $entries.Count; $i++) {
        $e = $entries[$i]
        if ($e.Check -eq $f.Check -and $e.File -eq $f.File -and $f.Match.Contains($e.Match)) { [void]$used.Add($i); $hit = $true; break }
    }
    if (-not $hit) { $open.Add($f) }
}
$stale = @()
$entries = @($allowlist.Allow)
for ($i = 0; $i -lt $entries.Count; $i++) { if (-not $used.Contains($i)) { $stale += $entries[$i] } }

Write-Host "Lab consistency check: $($guides.Count) guide(s), $($validators.Count) validator(s), $($phases.Count) manifest phase(s); $($findings.Count) finding(s), $($open.Count) not allowlisted, $($stale.Count) stale allowlist entr(ies)." -ForegroundColor Cyan

$failed = $false
if ($guides.Count -eq 0 -or $validators.Count -eq 0 -or $phases.Count -eq 0) {
    Write-GateFailure 'Found no guide, no validator or no manifest phase. An empty scan is not a pass: check the checkout and the manifest.'
    $failed = $true
}
foreach ($f in $open) {
    Write-GateFailure "[$($f.Check)] $($f.File): $($f.Detail). Fix it, or add it to tools/lab-consistency-allowlist.psd1 with a reason."
    $failed = $true
}
foreach ($s in $stale) {
    Write-GateFailure "[$($s.Check)] $($s.File): the allowlist entry '$($s.Match)' matches no finding any more; remove it."
    $failed = $true
}

if ($failed) { exit 1 }
Write-Host 'Lab consistency check passed.' -ForegroundColor Green
exit 0
