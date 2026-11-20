<#
.SYNOPSIS
    Counts, per lab guide, the steps and the steps that carry an Az PowerShell block.

.DESCRIPTION
    Reads every module-*/X.Y-*/lab-guide-X.Y.md and counts the headings of the form
    "### Step X.Y.N" outside code fences. A step section runs to the next "##" or "###"
    heading. A step "has PowerShell" when its section holds a fenced block tagged powershell,
    pwsh or ps1. A step "has CLI only" when it holds an azurecli, bash or sh block and no
    PowerShell block. The counts are a rough measure (read-back commands count too).

    docs/lab-parity.md quotes the output; tests/Lab-Parity-Doc.Tests.ps1 compares the two.

.PARAMETER Root
    Repository root. Defaults to the parent of this script's folder.

.PARAMETER AsMarkdown
    Writes the table rows as they appear in docs/lab-parity.md instead of objects.

.EXAMPLE
    ./tools/Get-LabParityCounts.ps1 -AsMarkdown

.NOTES
    Project: SkyCraft
#>

#Requires -Version 7.0

[CmdletBinding()]
param(
    [string]$Root = (Split-Path -Parent $PSScriptRoot),
    [switch]$AsMarkdown
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-StepCount {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][AllowEmptyString()][string[]]$Line
    )

    $inFence = $false
    $fenceTag = ''
    $steps = [System.Collections.Generic.List[hashtable]]::new()
    $current = $null
    foreach ($text in $Line) {
        if ($text -match '^\s*(`{3,}|~{3,})\s*([A-Za-z0-9_-]*)') {
            if (-not $inFence) {
                $inFence = $true
                $fenceTag = $Matches[2].ToLowerInvariant()
                if ($null -ne $current) {
                    if ($fenceTag -in 'powershell', 'pwsh', 'ps1') { $current.Psh = $true }
                    elseif ($fenceTag -in 'azurecli', 'bash', 'sh') { $current.Cli = $true }
                }
            }
            else {
                $inFence = $false
                $fenceTag = ''
            }
            continue
        }
        if ($inFence) { continue }
        if ($text -match '^###\s+Step\s+\d+\.\d+\.\d+') {
            $current = @{ Psh = $false; Cli = $false }
            $steps.Add($current)
        }
        elseif ($text -match '^#{1,3}\s') {
            $current = $null
        }
    }
    $withPsh = @($steps | Where-Object { $_.Psh }).Count
    $cliOnly = @($steps | Where-Object { $_.Cli -and -not $_.Psh }).Count
    [pscustomobject]@{ Steps = $steps.Count; WithPowerShell = $withPsh; CliOnly = $cliOnly }
}

$guides = @(
    Get-ChildItem -LiteralPath $Root -Directory -Filter 'module-*' |
        ForEach-Object { Get-ChildItem -LiteralPath $_.FullName -Recurse -File -Filter 'lab-guide-*.md' } |
        Sort-Object { [version]($_.BaseName -replace '^lab-guide-', '') }
)
if ($guides.Count -eq 0) { throw "No lab guide found under '$Root'." }

$result = foreach ($guide in $guides) {
    $lab = $guide.BaseName -replace '^lab-guide-', ''
    $count = Get-StepCount -Line (Get-Content -LiteralPath $guide.FullName)
    [pscustomobject]@{
        Lab            = $lab
        Steps          = $count.Steps
        WithPowerShell = $count.WithPowerShell
        CliOnly        = $count.CliOnly
    }
}

if ($AsMarkdown) {
    foreach ($row in $result) { "| $($row.Lab) | $($row.Steps) | $($row.WithPowerShell) | $($row.CliOnly) |" }
}
else {
    $result
}
