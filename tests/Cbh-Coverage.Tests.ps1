<#
.SYNOPSIS
    Pester 5 test: every PowerShell script in the repo ships Comment-Based Help.

.DESCRIPTION
    docs/powershell-standards.md §1 requires every *.ps1 under module-*/**/scripts/ to carry
    a Comment-Based Help block with .SYNOPSIS, .DESCRIPTION, and .NOTES. This test finds
    every such script and asserts those three tags are present in the first 60 lines.

    Which files count as lab scripts is defined once in tests/LabScripts.psm1 and shared
    with the script-standards and automation-contract suites, so all three lint the same set.

.EXAMPLE
    Invoke-Pester -Path .\tests\Cbh-Coverage.Tests.ps1

.NOTES
    Project: SkyCraft
#>

#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

Import-Module (Join-Path $PSScriptRoot 'LabScripts.psm1') -Force

$ScriptCases = @(Get-ScriptCase)

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
