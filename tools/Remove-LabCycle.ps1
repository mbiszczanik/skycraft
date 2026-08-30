<#
.SYNOPSIS
    Tears down everything a lab cycle deployed, and asserts that nothing survived it.

.DESCRIPTION
    Runs each lab's own Remove-LabResource.ps1 in the order tools/lab-cycle-manifest.psd1 declares,
    then sweeps the residue no lab script owns, then checks that the subscription is actually clean
    rather than assuming it.

    THE ORDER IS NOT SIMPLY THE REVERSE OF THE DEPLOY ORDER. Lab 1.3 goes FIRST, because it owns
    the CanNotDelete locks, and a lock left in place turns every delete below it into a failure that
    reads like a permissions problem. After that the order is the reverse of the deploy order, for
    the reason the deploy order existed: a lab is removed only once everything that depended on it
    is gone.

    A FAILURE HERE DOES NOT STOP THE REST. Leaving fifteen labs standing because the first delete
    failed is how a subscription accumulates the leftovers that block the next run's preflight. Each
    failure is reported, counted, and carried to the exit code; the teardown keeps going.

    RECOVERY SERVICES VAULT - WHAT IS TRUE, AND WHAT THIS REPOSITORY BELIEVED FOR MONTHS.

      Soft delete is platform-enforced and cannot be turned off. Azure Backup's 'secure by default'
      sets softDeleteState and enhancedSecurityState to AlwaysON at 14 days on every new vault.
      Creating a vault with it disabled fails with BMSUserErrorSoftDeleteStateNotSetToAlwaysON, and
      disabling it afterwards with Set-AzRecoveryServicesVaultProperty returns BadRequest. There is
      no 'disarm soft delete' step to write, so this script does not pretend to have one.

      The vault still deletes immediately, and that is the part issue #73 originally had wrong.
      Azure permits deleting a vault holding only SOFT-DELETED items; the vault then enters a
      soft-deleted state itself, at no cost, and stops being an active ARM resource. Verified end to
      end during PR #102 with a completed on-demand backup on the protected item: stop protection
      with the recovery points removed, delete the vault, and both Get-AzRecoveryServicesVault and
      'az backup vault list' come back empty - with no waiting and no support ticket. Redeploying
      the same vault name into the same resource group succeeded immediately afterwards.

      That single-pass teardown needs Azure CLI 2.75.0+ or Az PowerShell 7.5.0+. Older tooling takes
      the other path: it insists on a completely empty vault, which soft delete makes impossible, and
      the operator is left waiting out the 14-day window - which is almost certainly where the
      'permanent RSV residual' this repository believed in came from. The floor is asserted before
      anything is deleted, so an out-of-date machine is told at the start rather than after fifteen
      labs have already been removed.

      Lab 5.2's own Remove-LabResource.ps1 does the disarm and the delete. This script does not
      duplicate that work; it orders it, and then asserts the vault is gone.

    WHAT THIS SCRIPT SWEEPS THAT NO LAB SCRIPT OWNS.

      AzureBackupRG_<region>_1. Created by Azure rather than by this repository: while a VM is
      protected, the Recovery Services Vault puts a Microsoft.Compute/restorePointCollections in a
      resource group of that name, and both survive the vault. Verified on 2026-08-30 against this
      tree - the string 'AzureBackupRG' appears in no script in the repository, so nothing else
      removes it. Issue #73 allowed relying on the fix in #105; #105 shipped without it.

      A group matching the prefix is deleted only when it holds nothing but restore point
      collections. Anything else in it means it is not the group this rule means, and the sweep
      leaves it standing and says so rather than guessing.

      NetworkWatcherRG is NEVER deleted. It is Azure's own resource group, shared with every other
      workload in the subscription; lab 5.3's own teardown removes this repository's children from
      inside it, which is the correct scope.

      The three lab resource groups are deleted last, in parallel, after every lab teardown has run
      against them.

    THEN IT CHECKS. Issue #73 is explicit that a surviving vault is a failure rather than expected
    residue, so the vaults are asserted absent rather than reported. So are the AzureBackupRG groups
    and the three lab resource groups. An assertion that fails is counted like a teardown failure
    and leaves through the exit code, because a teardown that says it worked while the subscription
    disagrees is the exact failure this whole tool exists to make impossible.

    -WhatIf lists the entire plan - every lab invocation, every sweep, every resource group - and
    deletes nothing. Every destructive step goes through ShouldProcess, so there is no path that
    ignores it.

    There is no Read-Host anywhere in this script. It is meant to run unattended at the end of a
    multi-hour cycle, and a confirmation prompt at that point is a teardown that silently never
    happened.

