<#
.SYNOPSIS
    Pester 5 test: every automation script meets the PowerShell gold-path standards.

.DESCRIPTION
    Enforces the standards retrofitted in the PowerShell sprint (docs/powershell-standards.md):
    every *.ps1 under module-*/**/scripts/ must
      - set $ErrorActionPreference = 'Stop'
      - declare #Requires -Version 7.0
      - declare [CmdletBinding(...)]
    and every destructive Remove-*.ps1 must
      - declare SupportsShouldProcess (so it exposes -WhatIf / -Confirm)
      - contain no manual Read-Host confirmation prompt

    Path matching is separator-agnostic so the suite runs identically on the
    Windows dev box and the Linux CI runner.

.EXAMPLE
    Invoke-Pester -Path .\tests\Script-Standards.Tests.ps1

.NOTES
    Project: SkyCraft
#>

#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

$RepoRoot  = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$AllScripts = Get-ChildItem -Path $RepoRoot -Recurse -File -Filter '*.ps1' |
              Where-Object { ($_.FullName -replace '\\', '/') -match '/module-\d.*/scripts/' }

$ScriptCases = $AllScripts | ForEach-Object {
    @{ file = $_.FullName.Substring($RepoRoot.Length + 1); path = $_.FullName }
}

$RemoveCases = $AllScripts | Where-Object { $_.Name -like 'Remove-*.ps1' } | ForEach-Object {
    @{ file = $_.FullName.Substring($RepoRoot.Length + 1); path = $_.FullName }
}

$DeployPromptCases = $AllScripts |
                     Where-Object { $_.Name -like 'Deploy-*.ps1' -and
                                    (Get-Content -Raw -LiteralPath $_.FullName) -match 'Proceed with deployment' } |
                     ForEach-Object {
                         @{ file = $_.FullName.Substring($RepoRoot.Length + 1); path = $_.FullName }
                     }

# Regression guard for issue #103 (Lab 3.2 deployment silently skipped by a non-interactive caller)
$Lab32DeployCase = @(
    @{
        file = 'module-3-compute/3.2-virtual-machines/scripts/Deploy-Bicep.ps1'
        path = (Join-Path $RepoRoot 'module-3-compute/3.2-virtual-machines/scripts/Deploy-Bicep.ps1')
    }
)

# Regression guard for issue #105 (Lab 5.2 cleanup masked every failure and always exited 0)
$Lab52CleanupCase = @(
    @{
        file = 'module-5-monitoring-maintenance/5.2-business-continuity/scripts/Remove-LabResource.ps1'
        path = (Join-Path $RepoRoot 'module-5-monitoring-maintenance/5.2-business-continuity/scripts/Remove-LabResource.ps1')
    }
)

# Regression guard for issue #113 (Lab 5.2 deploy used a Standard policy and masked the failure)
$Lab52DeployCase = @(
    @{
        file = 'module-5-monitoring-maintenance/5.2-business-continuity/scripts/Deploy-Bicep.ps1'
        path = (Join-Path $RepoRoot 'module-5-monitoring-maintenance/5.2-business-continuity/scripts/Deploy-Bicep.ps1')
    }
)

Describe 'SkyCraft PowerShell - script standards' {

    It "'<file>' sets `$ErrorActionPreference = 'Stop'" -ForEach $ScriptCases {
        $content = Get-Content -Raw -LiteralPath $path
        $content | Should -Match "ErrorActionPreference\s*=\s*['`"]Stop['`"]"
    }

    It "'<file>' declares #Requires -Version 7.0" -ForEach $ScriptCases {
        $content = Get-Content -Raw -LiteralPath $path
        $content | Should -Match '#Requires -Version 7\.0'
    }

    It "'<file>' declares [CmdletBinding(...)]" -ForEach $ScriptCases {
        $content = Get-Content -Raw -LiteralPath $path
        $content | Should -Match '\[CmdletBinding\('
    }
}

Describe 'SkyCraft PowerShell - destructive scripts use ShouldProcess' {

    It "'<file>' declares SupportsShouldProcess" -ForEach $RemoveCases {
        $content = Get-Content -Raw -LiteralPath $path
        $content | Should -Match 'SupportsShouldProcess'
    }

    It "'<file>' contains no manual Read-Host prompt" -ForEach $RemoveCases {
        $content = Get-Content -Raw -LiteralPath $path
        $content | Should -Not -Match 'Read-Host'
    }
}

Describe 'SkyCraft PowerShell - deployment scripts stay automatable' {

    It "'<file>' declares a -Force switch so the confirmation can be skipped" -ForEach $DeployPromptCases {
        $content = Get-Content -Raw -LiteralPath $path
        $content | Should -Match '\[switch\]\$Force'
    }
}

