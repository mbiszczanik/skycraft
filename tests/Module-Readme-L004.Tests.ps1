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
# '🏗️ Architecture Overview' diagram. No module is excluded.
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

Describe 'Module README - architecture diagram in section 4' {
    It "'<module>' embeds a theme-aware architecture diagram in section 4" -ForEach $Modules {
        $raw = Get-Content -Raw -LiteralPath $readme

        $raw | Should -Match '<picture>' -Because "module '$module' must embed its architecture diagram through <picture> (lab-guide-standards.md section 3.4)"
        $raw | Should -Match 'prefers-color-scheme: dark' -Because "module '$module' must offer a dark variant of the diagram"
        $raw | Should -Match 'srcset="images/module-\d-architecture\.dark\.svg"' -Because "module '$module' must point at its own dark SVG"
        $raw | Should -Match 'src="images/module-\d-architecture\.svg"' -Because "module '$module' must keep a plain <img> fallback"
        $raw | Should -Not -Match '```mermaid' -Because "Mermaid is legacy — module '$module' should carry no Mermaid block (ADR-0004)"
    }

    It "'<module>' ships every file its <picture> block references" -ForEach $Modules {
        $dir = Split-Path -Parent $readme
        $raw = Get-Content -Raw -LiteralPath $readme

        $referenced = [regex]::Matches($raw, '(?:srcset|src)="(images/[^"]+)"') |
                      ForEach-Object { $_.Groups[1].Value } |
                      Select-Object -Unique

        $referenced.Count | Should -BeGreaterThan 0 -Because "module '$module' must reference at least one diagram file"

        foreach ($relative in $referenced) {
            $full = Join-Path $dir $relative
            Test-Path -LiteralPath $full | Should -BeTrue -Because "module '$module' references '$relative', which must exist on disk"
        }
    }

    It "'<module>' keeps the editable Excalidraw source next to the renders" -ForEach $Modules {
        $dir    = Split-Path -Parent $readme
        $source = Join-Path $dir 'images/module-*-architecture.excalidraw'

        @(Get-ChildItem -Path $source -File -ErrorAction SilentlyContinue).Count |
            Should -BeGreaterThan 0 -Because "module '$module' must commit the .excalidraw source, not only the renders (lab-guide-standards.md section 3.3)"
    }
}