.PARAMETER SubscriptionId
    The subscription this teardown is allowed to touch. Mandatory, and compared against the
    context's id rather than its name, for the same reason Invoke-LabCycle.ps1 does it: on
    2026-08-02 an Azure context changed identity mid-session and a cleanup query answered 'nothing
    found' - correctly, against an unrelated production subscription - one line before a -Force
    delete. On a script whose whole job is deleting, that check is the difference between a bug and
    an incident.

.PARAMETER Labs
    Tear down only these labs, by phase id. The sweep and the final assertions are skipped for a
    partial teardown: a subscription that still holds fifteen labs on purpose is not one whose
    resource groups should be deleted, and asserting it is empty would report failures that are
    entirely expected.

.PARAMETER ManifestPath
    The manifest whose Teardowns, ResidualSweep and ToolingFloor sections drive this.

.PARAMETER LabRoot
    Repository root, used to resolve each lab's scripts/ directory.

.PARAMETER LogDirectory
    Where per-teardown transcripts are written.

.PARAMETER ResultsPath
    JSONL results file. Each teardown and each assertion is appended as it happens.

.PARAMETER RunId
    Correlates these results with the deploy run that produced them. Generated when absent, so the
    script is equally usable on its own.

.PARAMETER TeardownRunner
    A scriptblock invoked once per lab invocation, returning an exit code. Injectable so the
    ordering and failure-handling tests stay offline.

.PARAMETER ContextProbe
    Returns the current Azure context.

.PARAMETER ToolingFloorRunner
    Returns the tooling-floor check results. Injectable so the tests do not depend on what happens
    to be installed on the machine running them.

.PARAMETER BackupResourceGroupProbe
    Given the prefix, returns @{ Name; ResourceTypes } for each matching resource group.

.PARAMETER ResourceGroupRemover
    Given a resource group name, deletes it. Returns nothing; throws on failure.

.PARAMETER ResourceGroupProbe
    Given a name, returns something truthy when that resource group still exists.

.PARAMETER VaultProbe
    Given an AssertAbsent entry, returns something truthy when that vault still exists.

.PARAMETER SkipSweep
    Run the per-lab teardowns and stop. No residue sweep, no resource group deletes, no assertions.
    For a teardown that is deliberately partial.

.EXAMPLE
    .\Remove-LabCycle.ps1 -SubscriptionId 00000000-0000-0000-0000-000000000000 -WhatIf

    Prints every delete this would perform, in order, and performs none of them.

.EXAMPLE
    .\Remove-LabCycle.ps1 -SubscriptionId 00000000-0000-0000-0000-000000000000 -Confirm:$false

    The real teardown, unattended.

.EXAMPLE
    .\Remove-LabCycle.ps1 -SubscriptionId 00000000-0000-0000-0000-000000000000 -Labs 5.2, 5.3 -Confirm:$false

    Removes labs 5.3 and 5.2 only, in the manifest's order, and leaves everything else - and the
    sweep and the assertions - alone.

.NOTES
    Project: SkyCraft
    Issue:   #73
#>

