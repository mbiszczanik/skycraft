<#
.SYNOPSIS
    Deploys and validates every SkyCraft lab in dependency order, and reports what happened.

.DESCRIPTION
    Reads tools/lab-cycle-manifest.psd1, orders the phases so none precedes a dependency, and runs
    each one. A phase is deploy, then any post-deploy step, then validate; a non-zero exit at any
    step fails the phase and skips everything downstream of it, naming the phase that caused each
    skip. Independent branches of the graph carry on.

    STOP ON A FAILED DEPLOY, CONTINUE PAST A FAILED VALIDATION - which is what issue #73 asks for,
    and both halves matter. A lab whose deployment failed has created nothing for the labs below it
    to build on, so running them produces a second failure for one cause. A lab that deployed and
    then failed its own validator has still created everything the labs below it need, so the run
    carries on and the failure is reported. The distinction lives in the graph rather than in the
    exit code: both count as failures, and the exit code is the count.

    A failure the platform asked us to wait out - a 429, a 503, SkuNotAvailable, AllocationFailed -
    is retried with backoff before the phase is declared failed. Nothing else is retried: a policy
    denial or a failing assertion cannot come out differently on a second attempt, and retrying it
    turns one clear failure into three separated by waiting.

    A phase killed at its timeout is reported Failed(Timeout) rather than Failed. One says the lab
    is broken, the other says our estimate was wrong, and they send an operator to different
    places. For the graph they mean the same thing: both skip everything downstream.

    State is written after every step and the in-flight phase is marked Running, so an interruption
    leaves the truth behind rather than a lie. -Resume re-runs everything that is not recorded
    Succeeded, including anything left Running: that phase is neither finished nor untouched, and
    re-running an idempotent deploy is the only reconciliation available without asking Azure.

    Results are appended to a JSONL file as each phase finishes, one object per line. That is the
    machine-readable history, and it is append-only for a reason: a run measured in hours that is
    killed at hour three would otherwise take every result with it, and those are the results that
    matter most.

    TEARDOWN IS A SEPARATE SCRIPT. Unless -SkipCleanup is passed, this hands off to
    tools/Remove-LabCycle.ps1 when the phases are done. It lives apart because it has to be
    runnable on its own - after a crash, after a -SkipCleanup run, or a week later - and because
    deleting things earns its own -WhatIf and its own confirmation rather than inheriting this
    script's.

    WHAT THESE FILES CONTAIN, AND WHY THEY ARE GITIGNORED. The transcripts under -LogDirectory
    capture whatever a lab script printed, which includes Az error streams and the deployment
    parameter values each script echoes before deploying; a deployment output can carry a
    connection string or an access key. The state file records phase ids and statuses only, and no
    output. Nothing here is redacted - the run needs the detail to be diagnosable - so
    .gitignore keeps all of it out of history and tests/Gitignore.Tests.ps1 asserts that through
    git check-ignore. Treat a transcript as a secret: do not paste one into an issue or a chat
    without reading it first.

    ON THE $null GUARDS THAT LOOK REDUNDANT. Several loops here test a collection before wrapping
    it in @(). That is deliberate: @($null) is a one-element array containing $null, so an
    unguarded foreach over an absent optional field runs once with an empty item. It has produced
    phantom test cases and a report claiming residue that did not exist. The manifest is full of
    optional fields, so the guards stay.

.PARAMETER SubscriptionId
    The subscription this run is allowed to touch. Mandatory, and compared against the context's
    id rather than its name.

    Not ceremony: on 2026-08-02 an Azure context changed identity mid-session and a cleanup query
    returned 'nothing found' - correctly, against an unrelated production subscription - one line
    before a -Force delete. A parameter that must be supplied is what makes that impossible rather
    than unlikely, which is why it has no default to fall back on.

.PARAMETER OpsEmail
    The address lab 5.1 attaches its action group to. Mandatory on that lab's deploy script, so the
    run refuses to start when a selected phase needs it and it was not given - rather than reaching
    lab 5.1 an hour in and hanging on a prompt no one is watching.

    Not needed when -Labs selects nothing that requires it.

.PARAMETER Labs
    Run only these labs, by phase id - '5.1', '5.2'. Everything else in the manifest is left out of
    the plan entirely rather than reported as skipped, because it was never part of this run.

    A DEPENDENCY OUTSIDE THE SELECTION IS TREATED AS ALREADY SATISFIED. '-Labs 5.2' runs lab 5.2
    against whatever 5.1 left behind last time; it does not pull 5.1 in, and it does not refuse.
    That is the useful behaviour for the thing this switch is for - re-running one lab after fixing
    it - and it is why the header says so out loud. Lab 5.2's own deploy script still gates on 5.1's
    workspace, so a selection whose prerequisites really are missing fails on the lab's own check
    with the lab's own message.

