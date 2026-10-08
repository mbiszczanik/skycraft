<#
.SYNOPSIS
    Pester 5 tests asserting that every file naming Lab 1.1's guest uses the guide's address.

.DESCRIPTION
    Regression guard for issue #193. The guide (step 1.1.5), ARCHITECTURE.md and the diagram
    invited one guest; the checklist, the three Lab 1.1 scripts and Lab 1.2's scripts used
    another, so a learner who followed the guide was checked, assigned roles and cleaned up
    against a guest they never invited.

    The guide is the source: the address is read from step 1.1.5 of lab-guide-1.1.md, and every
    other file that names the guest must name that one. What Lab 1.1's scripts do with it is
    proved by running them (module-1-identities-governance/1.1-entra-users-groups/tests/
    Guide-Addresses.Tests.ps1); this suite covers the documents and Lab 1.2, which reuses the
    guest for its External Partner role assignment.

.EXAMPLE
    Invoke-Pester -Path .\tests\Lab11-Guest-Address.Tests.ps1

.NOTES
    Project: SkyCraft
#>

#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    $script:Lab11 = Join-Path $repoRoot 'module-1-identities-governance' '1.1-entra-users-groups'
    $script:Lab12 = Join-Path $repoRoot 'module-1-identities-governance' '1.2-rbac'

    $guide = Get-Content -Raw -LiteralPath (Join-Path $script:Lab11 'lab-guide-1.1.md')
    $script:Guest = [regex]::Match($guide, '(?ms)^### Step 1\.1\.5:.*?^\|\s*Email\s*\|\s*(?<email>[^\s|]+)\s*\|').Groups['email'].Value
    $script:GuestAlias = ($script:Guest -split '@')[0]

    function Get-FileText {
        param([string]$Path)
        Get-Content -Raw -LiteralPath $Path
    }
}

Describe 'Lab 1.1 guest address - one address everywhere (#193)' {

    It 'reads the guest address from step 1.1.5 of the guide' {
        $script:Guest | Should -Match '^[^@\s]+@[^@\s]+\.[a-z]+$'
    }

    It 'ARCHITECTURE.md invites the guide''s guest' {
        $row = (Get-FileText (Join-Path $script:Lab11 'ARCHITECTURE.md')) -split '\r?\n' |
            Where-Object { $_ -match '^\|\s*Guest user model\s*\|' }
        $row | Should -Match ([regex]::Escape("``$($script:Guest)``"))
    }

    It 'the checklist expects the guide''s guest' {
        $text = Get-FileText (Join-Path $script:Lab11 'lab-checklist-1.1.md')
        [regex]::Match($text, '(?m)^\s*-\s*Email:\s*(?<email>\S+)\s*$').Groups['email'].Value | Should -Be $script:Guest
    }

    It 'the diagram names the guide''s guest' {
        Get-FileText (Join-Path $script:Lab11 'images' 'lab-1.1-architecture.excalidraw') |
            Should -Match ([regex]::Escape($script:Guest))
    }

    It 'Lab 1.2 <file> assigns the External Partner role to the guide''s guest' -ForEach @(
        @{ file = 'Deploy-Bicep.ps1' }
        @{ file = 'New-LabRoleAssignment.ps1' }
    ) {
        $text = Get-FileText (Join-Path $script:Lab12 'scripts' $file)
        $text | Should -Match ("['""]" + [regex]::Escape($script:Guest) + "['""]")
    }

    It 'Lab 1.2 Test-Lab.ps1 looks for the External Partner by the guide''s guest' {
        # A guest's sign-in name is rewritten to <alias>_<domain>#EXT#@<tenant>, hence the [@_].
        $text = Get-FileText (Join-Path $script:Lab12 'scripts' 'Test-Lab.ps1')
        $text | Should -Match ('Name="External Partner";\s*Principal="' + [regex]::Escape($script:GuestAlias) + '\[@_\]"')
    }
}
