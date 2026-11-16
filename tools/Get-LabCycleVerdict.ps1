<#
.SYNOPSIS
    Turns a lab cycle's results file into one verdict: passed, failed or not-executed (offline).

.DESCRIPTION
    A scheduled live cycle has three outcomes, and a green check mark must mean only the first
    (issue #527). This script reads the JSON lines tools/Invoke-LabCycle.ps1 writes, the labs the
    run was meant to cover, the cycle's exit code and a run id, and prints ONE JSON line:

      verdict      passed | failed | not-executed
      ran          lab ids that ran in this cycle (status Succeeded or starting with Failed)
      failed       lab ids that failed or, while others ran, have no record of having run
      reason       one sentence, no transcript text
      issueTitle   one constant string, so a workflow can open or update ONE tracking issue
      issueBody    the run id, the exit code and the lab ids, nothing else

    Exit codes: 0 passed, 1 failed, 2 bad input (names the cause on stderr), 3 not-executed.

    not-executed covers a run that never built anything: -AuthFailed set, the results file missing
    or empty, or no record with status Succeeded or Failed*. It is never reported as passed.
    A record with status DryRun or Succeeded(Resumed) did not run in this cycle and does not
    count as run. Skipped records are not failures of their own: the cause lab already is.

    Reads only the results file. It makes no Azure call and writes nothing.

.PARAMETER ResultsPath
    The results .jsonl file of the cycle. One JSON object per line; blank lines are ignored.

.PARAMETER ExpectedLab
    The lab ids the cycle was meant to run, for example 1.2, 2.1.

.PARAMETER CycleExitCode
    The exit code of tools/Invoke-LabCycle.ps1 (its failure count).

.PARAMETER RunId
    The run id of the workflow or the cycle. Letters, digits, dot, dash and underscore only.

.PARAMETER AuthFailed
    The run could not authenticate. Reported as not-executed whatever the file holds.

.EXAMPLE
    pwsh -NoProfile -File tools/Get-LabCycleVerdict.ps1 -ResultsPath results.jsonl -ExpectedLab 1.2,2.1 -CycleExitCode 0 -RunId 1234

.NOTES
    Project: SkyCraft
    Issue: #527
#>

[CmdletBinding()]
param(
    [string]$ResultsPath,

    [string[]]$ExpectedLab,

    [Nullable[int]]$CycleExitCode,

    [string]$RunId,

    [switch]$AuthFailed
)

$ErrorActionPreference = 'Stop'

# Constant on purpose: one title lets a workflow find and update the open issue.
$issueTitle = 'Scheduled lab cycle did not pass'
$idPattern = '^[0-9A-Za-z._-]+$'

function Exit-WithBadInput {
    param([string]$Cause)
    [Console]::Error.WriteLine("Get-LabCycleVerdict: $Cause")
    exit 2
}

# -File passes '1.2,2.1' as one string
$ExpectedLab = @($ExpectedLab | ForEach-Object { $_ -split ',' } | Where-Object { $_ })

if (-not $ResultsPath) { Exit-WithBadInput 'mandatory parameter -ResultsPath is missing.' }
if (-not $ExpectedLab -or $ExpectedLab.Count -eq 0) { Exit-WithBadInput 'mandatory parameter -ExpectedLab is missing.' }
if ($null -eq $CycleExitCode) { Exit-WithBadInput 'mandatory parameter -CycleExitCode is missing.' }
if (-not $RunId) { Exit-WithBadInput 'mandatory parameter -RunId is missing.' }
if ($RunId -notmatch $idPattern) { Exit-WithBadInput '-RunId may hold only letters, digits, dot, dash and underscore.' }
foreach ($lab in $ExpectedLab) {
    if ($lab -notmatch $idPattern) { Exit-WithBadInput '-ExpectedLab ids may hold only letters, digits, dot, dash and underscore.' }
}

function Write-Verdict {
    param(
        [string]$Verdict,
        [string[]]$Ran,
        [string[]]$Failed,
        [string]$Reason,
        [int]$Code
    )
    $body = "Run id: $RunId`nVerdict: $Verdict`nExit code: $CycleExitCode`nLabs that ran: $(@($Ran) -join ', ')`nLabs failed or missing: $(@($Failed) -join ', ')"
    $result = [ordered]@{
        verdict    = $Verdict
        ran        = @($Ran)
        failed     = @($Failed)
        reason     = $Reason
        issueTitle = $issueTitle
        issueBody  = $body
    }
    Write-Output ($result | ConvertTo-Json -Compress)
    exit $Code
}

if ($AuthFailed) {
    Write-Verdict -Verdict 'not-executed' -Ran @() -Failed @() -Reason 'The run could not authenticate, so no lab was built.' -Code 3
}

if (-not (Test-Path -LiteralPath $ResultsPath -PathType Leaf)) {
    Write-Verdict -Verdict 'not-executed' -Ran @() -Failed @() -Reason 'The results file does not exist, so no lab ran.' -Code 3
}

$lines = @(Get-Content -LiteralPath $ResultsPath | Where-Object { $_.Trim() })
if ($lines.Count -eq 0) {
    Write-Verdict -Verdict 'not-executed' -Ran @() -Failed @() -Reason 'The results file is empty, so no lab ran.' -Code 3
}

$records = [System.Collections.Generic.List[object]]::new()
$lineNumber = 0
foreach ($line in $lines) {
    $lineNumber++
    try {
        $record = $line | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        Exit-WithBadInput "results line $lineNumber is not valid JSON."
    }
    if ($record -isnot [pscustomobject]) { Exit-WithBadInput "results line $lineNumber is not a JSON object." }
    $records.Add($record)
}

# Per lab: did a record show it ran, did one show it fail. Ids that are not plain ids are dropped.
$ranIds = [System.Collections.Generic.List[string]]::new()
$failedIds = [System.Collections.Generic.List[string]]::new()
foreach ($record in $records) {
    $id = [string]$record.Id
    $status = [string]$record.Status
    if ($id -notmatch $idPattern) { continue }
    $isFailure = $status -like 'Failed*'
    $isRun = $isFailure -or $status -eq 'Succeeded'
    if ($isRun -and -not $ranIds.Contains($id)) { $ranIds.Add($id) }
    if ($isFailure -and -not $failedIds.Contains($id)) { $failedIds.Add($id) }
}

if ($ranIds.Count -eq 0) {
    Write-Verdict -Verdict 'not-executed' -Ran @() -Failed @() -Reason 'No record shows a lab that ran (status Succeeded or Failed*).' -Code 3
}

$missing = @($ExpectedLab | Where-Object { -not $ranIds.Contains($_) } | Select-Object -Unique)
$failedAll = @($failedIds) + @($missing | Where-Object { -not $failedIds.Contains($_) })

if ($CycleExitCode -ne 0 -or $failedIds.Count -gt 0 -or $missing.Count -gt 0) {
    $parts = [System.Collections.Generic.List[string]]::new()
    if ($CycleExitCode -ne 0) { $parts.Add("the cycle exited $CycleExitCode") }
    if ($failedIds.Count -gt 0) { $parts.Add("lab(s) failed: $($failedIds -join ', ')") }
    if ($missing.Count -gt 0) { $parts.Add("expected lab(s) have no run record: $($missing -join ', ')") }
    Write-Verdict -Verdict 'failed' -Ran $ranIds -Failed $failedAll -Reason (($parts -join '; ') + '.') -Code 1
}

Write-Verdict -Verdict 'passed' -Ran $ranIds -Failed @() -Reason 'Every expected lab succeeded and the cycle exited 0.' -Code 0
