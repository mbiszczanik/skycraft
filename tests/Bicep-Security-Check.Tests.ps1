<#
.SYNOPSIS
    Pester 5 tests for tools/Invoke-BicepSecurityCheck.ps1 (issue #522).

.DESCRIPTION
    Runs the real script as a child process against fixture repositories. The cases that need
    PSRule for Azure and the Bicep CLI are skipped, with the reason shown, on a machine that
    lacks either; CI installs both and runs the gate itself in the 'Bicep Security' job, so a
    skip here never stands for a pass of the gate. Cases that need neither always run: a
    malformed baseline, a missing module and an empty file list all fail.

.EXAMPLE
    Invoke-Pester -CI -Path .\tests\Bicep-Security-Check.Tests.ps1

.NOTES
    Project: SkyCraft
#>

#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeDiscovery {
    $hasPSRule = [bool](Get-Module -ListAvailable -Name PSRule.Rules.Azure |
            Where-Object { $_.Version -ge [version]'1.47.0' -and $_.Version -le [version]'1.47.99' })
    $hasBicep = [bool](Get-Command bicep -ErrorAction SilentlyContinue)
    $script:CanAnalyse = $hasPSRule -and $hasBicep
    $script:SkipReason = if ($script:CanAnalyse) { '' } else { 'PSRule.Rules.Azure 1.47.x or the Bicep CLI is not installed here; CI runs the gate itself' }
}