Describe 'SkyCraft PowerShell - Lab 3.2 deployment cannot be silently skipped' {

    It "'<file>' documents the -Force switch in its comment-based help" -ForEach $Lab32DeployCase {
        $content = Get-Content -Raw -LiteralPath $path
        $content | Should -Match '\.PARAMETER Force'
    }

    It "'<file>' contains no manual Read-Host prompt" -ForEach $Lab32DeployCase {
        $content = Get-Content -Raw -LiteralPath $path
        $content | Should -Not -Match 'Read-Host'
    }

    It "'<file>' exits non-zero when the deployment is declined" -ForEach $Lab32DeployCase {
        $content = Get-Content -Raw -LiteralPath $path
        $content | Should -Not -Match 'Deployment cancelled\.[^\r\n]*[\r\n]+\s*(\$Host\.SetShouldExit\(0\)[\r\n]+\s*)?exit 0'
        $content | Should -Match 'Deployment cancelled\.[^\r\n]*[\r\n]+\s*(\$Host\.SetShouldExit\([1-9]\)[\r\n]+\s*)?exit [1-9]'
    }
}

Describe 'SkyCraft PowerShell - Lab 5.2 cleanup cannot mask a failure' {

    It "'<file>' counts the steps that failed" -ForEach $Lab52CleanupCase {
        $content = Get-Content -Raw -LiteralPath $path
        $content | Should -Match '\$script:cleanupFailures\s*=\s*0'
        $content | Should -Match '\$script:cleanupFailures\+\+'
    }

    It "'<file>' exits non-zero when a step failed" -ForEach $Lab52CleanupCase {
        $content = Get-Content -Raw -LiteralPath $path
        $content | Should -Match '(?s)if \(\$script:cleanupFailures -gt 0\).*?exit 1'
    }

    It "'<file>' reports a failed delete as [ERROR], not [WARNING]" -ForEach $Lab52CleanupCase {
        $content = Get-Content -Raw -LiteralPath $path
        $content | Should -Not -Match '\[WARNING\] Could not'
        $content | Should -Match '\[ERROR\] Could not delete RSV'
    }

    It "'<file>' blames stale tooling first in the vault failure hint" -ForEach $Lab52CleanupCase {
        $content = Get-Content -Raw -LiteralPath $path
        $content | Should -Match 'Azure CLI 2\.75\.0\+'
        $content | Should -Match 'Az PowerShell 7\.5\.0\+'
        # The pre-#105 hint claimed the vault had to be emptied through the portal first.
        $content | Should -Not -Match 'Backup Items . Stop protection'
    }

    It "'<file>' removes the orphaned Azure Backup restore point collection" -ForEach $Lab52CleanupCase {
        $content = Get-Content -Raw -LiteralPath $path
        $content | Should -Match 'Microsoft\.Compute/restorePointCollections'
        $content | Should -Match 'AzureBackupRG_'
    }
}

Describe 'SkyCraft PowerShell - Lab 5.2 deployment survives Trusted Launch' {

    It "'<file>' creates the VM backup policy as an Enhanced policy" -ForEach $Lab52DeployCase {
        # Azure defaults VM deployments to Trusted Launch, which a Standard policy cannot protect.
        $content = Get-Content -Raw -LiteralPath $path
        $content | Should -Match '-PolicySubType Enhanced'
    }

    It "'<file>' keeps instant restore at the 2 days the lab documents" -ForEach $Lab52DeployCase {
        # Enhanced defaults to 7 days of billed snapshots, and Test-Lab.ps1 asserts 2.
        $content = Get-Content -Raw -LiteralPath $path
        $content | Should -Match 'SnapshotRetentionInDays\s*=\s*2'
    }

    It "'<file>' counts deployment failures and exits non-zero" -ForEach $Lab52DeployCase {
        $content = Get-Content -Raw -LiteralPath $path
        $content | Should -Match '\$script:deployFailures\s*=\s*0'
        $content | Should -Match '\$script:deployFailures\+\+'
        $content | Should -Match '(?s)if \(\$script:deployFailures -gt 0\).*?exit 1'
    }

    It "'<file>' reports a failed VM protection as [ERROR], not [WARNING]" -ForEach $Lab52DeployCase {
        $content = Get-Content -Raw -LiteralPath $path
        $content | Should -Not -Match '\[WARNING\] Could not enable VM backup'
        $content | Should -Match '\[ERROR\] Could not enable VM backup'
    }

    It "'<file>' does not identify a protected VM by FriendlyName alone" -ForEach $Lab52DeployCase {
        # FriendlyName comes back empty for some VMs (#105), which made the idempotency check
        # miss an already-protected VM and re-run Enable on every deployment.
        $content = Get-Content -Raw -LiteralPath $path
        $content | Should -Match 'ContainerName -split'
    }
}
