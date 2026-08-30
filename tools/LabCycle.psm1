<#
.SYNOPSIS
    Shared engine for the lab cycle orchestrator and its teardown.

.DESCRIPTION
    Everything both tools/Invoke-LabCycle.ps1 and tools/Remove-LabCycle.ps1 need, and everything
    that can be tested without Azure: the ordering and dependency logic, the child-process runner,
    preflight, the retry classifier, the version floor, the report and the JSONL writer.

    Held here rather than inside either script so that tests/LabCycle.Tests.ps1 can call exactly
    the functions the engine calls. A second copy of a topological sort living in the test file
    could drift from the shipped one while both stayed green, which would leave the manifest's
    acyclicity checked by code that never runs a phase.

    Every function that would otherwise reach Azure takes an injectable probe with a real default,
    so the whole suite runs offline while the shipped path stays the tested path.

.EXAMPLE
    Import-Module ./tools/LabCycle.psm1
    Get-PhaseOrder -Phases (Import-PowerShellDataFile ./tools/lab-cycle-manifest.psd1).Phases

.NOTES
    Project: SkyCraft
#>

#Requires -Version 7.0

$ErrorActionPreference = 'Stop'

function Get-PhaseOrder {
    <#
    .SYNOPSIS
        Returns phase ids in an order where no phase precedes one it depends on.

    .DESCRIPTION
        Kahn's algorithm. Throws on a cycle, naming the phases involved, because a cyclic graph
        cannot be partially run: deploying the orderable part would leave resources behind that
        the run cannot reason about. The engine calls this before it starts anything.

        Ties are broken by the order the phases were DECLARED in, which makes the run order
        deterministic and, where the graph allows it, identical to the manifest's own order.
        Without an explicit tie-break, two runs of the same manifest could order independent
        phases differently, a resumed run could diverge from the run it continues, and two
        transcripts of the same manifest would not diff. Hashtable key enumeration carries no
        ordering guarantee, so the tie-break has to be explicit rather than inherited from the
        data structure.

        DECLARATION ORDER RATHER THAN SORTED IDS, and the difference is not cosmetic. Issue #73
        names the order the cycle must run in, and the v0.8.0 live run measured it. Sorting ids
        would put lab 3.1 - which declares its own resource groups and therefore depends on
        nothing - in the very first ready batch alongside 1.2, ahead of 1.3, and the run would
        stop matching the order anyone had actually verified. Declaration order reproduces the
        manifest exactly whenever the dependencies permit it, and the result is still a valid
        topological order because a phase is only ever considered once every dependency of its
        own has already been placed.

        A dependency on an id outside the set is ignored rather than treated as unsatisfiable.
        The engine orders live phases only, and an excluded phase is not in that set; the manifest
        tests separately forbid a live phase from depending on an excluded one, so the check that
        matters is made where the information exists.

    .PARAMETER Phases
        Phase objects, each with an Id and a DependsOn list.

    .NOTES
        Project: SkyCraft
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        $Phases
    )

    $pending = @{}
    # Captured before anything is removed from $pending, because that is the only point at which
    # the declared sequence is still available: $pending is a hashtable and loses it immediately.
    $declared = @{}
    $index = 0
    foreach ($phase in $Phases) {
        $pending[$phase.Id] = @($phase.DependsOn)
        $declared[$phase.Id] = $index
        $index++
    }

    $order = [System.Collections.Generic.List[string]]::new()
    while ($pending.Count -gt 0) {
        $ready = @(
            $pending.Keys |
                Where-Object { @($pending[$_] | Where-Object { $pending.ContainsKey($_) }).Count -eq 0 } |
                Sort-Object { $declared[$_] }
        )
        if ($ready.Count -eq 0) {
            $stuck = @($pending.Keys | Sort-Object) -join ', '
            throw "Dependency cycle: these phases cannot be ordered, so none of them is safe to start: $stuck"
        }
        # ONE PHASE PER ITERATION, not the whole ready batch. Emitting the batch is the textbook
        # shape and it is wrong for what this has to produce: once 1.2 is placed, 1.3, 2.1, 3.1,
        # 3.3 and 4.1 all become ready at the same moment, and emitting them together puts 3.1 and
        # 4.1 ahead of 2.2 no matter how the batch is sorted. Taking only the earliest-declared
        # ready phase and re-deriving the ready set lets 2.2 - which 2.1 has just unblocked - take
        # its declared place. The result is still a valid topological order, and it reproduces the
        # manifest exactly whenever the dependencies permit it.
        $next = $ready[0]
        $order.Add($next)
        $pending.Remove($next)
    }

    $order
}

function Get-DependentPhase {
    <#
    .SYNOPSIS
        Returns every phase reachable from the given id - what a failure takes down with it.

    .DESCRIPTION
        NOT USED BY THE ENGINE'S SKIP LOGIC, deliberately. The engine does not need it: walking the
        topological order and checking each phase's own dependencies reaches the same set, one edge
        at a time, and that is simpler than precomputing reachability. This exists for the report,
        which needs the whole set at once - what a single failure cost the run - without re-walking
        the order.

        Transitive, not just the immediate dependents. A phase two edges below a failure would
        deploy against resources that were never created, so it is skipped for the same reason
        the first one is.

        Nothing outside that reachable set is returned. Independent branches of the graph are
        unaffected by a failure elsewhere, and skipping them would throw away coverage the run
        could still have collected - which for a run measured in hours is the difference between
        a partial result and a wasted afternoon.

    .PARAMETER Phases
        Phase objects, each with an Id and a DependsOn list.

    .PARAMETER Id
        The phase whose dependents are wanted.

    .NOTES
        Project: SkyCraft
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        $Phases,

        [Parameter(Mandatory)]
        [string]$Id
    )

    $found = [System.Collections.Generic.HashSet[string]]::new()
    $frontier = [System.Collections.Generic.Queue[string]]::new()
    $frontier.Enqueue($Id)

    while ($frontier.Count -gt 0) {
        $current = $frontier.Dequeue()
        foreach ($phase in $Phases) {
            if ($phase.Id -eq $current) { continue }
            if (@($phase.DependsOn) -notcontains $current) { continue }
            # Add returns false when the id is already present, which is also what stops a
            # diamond dependency from being walked twice.
            if ($found.Add($phase.Id)) { $frontier.Enqueue($phase.Id) }
        }
    }

    @($found)
}

