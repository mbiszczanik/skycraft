BeforeAll {
    $script:Gate = Join-Path $PSScriptRoot '../tools/Test-PrAcceptanceEvidence.ps1'
    $script:Paths = @('module-3-compute/3.4-app-service/lab-guide-3.4.md')
    # Synthetic evidence; child processes run only the PR gate.
    $script:Record = @'
Test-conditions: existing Free Trial, Sweden Central, Contributor, lab prerequisites retained
Acceptance-head: 0123456789abcdef
Scripted-check: 2026-11-02 Check-Fixture.ps1, 8 expected, 8 observed, exit 0
Portal-check: 2026-11-02 steps 1-3, expected plan visible, observed plan visible
Negative-check: 2026-11-02 denied request, expected exit 1, observed exit 1
Missing-result-check: 2026-11-02 empty response, expected FAIL, observed FAIL
Fallback-deploy: not-applicable: this change introduces no alternative SKU
'@
    . $script:Gate
}

Describe 'PR acceptance evidence completeness' {
    It 'accepts a complete record' {
        (Get-PrAcceptanceVerdict -ChangedFile $script:Paths -Body $script:Record).Pass | Should -BeTrue
    }

    It 'does not gate docs and test-only changes' {
        (Get-PrAcceptanceVerdict -ChangedFile @('docs/lab-acceptance.md', 'module-3-compute/3.4-app-service/tests/Test-Lab.Tests.ps1') -Body '').Pass | Should -BeTrue
    }

    It 'rejects an absent <field>' -ForEach @(
        @{ field = 'Test-conditions' }, @{ field = 'Acceptance-head' },
        @{ field = 'Scripted-check' }, @{ field = 'Portal-check' },
        @{ field = 'Negative-check' }, @{ field = 'Missing-result-check' },
        @{ field = 'Fallback-deploy' }
    ) {
        $body = $script:Record -replace "(?m)^${field}:.*\r?\n?", ''
        $v = Get-PrAcceptanceVerdict -ChangedFile $script:Paths -Body $body
        $v.Pass | Should -BeFalse
        $v.Reason | Should -Match $field
    }

    It 'rejects a placeholder <value>' -ForEach @(
        @{ value = '' }, @{ value = 'TBD' }, @{ value = '**none**' },
        @{ value = '<command, result>' }, @{ value = 'N/A' },
        @{ value = 'not-applicable:' }, @{ value = 'not-applicable: TBD' }
        @{ value = 'TBD.' }, @{ value = 'N/A.' }, @{ value = [string][char]0x2026 }
    ) {
        $body = $script:Record -replace '(?m)^Portal-check:.*', "Portal-check: $value"
        (Get-PrAcceptanceVerdict -ChangedFile $script:Paths -Body $body).Pass | Should -BeFalse
    }

    It 'rejects duplicate fields even if one is complete' {
        (Get-PrAcceptanceVerdict -ChangedFile $script:Paths -Body ($script:Record + "`nPortal-check: a second claim")).Pass | Should -BeFalse
    }

    It 'does not accept a record hidden in a template comment or code example' {
        foreach ($body in @("<!--`n$script:Record`n-->", ('```text' + "`n$script:Record`n" + '```'),
            ('```text' + "`n$script:Record"), ('```text' + "`n$script:Record`n" + '````'))) {
            (Get-PrAcceptanceVerdict -ChangedFile $script:Paths -Body $body).Pass | Should -BeFalse
        }
    }

    It 'allows an explicit blocked check with a tracking issue' {
        $body = $script:Record -replace '(?m)^Portal-check:.*', 'Portal-check: blocked: new subscription needed, tracked in #402'
        (Get-PrAcceptanceVerdict -ChangedFile $script:Paths -Body $body).Pass | Should -BeTrue
    }

    It 'does not count indented Markdown code as evidence' {
        foreach ($indent in @('    ', "`t")) {
            $body = ($script:Record -split "`n" | ForEach-Object { $indent + $_ }) -join "`n"
            (Get-PrAcceptanceVerdict -ChangedFile $script:Paths -Body $body).Pass | Should -BeFalse
        }
    }

    It 'exits zero for a complete record loaded from files' {
        $bodyFile = Join-Path $TestDrive 'body.md'
        $pathsFile = Join-Path $TestDrive 'paths.txt'
        $script:Record | Set-Content -LiteralPath $bodyFile
        $script:Paths | Set-Content -LiteralPath $pathsFile
        & pwsh -NoProfile -File $script:Gate -BodyPath $bodyFile -ChangedFilePath $pathsFile *> $null
        $LASTEXITCODE | Should -Be 0
    }

    It 'rejects an untracked blocked check' {
        $body = $script:Record -replace '(?m)^Portal-check:.*', 'Portal-check: blocked: new subscription needed'
        (Get-PrAcceptanceVerdict -ChangedFile $script:Paths -Body $body).Pass | Should -BeFalse
    }

    It 'rejects a closing keyword when acceptance evidence is blocked' {
        $body = ($script:Record -replace '(?m)^Portal-check:.*', 'Portal-check: blocked: new subscription needed, tracked in #402') + "`nCloses #402"
        (Get-PrAcceptanceVerdict -ChangedFile $script:Paths -Body $body).Pass | Should -BeFalse
    }

    It 'exits nonzero for missing evidence through the CLI' {
        & pwsh -NoProfile -File $script:Gate -ChangedFile $script:Paths[0] -Body 'Live-verified: run 1' *> $null
        $LASTEXITCODE | Should -Be 1
    }
}

