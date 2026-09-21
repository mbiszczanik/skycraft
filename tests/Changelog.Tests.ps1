<#
.SYNOPSIS
    Pester 5 tests: the CHANGELOG head resolves to exactly one release.

.DESCRIPTION
    Issue #82 - every versioned merge to main must produce the matching vX.Y.Z tag and
    GitHub Release, with the CHANGELOG section as the release notes. The release workflow
    (.github/workflows/release.yml) and the documented manual path (tools/Publish-Release.ps1)
    both read the CHANGELOG through tools/Changelog.psm1, so this file pins what that
    module must extract from a Keep-a-Changelog file:

      - the topmost '## [X.Y.Z] - YYYY-MM-DD' section, skipping '## [Unreleased]'
      - the section body only - not its heading, not the section that follows
      - the previous version, which the release notes' compare link needs
      - a hard failure when the file carries no released section at all

    The last Describe reads the repository's own CHANGELOG.md, so a malformed head
    heading is caught by CI before the merge that would have released it.

.EXAMPLE
    Invoke-Pester -Path .\tests\Changelog.Tests.ps1

.NOTES
    Project: SkyCraft
#>

#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    Import-Module (Join-Path $script:RepoRoot 'tools/Changelog.psm1') -Force

    # A Keep-a-Changelog file with the shape the repository's own CHANGELOG.md has: a
    # preamble, an Unreleased section, then released sections newest first.
    $script:Sample = @'
# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

### Added

- Something not yet released.

## [0.8.0] - 2026-08-29

### Added

- Pester guard `tests/Avm-Module-Pinning.Tests.ps1`.
- `.bicepparam` parameter files for the Module 1 Bicep entry points.

### Changed

- Lab 2.3 template outputs the public zone name.

## [0.7.1] - 2026-07-27

### Fixed

- A fix that shipped in 0.7.1.

[0.8.0]: https://github.com/example/repo/compare/v0.7.1...v0.8.0
'@

    function New-ChangelogFile {
        param([string]$Content)
        $path = Join-Path $TestDrive ('CHANGELOG-{0}.md' -f [guid]::NewGuid())
        Set-Content -LiteralPath $path -Value $Content -Encoding utf8 -NoNewline
        $path
    }
}

Describe 'Changelog - Get-ChangelogRelease reads the topmost released section' {

    BeforeAll {
        $script:Release = Get-ChangelogRelease -Path (New-ChangelogFile -Content $script:Sample)
    }

    It 'returns the version of the first released section, not Unreleased' {
        $script:Release.Version | Should -BeExactly '0.8.0'
    }

    It 'derives the tag as v<version>' {
        $script:Release.Tag | Should -BeExactly 'v0.8.0'
    }

    It 'returns the release date from the heading' {
        $script:Release.Date | Should -BeExactly '2026-08-29'
    }

    It 'returns the previous version so the compare link can be built' {
        $script:Release.PreviousTag | Should -BeExactly 'v0.7.1'
    }

    It 'returns the section body without its own heading' {
        $script:Release.Notes | Should -Not -Match '(?m)^## \[0\.8\.0\]'
        $script:Release.Notes | Should -Match '(?m)^### Added'
        $script:Release.Notes | Should -Match 'tests/Avm-Module-Pinning\.Tests\.ps1'
        $script:Release.Notes | Should -Match '(?m)^### Changed'
    }

    It 'stops the body at the next section' {
        $script:Release.Notes | Should -Not -Match '0\.7\.1'
        $script:Release.Notes | Should -Not -Match 'A fix that shipped'
    }

    It 'does not carry Unreleased content into the body' {
        $script:Release.Notes | Should -Not -Match 'Something not yet released'
    }

    It 'trims surrounding blank lines from the body' {
        $script:Release.Notes | Should -Not -Match '^\s'
        $script:Release.Notes | Should -Not -Match '\s$'
    }
}

Describe 'Changelog - Get-ChangelogRelease edge cases' {

    It 'returns no previous tag for the first release' {
        $content = @'
# Changelog

## [Unreleased]

## [0.1.0] - 2026-01-01

### Added

- First release.
'@
        $release = Get-ChangelogRelease -Path (New-ChangelogFile -Content $content)
        $release.Version     | Should -BeExactly '0.1.0'
        $release.PreviousTag | Should -BeNullOrEmpty
    }

    It 'throws when the file has no released section' {
        $content = @'
# Changelog

## [Unreleased]

### Added

- Not released.
'@
        { Get-ChangelogRelease -Path (New-ChangelogFile -Content $content) } |
            Should -Throw -ExpectedMessage '*no released section*'
    }

    It 'ignores a "## [" heading inside a fenced code block' {
        $content = @'
# Changelog

## [Unreleased]

```markdown
## [9.9.9] - 2099-01-01
```

## [0.2.0] - 2026-02-02

### Added

- Real release.
'@
        $release = Get-ChangelogRelease -Path (New-ChangelogFile -Content $content)
        $release.Version | Should -BeExactly '0.2.0'
    }
}

