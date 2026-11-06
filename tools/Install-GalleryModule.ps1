<#
.SYNOPSIS
    Installs a PowerShell Gallery module for the CI jobs, retrying when the Gallery fails for a moment.

.DESCRIPTION
    The Lint workflow installs PSScriptAnalyzer and Pester from the PowerShell Gallery. A single
    Install-Module call turned a short Gallery hiccup into a red check before any test ran, three
    times in two days (#440), each cured by re-running the failed job with no change.

    This script calls Install-Module up to -MaxAttempts times, waits -DelaySeconds times the attempt
    number between tries, and throws the last error when every try failed, so a real outage still
    fails the job and says why.

.PARAMETER Name
    The module to install.

.PARAMETER MinimumVersion
    Optional lower bound, passed to Install-Module.

.PARAMETER MaximumVersion
    Optional upper bound, passed to Install-Module.

.PARAMETER MaxAttempts
    How many times to try. Default 3.

.PARAMETER DelaySeconds
    Base wait between tries, multiplied by the number of the attempt that just failed. Default 15.

.EXAMPLE
    ./tools/Install-GalleryModule.ps1 -Name Pester -MinimumVersion 5.5 -MaximumVersion 5.99

.NOTES
    Project: SkyCraft
    Issue: #440
#>

#Requires -Version 7.0

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$Name,

    [string]$MinimumVersion,

    [string]$MaximumVersion,

    [ValidateRange(1, 10)]
    [int]$MaxAttempts = 3,

    [ValidateRange(0, 300)]
    [int]$DelaySeconds = 15
)

$ErrorActionPreference = 'Stop'

$install = @{ Name = $Name; Force = $true; Scope = 'CurrentUser'; ErrorAction = 'Stop' }
if ($MinimumVersion) { $install['MinimumVersion'] = $MinimumVersion }
if ($MaximumVersion) { $install['MaximumVersion'] = $MaximumVersion }

for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
    try {
        Install-Module @install
        return
    }
    catch {
        if ($attempt -ge $MaxAttempts) {
            throw "Install-Module $Name failed after $MaxAttempts attempt(s): $($_.Exception.Message)"
        }
        Write-Host "Install-Module $Name failed (attempt $attempt of $MaxAttempts): $($_.Exception.Message)"
        Start-Sleep -Seconds ($DelaySeconds * $attempt)
    }
}
