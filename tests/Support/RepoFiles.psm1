<#
.SYNOPSIS
    Lists the repository's files for a Pester suite the way git sees them (#414).

.DESCRIPTION
    `Get-ChildItem -Recurse` without -Force does not descend into dot-directories on Linux, so a
    suite that scans the repository root on the `ubuntu-latest` runner never sees `.github/`, while
    a local Windows run does. -Force would instead pull in ignored folders such as `.worktrees/`
    and `.patches/`. `git ls-files` lists the tracked files and the new ones that are not ignored,
    the same on every platform.

    Get-RepoFile returns FileInfo objects, so a suite changes only the line that lists the files.
    It throws when git fails or lists nothing, so a broken scan cannot pass as a green check.

.EXAMPLE
    Import-Module ./tests/Support/RepoFiles.psm1
    Get-RepoFile -Root $RepoRoot -Filter '*.bicep'

.NOTES
    Project: SkyCraft
    Issue: #414
#>

#Requires -Version 7.0

function Get-RepoFile {
    [CmdletBinding()]
    [OutputType([System.IO.FileInfo])]
    param(
        # The repository root.
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Root,

        # A file name pattern at any depth, such as '*.bicep' or 'lab-guide-*.md'. Default: every file.
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$Filter = '*'
    )

    $listed = @(& git -C $Root ls-files --cached --others --exclude-standard -- ":(glob)**/$Filter")
    if ($LASTEXITCODE -ne 0) { throw "git ls-files failed in '$Root' (exit $LASTEXITCODE); the file scan cannot run." }
    if ($listed.Count -eq 0) { throw "git ls-files listed no file matching '$Filter' in '$Root'; the file scan cannot run." }

    foreach ($relative in $listed) {
        $path = Join-Path $Root $relative
        # A file removed from the working tree is still in the index until it is staged.
        # -Force: on Linux Get-Item does not return a dot-file such as .editorconfig without it.
        if (Test-Path -LiteralPath $path -PathType Leaf) { Get-Item -LiteralPath $path -Force }
    }
}

Export-ModuleMember -Function Get-RepoFile
