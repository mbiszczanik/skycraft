<#
.SYNOPSIS
    Offline dry-run gate: runs every CI check that does not need Azure authentication.

.DESCRIPTION
    Invoke-DryRun.ps1 is the local pre-push gate for SkyCraft. It mirrors the parts of
    the Lint workflow (.github/workflows/lint.yml) that a developer machine can run
    without 'az login' and without any deployed Azure resources:

      Parse       Every *.ps1 / *.psm1 / *.psd1 is parsed with the PowerShell parser.
                  A syntax error is invisible to PSScriptAnalyzer, so this runs first.
      Analyzer    Invoke-ScriptAnalyzer over the repository with PSScriptAnalyzerSettings.psd1.
                  Only 'Error' severity fails the gate; warnings are counted and listed.
      Bicep       'az bicep build' over every Bicep entry point. Files under a 'modules'
                  folder are skipped - their callers compile them transitively.
      BicepParams 'az bicep build-params' over every *.bicepparam file.

    Every selected check runs to completion even when an earlier one fails, so a single
    run reports every problem instead of only the first. The script prints a consolidated
    summary and exits non-zero if any selected check failed.

    Checks that need a live subscription are deliberately out of scope: 'az deployment ...
    what-if', 'Test-Lab.ps1' and 'Remove-LabResource.ps1' all require 'az login' plus
    existing resources. See docs/dry-run-harness.md for per-lab copy-paste commands.

.PARAMETER RepoRoot
    Repository root to scan. Defaults to the parent of the 'tools' folder holding this script.

.PARAMETER Check
    Which checks to run. Defaults to all four. Use it to skip a check whose tooling is not
    installed locally, for example '-Check Parse,Analyzer' on a machine without the Azure CLI.
    Checks that are not selected are reported as SKIPPED in the summary, so a partial run
    can never be mistaken for a full one.

    'pwsh -File' cannot pass an array argument - it hands the whole comma-separated value
    over as one string and validation rejects it. Run the script directly, or use
    'pwsh -Command'. The default (no arguments) works with '-File'.

.PARAMETER ExcludeDirectory
    Directory names skipped during file discovery, at any depth. Defaults to the generated
    and scratch folders that .gitignore already excludes.

.EXAMPLE
    .\tools\Invoke-DryRun.ps1

    Runs all four checks over the whole repository and exits non-zero if any of them failed.

.EXAMPLE
    .\tools\Invoke-DryRun.ps1 -Check Parse,Analyzer

    Runs only the PowerShell checks - useful on a machine without the Azure CLI installed.

.EXAMPLE
    .\tools\Invoke-DryRun.ps1 -Check Bicep,BicepParams -Verbose

    Compiles the Bicep templates and parameter files only, echoing each file as it is built.

.NOTES
    Project: SkyCraft
    Date: 2026-08-30

    This script never authenticates to Azure and never deploys anything. It only reads
    files and shells out to 'az bicep', which is a purely local compiler.
#>

#Requires -Version 7.0

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$RepoRoot = (Split-Path -Parent $PSScriptRoot),

    [Parameter(Mandatory = $false)]
    [ValidateSet('Parse', 'Analyzer', 'Bicep', 'BicepParams')]
    [string[]]$Check = @('Parse', 'Analyzer', 'Bicep', 'BicepParams'),

    [Parameter(Mandatory = $false)]
    [string[]]$ExcludeDirectory = @('.git', '.worktrees', 'lab-outputs', 'node_modules', 'scratch', 'temp', 'test-results')
)

$ErrorActionPreference = 'Stop'

# 'az' reports failure through $LASTEXITCODE. Without this, PowerShell 7.4+ turns a
# non-zero native exit into a terminating error and aborts the loop that is collecting
# the very failures this gate exists to report.
$PSNativeCommandUseErrorActionPreference = $false

#region Helpers

