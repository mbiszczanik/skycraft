<#
.SYNOPSIS
    Shared helpers for the lab scripts. Today: Exit-Lab, which ends a lab script with the right
    exit code without closing the learner's PowerShell session.

.DESCRIPTION
    Every lab script serves two callers at once (issue #301):

      - the learner, who runs it at an interactive prompt (`.\scripts\Test-Lab.ps1`) on their own
        machine or in Cloud Shell, and keeps working in that session afterwards;
      - the automated callers, which start it as a process: tools/Invoke-LabCycle.ps1 through
        tools/Invoke-LabScript.ps1, CI, or anyone running `pwsh -File <script>`.

    PowerShell 7 drops the exit code of a script run as `pwsh -File` when the script declares
    `#Requires -Modules` for a module it has to auto-import - every Az.* module qualifies - so the
    process reports 0 for a failed run (issue #104). `$Host.SetShouldExit(<code>)` carries the code
    out, but it asks the host to end the whole process, not just the script: called from a script
    the learner ran at the prompt, it closes their PowerShell window, even with code 0 (issue #257).

    Exit-Lab settles both. It exits 1 when the failure count is above zero and 0 otherwise, and it
    calls `$Host.SetShouldExit` only when the calling script is the process entry point:

      - the process was started with `-File` (or a script path in its place) and without
        `-NoExit`, read from [Environment]::GetCommandLineArgs(); and
      - the outermost frame of the call stack is the script that called Exit-Lab, so the script
        was not called by another script (the lab cycle's launcher shim), by a typed command line
        (an interactive prompt, `-Command`) or by a test runner.

    In every other case it is a plain `exit`, which ends the script, sets $LASTEXITCODE for the
    caller and leaves the session open. A plain `exit` already reaches the caller in all of those
    cases: under `-Command` the process takes $LASTEXITCODE, and the launcher shim re-exits with it.

    Never `exit $failCount`: an exit code is one byte on Linux, so 256 failures would read as 0.

    `exit` inside a module function ends the script that called the function, not just the
    function, and sets $LASTEXITCODE - measured on PowerShell 7.6. So a lab script ends with
    `Exit-Lab -FailureCount $failCount` where it used to end with `exit`.

    Import it from a lab script by a path relative to the script, which holds in any clone of the
    repository, Cloud Shell included:

        Import-Module (Join-Path $PSScriptRoot '../../../tools/LabCommon.psm1') -Force -Verbose:$false

    The rest of #301 (Invoke-LabCheck, Get-LabResourceOrFail, Assert-LabSubscription) is not here
    yet. tests/Exit-Code-Propagation.Tests.ps1 requires every lab script to end through Exit-Lab
    and proves both callers with real pwsh processes.

.EXAMPLE
    Import-Module (Join-Path $PSScriptRoot '../../../tools/LabCommon.psm1') -Force -Verbose:$false
    Exit-Lab -FailureCount $failCount

.NOTES
    Project: SkyCraft
    Issues: #257, #301
#>

#Requires -Version 7.0

$ErrorActionPreference = 'Stop'

function Test-LabProcessEntryPoint {
    <#
    .SYNOPSIS
        Tells whether a script is the entry point of a `pwsh -File` process that ends with it.

    .DESCRIPTION
        True only when both hold:

          - the command line starts the process with -File (any prefix of it, with -, -- or /),
            or with a bare .ps1 path in its place, and carries no -NoExit before it. Arguments
            after the script path belong to the script and are not read. -Command and
            -EncodedCommand make it false: the process then runs typed text, not the script.
          - the outermost frame of the call stack is the calling script itself.

        A pure function of its inputs so the suite can test every shape of command line without
        starting a process for each.

    .PARAMETER CommandLineArgs
        The process command line, as [Environment]::GetCommandLineArgs() returns it: element 0 is
        the executable and is skipped.

    .PARAMETER OutermostScript
        The ScriptName of the outermost call-stack frame; empty for a typed command line.

    .PARAMETER CallerScript
        The path of the script that called Exit-Lab.

    .NOTES
        Project: SkyCraft
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter()]
        [AllowEmptyCollection()]
        [string[]]$CommandLineArgs = @(),

        [Parameter()]
        [AllowEmptyString()]
        [string]$OutermostScript = '',

        [Parameter()]
        [AllowEmptyString()]
        [string]$CallerScript = ''
    )

    if (-not $CallerScript -or -not $OutermostScript) { return $false }

    $comparison = if ($IsWindows) { [System.StringComparison]::OrdinalIgnoreCase } else { [System.StringComparison]::Ordinal }
    if (-not [string]::Equals($OutermostScript, $CallerScript, $comparison)) { return $false }

    $fileMode = $false
    $noExit   = $false
    foreach ($argument in @($CommandLineArgs | Select-Object -Skip 1)) {
        if ($argument -match '^(--|-|/)(?<name>[A-Za-z]+)(:.*)?$') {
            $name = $Matches['name'].ToLowerInvariant()
            if ('file'.StartsWith($name)) { $fileMode = $true; break }
            if ($name.Length -ge 3 -and 'noexit'.StartsWith($name)) { $noExit = $true; continue }
            if ('command'.StartsWith($name) -or $name -in 'e', 'ec' -or
                ($name.Length -ge 2 -and 'encodedcommand'.StartsWith($name))) {
                return $false
            }
            continue
        }
        # A bare argument is a switch's value (-ExecutionPolicy Bypass) or, when it names a
        # script, the script pwsh runs as if after -File.
        if ($argument -match '\.ps1$') { $fileMode = $true; break }
    }

    return ($fileMode -and -not $noExit)
}

function Exit-Lab {
    <#
    .SYNOPSIS
        Ends the calling lab script: exit 1 when anything failed, 0 otherwise.

    .DESCRIPTION
        Exits 1 when -FailureCount is above zero and 0 when it is zero. Calls
        $Host.SetShouldExit with the same code only when the calling script is the entry point of
        a `pwsh -File` process (see Test-LabProcessEntryPoint), where `#Requires -Modules` would
        otherwise drop the code (#104). At an interactive prompt, under -Command and when another
        script called the lab script, it is a plain `exit`: the session stays open and
        $LASTEXITCODE holds the code (#257).

        Call it from the lab script itself or from a function defined in it, not from a file the
        script dot-sources: the entry-point check compares the caller's file with the script the
        process started.

    .PARAMETER FailureCount
        How many checks, steps or preconditions failed. Above zero exits 1, zero exits 0. The count
        is never the exit code itself, which would wrap at 256.

    .EXAMPLE
        Exit-Lab -FailureCount $failCount

    .EXAMPLE
        Write-Host "Not logged in." -ForegroundColor Red; Exit-Lab -FailureCount 1

    .NOTES
        Project: SkyCraft
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateRange(0, [int]::MaxValue)]
        [int]$FailureCount
    )

    $code = if ($FailureCount -gt 0) { 1 } else { 0 }

    $stack     = @(Get-PSCallStack)
    $outermost = if ($stack.Count -gt 0) { [string]$stack[-1].ScriptName } else { '' }

    $entryPoint = Test-LabProcessEntryPoint `
        -CommandLineArgs ([Environment]::GetCommandLineArgs()) `
        -OutermostScript $outermost `
        -CallerScript ([string]$MyInvocation.PSCommandPath)

    if ($entryPoint) {
        $Host.SetShouldExit($code)
    }

    exit $code
}

Export-ModuleMember -Function Exit-Lab