#Requires -Version 7.0

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'LabRoot', Justification = 'False positive: read inside the default TeardownRunner closure.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'LogDirectory', Justification = 'False positive: read inside the default TeardownRunner closure.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'ResultsPath', Justification = 'False positive: read inside the $recordResult closure.')]
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$SubscriptionId,

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
    [string]$ResultsPath = (Join-Path $PSScriptRoot 'lab-cycle-logs/lab-cycle-results.jsonl'),

    [Parameter()]
    [string]$RunId = [guid]::NewGuid().ToString('N'),

    [Parameter()]
    [scriptblock]$TeardownRunner,

    [Parameter()]
    [scriptblock]$ContextProbe = { Get-AzContext },

    [Parameter()]
    [scriptblock]$ToolingFloorRunner,

    [Parameter()]
    [scriptblock]$BackupResourceGroupProbe = {
        param($Prefix)
        # Resource types rather than the resources themselves: the rule only has to distinguish
        # 'restore point collections and nothing else' from anything else, and the type list is a
        # much smaller answer than the resource list.
        Get-AzResourceGroup -ErrorAction SilentlyContinue |
            Where-Object { $_.ResourceGroupName -like "$Prefix*" } |
            ForEach-Object {
                $types = @(Get-AzResource -ResourceGroupName $_.ResourceGroupName -ErrorAction SilentlyContinue |
                    ForEach-Object { $_.ResourceType } | Sort-Object -Unique)
                @{ Name = $_.ResourceGroupName; ResourceTypes = $types }
            }
    },

    [Parameter()]
    [scriptblock]$ResourceGroupRemover = {
        param($Name)
        # -Force suppresses Az's own confirmation, which this script has already answered through
        # ShouldProcess. -AsJob starts the delete and returns: the three lab groups are independent
        # and deleting them one after another is three sequential multi-minute waits for no reason.
        # The jobs are waited on below, because the assertions that follow have to mean something.
        Remove-AzResourceGroup -Name $Name -Force -AsJob
    },

    [Parameter()]
    [scriptblock]$ResourceGroupProbe = {
        param($Name)
        Get-AzResourceGroup -Name $Name -ErrorAction SilentlyContinue
    },

    [Parameter()]
    [scriptblock]$VaultProbe = {
        param($Entry)
        switch ($Entry.Kind) {
            'RecoveryServicesVault' {
                Get-AzRecoveryServicesVault -ResourceGroupName $Entry.ResourceGroup -Name $Entry.Name -ErrorAction SilentlyContinue
            }
            'DataProtectionBackupVault' {
                Get-AzDataProtectionBackupVault -ResourceGroupName $Entry.ResourceGroup -VaultName $Entry.Name -ErrorAction SilentlyContinue
            }
            default { throw "No probe for vault kind '$($Entry.Kind)'." }
        }
    },

    [Parameter()]
    [switch]$SkipSweep
)

$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'LabCycle.psm1') -Force