.PARAMETER ManifestPath
    The manifest to run. Defaults to the one beside this script. Tests point it at fixture graphs.

.PARAMETER LabRoot
    Repository root, used to resolve each phase's Lab path.

.PARAMETER LogDirectory
    Where per-step transcripts are written. One file per step, named for the phase.

.PARAMETER ReportPath
    The human-readable run report.

.PARAMETER ResultsPath
    The JSONL results file. Appended to, never rewritten.

.PARAMETER PhaseRunner
    A scriptblock invoked once per step, receiving one hashtable and returning an exit code:

        @{ Phase = <manifest phase>; Kind = 'Deploy'|'PostDeploy'|'Test'; Arguments = <hashtable>; TimeoutMs = <int> }

    Injectable so the ordering and failure-propagation tests can substitute a fake and stay
    offline. The default is the real process runner, so the tested path is the shipped path.

.PARAMETER LockPath
    Run-lock file naming the process that holds the cycle.

.PARAMETER StatePath
    Where per-step state is written, and what -Resume reads.

.PARAMETER ContextProbe
    Returns the current Azure context. Injectable so the tests stay offline.

.PARAMETER PreflightRunner
    Runs the preflight checks. Injectable for the same reason.

.PARAMETER ConfirmRunner
    Asks for confirmation of the plan. Suppressed entirely by -Yes.

.PARAMETER SleepRunner
    Waits between retries. Injectable so the retry tests do not wait 30 real seconds.

.PARAMETER RemoveScriptPath
    The teardown script this hands off to. Defaults to tools/Remove-LabCycle.ps1 beside this one.

.PARAMETER MaxAttempts
    How many times a retryable step is attempted. Three, not unlimited: regional capacity can stay
    unavailable for hours, and a run that keeps retrying one capacity failure never reaches the
    phases that would have worked.

.PARAMETER DryRun
    Print the plan and touch nothing. No phase runs, and no teardown either.

.PARAMETER Yes
    Skip the plan confirmation. The teardown script is called with -Confirm:$false regardless, so
    an unattended run does not stop on its confirmation either.

.PARAMETER SkipCleanup
    Leave every lab standing. Nothing is torn down and Remove-LabCycle.ps1 is not called.

.PARAMETER Resume
    Continue a previous run rather than starting one.

.EXAMPLE
    .\Invoke-LabCycle.ps1 -SubscriptionId 00000000-0000-0000-0000-000000000000 -DryRun

    Prints the sixteen-phase plan and touches nothing.

.EXAMPLE
    .\Invoke-LabCycle.ps1 -SubscriptionId 00000000-0000-0000-0000-000000000000 -OpsEmail ops@example.com -Yes

    The full cycle: deploy and validate every lab, then tear everything down.

.EXAMPLE
    .\Invoke-LabCycle.ps1 -SubscriptionId 00000000-0000-0000-0000-000000000000 -Labs 5.2 -SkipCleanup -Yes

    Re-runs lab 5.2 alone against what an earlier run left standing, and leaves it standing.

.NOTES
    Project: SkyCraft
    Issue:   #73

    There is deliberately no -Force. In this repository -Force means one thing - what the engine
    passes to a child lab script - and a second meaning for that word, on a switch where being
    wrong deletes things, is not worth the convenience.
#>

#Requires -Version 7.0

# Read inside GetNewClosure scriptblocks, which PSScriptAnalyzer cannot correlate with the
# parameter block. Targeted at one name each so a genuinely unused parameter added later still
# surfaces.
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'LabRoot', Justification = 'False positive: read inside the default PhaseRunner closure.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'ResultsPath', Justification = 'False positive: read inside the $recordResult closure.')]
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$SubscriptionId,

    [Parameter()]
    [string]$OpsEmail,

    [Parameter()]
    [AllowEmptyCollection()]
    [string[]]$Labs = @(),

    [Parameter()]
    [string]$ManifestPath = (Join-Path $PSScriptRoot 'lab-cycle-manifest.psd1'),

    [Parameter()]
    [string]$LabRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path,

    [Parameter()]
    [string]$LogDirectory = (Join-Path $PSScriptRoot 'lab-cycle-logs'),

    [Parameter()]
    [string]$ReportPath = (Join-Path $PSScriptRoot 'lab-cycle-report.md'),

    [Parameter()]
    [string]$ResultsPath = (Join-Path $PSScriptRoot 'lab-cycle-logs/lab-cycle-results.jsonl'),

    [Parameter()]
    [scriptblock]$PhaseRunner,

    [Parameter()]
    [string]$LockPath = (Join-Path $PSScriptRoot '.lab-cycle-lock.json'),

    [Parameter()]
    [string]$StatePath = (Join-Path $PSScriptRoot '.lab-cycle-state.json'),

    # These are injectable so the engine's own tests stay offline. The defaults reach Azure and the
    # console; CI has neither credentials nor a human, and a test needing either would never run.
    [Parameter()]
    [scriptblock]$ContextProbe = { Get-AzContext },

    [Parameter()]
    [scriptblock]$PreflightRunner,

    [Parameter()]
    [scriptblock]$ConfirmRunner = { Read-Host 'Proceed with this plan? (y/N)' },

    [Parameter()]
    [scriptblock]$SleepRunner = { param($Seconds) Start-Sleep -Seconds $Seconds },

    [Parameter()]
    [string]$RemoveScriptPath = (Join-Path $PSScriptRoot 'Remove-LabCycle.ps1'),

    [Parameter()]
    [ValidateRange(1, 10)]
    [int]$MaxAttempts = 3,

    [Parameter()]
    [switch]$DryRun,

    [Parameter()]
    [switch]$Yes,

    [Parameter()]
    [switch]$SkipCleanup,

    [Parameter()]
    [switch]$Resume
)