BeforeAll {
    # BeforeDiscovery variables do not exist at run time: decide again.
    $script:CanAnalyse = [bool](Get-Module -ListAvailable -Name PSRule.Rules.Azure |
            Where-Object { $_.Version -ge [version]'1.47.0' -and $_.Version -le [version]'1.47.99' }) -and
        [bool](Get-Command bicep -ErrorAction SilentlyContinue)
    $script:RepoRoot =(Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    $script:Tool = Join-Path $script:RepoRoot 'tools' 'Invoke-BicepSecurityCheck.ps1'
    $script:Fixture = Join-Path ([System.IO.Path]::GetTempPath()) ('bicepsec-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $script:Fixture | Out-Null

    $script:EmptyBaseline = Join-Path $script:Fixture 'empty.psd1'
    Set-Content -LiteralPath $script:EmptyBaseline -Value "@{ Finding = @(); Unanalysable = @() }"

    # A storage account with weak settings, deployed through a parameter file.
    $script:WeakBicep = @'
param parName string
resource sa 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: parName
  location: 'swedencentral'
  kind: 'StorageV2'
  sku: { name: 'Standard_LRS' }
  properties: {
    allowBlobPublicAccess: true
    minimumTlsVersion: 'TLS1_0'
    supportsHttpsTrafficOnly: false
  }
}
'@
    $script:WeakParam = "using './main.bicep'`nparam parName = 'fixturestorage001'`n"

    function Initialize-FixtureRepo {
        param([hashtable]$File = @{})
        $dir = Join-Path $script:Fixture ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $dir | Out-Null
        foreach ($name in $File.Keys) {
            $target = Join-Path $dir $name
            New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force | Out-Null
            Set-Content -LiteralPath $target -Value $File[$name] -NoNewline
        }
        & git -C $dir init -q
        & git -C $dir add -A 2> $null
        return $dir
    }

    function Invoke-Gate {
        param([string]$Repo, [string]$Baseline = $script:EmptyBaseline)
        $output = & pwsh -NoProfile -File $script:Tool -RepoRoot $Repo -BaselinePath $Baseline 2>&1 | Out-String
        [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = $output }
    }
}

AfterAll {
    Remove-Item -LiteralPath $script:Fixture -Recurse -Force -ErrorAction SilentlyContinue
}

Describe 'Invoke-BicepSecurityCheck.ps1 - a check that did not run is not a pass' {

    It 'fails when the baseline does not exist' {
        $repo = Initialize-FixtureRepo -File @{ 'a.txt' = 'x' }
        $run = Invoke-Gate -Repo $repo -Baseline (Join-Path $script:Fixture 'nope.psd1')
        $run.ExitCode | Should -Be 1
        $run.Output | Should -Match 'does not exist'
    }

    It 'fails when a baseline entry has no reason' {
        $bad = Join-Path $script:Fixture 'noreason.psd1'
        Set-Content -LiteralPath $bad -Value "@{ Finding = @( @{ File = 'a.bicepparam'; Rule = 'Azure.X.Y'; Reason = '' } ); Unanalysable = @() }"
        $run = Invoke-Gate -Repo (Initialize-FixtureRepo -File @{ 'a.txt' = 'x' }) -Baseline $bad
        $run.ExitCode | Should -Be 1
        $run.Output | Should -Match "'Finding' entry has no Reason"
    }

    It 'fails when a baseline section is missing' {
        $bad = Join-Path $script:Fixture 'nosection.psd1'
        Set-Content -LiteralPath $bad -Value "@{ Finding = @() }"
        $run = Invoke-Gate -Repo (Initialize-FixtureRepo -File @{ 'a.txt' = 'x' }) -Baseline $bad
        $run.ExitCode | Should -Be 1
        $run.Output | Should -Match "section 'Unanalysable' is missing"
    }

    It 'fails when PSRule for Azure is not installed, instead of analysing nothing' {
        $repo = Initialize-FixtureRepo -File @{ 'a.txt' = 'x' }
        $output = & pwsh -NoProfile -File $script:Tool -RepoRoot $repo -BaselinePath $script:EmptyBaseline -ModuleName 'PSRule.Rules.DoesNotExist' 2>&1 | Out-String
        $run = [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = $output }
        $run.ExitCode | Should -Be 1
        $run.Output | Should -Match 'is not installed, so nothing was analysed'
    }

    It 'fails when the repository holds no Bicep file at all' -Skip:(-not $script:CanAnalyse) {
        $run = Invoke-Gate -Repo (Initialize-FixtureRepo -File @{ 'a.txt' = 'x' })
        $run.ExitCode | Should -Be 1
        $run.Output | Should -Match 'PSRule analysed no file'
    }
}

Describe 'Invoke-BicepSecurityCheck.ps1 - findings against the baseline' {

    BeforeAll {
        if ($script:CanAnalyse) {
            $script:WeakRepo = Initialize-FixtureRepo -File @{ 'bicep/main.bicep' = $script:WeakBicep; 'bicep/main.bicepparam' = $script:WeakParam }
            $script:NewFinding = Invoke-Gate -Repo $script:WeakRepo
        }
    }

    It 'fails on a finding the baseline does not hold, naming the file and the rule' -Skip:(-not $script:CanAnalyse) {
        $script:NewFinding.ExitCode | Should -Be 1 -Because $script:NewFinding.Output
        $script:NewFinding.Output | Should -Match 'bicep/main\.bicepparam: rule Azure\.Storage\.[A-Za-z]+ reports a finding'
    }

    It 'passes when every reported pair is in the baseline' -Skip:(-not $script:CanAnalyse) {
        $rules = @([regex]::Matches($script:NewFinding.Output, 'rule (Azure\.[A-Za-z0-9.]+) reports') | ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique)
        $rules.Count | Should -BeGreaterThan 0
        $entries = ($rules | ForEach-Object { "@{ File = 'bicep/main.bicepparam'; Rule = '$_'; Reason = 'fixture' }" }) -join "`n"
        $baseline = Join-Path $script:Fixture 'weak-baseline.psd1'
        Set-Content -LiteralPath $baseline -Value "@{ Finding = @($entries); Unanalysable = @() }"
        $run = Invoke-Gate -Repo $script:WeakRepo -Baseline $baseline
        $run.ExitCode | Should -Be 0 -Because $run.Output
        $run.Output | Should -Match '0 outside the baseline'
    }
}

Describe 'Invoke-BicepSecurityCheck.ps1 - the repository' {

    It 'gives every baseline entry a reason' {
        $baseline = Import-PowerShellDataFile -LiteralPath (Join-Path $script:RepoRoot 'tools' 'bicep-security-baseline.psd1')
        foreach ($entry in @($baseline.Finding) + @($baseline.Unanalysable)) {
            "$($entry.Reason)".Trim() | Should -Not -BeNullOrEmpty -Because "$($entry.File) needs a reason"
        }
    }

    It 'passes on this repository''s Bicep files' -Skip:(-not $script:CanAnalyse) {
        $output = & pwsh -NoProfile -File $script:Tool -RepoRoot $script:RepoRoot 2>&1 | Out-String
        $LASTEXITCODE | Should -Be 0 -Because $output
        $output | Should -Match 'Bicep security check passed'
    }
}
