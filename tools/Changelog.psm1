<#
.SYNOPSIS
    Reads the release at the head of a Keep-a-Changelog file.

.DESCRIPTION
    The release workflow (.github/workflows/release.yml) and the manual path
    (tools/Publish-Release.ps1) both decide what to tag and what to publish as release
    notes from CHANGELOG.md alone: the topmost '## [X.Y.Z] - YYYY-MM-DD' section is the
    release, its body is the notes. Held in a module so tests/Changelog.Tests.ps1 calls
    exactly the parser the release path calls.

.EXAMPLE
    Import-Module ./tools/Changelog.psm1
    Get-ChangelogRelease -Path ./CHANGELOG.md

.NOTES
    Project: SkyCraft
#>

#Requires -Version 7.0

$ErrorActionPreference = 'Stop'

function Get-ChangelogRelease {
    <#
    .SYNOPSIS
        Returns the topmost released section of a Keep-a-Changelog file.

    .DESCRIPTION
        Walks the file line by line, skipping fenced code blocks, until the first
        '## [X.Y.Z] - YYYY-MM-DD' heading. '## [Unreleased]' does not match and is passed
        over. The body runs from the line after that heading to the line before the next
        '## ' heading (or to the end of the file), with surrounding blank lines trimmed.

        The next released heading after the head, if any, supplies PreviousTag - the
        'from' side of the compare link every SkyCraft release carries.

    .PARAMETER Path
        The CHANGELOG file to read.

    .OUTPUTS
        [pscustomobject] with Version, Tag, Date, PreviousTag and Notes.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Path
    )

    $lines   = [System.IO.File]::ReadAllLines((Resolve-Path -LiteralPath $Path).Path)
    $heading = '^## \[(?<version>\d+\.\d+\.\d+)\]\s*-\s*(?<date>\d{4}-\d{2}-\d{2})\s*$'

    $inFence  = $false
    $head     = $null
    $previous = $null
    $body     = [System.Collections.Generic.List[string]]::new()

    foreach ($line in $lines) {

        # A fence toggles on its own line; nothing inside one is a heading.
        if ($line -match '^\s*(```|~~~)') {
            $inFence = -not $inFence
            if ($null -ne $head) { $body.Add($line) }
            continue
        }
        if ($inFence) {
            if ($null -ne $head) { $body.Add($line) }
            continue
        }

        if ($null -eq $head) {
            if ($line -match $heading) {
                $head = [pscustomobject]@{ Version = $Matches.version; Date = $Matches.date }
            }
            continue
        }

        # Any second-level heading ends the body. A released one also names the previous tag.
        if ($line -match '^## ') {
            if ($line -match $heading) { $previous = 'v' + $Matches.version }
            break
        }

        $body.Add($line)
    }

    if ($null -eq $head) {
        throw "CHANGELOG '$Path' has no released section: no '## [X.Y.Z] - YYYY-MM-DD' heading was found outside a code fence."
    }

    [pscustomobject]@{
        Version     = $head.Version
        Tag         = 'v' + $head.Version
        Date        = $head.Date
        PreviousTag = $previous
        Notes       = ($body -join "`n").Trim()
    }
}

function Get-ReleaseBody {
    <#
    .SYNOPSIS
        Builds the GitHub Release body for a CHANGELOG release.

    .DESCRIPTION
        The CHANGELOG section body followed by the '**Full Changelog**' compare link that
        every SkyCraft release since v0.4.0 ends with. A first release has nothing to
        compare against, so it links to the commit list at its tag instead.

    .PARAMETER Release
        The object Get-ChangelogRelease returns.

    .PARAMETER Repository
        The GitHub repository in 'owner/name' form.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Release,

        [Parameter(Mandatory = $true)]
        [ValidatePattern('^[^/\s]+/[^/\s]+$')]
        [string]$Repository
    )

    $link = if ($Release.PreviousTag) {
        "https://github.com/$Repository/compare/$($Release.PreviousTag)...$($Release.Tag)"
    }
    else {
        "https://github.com/$Repository/commits/$($Release.Tag)"
    }

    "$($Release.Notes)`n`n**Full Changelog**: $link"
}

function Invoke-GhCommand {
    <#
    .SYNOPSIS
        The real `gh` probe: runs the CLI and returns its exit code with its merged output.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string[]]$Arguments)

    $output = & gh @Arguments 2>&1 | ForEach-Object { "$_" }
    [pscustomobject]@{
        ExitCode = $LASTEXITCODE
        Output   = ($output -join "`n")
    }
}