$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'LabCycle.psm1') -Force

# The default runner is the real one, so the path every ordinary caller takes is the path the
# tests exercise. Defined here rather than as a parameter default because it closes over $LabRoot,
# $LogDirectory and the shim path, and a parameter default cannot see other parameters.
if (-not $PhaseRunner) {
    $shimPath = Join-Path $PSScriptRoot 'Invoke-LabScript.ps1'
    $PhaseRunner = {
        param($Invocation)

        $phase      = $Invocation.Phase
        $scriptName = if ($Invocation.Script) { $Invocation.Script } else {
            switch ($Invocation.Kind) {
                'Deploy'   { 'Deploy-Bicep.ps1' }
                'Test'     { 'Test-Lab.ps1' }
                'Teardown' { 'Remove-LabResource.ps1' }
                default    { throw "No script name for step kind '$($Invocation.Kind)'." }
            }
        }

        # Every lab is run from its own scripts/ folder, which is what the lab scripts' own help
        # shows and what their relative paths assume.
        $scriptsDir = Join-Path (Join-Path $LabRoot $phase.Lab) 'scripts'
        $safeId     = $phase.Id -replace '[^A-Za-z0-9._-]', '-'

        $result = Invoke-LabScriptProcess -ShimPath $shimPath `
            -ScriptPath (Join-Path $scriptsDir $scriptName) `
            -Arguments $Invocation.Arguments `
            -WorkingDirectory $scriptsDir `
            -TimeoutMs $Invocation.TimeoutMs `
            -TranscriptPath (Join-Path $LogDirectory "$safeId.$($Invocation.Kind.ToLowerInvariant()).log") `
            -StdinAnswers @($Invocation.StdinAnswers)

        # Returned whole rather than as a bare exit code. A timeout must stay distinguishable from
        # an ordinary failure, and the captured output is what the retry classifier reads.
        [pscustomobject]@{
            ExitCode = if ($result.TimedOut) { 124 } else { $result.ExitCode }
            TimedOut = $result.TimedOut
            Output   = $result.Output
        }
    }.GetNewClosure()
}

if (-not (Test-Path -LiteralPath $ManifestPath)) {
    Write-Host "[ERROR] Manifest not found: $ManifestPath" -ForegroundColor Red
    $Host.SetShouldExit(2)
    exit 2
}
$manifest = Import-PowerShellDataFile -LiteralPath $ManifestPath

$live     = @($manifest.Phases | Where-Object { -not $_.Excluded })
$excluded = @($manifest.Phases | Where-Object { $_.Excluded })

# -- -Labs -----------------------------------------------------------------------------------
# Applied before ordering, so a dependency outside the selection is simply not in the set that
# Get-PhaseOrder walks - which is exactly the 'treated as already satisfied' behaviour the help
# describes, rather than a second code path that has to agree with it.
$selected = $null
if (@($Labs).Count -gt 0) {
    $known = @($manifest.Phases | ForEach-Object { $_.Id })
    $unknown = @($Labs | Where-Object { $_ -notin $known })
    if ($unknown.Count -gt 0) {
        Write-Host "[ERROR] -Labs names phases that are not in the manifest: $($unknown -join ', ')" -ForegroundColor Red
        Write-Host "        Known phases: $($known -join ', ')" -ForegroundColor Gray
        $Host.SetShouldExit(2)
        exit 2
    }
    $selected = @($Labs)
    $live     = @($live | Where-Object { $_.Id -in $selected })
    # An exclusion outside the selection is not this run's business, so it is not reported as one.
    $excluded = @($excluded | Where-Object { $_.Id -in $selected })
}

