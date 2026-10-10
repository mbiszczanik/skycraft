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
    outside code fences, and where Option headings exist the first option with a portal part,
    which steps.json names in the step's "option"; the fixed list of bold captions
    that are not UI elements lives in parse.py), opens Chromium through tools/guide-drift/run.py
    on the Entra ID overview of the tenant of -SubscriptionId (or of -TenantId), waits for you to sign in (until
    the overview shows 'Tenant ID'), refuses to start unless the Portal is in English and the
    overview shows that tenant's id, then performs every portal step for real: later
    steps depend on what earlier ones created. It never clicks one of several matching elements,
    and never an element whose name contains delete, remove, reset, revoke, disable, block, purge
    or sign out unless the guide's own label contains that word too. Every check ends as match,
    drift (blocking, misleading or cosmetic), unknown or skipped, so 'could not check' is never
    reported as 'fine'.

    TENANT MODE. A lab that touches only Microsoft Entra ID (today 1.1) needs no subscription, and
    the tenant of a subscription may be a directory where the lab must not run: users, a guest and
    self-service password reset for all users do not belong in a corporate tenant. -TenantId runs
    such a lab against a tenant that has no subscription, after Connect-AzAccount -TenantId. A lab
    that deploys Azure resources (a phase of tools/lab-cycle-manifest.psd1) is refused in this
    mode: it needs -SubscriptionId.

    THE RUN MAKES REAL CHANGES in the tenant of -SubscriptionId or -TenantId: it creates users, a guest
    invitation and groups, and changes tenant settings, exactly as the guide says. Use a tenant
    where that is acceptable.

    SUPERVISED FIRST, RECORDED ALWAYS. When a label is not on screen the run stops and asks you,
    listing what it can see. The answer goes to tools/guide-drift/recordings/lab-X.Y.json, which
    is committed; later runs replay it and stop only where the Portal no longer matches it. That
    recording is the only thing a run writes into the repository. A guide edit that changes a
    portal label must update the recording in the same PR (tests/Guide-Drift-Recording.Tests.ps1).
    A resource that a navigation chain names in a code span ('**Load balancers** ->
    `dev-skycraft-swc-lb`') is never asked about: it is opened from the screen, or else, when it
    opens the chain, from the Portal's global search; when it is not found under that exact name,
    the step fails as blocking drift of the step (missing-resource), with no proposed guide edit
    (issue #199).

    STEPS THE RECORDING SKIPS. A step that is optional or conceptual by its heading and would
    create resources, or that follows the other option of a lettered pair, is left out by
    '"skip": "<reason>"' in its entry of the recording (issue #200). The run never performs it,
    lists it in summary.md under 'skipped' with that reason and goes on with the next step; a
    resume passes over it, and does not ask about a step that was in flight when the run stopped
    and is skipped in the recording since. The next step starts on the view the step before the
    skip ended on, without the blade the skipped step would have opened or the resources it would
    have created, so a later step that needed them fails: skip only a step whose blade and
    resources no later step needs, or skip those later steps too. The skip wins over the rest of
    the entry, which is kept (and still checked by tests/Guide-Drift-Recording.Tests.ps1) for the
    day the skip is removed. The reason must be a non-empty string and the step one the guide has,
    with a portal part; the run refuses to start (254) on a skip without a reason.

    WHAT A RUN LEAVES BEHIND, AND WHY IT IS GITIGNORED. -LogDirectory/<run id>/ holds
    steps.json (the parsed guide; parse.py failing stops the run with exit 1), results.jsonl (one
    record per check, appended as the run goes), a full-window screenshot of every step,
    summary.md, for a 'Search for' step that found no single result, search-<step>.aria.txt
    (the search dropdown's accessibility tree, redacted) and, for a label that was not found,
    blade-<step>-<guide line>.aria.txt (the outline the blade loading check read, redacted).
    summary.md and results.jsonl are safe to copy into an issue or a pull request: each record
    keeps what it observed on one line, as the failure prompt shows it, without Playwright's call
    log, with the tenant domain, id and name, the guest address and object ids as tokens, and
    every value typed into a password or secret field as [secret] (#212).
    Screenshots show the tenant name, user principal names and the subscription id, so nothing
    is copied into a guide's images/ folder: crop and anonymise by hand. The saved browser
    session (tools/.guide-drift-auth.json) is a sign-in. All of it is gitignored and asserted
    by tests/Gitignore.Tests.ps1.

    VALUES THAT MUST NOT BE LITERAL. Step 1.1.5 invites a guest; the recording overrides that
    address with ${SKYCRAFT_GUIDE_DRIFT_GUEST_EMAIL}, and '[yourtenant]' with
    ${SKYCRAFT_GUIDE_DRIFT_TENANT_PREFIX}, which this script sets from the tenant's initial
    *.onmicrosoft.com domain (and restores afterwards). Set SKYCRAFT_GUIDE_DRIFT_GUEST_EMAIL to an
    address you control before running lab 1.1.

    WHEN A STEP FAILS the run asks: c = you did it by hand, continue; s = skip this step and
    continue with the next one (it asks for the reason, which summary.md lists under 'skipped';
    the step's findings still count in the exit code, and a later step that needed it may fail
    and is asked about in turn); e = end the lab: skip the rest and finish; q = stop and keep the
    state (exit 255; continue with -Resume). Closed input ends the lab. A run that went on past a
    skipped step, or ended with e, is finished, so cleanup runs. A step done by hand (c) records
    the view the Portal shows when you answer, so a later -Resume can open it. On -Resume it asks
    whether the step in flight finished (y), must be redone (n) or is skipped (s); a step skipped
    with s before the stop is passed over.

    A RESUMED RUN HAS A NEW BROWSER on the Microsoft Entra ID overview (issue #206), and so has a
    run started with -FromStep. Before the first step that runs, the run opens the view that step
    starts from, from the recording: after y, the view the step in flight ended on; after n, the
    view the step before it ended on, to redo it from there; after s, the skipped step's own view,
    or the view it started from when it has none. It cannot open a view that names an object by
    id (the recording leaves ids out) or keeps a [token] or ${NAME} this run cannot fill in (is
    the environment variable set?); then it prints the view and the reason, or says no view is
    recorded for that step, and you bring the Portal there by hand. Either way it waits for Enter:
    check the Portal first, as an opened view has none of the blades the guide opened before it.
    A view is recorded only without tenant or personal data, also once percent-decoded; one that
    cannot be is recorded as none.

    A STEP ON THE WRONG BLADE (issue #207). The recording keeps the blade each step starts on
    ("startBlade": the blade part of the redacted view, such as
    Microsoft_AAD_IAM/GroupDetailsMenuBlade/~/Members), recorded the first time the step's first
    item goes through, with or without your help, once the address has settled; the console says
    'Recorded: step X starts on <blade>', so check it. Before a step with a recorded blade, the run
    compares the open blade with it (ignoring case and a trailing overview) for a few seconds; when
    it never matches, it reports misleading drift ('the step starts on X, the Portal is on Y; the
    guide does not say how to get there') and waits for you to bring the Portal to X and press
    Enter. The first step after -Resume or -FromStep, the first after a step the recording skips,
    and the first after a step you skipped with s are asked about the same way without blaming the
    guide; the latter two record no blade, so while a recorded skip stays, the start of the step
    after it is not checked. A step that opens with a global search, or with a resource name, may
    start anywhere and is not checked. Before the first field of a form, the run checks a field of
    that name can be filled in, so it never types into a list; when none can, it reports the same
    drift (once per cause) and waits for you to open the form. A wrong recorded blade is deleted
    from the recording by hand; the next run records it again.

    CLEANUP IS THE LAB'S OWN, AND ONLY AFTER A FINISHED RUN. This script has no deletion logic.
    Unless -SkipCleanup, and only when run.py ended normally and the state file confirms it
    (finished, with this run's id), it hands off to the lab's own teardown:
      - lab 1.1: scripts/Remove-LabResource.ps1 -Force (Microsoft Graph) in a child process,
        with SKYCRAFT_GRAPH_TENANT_ID set to the run's tenant so that its Graph sign-in is
        pinned to it. If SKYCRAFT_GRAPH_TENANT_ID is already set to another tenant, cleanup is
        skipped with a warning instead of deleting by name in the wrong tenant.
      - any other lab (-SubscriptionId only): tools/Remove-LabCycle.ps1 -Labs <lab>, that lab
        only, with the same -SubscriptionId.
    There is no cleanup after a run that did not start (254), was stopped with its state kept
    (255) or did not finish: -Resume needs what it created.

    WHAT LAB 1.1'S CLEANUP DOES NOT UNDO. It deletes the three users (on the tenant's initial
    *.onmicrosoft.com domain, where the run creates them), the guest the guide names in step 1.1.5
    and the three SkyCraft groups. It does not remove the guest the run invited (the address in
    SKYCRAFT_GUIDE_DRIFT_GUEST_EMAIL, which replaces the guide's), and it does not revert the
    self-service password reset scope (step 1.1.12). Remove those by hand, or use a tenant where
    leaving them is acceptable. (Step 1.1.11 only reviews licences.) The prerequisites of the
    cleanup are checked before the browser opens: missing Microsoft.Graph modules stop the run
    with exit 1, unless -SkipCleanup.

.PARAMETER SubscriptionId
    The subscription whose tenant the run is for. Mandatory and compared by id against the Az
    context through Test-LabCycleSubscription, for the reason Invoke-LabCycle.ps1 gives
    (2026-08-02). The tenant id, its initial *.onmicrosoft.com domain and its display name are
    read from it; the display name is kept out of the recording as '[tenantname]'.

.PARAMETER TenantId
    The tenant to run an Entra-only lab against, when it has no subscription (tenant mode, see
    above). Compared by id against the Az context, like -SubscriptionId: run
    Connect-AzAccount -TenantId <id> first (an account without a subscription is fine). Not
    allowed for a lab that deploys Azure resources, and not together with -SubscriptionId. Its
    initial *.onmicrosoft.com domain and display name are read with Get-AzTenant.

.PARAMETER Lab
    The lab to run, as 'X.Y'. Resolves module-*/X.Y-*/lab-guide-X.Y.md. Only labs with a
    recording in tools/guide-drift/recordings/ can run (1.1 today).

.PARAMETER FromStep
    Start at this step id ('1.1.6'), assuming earlier steps were done by hand. The run first
    brings the Portal to the view the step starts from (see A RESUMED RUN HAS A NEW BROWSER).

.PARAMETER Resume
    Continue the previous run from tools/.guide-drift-state.json, starting at the step that was
    in flight or failed. A finished run, or a state file of another lab, is refused (exit 254).
    The run continues in its own folder: the state records the absolute log directory of the
    stopped run, and -Resume uses it whatever -LogDirectory says. The browser is new: the run
    brings the Portal to the view the next step starts from (see A RESUMED RUN HAS A NEW BROWSER).

.PARAMETER LogDirectory
    Where run folders are written. Defaults to tools/guide-drift-logs. Resolved to an absolute
    path against the current directory. Ignored with -Resume when the state names the stopped
    run's directory (see -Resume).

.PARAMETER SkipCleanup
    Leave what the run created in place, and skip the check of the cleanup's prerequisites.

.PARAMETER PythonPath
    The interpreter to use. Defaults to 'python' on Windows and 'python3' elsewhere. The
    Microsoft Store alias (under WindowsApps) is refused: pass the real interpreter's path.

.EXAMPLE
    .\tools\Invoke-GuideDrift.ps1 -SubscriptionId 00000000-0000-0000-0000-000000000000 -Lab 1.1
    Performs lab 1.1 supervised, then removes its users and groups.

.EXAMPLE
    pwsh -File .\tools\Invoke-GuideDrift.ps1 -TenantId 00000000-0000-0000-0000-000000000000 -Lab 1.1
    Performs lab 1.1 in a tenant that has no subscription, then removes its users and groups.

.EXAMPLE
    .\tools\Invoke-GuideDrift.ps1 -SubscriptionId 00000000-0000-0000-0000-000000000000 -Lab 1.1 -Resume -SkipCleanup
    Continues an interrupted run and leaves the resources for inspection.

.NOTES
    Project: SkyCraft
    Issue:   #189
    Exit code: blocking drifts + unknowns (0 = nothing to fix, capped at 250); 1 when a prerequisite
    is missing, parse.py fails, or run.py crashes before the state confirms the run finished
    (Python's own exit 1; nothing is cleaned up and the state is kept); 254 when run.py stopped
    before the first step, or -Resume has no unfinished state of this lab to continue; 255 when it
    was interrupted (state kept, nothing cleaned up: re-run with -Resume).
    A cleanup that fails or is skipped does not change the exit code, as in Invoke-LabCycle.ps1:
    it is reported as a warning, and the code stays the count of findings.
    Like the other tools/*.ps1 entry points, the script ends the host process with its exit code
    ($Host.SetShouldExit, then exit). Dot-sourced or run inside an interactive session it closes
    that session: start it with 'pwsh -File', or read the run folder's summary.md afterwards.
#>

#Requires -Version 7.0
#Requires -Modules Az.Accounts

[CmdletBinding(DefaultParameterSetName = 'Subscription')]
param(
    [Parameter(Mandatory = $true, ParameterSetName = 'Subscription')]
    [ValidatePattern('^[0-9a-fA-F-]{36}$')]
    [string]$SubscriptionId,

    [Parameter(Mandatory = $true, ParameterSetName = 'Tenant')]
    [ValidatePattern('^[0-9a-fA-F-]{36}$')]
    [string]$TenantId,

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

# python reports failure through $LASTEXITCODE. Without this, PowerShell 7.4+ turns a non-zero
# native exit into a terminating error, and run.py's 254 and 255 would never reach the checks
# below (same reason as tools/Invoke-DryRun.ps1).
$PSNativeCommandUseErrorActionPreference = $false

Import-Module (Join-Path $PSScriptRoot 'LabCycle.psm1') -Force

$repoRoot     = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$toolDir      = Join-Path $PSScriptRoot 'guide-drift'
$statePath    = Join-Path $PSScriptRoot '.guide-drift-state.json'
$authPath     = Join-Path $PSScriptRoot '.guide-drift-auth.json'
$LogDirectory = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($LogDirectory)

# run.py reports a count of findings (0-250) or one of two codes that are not a count.
$notStarted = 254   # a precondition or guard stopped it before the first step
$aborted    = 255   # interrupted or stopped mid-run; the state file is kept for -Resume

Write-Host "=== Guide drift: lab $Lab ===" -ForegroundColor Cyan

# --- Guide --------------------------------------------------------------------------------
$labDirs = @(Get-ChildItem -Path $repoRoot -Directory -Filter 'module-*' |
    Get-ChildItem -Directory |
    Where-Object { $_.Name -like "$Lab-*" })
if ($labDirs.Count -gt 1) {
    Write-Host "[ERROR] More than one folder matches lab ${Lab}: $($labDirs.Name -join ', ')." -ForegroundColor Red
    $Host.SetShouldExit(1)
    exit 1
}
$labDir = $labDirs | Select-Object -First 1
$guide = if ($labDir) { Join-Path $labDir.FullName "lab-guide-$Lab.md" }
if (-not $guide -or -not (Test-Path -LiteralPath $guide)) {
    Write-Host "[ERROR] No lab guide found for lab $Lab (expected module-*/$Lab-*/lab-guide-$Lab.md)." -ForegroundColor Red
    $Host.SetShouldExit(1)
    exit 1
}
# --- Tenant mode: only for a lab that creates nothing in a subscription ---------------------------
$tenantMode = $PSCmdlet.ParameterSetName -eq 'Tenant'
if ($tenantMode) {
    $manifest = Import-PowerShellDataFile -LiteralPath (Join-Path $PSScriptRoot 'lab-cycle-manifest.psd1')
    if (@($manifest.Phases | Where-Object { $_.Id -eq $Lab }).Count -gt 0) {
        Write-Host "[ERROR] Lab $Lab deploys Azure resources; run it with -SubscriptionId." -ForegroundColor Red
        $Host.SetShouldExit(1)
        exit 1
    }
}

$recording = Join-Path $toolDir "recordings/lab-$Lab.json"
if (-not (Test-Path -LiteralPath $recording)) {
    Write-Host "[ERROR] No recording at $recording. Create one from the lab 1.1 seed shape before the first supervised run." -ForegroundColor Red
    $Host.SetShouldExit(1)
    exit 1
}

# --- Cleanup prerequisites: found out now, not after the lab has been performed ---------------
$cleanupScript = $null
if (-not $SkipCleanup) {
    if ($Lab -eq '1.1') {
        $cleanupScript = Join-Path $labDir.FullName 'scripts/Remove-LabResource.ps1'
        $missingModule = @()
        if (Test-Path -LiteralPath $cleanupScript) {
            # The modules the lab script itself declares, so this list cannot drift from it.
            $cleanupAst = [System.Management.Automation.Language.Parser]::ParseFile($cleanupScript, [ref]$null, [ref]$null)
            $missingModule = @($cleanupAst.ScriptRequirements.RequiredModules |
                ForEach-Object { $_.Name } |
                Where-Object { -not (Get-Module -ListAvailable -Name $_) })
        }
        if (-not (Test-Path -LiteralPath $cleanupScript)) {
            Write-Host "[ERROR] The cleanup script $cleanupScript is missing. Restore it, or pass -SkipCleanup." -ForegroundColor Red
            $Host.SetShouldExit(1)
            exit 1
        }
        if ($missingModule.Count -gt 0) {
            Write-Host "[ERROR] The cleanup of lab $Lab needs module(s) that are not installed: $($missingModule -join ', ')." -ForegroundColor Red
            Write-Host '        Install them (Install-Module Microsoft.Graph -Scope CurrentUser), or pass -SkipCleanup and remove what the run creates by hand.' -ForegroundColor Yellow
            $Host.SetShouldExit(1)
            exit 1
        }
    } elseif ($tenantMode) {
        # Remove-LabCycle.ps1 works on a subscription, and there is none here.
        Write-Host "[ERROR] Lab $Lab has no cleanup that works without a subscription. Pass -SkipCleanup and remove what the run creates by hand." -ForegroundColor Red
        $Host.SetShouldExit(1)
        exit 1
    } else {
        $cleanupScript = Join-Path $PSScriptRoot 'Remove-LabCycle.ps1'
        if (-not (Test-Path -LiteralPath $cleanupScript)) {
            Write-Host "[ERROR] The cleanup script $cleanupScript is missing. Restore it, or pass -SkipCleanup." -ForegroundColor Red
            $Host.SetShouldExit(1)
            exit 1
        }
    }
}

# --- Python and Playwright ----------------------------------------------------------------
$python = Get-Command $PythonPath -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $python -or $python.Source -match '[\\/]WindowsApps[\\/]') {
    # The Microsoft Store alias in WindowsApps is a stub that opens the Store instead of running Python.
    Write-Host "[ERROR] '$PythonPath' is not a usable Python interpreter$(if ($python) { ' (it is the Microsoft Store alias)' })." -ForegroundColor Red
    Write-Host '        Install Python 3.10+ and pass its full path with -PythonPath.' -ForegroundColor Yellow
    $Host.SetShouldExit(1)
    exit 1
}
& $PythonPath -c 'import sys; sys.exit(0 if sys.version_info >= (3, 10) else 3)' 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Host "[ERROR] '$PythonPath' is older than Python 3.10 or does not run. Pass a newer interpreter with -PythonPath." -ForegroundColor Red
    $Host.SetShouldExit(1)
    exit 1
}
& $PythonPath -c 'import playwright.sync_api' 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Host "[ERROR] Playwright is not installed for '$PythonPath':" -ForegroundColor Red
    Write-Host "        $PythonPath -m pip install -r tools/guide-drift/requirements.txt" -ForegroundColor Yellow
    Write-Host "        $PythonPath -m playwright install chromium" -ForegroundColor Yellow
    $Host.SetShouldExit(1)
    exit 1
}

# --- Subscription and tenant ----------------------------------------------------------------
if ($tenantMode) {
    # Compared by id, like the subscription: a tenant name or a stale context proves nothing.
    $azContext = Get-AzContext
    if (-not $azContext -or [string]$azContext.Tenant.Id -ine $TenantId) {
        Write-Host "[ERROR] The Azure context is $(if ($azContext) { "in tenant $($azContext.Tenant.Id)" } else { 'missing' }), not in $TenantId." -ForegroundColor Red
        Write-Host "        Run Connect-AzAccount -TenantId $TenantId first (an account without a subscription is fine)." -ForegroundColor Yellow
        $Host.SetShouldExit(1)
        exit 1
    }
    $check = [pscustomobject]@{ Ok = $true; Detail = '(none: tenant mode)' }
} else {
    $check = Test-LabCycleSubscription -SubscriptionId $SubscriptionId
    if (-not $check.Ok) {
        Write-Host "[ERROR] $($check.Detail)" -ForegroundColor Red
        $Host.SetShouldExit(1)
        exit 1
    }
}
try {
    $tenantId = if ($tenantMode) { $TenantId } else { (Get-AzContext).Tenant.Id }
    $tenant   = Get-AzTenant -TenantId $tenantId
}
catch {
    Write-Host "[ERROR] Could not read the tenant of the Azure context: $($_.Exception.Message)" -ForegroundColor Red
    $Host.SetShouldExit(1)
    exit 1
}
# The initial *.onmicrosoft.com domain: the one the lab's UPNs and the recording's placeholders use.
$domain = @($tenant.Domains) | Where-Object { $_ -match '^[^.]+\.onmicrosoft\.com$' } | Select-Object -First 1
if (-not $tenantId -or -not $domain) {
    Write-Host "[ERROR] Could not find the initial onmicrosoft.com domain of tenant $tenantId." -ForegroundColor Red
    $Host.SetShouldExit(1)
    exit 1
}
# The display name ('Contoso Ltd'), shown by the Portal; run.py keeps it out of the recording.
$tenantName = [string]$tenant.Name

# --- Which run this is ---------------------------------------------------------------------
$runId = Get-Date -Format 'yyyyMMdd-HHmmss'
if ($Resume) {
    # One run across -Resume: run.py appends to the run folder the state names, so the summary and
    # the exit code cover everything found before the stop. Only the unfinished state of this lab
    # is a run to continue; anything else must not get its folder (or its steps.json) touched.
    $previous = $null
    if (Test-Path -LiteralPath $statePath) {
        try { $previous = Get-Content -Raw -LiteralPath $statePath | ConvertFrom-Json }
        catch { Write-Verbose "State file unreadable: $($_.Exception.Message)" }
    }
    if (-not $previous -or -not $previous.runId -or $previous.lab -ne $Lab -or $previous.finished) {
        Write-Host "[ERROR] -Resume needs an unfinished run of lab $Lab in $statePath, and there is none. Delete the file or run without -Resume." -ForegroundColor Red
        $Host.SetShouldExit($notStarted)
        exit $notStarted
    }
    $runId = [string]$previous.runId
    # The stopped run's folder, wherever -LogDirectory points now: run.py records it in the state.
    if ($previous.logDir -and [string]$previous.logDir -ne $LogDirectory) {
        if ($PSBoundParameters.ContainsKey('LogDirectory')) {
            Write-Host "[WARNING] -LogDirectory $LogDirectory is ignored: run $runId continues in $($previous.logDir)." -ForegroundColor Yellow
        }
        $LogDirectory = [string]$previous.logDir
    }
}

# Cleanup of lab 1.1 deletes by name through Microsoft Graph, so it must sign in to the run's own
# tenant: with only SKYCRAFT_GRAPH_TENANT_ID set, Remove-LabResource.ps1 plans an interactive
# sign-in pinned to that tenant and reuses a Graph context only of that tenant. A value that is
# already set to another tenant is not overridden.
$cleanupSkipReason = $null
if ($cleanupScript -and $Lab -eq '1.1' -and $env:SKYCRAFT_GRAPH_TENANT_ID -and $env:SKYCRAFT_GRAPH_TENANT_ID.Trim() -ine $tenantId) {
    $cleanupSkipReason = "SKYCRAFT_GRAPH_TENANT_ID is $($env:SKYCRAFT_GRAPH_TENANT_ID.Trim()) but this run is in tenant $tenantId, so cleanup would sign in to the wrong tenant."
    Write-Host "[WARNING] $cleanupSkipReason Cleanup will be skipped." -ForegroundColor Yellow
}

Write-Host "  Subscription: $($check.Detail)" -ForegroundColor Gray
Write-Host "  Tenant:       $tenantId ($domain)" -ForegroundColor Gray
Write-Host "  Run:          $runId -> $LogDirectory" -ForegroundColor Gray

# The environment is the script's to borrow, not to keep: restored in the finally below.
$savedPrefix      = $env:SKYCRAFT_GUIDE_DRIFT_TENANT_PREFIX
$savedGraphTenant = $env:SKYCRAFT_GRAPH_TENANT_ID
try {
    $env:SKYCRAFT_GUIDE_DRIFT_TENANT_PREFIX = ($domain -split '\.')[0]

    # --- Parse, then run -----------------------------------------------------------------------
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
    # Not passed when empty: an empty native argument is easy to lose on the way to Python.
    if ($tenantName) { $runArgs += @('--tenant-name', $tenantName) }
    if ($FromStep) { $runArgs += @('--from-step', $FromStep) }
    if ($Resume)   { $runArgs += '--resume' }

    Write-Host 'Starting the browser...' -ForegroundColor Yellow
    & $PythonPath @runArgs
    $runExit = $LASTEXITCODE

    if ($runExit -eq $notStarted) {
        Write-Host '[ERROR] The run did not start (see the message above). Nothing is cleaned up.' -ForegroundColor Red
        $Host.SetShouldExit($runExit)
        exit $runExit
    }
    if ($runExit -eq $aborted) {
        Write-Host 'Run stopped before the end. Nothing is cleaned up, so it can continue: re-run with -Resume.' -ForegroundColor Yellow
        $Host.SetShouldExit($runExit)
        exit $runExit
    }

    # 0-250 is a count of findings only when the state confirms the run reached its end: cleanup
    # deletes what -Resume would need, so it wants positive proof, not the absence of a stop code.
    $finished = $false
    try {
        $final = Get-Content -Raw -LiteralPath $statePath | ConvertFrom-Json
        $finished = ($final.finished -eq $true) -and ([string]$final.runId -eq $runId)
    }
    catch { Write-Verbose "State file unreadable: $($_.Exception.Message)" }
    if (-not $finished) {
        Write-Host "[WARNING] run.py exited $runExit but $statePath does not show run $runId as finished. Nothing is cleaned up; the state is kept." -ForegroundColor Yellow
        $Host.SetShouldExit($runExit)
        exit $runExit
    }

    # --- Cleanup: the lab's own script ---------------------------------------------------------
    # A failed or skipped cleanup is a warning and never changes the exit code, which stays the
    # count of findings (the convention of Invoke-LabCycle.ps1: 'the lab failed' and 'the lab
    # could not be removed' are different facts).
    if ($SkipCleanup) {
        Write-Host 'Skipping cleanup (-SkipCleanup).' -ForegroundColor Gray
    } elseif ($cleanupSkipReason) {
        Write-Host "[WARNING] Cleanup skipped: $cleanupSkipReason Remove what the run created by hand." -ForegroundColor Yellow
    } else {
        Write-Host '=== Cleanup ===' -ForegroundColor Cyan
        try {
            if ($Lab -eq '1.1') {
                # A child process: the lab script signs in to Microsoft Graph and calls
                # $Host.SetShouldExit on failure, neither of which belongs in this process.
                # It inherits the pinned tenant.
                $env:SKYCRAFT_GRAPH_TENANT_ID = $tenantId
                & (Get-Process -Id $PID).Path -NoProfile -File $cleanupScript -Force
                if ($LASTEXITCODE -ne 0) {
                    Write-Host "[WARNING] Cleanup exited $LASTEXITCODE. The run's results stand; remove what is left by hand." -ForegroundColor Yellow
                }
            } else {
                # This lab only: without -Labs the script tears down every lab in the subscription.
                $global:LASTEXITCODE = 0   # python's code must not pass for the teardown's
                $teardown = & $cleanupScript -Labs $Lab -SubscriptionId $SubscriptionId -RunId $runId `
                    -LogDirectory $runDir -ResultsPath (Join-Path $runDir 'teardown.jsonl') -Confirm:$false
                if (-not $teardown) {
                    Write-Host "[WARNING] Cleanup did not run (exit $LASTEXITCODE). Remove what the run created by hand." -ForegroundColor Yellow
                } elseif ($teardown.TeardownFailedCount -gt 0 -or $teardown.AssertionFailedCount -gt 0) {
                    Write-Host "[WARNING] Cleanup reported $($teardown.TeardownFailedCount) failed delete(s) and $($teardown.AssertionFailedCount) failed assertion(s). Remove what is left by hand." -ForegroundColor Yellow
                }
            }
        }
        catch {
            Write-Host "[WARNING] Cleanup failed: $($_.Exception.Message)" -ForegroundColor Yellow
            Write-Host '          Remove what the run created by hand.' -ForegroundColor Yellow
        }
    }

    if ($runExit -eq 0) {
        Write-Host "Nothing to fix in lab $Lab." -ForegroundColor Green
    } else {
        Write-Host "$runExit blocking drift(s) or unknown(s) in lab $Lab. See $(Join-Path $runDir 'summary.md')." -ForegroundColor Yellow
    }
    $Host.SetShouldExit($runExit)
    exit $runExit
}
finally {
    $env:SKYCRAFT_GUIDE_DRIFT_TENANT_PREFIX = $savedPrefix
    $env:SKYCRAFT_GRAPH_TENANT_ID           = $savedGraphTenant
}
