<#
.SYNOPSIS
    Pester 5 tests for tools/Test-LabConsistency.ps1 (issues #363, #364, #362).

.DESCRIPTION
    Runs the real script as a child process against fixture repositories: a validator that
    compares a property with -eq $false, a guide whose Prerequisites miss a manifest dependency,
    a guide without a Prerequisites or a Leaves Behind section each fail; an allowlisted finding
    passes; a stale allowlist entry, a reasonless entry and an empty repository fail; and the
    repository itself passes.

.EXAMPLE
    Invoke-Pester -CI -Path .\tests\Lab-Consistency.Tests.ps1

.NOTES
    Project: SkyCraft
#>

#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    $script:Tool = Join-Path $script:RepoRoot 'tools' 'Test-LabConsistency.ps1'
    $script:Fixture = Join-Path ([System.IO.Path]::GetTempPath()) ('labcons-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $script:Fixture | Out-Null

    $script:EmptyAllowlist = Join-Path $script:Fixture 'empty.psd1'
    Set-Content -LiteralPath $script:EmptyAllowlist -Value '@{ Allow = @() }'

    $script:GoodGuide = @'
# Lab 1.2

## Prerequisites

- Lab 1.1 is done.

## Steps

## What This Lab Leaves Behind

Nothing.
'@
    $script:GoodValidator = 'if (-not $sa.AllowBlobPublicAccess) { "ok" }'

    function Initialize-LabFixture {
        param([string]$Guide = $script:GoodGuide, [string]$Validator = $script:GoodValidator, [string]$Manifest, [switch]$NoLab)
        $dir = Join-Path $script:Fixture ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path (Join-Path $dir 'tools') | Out-Null
        if (-not $Manifest) { $Manifest = "@{ Phases = @( @{ Id = '1.2'; Lab = 'module-1-x/1.2-a'; DependsOn = @('1.1') } ) }" }
        Set-Content -LiteralPath (Join-Path $dir 'tools' 'lab-cycle-manifest.psd1') -Value $Manifest
        if (-not $NoLab) {
            $lab = Join-Path $dir 'module-1-x' '1.2-a'
            New-Item -ItemType Directory -Path (Join-Path $lab 'scripts') -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $lab 'lab-guide-1.2.md') -Value $Guide
            Set-Content -LiteralPath (Join-Path $lab 'scripts' 'Test-Lab.ps1') -Value $Validator
        }
        return $dir
    }

    function Invoke-Gate {
        param([string]$Repo, [string]$Allowlist = $script:EmptyAllowlist)
        $output = & pwsh -NoProfile -File $script:Tool -RepoRoot $Repo -AllowlistPath $Allowlist 2>&1 | Out-String
        [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = $output }
    }
}

AfterAll {
    Remove-Item -LiteralPath $script:Fixture -Recurse -Force -ErrorAction SilentlyContinue
}

Describe 'Test-LabConsistency.ps1 - findings' {

    It 'passes on a lab whose guide, validator and manifest agree' {
        $run = Invoke-Gate -Repo (Initialize-LabFixture)
        $run.ExitCode | Should -Be 0 -Because $run.Output
        $run.Output | Should -Match '1 guide\(s\), 1 validator\(s\), 1 manifest phase\(s\); 0 finding'
    }

    It 'fails on a validator that compares a property with -eq $false' {
        $run = Invoke-Gate -Repo (Initialize-LabFixture -Validator 'if ($sa.AllowBlobPublicAccess -eq $false) { "ok" }')
        $run.ExitCode | Should -Be 1
        $run.Output | Should -Match '\[NullUnsafeComparison\].*Test-Lab\.ps1'
    }

    It 'fails on a validator that compares a property with -ne $false' {
        $run = Invoke-Gate -Repo (Initialize-LabFixture -Validator 'if ($x.Enabled -ne $false) { "ok" }')
        $run.ExitCode | Should -Be 1
        $run.Output | Should -Match '\[NullUnsafeComparison\]'
    }

    It 'does not flag -eq $true or a plain variable' {
        $run = Invoke-Gate -Repo (Initialize-LabFixture -Validator 'if ($x.Enabled -eq $true -or $flag -eq $false) { "ok" }')
        $run.ExitCode | Should -Be 0 -Because $run.Output
    }

    It 'fails when the Prerequisites section does not name a manifest dependency' {
        $guide = $script:GoodGuide -replace 'Lab 1\.1 is done\.', 'Nothing else is needed.'
        $run = Invoke-Gate -Repo (Initialize-LabFixture -Guide $guide)
        $run.ExitCode | Should -Be 1
        $run.Output | Should -Match '\[PrerequisiteEdges\].*depend on Lab 1\.1'
    }

    It 'fails when the guide has no Prerequisites section at all' {
        $guide = $script:GoodGuide -replace '(?s)## Prerequisites.*?(?=## Steps)', ''
        $run = Invoke-Gate -Repo (Initialize-LabFixture -Guide $guide)
        $run.ExitCode | Should -Be 1
        $run.Output | Should -Match 'no Prerequisites section'
    }

    It 'fails when the guide has no Leaves Behind section' {
        $guide = $script:GoodGuide -replace '(?s)## What This Lab Leaves Behind.*', ''
        $run = Invoke-Gate -Repo (Initialize-LabFixture -Guide $guide)
        $run.ExitCode | Should -Be 1
        $run.Output | Should -Match '\[LeavesBehindSection\]'
    }
}

