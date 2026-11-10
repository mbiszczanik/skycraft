<#
.SYNOPSIS
    Pester 5 test: a Test-Lab.ps1 that prints [FAIL] also raises its failure count.

.DESCRIPTION
    Regression guard for #544 (same shape as Setup-Script-Failure-Count.Tests.ps1, for the
    validators). Over every module-*/*/scripts/Test-Lab.ps1, parsed with the PowerShell AST:
    every Write-Host that prints [FAIL] sits in a block that increments a counter (`++` or
    `+= n`), so a failed check is never only printed and the script cannot end with exit 0.

    Scripts that legitimately differ are listed with a reason in
    tests/Test-Lab-Fail-Count.Allowlist.psd1. A broken fixture, built here from a here-string,
    proves the check can fail.

    Offline only.

.NOTES
    Project: SkyCraft
#>

#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeDiscovery {
    $root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    $allow = Import-PowerShellDataFile -LiteralPath (Join-Path $PSScriptRoot 'Test-Lab-Fail-Count.Allowlist.psd1')
    $script:Cases = @(Get-ChildItem -Path $root -Directory -Filter 'module-*' |
            Get-ChildItem -Directory |
            ForEach-Object { Join-Path $_.FullName 'scripts/Test-Lab.ps1' } |
            Where-Object { Test-Path -LiteralPath $_ } |
            ForEach-Object {
                $rel = [System.IO.Path]::GetRelativePath($root, $_) -replace '\\', '/'
                @{ Relative = $rel; Path = $_; Allowed = $allow.ContainsKey($rel) }
            })
}

BeforeAll {
    function Get-UncountedFailPrint {
        param([string]$Text)
        $ast = [System.Management.Automation.Language.Parser]::ParseInput($Text, [ref]$null, [ref]$null)
        $prints = @($ast.FindAll({
                    param($n)
                    $n -is [System.Management.Automation.Language.CommandAst] -and
                    $n.GetCommandName() -eq 'Write-Host' -and $n.Extent.Text -match '\[FAIL\]' -and
                    # the closing summary ("See the [FAIL] lines above") names the marker, it is not a check
                    $n.Extent.Text -notmatch '\[FAIL\] lines'
                }, $true))
        foreach ($print in $prints) {
            $block = $print.Parent
            while ($block -and $block -isnot [System.Management.Automation.Language.StatementBlockAst] -and $block -isnot [System.Management.Automation.Language.NamedBlockAst]) {
                $block = $block.Parent
            }
            $counts = $false
            if ($block) {
                $counts = [bool]$block.Find({
                        param($n)
                        ($n -is [System.Management.Automation.Language.UnaryExpressionAst] -and $n.TokenKind -in 'PlusPlus', 'PostfixPlusPlus') -or
                        ($n -is [System.Management.Automation.Language.AssignmentStatementAst] -and $n.Operator -eq 'PlusEquals')
                    }, $true)
            }
            if (-not $counts) { "line $($print.Extent.StartLineNumber): $($print.Extent.Text.Trim())" }
        }
    }
}

Describe '#544 Test-Lab.ps1 counts every [FAIL] it prints' {

    It 'finds the Test-Lab.ps1 scripts (the guard has something to check)' {
        $found = @(Get-ChildItem -Path (Join-Path $PSScriptRoot '..') -Directory -Filter 'module-*' | Get-ChildItem -Directory |
                ForEach-Object { Join-Path $_.FullName 'scripts/Test-Lab.ps1' } | Where-Object { Test-Path -LiteralPath $_ })
        $found.Count | Should -BeGreaterThan 10
    }

    It '<Relative> counts every [FAIL] it prints' -ForEach $script:Cases {
        if ($Allowed) { Set-ItResult -Skipped -Because 'listed in Test-Lab-Fail-Count.Allowlist.psd1'; return }
        $uncounted = @(Get-UncountedFailPrint -Text (Get-Content -LiteralPath $Path -Raw))
        $uncounted | Should -BeNullOrEmpty -Because 'a [FAIL] that is only printed leaves the run at exit 0'
    }

    It 'every allow-list entry names an existing script and gives a reason' {
        $allow = Import-PowerShellDataFile -LiteralPath (Join-Path $PSScriptRoot 'Test-Lab-Fail-Count.Allowlist.psd1')
        $root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
        foreach ($k in $allow.Keys) {
            Test-Path -LiteralPath (Join-Path $root $k) | Should -BeTrue -Because "$k is on the allow-list"
            [string]$allow[$k] | Should -Not -BeNullOrEmpty
        }
    }

    It 'fails on a fixture that prints [FAIL] without counting it' {
        $broken = @'
$failCount = 0
if (-not $ok) {
    Write-Host "[FAIL] thing missing" -ForegroundColor Red
}
Exit-Lab -FailureCount $failCount
'@
        @(Get-UncountedFailPrint -Text $broken).Count | Should -Be 1
    }

    It 'passes on a fixture that counts the [FAIL] it prints' {
        $good = @'
$failCount = 0
if (-not $ok) {
    Write-Host "[FAIL] thing missing" -ForegroundColor Red
    $failCount++
}
Exit-Lab -FailureCount $failCount
'@
        @(Get-UncountedFailPrint -Text $good).Count | Should -Be 0
    }
}