function Test-DryRunExcludedPath {
    <#
    .SYNOPSIS
        Returns $true when any directory segment of $Path below $Root is excluded.

    .DESCRIPTION
        Used both to prune file discovery and to drop PSScriptAnalyzer findings that come
        from generated or scratch folders that are not part of the repository content.

    .NOTES
        Project: SkyCraft
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Root,

        [Parameter(Mandatory = $false)]
        [string[]]$ExcludeName = @()
    )

    if ($ExcludeName.Count -eq 0) { return $false }

    $parent = Split-Path -Parent $Path
    if (-not $parent.StartsWith($Root, [StringComparison]::OrdinalIgnoreCase)) { return $false }

    $relative = $parent.Substring($Root.Length).Replace('\', '/').Trim('/')
    if (-not $relative) { return $false }

    foreach ($segment in $relative -split '/') {
        if ($segment -in $ExcludeName) { return $true }
    }

    return $false
}

function Get-DryRunFile {
    <#
    .SYNOPSIS
        Returns repository files with the requested extensions, skipping excluded directories.

    .DESCRIPTION
        Enumerates $Root without descending into any top-level directory whose name appears
        in $ExcludeName, which keeps the .git object store out of the scan, then drops any
        remaining file that sits under an excluded directory at a deeper level.

    .NOTES
        Project: SkyCraft
    #>
    [CmdletBinding()]
    [OutputType([System.IO.FileInfo])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Root,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string[]]$Extension,

        [Parameter(Mandatory = $false)]
        [string[]]$ExcludeName = @()
    )

    $found = [System.Collections.Generic.List[System.IO.FileInfo]]::new()

    foreach ($entry in Get-ChildItem -LiteralPath $Root -Force) {
        if ($entry.PSIsContainer) {
            if ($entry.Name -in $ExcludeName) { continue }
            foreach ($file in Get-ChildItem -LiteralPath $entry.FullName -Recurse -File -Force) {
                $found.Add($file)
            }
        }
        else {
            $found.Add($entry)
        }
    }

    $found |
        Where-Object { $_.Extension -in $Extension } |
        Where-Object { -not (Test-DryRunExcludedPath -Path $_.FullName -Root $Root -ExcludeName $ExcludeName) } |
        Sort-Object FullName
}

function Get-DryRunRelativePath {
    <#
    .SYNOPSIS
        Renders a full path relative to the repository root, with forward slashes.

    .DESCRIPTION
        Keeps console output identical on the Windows dev box and on a Linux runner, so a
        local failure line can be compared with the CI annotation for the same file.

    .NOTES
        Project: SkyCraft
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Root
    )

    if ($Path.StartsWith($Root, [StringComparison]::OrdinalIgnoreCase)) {
        return $Path.Substring($Root.Length).TrimStart('\', '/').Replace('\', '/')
    }

    return $Path.Replace('\', '/')
}

function New-DryRunResult {
    <#
    .SYNOPSIS
        Builds one row of the consolidated dry-run summary.

    .DESCRIPTION
        Status is 'Passed', 'Failed' or 'Skipped'. Failure holds the human-readable lines
        printed under the summary, and Note explains a skip or carries the warning count.

    .NOTES
        Project: SkyCraft
    #>
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Builds an in-memory summary row; changes no system state, so -WhatIf would be meaningless.')]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [ValidateSet('Passed', 'Failed', 'Skipped')]
        [string]$Status,

        [Parameter(Mandatory = $false)]
        [int]$ItemCount = 0,

        [Parameter(Mandatory = $false)]
        [AllowEmptyCollection()]
        [string[]]$Failure = @(),

        [Parameter(Mandatory = $false)]
        [timespan]$Duration = [timespan]::Zero,

        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string]$Note = ''
    )

    [pscustomobject]@{
        Name      = $Name
        Status    = $Status
        ItemCount = $ItemCount
        Failure   = $Failure
        Duration  = $Duration
        Note      = $Note
    }
}

function Write-DryRunHeader {
    <#
    .SYNOPSIS
        Prints the cyan section header that introduces a check.

    .DESCRIPTION
        Follows the SkyCraft console colour scheme (docs/powershell-standards.md, Section 3).

    .NOTES
        Project: SkyCraft
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Title
    )

    Write-Host ''
    Write-Host "=== $Title ===" -ForegroundColor Cyan
}

