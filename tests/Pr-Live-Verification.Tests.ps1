<#
.SYNOPSIS
    Pester 5 test: the decisions the PR live-verification gate makes.

.DESCRIPTION
    Follows tests/Resource-Audit.Tests.ps1: lifts the decision helpers out of
    tools/Test-PrLiveVerification.ps1 with the PowerShell parser and runs them against
    synthetic PR bodies and file lists. Only the FunctionDefinitionAst nodes are evaluated,
    so the script body never runs and no GitHub call is made.

    Why this exists: PR #132 closed issue #79 on merge while its own body said the live
    follow-the-guide pass had not been run (ADR-0006). Nothing enforced the PR template's
    "Test-Lab.ps1 passes for affected lab(s)" box - a body written with --body-file skips
    the template entirely - and a live lab cycle deliberately cannot run in CI. The gate
    makes the decision explicit instead: a PR that touches lab content must declare either
    the verification it ran or the issue that tracks the one it deferred, and a deferred PR
    must not carry a closing keyword.

.EXAMPLE
    Invoke-Pester -Path .\tests\Pr-Live-Verification.Tests.ps1

.NOTES
    Project: SkyCraft
#>

#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    $RepoRoot   = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    $ScriptPath = Join-Path $RepoRoot 'tools/Test-PrLiveVerification.ps1'

    if (-not (Test-Path -LiteralPath $ScriptPath)) {
        throw "Test-PrLiveVerification.ps1 not found at $ScriptPath"
    }

    $parseError = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($ScriptPath, [ref]$null, [ref]$parseError)
    if ($parseError) {
        throw "Test-PrLiveVerification.ps1 does not parse: $($parseError[0].Message)"
    }

    $functionAst = $ast.FindAll(
        { $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $false)
    foreach ($function in $functionAst) {
        . ([scriptblock]::Create($function.Extent.Text))
    }
    $script:LiftedName = @($functionAst.Name)
}

Describe 'Test-PrLiveVerification.ps1 exposes its decision helpers' {
    It 'defines Test-GatedPath and Get-PrGateVerdict as top-level functions' {
        $script:LiftedName | Should -Contain 'Test-GatedPath'
        $script:LiftedName | Should -Contain 'Get-PrGateVerdict'
    }
}

Describe 'Test-GatedPath: which changed files put a PR under the gate' {
    It "'<path>' is gated=<gated>" -ForEach @(
        @{ path = 'module-5-monitoring-maintenance/5.3-network-monitoring/lab-guide-5.3.md'; gated = $true }
        @{ path = 'module-3-compute/3.2-virtual-machines/scripts/Deploy-Bicep.ps1';           gated = $true }
        @{ path = 'module-4-storage/4.2-blob-storage/bicep/main.bicep';                       gated = $true }
        @{ path = 'scripts/Invoke-ResourceAudit.ps1';                                          gated = $true }
        @{ path = 'tools/lab-cycle-manifest.psd1';                                             gated = $true }
        @{ path = 'tools/Invoke-LabCycle.ps1';                                                 gated = $true }
        @{ path = 'tools/LabCycle.psm1';                                                       gated = $true }
        @{ path = 'tools/Test-PrLiveVerification.ps1';                                         gated = $false }
        @{ path = 'tools/Invoke-DryRun.ps1';                                                   gated = $false }
        @{ path = 'tests/Pr-Live-Verification.Tests.ps1';                                      gated = $false }
        @{ path = 'docs/adr/0006-pr-live-verification-gate.md';                                gated = $false }
        @{ path = '.github/workflows/pr-gate.yml';                                             gated = $false }
        @{ path = 'CHANGELOG.md';                                                              gated = $false }
    ) {
        Test-GatedPath -Path $path | Should -Be $gated
    }
}