if (-not $TeardownRunner) {
    $shimPath = Join-Path $PSScriptRoot 'Invoke-LabScript.ps1'
    $TeardownRunner = {
        param($Invocation)

        $scriptsDir = Join-Path (Join-Path $LabRoot $Invocation.Lab) 'scripts'
        $safeId     = $Invocation.Lab -replace '[^A-Za-z0-9._-]', '-'

        $result = Invoke-LabScriptProcess -ShimPath $shimPath `
            -ScriptPath (Join-Path $scriptsDir 'Remove-LabResource.ps1') `
            -Arguments $Invocation.Arguments `
            -WorkingDirectory $scriptsDir `
            -TimeoutMs $Invocation.TimeoutMs `
            -TranscriptPath (Join-Path $LogDirectory "$safeId.teardown.log")

        if ($result.TimedOut) { 124 } else { [int]$result.ExitCode }
    }.GetNewClosure()
}

if (-not (Test-Path -LiteralPath $ManifestPath)) {
    Write-Host "[ERROR] Manifest not found: $ManifestPath" -ForegroundColor Red
    $Host.SetShouldExit(2)
    exit 2
}
$manifest = Import-PowerShellDataFile -LiteralPath $ManifestPath

$teardowns = @($manifest.Teardowns)
$partial   = $false
if (@($Labs).Count -gt 0) {
    $partial = $true
    # A selection names phases; a teardown entry names a lab. Mapped through the manifest's own
    # phases so the two never have to be kept in step by hand.
    $labsById = @{}
    foreach ($phase in @($manifest.Phases)) { $labsById[$phase.Id] = $phase.Lab }

    $unknown = @($Labs | Where-Object { -not $labsById.ContainsKey($_) })
    if ($unknown.Count -gt 0) {
        Write-Host "[ERROR] -Labs names phases that are not in the manifest: $($unknown -join ', ')" -ForegroundColor Red
        $Host.SetShouldExit(2)
        exit 2
    }

    $wanted    = @($Labs | ForEach-Object { $labsById[$_] })
    $teardowns = @($teardowns | Where-Object { $_.Lab -in $wanted })
}

$results     = [System.Collections.Generic.List[hashtable]]::new()
$leftBehind  = [System.Collections.Generic.List[hashtable]]::new()
$assertions  = [System.Collections.Generic.List[hashtable]]::new()

$recordResult = {
    param($Record)
    if ($WhatIfPreference) { return }
    $line = [ordered]@{ RunId = $RunId; At = (Get-Date).ToString('o'); SubscriptionId = $SubscriptionId; Kind = 'Teardown' }
    foreach ($key in $Record.Keys) { $line[$key] = $Record[$key] }
    Write-LabCycleResultLine -Path $ResultsPath -Record $line
}.GetNewClosure()

Write-Host ''
Write-Host "Lab cycle teardown - $($teardowns.Count) lab(s)" -ForegroundColor Cyan
Write-Host "  Subscription: $SubscriptionId" -ForegroundColor Gray
Write-Host "  Manifest:     $ManifestPath" -ForegroundColor Gray
Write-Host "  Run id:       $RunId" -ForegroundColor Gray
if ($WhatIfPreference) { Write-Host '  -WhatIf - the plan is printed and nothing is deleted' -ForegroundColor Yellow }
if ($partial) {
    Write-Host "  -Labs: only $($Labs -join ', '). The residue sweep and the final assertions are skipped: a subscription that still holds the other labs on purpose is not one to assert empty." -ForegroundColor Yellow
}
if ($SkipSweep -and -not $partial) {
    Write-Host '  -SkipSweep: per-lab teardown only. Nothing is swept, no resource group is deleted, and nothing is asserted.' -ForegroundColor Yellow
}
Write-Host ''

# -- Tooling floor -----------------------------------------------------------------------------
# First, and before anything is deleted. See the RECOVERY SERVICES VAULT note above for why an
# out-of-date az CLI or Az PowerShell turns a single-pass teardown into a 14-day wait, and why
# learning that at the end is much worse than learning it here.
if (-not $ToolingFloorRunner) {
    $ToolingFloorRunner = {
        Test-LabCycleToolingFloor -MinimumAzCli $manifest.ToolingFloor.AzCli `
            -MinimumAzPowerShell $manifest.ToolingFloor.AzPowerShell
    }.GetNewClosure()
}

Write-Host '  Preflight' -ForegroundColor Cyan
$checks = [System.Collections.Generic.List[hashtable]]::new()
foreach ($check in @(& $ToolingFloorRunner)) { $checks.Add($check) }

# The subscription check runs whatever the tooling said, because its answer is the one an operator
# most needs to see: 'your az is old AND you are pointed at the wrong subscription' is two facts,
# and reporting only the first would let the second be discovered on the next attempt.
$checks.Add((Test-LabCycleSubscription -SubscriptionId $SubscriptionId -ContextProbe $ContextProbe))