function Invoke-DryRunBicepBuild {
    <#
    .SYNOPSIS
        Compiles a set of Bicep or .bicepparam files with the Azure CLI and returns the failures.

    .DESCRIPTION
        Shells out to 'az bicep build' / 'az bicep build-params' once per file, writing the
        compiled JSON to a throwaway file.

        The compiled JSON deliberately goes to --outfile rather than --stdout: on a Windows
        console that is not UTF-8, 'az bicep build --stdout' dies with a UnicodeEncodeError
        as soon as a template pulls in an AVM module whose metadata contains a non-ANSI
        character. Writing to a file bypasses the console encoding entirely. Do not
        "simplify" this back to --stdout.

    .NOTES
        Project: SkyCraft
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [System.IO.FileInfo[]]$File,

        [Parameter(Mandatory = $true)]
        [ValidateSet('build', 'build-params')]
        [string]$Command,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$OutputDirectory,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Root
    )

    $failures = [System.Collections.Generic.List[string]]::new()
    $index = 0

    foreach ($item in $File) {
        $index++
        $relative = Get-DryRunRelativePath -Path $item.FullName -Root $Root
        Write-Host ('  [{0,3}/{1}] {2}' -f $index, $File.Count, $relative) -ForegroundColor Gray

        $outFile = Join-Path $OutputDirectory ('{0:d3}.json' -f $index)
        $output = & az bicep $Command --file $item.FullName --outfile $outFile 2>&1

        if ($LASTEXITCODE -ne 0) {
            $failures.Add("${relative}: az bicep $Command failed (exit $LASTEXITCODE)")
            $detail = ($output | Out-String).Trim()
            if ($detail) {
                foreach ($line in ($detail -split '\r?\n')) {
                    if ($line.Trim()) { $failures.Add("    $($line.Trim())") }
                }
            }
        }
    }

    return $failures.ToArray()
}

#endregion Helpers