# -- -OpsEmail -------------------------------------------------------------------------------
# Checked here rather than made Mandatory on the parameter, because it is only mandatory for some
# selections. Mandatory would prompt for it on a '-Labs 2.1' run that has no use for it, and a
# prompt is the one thing an unattended cycle must not contain.
$needsOpsEmail = @($live | Where-Object { $_.RequiresOpsEmail })
if ($needsOpsEmail.Count -gt 0 -and [string]::IsNullOrWhiteSpace($OpsEmail)) {
    Write-Host "[ERROR] -OpsEmail is required: $(@($needsOpsEmail | ForEach-Object { $_.Id }) -join ', ') cannot deploy without it." -ForegroundColor Red
    Write-Host '        Its deploy script declares -OpsEmail mandatory, so without it the phase stops on a prompt nobody is watching.' -ForegroundColor Gray
    $Host.SetShouldExit(2)
    exit 2
}

# Ordering happens before anything runs. A cycle throws out of Get-PhaseOrder, and that is the
# intended behaviour rather than something to catch and continue past: half a cyclic graph
# deployed is resources left behind that the run cannot reason about.
$order = Get-PhaseOrder -Phases $live

$byId = @{}
foreach ($phase in $live) { $byId[$phase.Id] = $phase }

$results = [System.Collections.Generic.List[hashtable]]::new()
$status  = @{}
$cause   = @{}

# Teardown results are kept apart from phase results all the way to the report, because they
# answer a different question and a reader who conflates them debugs the wrong thing.
$teardownResults = [System.Collections.Generic.List[hashtable]]::new()
$leftBehind      = [System.Collections.Generic.List[hashtable]]::new()

$runId = [guid]::NewGuid().ToString('N')

# -- Results, appended as they happen ----------------------------------------------------------
# Every phase outcome goes to the JSONL file the moment it is known, including Skipped and
# Excluded. A results file that held only successes would be the least useful half of the run.
$recordResult = {
    param($Record)
    if ($DryRun) { return }
    $line = [ordered]@{ RunId = $runId; At = (Get-Date).ToString('o'); SubscriptionId = $SubscriptionId }
    foreach ($key in $Record.Keys) { $line[$key] = $Record[$key] }
    Write-LabCycleResultLine -Path $ResultsPath -Record $line
}.GetNewClosure()

