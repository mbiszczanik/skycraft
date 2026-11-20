<#
.SYNOPSIS
    Pester 5 test: tools/Invoke-DryRun.ps1 -Check Parse gates on the files it finds.

.DESCRIPTION
    Regression guard for issue #559. The Parse check kept $failures empty when file discovery
    returned nothing, so a broken discovery reported success. This file holds the Parse check
    to the same contract as the Pester check (tests/DryRun-Pester-Gate.Tests.ps1):
      - an empty discovery fails the gate and names the root it searched;
      - a file that does not parse fails the gate and names the file and line;
      - a root holding a valid file passes.

    The harness is launched in a child pwsh because the caller-visible fact is its exit code.

.EXAMPLE
    Invoke-Pester -Path .\tests\DryRun-Parse-Gate.Tests.ps1

.NOTES
    Project: SkyCraft
#>

#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

Describe 'SkyCraft dry run - the Parse check gates on the files it finds' {

    BeforeAll {
        $script:Pwsh    = (Get-Process -Id $PID).Path
        $script:Harness = (Resolve-Path (Join-Path $PSScriptRoot '../tools/Invoke-DryRun.ps1')).Path

        function Initialize-FixtureRoot {
            param([hashtable]$File = @{})

            $root = Join-Path $TestDrive ('root-{0}' -f [guid]::NewGuid().ToString('n'))
            New-Item -ItemType Directory -Path $root -Force | Out-Null
            foreach ($name in $File.Keys) {
                $File[$name] | Set-Content -LiteralPath (Join-Path $root $name) -Encoding utf8
            }

            return $root
        }

        function Invoke-HarnessParseCheck {
            param([string]$Root)

            $output = & $script:Pwsh -NoProfile -File $script:Harness -RepoRoot $Root -Check Parse 2>&1 | Out-String
            [PSCustomObject]@{ ExitCode = $LASTEXITCODE; Output = $output }
        }
    }

    It 'exits 1 and names the searched root when no PowerShell file is discovered' {
        $root = Initialize-FixtureRoot
        $run = Invoke-HarnessParseCheck -Root $root
        $run.ExitCode | Should -Be 1 -Because $run.Output
        $run.Output   | Should -Match '(?m)^Parse:' -Because 'the failure must be attributed to the Parse check in the summary'
        $run.Output   | Should -Match ([regex]::Escape((Split-Path -Leaf $root))) -Because 'the message must name the root it searched'
    }

    It 'exits 1 and names the file and line when a file does not parse' {
        $root = Initialize-FixtureRoot -File @{ 'Broken.ps1' = 'function Broken { if (' }
        $run = Invoke-HarnessParseCheck -Root $root
        $run.ExitCode | Should -Be 1 -Because $run.Output
        $run.Output   | Should -Match 'Broken\.ps1:1:' -Because 'the failure must name the file and line'
    }

    It 'exits 0 when the root holds one valid file' {
        $root = Initialize-FixtureRoot -File @{ 'Valid.ps1' = 'function Valid { 1 }' }
        $run = Invoke-HarnessParseCheck -Root $root
        $run.ExitCode | Should -Be 0 -Because $run.Output
    }
}