# Get-Item, not Resolve-Path: it expands 8.3 short components ('MBISZC~1') to the long form
# that Get-ChildItem hands back, so the prefix comparison in Get-DryRunRelativePath matches
# and failures are reported as repo-relative paths rather than absolute ones.
$RepoRoot = (Get-Item -LiteralPath $RepoRoot -Force).FullName.TrimEnd('\', '/')

Write-Host '=== SkyCraft offline dry run ===' -ForegroundColor Cyan
Write-Host "Repository : $RepoRoot" -ForegroundColor Gray
Write-Host "Checks     : $($Check -join ', ')" -ForegroundColor Gray
Write-Host 'This gate never authenticates to Azure and never deploys anything.' -ForegroundColor Gray

$allChecks = @('Parse', 'Analyzer', 'Bicep', 'BicepParams')
$results = [System.Collections.Generic.List[pscustomobject]]::new()
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('skycraft-dryrun-' + [guid]::NewGuid().ToString('n'))

try {
    New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null

    foreach ($name in $allChecks) {

        if ($name -notin $Check) {
            $results.Add((New-DryRunResult -Name $name -Status 'Skipped' -Note 'not selected'))
            continue
        }

        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        $failures = [System.Collections.Generic.List[string]]::new()
        $itemCount = 0
        $note = ''

        switch ($name) {

            'Parse' {
                Write-DryRunHeader -Title 'Check 1/4: PowerShell parse'

                $psFiles = @(Get-DryRunFile -Root $RepoRoot -Extension '.ps1', '.psm1', '.psd1' -ExcludeName $ExcludeDirectory)
                $itemCount = $psFiles.Count
                Write-Host "Parsing $($psFiles.Count) PowerShell file(s)..." -ForegroundColor Yellow

                foreach ($file in $psFiles) {
                    $parseErrors = $null
                    [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$null, [ref]$parseErrors) | Out-Null

                    if ($parseErrors.Count -gt 0) {
                        $relative = Get-DryRunRelativePath -Path $file.FullName -Root $RepoRoot
                        foreach ($parseError in $parseErrors) {
                            $failures.Add(('{0}:{1}:{2} {3}' -f $relative,
                                                                $parseError.Extent.StartLineNumber,
                                                                $parseError.Extent.StartColumnNumber,
                                                                $parseError.Message))
                        }
                    }
                    else {
                        Write-Verbose "Parsed: $($file.FullName)"
                    }
                }
            }

            'Analyzer' {
                Write-DryRunHeader -Title 'Check 2/4: PSScriptAnalyzer'

                $settingsFile = Join-Path $RepoRoot 'PSScriptAnalyzerSettings.psd1'

                if (-not (Get-Module -ListAvailable -Name PSScriptAnalyzer)) {
                    $failures.Add('PSScriptAnalyzer is not installed, so nothing was analysed.')
                    $failures.Add('    Install-Module PSScriptAnalyzer -Scope CurrentUser')
                    $failures.Add('    Or skip this check explicitly with: -Check Parse,Bicep,BicepParams')
                }
                elseif (-not (Test-Path -LiteralPath $settingsFile)) {
                    $failures.Add("Settings file not found: $settingsFile")
                }
                else {
                    Import-Module PSScriptAnalyzer
                    Write-Host 'Analysing the repository (this is the slow check)...' -ForegroundColor Yellow

                    $findings = @(Invoke-ScriptAnalyzer -Path $RepoRoot -Recurse -Settings $settingsFile |
                                  Where-Object { -not (Test-DryRunExcludedPath -Path $_.ScriptPath -Root $RepoRoot -ExcludeName $ExcludeDirectory) })

                    $itemCount = @(Get-DryRunFile -Root $RepoRoot -Extension '.ps1', '.psm1', '.psd1' -ExcludeName $ExcludeDirectory).Count
                    $analyzerErrors = @($findings | Where-Object { $_.Severity -eq 'Error' })
                    $analyzerWarnings = @($findings | Where-Object { $_.Severity -eq 'Warning' })

                    # CI gates on Error only; warnings are printed so they can be fixed or justified in the PR.
                    foreach ($finding in $analyzerErrors) {
                        $relative = Get-DryRunRelativePath -Path $finding.ScriptPath -Root $RepoRoot
                        $failures.Add(('{0}:{1} [{2}] {3}' -f $relative, $finding.Line, $finding.RuleName, $finding.Message))
                    }

                    $note = "$($analyzerWarnings.Count) warning(s)"

                    if ($analyzerWarnings.Count -gt 0) {
                        Write-Host "  -> $($analyzerWarnings.Count) warning(s), not gating (same as CI):" -ForegroundColor Yellow
                        foreach ($finding in $analyzerWarnings) {
                            $relative = Get-DryRunRelativePath -Path $finding.ScriptPath -Root $RepoRoot
                            Write-Host ('     {0}:{1} [{2}] {3}' -f $relative, $finding.Line, $finding.RuleName, $finding.Message) -ForegroundColor Gray
                        }
                    }
                }
            }

            'Bicep' {
                Write-DryRunHeader -Title 'Check 3/4: az bicep build (entry points)'

                # Templates under a 'modules' folder are compiled transitively by their caller,
                # exactly as the Lint workflow filters them out.
                $bicepFiles = @(Get-DryRunFile -Root $RepoRoot -Extension '.bicep' -ExcludeName $ExcludeDirectory |
                                Where-Object { $_.FullName -notmatch '[\\/]modules[\\/]' })

                if (-not (Get-Command -Name az -CommandType Application -ErrorAction SilentlyContinue)) {
                    $failures.Add("Azure CLI ('az') was not found on PATH, so $($bicepFiles.Count) template(s) were NOT compiled.")
                    $failures.Add('    Install it from https://aka.ms/installazurecli, then run: az bicep install')
                    $failures.Add('    Or skip this check explicitly with: -Check Parse,Analyzer')
                }
                else {
                    $itemCount = $bicepFiles.Count
                    Write-Host "Building $($bicepFiles.Count) Bicep entry point(s)..." -ForegroundColor Yellow

                    $buildDirectory = Join-Path $tempRoot 'bicep'
                    New-Item -ItemType Directory -Path $buildDirectory -Force | Out-Null

                    foreach ($line in (Invoke-DryRunBicepBuild -File $bicepFiles -Command 'build' -OutputDirectory $buildDirectory -Root $RepoRoot)) {
                        $failures.Add($line)
                    }
                }
            }

            'BicepParams' {
                Write-DryRunHeader -Title 'Check 4/4: az bicep build-params'

                $paramFiles = @(Get-DryRunFile -Root $RepoRoot -Extension '.bicepparam' -ExcludeName $ExcludeDirectory)

                if (-not (Get-Command -Name az -CommandType Application -ErrorAction SilentlyContinue)) {
                    $failures.Add("Azure CLI ('az') was not found on PATH, so $($paramFiles.Count) parameter file(s) were NOT compiled.")
                    $failures.Add('    Install it from https://aka.ms/installazurecli, then run: az bicep install')
                    $failures.Add('    Or skip this check explicitly with: -Check Parse,Analyzer')
                }
                else {
                    $itemCount = $paramFiles.Count
                    Write-Host "Building $($paramFiles.Count) parameter file(s)..." -ForegroundColor Yellow

                    $paramDirectory = Join-Path $tempRoot 'bicepparam'
                    New-Item -ItemType Directory -Path $paramDirectory -Force | Out-Null

                    foreach ($line in (Invoke-DryRunBicepBuild -File $paramFiles -Command 'build-params' -OutputDirectory $paramDirectory -Root $RepoRoot)) {
                        $failures.Add($line)
                    }
                }
            }
        }

        $stopwatch.Stop()
        $status = if ($failures.Count -gt 0) { 'Failed' } else { 'Passed' }
        $results.Add((New-DryRunResult -Name $name -Status $status -ItemCount $itemCount `
                                       -Failure $failures.ToArray() -Duration $stopwatch.Elapsed -Note $note))

        if ($status -eq 'Passed') {
            Write-Host ('  -> PASS ({0} item(s), {1:n1}s)' -f $itemCount, $stopwatch.Elapsed.TotalSeconds) -ForegroundColor Green
        }
        else {
            Write-Host ('  -> FAIL ({0} problem(s))' -f $failures.Count) -ForegroundColor Red
        }
    }
}
finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

#region Summary

$failedChecks = @($results | Where-Object { $_.Status -eq 'Failed' })

if ($failedChecks.Count -gt 0) {
    Write-Host ''
    Write-Host '=== Failures ===' -ForegroundColor Cyan
    foreach ($result in $failedChecks) {
        Write-Host ''
        Write-Host "$($result.Name):" -ForegroundColor Red
        foreach ($line in $result.Failure) {
            Write-Host "  $line" -ForegroundColor Red
        }
    }
}

Write-Host ''
Write-Host '=== Dry-run summary ===' -ForegroundColor Cyan
Write-Host ('{0,-12} {1,-7} {2,6} {3,9} {4,10}  {5}' -f 'Check', 'Status', 'Items', 'Problems', 'Duration', 'Note') -ForegroundColor Gray

foreach ($result in $results) {
    switch ($result.Status) {
        'Passed' { $label = 'PASS'; $colour = 'Green' }
        'Failed' { $label = 'FAIL'; $colour = 'Red' }
        'Skipped' { $label = 'SKIP'; $colour = 'Yellow' }
    }

    $items = if ($result.Status -eq 'Skipped') { '-' } else { $result.ItemCount.ToString() }
    $problems = if ($result.Status -eq 'Skipped') { '-' } else { $result.Failure.Count.ToString() }
    $duration = if ($result.Status -eq 'Skipped') { '-' } else { '{0:n1}s' -f $result.Duration.TotalSeconds }

    Write-Host ('{0,-12} {1,-7} {2,6} {3,9} {4,10}  {5}' -f $result.Name, $label, $items, $problems, $duration, $result.Note) -ForegroundColor $colour
}

$skippedChecks = @($results | Where-Object { $_.Status -eq 'Skipped' })
if ($skippedChecks.Count -gt 0) {
    Write-Host ''
    Write-Host "Not run: $($skippedChecks.Name -join ', '). This run did NOT cover the whole gate." -ForegroundColor Yellow
}

Write-Host ''
Write-Host 'Out of scope here (need Azure or extra tooling): az deployment what-if, Test-Lab.ps1,' -ForegroundColor Gray
Write-Host 'Remove-LabResource.ps1, Pester, markdownlint, gitleaks. See docs/dry-run-harness.md' -ForegroundColor Gray
Write-Host 'for the copy-paste commands, per lab.' -ForegroundColor Gray

if ($failedChecks.Count -gt 0) {
    Write-Host ''
    Write-Host "Dry run FAILED: $($failedChecks.Count) check(s) reported problems." -ForegroundColor Red
    $Host.SetShouldExit(1)
    exit 1
}

Write-Host ''
Write-Host 'Dry run passed. CI still runs Pester, markdownlint and gitleaks on top of this.' -ForegroundColor Green
exit 0

#endregion Summary
