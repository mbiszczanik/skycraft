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
