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
      verified    The body carries exactly one 'Live-verified: <what ran, where, date, exit codes>'
                  line with a real run, not a placeholder (issue #404). Pass.
      deferred    The body carries exactly one 'Live-verification: deferred -> #<issue>' line
                  and no GitHub closing keyword (close/fix/resolve + #N), so the merge cannot
                  close the issue whose live criterion is still open; exactly one
                  'Live-verification-blocker: <why>' line saying why the live check cannot run
                  in the test environment (issue #404), with a real reason, not blank or a
                  placeholder; and the label 'live-deferral-approved': the maintainer's decision
                  that this PR may merge before its live pass (issue #338). Pass; otherwise fail.
      otherwise   Fail, with the accepted forms in the message.

    Declarations inside HTML comments are ignored, so the PR template can show the syntax.

.PARAMETER BodyPath
    File holding the PR body (the workflow writes github.event.pull_request.body to it).

.PARAMETER ChangedFilePath
    File holding the changed paths, one per line (from the pulls/{n}/files API).

.PARAMETER Body
    The PR body as a string; alternative to -BodyPath for local runs.

.PARAMETER ChangedFile
    The changed paths as an array; alternative to -ChangedFilePath for local runs.

.PARAMETER LabelPath
    File holding the PR's labels, one per line (the workflow reads them from the issues API).

.PARAMETER Label
    The PR's labels as an array; alternative to -LabelPath for local runs.

.EXAMPLE
    .\tools\Test-PrLiveVerification.ps1 -BodyPath body.md -ChangedFilePath files.txt
    The workflow form. Exits 1 when the gate fails.

.EXAMPLE
    .\tools\Test-PrLiveVerification.ps1 -Body (gh pr view 140 --json body -q .body) -ChangedFile (gh pr diff 140 --name-only) -Label (gh pr view 140 --json labels -q '.labels[].name')
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
    [string[]]$ChangedFile,

    [Parameter(Mandatory = $false)]
    [string]$LabelPath,

    [Parameter(Mandatory = $false)]
    [string[]]$Label
)

$ErrorActionPreference = 'Stop'

# Lab content and the tooling that deploys it: anything a live cycle exercises. The gate script,
# the dry-run harness and the tests are not in scope - nothing about them can be verified live.
# That includes a lab's own tests/ directory: its Pester suites stub Az and run in CI (issue #156).
function Test-GatedPath {
    param([Parameter(Mandatory)][string]$Path)

    $normalized = $Path -replace '\\', '/'
    if ($normalized -match '^module-\d[^/]*/(?:[^/]+/)*tests/') { return $false }
    return [bool]($normalized -match '^(module-\d[^/]*/|scripts/|tools/(Invoke-LabCycle\.ps1|Remove-LabCycle\.ps1|Invoke-LabScript\.ps1|LabCycle\.psm1|lab-cycle-manifest\.psd1)$)')
}

function Get-PrGateVerdict {
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$ChangedFile,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Body,
        [AllowEmptyCollection()][string[]]$Label = @()
    )

    # The maintainer's decision to merge a PR before its live pass ran (issue #338).
    $approvalLabel = 'live-deferral-approved'
    # Template placeholders and filler that name no run or blocker (issue #404). Markdown emphasis is
    # stripped first so `TBD` or **none** cannot slip through.
    $placeholder = '(?i)^(?:<[^>]*>.*|tbd|tba|todo|n/?a|none|unknown|see above|-+|\.+|\u2026|\?+)\.?$'
    $isPlaceholder = { param([string]$Text) (($Text -replace '[`*_]', '').Trim()) -match $placeholder }

    $verdict = [PSCustomObject]@{
        Gated      = $false
        Pass       = $true
        Reason     = 'no gated path changed'
        Verified   = $null
        DeferredTo = $null
        Blocker    = $null
    }

    $gatedPaths = @($ChangedFile | Where-Object { Test-GatedPath -Path $_ })
    if ($gatedPaths.Count -eq 0) { return $verdict }
    $verdict.Gated = $true

    # The template shows both forms inside an HTML comment; those must not count.
    $text = [regex]::Replace($Body, '(?s)<!--.*?-->', '')

    $verified = [regex]::Matches($text, '(?im)^[ \t]*Live-verified:[ \t]*(?<what>\S.*?)[ \t]*\r?$')
    $deferred = [regex]::Matches($text, '(?im)^[ \t]*Live-verification:[ \t]*deferred[ \t]*->[ \t]*#(?<issue>\d+)[ \t]*\r?$')
    # A separate key, so the deferred regex above and existing PR bodies stay valid (issue #404).
    $blocker  = [regex]::Matches($text, '(?im)^[ \t]*Live-verification-blocker:[ \t]*(?<why>.*?)[ \t]*\r?$')
    $closing  = [regex]::IsMatch($text, '(?i)\b(close[sd]?|fix(e[sd])?|resolve[sd]?)\b[ \t]*:?[ \t]*(?:[\w.-]+/[\w.-]+)?#\d+')

    $accepted = "Declare exactly one of:`n" +
                "  Live-verified: <what ran, where, date, exit codes>`n" +
                "  Live-verification: deferred -> #<issue tracking the live pass>`n" +
                "  (deferred also needs) Live-verification-blocker: <why the live check cannot run in the test environment>"

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
        if (& $isPlaceholder $verdict.Verified) {
            $verdict.Pass   = $false
            $verdict.Reason = "the 'Live-verified:' line gives no run ('$($verdict.Verified)'). Declare what ran, where, date, exit codes."
            return $verdict
        }
        $verdict.Reason   = "live-verified: $($verdict.Verified)"
        return $verdict
    }

    $verdict.DeferredTo = [int]$deferred[0].Groups['issue'].Value
    if ($closing) {
        $verdict.Pass   = $false
        $verdict.Reason = "live verification is deferred to #$($verdict.DeferredTo), but the body carries a closing keyword (close/fix/resolve #N). A merge would close an issue whose live criterion is still open - use 'Refs #N' and close it after the live pass."
        return $verdict
    }
    $blockerHelp = "A deferral is only for a live check the test environment cannot run: add exactly one line 'Live-verification-blocker: <why the live check cannot run in the test environment>', or run the live check on this branch and declare 'Live-verified: <what ran, where, date, exit codes>'."
    if ($blocker.Count -gt 1) {
        $verdict.Pass   = $false
        $verdict.Reason = "live verification is deferred to #$($verdict.DeferredTo) and the body carries $($blocker.Count) 'Live-verification-blocker:' lines; exactly one is allowed. $blockerHelp"
        return $verdict
    }
    $why = if ($blocker.Count -eq 1) { $blocker[0].Groups['why'].Value.Trim() } else { '' }
    if (-not $why -or (& $isPlaceholder $why)) {
        $verdict.Pass   = $false
        $verdict.Reason = if ($blocker.Count -eq 0) {
            "live verification is deferred to #$($verdict.DeferredTo) but the body has no 'Live-verification-blocker:' line. $blockerHelp"
        } else {
            "live verification is deferred to #$($verdict.DeferredTo) but the 'Live-verification-blocker:' line gives no reason ('$why'). $blockerHelp"
        }
        return $verdict
    }
    $verdict.Blocker = $why
    if (@($Label | ForEach-Object { $_.Trim() }) -notcontains $approvalLabel) {
        $verdict.Pass   = $false
        $verdict.Reason = "live verification is deferred to #$($verdict.DeferredTo) and the PR has no '$approvalLabel' label. Run the live pass and declare 'Live-verified: <what ran, where, date, exit codes>', or, if merging before it is acceptable, the maintainer adds the label."
        return $verdict
    }
    $verdict.Reason = "live verification deferred to #$($verdict.DeferredTo) (blocker: $why), merge approved by the '$approvalLabel' label"
    return $verdict
}

# ── Entry point ─────────────────────────────────────────────────────────────
if ($MyInvocation.InvocationName -ne '.') {
    if ($BodyPath)        { $Body = Get-Content -Raw -LiteralPath $BodyPath }
    if ($ChangedFilePath) { $ChangedFile = @(Get-Content -LiteralPath $ChangedFilePath | Where-Object { $_.Trim() }) }
    if ($null -eq $Body)  { $Body = '' }
    if ($null -eq $ChangedFile) { $ChangedFile = @() }
    if ($LabelPath)       { $Label = @(Get-Content -LiteralPath $LabelPath | Where-Object { $_.Trim() }) }
    if ($null -eq $Label) { $Label = @() }

    $result = Get-PrGateVerdict -ChangedFile $ChangedFile -Body $Body -Label $Label

    if ($result.Pass) {
        Write-Host "[PASS] PR gate: $($result.Reason)" -ForegroundColor Green
        exit 0
    }

    Write-Host "[FAIL] PR gate: $($result.Reason)" -ForegroundColor Red
    $Host.SetShouldExit(1)
    exit 1
}
