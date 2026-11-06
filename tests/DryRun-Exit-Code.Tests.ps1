<#
.SYNOPSIS
    Pester 5 test: tools/Invoke-DryRun.ps1 returns 0 after a passing run whatever exit code a child left behind (#472).

.DESCRIPTION
    An in-process suite that ends with $Host.SetShouldExit(n) pins the host's exit code to n, and a
    later plain `exit 0` does not override it. On 2026-11-01 a dry run with every check passing
    printed "Dry run passed." and returned 5. The cases run the real launcher in a child pwsh over
    a one-file fixture repository with only the Parse check, so they need neither Azure nor the
    full suite:
      - a passing run returns 0 when the host code was set to 5 first;
      - the same run returns 0 when started directly;
      - a failing run (a script that does not parse) returns a nonzero code, also when the host
        code was set to 0 first.

.EXAMPLE
    Invoke-Pester -Path .\tests\DryRun-Exit-Code.Tests.ps1

.NOTES
    Project: SkyCraft
    Issue: #472
#>

#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    $script:Harness = (Resolve-Path (Join-Path $PSScriptRoot '..' 'tools' 'Invoke-DryRun.ps1')).Path
    $script:Pwsh    = (Get-Process -Id $PID).Path

    $script:GoodRepo = Join-Path $TestDrive 'good'
    $script:BadRepo  = Join-Path $TestDrive 'bad'
    New-Item -ItemType Directory -Path $script:GoodRepo, $script:BadRepo -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $script:GoodRepo 'a.ps1') -Value 'Write-Output "ok"'
    Set-Content -LiteralPath (Join-Path $script:BadRepo 'a.ps1') -Value 'if ($true {'

    function script:Invoke-Harness {
        param([string]$Repo, [string]$Prelude = '')
        $command = "$Prelude & '$($script:Harness)' -RepoRoot '$Repo' -Check Parse"
        $null = & $script:Pwsh -NoProfile -Command $command 2>&1
        return $LASTEXITCODE
    }
}

Describe 'Invoke-DryRun.ps1 exit code (#472)' {

    It 'returns 0 after a passing run when a child left the host code at 5' {
        Invoke-Harness -Repo $script:GoodRepo -Prelude '$Host.SetShouldExit(5);' | Should -Be 0
    }

    It 'returns 0 after a passing run started directly' {
        Invoke-Harness -Repo $script:GoodRepo | Should -Be 0
    }

    It 'returns a nonzero code for a failing run, also when the host code was set to 0 first' {
        Invoke-Harness -Repo $script:BadRepo -Prelude '$Host.SetShouldExit(0);' | Should -Not -Be 0
    }
}