Describe 'Acceptance-head against the PR head' {
    BeforeAll {
        $script:Head = '0123456789abcdef0123456789abcdef01234567'
    }

    It 'accepts a head that is a prefix of the PR head' {
        (Get-PrAcceptanceVerdict -ChangedFile $script:Paths -Body $script:Record -HeadSha $script:Head).Pass | Should -BeTrue
    }

    It 'rejects a stale commit with no explanation and names the entry' {
        $v = Get-PrAcceptanceVerdict -ChangedFile $script:Paths -Body $script:Record -HeadSha 'fedcba9876543210fedcba9876543210fedcba98'
        $v.Pass | Should -BeFalse
        $v.Reason | Should -Match 'Acceptance-head 0123456789abcdef is not the PR head fedcba987654'
    }

    It 'accepts a stale commit that explains the later changes' {
        $body = $script:Record -replace '(?m)^Acceptance-head:.*', 'Acceptance-head: 0123456789abcdef, later changes: only the PR text and a comment'
        (Get-PrAcceptanceVerdict -ChangedFile $script:Paths -Body $body -HeadSha 'fedcba9876543210fedcba9876543210fedcba98').Pass | Should -BeTrue
    }

    It 'rejects a stale commit whose later-changes note is a placeholder: <note> (review finding)' -ForEach @(
        @{ note = '<why they cannot affect the result>' }, @{ note = 'TBD' }, @{ note = 'todo' }, @{ note = 'n/a' },
        @{ note = 'none' }, @{ note = '...' }, @{ note = '' }
    ) {
        $body = $script:Record -replace '(?m)^Acceptance-head:.*', "Acceptance-head: 0123456789abcdef, later changes: $note"
        $v = Get-PrAcceptanceVerdict -ChangedFile $script:Paths -Body $body -HeadSha 'fedcba9876543210fedcba9876543210fedcba98'
        $v.Pass | Should -BeFalse
        $v.Reason | Should -Match 'Acceptance-head 0123456789abcdef is not the PR head'
    }

    It 'rejects an entry that names no commit' {
        $body = $script:Record -replace '(?m)^Acceptance-head:.*', 'Acceptance-head: the current branch'
        $v = Get-PrAcceptanceVerdict -ChangedFile $script:Paths -Body $body -HeadSha $script:Head
        $v.Pass | Should -BeFalse
        $v.Reason | Should -Match 'names no commit'
    }

    It 'does not compare an entry marked not-applicable with a reason' {
        $body = $script:Record -replace '(?m)^Acceptance-head:.*', 'Acceptance-head: not-applicable: documentation change, nothing was tested'
        (Get-PrAcceptanceVerdict -ChangedFile $script:Paths -Body $body -HeadSha $script:Head).Pass | Should -BeTrue
    }

    It 'does not compare the commit when no head is given' {
        $body = $script:Record -replace '(?m)^Acceptance-head:.*', 'Acceptance-head: the current branch'
        (Get-PrAcceptanceVerdict -ChangedFile $script:Paths -Body $body).Pass | Should -BeTrue
    }

    It 'exits nonzero through the CLI for a stale commit and zero for the matching head' {
        $bodyFile = Join-Path $TestDrive 'head-body.md'
        $pathsFile = Join-Path $TestDrive 'head-paths.txt'
        $script:Record | Set-Content -LiteralPath $bodyFile
        $script:Paths | Set-Content -LiteralPath $pathsFile
        & pwsh -NoProfile -File $script:Gate -BodyPath $bodyFile -ChangedFilePath $pathsFile -HeadSha 'fedcba9876543210fedcba9876543210fedcba98' *> $null
        $LASTEXITCODE | Should -Be 1
        & pwsh -NoProfile -File $script:Gate -BodyPath $bodyFile -ChangedFilePath $pathsFile -HeadSha $script:Head *> $null
        $LASTEXITCODE | Should -Be 0
    }

    It 'does not look at the commit of an ungated change' {
        (Get-PrAcceptanceVerdict -ChangedFile @('docs/lab-acceptance.md') -Body '' -HeadSha $script:Head).Pass | Should -BeTrue
    }
}
