<#
.SYNOPSIS
    Pester 5 tests for tools/Test-IdentifyingData.ps1 (issue #523).

.DESCRIPTION
    Runs the real script as a child process against fixture repositories: a finding outside the
    allowlist fails, an allowlisted value passes, an empty scan fails, an unlisted binary file
    fails, a malformed allowlist fails, and no failure line repeats the value it found. A last
    case runs the gate on this repository's tracked files.

.EXAMPLE
    Invoke-Pester -CI -Path .\tests\Test-IdentifyingData.Tests.ps1

.NOTES
    Project: SkyCraft
#>

#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    $script:Tool = Join-Path $script:RepoRoot 'tools' 'Test-IdentifyingData.ps1'
    $script:RealAllowlist = Join-Path $script:RepoRoot 'tools' 'identifying-data-allowlist.psd1'

    # A GUID and an address no allowlist entry covers, assembled so that this file holds neither.
    $script:UnknownGuid = ('3f2a9c10', '7b4d', '4e11', '9a05', 'c8d2e6f01b37') -join '-'
    $script:UnknownEmail = 'real.person' + '@' + 'contoso-real.net'
    $script:UserPath = 'C:' + '\Users\' + 'pat.sample' + '\repos'

    $script:Fixture = Join-Path ([System.IO.Path]::GetTempPath()) ('idcheck-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $script:Fixture | Out-Null

    # Writes a fixture folder with the given files and returns the run's exit code and output.
    function Invoke-Gate {
        param(
            [hashtable]$File = @{},
            [string]$Allowlist = $script:RealAllowlist,
            [byte[]]$Binary,
            [string]$BinaryName
        )
        $dir = Join-Path $script:Fixture ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $dir | Out-Null
        foreach ($name in $File.Keys) { Set-Content -LiteralPath (Join-Path $dir $name) -Value $File[$name] -NoNewline }
        if ($Binary) { [System.IO.File]::WriteAllBytes((Join-Path $dir $BinaryName), $Binary) }
        # A real repository, so the script reads its file list the way CI does.
        & git -C $dir init -q
        & git -C $dir add -A

        $output = & pwsh -NoProfile -File $script:Tool -RepoRoot $dir -AllowlistPath $Allowlist 2>&1 | Out-String
        [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = $output }
    }
}

AfterAll {
    Remove-Item -LiteralPath $script:Fixture -Recurse -Force -ErrorAction SilentlyContinue
}

Describe 'Test-IdentifyingData.ps1 - findings' {

    It 'passes on text that holds only allowlisted shapes' {
        $run = Invoke-Gate -File @{
            'a.md' = "Reader: acdd72a7-3385-48ef-bd42-f606fba81ae7`nzero: 00000000-0000-0000-0000-000000000000`nuser: jane@example.com, ops@x.example`n"
        }
        $run.ExitCode | Should -Be 0 -Because $run.Output
        $run.Output | Should -Match '1 text file\(s\) scanned'
    }

    It 'fails on a GUID that is not allowlisted' {
        $run = Invoke-Gate -File @{ 'a.md' = "tenant $($script:UnknownGuid)`n" }
        $run.ExitCode | Should -Be 1
        $run.Output | Should -Match 'a\.md:1: GUID'
    }

    It 'fails on an e-mail address that is not allowlisted' {
        $run = Invoke-Gate -File @{ 'a.md' = "mail $($script:UnknownEmail)`n" }
        $run.ExitCode | Should -Be 1
        $run.Output | Should -Match 'a\.md:1: E-mail'
    }

    It 'fails on a Windows path with a user name' {
        $run = Invoke-Gate -File @{ 'a.ps1' = "`$p = '$($script:UserPath)'`n" }
        $run.ExitCode | Should -Be 1
        $run.Output | Should -Match 'a\.ps1:1: User path'
    }

    It 'does not repeat the value it found, only a masked form' {
        $run = Invoke-Gate -File @{ 'a.md' = "tenant $($script:UnknownGuid) mail $($script:UnknownEmail) path $($script:UserPath)`n" }
        $run.ExitCode | Should -Be 1
        $run.Output | Should -Not -Match ([regex]::Escape($script:UnknownGuid))
        $run.Output | Should -Not -Match ([regex]::Escape($script:UnknownEmail))
        $run.Output | Should -Not -Match 'pat.sample'
    }

    It 'reports every finding, not only the first' {
        $run = Invoke-Gate -File @{ 'a.md' = "$($script:UnknownGuid)`n$($script:UnknownEmail)`n" }
        $run.Output | Should -Match '2 finding\(s\)'
    }
}

Describe 'Test-IdentifyingData.ps1 - a check that did not run is not a pass' {

    It 'fails when it scanned no text file' {
        $run = Invoke-Gate -File @{}
        $run.ExitCode | Should -Be 1
        $run.Output | Should -Match 'No text file was scanned'
    }

    It 'fails on a binary file whose extension is not on the allowlist' {
        $run = Invoke-Gate -File @{ 'a.md' = "clean`n" } -Binary ([byte[]](1, 0, 2, 0)) -BinaryName 'data.bin'
        $run.ExitCode | Should -Be 1
        $run.Output | Should -Match "Binary file 'data\.bin' was not scanned"
    }

    It 'counts a binary file with an allowlisted extension and still passes' {
        $run = Invoke-Gate -File @{ 'a.md' = "clean`n" } -Binary ([byte[]](137, 80, 0, 71)) -BinaryName 'shot.png'
        $run.ExitCode | Should -Be 0 -Because $run.Output
        $run.Output | Should -Match '1 allowlisted binary file'
    }

    It 'fails when the allowlist does not exist' {
        $run = Invoke-Gate -File @{ 'a.md' = "clean`n" } -Allowlist (Join-Path $script:Fixture 'nope.psd1')
        $run.ExitCode | Should -Be 1
        $run.Output | Should -Match 'does not exist'
    }

    It 'fails when an allowlist entry has no reason' {
        $bad = Join-Path $script:Fixture 'noreason.psd1'
        Set-Content -LiteralPath $bad -Value @'
@{
    GuidValue = @( @{ Value = '3f2a9c10-7b4d-4e11-9a05-c8d2e6f01b37'; Reason = '' } )
    GuidPattern = @()
    EmailValue = @()
    EmailDomain = @()
    UserPathName = @()
    BinaryExtension = @()
}
'@
        $run = Invoke-Gate -File @{ 'a.md' = "clean`n" } -Allowlist $bad
        $run.ExitCode | Should -Be 1
        $run.Output | Should -Match 'without a value or without a reason'
    }

    It 'fails when an allowlist section is missing' {
        $bad = Join-Path $script:Fixture 'nosection.psd1'
        Set-Content -LiteralPath $bad -Value "@{ GuidValue = @() }"
        $run = Invoke-Gate -File @{ 'a.md' = "clean`n" } -Allowlist $bad
        $run.ExitCode | Should -Be 1
        $run.Output | Should -Match "section 'EmailDomain' is missing"
    }
}

Describe 'Test-IdentifyingData.ps1 - the real allowlist' {

    It 'gives every entry a reason' {
        $list = Import-PowerShellDataFile -LiteralPath $script:RealAllowlist
        foreach ($section in $list.Keys) {
            foreach ($entry in @($list[$section])) {
                "$($entry.Reason)".Trim() | Should -Not -BeNullOrEmpty -Because "$section entry '$($entry.Value)' needs a reason"
            }
        }
    }

    It 'passes on this repository''s tracked files' {
        $output = & pwsh -NoProfile -File $script:Tool -RepoRoot $script:RepoRoot 2>&1 | Out-String
        $LASTEXITCODE | Should -Be 0 -Because $output
        $output | Should -Match 'Identifying-data check passed'
    }
}