foreach ($check in $checks) {
    if (-not $check.Ok) { Write-Host "    [STOP] $($check.Name): $($check.Detail)" -ForegroundColor Red }
    else { Write-Host "    [ OK ] $($check.Name): $($check.Detail)" -ForegroundColor DarkGray }
}
$blocked = @($checks | Where-Object { -not $_.Ok })
if ($blocked.Count -gt 0) {
    Write-Host ''
    Write-Host "[ERROR] Teardown refused to start: $($blocked[0].Name)" -ForegroundColor Red
    Write-Host '        Nothing has been deleted.' -ForegroundColor Gray
    $Host.SetShouldExit(3)
    exit 3
}
Write-Host ''

# -- Per-lab teardown --------------------------------------------------------------------------
Write-Host '  Labs' -ForegroundColor Cyan
foreach ($entry in $teardowns) {
    $worstExit = 0
    $ran       = $false

    foreach ($invocation in @($entry.Invocations)) {
        $described = ($invocation.Keys | Sort-Object | ForEach-Object { "-$_ $($invocation[$_])" }) -join ' '
        if (-not $PSCmdlet.ShouldProcess("$($entry.Lab) [$described]", 'run Remove-LabResource.ps1')) { continue }

        $ran = $true
        # Each invocation carries its own arguments. Labs 3.2, 4.3 and 4.4 have no 'all' in their
        # -Environment ValidateSet, so one call per environment is the only way to remove
        # everything they deployed.
        $code = & $TeardownRunner @{
            Lab       = $entry.Lab
            Arguments = $invocation
            TimeoutMs = $entry.TimeoutMs
        }
        $code = if ($code -is [int]) { $code } else { [int]$code.ExitCode }
        if ($code -ne 0 -and $worstExit -eq 0) { $worstExit = $code }
    }

    if (-not $ran) {
        Write-Host "    [PLAN] $($entry.Lab)" -ForegroundColor Gray
        continue
    }

    if ($worstExit -eq 0) {
        $record = @{ Lab = $entry.Lab; Status = 'Removed'; ExitCode = 0 }
        Write-Host "    [ OK ] $($entry.Lab)" -ForegroundColor Green
    }
    else {
        $record = @{ Lab = $entry.Lab; Status = 'Failed'; ExitCode = $worstExit }
        Write-Host "    [FAIL] $($entry.Lab) - exited $worstExit (continuing; the other labs still have to go)" -ForegroundColor Red
    }
    $results.Add($record)
    & $recordResult $record

    # Guarded rather than wrapped: @($null) is a one-element array holding $null, so an unguarded
    # foreach over a missing LeavesBehind adds one empty residue entry per lab and the report
    # claims things were left behind that do not exist.
    if ($entry.LeavesBehind) {
        foreach ($residue in @($entry.LeavesBehind)) {
            $leftBehind.Add(@{ Lab = $entry.Lab; What = $residue.What; Why = $residue.Why })
        }
    }
}

foreach ($residue in $leftBehind) {
    Write-Host "    [KEPT] $($residue.Lab): $($residue.What) - $($residue.Why)" -ForegroundColor Yellow
}

# -- Residue sweep, and the assertions -----------------------------------------------------------
$sweep = $manifest.ResidualSweep
$doSweep = -not $SkipSweep -and -not $partial