Describe 'Get-PrGateVerdict' {
    BeforeAll {
        $script:Gated    = @('module-5-monitoring-maintenance/5.1-azure-monitor/lab-guide-5.1.md')
        $script:NotGated = @('docs/adr/0006-pr-live-verification-gate.md', 'CHANGELOG.md')
    }

    It 'passes a PR that touches no gated path, whatever its body says' {
        $v = Get-PrGateVerdict -ChangedFile $script:NotGated -Body 'Closes #1'
        $v.Gated | Should -BeFalse
        $v.Pass  | Should -BeTrue
    }

    It 'fails a gated PR that declares nothing' {
        $v = Get-PrGateVerdict -ChangedFile $script:Gated -Body "## Summary`nGuide fixes.`n`nCloses #79"
        $v.Gated  | Should -BeTrue
        $v.Pass   | Should -BeFalse
        $v.Reason | Should -Match 'Live-verified|Live-verification'
    }

    It 'passes a gated PR that declares what it verified' {
        $v = Get-PrGateVerdict -ChangedFile $script:Gated -Body "Closes #79`n`nLive-verified: Invoke-LabCycle run 67b14134 on 2026-09-20, labs 5.1-5.3"
        $v.Pass     | Should -BeTrue
        $v.Verified | Should -Match '67b14134'
    }

    It 'passes a gated PR that defers to a tracked issue and only references its own' {
        $v = Get-PrGateVerdict -ChangedFile $script:Gated -Body "Refs #79`n`nLive-verification: deferred -> #141"
        $v.Pass       | Should -BeTrue
        $v.DeferredTo | Should -Be 141
    }

    It 'fails a deferred PR that still carries a closing keyword' {
        $v = Get-PrGateVerdict -ChangedFile $script:Gated -Body "Closes #79`n`nLive-verification: deferred -> #141"
        $v.Pass   | Should -BeFalse
        $v.Reason | Should -Match 'Refs'
    }

    It "treats every GitHub closing keyword as closing: '<keyword>'" -ForEach @(
        @{ keyword = 'close' }, @{ keyword = 'Closes' }, @{ keyword = 'closed' },
        @{ keyword = 'fix' },   @{ keyword = 'Fixes' },  @{ keyword = 'fixed' },
        @{ keyword = 'resolve' }, @{ keyword = 'Resolves' }, @{ keyword = 'resolved' }
    ) {
        $v = Get-PrGateVerdict -ChangedFile $script:Gated -Body "$keyword #79`nLive-verification: deferred -> #141"
        $v.Pass | Should -BeFalse
    }

    It 'fails a PR that declares both verified and deferred' {
        $v = Get-PrGateVerdict -ChangedFile $script:Gated -Body "Live-verified: run 1`nLive-verification: deferred -> #141"
        $v.Pass   | Should -BeFalse
        $v.Reason | Should -Match 'one'
    }

    It 'fails an empty Live-verified declaration' {
        $v = Get-PrGateVerdict -ChangedFile $script:Gated -Body "Live-verified:   `nCloses #79"
        $v.Pass | Should -BeFalse
    }

    It 'fails a deferred declaration without an issue number' {
        $v = Get-PrGateVerdict -ChangedFile $script:Gated -Body "Refs #79`nLive-verification: deferred"
        $v.Pass | Should -BeFalse
    }

    It 'ignores declarations that sit inside an HTML comment (the template shows the syntax there)' {
        $body = "<!-- Live-verified: <run id>  or  Live-verification: deferred -> #<issue> -->`nCloses #79"
        $v = Get-PrGateVerdict -ChangedFile $script:Gated -Body $body
        $v.Pass | Should -BeFalse
    }

    It 'matches the declaration keys case-insensitively and with surrounding whitespace' {
        $v = Get-PrGateVerdict -ChangedFile $script:Gated -Body "  live-VERIFIED:  labs 5.1-5.3 by hand, 2026-09-20  "
        $v.Pass | Should -BeTrue
    }

    It 'counts a cross-repository closing keyword as closing too' {
        # GitHub honours "closes owner/repo#1" as well as "closes #1".
        $v = Get-PrGateVerdict -ChangedFile $script:Gated -Body "closes mbiszczanik/other#1`nLive-verification: deferred -> #141"
        $v.Pass | Should -BeFalse
    }
}
