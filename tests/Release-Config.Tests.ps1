<#
.SYNOPSIS
    Pester 5 tests pinning the release-please configuration to the PR-title check.

.DESCRIPTION
    Releases are cut by release-please from the Conventional Commits titles of the pull
    requests squash-merged into main (docs/adr/0007-release-with-release-please.md). Two
    files decide which commit types count and both have to agree:

      1. release-please-config.json - 'changelog-sections' lists the types the bot knows;
         a type outside that list is silently ignored when the release notes are built.
      2. .github/workflows/pr-title.yml - the 'types' input of the PR-title check lists
         the types a contributor may use in a PR title.

    A type allowed by (2) but missing from (1) passes the merge gate and then vanishes
    from the release notes with nothing to notice; the third test below makes the two
    lists identical. The first two tests keep both JSON files parseable so a stray comma
    cannot break the release workflow on main.

.EXAMPLE
    Invoke-Pester -Path .\tests\Release-Config.Tests.ps1

.NOTES
    Project: SkyCraft
#>

#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    $script:RepoRoot     = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    $script:ConfigPath   = Join-Path $script:RepoRoot 'release-please-config.json'
    $script:ManifestPath = Join-Path $script:RepoRoot '.release-please-manifest.json'
    $script:PrTitlePath  = Join-Path $script:RepoRoot '.github/workflows/pr-title.yml'

    # The 'types' input is a YAML block scalar (types: |) with one type per indented line.
    # Read it line by line rather than with a YAML parser, which pwsh does not ship.
    function script:Get-PrTitleAllowedType {
        param([string]$Path)
        $lines = Get-Content -LiteralPath $Path
        $start = -1
        for ($i = 0; $i -lt $lines.Count; $i++) {
            if ($lines[$i] -match '^\s*types:\s*\|\s*$') { $start = $i; break }
        }
        if ($start -lt 0) { return @() }
        $indent = ($lines[$start] -replace '^(\s*).*$', '$1').Length
        $types = @()
        for ($i = $start + 1; $i -lt $lines.Count; $i++) {
            $line = $lines[$i]
            if ($line -notmatch '^\s+\S') { break }
            if ((($line -replace '^(\s*).*$', '$1').Length) -le $indent) { break }
            $types += $line.Trim()
        }
        return $types
    }
}

Describe 'release-please configuration - the files parse' {
    It 'release-please-config.json is valid JSON and configures the root package' {
        $config = Get-Content -Raw -LiteralPath $script:ConfigPath | ConvertFrom-Json
        $config.'release-type' | Should -Be 'simple'
        $config.packages.PSObject.Properties.Name | Should -Contain '.'
        $config.'bump-minor-pre-major' | Should -BeTrue
    }

    It '.release-please-manifest.json pins a three-part version for the root package' {
        $manifest = Get-Content -Raw -LiteralPath $script:ManifestPath | ConvertFrom-Json
        $manifest.'.' | Should -Match '^\d+\.\d+\.\d+$'
    }

    It 'version.txt carries the same version as the manifest' {
        $manifest = Get-Content -Raw -LiteralPath $script:ManifestPath | ConvertFrom-Json
        (Get-Content -Raw -LiteralPath (Join-Path $script:RepoRoot 'version.txt')).Trim() |
            Should -Be $manifest.'.'
    }
}

Describe 'release-please configuration - the PR-title check and the changelog sections agree' {
    It 'the PR-title check allows exactly the commit types release-please knows' {
        $config   = Get-Content -Raw -LiteralPath $script:ConfigPath | ConvertFrom-Json
        $sections = @($config.'changelog-sections'.type)
        $allowed  = @(Get-PrTitleAllowedType -Path $script:PrTitlePath)

        $sections.Count | Should -BeGreaterThan 0 -Because 'an empty section list would hide every commit'
        $allowed.Count  | Should -BeGreaterThan 0 -Because "the 'types: |' block was not found in pr-title.yml"
        Compare-Object -ReferenceObject $sections -DifferenceObject $allowed |
            Should -BeNullOrEmpty -Because 'a type allowed in a PR title but unknown to release-please is dropped from the notes'
    }

    It 'the docs type is visible so documentation-only work produces a release' {
        $config = Get-Content -Raw -LiteralPath $script:ConfigPath | ConvertFrom-Json
        $docs = $config.'changelog-sections' | Where-Object type -eq 'docs'
        $docs | Should -Not -BeNullOrEmpty
        [bool]$docs.hidden | Should -BeFalse
    }
}
