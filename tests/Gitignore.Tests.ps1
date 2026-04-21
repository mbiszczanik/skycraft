<#
.SYNOPSIS
    Pester 5 tests asserting .gitignore contains the expected patterns and not the
    typo patterns that were removed.

.DESCRIPTION
    Guards the repo against two regressions:
      1. The '*.agent' and '*.github' patterns that were in .gitignore ignored
         files literally ending in '.agent' / '.github' (no matching use case in
         this repo, and '*.github' was most likely meant to be '.github/').
         They must not come back.
      2. The session scratch directory ('.patches/') must stay ignored so a
         clean 'git status' does not show transient working state.

    For (2) the test uses 'git check-ignore' rather than regexing the file, so
    it catches real matching behaviour including negations.

.EXAMPLE
    Invoke-Pester -Path .\tests\Gitignore.Tests.ps1

.NOTES
    Project: SkyCraft
#>

#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    $script:RepoRoot  = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    $script:Gitignore = Join-Path $script:RepoRoot '.gitignore'
    $script:GitignoreText = Get-Content -Raw -LiteralPath $script:Gitignore
}

Describe '.gitignore - typo regressions' {
    It 'does not contain the "*.agent" glob (no real use case in this repo)' {
        $script:GitignoreText | Should -Not -Match '(?m)^\*\.agent\s*$'
    }

    It 'does not contain the "*.github" glob (typo; was misread as ".github/")' {
        $script:GitignoreText | Should -Not -Match '(?m)^\*\.github\s*$'
    }
}

Describe '.gitignore - required ignore patterns' {
    It 'ignores the local patch scratch directory (.patches/)' {
        Push-Location $script:RepoRoot
        try {
            git check-ignore -q '.patches/example.patch'
            $LASTEXITCODE | Should -Be 0 -Because '.patches/ is a working-tree scratch dir and must not show up in git status'
        } finally { Pop-Location }
    }

    It 'still ignores compiled Bicep ARM output (**/bicep/*.json)' {
        Push-Location $script:RepoRoot
        try {
            git check-ignore -q 'module-2-networking/2.1-virtual-networks/bicep/main.json'
            $LASTEXITCODE | Should -Be 0 -Because 'compiled ARM templates are generated artefacts'
        } finally { Pop-Location }
    }

    It 'still ignores Azure credential file patterns' {
        Push-Location $script:RepoRoot
        try {
            git check-ignore -q 'credentials.json'
            $LASTEXITCODE | Should -Be 0
            git check-ignore -q 'secret.pfx'
            $LASTEXITCODE | Should -Be 0
        } finally { Pop-Location }
    }
}
