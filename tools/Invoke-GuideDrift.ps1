<#
.SYNOPSIS
    Performs one lab guide's portal steps in a visible browser and reports what no longer matches
    the Azure Portal.

.DESCRIPTION
    The lab cycle (Invoke-LabCycle.ps1) proves the infrastructure-as-code path of 16 labs. Nothing
    proves that the portal instructions - the bold labels, the navigation chains, the form tables -
    still match the Portal, which changes without notice. This tool is for the moment a lab is
    being revised: run it, get a list of what drifted, with proposed edits and fresh screenshots.
    It never runs in CI (issue #189).

    WHAT A RUN DOES. Parses the guide with tools/guide-drift/parse.py (only '### Step' sections,
    outside code fences, Option 1 where Option headings exist; the fixed list of bold captions
    that are not UI elements lives in parse.py), opens Chromium through tools/guide-drift/run.py
    on the Entra ID overview of the tenant of -SubscriptionId, waits for you to sign in (until
    the overview shows 'Tenant ID'), refuses to start unless the Portal is in English and the
    overview shows that tenant's id, then performs every portal step for real: later
    steps depend on what earlier ones created. It never clicks one of several matching elements,
    and never an element whose name contains delete, remove, reset, revoke, disable, block, purge
    or sign out unless the guide's own label contains that word too. Every check ends as match, drift (blocking, misleading or
    cosmetic), unknown or skipped, so 'could not check' is never reported as 'fine'.

    SUPERVISED FIRST, RECORDED ALWAYS. When a label is not on screen the run stops and asks you,
    listing what it can see. The answer goes to tools/guide-drift/recordings/lab-X.Y.json, which
    is committed; later runs replay it and stop only where the Portal no longer matches it. That
    recording is the only thing a run writes into the repository. A guide edit that changes a
    portal label must update the recording in the same PR (tests/Guide-Drift-Recording.Tests.ps1).

    WHAT A RUN LEAVES BEHIND, AND WHY IT IS GITIGNORED. -LogDirectory/<run id>/ holds
    results.jsonl (one record per check, appended as the run goes), a full-window screenshot of
    every step and summary.md. Screenshots show the tenant name, user principal names and the
    subscription id, so nothing is copied into a guide's images/ folder: crop and anonymise by
    hand. The saved browser session (tools/.guide-drift-auth.json) is a sign-in. All of it is
    gitignored and asserted by tests/Gitignore.Tests.ps1.

    VALUES THAT MUST NOT BE LITERAL. Step 1.1.5 invites a guest; the recording overrides that
    address with ${SKYCRAFT_GUIDE_DRIFT_GUEST_EMAIL}, and '[yourtenant]' with
    ${SKYCRAFT_GUIDE_DRIFT_TENANT_PREFIX}, which this script sets from the tenant's default domain.
    Set SKYCRAFT_GUIDE_DRIFT_GUEST_EMAIL to an address you control before running lab 1.1.

    WHEN A STEP FAILS the run asks: c = you did it by hand, continue; s = skip the rest and
    finish; q = stop and keep the state (exit 255; continue with -Resume). On -Resume it shows the
    previous step's view and asks whether the step in flight finished (y), must be redone (n) or
    skipped (s).

    CLEANUP IS THE LAB'S OWN. This script has no deletion logic. Unless -SkipCleanup, lab 1.1
    hands off to its scripts/Remove-LabResource.ps1 -Force (Microsoft Graph), every other lab to
    tools/Remove-LabCycle.ps1 with the same -SubscriptionId. There is no cleanup after a run
    that did not start (254) or was stopped with its state kept (255): -Resume needs what it
    created.

.PARAMETER SubscriptionId
    The subscription whose tenant the run is for. Mandatory and compared by id against the Az
    context through Test-LabCycleSubscription, for the reason Invoke-LabCycle.ps1 gives
    (2026-08-02). The tenant id and default domain are read from it.

.PARAMETER Lab
    The lab to run, as 'X.Y'. Resolves module-*/X.Y-*/lab-guide-X.Y.md.

.PARAMETER FromStep
    Start at this step id ('1.1.6'), assuming earlier steps were done by hand.

.PARAMETER Resume
    Continue the previous run from tools/.guide-drift-state.json, starting at the step that was
    in flight or failed. A finished run, or a state file of another lab, is refused (exit 254).

.PARAMETER LogDirectory
    Where run folders are written. Defaults to tools/guide-drift-logs.