function Invoke-LabScriptProcess {
    <#
    .SYNOPSIS
        Runs one lab script as a child process and returns its real exit code.

    .DESCRIPTION
        Drives System.Diagnostics.Process directly rather than using Start-Process, which offers
        either a visible window whose output is never captured or redirection to files that are not
        live. A run measured in hours needs both: progress on the console as it happens, and a
        transcript afterwards. Asynchronous readers feed both from one pair of streams.

        Always invoked through tools/Invoke-LabScript.ps1. Launching a lab script with pwsh -File
        directly returns 0 whatever the script exited with, because every lab script declares
        #Requires -Modules; the shim exists solely to carry that code back out.

        WorkingDirectory is mandatory rather than tidiness. Lab 2.3 declares -TemplateFile with a
        default resolved against the current directory rather than $PSScriptRoot, so a lab invoked
        from anywhere but its own scripts/ folder breaks, and the failure looks like a broken
        template rather than a misplaced caller.

        On timeout the whole process tree is killed - Kill($true), not Stop-Process. Lab 3.3 sleeps
        90 seconds mid-deployment waiting on DNS propagation, and a kill that left a grandchild
        running would leak a process the report cannot see, because the engine believes the phase
        is over.

    .PARAMETER ShimPath
        Path to tools/Invoke-LabScript.ps1.

    .PARAMETER ScriptPath
        The lab script to run.

    .PARAMETER Arguments
        Named arguments for the lab script. Serialised to JSON for the shim, which splats them, so
        nothing is ever quoted into a command line.

    .PARAMETER WorkingDirectory
        Directory to run from. Always the lab's own scripts/ folder.

    .PARAMETER TimeoutMs
        Milliseconds before the process tree is killed.

    .PARAMETER TranscriptPath
        File to write the combined output to. Its directory is created if missing.

    .PARAMETER StdinAnswers
        Lines to feed the child's standard input, one per Read-Host the script will reach, before
        stdin is closed.

        Needed by exactly one lab. Lab 2.2's Deploy-Bicep.ps1 asks whether to deploy Azure Bastion
        through Read-Host and declares no switch to answer it with, so an unattended run has
        nowhere else to put the answer. Feeding a line is not the same as leaving stdin at
        end-of-file: Read-Host on a closed stream throws under $ErrorActionPreference = 'Stop', and
        the phase would then fail on the prompt rather than on anything to do with the lab.

        Stdin is redirected only when answers are supplied. A child that inherits this process's
        stdin can still be driven by hand, which is what makes a phase debuggable on its own.

    .EXAMPLE
        Invoke-LabScriptProcess -ShimPath ./tools/Invoke-LabScript.ps1 `
            -ScriptPath ./module-2-networking/2.1-virtual-networks/scripts/Deploy-Bicep.ps1 `
            -WorkingDirectory ./module-2-networking/2.1-virtual-networks/scripts `
            -TimeoutMs 1200000 -TranscriptPath ./tools/lab-cycle-logs/2.1-main.deploy.log

    .NOTES
        Project: SkyCraft
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ShimPath,

        [Parameter(Mandatory)]
        [string]$ScriptPath,

        [Parameter()]
        [hashtable]$Arguments,

        [Parameter(Mandatory)]
        [string]$WorkingDirectory,

        [Parameter(Mandatory)]
        [int]$TimeoutMs,

        [Parameter(Mandatory)]
        [string]$TranscriptPath,

        [Parameter()]
        [AllowEmptyCollection()]
        [string[]]$StdinAnswers = @()
    )

    $transcriptDir = Split-Path -Parent $TranscriptPath
    if ($transcriptDir -and -not (Test-Path -LiteralPath $transcriptDir)) {
        New-Item -ItemType Directory -Path $transcriptDir -Force | Out-Null
    }

    $argumentJson = if ($Arguments -and $Arguments.Count -gt 0) { $Arguments | ConvertTo-Json -Compress } else { $null }

    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName               = 'pwsh'
    $startInfo.WorkingDirectory       = $WorkingDirectory
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError  = $true
    $startInfo.UseShellExecute        = $false
    $startInfo.CreateNoWindow         = $true
    # Only when there is something to say. Redirecting unconditionally would close stdin on every
    # child, turning any prompt this manifest has not accounted for from a visible hang into a
    # throw somewhere inside the lab - which is harder to read, not easier.
    $feedStdin                        = @($StdinAnswers).Count -gt 0
    $startInfo.RedirectStandardInput  = $feedStdin
    foreach ($argument in '-NoProfile', '-File', $ShimPath, '-TargetScript', $ScriptPath) {
        $startInfo.ArgumentList.Add($argument)
    }
    if ($argumentJson) {
        $startInfo.ArgumentList.Add('-ArgumentJson')
        $startInfo.ArgumentList.Add($argumentJson)
    }

    # Both readers append here and the loop below drains it. Synchronized rather than a plain list
    # because the handlers run on threadpool threads rather than this one.
    $sink = [System.Collections.ArrayList]::Synchronized([System.Collections.ArrayList]::new())

    # WaitForExit() is not enough to know the output is all in. The -Action blocks below run on
    # PowerShell's event queue, which is serviced when this runspace is idle - so a script that
    # exits quickly can be reaped before its lines have been appended, and the transcript loses
    # them. This was measured: one full-suite run in seven failed the transcript assertion while
    # the same test passed in isolation every time.
    #
    # BeginOutputReadLine signals end-of-stream by calling the handler once with a $null Data, so
    # these two flags are a definite answer to 'has everything arrived' rather than a guess at how
    # long to wait for it.
    $streamState = [hashtable]::Synchronized(@{ OutDone = $false; ErrDone = $false })
    $handlerData = @{ Sink = $sink; State = $streamState }

    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $startInfo

    $onOutput = Register-ObjectEvent -InputObject $process -EventName OutputDataReceived -MessageData $handlerData -Action {
        if ($null -eq $EventArgs.Data) { $Event.MessageData.State.OutDone = $true }
        else { [void]$Event.MessageData.Sink.Add($EventArgs.Data) }
    }
    $onError = Register-ObjectEvent -InputObject $process -EventName ErrorDataReceived -MessageData $handlerData -Action {
        # Tagged, because Az reports failures on stderr and an untagged transcript would show a
        # failure with nothing to say it was one.
        if ($null -eq $EventArgs.Data) { $Event.MessageData.State.ErrDone = $true }
        else { [void]$Event.MessageData.Sink.Add("[stderr] $($EventArgs.Data)") }
    }

    $writer   = [System.IO.StreamWriter]::new($TranscriptPath, $false)
    $timedOut = $false
    $drained  = 0
    $exitCode = -1

    try {
        $writer.AutoFlush = $true
        $writer.WriteLine("# $ScriptPath")
        $writer.WriteLine("# cwd: $WorkingDirectory")
        if ($argumentJson) { $writer.WriteLine("# args: $argumentJson") }
        # Recorded, because a phase that behaved differently from an interactive run needs the
        # answers it was given to be visible in its own transcript rather than only in the manifest.
        if ($feedStdin) { $writer.WriteLine("# stdin: $(@($StdinAnswers).Count) canned answer(s)") }

        [void]$process.Start()
        $process.BeginOutputReadLine()
        $process.BeginErrorReadLine()

        # Written and then CLOSED. Leaving the stream open makes a script that reaches one more
        # Read-Host than the manifest planned for wait on input that will never come, and the only
        # thing that ends the phase is its timeout - forty minutes to learn about a prompt. Closing
        # turns that into an immediate end-of-file, which the transcript shows for what it is.
        if ($feedStdin) {
            foreach ($answer in @($StdinAnswers)) { $process.StandardInput.WriteLine($answer) }
            $process.StandardInput.Close()
        }

        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        while (-not $process.HasExited) {
            while ($drained -lt $sink.Count) {
                $line = $sink[$drained]
                Write-Host "    $line" -ForegroundColor DarkGray
                $writer.WriteLine($line)
                $drained++
            }
            if ($stopwatch.ElapsedMilliseconds -gt $TimeoutMs) {
                $timedOut = $true
                # $true is the whole point: the tree, not only the process Start handed back.
                $process.Kill($true)
                break
            }
            Start-Sleep -Milliseconds 100
        }

        $process.WaitForExit()

        # Drain until both streams have signalled end-of-stream, not merely until the process is
        # gone. Start-Sleep is what lets this runspace go idle so the queued -Action blocks run;
        # without yielding here the flags would never flip and this would spin until the grace
        # period expired. The grace period is a backstop against a handler that never fires, not
        # the mechanism - if it is ever hit, the transcript is short and the run should not pretend
        # otherwise, so it says so.
        $grace = [System.Diagnostics.Stopwatch]::StartNew()
        while (-not ($streamState.OutDone -and $streamState.ErrDone) -and $grace.ElapsedMilliseconds -lt 10000) {
            while ($drained -lt $sink.Count) {
                $line = $sink[$drained]
                Write-Host "    $line" -ForegroundColor DarkGray
                $writer.WriteLine($line)
                $drained++
            }
            Start-Sleep -Milliseconds 25
        }

        while ($drained -lt $sink.Count) {
            $line = $sink[$drained]
            Write-Host "    $line" -ForegroundColor DarkGray
            $writer.WriteLine($line)
            $drained++
        }

        if (-not ($streamState.OutDone -and $streamState.ErrDone)) {
            $writer.WriteLine('# transcript may be incomplete: output streams did not close within 10s of exit')
        }

        $exitCode = $process.ExitCode
        if ($timedOut) { $writer.WriteLine("# killed after ${TimeoutMs}ms") }
    }
    finally {
        Unregister-Event -SourceIdentifier $onOutput.Name -ErrorAction SilentlyContinue
        Unregister-Event -SourceIdentifier $onError.Name -ErrorAction SilentlyContinue
        $writer.Dispose()
        $process.Dispose()
    }

    [pscustomobject]@{
        ExitCode = $exitCode
        TimedOut = $timedOut
        # Returned as well as written to the transcript so the engine can classify a failure
        # without re-reading a file it does not know the path of - the transcript path is built
        # inside the runner, and having the engine reconstruct it would be two places to keep
        # agreeing about a name.
        Output   = ($sink -join [Environment]::NewLine)
    }
}

function Write-LabCycleReport {
    <#
    .SYNOPSIS
        Writes the human-readable run report.

    .DESCRIPTION
        The state file is the machine-readable record; this is the one a person reads, so it says
        what the run cannot claim as well as what it did.

        Every section is here because leaving it out would let the report overstate the run:
          - coverage split three ways, because a parameter file that was deployed and one that was
            only compiled are not the same coverage
          - each skip named with the failure that caused it, and each failure with what it cost, so
            nobody re-walks the graph by hand to find out why a phase never ran
          - each exclusion with its reason rather than only its count
          - residue, because omitting what was knowingly left standing claims a cleanliness the
            subscription does not have, and the next run's preflight is what contradicts it
          - teardown kept separate, because 'the lab failed' and 'the lab could not be removed'
            send a reader to different places

    .PARAMETER Path
        Report file to write.

    .PARAMETER SubscriptionId
        Subscription the run was allowed to touch.

    .PARAMETER ManifestPath
        Manifest that was run.

    .PARAMETER Phases
        Phase results.

    .PARAMETER Teardowns
        Teardown results.

    .PARAMETER Assertions
        What the teardown checked afterwards - that the vaults are gone, that no AzureBackupRG
        survived, that the lab resource groups are gone. Rendered as its own section rather than
        folded into Teardown, because they answer different questions: Teardown says every delete
        reported success, and this says the subscription agrees. A teardown where the first is
        clean and the second is not is the exact failure worth a section of its own.

    .PARAMETER LeftBehind
        Documented residue.

    .PARAMETER Coverage
        Live / CompileOnly / Uncovered counts.

    .PARAMETER LivePhases
        The manifest's live phases, used to work out what each failure cost.

    .PARAMETER LogDirectory
        Where the per-step transcripts were written.

    .PARAMETER DryRun
        The run planned only.

    .EXAMPLE
        Write-LabCycleReport -Path ./tools/lab-cycle-report.md -SubscriptionId $id -Phases $results

    .NOTES
        Project: SkyCraft
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$SubscriptionId,
        [Parameter()][string]$ManifestPath,
        [Parameter()][AllowEmptyCollection()]$Phases = @(),
        [Parameter()][AllowEmptyCollection()]$Teardowns = @(),
        [Parameter()][AllowEmptyCollection()]$Assertions = @(),
        [Parameter()][AllowEmptyCollection()]$LeftBehind = @(),
        [Parameter()]$Coverage,
        [Parameter()][AllowEmptyCollection()]$LivePhases = @(),
        [Parameter()][string]$LogDirectory,
        [Parameter()][switch]$DryRun
    )

    if (-not $PSCmdlet.ShouldProcess($Path, 'write lab cycle report')) { return }

    $directory = Split-Path -Parent $Path
    if ($directory -and -not (Test-Path -LiteralPath $directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }

    # 'Failed*' rather than equality, the same convention the engine uses, so a compound status
    # added later still lands in the Failed section instead of vanishing from the report.
    $failed   = @($Phases | Where-Object { $_.Status -like 'Failed*' })
    $skipped  = @($Phases | Where-Object { $_.Status -eq 'Skipped' })
    $excluded = @($Phases | Where-Object { $_.Status -eq 'Excluded' })

    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add('# Lab cycle report')
    $lines.Add('')
    $lines.Add("- Run at: $((Get-Date).ToString('o'))")
    $lines.Add("- Subscription: $SubscriptionId")
    $lines.Add("- Manifest: $ManifestPath")
    if ($LogDirectory) { $lines.Add("- Transcripts: $LogDirectory") }
    if ($DryRun) { $lines.Add('- DRY RUN - nothing was deployed') }
    $lines.Add('')

    $lines.Add('## Summary')
    $lines.Add('')
    $lines.Add("- Succeeded: $(@($Phases | Where-Object { $_.Status -like 'Succeeded*' }).Count)")
    $lines.Add("- Failed: $($failed.Count)")
    $lines.Add("- Skipped: $($skipped.Count)")
    $lines.Add("- Excluded: $($excluded.Count)")
    $lines.Add('')

    $lines.Add('## Coverage')
    $lines.Add('')
    $lines.Add('Split rather than totalled, and split by outcome rather than by intent. A file deployed and validated, one deployed but not validated, one that failed, one that never ran and one only ever compiled are five different kinds of coverage. Each phase appears in exactly one line below.')
    $lines.Add('')
    $lines.Add("- Live, deployed and validated this run: $($Coverage.Live)")
    $lines.Add("- Deployed, but validation not performed: $($Coverage.DeployedNotValidated)")
    $lines.Add("- Failed: $($Coverage.Failed)")
    $lines.Add("- Never ran: $($Coverage.NotRun)")
    $lines.Add("- Compile-only, never deployed: $($Coverage.CompileOnly)")
    $lines.Add("- Unaccounted for: $($Coverage.Uncovered)")
    $lines.Add('')

    $lines.Add('## Phases')
    $lines.Add('')
    $lines.Add('| Phase | Lab | Status | Exit | Attempts | Duration (ms) | Transcript |')
    $lines.Add('| --- | --- | --- | --- | --- | --- | --- |')
    foreach ($phase in $Phases) {
        $safeId   = "$($phase.Id)" -replace '[^A-Za-z0-9._-]', '-'
        # 'Skipped' belongs with 'Excluded' and 'DryRun': all three ran no step, so none of them
        # wrote a transcript. Naming one anyway sends the reader to a file that does not exist.
        $log      = if ($LogDirectory -and $phase.Status -notin 'Excluded', 'DryRun', 'Skipped') { "$safeId.deploy.log" } else { '-' }
        $exit     = if ($null -ne $phase.ExitCode) { $phase.ExitCode } else { '-' }
        $attempts = if ($phase.Attempts) { $phase.Attempts } else { '-' }
        $lines.Add("| $($phase.Id) | $($phase.Lab) | $($phase.Status) | $exit | $attempts | $($phase.DurationMs) | $log |")
    }
    $lines.Add('')

    $lines.Add('## Failed')
    $lines.Add('')
    if ($failed.Count -eq 0) { $lines.Add('None.') }
    else {
        foreach ($phase in $failed) {
            # What the failure cost, stated rather than left to be derived. This is what
            # Get-DependentPhase is for: everything downstream never ran because of this phase.
            $cost = @(Get-DependentPhase -Phases $LivePhases -Id $phase.Id) | Sort-Object
            $costText = if ($cost.Count -gt 0) { "cost $($cost.Count) phase(s): $($cost -join ', ')" } else { 'cost no other phase' }
            $lines.Add("- **$($phase.Id)** ($($phase.Lab)) - $($phase.Status), $($phase.FailedStep) exited $($phase.ExitCode); $costText")
        }
    }
    $lines.Add('')

    $lines.Add('## Skipped')
    $lines.Add('')
    if ($skipped.Count -eq 0) { $lines.Add('None.') }
    else {
        foreach ($phase in $skipped) {
            $lines.Add("- **$($phase.Id)** ($($phase.Lab)) - never ran; caused by **$($phase.Cause)**")
        }
    }
    $lines.Add('')

    # Its own section, and deliberately not folded into Failed or Excluded. 'This environment cannot
    # check it' is neither 'it is broken' nor 'we never deployed it', and a reader who conflates
    # them debugs a deployment that worked or trusts a check that never ran.
    $validationExcluded = @($Phases | Where-Object { $_.ValidationExcluded })
    $lines.Add('## Validation excluded')
    $lines.Add('')
    if ($validationExcluded.Count -eq 0) { $lines.Add('None.') }
    else {
        $lines.Add('Deployed, and reported as succeeded, but their validators were not run. Each is counted as "deployed, but validation not performed" above, never as validated.')
        $lines.Add('')
        foreach ($phase in $validationExcluded) {
            $lines.Add("- **$($phase.Id)** ($($phase.Lab)) - $($phase.ValidationExcluded)")
        }
    }
    $lines.Add('')

    $lines.Add('## Excluded')
    $lines.Add('')
    if ($excluded.Count -eq 0) { $lines.Add('None.') }
    else {
        foreach ($phase in $excluded) {
            $lines.Add("- **$($phase.Id)** ($($phase.Lab)) - $($phase.Cause)")
        }
    }
    $lines.Add('')

    $lines.Add('## Teardown')
    $lines.Add('')
    if (@($Teardowns).Count -eq 0) { $lines.Add('Nothing was torn down.') }
    else {
        $lines.Add('Counted separately from the phases above and deliberately absent from the exit code: a lab that deployed cleanly and could not be removed is not a failed deployment.')
        $lines.Add('')
        foreach ($teardown in $Teardowns) {
            # 124 is the runner's timeout sentinel, and a bare 'exit 124' tells a reader nothing.
            # 'The delete is still running and we stopped waiting' and 'the delete failed' send
            # someone to different places - the first to a longer TimeoutMs, the second to Azure.
            $detail = if ($teardown.ExitCode -eq 124) { ' (timed out; the delete was still running when the limit killed it)' }
                      elseif ($teardown.ExitCode)     { " (exit $($teardown.ExitCode))" }
                      else                            { '' }
            $target = if ($teardown.Target) { "$($teardown.Lab): $($teardown.Target)" } else { $teardown.Lab }
            $lines.Add("- $target - $($teardown.Status)$detail")
        }
    }
    $lines.Add('')

    # Its own section. Teardown above says every delete reported success; this says the
    # subscription agrees. Issue #73 is explicit that a surviving vault is a failure rather than
    # expected residue, so this is the section that carries the evidence for the claim.
    $lines.Add('## Teardown assertions')
    $lines.Add('')
    if (@($Assertions).Count -eq 0) { $lines.Add('Not checked. A partial or skipped teardown asserts nothing, because a subscription that still holds the other labs on purpose is not one to assert empty.') }
    else {
        $failedAssertions = @($Assertions | Where-Object { -not $_.Ok })
        if ($failedAssertions.Count -eq 0) {
            $lines.Add("All $(@($Assertions).Count) passed: the subscription is as empty as the teardown claims.")
        }
        else {
            $lines.Add("**$($failedAssertions.Count) of $(@($Assertions).Count) FAILED.** Every delete above may have reported success; the subscription disagrees. This is not residue, and it is not expected.")
        }
        $lines.Add('')
        foreach ($assertion in $Assertions) {
            $mark = if ($assertion.Ok) { 'PASS' } else { '**FAIL**' }
            $lines.Add("- $mark - $($assertion.Name): $($assertion.Detail)")
        }
    }
    $lines.Add('')

    $lines.Add('## Left behind')
    $lines.Add('')
    if (@($LeftBehind).Count -eq 0) { $lines.Add('Nothing recorded as knowingly left behind.') }
    else {
        $lines.Add('Not failures - documented residue. Omitting these would claim a cleanliness the subscription does not have.')
        $lines.Add('')
        foreach ($residue in $LeftBehind) {
            $lines.Add("- **$($residue.Lab)**: $($residue.What) - $($residue.Why)")
        }
    }
    $lines.Add('')

    Set-Content -LiteralPath $Path -Value ($lines -join [Environment]::NewLine)
}

function Get-LabCycleFailureClass {
    <#
    .SYNOPSIS
        Decides whether a failed step is worth another attempt, and how long to wait first.

    .DESCRIPTION
        Without this, one transient throttle on a root phase cascades into every phase below it and
        a multi-hour run produces nothing usable. With too much of it, every real failure becomes
        three failures separated by backoff and a clear error takes minutes longer to report.

        So the list is short and names only failures where the platform is asking us to wait: HTTP
        429 and 503, SkuNotAvailable and AllocationFailed. Regional capacity errors are routine on
        this subscription - the entire B-series is capacity-blocked in Sweden Central, which is why
        lab 3.2 pins Standard_D2s_v3.

        NOT RETRYABLE, deliberately: a validator assertion failure, an authorization failure, a
        policy denial, a missing parameter file, a bicep compile error. None of them can come out
        differently on a second attempt.

        A TIMEOUT IS NEVER RETRYABLE, whatever its output happens to contain. A killed phase says
        nothing about whether another attempt would finish inside the same limit, and the fix for a
        phase that ran out of time is a longer limit rather than another 40 minutes spent learning
        the same thing.

        Matched against the step's captured output rather than against real throttling: a 429 is
        not reproducible on demand, so a test that waits for one is a test that sometimes does not
        run.

    .PARAMETER Text
        The failed step's captured output.

    .PARAMETER TimedOut
        The step was killed at its timeout rather than exiting on its own.

    .EXAMPLE
        Get-LabCycleFailureClass -Text $output

    .NOTES
        Project: SkyCraft
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowEmptyString()]
        [AllowNull()]
        [string]$Text,

        [Parameter()]
        [switch]$TimedOut
    )

    if ($TimedOut) {
        return [pscustomobject]@{ Retryable = $false; Reason = 'timed out; a longer TimeoutMs is the fix, not another attempt'; RetryAfterSeconds = $null }
    }
    if ([string]::IsNullOrWhiteSpace($Text)) {
        return [pscustomobject]@{ Retryable = $false; Reason = 'no output to classify'; RetryAfterSeconds = $null }
    }

    # Ordered, so the reason reported is the most specific match rather than whichever pattern
    # happened to be tested first. The bare status codes are last and are bounded by digit
    # guards, so a resource named 'sku429' or an id containing 503 does not read as a throttle.
    $signals = [ordered]@{
        'SkuNotAvailable'  = 'SkuNotAvailable'
        'AllocationFailed' = 'AllocationFailed'
        'TooManyRequests'  = 'TooManyRequests'
        '429'              = '(?<![\w.])429(?![\w.])'
        '503'              = '(?<![\w.])503(?![\w.])'
    }

    foreach ($name in $signals.Keys) {
        if ($Text -notmatch $signals[$name]) { continue }

        # Azure says how long to wait when it knows. Ignoring that either retries too early and
        # earns another 429, or waits far longer than was asked.
        $retryAfter = $null
        $match = [regex]::Match($Text, '(?im)^\s*Retry-After:\s*(\d+)')
        if ($match.Success) { $retryAfter = [int]$match.Groups[1].Value }

        return [pscustomobject]@{
            Retryable         = $true
            Reason            = "$name - the platform is asking us to wait rather than reporting the deployment wrong"
            RetryAfterSeconds = $retryAfter
        }
    }

    [pscustomobject]@{ Retryable = $false; Reason = 'not a transient platform failure'; RetryAfterSeconds = $null }
}

function ConvertTo-CheckResult {
    # Internal. One shape for every preflight answer, so the engine and the report can treat them
    # uniformly rather than each check inventing its own.
    #
    # Severity is separate from Ok on purpose. Ok answers 'may the run proceed'; Severity answers
    # 'is there something the operator should see'. A check that passes with a warning has both, and
    # collapsing them would force a reportable condition to choose between being fatal and silent.
    param([string]$Name, [bool]$Ok, [string]$Detail, [ValidateSet('Info', 'Warning')][string]$Severity = 'Info')
    @{ Name = $Name; Ok = $Ok; Detail = $Detail; Severity = $Severity }
}

# Leftover kinds whose reserved name has been measured to be recoverable rather than blocking.
#
# LogAnalytics is here because it was measured, on 2026-08-04 against the live subscription: the
# workspace was created, deleted into its 14-day soft-delete window, confirmed in the deleted list,
# then created again under the same name in the same resource group - and Azure recovered it,
# provisioning state Succeeded. Lab 5.1's teardown reserves that name on every clean run, so a hard
# stop here would mean a successful run prevents the next one from starting.
#
# KeyVault and RecoveryServicesVault are deliberately absent. Lab 3.2's vault sets
# enablePurgeProtection, and a vault that cannot be purged plausibly cannot have its name reused -
# but that is untested, and neither kind may inherit a result measured for a different one. Add a
# kind here only after measuring it the same way.
$script:RecoverableLeftoverKind = @('LogAnalytics')

# The action every phase needs. Both New-AzSubscriptionDeployment and New-AzResourceGroupDeployment
# require it, and all 16 deploy scripts go through one or the other, so an identity without it
# cannot run a single phase.
$script:RequiredDeployAction = 'Microsoft.Resources/deployments/write'

function Test-LabCycleActionAllowed {
    <#
    .SYNOPSIS
        Decides whether a set of Azure RBAC permission entries allows one action.

    .DESCRIPTION
        Azure RBAC grants an action when some entry's Actions matches it and that same entry's
        NotActions does not. Only '*' is a wildcard, and it spans '/' - '*/write' matches
        'Microsoft.Resources/deployments/write', which a segment-by-segment matcher would reject.
        Matching is case-insensitive: role definitions carry 'Microsoft.Authorization/*/Write' in
        one place and lowercase elsewhere, and a case-sensitive comparison would miss a NotActions
        entry - failing open, which is the wrong direction for a permission check to fail.

        Separate from the preflight check so the matcher can be tested on its own rather than only
        through seven other checks.

    .PARAMETER Permissions
        Entries as the Microsoft.Authorization/permissions API returns them: objects carrying
        actions/notActions, or the PowerShell-cased Actions/NotActions.

    .PARAMETER Action
        The action to test, e.g. 'Microsoft.Resources/deployments/write'.

    .EXAMPLE
        Test-LabCycleActionAllowed -Permissions $p -Action 'Microsoft.Resources/deployments/write'

    .NOTES
        Project: SkyCraft
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Action', Justification = 'False positive: read inside the $matchesAny scriptblock, which PSSA cannot correlate with the param block.')]
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowEmptyCollection()]
        $Permissions = @(),

        [Parameter(Mandatory)]
        [string]$Action
    )

    # '*' is the only wildcard, and it matches any run of characters including '/'.
    $toRegex = {
        param($Pattern)
        "^$([regex]::Escape($Pattern).Replace('\*', '.*'))$"
    }

    $matchesAny = {
        param($Patterns)
        foreach ($pattern in @($Patterns)) {
            if ([string]::IsNullOrWhiteSpace($pattern)) { continue }
            if ($Action -match (& $toRegex $pattern)) { return $true }
        }
        $false
    }

    foreach ($entry in @($Permissions)) {
        if (-not $entry) { continue }
        $actions    = if ($null -ne $entry.actions)    { $entry.actions }    else { $entry.Actions }
        $notActions = if ($null -ne $entry.notActions) { $entry.notActions } else { $entry.NotActions }

        if ((& $matchesAny $actions) -and -not (& $matchesAny $notActions)) { return $true }
    }

    $false
}

function Test-LabCycleSubscription {
    <#
    .SYNOPSIS
        Checks that the Azure context holds the subscription this run was told to use.

    .DESCRIPTION
        Compares ids, never names. On 2026-08-02 an Azure context changed identity mid-session on
        this machine and a cleanup query answered 'nothing found' - correctly, against an unrelated
        production subscription - one line before a -Force delete. Two subscriptions can share a
        display name; only the id identifies one.

        Separate from the rest of preflight because the engine re-runs this between phases. A run
        measured in hours has far more exposure to that drift than one session did.

    .PARAMETER SubscriptionId
        The subscription the run is allowed to touch.

    .PARAMETER ContextProbe
        Returns the current Azure context. Injectable so the tests stay offline.

    .NOTES
        Project: SkyCraft
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$SubscriptionId,

        [Parameter()]
        [scriptblock]$ContextProbe = { Get-AzContext }
    )

    $context = & $ContextProbe
    if (-not $context -or -not $context.Subscription) {
        return ConvertTo-CheckResult -Name 'subscription' -Ok $false -Detail 'No Azure context. Run Connect-AzAccount first; the engine will not authenticate on your behalf.'
    }

    $actualId = $context.Subscription.Id
    if ($actualId -ne $SubscriptionId) {
        return ConvertTo-CheckResult -Name 'subscription' -Ok $false -Detail "Context is on subscription $actualId ('$($context.Subscription.Name)'), but this run was told to use $SubscriptionId. Refusing to touch a subscription that was not asked for."
    }

    ConvertTo-CheckResult -Name 'subscription' -Ok $true -Detail "$actualId ('$($context.Subscription.Name)')"
}

function Get-LabCycleLockOwner {
    <#
    .SYNOPSIS
        Returns the live process holding the run lock, or nothing.

    .DESCRIPTION
        A lock left behind by a crashed run must not block the next one forever, so the file alone
        is not the answer - the question is whether the process it names is still alive. Returns
        nothing for a missing file, an unreadable one, or a dead owner.

    .PARAMETER LockPath
        The lock file.

    .NOTES
        Project: SkyCraft
    #>
    [CmdletBinding()]
    param([Parameter()][string]$LockPath)

    if (-not $LockPath -or -not (Test-Path -LiteralPath $LockPath)) { return $null }

    try { $lock = Get-Content -Raw -LiteralPath $LockPath | ConvertFrom-Json }
    catch {
        # A corrupt lock names nobody, so it cannot be shown to be held. Treated as stale rather
        # than as a stop, because the alternative is a run blocked by an unparseable file.
        return $null
    }

    if (-not $lock.ProcessId) { return $null }
    if (-not (Get-Process -Id $lock.ProcessId -ErrorAction SilentlyContinue)) { return $null }

    [pscustomobject]@{ ProcessId = $lock.ProcessId; StartedAt = $lock.StartedAt }
}

function New-LabCycleLock {
    <#
    .SYNOPSIS
        Writes the run lock naming this process.

    .PARAMETER LockPath
        The lock file to write.

    .NOTES
        Project: SkyCraft
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)][string]$LockPath)

    if (-not $PSCmdlet.ShouldProcess($LockPath, 'write run lock')) { return }

    $directory = Split-Path -Parent $LockPath
    if ($directory -and -not (Test-Path -LiteralPath $directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }
    @{ ProcessId = $PID; StartedAt = (Get-Date).ToString('o') } | ConvertTo-Json | Set-Content -LiteralPath $LockPath
}

function Invoke-LabCycleCanary {
    <#
    .SYNOPSIS
        Proves Pester can still tell a pass from a failure.

    .DESCRIPTION
        On 2026-08-03 this machine's Pester.ps1 was overwritten mid-session. While broken,
        Invoke-Pester still discovered every test and reported them all as failed - loud, and
        therefore safe. The inverse is what this guards: a corrupt install quietly reporting passes
        would make every validator in the run agree the labs are fine, and nothing else in a run
        would notice.

        Asserts both directions, because only the second catches that inverse: a true assertion
        must pass, and a false one must throw.

        Runs in a child process. Invoking Pester from inside a Pester run shares module state with
        the run doing the testing, so an in-process canary would partly be testing the harness that
        is already loaded rather than the installation a phase would get.

    .NOTES
        Project: SkyCraft
    #>
    [CmdletBinding()]
    param()

    $canary = @'
$ErrorActionPreference = 'Stop'
Import-Module Pester -MinimumVersion 5.0.0
$container = New-PesterContainer -ScriptBlock {
    Describe 'canary' {
        It 'a true assertion passes' { 1 + 1 | Should -Be 2 }
        It 'a false assertion throws' { { 1 | Should -Be 2 } | Should -Throw }
    }
}
$result = Invoke-Pester -Container $container -PassThru -Output None
if ($result.PassedCount -eq 2 -and $result.FailedCount -eq 0) { exit 0 } else { exit 1 }
'@

    $canaryFile = Join-Path ([System.IO.Path]::GetTempPath()) "lab-cycle-canary-$([guid]::NewGuid().ToString('N')).ps1"
    try {
        Set-Content -LiteralPath $canaryFile -Value $canary
        & pwsh -NoProfile -File $canaryFile *> $null
        $LASTEXITCODE -eq 0
    }
    finally {
        Remove-Item -LiteralPath $canaryFile -Force -ErrorAction SilentlyContinue
    }
}

function Test-LabCyclePreflight {
    <#
    .SYNOPSIS
        Runs every check that must hold before a lab cycle starts. Each one is a hard stop.

    .DESCRIPTION
        Returns one result per check, in order, and stops at the first failure. A check may also
        pass with Severity 'Warning' - reportable but not fatal, which the leftovers check uses for
        a name that Azure has been measured to recover rather than refuse. Stopping matters as
        much as checking: the later checks assume the earlier ones held, and a leftover query run
        against a context pointed at the wrong subscription would ask the wrong subscription -
        whose answer, 'nothing found', is the exact reassuring lie this guard exists for.

        Every Azure-dependent step goes through an injectable probe, so these run in CI, which has
        neither the Az modules nor credentials.

        Order, and why each earns its place:
          1. subscription   the context holds the id the run was given - see Test-LabCycleSubscription
          2. deploy perm    the identity holding that context may actually deploy. Right
                            subscription and wrong identity passes every other check and then
                            fails an hour in, having already created partial resources
          3. tools on PATH  standalone bicep, because Az PowerShell compiles .bicep client-side by
                            shelling out to a bare 'bicep' and 'az bicep install' puts its copy
                            where only the CLI can see it; pwsh, because every phase is a pwsh
                            child; az, because the deploy scripts call az bicep build-params
          4. az bicep       and that the subcommand works, not merely that az exists
          5. ssh key        ~/.ssh/skycraft-dev.pub, which lab 3.2 requires
          6. run lock       no live process is already running a cycle
          7. leftovers      soft-deleted resources holding names this run needs. A reserved Log
                            Analytics name warns rather than stops: measured on 2026-08-04, Azure
                            recovers the workspace when the same name is redeployed to the same
                            resource group, and lab 5.1's teardown reserves that name on every
                            clean run - so stopping would make a good run block the next one
          8. pester canary  Pester can still tell a pass from a failure

    .PARAMETER SubscriptionId
        The subscription the run is allowed to touch.

    .PARAMETER Guards
        Soft-delete guards from the manifest: Kind, Name, ResourceGroup, Lab.

    .PARAMETER SshKeyPath
        The public key lab 3.2 requires. Defaults to ~/.ssh/skycraft-dev.pub.

    .PARAMETER LockPath
        Run-lock file holding the owning process id and start time.

    .PARAMETER ContextProbe
        Returns the Azure context.

    .PARAMETER CommandProbe
        Given a command name, returns something truthy when it is on PATH.

    .PARAMETER AzBicepProbe
        Returns true when az bicep works.

    .PARAMETER LeftoverProbe
        Given the guards, returns what is soft-deleted and in the way. Reported, never purged:
        purging is irreversible and an unattended orchestrator should not make that call.

    .PARAMETER PermissionProbe
        Given the subscription id, returns the caller's RBAC permission entries at that scope.
        Defaults to the Microsoft.Authorization/permissions API, which is read-only and answers
        for the caller itself - unlike Get-AzRoleAssignment, which lists what everyone holds and
        on 2026-08-04 showed an Owner assignment belonging to a different account than the one
        the context was actually using.

    .PARAMETER CanaryProbe
        Returns true when Pester can still assert.

    .EXAMPLE
        Test-LabCyclePreflight -SubscriptionId $id -Guards $manifest.SoftDeleteGuards

    .NOTES
        Project: SkyCraft
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'SubscriptionId', Justification = 'False positive: read inside the $checks scriptblocks, which PSSA cannot correlate with the param block.')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Guards', Justification = 'False positive: read inside the $checks scriptblocks, which PSSA cannot correlate with the param block.')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'SshKeyPath', Justification = 'False positive: read inside the $checks scriptblocks, which PSSA cannot correlate with the param block.')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'LockPath', Justification = 'False positive: read inside the $checks scriptblocks, which PSSA cannot correlate with the param block.')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'ContextProbe', Justification = 'False positive: read inside the $checks scriptblocks, which PSSA cannot correlate with the param block.')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'CommandProbe', Justification = 'False positive: read inside the $checks scriptblocks, which PSSA cannot correlate with the param block.')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'AzBicepProbe', Justification = 'False positive: read inside the $checks scriptblocks, which PSSA cannot correlate with the param block.')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'LeftoverProbe', Justification = 'False positive: read inside the $checks scriptblocks, which PSSA cannot correlate with the param block.')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'PermissionProbe', Justification = 'False positive: read inside the $checks scriptblocks, which PSSA cannot correlate with the param block.')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'CanaryProbe', Justification = 'False positive: read inside the $checks scriptblocks, which PSSA cannot correlate with the param block.')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$SubscriptionId,

        [Parameter()]
        [AllowEmptyCollection()]
        $Guards = @(),

        [Parameter()]
        [string]$SshKeyPath = (Join-Path $HOME '.ssh/skycraft-dev.pub'),

        [Parameter()]
        [string]$LockPath,

        [Parameter()]
        [scriptblock]$ContextProbe = { Get-AzContext },

        [Parameter()]
        [scriptblock]$CommandProbe = { param($Name) Get-Command $Name -ErrorAction SilentlyContinue },

        [Parameter()]
        [scriptblock]$AzBicepProbe = {
            & az bicep version *> $null
            $LASTEXITCODE -eq 0
        },

        [Parameter()]
        [scriptblock]$LeftoverProbe = {
            param($Guards)
            $found = @()
            foreach ($guard in $Guards) {
                if ($guard.Kind -eq 'KeyVault') {
                    $removed = @(Get-AzKeyVault -InRemovedState -ErrorAction SilentlyContinue |
                        Where-Object { $_.VaultName -eq $guard.Name })
                    foreach ($item in $removed) {
                        $protection = if ($item.EnablePurgeProtection) { 'ON - blocks redeployment until it expires' } else { 'off' }
                        $found += @{ Kind = 'KeyVault'; Name = $guard.Name; Detail = "soft-deleted in $($item.Location); purge protection $protection" }
                    }
                }
                else {
                    # A Log Analytics workspace and a Recovery Services Vault both keep their name
                    # reserved after deletion, so an existing one by that name blocks this run.
                    $existing = @(Get-AzResource -Name $guard.Name -ErrorAction SilentlyContinue)
                    foreach ($item in $existing) {
                        $found += @{ Kind = $guard.Kind; Name = $guard.Name; Detail = "already exists at $($item.ResourceId)" }
                    }
                }
            }
            $found
        },

        [Parameter()]
        [scriptblock]$PermissionProbe = {
            param($SubscriptionId)
            # Read-only, and authoritative: this returns what the CALLER may do at that scope,
            # collapsing every role assignment, group membership and inherited grant into one
            # answer. Get-AzRoleAssignment would not - on 2026-08-04 it showed an Owner assignment
            # on this subscription while the caller itself held only '*/read'.
            $response = Invoke-AzRestMethod -Method GET -Path "/subscriptions/$SubscriptionId/providers/Microsoft.Authorization/permissions?api-version=2022-04-01"
            if ($response.StatusCode -ne 200) {
                throw "Could not read permissions for subscription $SubscriptionId (HTTP $($response.StatusCode)): $($response.Content)"
            }
            ($response.Content | ConvertFrom-Json).value
        },

        [Parameter()]
        [scriptblock]$CanaryProbe = { Invoke-LabCycleCanary }
    )

    $results = [System.Collections.Generic.List[hashtable]]::new()

    # Each check is a scriptblock so the order is a list rather than control flow, and so the loop
    # can stop at the first failure without every check needing its own early return.
    $checks = @(
        { Test-LabCycleSubscription -SubscriptionId $SubscriptionId -ContextProbe $ContextProbe }

        {
            # Second, because it is the other half of 'am I who I need to be'. The subscription
            # check proves the context points at the right subscription; this proves the identity
            # holding that context can actually deploy into it. On 2026-08-04 the first passed and
            # the second would not have: same id, same tenant, a principal with '*/read'.
            $permissions = @(& $PermissionProbe $SubscriptionId)
            if (Test-LabCycleActionAllowed -Permissions $permissions -Action $script:RequiredDeployAction) {
                ConvertTo-CheckResult -Name 'deploy permission' -Ok $true -Detail "the context identity may $script:RequiredDeployAction"
            }
            else {
                $granted = @($permissions | ForEach-Object { $_.actions } | Where-Object { $_ }) -join ', '
                if (-not $granted) { $granted = '(none)' }
                ConvertTo-CheckResult -Name 'deploy permission' -Ok $false -Detail "the context identity cannot $script:RequiredDeployAction on this subscription; it holds: $granted. Right subscription, wrong identity - every other check passes and the first deployment fails an hour in, with partial resources already created. Connect-AzAccount as a principal with Contributor or Owner here."
            }
        }

        {
            $missing = @('bicep', 'pwsh', 'az') | Where-Object { -not (& $CommandProbe $_) }
            if ($missing) {
                $why = if ($missing -contains 'bicep') { " Standalone 'bicep' is not what 'az bicep install' provides: Az PowerShell compiles .bicep client-side through a bare bicep on PATH." } else { '' }
                ConvertTo-CheckResult -Name 'tools on PATH' -Ok $false -Detail "not found: $($missing -join ', ').$why"
            }
            else { ConvertTo-CheckResult -Name 'tools on PATH' -Ok $true -Detail 'bicep, pwsh, az' }
        }

        {
            if (& $AzBicepProbe) { ConvertTo-CheckResult -Name 'az bicep' -Ok $true -Detail 'az bicep works' }
            else { ConvertTo-CheckResult -Name 'az bicep' -Ok $false -Detail "'az bicep' does not work, and every deploy script compiles its parameter file with 'az bicep build-params'." }
        }

        {
            if (Test-Path -LiteralPath $SshKeyPath) { ConvertTo-CheckResult -Name 'ssh key' -Ok $true -Detail $SshKeyPath }
            else { ConvertTo-CheckResult -Name 'ssh key' -Ok $false -Detail "lab 3.2 requires a public key at $SshKeyPath" }
        }

        {
            $owner = Get-LabCycleLockOwner -LockPath $LockPath
            if ($owner) {
                ConvertTo-CheckResult -Name 'run lock' -Ok $false -Detail "a lab cycle is already running: process $($owner.ProcessId), started $($owner.StartedAt). Two runs against one subscription interleave deployments and corrupt the state file."
            }
            else { ConvertTo-CheckResult -Name 'run lock' -Ok $true -Detail 'no live run holds the lock' }
        }

        {
            $leftovers = @(& $LeftoverProbe $Guards)
            $blocking = @($leftovers | Where-Object { $_.Kind -notin $script:RecoverableLeftoverKind })
            $recoverable = @($leftovers | Where-Object { $_.Kind -in $script:RecoverableLeftoverKind })

            $describe = { param($Items) ($Items | ForEach-Object { "$($_.Kind) '$($_.Name)': $($_.Detail)" }) -join '; ' }

            if ($blocking.Count -gt 0) {
                # A recoverable leftover alongside a blocking one changes nothing about the blocker,
                # so both are named: hiding the warning here would make the stop harder to diagnose.
                $detail = "names this run needs are still taken: $(& $describe $blocking). Reported, not purged - purging is irreversible and is yours to decide."
                if ($recoverable.Count -gt 0) { $detail += " Also reserved, but recoverable: $(& $describe $recoverable)." }
                ConvertTo-CheckResult -Name 'leftovers' -Ok $false -Detail $detail
            }
            elseif ($recoverable.Count -gt 0) {
                ConvertTo-CheckResult -Name 'leftovers' -Ok $true -Severity 'Warning' -Detail "reserved but recoverable, so the run continues: $(& $describe $recoverable). Azure recovers a soft-deleted workspace when the same name is redeployed to the same resource group; the run will be slower, not blocked."
            }
            else { ConvertTo-CheckResult -Name 'leftovers' -Ok $true -Detail "$(@($Guards).Count) guarded name(s) clear" }
        }

        {
            if (& $CanaryProbe) { ConvertTo-CheckResult -Name 'pester canary' -Ok $true -Detail 'Pester can tell a pass from a failure' }
            else { ConvertTo-CheckResult -Name 'pester canary' -Ok $false -Detail 'the Pester canary did not pass, so no validator result in this run could be trusted' }
        }
    )

    foreach ($check in $checks) {
        $result = & $check
        $results.Add($result)
        if (-not $result.Ok) { break }
    }

    $results
}

function Write-LabCycleResultLine {
    <#
    .SYNOPSIS
        Appends one step result to the run's JSONL results file.

    .DESCRIPTION
        One JSON object per line, appended as each step finishes. Deliberately not a single JSON
        document written at the end: a run measured in hours that is killed at hour three would
        take every result with it, and the results that matter most are the ones from a run that
        did not finish.

        Separate from the state file, which answers 'what is left to do' and is rewritten in place
        after every step, and from the report, which is written once at the end for a person to
        read. This is the machine-readable history of what happened, in order, append-only.

        Line-delimited rather than an array so a partial file is still a valid input: every
        complete line parses on its own, and a run killed mid-write costs the last line rather than
        the file.

    .PARAMETER Path
        The .jsonl file to append to. Its directory is created if missing.

    .PARAMETER Record
        The object to write. Serialised compressed, so one record is one line.

    .EXAMPLE
        Write-LabCycleResultLine -Path ./tools/lab-cycle-logs/results.jsonl -Record @{ Id = '2.1'; Status = 'Succeeded' }

    .NOTES
        Project: SkyCraft
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        $Record
    )

    if (-not $PSCmdlet.ShouldProcess($Path, 'append lab cycle result')) { return }

    $directory = Split-Path -Parent $Path
    if ($directory -and -not (Test-Path -LiteralPath $directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }

    # -Compress is what keeps one record on one line; without it ConvertTo-Json pretty-prints and
    # the file stops being line-delimited JSON while still looking like JSON.
    $json = $Record | ConvertTo-Json -Depth 8 -Compress
    Add-Content -LiteralPath $Path -Value $json
}

function Compare-LabCycleVersion {
    <#
    .SYNOPSIS
        Answers whether an observed version is at least a required one.

    .DESCRIPTION
        Split out so the comparison can be tested against strings rather than against whatever
        happens to be installed on the machine running the tests, which is the one thing a version
        floor must not depend on.

        Tolerant of the shapes these tools actually report: az prints '2.86.0', Az PowerShell
        reports a four-part version, and both can carry a pre-release suffix. Everything from the
        first character that is neither a digit nor a dot is discarded before parsing, and a
        missing component counts as zero, so '7.5' satisfies a floor of '7.5.0'.

        Returns $false for anything unparseable rather than throwing. A caller that cannot read a
        version has not established that the floor is met, and treating 'unknown' as 'fine' is the
        direction a version gate must not fail in.

    .PARAMETER Observed
        The version string as the tool reported it.

    .PARAMETER Minimum
        The lowest acceptable version.

    .EXAMPLE
        Compare-LabCycleVersion -Observed '2.86.0' -Minimum '2.75.0'

    .NOTES
        Project: SkyCraft
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowEmptyString()]
        [AllowNull()]
        [string]$Observed,

        [Parameter(Mandatory)]
        [string]$Minimum
    )

    $normalise = {
        param($Text)
        if ([string]::IsNullOrWhiteSpace($Text)) { return $null }
        $match = [regex]::Match($Text, '\d+(\.\d+)*')
        if (-not $match.Success) { return $null }
        $parts = @($match.Value -split '\.' | ForEach-Object { [int]$_ })
        while ($parts.Count -lt 4) { $parts += 0 }
        [version]::new($parts[0], $parts[1], $parts[2], $parts[3])
    }

    $left  = & $normalise $Observed
    $right = & $normalise $Minimum
    if (-not $left -or -not $right) { return $false }

    $left -ge $right
}

function Test-LabCycleToolingFloor {
    <#
    .SYNOPSIS
        Checks that the installed az CLI and Az PowerShell are new enough to tear down a vault.

    .DESCRIPTION
        A hard prerequisite of teardown, not general hygiene, and it earns a check of its own
        because of what happens without it.

        Azure Backup permits deleting a Recovery Services Vault that holds only SOFT-DELETED
        items. The vault then enters a soft-deleted state itself, at no cost, and stops being an
        active ARM resource - which is why this repository's teardown is a single pass rather than
        a 14-day wait. Older tooling does not take that path: it insists on a completely empty
        vault, which cannot happen while soft delete is on, and the operator is left believing the
        vault is stuck. That belief was recorded in issue #73 as a permanent residual until the
        v0.8.0 cycle disproved it on az CLI 2.86.0 and Az PowerShell 14.0.0.

        Checked before anything is deleted rather than when the vault is reached. A teardown that
        removes fifteen labs and then fails on the sixteenth for a reason knowable at the start has
        wasted an hour and left the subscription half-torn-down.

        Both probes are injectable so the tests never depend on what is installed on the machine
        running them.

    .PARAMETER MinimumAzCli
        Lowest acceptable az CLI version.

    .PARAMETER MinimumAzPowerShell
        Lowest acceptable Az PowerShell version.

    .PARAMETER AzCliVersionProbe
        Returns the az CLI version string, or nothing when az is absent.

    .PARAMETER AzPowerShellVersionProbe
        Returns the Az PowerShell version string, or nothing when the module is absent.

    .EXAMPLE
        Test-LabCycleToolingFloor -MinimumAzCli '2.75.0' -MinimumAzPowerShell '7.5.0'

    .NOTES
        Project: SkyCraft
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$MinimumAzCli,

        [Parameter(Mandatory)]
        [string]$MinimumAzPowerShell,

        [Parameter()]
        [scriptblock]$AzCliVersionProbe = {
            $raw = & az version --output json 2>$null
            if ($LASTEXITCODE -ne 0 -or -not $raw) { return $null }
            ($raw | ConvertFrom-Json).'azure-cli'
        },

        [Parameter()]
        [scriptblock]$AzPowerShellVersionProbe = {
            $module = Get-Module -ListAvailable -Name Az -ErrorAction SilentlyContinue |
                Sort-Object Version -Descending |
                Select-Object -First 1
            # Az is a meta-module and a machine can carry the sub-modules without it. Az.Accounts
            # is installed by every one of them, so it is the version that is always readable.
            if (-not $module) {
                $module = Get-Module -ListAvailable -Name Az.Accounts -ErrorAction SilentlyContinue |
                    Sort-Object Version -Descending |
                    Select-Object -First 1
            }
            if ($module) { "$($module.Version)" } else { $null }
        }
    )

    $results = [System.Collections.Generic.List[hashtable]]::new()

    $why = "Teardown deletes a Recovery Services Vault that holds only soft-deleted items. Older tooling refuses that and demands an empty vault instead, which soft delete makes impossible - so the vault appears stuck for 14 days. Upgrade before running this, rather than discovering it after fifteen labs have already been removed."

    $azCli = & $AzCliVersionProbe
    if (Compare-LabCycleVersion -Observed $azCli -Minimum $MinimumAzCli) {
        $results.Add((ConvertTo-CheckResult -Name 'az CLI version' -Ok $true -Detail "$azCli (floor $MinimumAzCli)"))
    }
    else {
        $found = if ($azCli) { $azCli } else { 'not found or unreadable' }
        $results.Add((ConvertTo-CheckResult -Name 'az CLI version' -Ok $false -Detail "az CLI $found is below the required $MinimumAzCli. $why"))
    }

    $azPs = & $AzPowerShellVersionProbe
    if (Compare-LabCycleVersion -Observed $azPs -Minimum $MinimumAzPowerShell) {
        $results.Add((ConvertTo-CheckResult -Name 'Az PowerShell version' -Ok $true -Detail "$azPs (floor $MinimumAzPowerShell)"))
    }
    else {
        $found = if ($azPs) { $azPs } else { 'not found or unreadable' }
        $results.Add((ConvertTo-CheckResult -Name 'Az PowerShell version' -Ok $false -Detail "Az PowerShell $found is below the required $MinimumAzPowerShell. $why"))
    }

    $results
}

Export-ModuleMember -Function Get-PhaseOrder, Get-DependentPhase, Invoke-LabScriptProcess,
    Test-LabCycleSubscription, Test-LabCyclePreflight, Test-LabCycleActionAllowed, Invoke-LabCycleCanary,
    Get-LabCycleLockOwner, New-LabCycleLock, Get-LabCycleFailureClass, Write-LabCycleReport,
    Write-LabCycleResultLine, Compare-LabCycleVersion, Test-LabCycleToolingFloor