Describe 'Changelog - Get-ReleaseBody builds the GitHub Release body' {

    BeforeAll {
        $script:Release = Get-ChangelogRelease -Path (New-ChangelogFile -Content $script:Sample)
    }

    It 'starts with the CHANGELOG section body' {
        $notes = Get-ReleaseBody -Release $script:Release -Repository 'mbiszczanik/skycraft'
        $notes | Should -Match '^### Added'
    }

    It 'ends with the compare link the earlier releases carry' {
        $notes = Get-ReleaseBody -Release $script:Release -Repository 'mbiszczanik/skycraft'
        $notes | Should -Match '\*\*Full Changelog\*\*: https://github\.com/mbiszczanik/skycraft/compare/v0\.7\.1\.\.\.v0\.8\.0$'
    }

    It 'links to the commit list instead when there is no previous release' {
        $first = [pscustomobject]@{ Version = '0.1.0'; Tag = 'v0.1.0'; Date = '2026-01-01'; PreviousTag = $null; Notes = '### Added' }
        $notes = Get-ReleaseBody -Release $first -Repository 'mbiszczanik/skycraft'
        $notes | Should -Match '\*\*Full Changelog\*\*: https://github\.com/mbiszczanik/skycraft/commits/v0\.1\.0$'
    }
}

Describe 'Changelog - Publish-ChangelogRelease drives gh from the CHANGELOG head' {

    BeforeAll {
        $script:Path = New-ChangelogFile -Content $script:Sample

        # A fake `gh` that records every call and answers the release probe as told.
        # Returned as a factory so each It gets its own call log.
        function New-FakeGh {
            param([bool]$ReleaseExists, [int]$CreateExitCode = 0)
            $calls = [System.Collections.Generic.List[string[]]]::new()
            $gh = {
                param([string[]]$Arguments)
                $calls.Add($Arguments)
                switch ($Arguments[1]) {
                    'view'   { return [pscustomobject]@{ ExitCode = ($ReleaseExists ? 0 : 1); Output = ($ReleaseExists ? '{"tagName":"v0.8.0"}' : 'release not found') } }
                    'create' { return [pscustomobject]@{ ExitCode = $CreateExitCode; Output = ($CreateExitCode -eq 0 ? 'https://github.com/o/r/releases/tag/v0.8.0' : 'HTTP 422: Validation Failed') } }
                }
                throw "unexpected gh call: $($Arguments -join ' ')"
            }.GetNewClosure()
            [pscustomobject]@{ Command = $gh; Calls = $calls }
        }
    }

    It 'reports AlreadyPublished and creates nothing when the release exists' {
        $fake = New-FakeGh -ReleaseExists $true
        $result = Publish-ChangelogRelease -Path $script:Path -Repository 'o/r' -Target 'abc123' -GhCommand $fake.Command

        $result.Status | Should -BeExactly 'AlreadyPublished'
        $result.Tag    | Should -BeExactly 'v0.8.0'
        @($fake.Calls | Where-Object { $_[1] -eq 'create' }).Count | Should -Be 0
    }

    It 'probes the release by tag in the given repository' {
        $fake = New-FakeGh -ReleaseExists $true
        Publish-ChangelogRelease -Path $script:Path -Repository 'o/r' -Target 'abc123' -GhCommand $fake.Command | Out-Null

        $probe = @($fake.Calls | Where-Object { $_[1] -eq 'view' })
        $probe.Count | Should -Be 1
        $probe[0] | Should -Contain 'v0.8.0'
        ($probe[0] -join ' ') | Should -Match '--repo o/r'
    }

    It 'creates the release at the target commit with the tag as title and the CHANGELOG notes' {
        $fake = New-FakeGh -ReleaseExists $false
        $result = Publish-ChangelogRelease -Path $script:Path -Repository 'o/r' -Target 'abc123' -GhCommand $fake.Command

        $result.Status | Should -BeExactly 'Published'
        $result.Url    | Should -BeExactly 'https://github.com/o/r/releases/tag/v0.8.0'

        $create = @($fake.Calls | Where-Object { $_[1] -eq 'create' })
        $create.Count | Should -Be 1
        $arguments = $create[0]
        $arguments[2] | Should -BeExactly 'v0.8.0'
        $arguments[($arguments.IndexOf('--target') + 1)] | Should -BeExactly 'abc123'
        $arguments[($arguments.IndexOf('--title') + 1)]  | Should -BeExactly 'v0.8.0'
        ($arguments -join ' ') | Should -Match '--repo o/r'

        $notesFile = $arguments[($arguments.IndexOf('--notes-file') + 1)]
        $result.Notes | Should -BeExactly (Get-ReleaseBody -Release (Get-ChangelogRelease -Path $script:Path) -Repository 'o/r')
        $notesFile | Should -Not -BeNullOrEmpty
    }

    It 'creates nothing under -WhatIf' {
        $fake = New-FakeGh -ReleaseExists $false
        $result = Publish-ChangelogRelease -Path $script:Path -Repository 'o/r' -Target 'abc123' -GhCommand $fake.Command -WhatIf

        $result.Status | Should -BeExactly 'WhatIf'
        @($fake.Calls | Where-Object { $_[1] -eq 'create' }).Count | Should -Be 0
    }

    It 'throws with the gh output when the create fails' {
        $fake = New-FakeGh -ReleaseExists $false -CreateExitCode 1
        { Publish-ChangelogRelease -Path $script:Path -Repository 'o/r' -Target 'abc123' -GhCommand $fake.Command } |
            Should -Throw -ExpectedMessage '*HTTP 422*'
    }
}

