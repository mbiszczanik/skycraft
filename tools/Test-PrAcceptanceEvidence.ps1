<#
.SYNOPSIS
    Checks the completeness of lab acceptance evidence in a pull request.
.DESCRIPTION
    Reads the PR body and changed paths without contacting Azure or GitHub.
    Completeness is not proof that a declared test ran or passed.
.PARAMETER Body
    Pull request body.
.PARAMETER ChangedFile
    Changed repository paths.
.PARAMETER BodyPath
    UTF-8 file containing the pull request body.
.PARAMETER ChangedFilePath
    File containing changed paths, one per line.
.EXAMPLE
    ./tools/Test-PrAcceptanceEvidence.ps1 -BodyPath body.md -ChangedFilePath files.txt
.NOTES
    Project: SkyCraft
#>
#Requires -Version 7.0
[CmdletBinding()]
param(
    [string]$Body = '',
    [string[]]$ChangedFile = @(),
    [string]$BodyPath,
    [string]$ChangedFilePath
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Test-PrLiveVerification.ps1') -Body $Body -ChangedFile $ChangedFile -BodyPath $BodyPath -ChangedFilePath $ChangedFilePath

function Get-PrAcceptanceVerdict {
    param(
        [AllowEmptyString()][string]$Body,
        [AllowEmptyCollection()][string[]]$ChangedFile
    )
    if (@($ChangedFile | Where-Object { Test-GatedPath -Path $_ }).Count -eq 0) {
        return [pscustomobject]@{ Pass = $true; Reason = 'no gated path changed' }
    }
    $text = [regex]::Replace($Body, '(?s)<!--.*?-->', '')
    $visible = [System.Collections.Generic.List[string]]::new()
    $fence = ''
    foreach ($line in ($text -split '\r?\n')) {
        if ($fence) {
            if ($line -match ('^ {0,3}' + [regex]::Escape($fence[0]) + '{' + $fence.Length + ',}[ \t]*$')) { $fence = '' }
            continue
        }
        if ($line -match '^ {0,3}(?<fence>`{3,}|~{3,})') {
            $fence = $Matches.fence
            continue
        }
        $visible.Add($line)
    }
    $text = $visible -join "`n"
    $fields = @('Test-conditions', 'Acceptance-head', 'Scripted-check', 'Portal-check',
        'Negative-check', 'Missing-result-check', 'Fallback-deploy')
    foreach ($field in $fields) {
        $entries = [regex]::Matches($text, "(?im)^ {0,3}${field}:[ \t]*(?<value>[^\r\n]*)\r?$")
        if ($entries.Count -ne 1) {
            return [pscustomobject]@{ Pass = $false; Reason = "$field requires exactly one visible entry; found $($entries.Count). See docs/lab-acceptance.md." }
        }
        $value = ($entries[0].Groups['value'].Value -replace '[`*_]', '').Trim()
        $detail = ($value -replace '^(?i)(not-applicable|blocked):\s*', '').Trim()
        if (-not $detail -or $detail -match '(?i)^(<.*|tbd|tba|todo|n/?a|none|unknown|see above|[-.?]+|\u2026)\.?$') {
            return [pscustomobject]@{ Pass = $false; Reason = "$field has no evidence or reason. See docs/lab-acceptance.md." }
        }
        if ($value -match '^(?i)blocked:' -and $detail -notmatch '#\d+') {
            return [pscustomobject]@{ Pass = $false; Reason = "$field is blocked without a tracking issue." }
        }
        if ($value -match '^(?i)blocked:' -and $text -match '(?i)\b(close[sd]?|fix(e[sd])?|resolve[sd]?)\b[ \t]*:?[ \t]*(?:[\w.-]+/[\w.-]+)?#\d+') {
            return [pscustomobject]@{ Pass = $false; Reason = "$field is blocked but the body carries a closing keyword; use Refs and retain the outstanding acceptance." }
        }
    }
    return [pscustomobject]@{ Pass = $true; Reason = 'acceptance record complete; execution and outcomes require evidence review' }
}

if ($MyInvocation.InvocationName -ne '.') {
    if ($BodyPath) { $Body = Get-Content -Raw -LiteralPath $BodyPath }
    if ($ChangedFilePath) { $ChangedFile = @(Get-Content -LiteralPath $ChangedFilePath) }
    $result = Get-PrAcceptanceVerdict -Body $Body -ChangedFile $ChangedFile
    Write-Host $result.Reason
    $code = if ($result.Pass) { 0 } else { 1 }
    $Host.SetShouldExit($code)
    exit $code
}