function Publish-ChangelogRelease {
    <#
    .SYNOPSIS
        Creates the GitHub Release (and its tag) for the CHANGELOG head, once.

    .DESCRIPTION
        Reads the head release with Get-ChangelogRelease, asks `gh release view` whether that
        tag is already published and, if not, runs `gh release create` with the tag as the
        title, the given commit as the target and Get-ReleaseBody as the body. `gh release
        create` creates the tag on the target commit when it does not exist yet, so the
        tag and the release always come from the same call.

        Idempotent: a second run against the same CHANGELOG head reports AlreadyPublished
        and touches nothing. That is what lets the release workflow run on every push to
        main that changes CHANGELOG.md - only the merge that adds a new section releases.

        The `gh` call is injectable so tests/Changelog.Tests.ps1 exercises the decision
        without a network or a token; the shipped default runs the real CLI.

    .PARAMETER Path
        The CHANGELOG file to release from.

    .PARAMETER Repository
        The GitHub repository in 'owner/name' form.

    .PARAMETER Target
        The commit (SHA or ref) to tag when the release is created.

    .PARAMETER GhCommand
        A script block that takes [string[]] `gh` arguments and returns an object with
        ExitCode and Output. Defaults to running the real `gh`.

    .OUTPUTS
        [pscustomobject] with Status (AlreadyPublished | Published | WhatIf), Tag, Version,
        Notes and - when published - Url.
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [ValidatePattern('^[^/\s]+/[^/\s]+$')]
        [string]$Repository,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Target,

        [Parameter(Mandatory = $false)]
        [scriptblock]$GhCommand = { param([string[]]$Arguments) Invoke-GhCommand -Arguments $Arguments }
    )

    $release = Get-ChangelogRelease -Path $Path
    $notes   = Get-ReleaseBody -Release $release -Repository $Repository

    $probe = & $GhCommand @('release', 'view', $release.Tag, '--repo', $Repository, '--json', 'tagName')
    if ($probe.ExitCode -eq 0) {
        return [pscustomobject]@{
            Status  = 'AlreadyPublished'
            Tag     = $release.Tag
            Version = $release.Version
            Notes   = $notes
            Url     = "https://github.com/$Repository/releases/tag/$($release.Tag)"
        }
    }

    if (-not $PSCmdlet.ShouldProcess($Repository, "Create GitHub Release $($release.Tag) at $Target")) {
        return [pscustomobject]@{
            Status  = 'WhatIf'
            Tag     = $release.Tag
            Version = $release.Version
            Notes   = $notes
            Url     = $null
        }
    }

    # --notes-file rather than --notes: the body is multi-line Markdown and must reach gh
    # byte-for-byte, without the shell deciding what a newline or a backtick means.
    $notesFile = Join-Path ([System.IO.Path]::GetTempPath()) ("release-notes-{0}.md" -f [guid]::NewGuid())
    try {
        [System.IO.File]::WriteAllText($notesFile, $notes, [System.Text.UTF8Encoding]::new($false))

        $create = & $GhCommand @(
            'release', 'create', $release.Tag,
            '--repo', $Repository,
            '--target', $Target,
            '--title', $release.Tag,
            '--notes-file', $notesFile
        )
        if ($create.ExitCode -ne 0) {
            throw "gh release create $($release.Tag) failed (exit $($create.ExitCode)): $($create.Output)"
        }

        [pscustomobject]@{
            Status  = 'Published'
            Tag     = $release.Tag
            Version = $release.Version
            Notes   = $notes
            Url     = $create.Output.Trim()
        }
    }
    finally {
        if (Test-Path -LiteralPath $notesFile) { Remove-Item -LiteralPath $notesFile -Force }
    }
}

function ConvertTo-GitHubRepository {
    <#
    .SYNOPSIS
        Reads 'owner/name' out of a GitHub remote URL.

    .DESCRIPTION
        Accepts the https, scp-style ssh and ssh:// forms git prints for `remote get-url`,
        with or without the '.git' suffix. Anything not on github.com throws: a release
        published to the wrong host is worse than no release.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$RemoteUrl
    )

    if ($RemoteUrl -match '^(?:https://|ssh://(?:[^@/]+@)?|[^@/]+@)github\.com[:/](?<owner>[^/\s]+)/(?<name>[^/\s]+?)(?:\.git)?/?$') {
        return "$($Matches.owner)/$($Matches.name)"
    }

    throw "'$RemoteUrl' is not a GitHub remote; pass -Repository owner/name explicitly."
}

Export-ModuleMember -Function Get-ChangelogRelease, Get-ReleaseBody, Publish-ChangelogRelease, ConvertTo-GitHubRepository
