<#
.SYNOPSIS
    Pester 5 test: Module 1 README ships the required Architecture Overview section.

.DESCRIPTION
    docs/project-standards.md §1.1 (L004) requires every module README to carry a
    '🏗️ Architecture Overview' section with a Mermaid diagram as section #4 (between
    '📋 Module Sections' and '✅ Prerequisites'). This test asserts that contract
    on module-1-identities-governance/README.MD.

.EXAMPLE
    Invoke-Pester -Path .\Readme-Architecture.Tests.ps1

.NOTES
    Project: SkyCraft
    Module: 1 - Identities & Governance
#>

#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    $script:ReadmePath = (Resolve-Path (Join-Path $PSScriptRoot '..\README.MD')).Path
    $script:Text       = Get-Content -Raw -LiteralPath $script:ReadmePath
    $script:Headings   = Get-Content -LiteralPath $script:ReadmePath |
                         Where-Object { $_ -match '^##\s+' } |
                         ForEach-Object { $_ -replace '^##\s+', '' }
}

Describe 'Module 1 README - L004 Architecture Overview' {
    It 'defines an Architecture Overview section with the required emoji' {
        ($script:Text) | Should -Match '##\s+🏗️\s+Architecture Overview'
    }

    It 'places Architecture Overview as section #4' {
        $script:Headings.Count | Should -BeGreaterOrEqual 4
        $script:Headings[3] | Should -Match '🏗️'
        $script:Headings[3] | Should -Match 'Architecture Overview'
    }

    It 'embeds a Mermaid code block in the README' {
        $script:Text | Should -Match '```mermaid'
    }

    It 'references the three SkyCraft resource groups in the diagram' {
        $script:Text | Should -Match 'platform-skycraft-swc-rg'
        $script:Text | Should -Match 'dev-skycraft-swc-rg'
        $script:Text | Should -Match 'prod-skycraft-swc-rg'
    }

    It 'references at least one Warcraft persona from the framework' {
        $script:Text | Should -Match '(Malfurion|Khadgar|Chromie|Illidan)'
    }
}
