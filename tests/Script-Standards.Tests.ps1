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

    Which files count as lab scripts is defined once in tests/LabScripts.psm1 and shared
    with the CBH-coverage and automation-contract suites, so all three lint the same set.

.EXAMPLE
    Invoke-Pester -Path .\tests\Script-Standards.Tests.ps1

.NOTES
    Project: SkyCraft
#>

#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

Import-Module (Join-Path $PSScriptRoot 'LabScripts.psm1') -Force

$ScriptCases = @(Get-ScriptCase)
$RemoveCases = @(Get-ScriptCase -FileName 'Remove-*.ps1')

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