Describe 'Test-LabConsistency.ps1 - the allowlist' {

    BeforeAll {
        $script:Weak = 'if ($sa.AllowBlobPublicAccess -eq $false) { "ok" }'
        $script:WeakFile = 'module-1-x/1.2-a/scripts/Test-Lab.ps1'
    }

    It 'lets an allowlisted finding pass' {
        $list = Join-Path $script:Fixture 'allow.psd1'
        Set-Content -LiteralPath $list -Value "@{ Allow = @( @{ Check = 'NullUnsafeComparison'; File = '$script:WeakFile'; Match = '`$sa.AllowBlobPublicAccess -eq `$false'; Reason = 'fixture' } ) }"
        $run = Invoke-Gate -Repo (Initialize-LabFixture -Validator $script:Weak) -Allowlist $list
        $run.ExitCode | Should -Be 0 -Because $run.Output
        $run.Output | Should -Match '1 finding\(s\), 0 not allowlisted'
    }

    It 'fails on an entry that matches no finding any more' {
        $list = Join-Path $script:Fixture 'stale.psd1'
        Set-Content -LiteralPath $list -Value "@{ Allow = @( @{ Check = 'NullUnsafeComparison'; File = '$script:WeakFile'; Match = 'gone'; Reason = 'fixture' } ) }"
        $run = Invoke-Gate -Repo (Initialize-LabFixture) -Allowlist $list
        $run.ExitCode | Should -Be 1
        $run.Output | Should -Match 'matches no finding any more'
    }

    It 'fails on an entry without a reason' {
        $list = Join-Path $script:Fixture 'noreason.psd1'
        Set-Content -LiteralPath $list -Value "@{ Allow = @( @{ Check = 'NullUnsafeComparison'; File = 'a'; Match = 'b'; Reason = '' } ) }"
        $run = Invoke-Gate -Repo (Initialize-LabFixture) -Allowlist $list
        $run.ExitCode | Should -Be 1
        $run.Output | Should -Match 'has no Reason'
    }

    It 'fails when the allowlist does not exist' {
        $run = Invoke-Gate -Repo (Initialize-LabFixture) -Allowlist (Join-Path $script:Fixture 'nope.psd1')
        $run.ExitCode | Should -Be 1
        $run.Output | Should -Match 'does not exist'
    }
}

Describe 'Test-LabConsistency.ps1 - a check that did not run is not a pass' {

    It 'fails when the repository holds no lab at all' {
        $run = Invoke-Gate -Repo (Initialize-LabFixture -NoLab)
        $run.ExitCode | Should -Be 1
        $run.Output | Should -Match 'Found no guide, no validator'
    }

    It 'fails when the manifest is missing' {
        $dir = Initialize-LabFixture
        Remove-Item -LiteralPath (Join-Path $dir 'tools' 'lab-cycle-manifest.psd1')
        $run = Invoke-Gate -Repo $dir
        $run.ExitCode | Should -Be 1
        $run.Output | Should -Match 'manifest .* does not exist'
    }
}

Describe 'Test-LabConsistency.ps1 - the repository' {

    It 'passes on this repository' {
        $output = & pwsh -NoProfile -File $script:Tool -RepoRoot $script:RepoRoot 2>&1 | Out-String
        $LASTEXITCODE | Should -Be 0 -Because $output
        $output | Should -Match 'Lab consistency check passed'
    }

    It 'gives every allowlist entry a reason' {
        $list = Import-PowerShellDataFile -LiteralPath (Join-Path $script:RepoRoot 'tools' 'lab-consistency-allowlist.psd1')
        foreach ($entry in @($list.Allow)) { "$($entry.Reason)".Trim() | Should -Not -BeNullOrEmpty -Because "$($entry.File) needs a reason" }
    }
}
