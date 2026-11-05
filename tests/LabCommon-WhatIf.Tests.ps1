<#
.SYNOPSIS
    Pester 5 tests: what-if tables printed by the lab deploy scripts carry no subscription id (#393).

.DESCRIPTION
    Az prints a what-if result itself, so Write-Host redaction never sees it. Write-LabWhatIfResult
    renders the result to text, redacts it with Protect-LabText and writes it. These cases run the
    helper in this process and check that every what-if call in a lab deploy script goes through it.

.EXAMPLE
    Invoke-Pester -Path .\tests\LabCommon-WhatIf.Tests.ps1

.NOTES
    Project: SkyCraft
    Issue: #393
#>

#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    Import-Module (Join-Path $script:RepoRoot 'tools' 'LabCommon.psm1') -Force -Verbose:$false
}

Describe 'Write-LabWhatIfResult (#393)' {

    It 'prints a what-if result with the subscription id redacted' {
        $result = [pscustomobject]@{ ResourceId = '/subscriptions/11111111-2222-3333-4444-555555555555/resourceGroups/dev-rg'; Change = 'Create' }
        $shown = ($result | Write-LabWhatIfResult 6>&1 | Out-String)
        $shown | Should -Match '/subscriptions/<id>/resourceGroups/dev-rg'
        $shown | Should -Match 'Create'
        $shown | Should -Not -Match '11111111-2222-3333-4444-555555555555'
    }

    It 'prints nothing for an empty or null result' {
        (@() | Write-LabWhatIfResult 6>&1 | Out-String) | Should -BeNullOrEmpty
        ($null | Write-LabWhatIfResult 6>&1 | Out-String) | Should -BeNullOrEmpty
    }
}

Describe 'Every what-if call in a lab deploy script goes through the helper (#393)' {

    It 'finds the deploy scripts to read' {
        $files = @(git -C $script:RepoRoot ls-files 'module-*/*/scripts/Deploy-*.ps1')
        $files.Count | Should -BeGreaterThan 10
    }

    It 'has no call of the what-if cmdlet that skips Write-LabWhatIfResult' {
        $files = @(git -C $script:RepoRoot ls-files 'module-*/*/scripts/Deploy-*.ps1')
        $skipped = foreach ($file in $files) {
            $lines = Get-Content -LiteralPath (Join-Path $script:RepoRoot $file)
            for ($i = 0; $i -lt $lines.Count; $i++) {
                $line = $lines[$i]
                if ($line -match '^\s*#' -or $line -notmatch 'Get-AzSubscriptionDeploymentWhatIfResult @') { continue }
                $piped = $line -match '\|\s*Write-LabWhatIfResult'
                # A call stored in $result is piped where the script prints it.
                $stored = $line -match '\$result\s*=\s*Get-AzSubscriptionDeploymentWhatIfResult'
                if (-not $piped -and -not $stored) { "${file}:$($i + 1)" }
                if ($stored -and -not ($lines -match '^\s*\$result\s*\|\s*Write-LabWhatIfResult')) { "${file}:$($i + 1) (result never piped)" }
            }
        }
        $skipped | Should -BeNullOrEmpty
    }
}