# -- State ---------------------------------------------------------------------------------
# Written after every STEP, not every phase. The risk window is during a step: a phase that
# deploys for twenty minutes and then dies has created real Azure resources, and a state file
# that only learns of them when the phase completes has no record that they exist.
$stepInFlight = @{}
$stateWriter = {
    $snapshot = [ordered]@{
        SubscriptionId = $SubscriptionId
        ManifestPath   = $ManifestPath
        RunId          = $runId
        UpdatedAt      = (Get-Date).ToString('o')
        Phases         = [ordered]@{}
    }
    foreach ($key in ($status.Keys | Sort-Object)) {
        # Step is what makes a per-step write worth making. Without it every write inside a phase
        # produces byte-identical content, the writes are unobservable, and 'after every step' is
        # a claim no test can check. It is also the more useful fact after an interruption, since
        # 'died during Test' and 'died during Deploy' need different reconciliation.
        $snapshot.Phases[$key] = @{ Status = $status[$key]; Cause = $cause[$key]; Step = $stepInFlight[$key] }
    }
    $directory = Split-Path -Parent $StatePath
    if ($directory -and -not (Test-Path -LiteralPath $directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }
    $snapshot | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $StatePath
}.GetNewClosure()

# -- Resume --------------------------------------------------------------------------------
# 'Succeeded' is the only status a resume trusts. 'Running' means the engine died holding that
# phase: it is neither done - claiming so would skip a phase whose resources may be half-created -
# nor untouched, and re-running an idempotent deploy is the only reconciliation available without
# asking Azure. Everything else is re-run because it did not finish.
$resumed = @{}
if ($Resume -and (Test-Path -LiteralPath $StatePath)) {
    $previous = Get-Content -Raw -LiteralPath $StatePath | ConvertFrom-Json

    if ($previous.SubscriptionId -and $previous.SubscriptionId -ne $SubscriptionId) {
        throw "State at '$StatePath' belongs to subscription $($previous.SubscriptionId), but this run is for $SubscriptionId. Skipping phases because they succeeded somewhere else is the same class of mistake as deploying into a subscription this run was not given."
    }

    foreach ($property in @($previous.Phases.PSObject.Properties)) {
        if ($property.Value.Status -eq 'Succeeded') { $resumed[$property.Name] = $true }
    }
    Write-Host "  -Resume: $($resumed.Count) phase(s) already succeeded and will not be run again" -ForegroundColor Gray
}

Write-Host ''
Write-Host "Lab cycle - $($live.Count) phases, $($excluded.Count) excluded" -ForegroundColor Cyan
Write-Host "  Subscription: $SubscriptionId" -ForegroundColor Gray
Write-Host "  Manifest:     $ManifestPath" -ForegroundColor Gray
Write-Host "  Run id:       $runId" -ForegroundColor Gray
if ($DryRun) { Write-Host '  DRY RUN - nothing will be deployed' -ForegroundColor Yellow }
if ($selected) {
    Write-Host "  -Labs: only $($selected -join ', '). Dependencies outside the selection are assumed already deployed; each lab's own prerequisite gate is what checks that." -ForegroundColor Yellow
}
if ($Yes)         { Write-Host '  -Yes: the plan will not be confirmed before it runs' -ForegroundColor Gray }
if ($SkipCleanup) { Write-Host '  -SkipCleanup: nothing will be torn down; every lab is left standing' -ForegroundColor Yellow }
if ($Resume)      { Write-Host "  -Resume: continuing from $StatePath; phases that already succeeded will not be re-run" -ForegroundColor Gray }
Write-Host ''

# -- Preflight -------------------------------------------------------------------------------
# Before anything. A failed check is a hard stop and the first one ends the run: the later
# checks assume the earlier ones held, so continuing past one asks a question whose answer cannot
# be trusted. A dry run still preflights - checking the plan against a subscription you are not
# actually on is the mistake -DryRun exists to prevent.
#
# A check may instead pass carrying a warning, and the run continues. That is not a softening of
# the gate: it exists because lab 5.1's teardown reserves its Log Analytics name on every clean
# run, and Azure was measured to recover that name rather than refuse it. Treating it as fatal
# would mean a successful run stopped the next one from ever starting.
if (-not $PreflightRunner) {
    $PreflightRunner = {
        Test-LabCyclePreflight -SubscriptionId $SubscriptionId `
            -Guards $manifest.SoftDeleteGuards `
            -LockPath $LockPath `
            -ContextProbe $ContextProbe
    }.GetNewClosure()
}

Write-Host '  Preflight' -ForegroundColor Cyan
$checks = @(& $PreflightRunner)
foreach ($check in $checks) {
    if (-not $check.Ok) { Write-Host "    [STOP] $($check.Name): $($check.Detail)" -ForegroundColor Red }
    elseif ($check.Severity -eq 'Warning') { Write-Host "    [WARN] $($check.Name): $($check.Detail)" -ForegroundColor Yellow }
    else { Write-Host "    [ OK ] $($check.Name): $($check.Detail)" -ForegroundColor DarkGray }
}
$blocked = @($checks | Where-Object { -not $_.Ok })
if ($blocked.Count -gt 0) {
    Write-Host ''
    Write-Host "[ERROR] Preflight stopped the run: $($blocked[0].Name)" -ForegroundColor Red
    $Host.SetShouldExit(3)
    exit 3
}
Write-Host ''

# The plan is printed before the confirmation, not after, so what is being agreed to is on screen.
Write-Host '  Plan' -ForegroundColor Cyan
foreach ($id in $order) { Write-Host "    $id  ($($byId[$id].Lab))" -ForegroundColor DarkGray }
if (-not $SkipCleanup -and -not $DryRun) {
    Write-Host "    then teardown, through $RemoveScriptPath" -ForegroundColor DarkGray
}
Write-Host ''

if (-not $Yes) {
    $answer = & $ConfirmRunner
    if ("$answer" -notmatch '^(y|yes)$') {
        Write-Host '[ABORT] Not confirmed; nothing was run.' -ForegroundColor Yellow
        $Host.SetShouldExit(4)
        exit 4
    }
}

if (-not $DryRun) { New-LabCycleLock -LockPath $LockPath }

try {

foreach ($id in $order) {
    # BETWEEN EVERY PHASE, not only at startup. The context drift this catches happened inside a
    # single working session on 2026-08-02; a run measured in hours is exposed to it far longer,
    # and the phase about to start would deploy into whatever subscription the context now names.
    if (-not $DryRun) {
        $stillOurs = Test-LabCycleSubscription -SubscriptionId $SubscriptionId -ContextProbe $ContextProbe
        if (-not $stillOurs.Ok) {
            Write-Host "[ERROR] Subscription changed mid-run: $($stillOurs.Detail)" -ForegroundColor Red
            throw "Subscription context drifted before phase '$id'. Stopping rather than deploying into a subscription this run was not given."
        }
    }

    $phase = $byId[$id]

    # A phase a previous run finished is not run again, and is reported as Succeeded(Resumed)
    # rather than Succeeded - the report must not claim this run deployed something it did not.
    if ($resumed[$id]) {
        $status[$id] = 'Succeeded'
        $record = @{ Id = $id; Lab = $phase.Lab; Status = 'Succeeded(Resumed)'; ExitCode = 0; Cause = $null; FailedStep = $null; DurationMs = 0; Attempts = 0 }
        $results.Add($record)
        & $recordResult $record
        Write-Host "  [SKIP] $id - succeeded in the run being resumed" -ForegroundColor DarkGray
        continue
    }

    # A phase is skipped when anything it depends on did not succeed. The cause recorded is the
    # phase that actually failed, not the intermediate one, so the report names the thing to fix:
    # a dependency that was itself skipped carries its own cause forward.
    #
    # 'Failed*' rather than 'Failed', so a phase killed at its timeout blocks its dependents exactly
    # as a failed one does. The status distinguishes them for the operator; the graph must not.
    $blocker = @($phase.DependsOn | Where-Object { $status[$_] -like 'Failed*' -or $status[$_] -eq 'Skipped' }) | Select-Object -First 1
    if ($blocker) {
        $status[$id] = 'Skipped'
        $cause[$id]  = if ($cause.ContainsKey($blocker)) { $cause[$blocker] } else { $blocker }
        $record = @{ Id = $id; Lab = $phase.Lab; Status = 'Skipped'; ExitCode = $null; Cause = $cause[$id]; FailedStep = $null; DurationMs = 0 }
        $results.Add($record)
        & $recordResult $record
        Write-Host "  [SKIP] $id - depends on $($cause[$id])" -ForegroundColor Yellow
        continue
    }

    if ($DryRun) {
        $status[$id] = 'DryRun'
        $results.Add(@{ Id = $id; Lab = $phase.Lab; Status = 'DryRun'; ExitCode = $null; Cause = $null; FailedStep = $null; DurationMs = 0 })
        Write-Host "  [PLAN] $id - $($phase.Lab) ($($phase.ParamFile))" -ForegroundColor Gray
        continue
    }

    # Deploy, then any post-deploy step, then validate. The first non-zero code stops the phase:
    # validating a deployment that failed reports a second failure for one cause, and the report
    # would then carry two entries for one broken lab.
    #
    # The deploy arguments are copied rather than used in place, because -OpsEmail is merged into
    # them and the manifest hashtable would otherwise be mutated for the rest of the process.
    $deployArguments = @{}
    if ($phase.Deploy) { foreach ($key in $phase.Deploy.Keys) { $deployArguments[$key] = $phase.Deploy[$key] } }
    if ($phase.RequiresOpsEmail) { $deployArguments['OpsEmail'] = $OpsEmail }

    # '$null -ne' rather than @() around it, and this is the $null-collection trap the header warns
    # about doing real damage: @($null) is a ONE-element array holding $null, which the runner reads
    # as 'there is an answer to feed'. Every phase would then have its stdin redirected and closed,
    # so a lab that reached an unplanned prompt would throw on it instead of waiting where an
    # operator could see it. Only lab 2.2 declares answers; every other phase must get none.
    $stdinAnswers = if ($null -ne $phase.StdinAnswers) { @($phase.StdinAnswers) } else { @() }

    $steps = [System.Collections.Generic.List[hashtable]]::new()
    $steps.Add(@{ Kind = 'Deploy'; Arguments = $deployArguments; StdinAnswers = $stdinAnswers })
    if ($phase.PostDeploy) { $steps.Add(@{ Kind = 'PostDeploy'; Arguments = $phase.PostDeploy.Arguments; Script = $phase.PostDeploy.Script }) }

    # TestExcluded names a validation this environment cannot perform, and carries the reason. It is
    # not a way to silence an inconvenient validator: the phase still deploys, the reason is printed
    # and reported, and coverage refuses to call the phase validated. Only the check is skipped, and
    # only because running it would report a failure that no deployment could ever fix.
    if ($phase.TestExcluded) {
        Write-Host "  [SKIP] $id Test - $($phase.TestExcluded)" -ForegroundColor Yellow
    }
    else {
        $steps.Add(@{ Kind = 'Test'; Arguments = $phase.Test })
    }

    $started       = [datetime]::UtcNow
    $exitCode      = 0
    $failedStep    = $null
    $timedOut      = $false
    $phaseAttempts = 1

    # Marked Running before the first step and written immediately, so an interruption anywhere
    # inside the phase leaves the truth behind: not Succeeded, which is a lie, and not absent,
    # which reads as never started.
    $status[$id] = 'Running'
    & $stateWriter

    foreach ($step in $steps) {
        $invocation = @{
            Phase        = $phase
            Kind         = $step.Kind
            Script       = $step.Script
            Arguments    = $step.Arguments
            # Same guard, for the same reason: only the Deploy step carries answers, and the
            # PostDeploy and Test steps must not inherit a one-element array holding $null.
            StdinAnswers = if ($null -ne $step.StdinAnswers) { @($step.StdinAnswers) } else { @() }
            TimeoutMs    = $phase.TimeoutMs
        }

        # RETRY, BOUNDED, AND ONLY FOR WHAT THE PLATFORM ASKED US TO WAIT OUT. A single transient
        # 429 on a root phase would otherwise cascade into every phase below it and the run
        # produces nothing usable. Retrying anything else turns one clear failure into three.
        # Recorded before the step runs, not after, so the file names the step that is in flight
        # rather than the last one that finished. That is the fact an interruption needs.
        $stepInFlight[$id] = $step.Kind
        & $stateWriter

        $attempt = 1
        while ($true) {
            $outcome = & $PhaseRunner $invocation

            # A runner may hand back a bare exit code or a full outcome. The offline fakes return
            # an integer and the real runner returns an object, so the shape is normalised here
            # rather than at each call site.
            $exitCode = if ($outcome -is [int]) { $outcome } else { [int]$outcome.ExitCode }
            $timedOut = if ($outcome -is [int]) { $false } else { [bool]$outcome.TimedOut }
            $output   = if ($outcome -is [int]) { '' } else { [string]$outcome.Output }

            if ($exitCode -eq 0) { break }

            $class = Get-LabCycleFailureClass -Text $output -TimedOut:$timedOut
            if (-not $class.Retryable -or $attempt -ge $MaxAttempts) { break }

            # Azure's own Retry-After when it named one, otherwise exponential: 30s, 60s, 120s.
            $wait = if ($class.RetryAfterSeconds) { [int]$class.RetryAfterSeconds } else { [int](30 * [Math]::Pow(2, $attempt - 1)) }
            Write-Host "  [WAIT] $id $($step.Kind) attempt $attempt of $MaxAttempts - $($class.Reason); retrying in ${wait}s" -ForegroundColor Yellow
            & $SleepRunner $wait
            $attempt++
            if ($attempt -gt $phaseAttempts) { $phaseAttempts = $attempt }
        }

        # After every step, not every phase.
        & $stateWriter
        if ($exitCode -ne 0) { $failedStep = $step.Kind; break }
    }

    $durationMs = [int]([datetime]::UtcNow - $started).TotalMilliseconds

    if ($exitCode -eq 0) {
        $status[$id] = 'Succeeded'
        $record = @{ Id = $id; Lab = $phase.Lab; Status = 'Succeeded'; ExitCode = 0; Cause = $null; FailedStep = $null; DurationMs = $durationMs; Attempts = $phaseAttempts; ValidationExcluded = $phase.TestExcluded }
        $results.Add($record)
        & $recordResult $record
        Write-Host "  [ OK ] $id" -ForegroundColor Green
    }
    else {
        # A killed phase and a failed one are different facts and send an operator to different
        # places: one says the lab is broken, the other says our estimate was wrong.
        $phaseStatus = if ($timedOut) { 'Failed(Timeout)' } else { 'Failed' }
        $status[$id] = $phaseStatus
        $cause[$id]  = $id
        $record = @{ Id = $id; Lab = $phase.Lab; Status = $phaseStatus; ExitCode = $exitCode; Cause = $null; FailedStep = $failedStep; DurationMs = $durationMs; Attempts = $phaseAttempts }
        $results.Add($record)
        & $recordResult $record
        $how = if ($timedOut) { "timed out after $($phase.TimeoutMs)ms" } else { "exited $exitCode" }
        Write-Host "  [FAIL] $id - $failedStep $how" -ForegroundColor Red
    }

    & $stateWriter
}

}
finally {
    # State first: whatever happened, the file must describe it. A phase still marked Running here
    # is one this handler could not finish, which is exactly what -Resume needs to reconcile - so
    # it is deliberately left saying Running rather than being tidied into something definite.
    if (-not $DryRun) { & $stateWriter }

    # The lock is released however the run ends, including an interruption or the context-drift
    # throw above. A lock left behind by a crash is survivable - preflight treats a dead owner as
    # stale - but leaving one behind on an ordinary failure would make every later run look
    # blocked, and the operator would learn to delete it by hand, which defeats it.
    #
    # Released BEFORE teardown, because teardown is a separate script that takes the lock itself.
    if (-not $DryRun) { Remove-Item -LiteralPath $LockPath -Force -ErrorAction SilentlyContinue }
}

# -- Teardown ------------------------------------------------------------------------------
# Handed to Remove-LabCycle.ps1 rather than done here. It has to be runnable on its own - after a
# crash, after a -SkipCleanup run, or a week later - and a teardown that only exists inside a
# successful deploy run is the one that is never there when it is needed.
#
# TEARDOWN HAS ITS OWN COUNT AND IS DELIBERATELY ABSENT FROM THIS SCRIPT'S EXIT CODE. 'The lab
# failed' and 'the lab could not be removed' are different facts with different remedies, and
# collapsing them sends an operator to debug a deployment that worked.
if (-not $SkipCleanup -and -not $DryRun) {
    if (-not (Test-Path -LiteralPath $RemoveScriptPath)) {
        Write-Host "[ERROR] Teardown script not found: $RemoveScriptPath" -ForegroundColor Red
        Write-Host '        Every lab is left standing. Run the teardown by hand before the next cycle.' -ForegroundColor Yellow
    }
    else {
        $removeArguments = @{
            SubscriptionId = $SubscriptionId
            ManifestPath   = $ManifestPath
            LabRoot        = $LabRoot
            LogDirectory   = $LogDirectory
            ResultsPath    = $ResultsPath
            RunId          = $runId
            Confirm        = $false
        }
        if ($selected) { $removeArguments['Labs'] = $selected }

        $teardown = & $RemoveScriptPath @removeArguments
        if ($teardown) {
            foreach ($entry in @($teardown.Teardowns)) { if ($entry) { $teardownResults.Add($entry) } }
            foreach ($residue in @($teardown.LeftBehind)) { if ($residue) { $leftBehind.Add($residue) } }
        }
    }
}

foreach ($phase in $excluded) {
    $record = @{ Id = $phase.Id; Lab = $phase.Lab; Status = 'Excluded'; ExitCode = $null; Cause = $phase.Excluded; FailedStep = $null; DurationMs = 0 }
    $results.Add($record)
    & $recordResult $record
}

# 'Failed*' rather than equality, the same convention as the blocker check. An equality test is
# how a compound status added later - Failed(Quota), say - silently stops being counted.
$failedCount  = @($results | Where-Object { $_.Status -like 'Failed*' }).Count
$skippedCount = @($results | Where-Object { $_.Status -eq 'Skipped' }).Count

# -- Coverage, split by what actually happened -----------------------------------------------
# One number would misrepresent the run. A parameter file that was deployed and validated and one
# that was only ever compiled are not the same coverage, and rolling them together is how '16 of
# 16' gets claimed for a run that deployed 15.
#
# The categories must PARTITION the manifest: every phase in exactly one, no overlaps, no gaps.
# Uncovered must stay zero: the manifest's accounting test guarantees every parameter file is
# either a phase or a CompileOnly entry, so a non-zero here means that guarantee has been lost.
$succeeded = @($results | Where-Object { $_.Status -like 'Succeeded*' })
$coverage = @{
    Live                 = @($succeeded | Where-Object { -not $_.ValidationExcluded }).Count
    DeployedNotValidated = @($succeeded | Where-Object { $_.ValidationExcluded }).Count
    Failed               = $failedCount
    NotRun               = $skippedCount
    CompileOnly          = @($manifest.CompileOnly).Count + $excluded.Count
    Uncovered            = 0
}
if ($DryRun) {
    $coverage.Live = 0
    $coverage.DeployedNotValidated = 0
    $coverage.Planned = @($results | Where-Object { $_.Status -eq 'DryRun' }).Count
}

Write-Host ''
Write-Host "  Succeeded $($succeeded.Count)  Failed $failedCount  Skipped $skippedCount  Excluded $($excluded.Count)" -ForegroundColor Cyan
Write-Host "  Coverage: $($coverage.Live) deployed and validated, $($coverage.DeployedNotValidated) deployed but not validated, $($coverage.Failed) failed, $($coverage.NotRun) never ran, $($coverage.CompileOnly) compile-only, $($coverage.Uncovered) unaccounted for" -ForegroundColor Cyan
Write-Host ''

Write-LabCycleReport -Path $ReportPath -SubscriptionId $SubscriptionId -ManifestPath $ManifestPath `
    -Phases $results -Teardowns $teardownResults -LeftBehind $leftBehind -Coverage $coverage `
    -LivePhases $live -LogDirectory $LogDirectory -DryRun:$DryRun
Write-Host "  Report:  $ReportPath" -ForegroundColor Gray
if (-not $DryRun) { Write-Host "  Results: $ResultsPath" -ForegroundColor Gray }
Write-Host ''

[pscustomobject]@{
    RunId                = $runId
    Order                = $order
    Phases               = $results
    FailedCount          = $failedCount
    SkippedCount         = $skippedCount
    Coverage             = $coverage
    ReportPath           = $ReportPath
    ResultsPath          = $ResultsPath
    Teardowns            = $teardownResults
    TeardownFailedCount  = @($teardownResults | Where-Object { $_.Status -eq 'Failed' }).Count
    LeftBehind           = $leftBehind
}

# THE LAST STATEMENT, AND THE POINT OF THE WHOLE PROJECT. A run that reports success while phases
# failed is invisible from inside this process - which is why issues #104 and #105 were both filed
# against cleanup scripts that printed a failure and exited 0 - so the count has to leave through
# the exit code, where a caller and a CI job can see it. Tested from outside, through
# tools/Invoke-LabScript.ps1.
#
# Teardown failures are deliberately not in this number; they are in the report and in the object
# above.
#
# $Host.SetShouldExit as well as `exit`: a script carrying '#Requires -Modules' launched with
# 'pwsh -File' has its `exit` discarded and the process reports 0 regardless. This script declares
# no module requirement, so `exit` alone would work today - but tests/Exit-Code-Propagation.Tests.ps1
# holds the whole repository to the pattern, and an orchestrator whose entire value is a
# trustworthy exit code is the last place to make an exception.
$Host.SetShouldExit($failedCount)
exit $failedCount