if (-not $doSweep) {
    Write-Host ''
    Write-Host '  Sweep and assertions skipped for a partial teardown.' -ForegroundColor Yellow
}
else {
    Write-Host ''
    Write-Host '  Sweep' -ForegroundColor Cyan

    # AzureBackupRG_<region>_1. Azure's, not ours, and it outlives the vault that created it.
    foreach ($group in @(& $BackupResourceGroupProbe $sweep.BackupResourceGroupPrefix)) {
        if (-not $group) { continue }

        $unexpected = @($group.ResourceTypes | Where-Object { $_ -ne 'Microsoft.Compute/restorePointCollections' })
        if ($unexpected.Count -gt 0) {
            # Left standing on purpose. A group by this name holding something else is not the
            # group this rule means, and deleting it on a name match would be the sweep doing the
            # exact class of damage it exists to prevent.
            $what = "resource group '$($group.Name)'"
            $why  = "left standing: it holds $($unexpected -join ', '), not only restore point collections, so it is not the orphan this sweep removes. Check it by hand."
            $leftBehind.Add(@{ Lab = '(sweep)'; What = $what; Why = $why })
            Write-Host "    [KEPT] $what - $why" -ForegroundColor Yellow
            continue
        }

        if (-not $PSCmdlet.ShouldProcess($group.Name, 'delete orphaned Azure Backup resource group')) {
            Write-Host "    [PLAN] delete $($group.Name)" -ForegroundColor Gray
            continue
        }

        try {
            $job = & $ResourceGroupRemover $group.Name
            if ($job) { $job | Wait-Job | Receive-Job -ErrorAction Stop | Out-Null }
            $record = @{ Lab = '(sweep)'; Status = 'Removed'; ExitCode = 0; Target = $group.Name }
            Write-Host "    [ OK ] $($group.Name)" -ForegroundColor Green
        }
        catch {
            $record = @{ Lab = '(sweep)'; Status = 'Failed'; ExitCode = 1; Target = $group.Name; Detail = "$_" }
            Write-Host "    [FAIL] $($group.Name) - $_" -ForegroundColor Red
        }
        $results.Add($record)
        & $recordResult $record
    }

    # The three lab resource groups, last and in parallel. Each is independent of the others, and
    # a resource group delete is minutes rather than seconds.
    $jobs = @()
    foreach ($name in @($sweep.ResourceGroups)) {
        if (-not (& $ResourceGroupProbe $name)) {
            Write-Host "    [ -- ] $name already gone" -ForegroundColor DarkGray
            continue
        }
        if (-not $PSCmdlet.ShouldProcess($name, 'delete lab resource group')) {
            Write-Host "    [PLAN] delete $name" -ForegroundColor Gray
            continue
        }
        Write-Host "    [ .. ] deleting $name" -ForegroundColor Yellow
        try { $jobs += @{ Name = $name; Job = (& $ResourceGroupRemover $name) } }
        catch {
            $record = @{ Lab = '(sweep)'; Status = 'Failed'; ExitCode = 1; Target = $name; Detail = "$_" }
            $results.Add($record)
            & $recordResult $record
            Write-Host "    [FAIL] $name - $_" -ForegroundColor Red
        }
    }

    foreach ($started in $jobs) {
        try {
            if ($started.Job) { $started.Job | Wait-Job | Receive-Job -ErrorAction Stop | Out-Null }
            $record = @{ Lab = '(sweep)'; Status = 'Removed'; ExitCode = 0; Target = $started.Name }
            Write-Host "    [ OK ] $($started.Name)" -ForegroundColor Green
        }
        catch {
            $record = @{ Lab = '(sweep)'; Status = 'Failed'; ExitCode = 1; Target = $started.Name; Detail = "$_" }
            Write-Host "    [FAIL] $($started.Name) - $_" -ForegroundColor Red
        }
        $results.Add($record)
        & $recordResult $record
    }

    # -- Assertions ------------------------------------------------------------------------------
    # Not reported as residue. Issue #73 is explicit: a surviving vault is a failure, and treating
    # it as expected residue is how this repository spent months believing in a 14-day wait that
    # was not there. A teardown that says it worked while the subscription disagrees is the exact
    # failure this tool exists to make impossible, so these leave through the exit code.
    #
    # Skipped entirely under -WhatIf: nothing was deleted, so everything would still be present and
    # every assertion would fail for the one reason that is not interesting.
    if (-not $WhatIfPreference) {
        Write-Host ''
        Write-Host '  Assertions' -ForegroundColor Cyan

        foreach ($entry in @($sweep.AssertAbsent)) {
            $survivor = & $VaultProbe $entry
            if ($survivor) {
                $detail = "$($entry.Kind) '$($entry.Name)' still exists in '$($entry.ResourceGroup)'. Its lab's own Remove-LabResource.ps1 reported no failure, so this is a teardown that lied. Check the transcript for that lab, and check the az CLI / Az PowerShell versions above: older tooling refuses to delete a vault holding soft-deleted items and leaves it exactly like this."
                $assertions.Add(@{ Name = "$($entry.Kind) absent"; Ok = $false; Detail = $detail })
                Write-Host "    [FAIL] $detail" -ForegroundColor Red
            }
            else {
                $assertions.Add(@{ Name = "$($entry.Kind) absent"; Ok = $true; Detail = "$($entry.Name) is gone" })
                Write-Host "    [ OK ] $($entry.Kind) '$($entry.Name)' is gone" -ForegroundColor Green
            }
        }

        $survivingBackupGroups = @(& $BackupResourceGroupProbe $sweep.BackupResourceGroupPrefix | Where-Object { $_ })
        if ($survivingBackupGroups.Count -gt 0) {
            $names = @($survivingBackupGroups | ForEach-Object { $_.Name }) -join ', '
            $assertions.Add(@{ Name = 'no AzureBackupRG left'; Ok = $false; Detail = "still present: $names" })
            Write-Host "    [FAIL] Azure Backup resource groups still present: $names" -ForegroundColor Red
        }
        else {
            $assertions.Add(@{ Name = 'no AzureBackupRG left'; Ok = $true; Detail = 'none' })
            Write-Host '    [ OK ] no AzureBackupRG_* resource group remains' -ForegroundColor Green
        }

        foreach ($name in @($sweep.ResourceGroups)) {
            if (& $ResourceGroupProbe $name) {
                $assertions.Add(@{ Name = 'lab resource group absent'; Ok = $false; Detail = "'$name' still exists" })
                Write-Host "    [FAIL] resource group '$name' still exists" -ForegroundColor Red
            }
            else {
                $assertions.Add(@{ Name = 'lab resource group absent'; Ok = $true; Detail = "'$name' is gone" })
                Write-Host "    [ OK ] resource group '$name' is gone" -ForegroundColor Green
            }
        }

        foreach ($assertion in $assertions) {
            $assertionStatus = if ($assertion.Ok) { 'Passed' } else { 'Failed' }
            & $recordResult @{ Lab = '(assertion)'; Status = $assertionStatus; Target = $assertion.Name; Detail = $assertion.Detail }
        }
    }
}

