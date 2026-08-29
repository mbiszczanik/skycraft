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
