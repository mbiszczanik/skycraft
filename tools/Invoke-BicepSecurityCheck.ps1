<#
.SYNOPSIS
    CI gate: PSRule for Azure assesses the resources every Bicep template and parameter file creates.

.DESCRIPTION
    `bicep build` proves a template compiles; it says nothing about what the template configures
    (public network access, TLS version, encryption, diagnostics). The labs ship templates that
    learners copy, so a weak default spreads. This script expands every tracked .bicepparam file
    with PSRule for Azure and compares what the rules report with a reviewed baseline
    (tools/bicep-security-baseline.psd1).

    Tool choice (issue #522, comparison run 2026-11-12 on this repository's templates): PSRule for
    Azure 1.47.0 analysed 25 targets and reported 63 findings of 34 rules; Checkov 3.4.5 ran one
    check on the same tree and reported seven parsing errors. PSRule expands a parameter file with
    its real values, which is what the labs deploy.

    The gate fails when
      - a (parameter file, rule) pair reports a finding the baseline does not hold;
      - a tracked .bicep or .bicepparam file was not analysed and the baseline's Unanalysable
        section does not name it with a reason (PSRule cannot expand a template that needs
        parameters it is not given, or one that reads a resource that does not exist yet);
      - no file was analysed at all, or PSRule for Azure is missing or outside the pinned range;
      - the baseline is malformed or holds an entry without a reason.

    A .bicep file counts as analysed when an analysed parameter file reaches it through `using`
    or a `module` reference, or when PSRule expands it directly with its default parameters.

.PARAMETER RepoRoot
    The repository to check. Default: the parent of this script's folder.

.PARAMETER BaselinePath
    The baseline. Default: tools/bicep-security-baseline.psd1 next to this script.

.PARAMETER Update
    Prints the baseline entries for the current findings and files that could not be analysed, in
    the baseline's format, and exits 0. For the maintainer who reviews them; nothing is written.

.PARAMETER ModuleName
    The PSRule module to use. Default PSRule.Rules.Azure; a test names a module that does not exist.

.EXAMPLE
    pwsh -NoProfile -File tools/Invoke-BicepSecurityCheck.ps1

.NOTES
    Project: SkyCraft
    Issue: #522
#>

#Requires -Version 7.0

[CmdletBinding()]
param(
    [string]$RepoRoot = (Split-Path -Parent $PSScriptRoot),
    [string]$BaselinePath = (Join-Path $PSScriptRoot 'bicep-security-baseline.psd1'),
    [switch]$Update,
    [string]$ModuleName = 'PSRule.Rules.Azure'
)

$ErrorActionPreference = 'Stop'
$moduleName = $ModuleName
$moduleMin = [version]'1.47.0'
$moduleMax = [version]'1.47.99'

function Write-GateFailure {
    param([string]$Message)
    Write-Host "  [FAIL] $Message" -ForegroundColor Red
}

function Get-RelativePath {
    param([string]$Full)
    ([System.IO.Path]::GetRelativePath($RepoRoot, $Full)) -replace '\\', '/'
}

function Import-Baseline {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { throw "The baseline '$Path' does not exist." }
    $data = Import-PowerShellDataFile -LiteralPath $Path
    $problems = [System.Collections.Generic.List[string]]::new()
    foreach ($section in 'Finding', 'Unanalysable') {
        if (-not $data.ContainsKey($section)) { $problems.Add("section '$section' is missing"); continue }
        foreach ($entry in @($data[$section])) {
            $needed = if ($section -eq 'Finding') { @('File', 'Rule', 'Reason') } else { @('File', 'Reason') }
            foreach ($key in $needed) {
                if (-not $entry[$key] -or -not "$($entry[$key])".Trim()) { $problems.Add("a '$section' entry has no $key") }
            }
        }
    }
    if ($problems.Count) { throw ("The baseline '$Path' is not usable: " + (($problems | Select-Object -Unique) -join '; ') + '.') }
    return $data
}

# Files a Bicep or parameter file reaches through 'using' and 'module' statements.
function Get-ReferencedBicep {
    param([string]$File)
    $seen = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $queue = [System.Collections.Generic.Queue[string]]::new()
    $queue.Enqueue($File)
    while ($queue.Count) {
        $current = $queue.Dequeue()
        if (-not (Test-Path -LiteralPath $current -PathType Leaf)) { continue }
        $dir = Split-Path -Parent $current
        foreach ($line in (Get-Content -LiteralPath $current)) {
            if ($line -match "^\s*(using|module\s+\w+)\s+'(?<p>[^']+\.bicep)'") {
                $target = [System.IO.Path]::GetFullPath((Join-Path $dir $Matches['p']))
                if ($seen.Add($target)) { $queue.Enqueue($target) }
            }
        }
    }
    return $seen
}

try {
    $baseline = Import-Baseline -Path $BaselinePath
} catch {
    Write-GateFailure $_.Exception.Message
    exit 1
}

$module = Get-Module -ListAvailable -Name $moduleName |
    Where-Object { $_.Version -ge $moduleMin -and $_.Version -le $moduleMax } |
    Sort-Object Version -Descending | Select-Object -First 1
if (-not $module) {
    Write-GateFailure "$moduleName $moduleMin to $moduleMax is not installed, so nothing was analysed. Install it: ./tools/Install-GalleryModule.ps1 -Name $moduleName -MinimumVersion $moduleMin -MaximumVersion $moduleMax"
    exit 1
}
Import-Module $module.Path -Force

$listed = & git -C $RepoRoot ls-files -z
if ($LASTEXITCODE -ne 0) {
    Write-GateFailure "git ls-files failed in '$RepoRoot' (exit $LASTEXITCODE); no file list, so nothing was checked."
    exit 1
}
$tracked = @(($listed -join '') -split "`0" | Where-Object { $_ })
$paramFiles = @($tracked | Where-Object { $_ -like '*.bicepparam' })
$bicepFiles = @($tracked | Where-Object { $_ -like '*.bicep' })

$analysed = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
$notExpanded = [ordered]@{}
$findings = [System.Collections.Generic.List[object]]::new()
$resultCount = 0

Push-Location $RepoRoot
try {
    foreach ($relative in $paramFiles) {
        $full = [System.IO.Path]::GetFullPath((Join-Path $RepoRoot $relative))
        try {
            $result = @(Invoke-PSRule -Module $moduleName -InputPath $relative -Format File -Outcome All -ErrorAction Stop -WarningAction SilentlyContinue)
        } catch {
            $notExpanded[$relative] = ($_.Exception.Message -replace '\s+', ' ')
            continue
        }
        if ($result.Count -eq 0) { $notExpanded[$relative] = 'PSRule returned no result for this file'; continue }
        $resultCount += $result.Count
        [void]$analysed.Add($relative)
        foreach ($reached in (Get-ReferencedBicep -File $full)) { [void]$analysed.Add((Get-RelativePath $reached)) }
        foreach ($r in ($result | Where-Object { $_.Outcome -in 'Fail', 'Error' })) {
            $findings.Add([pscustomobject]@{ File = $relative; Rule = $r.RuleName; Target = $r.TargetName })
        }
    }

    # A .bicep file no parameter file reaches is expanded on its own, with its default parameters.
    $option = New-PSRuleOption -Configuration @{ AZURE_BICEP_FILE_EXPANSION = $true }
    foreach ($relative in ($bicepFiles | Where-Object { -not $analysed.Contains($_) })) {
        try {
            $result = @(Invoke-PSRule -Module $moduleName -InputPath $relative -Format File -Option $option -Outcome All -ErrorAction Stop -WarningAction SilentlyContinue)
        } catch {
            $notExpanded[$relative] = ($_.Exception.Message -replace '\s+', ' ')
            continue
        }
        if ($result.Count -eq 0) { $notExpanded[$relative] = 'PSRule returned no result for this file'; continue }
        $resultCount += $result.Count
        [void]$analysed.Add($relative)
        foreach ($r in ($result | Where-Object { $_.Outcome -in 'Fail', 'Error' })) {
            $findings.Add([pscustomobject]@{ File = $relative; Rule = $r.RuleName; Target = $r.TargetName })
        }
    }
} finally {
    Pop-Location
}

$pairs = @($findings | Group-Object File, Rule | ForEach-Object { $_.Group[0] })
$unanalysed = @(@($paramFiles) + @($bicepFiles) | Where-Object { -not $analysed.Contains($_) })

if ($Update) {
    Write-Host '# Finding entries for the current findings (review each reason before committing):'
    foreach ($p in ($pairs | Sort-Object File, Rule)) {
        Write-Host ("        @{{ File = '{0}'; Rule = '{1}'; Reason = 'TODO' }}" -f $p.File, $p.Rule)
    }
    Write-Host '# Unanalysable entries:'
    foreach ($u in $unanalysed) {
        Write-Host ("        @{{ File = '{0}'; Reason = 'TODO: {1}' }}" -f $u, (($notExpanded[$u] -as [string]) -replace "'", '').Substring(0, [Math]::Min(120, ("$($notExpanded[$u])").Length)))
    }
    exit 0
}

$baselinePairs = @($baseline.Finding | ForEach-Object { "$($_.File)|$($_.Rule)" })
$newPairs = @($pairs | Where-Object { "$($_.File)|$($_.Rule)" -notin $baselinePairs })
$baselineUnanalysable = @($baseline.Unanalysable | ForEach-Object { $_.File })
$newUnanalysed = @($unanalysed | Where-Object { $_ -notin $baselineUnanalysable })

Write-Host "Bicep security check: $moduleName $($module.Version); $($analysed.Count) of $($paramFiles.Count + $bicepFiles.Count) tracked Bicep file(s) analysed, $resultCount rule result(s), $($findings.Count) finding(s) in $($pairs.Count) file and rule pair(s), $($newPairs.Count) outside the baseline, $($unanalysed.Count) not analysed ($($newUnanalysed.Count) outside the baseline)." -ForegroundColor Cyan

$failed = $false
if ($analysed.Count -eq 0 -or $resultCount -eq 0) {
    Write-GateFailure 'PSRule analysed no file. An empty analysis is not a pass: check the module and the file list.'
    $failed = $true
}
foreach ($p in $newPairs) {
    Write-GateFailure "$($p.File): rule $($p.Rule) reports a finding (target $($p.Target)) that the baseline does not hold. Fix the template, or add it to tools/bicep-security-baseline.psd1 with a reason."
    $failed = $true
}
foreach ($u in $newUnanalysed) {
    $why = if ($notExpanded.Contains($u)) { $notExpanded[$u].Substring(0, [Math]::Min(160, $notExpanded[$u].Length)) } else { 'no analysed parameter file reaches it' }
    Write-GateFailure "$u was not analysed ($why) and the baseline's Unanalysable section does not name it."
    $failed = $true
}

if ($failed) { exit 1 }
Write-Host 'Bicep security check passed.' -ForegroundColor Green
exit 0
