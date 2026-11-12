<#
.SYNOPSIS
    CI gate: tracked files must not hold identifying data (GUIDs, e-mail addresses, user paths).

.DESCRIPTION
    gitleaks finds credentials. It does not find the data the project's public-content rule
    excludes: a tenant or subscription id, an object id of a real environment, a real e-mail
    address, a Windows path with a user name. This script scans every tracked file for three
    shapes and fails on a match that is not on the reviewed allowlist
    (tools/identifying-data-allowlist.psd1, every entry carries a reason):

      GUID         tenant, subscription, object and resource ids
      E-mail       any address@domain
      User path    a Windows path under \Users\<name> (the allowlist names placeholders)

    The gate fails, instead of passing quietly, when
      - it scanned no text file at all (an empty file list is a broken checkout, not a clean tree);
      - a tracked binary file has an extension the allowlist does not name (its content was not
        scanned, so the tree cannot be called clean);
      - the allowlist is missing, malformed, or holds an entry without a reason.

    A finding is reported as file:line, kind and a masked value, never the value itself: the
    gate's log is public in a public repository and must not republish what it found.

    Screenshots (PNG) cannot be read by this check. The allowlist names the extension with the
    reason; the review of screenshots stays manual (issue #486).

.PARAMETER RepoRoot
    The repository to scan. Default: the parent of this script's folder.

.PARAMETER AllowlistPath
    The allowlist. Default: tools/identifying-data-allowlist.psd1 next to this script.

.EXAMPLE
    pwsh -NoProfile -File tools/Test-IdentifyingData.ps1
    Scans the tracked files; exit 0 when nothing is left outside the allowlist, 1 otherwise.

.NOTES
    Project: SkyCraft
    Issue: #523
#>

#Requires -Version 7.0

[CmdletBinding()]
param(
    [string]$RepoRoot = (Split-Path -Parent $PSScriptRoot),
    [string]$AllowlistPath = (Join-Path $PSScriptRoot 'identifying-data-allowlist.psd1')
)

$ErrorActionPreference = 'Stop'

$guidPattern = [regex]'\b[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\b'
$emailPattern = [regex]'\b[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+\b'
$userPathPattern = [regex]'(?i)\b[A-Z]:[\\/]+Users[\\/]+(?<name>[^\\/\s"''`<>|*?]+)'

function Write-GateFailure {
    param([string]$Message)
    Write-Host "  [FAIL] $Message" -ForegroundColor Red
}

# Masked form of a finding: enough to find it, not enough to republish it.
function Get-MaskedValue {
    param([string]$Kind, [string]$Value)
    switch ($Kind) {
        'GUID' { return ($Value.Substring(0, 4) + '****-****') }
        'E-mail' {
            $at = $Value.IndexOf('@')
            return ($Value.Substring(0, [Math]::Min(1, $at)) + '***' + $Value.Substring($at))
        }
        default { return ($Value.Substring(0, [Math]::Min(1, $Value.Length)) + '***') }
    }
}

function Import-Allowlist {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) { throw "The allowlist '$Path' does not exist." }
    $list = Import-PowerShellDataFile -LiteralPath $Path

    $problems = [System.Collections.Generic.List[string]]::new()
    foreach ($section in 'GuidValue', 'GuidPattern', 'EmailValue', 'EmailDomain', 'UserPathName', 'BinaryExtension') {
        if (-not $list.ContainsKey($section)) { $problems.Add("section '$section' is missing"); continue }
        foreach ($entry in @($list[$section])) {
            if (-not $entry -or -not $entry.Value -or -not $entry.Reason -or -not "$($entry.Reason)".Trim()) {
                $problems.Add("section '$section' holds an entry without a value or without a reason")
            }
        }
    }
    foreach ($entry in @($list['GuidPattern'])) {
        try { $null = [regex]::new($entry.Value) } catch { $problems.Add("GuidPattern '$($entry.Value)' is not a valid regular expression") }
    }
    if ($problems.Count) { throw ("The allowlist '$Path' is not usable: " + ($problems -join '; ') + '.') }
    return $list
}

function Test-GuidAllowed {
    param([string]$Value, $Allowlist)
    $v = $Value.ToLowerInvariant()
    foreach ($entry in @($Allowlist.GuidValue)) { if ($v -eq "$($entry.Value)".ToLowerInvariant()) { return $true } }
    foreach ($entry in @($Allowlist.GuidPattern)) { if ($v -match $entry.Value) { return $true } }
    return $false
}

