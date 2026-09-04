<#
.SYNOPSIS
    Pester 5 test: every relative Markdown link resolves on disk, case included.

.DESCRIPTION
    docs/project-standards.md section 1.1 warns that link targets must match
    directory/file casing exactly - broken case is invisible on a case-insensitive
    filesystem (Windows, where `Test-Path` ignores case) but breaks the link on
    Linux/macOS or the case-sensitive CI runner.

    For every `*.md` file tracked by `git ls-files`, this test extracts every
    `](...)` link outside fenced code blocks and inline code spans (a link
    shown as a literal example - a template placeholder, a syntax sample - is
    not a real link to resolve), skips URI-scheme links (http/https/mailto/...)
    and pure anchors (`#section`), resolves the remainder relative to the referencing
    file's directory (or the repo root for a leading `/`), and asserts the
    resolved path is a member of the `git ls-files` output via case-sensitive
    (`-ccontains`) matching, not `Test-Path`.

    Path matching is separator-agnostic so the suite runs identically on the
    Windows dev box and the Linux CI runner.

.EXAMPLE
    Invoke-Pester -Path .\tests\Markdown-Links.Tests.ps1

.NOTES
    Project: SkyCraft
#>

#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path

# git ls-files preserves the exact on-disk casing Git tracks, unlike Test-Path,
# which is case-insensitive on Windows.
$TrackedFiles = @(& git -C $RepoRoot ls-files | ForEach-Object { $_ -replace '\\', '/' })

$TrackedDirs = @(foreach ($trackedFile in $TrackedFiles) {
    $segments = $trackedFile -split '/'
    for ($i = 1; $i -lt $segments.Length; $i++) {
        $segments[0..($i - 1)] -join '/'
    }
}) | Select-Object -Unique

$SchemeOrAnchorPattern = '^([a-zA-Z][a-zA-Z0-9+.\-]*:|#)'

function Resolve-MarkdownLinkTarget {
    param(
        [Parameter(Mandatory)][string]$Target,
        [AllowEmptyString()][string]$MarkdownDir
    )

    $isRootRelative = $Target.StartsWith('/')
    $stripped = ($Target.TrimStart('/').TrimEnd('/')) -split '[#?]' | Select-Object -First 1
    $stripped = [Uri]::UnescapeDataString($stripped)

    $segments = [System.Collections.Generic.List[string]]::new()
    if (-not $isRootRelative -and $MarkdownDir) {
        $segments.AddRange([string[]]($MarkdownDir -split '/'))
    }
    $segments.AddRange([string[]]($stripped -split '/'))

    $normalized = [System.Collections.Generic.List[string]]::new()
    foreach ($segment in $segments) {
        if ($segment -eq '' -or $segment -eq '.') { continue }
        elseif ($segment -eq '..') {
            if ($normalized.Count -gt 0) { $normalized.RemoveAt($normalized.Count - 1) }
        }
        else {
            $normalized.Add($segment)
        }
    }

    return ($normalized -join '/')
}

$MarkdownFiles = $TrackedFiles | Where-Object { $_ -like '*.md' }

$LinkCases = foreach ($mdFile in $MarkdownFiles) {
    $absPath = Join-Path $RepoRoot $mdFile
    $rawText = Get-Content -Raw -LiteralPath $absPath
    $mdSegments = $mdFile -split '/'
    $mdDir = if ($mdSegments.Length -gt 1) { $mdSegments[0..($mdSegments.Length - 2)] -join '/' } else { '' }

    # Strip fenced code blocks and inline code spans first: a link shown as a
    # literal example (a template placeholder, a syntax sample) is not a real
    # link to resolve. Blank out matches rather than removing them, so capture
    # offsets used only for reporting stay stable.
    $text = [regex]::Replace($rawText, '(?ms)^```.*?^```', { param($mm) $mm.Value -replace '[^\r\n]', ' ' })
    $text = [regex]::Replace($text, '`[^`\r\n]*`', { param($mm) $mm.Value -replace '.', ' ' })

    foreach ($m in [regex]::Matches($text, '\]\(([^)\s][^)]*)\)')) {
        $target = $m.Groups[1].Value.Trim()
        if ([string]::IsNullOrWhiteSpace($target) -or $target -match $SchemeOrAnchorPattern) { continue }
        # Un-fenced placeholder examples aren't real links: checklist-standards.md's
        # "Lab X.Y" / "../X.Z-lab-name/..." prose uses letters where a real lab
        # number is always digits (e.g. 2.3), and lab-guide-template.md's
        # "[PLACEHOLDER]" tokens use square brackets no real repo path contains.
        if ($target -match 'X\.[YZ]' -or $target -match '[\[\]]') { continue }

        $isDirLink = $target.TrimEnd() -match '/$'
        $resolved = Resolve-MarkdownLinkTarget -Target $target -MarkdownDir $mdDir
        if ([string]::IsNullOrWhiteSpace($resolved)) { continue }

        # Resolved at discovery time and carried as a plain boolean, rather than
        # re-checked against $TrackedFiles/$TrackedDirs inside the It block: Pester
        # re-executes this file's top-level code for its discovery and run passes,
        # and relying on a script-scope collection surviving into the run pass
        # proved unreliable - baking the verdict into the case itself sidesteps that.
        $isTracked = if ($isDirLink) { $TrackedDirs -ccontains $resolved } else { $TrackedFiles -ccontains $resolved }

        @{
            file       = $mdFile
            link       = $target
            resolved   = $resolved
            isDir      = $isDirLink
            isTracked  = $isTracked
        }
    }
}

Describe 'Markdown relative links resolve on disk (case-sensitive)' {

    It "'<file>' link '<link>' resolves to a tracked path with matching case" -ForEach $LinkCases {
        $kind = if ($isDir) { 'directory' } else { 'file' }
        $isTracked | Should -BeTrue -Because "'$resolved' referenced by '$file' must be a tracked $kind with matching case (git ls-files)"
    }
}
