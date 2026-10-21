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
    must not carry a closing keyword, must name why the live check cannot run in the test
    environment (issue #404) and needs the maintainer's label.

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
        # A lab-local Pester suite stubs Az and runs in CI (lint.yml) - nothing about it can be
        # verified live, so it is out of scope like tests/ (issue #156). Its lab's scripts are not.
        @{ path = 'module-5-monitoring-maintenance/5.2-business-continuity/tests/Remove-LabResource.Tests.ps1';  gated = $false }
        @{ path = 'module-1-identities-governance/1.2-rbac/tests/RoleAssignments-DeployPath.Tests.ps1';         gated = $false }
        @{ path = 'module-3-compute\3.3-containers\tests\Remove-LabResource.Tests.ps1';                        gated = $false }
        @{ path = 'module-5-monitoring-maintenance/5.2-business-continuity/scripts/Remove-LabResource.ps1';     gated = $true }
        @{ path = 'module-4-storage/4.2-blob-storage/bicep/tests.bicep';                                         gated = $true }
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
        $script:Blocker  = 'Live-verification-blocker: the step needs a subscription created today; the test subscription is months old.'
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

    It 'passes a PR that touches only a lab-local test suite, tests/ and docs, with no declaration (PR #151)' {
        $files = @(
            'module-5-monitoring-maintenance/5.2-business-continuity/tests/Remove-LabResource.Tests.ps1'
            'tests/Lab-Script-Harness-Guard.Tests.ps1'
            'docs/powershell-standards.md'
            'CHANGELOG.md'
        )
        $v = Get-PrGateVerdict -ChangedFile $files -Body "## Summary`nSuite fixes.`n`nCloses #112"
        $v.Gated | Should -BeFalse
        $v.Pass  | Should -BeTrue
    }

    It 'still fails a PR that changes a lab-local suite together with the lab script it covers' {
        $files = @(
            'module-5-monitoring-maintenance/5.2-business-continuity/tests/Remove-LabResource.Tests.ps1'
            'module-5-monitoring-maintenance/5.2-business-continuity/scripts/Remove-LabResource.ps1'
        )
        $v = Get-PrGateVerdict -ChangedFile $files -Body 'Closes #112'
        $v.Gated | Should -BeTrue
        $v.Pass  | Should -BeFalse
    }

    It 'passes a gated PR that declares what it verified' {
        $v = Get-PrGateVerdict -ChangedFile $script:Gated -Body "Closes #79`n`nLive-verified: Invoke-LabCycle run 67b14134 on 2026-09-20, labs 5.1-5.3"
        $v.Pass     | Should -BeTrue
        $v.Verified | Should -Match '67b14134'
    }

    It 'passes a deferred PR that references its issue, names its blocker and carries the approval label (#338, #404)' {
        $v = Get-PrGateVerdict -ChangedFile $script:Gated -Body "Refs #79`n`nLive-verification: deferred -> #141`n$script:Blocker" `
            -Label @('documentation', 'live-deferral-approved')
        $v.Pass       | Should -BeTrue
        $v.DeferredTo | Should -Be 141
        $v.Reason     | Should -Match 'live-deferral-approved'
    }

    It 'fails a deferred PR without the approval label, naming the label and the way out (#338)' {
        $v = Get-PrGateVerdict -ChangedFile $script:Gated -Body "Refs #79`n`nLive-verification: deferred -> #141`n$script:Blocker"
        $v.Pass       | Should -BeFalse
        $v.DeferredTo | Should -Be 141
        $v.Reason     | Should -Match 'live-deferral-approved'
        $v.Reason     | Should -Match 'Live-verified'
    }

    It 'does not take a label that only resembles the approval label' {
        $v = Get-PrGateVerdict -ChangedFile $script:Gated -Body "Refs #79`nLive-verification: deferred -> #141" `
            -Label @('live-deferral-approved-later', 'live deferral approved')
        $v.Pass | Should -BeFalse
    }

    It 'still fails a deferred PR with a closing keyword, label or not' {
        $v = Get-PrGateVerdict -ChangedFile $script:Gated -Body "Closes #79`nLive-verification: deferred -> #141" `
            -Label @('live-deferral-approved')
        $v.Pass   | Should -BeFalse
        $v.Reason | Should -Match 'Refs'
    }

    It 'needs no label for a verified or an ungated PR' {
        (Get-PrGateVerdict -ChangedFile $script:Gated -Body 'Live-verified: labs 1.3 by hand, 2026-10-14').Pass | Should -BeTrue
        (Get-PrGateVerdict -ChangedFile $script:NotGated -Body 'Live-verification: deferred -> #141').Pass     | Should -BeTrue
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
        # Multi-line, as in the template: the line-start anchor alone would accept these.
        $body = "Closes #79`n<!--`n  Live-verified: Lab 1.1 Test-Lab 10/10, test tenant, 2026-10-20, exit 0`n-->"
        $v = Get-PrGateVerdict -ChangedFile $script:Gated -Body $body
        $v.Pass   | Should -BeFalse
        $v.Reason | Should -Match 'declares no live verification'
    }

    It 'matches the declaration keys case-insensitively and with surrounding whitespace' {
        $v = Get-PrGateVerdict -ChangedFile $script:Gated -Body "  live-VERIFIED:  labs 5.1-5.3 by hand, 2026-09-20  "
        $v.Pass | Should -BeTrue
    }

    # Issue #404: a deferral is allowed only for a live check the test environment cannot run,
    # and the PR says why on its own line. PR #382 was deferred although its fix ran live and passed.
    It 'fails a labelled deferred PR without a blocker line, naming the line' {
        $v = Get-PrGateVerdict -ChangedFile $script:Gated -Body "Refs #79`nLive-verification: deferred -> #141" `
            -Label @('live-deferral-approved')
        $v.Pass       | Should -BeFalse
        $v.DeferredTo | Should -Be 141
        $v.Reason     | Should -Match 'Live-verification-blocker:'
    }

    It "fails a blank or placeholder blocker reason: '<why>'" -ForEach @(
        @{ why = '' }, @{ why = '   ' }, @{ why = '<why the live check cannot run in the test environment>' },
        @{ why = '<reason>' }, @{ why = 'TBD' }, @{ why = 'todo' }, @{ why = 'N/A' }, @{ why = 'none' },
        @{ why = '-' }, @{ why = '...' }, @{ why = '`TBD`' }, @{ why = '**none**' }, @{ why = 'TBA' },
        @{ why = '<why> pending' }, @{ why = 'see above' }, @{ why = 'unknown' }, @{ why = '?' },
        @{ why = [string][char]0x2026 }
    ) {
        $v = Get-PrGateVerdict -ChangedFile $script:Gated -Body "Refs #79`nLive-verification: deferred -> #141`nLive-verification-blocker: $why" `
            -Label @('live-deferral-approved')
        $v.Pass   | Should -BeFalse
        $v.Reason | Should -Match 'Live-verification-blocker:'
    }

    It 'fails a deferred PR with two blocker lines' {
        $v = Get-PrGateVerdict -ChangedFile $script:Gated -Body "Refs #79`nLive-verification: deferred -> #141`n$script:Blocker`n$script:Blocker" `
            -Label @('live-deferral-approved')
        $v.Pass   | Should -BeFalse
        $v.Reason | Should -Match "carries 2 'Live-verification-blocker:' lines"
    }

    It 'ignores a blocker line inside an HTML comment' {
        $body = "Refs #79`nLive-verification: deferred -> #141`n<!--`n  $script:Blocker`n-->"
        $v = Get-PrGateVerdict -ChangedFile $script:Gated -Body $body -Label @('live-deferral-approved')
        $v.Pass   | Should -BeFalse
        $v.Reason | Should -Match "no 'Live-verification-blocker:' line"
    }

    It 'does not read the blocker line as a second deferred declaration' {
        $v = Get-PrGateVerdict -ChangedFile $script:Gated -Body "Refs #79`nLive-verification: deferred -> #141`n$script:Blocker" `
            -Label @('live-deferral-approved')
        $v.Pass   | Should -BeTrue
        $v.Reason | Should -Match 'subscription created today'
    }

    It 'needs no blocker line for a verified or an ungated PR' {
        (Get-PrGateVerdict -ChangedFile $script:Gated -Body 'Live-verified: Lab 1.1 Test-Lab 10/10, test tenant, 2026-10-20, exit 0').Pass | Should -BeTrue
        (Get-PrGateVerdict -ChangedFile $script:NotGated -Body "Live-verification: deferred -> #141`nLive-verification-blocker:").Pass  | Should -BeTrue
    }

    It "fails a placeholder Live-verified line: '<what>'" -ForEach @(
        @{ what = 'TBD' }, @{ what = 'n/a' }, @{ what = '<what ran, where, date, exit codes>' }, @{ what = '**TBD**' }
    ) {
        $v = Get-PrGateVerdict -ChangedFile $script:Gated -Body "Closes #79`nLive-verified: $what"
        $v.Pass   | Should -BeFalse
        $v.Reason | Should -Match "'Live-verified:' line gives no run"
    }

    It 'counts a cross-repository closing keyword as closing too' {
        # GitHub honours "closes owner/repo#1" as well as "closes #1".
        $v = Get-PrGateVerdict -ChangedFile $script:Gated -Body "closes mbiszczanik/other#1`nLive-verification: deferred -> #141"
        $v.Pass | Should -BeFalse
    }
}

