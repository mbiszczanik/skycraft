<#
.SYNOPSIS
    Pester 5 test: no repository suite lists the repository's files with a bare recursive
    Get-ChildItem (#414).

.DESCRIPTION
    On Linux, `Get-ChildItem -Recurse` without -Force skips dot-directories, so on the
    `ubuntu-latest` runner a suite that scans from the repository root never sees `.github/`,
    while a local Windows run does. A suite that lists files from the repository root shall use
    Get-RepoFile (tests/Support/RepoFiles.psm1, built on `git ls-files`) or pass -Force.

    The test parses every `tests/*.Tests.ps1` and fails on a Get-ChildItem (or its aliases gci,
    dir, ls) that has -Recurse, has no -Force, and takes the repository root variable
    ($RepoRoot, $repoRoot, $script:RepoRoot) as its path. A listing of one module folder
    (-LiteralPath of a module directory) is not a repository-root scan and is not flagged.

    The test fails when it finds no suite, and fixtures prove the rule catches what it should.

.EXAMPLE
    Invoke-Pester -Path .\tests\Repo-File-Enumeration.Tests.ps1

.NOTES
    Project: SkyCraft
    Issue: #414
#>

#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeDiscovery {
    $script:Suites = foreach ($file in Get-ChildItem -LiteralPath $PSScriptRoot -File -Filter '*.Tests.ps1') {
        @{ name = $file.Name; path = $file.FullName }
    }
}

BeforeAll {
    # The Get-ChildItem calls in PowerShell text that scan from the repository root recursively
    # without -Force, as 'line: text' strings.
    function Get-BareRootListing {
        param([string]$Text)

        $tokens = $null
        $errors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseInput($Text, [ref]$tokens, [ref]$errors)
        $commands = $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] }, $true)
        foreach ($command in $commands) {
            if ("$($command.GetCommandName())" -notin 'Get-ChildItem', 'gci', 'dir', 'ls') { continue }
            $names = @($command.CommandElements | Where-Object { $_ -is [System.Management.Automation.Language.CommandParameterAst] } | ForEach-Object { $_.ParameterName })
            $has = { param($p) [bool]@($names | Where-Object { $_.Length -ge 3 -and $p.StartsWith($_, [System.StringComparison]::OrdinalIgnoreCase) }).Count }
            if (-not (& $has 'Recurse')) { continue }
            if (& $has 'Force') { continue }
            $text = $command.Extent.Text
            if ($text -notmatch '(?i)\$(script:)?reporoot\b') { continue }
            "$($command.Extent.StartLineNumber): $($text -replace '\s+', ' ')"
        }
    }
}

Describe 'Repository file listing in suites - the rule catches what it should (#414)' {

    It 'flags <case>' -ForEach @(
        @{ case = 'a recursive listing from $RepoRoot'; text = "Get-ChildItem -Path `$RepoRoot -Recurse -File -Filter '*.bicep'" }
        @{ case = 'a listing from $script:RepoRoot'; text = "Get-ChildItem -Path `$script:RepoRoot -Recurse -File" }
        @{ case = 'a listing from a lower-case $repoRoot'; text = "Get-ChildItem -Path `$repoRoot -Recurse -File -Filter '*.md'" }
        @{ case = 'the alias gci'; text = "gci `$RepoRoot -Recurse -File" }
        @{ case = 'an abbreviated -Rec'; text = "Get-ChildItem -Path `$RepoRoot -Rec -File" }
    ) {
        @(Get-BareRootListing -Text $text).Count | Should -Be 1
    }

    It 'does not flag <case>' -ForEach @(
        @{ case = 'a listing with -Force'; text = "Get-ChildItem -Path `$RepoRoot -Recurse -File -Force" }
        @{ case = 'a listing of one module folder'; text = "Get-ChildItem -LiteralPath `$dir.FullName -Recurse -File -Filter '*.ps1'" }
        @{ case = 'a listing that is not recursive'; text = "Get-ChildItem -LiteralPath `$RepoRoot -File -Filter 'README.*'" }
        @{ case = 'Get-RepoFile'; text = "Get-RepoFile -Root `$RepoRoot -Filter '*.bicep'" }
        @{ case = 'a comment that names the cmdlet'; text = "# Get-ChildItem -Path `$RepoRoot -Recurse -File" }
    ) {
        @(Get-BareRootListing -Text $text) | Should -BeNullOrEmpty
    }

    It 'gives the line of the listing' {
        $finding = @(Get-BareRootListing -Text "`$a = 1`n`$b = Get-ChildItem -Path `$RepoRoot -Recurse -File")
        $finding[0] | Should -BeLike '2: *'
    }
}

Describe 'Repository file listing in suites - every suite (#414)' {

    It 'finds the suites to check' -TestCases @(@{ count = @($script:Suites).Count }) {
        $count | Should -BeGreaterThan 30 -Because 'finding none means the scan is broken'
    }

    It '<name> does not list the repository from its root without -Force' -ForEach @($script:Suites) {
        $findings = @(Get-BareRootListing -Text (Get-Content -Raw -LiteralPath $path))
        $findings | Should -BeNullOrEmpty -Because "Linux skips dot-directories without -Force (#414); use Get-RepoFile from tests/Support/RepoFiles.psm1. Found:`n$($findings -join "`n")"
    }
}