$failedCount    = @($results | Where-Object { $_.Status -eq 'Failed' }).Count
$assertionFails = @($assertions | Where-Object { -not $_.Ok }).Count

Write-Host ''
Write-Host "  Removed $(@($results | Where-Object { $_.Status -eq 'Removed' }).Count)  Failed $failedCount  Assertions failed $assertionFails" -ForegroundColor Cyan
if ($leftBehind.Count -gt 0) {
    Write-Host "  Left behind on purpose: $($leftBehind.Count) - see the entries above, and TROUBLESHOOTING.md." -ForegroundColor Yellow
}
Write-Host ''

[pscustomobject]@{
    RunId               = $RunId
    Teardowns           = $results
    LeftBehind          = $leftBehind
    Assertions          = $assertions
    TeardownFailedCount = $failedCount
    AssertionFailedCount = $assertionFails
}

# Both counts, because both mean the subscription is not in the state this script claims. A
# teardown that failed is one the operator has to finish by hand; an assertion that failed is one
# where every delete reported success and the subscription still disagrees, which is worse.
#
# $Host.SetShouldExit as well as `exit`, for the reason tests/Exit-Code-Propagation.Tests.ps1
# exists: a '#Requires -Modules' script launched with 'pwsh -File' has its `exit` discarded and the
# process reports 0 regardless.
$exitCode = $failedCount + $assertionFails
$Host.SetShouldExit($exitCode)
exit $exitCode
