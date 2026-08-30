<#
.SYNOPSIS
    Runs a lab script and returns its real exit code.

.DESCRIPTION
    A lab script's `exit` is discarded when the script is launched with `pwsh -File`, because every
    lab script declares `#Requires -Modules` and that combination makes the process exit 0 whatever
    the script returned. `-Command "& script"` reports failure but not which failure: measured on
    PowerShell 7.6.3, a target exiting 0 gives 0 and a target exiting 8 gives 1, as does one that
    throws. Every non-zero code collapses to 1, so a validator that exits a count of failed
    assertions arrives as an undifferentiated 1.

    This shim is invoked with -File, which passes arguments natively instead of through a quoted
    string, and re-exits with the target's code. It declares no #Requires -Modules of its own -
    that is the entire reason it works, and tests/LabCycle.Tests.ps1 asserts both halves: that the
    shim stays free of a module requirement, and that a target exiting 7 arrives as 7.

    KNOWN GAP. The shim reports whatever $LASTEXITCODE holds when the target returns. A target that
    runs a failing native command and then returns without `exit` is therefore reported with that
    command's code, which may have nothing to do with its verdict - measured: a target running
    `cmd /c "exit 42"` and falling off the end is reported as 42. Nothing in this repository hits
    it, because every lab script ends in an explicit `exit` and
    tests/Exit-Code-Propagation.Tests.ps1 holds them to that, but a caller that runs arbitrary
    scripts through this shim cannot rely on it.

.PARAMETER TargetScript
    Absolute path to the lab script to run.

.PARAMETER ArgumentJson
    JSON object of named arguments to splat, e.g. '{"Environment":"prod"}'. Omit for none.

.EXAMPLE
    pwsh -NoProfile -File Invoke-LabScript.ps1 -TargetScript C:\...\Deploy-Bicep.ps1 -ArgumentJson '{"Environment":"prod"}'

.NOTES
    Project: SkyCraft
#>

#Requires -Version 7.0

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$TargetScript,

    [Parameter(Mandatory = $false)]
    [string]$ArgumentJson
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $TargetScript)) {
    Write-Host "[ERROR] Target script not found: $TargetScript" -ForegroundColor Red
    exit 127
}

$splat = @{}
if ($ArgumentJson) {
    try {
        $parsed = $ArgumentJson | ConvertFrom-Json -AsHashtable
        if ($parsed) { $splat = $parsed }
    }
    catch {
        Write-Host "[ERROR] Could not parse -ArgumentJson: $_" -ForegroundColor Red
        exit 126
    }
}

# A target that throws never reaches the exit below: $ErrorActionPreference = 'Stop' propagates the
# terminating error out of this script and pwsh exits 1 on its own. Measured, so that nothing here
# pretends to handle a case it does not reach.
& $TargetScript @splat
exit $LASTEXITCODE
