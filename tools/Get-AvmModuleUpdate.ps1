<#
.SYNOPSIS
    Lists every AVM module the repository pins next to the newest version br/public publishes.

.DESCRIPTION
    Dependabot does not read Bicep registry references, so the 'br/public:avm/res/...:x.y.z'
    pins in the lab templates have no update signal of their own (issue #82). This script
    is that signal. It scans every *.bicep file for AVM module declarations, asks
    mcr.microsoft.com - the registry behind the br/public alias - for each module's tag
    list, and prints one row per module:

      Module     the AVM module path
      Pinned     the version the templates use
      Latest     the newest x.y.z tag the registry lists
      Status     Current, Behind, Unlisted or Unknown
      Files      the templates that reference it

    Status decides the exit code. Behind is a review item, not a defect, so by default
    it exits 0 and only -FailOnBehind turns it into a failure - the quarterly workflow
    (.github/workflows/avm-module-update.yml) passes that switch so a red run is the
    nudge to review. Unlisted always exits 1: a pin the registry does not publish is a
    template that cannot compile, whatever the switches say. Unknown means the tag list
    could not be read; it is reported, never counted as a failure, so an offline run
    still prints what it can.

    The scan, the registry call and the classification live in tools/AvmRegistry.psm1,
    where tests/Avm-Module-Update.Tests.ps1 exercises them offline.

    To upgrade a module: update every reference and the catalogue in
    docs/bicep-standards.md section 4.4 in the same PR, as that section requires.
    tests/Avm-Module-Pinning.Tests.ps1 fails the PR if any reference is left behind.

.PARAMETER RepoRoot
    Repository root to scan. Defaults to the parent of the 'tools' folder holding this script.

.PARAMETER Format
    'Table' (default) prints a console table. 'Markdown' prints a Markdown table, which the
    workflow appends to its job summary.

.PARAMETER FailOnBehind
    Exit 1 when any module has a newer version published.

.PARAMETER TagListProvider
    Test seam: a script block that takes a module path and returns its raw tag names.
    Leave unset to query the real registry.

.EXAMPLE
    .\tools\Get-AvmModuleUpdate.ps1

    Prints the pins-vs-latest table for the whole repository and exits 0 unless a pin
    is unlisted.

.EXAMPLE
    .\tools\Get-AvmModuleUpdate.ps1 -FailOnBehind

    The quarterly review: exits 1 when any module could be upgraded.

.EXAMPLE
    .\tools\Get-AvmModuleUpdate.ps1 -Format Markdown >> $env:GITHUB_STEP_SUMMARY

    Appends the table to a GitHub Actions job summary.

.NOTES
    Project: SkyCraft
    Date: 2026-09-19

    This script only reads files and sends anonymous GET requests to mcr.microsoft.com.
    It never authenticates to Azure and never changes a template.
#>

#Requires -Version 7.0

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$RepoRoot = (Split-Path -Parent $PSScriptRoot),

    [Parameter(Mandatory = $false)]
    [ValidateSet('Table', 'Markdown')]
    [string]$Format = 'Table',

    [Parameter(Mandatory = $false)]
    [switch]$FailOnBehind,

    [Parameter(Mandatory = $false)]
    [scriptblock]$TagListProvider
)

$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'AvmRegistry.psm1') -Force

$references = @(Get-AvmModuleReference -RepoRoot $RepoRoot)
if ($references.Count -eq 0) {
    Write-Host "[ERROR] No 'br/public:avm/...' module declaration found under $RepoRoot."
    $Host.SetShouldExit(1)
    exit 1
}

$compareArguments = @{ Reference = $references }
if ($TagListProvider) { $compareArguments['TagListProvider'] = $TagListProvider }

$results = @(Compare-AvmModulePin @compareArguments)

switch ($Format) {
    'Markdown' {
        Write-Output '| Module | Pinned | Latest | Status | Files |'
        Write-Output '|---|---|---|---|---|'
        foreach ($r in $results) {
            $latest = if ($r.Latest) { $r.Latest } else { '-' }
            Write-Output ('| `{0}` | {1} | {2} | {3} | {4} |' -f $r.Module, $r.Pinned, $latest, $r.Status, ($r.Files -join '<br>'))
        }
    }
    'Table' {
        $results |
            Select-Object Module, Pinned, Latest, Status, @{ Name = 'Files'; Expression = { $_.Files -join ', ' } } |
            Format-Table -AutoSize |
            Out-String -Width 220 |
            Write-Host
    }
}

$behind   = @($results | Where-Object Status -eq 'Behind')
$unlisted = @($results | Where-Object Status -eq 'Unlisted')
$unknown  = @($results | Where-Object Status -eq 'Unknown')

foreach ($r in $unknown) {
    Write-Warning "$($r.Module): tag list not read - $($r.Error)"
}

Write-Host ("Modules: {0}  Current: {1}  Behind: {2}  Unlisted: {3}  Unknown: {4}" -f
    $results.Count, @($results | Where-Object Status -eq 'Current').Count, $behind.Count, $unlisted.Count, $unknown.Count)

if ($unlisted.Count -gt 0) {
    Write-Host "[ERROR] $($unlisted.Count) pin(s) are not published on br/public: $($unlisted.Module -join ', ')"
    $Host.SetShouldExit(1)
    exit 1
}

if ($FailOnBehind -and $behind.Count -gt 0) {
    Write-Host "[REVIEW] $($behind.Count) module(s) have a newer version: $(($behind | ForEach-Object { "$($_.Module) $($_.Pinned) -> $($_.Latest)" }) -join '; ')"
    $Host.SetShouldExit(1)
    exit 1
}

# A plain exit 0 so a caller's $LASTEXITCODE is set by this script, not by whatever
# native command ran before it.
exit 0
