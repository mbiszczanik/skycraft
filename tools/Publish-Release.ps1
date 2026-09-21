<#
.SYNOPSIS
    Tags and publishes the GitHub Release for the CHANGELOG head.

.DESCRIPTION
    Publish-Release.ps1 is the one release path SkyCraft has. The release workflow
    (.github/workflows/release.yml) runs it on every push to main that touches
    CHANGELOG.md, and a maintainer runs it by hand for a backfill or when the workflow
    is unavailable. Both do the same thing:

      1. Read the topmost '## [X.Y.Z] - YYYY-MM-DD' section of CHANGELOG.md.
      2. Ask `gh release view vX.Y.Z` whether that release already exists.
         If it does, report it and exit 0 - the run is a no-op, not a failure.
      3. Otherwise `gh release create vX.Y.Z` at the target commit, titled vX.Y.Z,
         with the CHANGELOG section plus a '**Full Changelog**' compare link as the
         notes. `gh` creates the tag on the target commit in the same call.

    The CHANGELOG is the single source of truth: no version is typed anywhere else, so
    the tag, the release title and the notes cannot disagree with each other or with
    the file. The parser and the gh call live in tools/Changelog.psm1, where
    tests/Changelog.Tests.ps1 exercises them offline.

    Requires the GitHub CLI (`gh`) authenticated with a token that can write contents
    of the repository. In the workflow that is the job's GITHUB_TOKEN; locally it is
    `gh auth login`.

.PARAMETER Path
    The CHANGELOG file to release from. Defaults to CHANGELOG.md at the repository root.

.PARAMETER Repository
    The GitHub repository in 'owner/name' form. Defaults to $env:GITHUB_REPOSITORY when
    set (GitHub Actions), otherwise to the 'origin' remote of the repository.

.PARAMETER Target
    The commit to tag when the release is created. Defaults to $env:GITHUB_SHA when set,
    otherwise to HEAD. Pass the merge commit's SHA explicitly for a backfill.

.PARAMETER GhCommand
    Test seam: a script block that takes [string[]] `gh` arguments and returns an object
    with ExitCode and Output. Leave unset to run the real `gh`.

.EXAMPLE
    .\tools\Publish-Release.ps1 -WhatIf

    Shows which version would be released, at which commit, without creating anything.

.EXAMPLE
    .\tools\Publish-Release.ps1

    Publishes the CHANGELOG head as a release of the origin repository at HEAD, or
    reports that it is already published.

.EXAMPLE
    .\tools\Publish-Release.ps1 -Target 9649690

    Backfills a release for a CHANGELOG head that was merged earlier, tagging that commit.

.NOTES
    Project: SkyCraft
    Date: 2026-09-19

    Exits 0 when the release was created or already existed, 1 when `gh` refused to
    create it. Never deletes or edits an existing release or tag.
#>

#Requires -Version 7.0

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$Path = (Join-Path (Split-Path -Parent $PSScriptRoot) 'CHANGELOG.md'),

    [Parameter(Mandatory = $false)]
    [ValidatePattern('^[^/\s]+/[^/\s]+$')]
    [string]$Repository,

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$Target,

    [Parameter(Mandatory = $false)]
    [scriptblock]$GhCommand
)

$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'Changelog.psm1') -Force

if (-not $Repository) {
    $Repository = if ($env:GITHUB_REPOSITORY) {
        $env:GITHUB_REPOSITORY
    }
    else {
        ConvertTo-GitHubRepository -RemoteUrl (& git -C (Split-Path -Parent $Path) remote get-url origin)
    }
}

if (-not $Target) {
    $Target = if ($env:GITHUB_SHA) { $env:GITHUB_SHA } else { (& git -C (Split-Path -Parent $Path) rev-parse HEAD) }
}

$publishArguments = @{
    Path       = $Path
    Repository = $Repository
    Target     = $Target
}
if ($GhCommand) { $publishArguments['GhCommand'] = $GhCommand }

try {
    $result = Publish-ChangelogRelease @publishArguments -WhatIf:$WhatIfPreference
}
catch {
    Write-Host "[ERROR] $($_.Exception.Message)"
    $Host.SetShouldExit(1)
    exit 1
}

switch ($result.Status) {
    'AlreadyPublished' { Write-Host "[SKIP] $($result.Tag) is already published: $($result.Url)" }
    'Published'        { Write-Host "[OK] Published $($result.Tag) at $Target`: $($result.Url)" }
    'WhatIf'           { Write-Host "[WHATIF] Would publish $($result.Tag) of $Repository at $Target with these notes:`n`n$($result.Notes)" }
}

$result

# A plain exit 0 so a caller's $LASTEXITCODE is set by this script, not by whatever
# native command ran before it.
exit 0
