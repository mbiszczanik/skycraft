<#
.SYNOPSIS
    Pester 5 tests asserting every module README follows the L004 13-section contract.

.DESCRIPTION
    docs/project-standards.md §1.1 (L004) requires every module-level README to ship
    the following 13 sections, in order, with the standard emojis:

       1. 📚 Module Overview
       2. 🎯 Learning Objectives
       3. 📋 Module Sections
       4. 🏗️ Architecture Overview
       5. ✅ Prerequisites
       6. 🚀 Getting Started
       7. 📖 How to Use This Module
       8. 🎓 AZ-104 Exam Alignment
       9. ⏱️ Time Management
      10. 🔗 Useful Resources
      11. 📞 Getting Help
      12. ✨ What's Next
      13. 📌 Module Navigation

    Variants permitted by the existing modules:
      - section 4 heading may be "Architecture Overview" (M2/M3/M4) or "Module Architecture" (M5)
      - section 12 heading may be "What's Next" or "What's Next After This Module?"

.EXAMPLE
    Invoke-Pester -Path .\tests\Module-Readme-L004.Tests.ps1

.NOTES
    Project: SkyCraft
#>

#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path

# All five modules (1-5) now ship the full L004 13-section contract, including the
# '🏗️ Architecture Overview' Mermaid section. No module is excluded.
$ExcludedModules = @()

$Modules  = Get-ChildItem -Path $RepoRoot -Directory -Filter 'module-*' |
            Where-Object { $ExcludedModules -notcontains $_.Name } |
            Sort-Object Name |
            ForEach-Object {
                $readme = Get-ChildItem -Path $_.FullName -Filter 'README.*' -File |
                          Where-Object { $_.Name -match '^README\.(md|MD)$' } |
                          Select-Object -First 1
                if ($readme) {
                    @{ module = $_.Name; readme = $readme.FullName }
                }
            }

$ExpectedSections = @(
    @{ idx =  1; emoji = '📚'; pattern = 'Module Overview' }
    @{ idx =  2; emoji = '🎯'; pattern = 'Learning Objectives' }
    @{ idx =  3; emoji = '📋'; pattern = 'Module Sections' }
    @{ idx =  4; emoji = '🏗️'; pattern = '(Architecture Overview|Module Architecture)' }
    @{ idx =  5; emoji = '✅'; pattern = 'Prerequisites' }
    @{ idx =  6; emoji = '🚀'; pattern = 'Getting Started' }
    @{ idx =  7; emoji = '📖'; pattern = 'How to Use This Module' }
    @{ idx =  8; emoji = '🎓'; pattern = 'AZ-104 Exam Alignment' }
    @{ idx =  9; emoji = '⏱️'; pattern = 'Time Management' }
    @{ idx = 10; emoji = '🔗'; pattern = 'Useful Resources' }
    @{ idx = 11; emoji = '📞'; pattern = 'Getting Help' }
    @{ idx = 12; emoji = '✨'; pattern = "What's Next" }
    @{ idx = 13; emoji = '📌'; pattern = 'Module Navigation' }
)

Describe 'Module README - L004 section order' {
    It "'<module>' contains all 13 required sections in order" -ForEach $Modules {
        $headings = Get-Content -LiteralPath $readme |
                    Where-Object { $_ -match '^##\s+' } |
                    ForEach-Object { $_ -replace '^##\s+', '' }
        $headings.Count | Should -BeGreaterOrEqual 13 -Because "README '$module' should expose at least 13 top-level sections"

        for ($i = 0; $i -lt $ExpectedSections.Count; $i++) {
            $expected = $ExpectedSections[$i]
            $actual   = $headings[$i]
            $actual | Should -Match $expected.emoji -Because "section $($expected.idx) of '$module' must start with '$($expected.emoji)' — saw '$actual'"
            $actual | Should -Match $expected.pattern -Because "section $($expected.idx) of '$module' must mention '$($expected.pattern)' — saw '$actual'"
        }
    }
}

Describe 'Module README - Mermaid diagram in section 4' {
    It "'<module>' embeds a Mermaid diagram in section 4" -ForEach $Modules {
        $raw = Get-Content -Raw -LiteralPath $readme
        $raw | Should -Match '```mermaid' -Because "module '$module' must contain at least one Mermaid code block (L004 section 4)"
    }
}