# Issue #404: the template asks for what the gate and ADR-0006 decision 6 expect.
Describe 'PULL_REQUEST_TEMPLATE.md asks for the declarations ADR-0006 decision 6 expects' {
    BeforeAll {
        $script:Template = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot '.github/PULL_REQUEST_TEMPLATE.md')
        # Only lines outside HTML comments land in a PR body as written.
        $script:Visible  = [regex]::Replace($script:Template, '(?s)<!--.*?-->', '')
    }

    It 'shows the Live-verified form with run, place, date and exit codes' {
        $script:Template | Should -Match '(?m)^\s*Live-verified: <what ran, where, date, exit codes>\s*$'
    }

    It 'shows the deferred and blocker lines for a deferral' {
        $script:Template | Should -Match '(?m)^\s*Live-verification: deferred -> #<issue[^>]*>\s*$'
        $script:Template | Should -Match '(?m)^\s*Live-verification-blocker: <why the live check cannot run in the test environment>\s*$'
    }

    It 'leaves a visible Live-verified line and an Offline checks line naming the CI run' {
        $script:Visible | Should -Match '(?m)^Live-verified:'
        $script:Visible | Should -Match '(?m)^Offline checks: full CI test set, CI run <id>\s*$'
    }

    It 'links the issue with Refs, not a closing keyword, by default' {
        $script:Visible | Should -Match '(?m)^Refs #\s*$'
        $script:Visible | Should -Not -Match '(?im)^\s*(close[sd]?|fix(e[sd])?|resolve[sd]?)\s+#'
    }
}
