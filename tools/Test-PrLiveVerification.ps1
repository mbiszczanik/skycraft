<#
.SYNOPSIS
    PR gate: a pull request that touches lab content must declare its live verification.

.DESCRIPTION
    The live checks - Invoke-LabCycle.ps1, or a lab's Deploy-Bicep.ps1 followed by its
    Test-Lab.ps1 against the SkyCraft subscription - deliberately do not run in CI
    (docs/dry-run-harness.md section 3.2). PR #132 showed what that leaves open: its body said
    the live pass had not been run, it still carried 'Closes #79', and the merge closed the
    issue with its acceptance criterion unmet (ADR-0006).

    This script is the check .github/workflows/pr-gate.yml runs. Given the PR body and the
    list of changed files, it decides:

      not gated   No changed file is lab content (see Test-GatedPath). Pass.
      verified    The body carries exactly one 'Live-verified: <what was run>' line. Pass.
      deferred    The body carries exactly one 'Live-verification: deferred -> #<issue>' line
                  and no GitHub closing keyword (close/fix/resolve + #N), so the merge cannot
                  close the issue whose live criterion is still open. Pass.
      otherwise   Fail, with the two accepted forms in the message.

    Declarations inside HTML comments are ignored, so the PR template can show the syntax.

.PARAMETER BodyPath
    File holding the PR body (the workflow writes github.event.pull_request.body to it).

.PARAMETER ChangedFilePath
    File holding the changed paths, one per line (from the pulls/{n}/files API).

.PARAMETER Body
    The PR body as a string; alternative to -BodyPath for local runs.

.PARAMETER ChangedFile
    The changed paths as an array; alternative to -ChangedFilePath for local runs.

.EXAMPLE
    .\tools\Test-PrLiveVerification.ps1 -BodyPath body.md -ChangedFilePath files.txt
    The workflow form. Exits 1 when the gate fails.

.EXAMPLE
    .\tools\Test-PrLiveVerification.ps1 -Body (gh pr view 140 --json body -q .body) -ChangedFile (gh pr diff 140 --name-only)
    Check an open PR from a developer machine.

.NOTES
    Project: SkyCraft
    Author: Marcin Biszczanik
    Date: 2026-09-21
#>

#Requires -Version 7.0

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$BodyPath,

    [Parameter(Mandatory = $false)]
    [string]$ChangedFilePath,

    [Parameter(Mandatory = $false)]
    [string]$Body,

    [Parameter(Mandatory = $false)]
    [string[]]$ChangedFile
)

$ErrorActionPreference = 'Stop'

# Lab content and the tooling that deploys it: anything a live cycle exercises. The gate script,
# the dry-run harness and the tests are not in scope - nothing about them can be verified live.
function Test-GatedPath {
    param([Parameter(Mandatory)][string]$Path)

    $normalized = $Path -replace '\\', '/'
    return [bool]($normalized -match '^(module-\d[^/]*/|scripts/|tools/(Invoke-LabCycle\.ps1|Remove-LabCycle\.ps1|Invoke-LabScript\.ps1|LabCycle\.psm1|lab-cycle-manifest\.psd1)$)')
}

function Get-PrGateVerdict {
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$ChangedFile,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Body
    )

    $verdict = [PSCustomObject]@{
        Gated      = $false
        Pass       = $true
        Reason     = 'no gated path changed'
        Verified   = $null
        DeferredTo = $null
    }

    $gatedPaths = @($ChangedFile | Where-Object { Test-GatedPath -Path $_ })
    if ($gatedPaths.Count -eq 0) { return $verdict }
    $verdict.Gated = $true

    # The template shows both forms inside an HTML comment; those must not count.
    $text = [regex]::Replace($Body, '(?s)<!--.*?-->', '')

    $verified = [regex]::Matches($text, '(?im)^[ \t]*Live-verified:[ \t]*(?<what>\S.*?)[ \t]*\r?$')
    $deferred = [regex]::Matches($text, '(?im)^[ \t]*Live-verification:[ \t]*deferred[ \t]*->[ \t]*#(?<issue>\d+)[ \t]*\r?$')
    $closing  = [regex]::IsMatch($text, '(?i)\b(close[sd]?|fix(e[sd])?|resolve[sd]?)\b[ \t]*:?[ \t]*(?:[\w.-]+/[\w.-]+)?#\d+')

    $accepted = "Declare exactly one of:`n" +
                "  Live-verified: <what was run - Invoke-LabCycle run id, or labs + date>`n" +
                "  Live-verification: deferred -> #<issue tracking the live pass>"

    if ($verified.Count + $deferred.Count -eq 0) {
        $verdict.Pass   = $false
        $verdict.Reason = "changed lab content ($($gatedPaths.Count) gated file(s)) but the PR body declares no live verification.`n$accepted"
        return $verdict
    }
    if ($verified.Count + $deferred.Count -gt 1) {
        $verdict.Pass   = $false
        $verdict.Reason = "the PR body carries $($verified.Count + $deferred.Count) declarations; exactly one is allowed.`n$accepted"
        return $verdict
    }
    if ($verified.Count -eq 1) {
        $verdict.Verified = $verified[0].Groups['what'].Value
        $verdict.Reason   = "live-verified: $($verdict.Verified)"
        return $verdict
    }

    $verdict.DeferredTo = [int]$deferred[0].Groups['issue'].Value
    if ($closing) {
        $verdict.Pass   = $false
        $verdict.Reason = "live verification is deferred to #$($verdict.DeferredTo), but the body carries a closing keyword (close/fix/resolve #N). A merge would close an issue whose live criterion is still open - use 'Refs #N' and close it after the live pass."
        return $verdict
    }
    $verdict.Reason = "live verification deferred to #$($verdict.DeferredTo)"
    return $verdict
}

# ── Entry point ─────────────────────────────────────────────────────────────
if ($MyInvocation.InvocationName -ne '.') {
    if ($BodyPath)        { $Body = Get-Content -Raw -LiteralPath $BodyPath }
    if ($ChangedFilePath) { $ChangedFile = @(Get-Content -LiteralPath $ChangedFilePath | Where-Object { $_.Trim() }) }
    if ($null -eq $Body)  { $Body = '' }
    if ($null -eq $ChangedFile) { $ChangedFile = @() }

    $result = Get-PrGateVerdict -ChangedFile $ChangedFile -Body $Body

    if ($result.Pass) {
        Write-Host "[PASS] PR gate: $($result.Reason)" -ForegroundColor Green
        exit 0
    }

    Write-Host "[FAIL] PR gate: $($result.Reason)" -ForegroundColor Red
    $Host.SetShouldExit(1)
    exit 1
}
