<#
.SYNOPSIS
    Pester 5 tests for the repository pre-commit hook (tools/git-hooks/pre-commit).

.DESCRIPTION
    Several agent sessions work on this repository at once. ADR-0003 asks for a git
    worktree per piece of multi-commit work, but as a rule it was broken three times:
    a commit landed on another session's branch in the shared checkout (issue #303).
    The hook turns the rule into a mechanism. It refuses a commit when:

      1. the current branch is main, or
      2. the working tree is the main checkout and another worktree exists.

    Each case is exercised against a throwaway repository under TestDrive, with the
    hook run by git itself (core.hooksPath), so the tests prove what a real commit
    does, not what the script returns in isolation.

.EXAMPLE
    Invoke-Pester -Path .\tests\Git-Hooks.Tests.ps1

.NOTES
    Project: SkyCraft
#>

#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    $script:HookPath = Join-Path $script:RepoRoot 'tools/git-hooks/pre-commit'

    # A repository with one commit on main, the hook installed through core.hooksPath,
    # and a feature branch. Returns the repository path.
    function Build-HookTestRepo {
        param([string]$Root)
        $repo = Join-Path $Root 'repo'
        New-Item -ItemType Directory -Path (Join-Path $repo 'tools/git-hooks') -Force | Out-Null
        Copy-Item -LiteralPath $script:HookPath -Destination (Join-Path $repo 'tools/git-hooks/pre-commit')
        git -C $repo init --quiet --initial-branch=main
        git -C $repo config user.email 'test@example.invalid'
        git -C $repo config user.name 'Hook Test'
        git -C $repo config core.hooksPath tools/git-hooks
        # The fixture has no .gitattributes; keep a global core.autocrlf from touching the hook.
        git -C $repo config core.autocrlf false
        Set-Content -LiteralPath (Join-Path $repo 'a.txt') -Value 'a'
        # The first commit must land on main for the fixture: bypass the hook under test.
        git -C $repo add -A
        git -C $repo commit --quiet --no-verify -m 'init'
        git -C $repo branch feature/one
        return $repo
    }

    # Stages a change and attempts a commit. Returns the exit code and the combined output.
    function Invoke-TestCommit {
        param([string]$Path, [string]$File)
        Add-Content -LiteralPath (Join-Path $Path $File) -Value ([guid]::NewGuid())
        git -C $Path add -A
        $out = git -C $Path commit -m 'change' 2>&1 | Out-String
        return [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = $out }
    }
}

Describe 'pre-commit hook - the file' {
    It 'exists at tools/git-hooks/pre-commit' {
        Test-Path -LiteralPath $script:HookPath | Should -BeTrue
    }

    It 'is checked out with LF line endings, so sh can run it on Windows' {
        $bytes = [System.IO.File]::ReadAllBytes($script:HookPath)
        $bytes | Should -Not -Contain ([byte]13)
    }

    It 'is marked executable in the index, so git runs it on Linux and macOS' {
        $mode = (git -C $script:RepoRoot ls-files --stage -- 'tools/git-hooks/pre-commit') -split '\s+' | Select-Object -First 1
        $mode | Should -Be '100755'
    }
}

Describe 'pre-commit hook - what it refuses' {
    BeforeEach {
        $script:Repo = Build-HookTestRepo -Root (Join-Path $TestDrive ([guid]::NewGuid()))
    }

    It 'refuses a commit on main, even with no other worktree' {
        $result = Invoke-TestCommit -Path $script:Repo -File 'a.txt'
        $result.ExitCode | Should -Not -Be 0
        $result.Output | Should -Match 'main'
    }

    It 'allows a commit on a feature branch in a checkout with no other worktree' {
        git -C $script:Repo switch --quiet feature/one
        $result = Invoke-TestCommit -Path $script:Repo -File 'a.txt'
        $result.ExitCode | Should -Be 0 -Because $result.Output
    }

    It 'refuses a commit in the main checkout while another worktree exists' {
        git -C $script:Repo switch --quiet feature/one
        $wt = Join-Path (Split-Path $script:Repo) 'wt-two'
        git -C $script:Repo worktree add --quiet -b feature/two $wt 2>$null
        $result = Invoke-TestCommit -Path $script:Repo -File 'a.txt'
        $result.ExitCode | Should -Not -Be 0
        $result.Output | Should -Match 'worktree add'
    }

    It 'allows a commit on a feature branch inside a linked worktree' {
        $wt = Join-Path (Split-Path $script:Repo) 'wt-two'
        git -C $script:Repo worktree add --quiet -b feature/two $wt 2>$null
        $result = Invoke-TestCommit -Path $wt -File 'a.txt'
        $result.ExitCode | Should -Be 0 -Because $result.Output
    }

    It 'refuses a commit on main inside a linked worktree' {
        git -C $script:Repo switch --quiet feature/one
        $wt = Join-Path (Split-Path $script:Repo) 'wt-main'
        git -C $script:Repo worktree add --quiet $wt main 2>$null
        $result = Invoke-TestCommit -Path $wt -File 'a.txt'
        $result.ExitCode | Should -Not -Be 0
    }

    It 'refuses a commit from a subdirectory of the main checkout while another worktree exists' {
        git -C $script:Repo switch --quiet feature/one
        $wt = Join-Path (Split-Path $script:Repo) 'wt-two'
        git -C $script:Repo worktree add --quiet -b feature/two $wt 2>$null
        $sub = Join-Path $script:Repo 'tools'
        $result = Invoke-TestCommit -Path $sub -File 'x.txt'
        $result.ExitCode | Should -Not -Be 0
    }
}
