<#
.SYNOPSIS
    Pester 5 test: every module ships README.md (lowercase) and every link uses that casing.

.DESCRIPTION
    docs/project-standards.md §1.1 warns that "Directory naming must match link targets
    exactly" — broken case is invisible on case-insensitive filesystems (Windows) but
    breaks links on Linux/macOS checkouts. This test asserts:
      - every module-*/ directory contains a file literally named 'README.md' (lowercase)
      - no Markdown file in the repo links to 'README.MD' (uppercase)

.EXAMPLE
    Invoke-Pester -Path .\tests\Readme-Casing.Tests.ps1

.NOTES
    Project: SkyCraft
#>

#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

$RepoRoot   = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$ModuleDirs = Get-ChildItem -Path $RepoRoot -Directory -Filter 'module-*' |
              Sort-Object Name
$ModuleCases = $ModuleDirs | ForEach-Object {
    @{ module = $_.Name; path = $_.FullName }
}

# Scan every tracked or new-but-unignored .md file for 'README.MD' references. git, not
# Get-ChildItem: the Linux runner skips dot-directories (.github) without -Force, and -Force
# would pull in ignored worktrees and .patches.
$MarkdownFiles = @(& git -C $RepoRoot ls-files --cached --others --exclude-standard -- '*.md' '*.MD')
if ($LASTEXITCODE -ne 0 -or $MarkdownFiles.Count -eq 0) {
    throw "git ls-files returned no Markdown files (exit $LASTEXITCODE); the casing scan cannot run."
}
$MarkdownCases = $MarkdownFiles | ForEach-Object {
    @{
        file = $_
        path = Join-Path $RepoRoot $_
    }
}

Describe 'README filename casing' {
    It "'<module>' ships a lowercase README.md" -ForEach $ModuleCases {
        $files = Get-ChildItem -LiteralPath $path -File -Filter 'README.*' |
                 Where-Object { $_.Name -like 'README.*' }
        # Must contain exactly one README file named literally 'README.md' (lowercase).
        $lowercase = $files | Where-Object { $_.Name -ceq 'README.md' }
        $uppercase = $files | Where-Object { $_.Name -ceq 'README.MD' }
        $lowercase | Should -Not -BeNullOrEmpty -Because "'$module' must provide a lowercase README.md"
        $uppercase | Should -BeNullOrEmpty     -Because "'$module' must not also ship an uppercase README.MD"
    }

    It 'repo root ships a lowercase README.md' {
        $root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
        $rootReadmeLower = Test-Path -LiteralPath (Join-Path $root 'README.md')
        $rootReadmeLower | Should -BeTrue -Because 'root README.md is linked as lowercase by every module back-reference'

        $all = Get-ChildItem -LiteralPath $root -File -Filter 'README.*'
        $upper = $all | Where-Object { $_.Name -ceq 'README.MD' }
        $upper | Should -BeNullOrEmpty -Because 'mixed casing at the root breaks module back-links on case-sensitive filesystems'
    }
}

Describe 'README link casing in Markdown' {
    It 'scans Markdown under dot-directories' {
        # Discovery-phase variables are not visible inside It, so list again.
        $listed = @(& git -C (Join-Path $PSScriptRoot '..') ls-files --cached --others --exclude-standard -- '*.md' '*.MD')
        $listed | Should -Contain '.github/PULL_REQUEST_TEMPLATE.md' -Because 'the scan must list the same files on Windows and Linux'
    }

    It "'<file>' contains no link to 'README.MD'" -ForEach $MarkdownCases {
        $text = Get-Content -Raw -LiteralPath $path
        # Case-sensitive: 'README.MD' must not appear literally; 'README.md' is fine.
        $text | Should -Not -CMatch 'README\.MD' -Because "'$file' must link to README.md, not README.MD"
    }
}