function Test-EmailAllowed {
    param([string]$Value, $Allowlist)
    $v = $Value.ToLowerInvariant()
    foreach ($entry in @($Allowlist.EmailValue)) { if ($v -eq "$($entry.Value)".ToLowerInvariant()) { return $true } }
    $domain = $v.Substring($v.IndexOf('@') + 1)
    foreach ($entry in @($Allowlist.EmailDomain)) {
        $d = "$($entry.Value)".ToLowerInvariant()
        # '*.example' allows every address under the .example top level domain.
        if ($d.StartsWith('*.')) { if ($domain.EndsWith($d.Substring(1))) { return $true } }
        elseif ($domain -eq $d) { return $true }
    }
    return $false
}

try {
    $allowlist = Import-Allowlist -Path $AllowlistPath
} catch {
    Write-GateFailure $_.Exception.Message
    exit 1
}

$listed = & git -C $RepoRoot ls-files -z
if ($LASTEXITCODE -ne 0) {
    Write-GateFailure "git ls-files failed in '$RepoRoot' (exit $LASTEXITCODE); no file list, so nothing was checked."
    exit 1
}
$files = @(($listed -join '') -split "`0" | Where-Object { $_ })

$textScanned = 0
$binaryAllowed = 0
$findings = [System.Collections.Generic.List[string]]::new()
$unscanned = [System.Collections.Generic.List[string]]::new()
$allowedExtension = @($allowlist.BinaryExtension | ForEach-Object { "$($_.Value)".ToLowerInvariant() })

foreach ($relative in $files) {
    $full = Join-Path $RepoRoot $relative
    if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { continue }
    $bytes = [System.IO.File]::ReadAllBytes($full)

    $head = [Math]::Min($bytes.Length, 8192)
    $isBinary = $false
    for ($i = 0; $i -lt $head; $i++) { if ($bytes[$i] -eq 0) { $isBinary = $true; break } }
    if ($isBinary) {
        $extension = [System.IO.Path]::GetExtension($relative).TrimStart('.').ToLowerInvariant()
        if ($extension -and $extension -in $allowedExtension) { $binaryAllowed++ } else { $unscanned.Add($relative) }
        continue
    }

    $textScanned++
    $lineNumber = 0
    foreach ($line in ([System.Text.Encoding]::UTF8.GetString($bytes) -split "`n")) {
        $lineNumber++
        foreach ($m in $guidPattern.Matches($line)) {
            if (-not (Test-GuidAllowed -Value $m.Value -Allowlist $allowlist)) {
                $findings.Add("${relative}:${lineNumber}: GUID $(Get-MaskedValue -Kind 'GUID' -Value $m.Value)")
            }
        }
        foreach ($m in $emailPattern.Matches($line)) {
            if (-not (Test-EmailAllowed -Value $m.Value -Allowlist $allowlist)) {
                $findings.Add("${relative}:${lineNumber}: E-mail $(Get-MaskedValue -Kind 'E-mail' -Value $m.Value)")
            }
        }
        foreach ($m in $userPathPattern.Matches($line)) {
            $name = $m.Groups['name'].Value
            $ok = @($allowlist.UserPathName | Where-Object { "$($_.Value)".ToLowerInvariant() -eq $name.ToLowerInvariant() }).Count -gt 0
            if (-not $ok) {
                $findings.Add("${relative}:${lineNumber}: User path $(Get-MaskedValue -Kind 'User path' -Value $name)")
            }
        }
    }
}

Write-Host "Identifying-data check: $textScanned text file(s) scanned, $binaryAllowed allowlisted binary file(s) not readable by this check, $($unscanned.Count) unscanned binary file(s), $($findings.Count) finding(s)." -ForegroundColor Cyan

$failed = $false
if ($textScanned -eq 0) {
    Write-GateFailure 'No text file was scanned. An empty scan is not a clean tree: check the checkout and the file list.'
    $failed = $true
}
foreach ($file in $unscanned) {
    Write-GateFailure "Binary file '$file' was not scanned and its extension is not on the allowlist (BinaryExtension, with a reason)."
    $failed = $true
}
foreach ($finding in $findings) {
    Write-GateFailure "$finding is not on the allowlist. Replace it with a placeholder, or add it to tools/identifying-data-allowlist.psd1 with a reason."
    $failed = $true
}

if ($failed) { exit 1 }
Write-Host 'Identifying-data check passed.' -ForegroundColor Green
exit 0
