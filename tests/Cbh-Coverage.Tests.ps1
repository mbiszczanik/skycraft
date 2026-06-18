<#
.SYNOPSIS
    Pester 5 test: every PowerShell script in the repo ships Comment-Based Help.

.DESCRIPTION
    docs/powershell-standards.md §1 requires every *.ps1 under module-*/**/scripts/ to carry
    a Comment-Based Help block with .SYNOPSIS, .DESCRIPTION, and .NOTES. This test finds
    every such script and asserts those three tags are present in the first 60 lines.

.EXAMPLE
    Invoke-Pester -Path .\tests\Cbh-Coverage.Tests.ps1

.NOTES
    Project: SkyCraft
#>

#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

$RepoRoot   = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$PsScripts  = Get-ChildItem -Path $RepoRoot -Recurse -File -Filter '*.ps1' |
              Where-Object { $_.FullName -match '\\module-\d.*\\scripts\\' }

$ScriptCases = $PsScripts | ForEach-Object {
    @{ file = $_.FullName.Substring($RepoRoot.Length + 1); path = $_.FullName }
}

Describe 'SkyCraft PowerShell - CBH coverage' {
    It "'<file>' contains a .SYNOPSIS tag in the first 60 lines" -ForEach $ScriptCases {
        $head = (Get-Content -LiteralPath $path -TotalCount 60) -join "`n"
        $head | Should -Match '\.SYNOPSIS'
    }

    It "'<file>' contains a .DESCRIPTION tag in the first 60 lines" -ForEach $ScriptCases {
        $head = (Get-Content -LiteralPath $path -TotalCount 60) -join "`n"
        $head | Should -Match '\.DESCRIPTION'
    }

    It "'<file>' contains a .NOTES tag in the first 60 lines" -ForEach $ScriptCases {
        $head = (Get-Content -LiteralPath $path -TotalCount 60) -join "`n"
        $head | Should -Match '\.NOTES'
    }
}
