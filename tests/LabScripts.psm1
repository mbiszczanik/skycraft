<#
.SYNOPSIS
    Shared helper: locates the lab automation scripts that the repo-standards suites lint.

.DESCRIPTION
    The automation-contract rules, the script-standards suite and the CBH-coverage suite all
    need the same answer to one question: which files are lab scripts? The answer is every
    *.ps1 under module-<digit>*/scripts/.

    That definition lives here once. Held separately in each suite it could drift, and a
    drifted copy silently lints fewer files without any test failing - the worst outcome
    for a lint suite, because coverage shrinks invisibly.

    Get-LabScript returns FileInfo objects. Get-ScriptCase projects them into the
    @{ file = <repo-relative>; path = <absolute> } hashtables Pester's -ForEach expects.

.EXAMPLE
    Import-Module ./tests/LabScripts.psm1
    Get-ScriptCase -FileName 'Deploy-Bicep.ps1'

.NOTES
    Project: SkyCraft
#>

#Requires -Version 7.0

$ErrorActionPreference = 'Stop'

function Get-LabScriptRoot {
    <#
    .SYNOPSIS
        Returns the repository root, resolved as the parent of tests/.

    .DESCRIPTION
        Every caller sits in tests/, so the root is derived from this module's own location
        rather than the caller's working directory.

    .NOTES
        Project: SkyCraft
    #>
    [CmdletBinding()]
    param()

    (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
}

function Get-LabScript {
    <#
    .SYNOPSIS
        Returns every lab automation script, optionally narrowed to one file name.

    .DESCRIPTION
        Matches *.ps1 under module-<digit>*/scripts/. Path matching is separator-agnostic so
        the suites select an identical set on the Windows dev box and the Linux CI runner.

    .PARAMETER FileName
        File name filter, e.g. 'Deploy-Bicep.ps1'. Defaults to every *.ps1.

    .PARAMETER Root
        Repository root to search. Defaults to the parent of tests/.

    .NOTES
        Project: SkyCraft
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$FileName = '*.ps1',

        [Parameter()]
        [string]$Root
    )

    if (-not $Root) { $Root = Get-LabScriptRoot }

    Get-ChildItem -Path $Root -Recurse -File -Filter $FileName |
        Where-Object { ($_.FullName -replace '\\', '/') -match '/module-\d.*/scripts/' }
}

function Get-ScriptCase {
    <#
    .SYNOPSIS
        Projects lab scripts into the case hashtables Pester's -ForEach consumes.

    .DESCRIPTION
        Emits @{ file = <repo-relative path>; path = <absolute path> } per script. The
        relative 'file' is what test names display; 'path' is what the assertions read.

    .PARAMETER FileName
        File name filter, e.g. 'Test-Lab.ps1'. Defaults to every *.ps1.

    .PARAMETER Root
        Repository root to search. Defaults to the parent of tests/.

    .NOTES
        Project: SkyCraft
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$FileName = '*.ps1',

        [Parameter()]
        [string]$Root
    )

    if (-not $Root) { $Root = Get-LabScriptRoot }

    Get-LabScript -FileName $FileName -Root $Root | ForEach-Object {
        @{ file = $_.FullName.Substring($Root.Length + 1); path = $_.FullName }
    }
}

Export-ModuleMember -Function Get-LabScriptRoot, Get-LabScript, Get-ScriptCase