.PARAMETER SkipCleanup
    Leave what the run created in place.

.PARAMETER PythonPath
    The interpreter to use. Defaults to 'python' on Windows and 'python3' elsewhere.

.EXAMPLE
    .\tools\Invoke-GuideDrift.ps1 -SubscriptionId 00000000-0000-0000-0000-000000000000 -Lab 1.1
    Performs lab 1.1 supervised, then removes its users and groups.

.EXAMPLE
    .\tools\Invoke-GuideDrift.ps1 -SubscriptionId 00000000-0000-0000-0000-000000000000 -Lab 1.1 -Resume -SkipCleanup
    Continues an interrupted run and leaves the resources for inspection.

.NOTES
    Project: SkyCraft
    Issue:   #189
    Exit code: blocking drifts + unknowns (0 = nothing to fix, capped at 250); 1 when a prerequisite
    is missing; 254 when run.py stopped before the first step; 255 when it was interrupted
    (state kept, nothing cleaned up: re-run with -Resume).
#>

#Requires -Version 7.0
#Requires -Modules Az.Accounts

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[0-9a-fA-F-]{36}$')]
    [string]$SubscriptionId,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^\d+\.\d+$')]
    [string]$Lab,

    [Parameter(Mandatory = $false)]
    [ValidatePattern('^\d+\.\d+\.\d+$')]
    [string]$FromStep,

    [Parameter(Mandatory = $false)]
    [switch]$Resume,

    [Parameter(Mandatory = $false)]
    [string]$LogDirectory = (Join-Path $PSScriptRoot 'guide-drift-logs'),

    [Parameter(Mandatory = $false)]
    [switch]$SkipCleanup,

    [Parameter(Mandatory = $false)]
    [string]$PythonPath = $(if ($IsWindows) { 'python' } else { 'python3' })
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'LabCycle.psm1') -Force

$repoRoot  = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$toolDir   = Join-Path $PSScriptRoot 'guide-drift'
$statePath = Join-Path $PSScriptRoot '.guide-drift-state.json'
$authPath  = Join-Path $PSScriptRoot '.guide-drift-auth.json'
$runId     = Get-Date -Format 'yyyyMMdd-HHmmss'
if ($Resume -and (Test-Path -LiteralPath $statePath)) {
    # One run across -Resume: run.py appends to the run folder the state names, so the summary
    # and the exit code cover everything found before the stop.
    try {
        $previousRunId = (Get-Content -Raw -LiteralPath $statePath | ConvertFrom-Json).runId
        if ($previousRunId) { $runId = $previousRunId }
    } catch {
        # An unreadable state file is run.py's to report (exit 254 with what to do); keep the new id.
        Write-Verbose "State file unreadable: $($_.Exception.Message)"
    }
}

Write-Host "=== Guide drift: lab $Lab ===" -ForegroundColor Cyan

# --- Guide --------------------------------------------------------------------------------
$labDir = Get-ChildItem -Path $repoRoot -Directory -Filter 'module-*' |
    Get-ChildItem -Directory |
    Where-Object { $_.Name -like "$Lab-*" } |
    Select-Object -First 1
$guide = if ($labDir) { Join-Path $labDir.FullName "lab-guide-$Lab.md" }
if (-not $guide -or -not (Test-Path -LiteralPath $guide)) {
    Write-Host "[ERROR] No lab guide found for lab $Lab (expected module-*/$Lab-*/lab-guide-$Lab.md)." -ForegroundColor Red
    $Host.SetShouldExit(1)
    exit 1
}
$recording = Join-Path $toolDir "recordings/lab-$Lab.json"
if (-not (Test-Path -LiteralPath $recording)) {
    Write-Host "[ERROR] No recording at $recording. Create one from the lab 1.1 seed shape before the first supervised run." -ForegroundColor Red
    $Host.SetShouldExit(1)
    exit 1
}

# --- Python and Playwright ----------------------------------------------------------------
if (-not (Get-Command $PythonPath -ErrorAction SilentlyContinue)) {
    Write-Host "[ERROR] '$PythonPath' not found. Install Python 3.10+ or pass -PythonPath." -ForegroundColor Red
    $Host.SetShouldExit(1)
    exit 1
}
& $PythonPath -c 'import sys; assert sys.version_info >= (3, 10); import playwright.sync_api' 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Host "[ERROR] Python 3.10+ with Playwright is required:" -ForegroundColor Red
    Write-Host "        $PythonPath -m pip install -r tools/guide-drift/requirements.txt" -ForegroundColor Yellow
    Write-Host "        $PythonPath -m playwright install chromium" -ForegroundColor Yellow
    $Host.SetShouldExit(1)
    exit 1
}