Describe 'Changelog - ConvertTo-GitHubRepository reads owner/name from a remote URL' {

    It 'parses <url>' -ForEach @(
        @{ url = 'https://github.com/mbiszczanik/skycraft.git'; expected = 'mbiszczanik/skycraft' }
        @{ url = 'https://github.com/mbiszczanik/skycraft';     expected = 'mbiszczanik/skycraft' }
        @{ url = 'git@github.com:mbiszczanik/skycraft.git';     expected = 'mbiszczanik/skycraft' }
        @{ url = 'ssh://git@github.com/mbiszczanik/skycraft.git'; expected = 'mbiszczanik/skycraft' }
    ) {
        ConvertTo-GitHubRepository -RemoteUrl $url | Should -BeExactly $expected
    }

    It 'throws on a remote that is not GitHub' {
        { ConvertTo-GitHubRepository -RemoteUrl 'https://dev.azure.com/org/project/_git/repo' } |
            Should -Throw -ExpectedMessage '*not a GitHub remote*'
    }
}

Describe 'Changelog - tools/Publish-Release.ps1 wraps the module' {

    BeforeAll {
        $script:Script = Join-Path $script:RepoRoot 'tools/Publish-Release.ps1'
        $script:Path   = New-ChangelogFile -Content $script:Sample
    }

    It 'previews the release under -WhatIf without calling gh release create' {
        $calls = [System.Collections.Generic.List[string[]]]::new()
        $gh = { param([string[]]$Arguments) $calls.Add($Arguments); [pscustomobject]@{ ExitCode = 1; Output = 'not found' } }.GetNewClosure()

        $output = & $script:Script -Path $script:Path -Repository 'o/r' -Target 'abc123' -GhCommand $gh -WhatIf 6>&1 | Out-String

        $output | Should -Match 'v0\.8\.0'
        @($calls | Where-Object { $_[1] -eq 'create' }).Count | Should -Be 0
    }

    It 'prints the release URL when it publishes' {
        $gh = {
            param([string[]]$Arguments)
            if ($Arguments[1] -eq 'view') { return [pscustomobject]@{ ExitCode = 1; Output = 'not found' } }
            [pscustomobject]@{ ExitCode = 0; Output = 'https://github.com/o/r/releases/tag/v0.8.0' }
        }

        $output = & $script:Script -Path $script:Path -Repository 'o/r' -Target 'abc123' -GhCommand $gh 6>&1 | Out-String

        $output | Should -Match 'https://github\.com/o/r/releases/tag/v0\.8\.0'
    }
}

Describe 'Changelog - the repository CHANGELOG.md has a releasable head' {

    BeforeAll {
        $script:Actual = Get-ChangelogRelease -Path (Join-Path $script:RepoRoot 'CHANGELOG.md')
    }

    It 'resolves to an exact x.y.z version' {
        $script:Actual.Version | Should -Match '^\d+\.\d+\.\d+$'
    }

    It 'carries a date in ISO form' {
        $script:Actual.Date | Should -Match '^\d{4}-\d{2}-\d{2}$'
    }

    It 'has a non-empty body to publish as release notes' {
        $script:Actual.Notes | Should -Not -BeNullOrEmpty
    }
}