# --- Subscription and tenant ----------------------------------------------------------------
$check = Test-LabCycleSubscription -SubscriptionId $SubscriptionId
if (-not $check.Ok) {
    Write-Host "[ERROR] $($check.Detail)" -ForegroundColor Red
    $Host.SetShouldExit(1)
    exit 1
}
$context  = Get-AzContext
$tenantId = $context.Tenant.Id
$tenant   = Get-AzTenant -TenantId $tenantId
$domain   = if ($tenant.DefaultDomain) { $tenant.DefaultDomain } else { @($tenant.Domains)[0] }
if (-not $domain) {
    Write-Host "[ERROR] Could not read the default domain of tenant $tenantId." -ForegroundColor Red
    $Host.SetShouldExit(1)
    exit 1
}
$env:SKYCRAFT_GUIDE_DRIFT_TENANT_PREFIX = ($domain -split '\.')[0]
Write-Host "  Subscription: $($check.Detail)" -ForegroundColor Gray
Write-Host "  Tenant:       $tenantId ($domain)" -ForegroundColor Gray
Write-Host "  Run:          $runId -> $LogDirectory" -ForegroundColor Gray

# --- Parse, then run -------------------------------------------------------------------------
$runDir = Join-Path $LogDirectory $runId
New-Item -ItemType Directory -Path $runDir -Force | Out-Null
$stepsPath = Join-Path $runDir 'steps.json'
& $PythonPath (Join-Path $toolDir 'parse.py') $guide --out $stepsPath --repo-root $repoRoot
if ($LASTEXITCODE -ne 0) {
    Write-Host "[ERROR] parse.py failed for $guide." -ForegroundColor Red
    $Host.SetShouldExit(1)
    exit 1
}

$runArgs = @(
    (Join-Path $toolDir 'run.py')
    '--steps', $stepsPath
    '--recording', $recording
    '--log-dir', $LogDirectory
    '--run-id', $runId
    '--tenant-id', $tenantId
    '--tenant-domain', $domain
    '--state', $statePath
    '--auth-state', $authPath
)
if ($FromStep) { $runArgs += @('--from-step', $FromStep) }
if ($Resume)   { $runArgs += '--resume' }

Write-Host 'Starting the browser...' -ForegroundColor Yellow
& $PythonPath @runArgs
$runExit = $LASTEXITCODE

# run.py reports a count of findings (0-250) or one of two codes that are not a count.
$notStarted = 254   # a precondition or guard stopped it before the first step
$aborted    = 255   # interrupted or stopped mid-run; the state file is kept for -Resume
if ($runExit -eq $notStarted) {
    Write-Host '[ERROR] The run did not start (see the message above). Nothing is cleaned up.' -ForegroundColor Red
    $Host.SetShouldExit($runExit)
    exit $runExit
}
if ($runExit -eq $aborted) {
    Write-Host "Run stopped before the end. Nothing is cleaned up, so it can continue: re-run with -Resume." -ForegroundColor Yellow
    $Host.SetShouldExit($runExit)
    exit $runExit
}

# --- Cleanup: the lab's own script -----------------------------------------------------------
if ($SkipCleanup) {
    Write-Host 'Skipping cleanup (-SkipCleanup).' -ForegroundColor Gray
} else {
    Write-Host '=== Cleanup ===' -ForegroundColor Cyan
    $global:LASTEXITCODE = 0   # run.py's code must not be read as the cleanup's
    if ($Lab -eq '1.1') {
        & (Join-Path $labDir.FullName 'scripts/Remove-LabResource.ps1') -Force
    } else {
        & (Join-Path $PSScriptRoot 'Remove-LabCycle.ps1') -SubscriptionId $SubscriptionId -Confirm:$false
    }
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[WARNING] Cleanup exited $LASTEXITCODE. The run's results above stand; remove what is left by hand." -ForegroundColor Yellow
    }
}

if ($runExit -eq 0) {
    Write-Host "Nothing to fix in lab $Lab." -ForegroundColor Green
} else {
    Write-Host "$runExit blocking drift(s) or unknown(s) in lab $Lab. See $runDir/summary.md." -ForegroundColor Yellow
}
$Host.SetShouldExit($runExit)
exit $runExit
