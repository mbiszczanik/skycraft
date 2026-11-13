<#
.SYNOPSIS
    Pester 5 test: every lab script uses the shared module tools/LabCommon.psm1 (issue #301).

.DESCRIPTION
    Gate for the shared lab module. Over every script under module-*/*/scripts/ (subfolders
    included) it fails when a script:

      NoImport             does not import tools/LabCommon.psm1,
      DirectSetShouldExit  calls $Host.SetShouldExit itself (only Exit-Lab may),
      BareCountExit        ends with a non-zero `exit` such as `exit $failCount`.

    Existing violators are listed in tests/lab-common-usage-allowlist.psd1 (rule, file, reason).
    An entry whose script no longer violates its rule fails the suite, so the list only shrinks.

    Exit-Code-Propagation.Tests.ps1 already holds the deeper exit contract (import path,
    Exit-Lab as the last statement, trap, Write-Error) and is not repeated here; this file adds
    the scan over scripts/ subfolders, the allowlist with stale detection, and fixtures that
    show each rule fails a non-conforming script.

.EXAMPLE
    Invoke-Pester -Path .\tests\Lab-Common-Usage.Tests.ps1

.NOTES
    Project: SkyCraft
#>

#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeDiscovery {
    $allowlist = Import-PowerShellDataFile -LiteralPath (Join-Path $PSScriptRoot 'lab-common-usage-allowlist.psd1')
    $script:AllowEntries = @($allowlist.Entries | ForEach-Object { @{ rule = $_.Rule; file = $_.File; reason = $_.Reason } })
    $script:Rules = @('NoImport', 'DirectSetShouldExit', 'BareCountExit') | ForEach-Object { @{ rule = $_ } }
}

BeforeAll {
    $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    $script:KnownRules = @('NoImport', 'DirectSetShouldExit', 'BareCountExit')

    # Module directories first, then recurse: `Get-ChildItem -Path 'module-*' -Recurse` returns
    # nothing on pwsh 7.6.
    function Get-LabScriptRelativePath {
        param([Parameter(Mandatory)][string]$Root)

        foreach ($module in Get-ChildItem -LiteralPath $Root -Directory -Filter 'module-*') {
            foreach ($lab in Get-ChildItem -LiteralPath $module.FullName -Directory) {
                $scripts = Join-Path $lab.FullName 'scripts'
                if (-not (Test-Path -LiteralPath $scripts -PathType Container)) { continue }
                Get-ChildItem -LiteralPath $scripts -Recurse -File -Filter '*.ps1' |
                    ForEach-Object { $_.FullName.Substring($Root.Length + 1) -replace '\\', '/' }
            }
        }
    }

    # The rules a script text breaks, read from its syntax tree so that a call quoted in a
    # comment or a string is not counted.
    function Get-LabCommonViolation {
        param([Parameter(Mandatory)][string]$Text)

        $ast = [System.Management.Automation.Language.Parser]::ParseInput($Text, [ref]$null, [ref]$null)

        $import = $ast.FindAll({ param($n)
            $n -is [System.Management.Automation.Language.CommandAst] -and
            $n.GetCommandName() -eq 'Import-Module' -and
            $n.Extent.Text -match 'LabCommon\.psm1'
        }, $true)
        if (@($import).Count -eq 0) { 'NoImport' }

        $setShouldExit = $ast.FindAll({ param($n)
            $n -is [System.Management.Automation.Language.InvokeMemberExpressionAst] -and
            $n.Member.Extent.Text -eq 'SetShouldExit'
        }, $true)
        if (@($setShouldExit).Count -gt 0) { 'DirectSetShouldExit' }

        $countExit = $ast.FindAll({ param($n)
            $n -is [System.Management.Automation.Language.ExitStatementAst] -and
            $n.Pipeline -and $n.Pipeline.Extent.Text.Trim() -ne '0'
        }, $true)
        if (@($countExit).Count -gt 0) { 'BareCountExit' }
    }

    # Allowlist entries whose script no longer breaks the rule, or no longer exists.
    function Get-StaleEntry {
        param(
            [Parameter(Mandatory)][object[]]$Entry,
            [Parameter(Mandatory)][scriptblock]$ViolationOf
        )

        foreach ($e in $Entry) {
            $found = @(& $ViolationOf $e.file)
            if ($e.rule -notin $found) { $e.file }
        }
    }

    $script:LabScripts = @(Get-LabScriptRelativePath -Root $script:RepoRoot)
}

Describe 'Lab scripts use the shared module' {

    It 'finds lab scripts to scan' {
        $script:LabScripts.Count | Should -BeGreaterThan 0
    }

    Context 'Allowlist' {

        It 'names a known rule and a reason for <file>' -ForEach $script:AllowEntries {
            $rule | Should -BeIn $script:KnownRules
            $reason | Should -Not -BeNullOrEmpty
        }

        It 'lists <file> only while it still breaks <rule>' -ForEach $script:AllowEntries {
            $file | Should -BeIn $script:LabScripts
            $text = Get-Content -Raw -LiteralPath (Join-Path $script:RepoRoot $file)
            @(Get-LabCommonViolation -Text $text) | Should -Contain $rule
        }
    }

    Context 'Stale entries' {

        It 'finds none in the allowlist' {
            $entries = @((Import-PowerShellDataFile -LiteralPath (Join-Path $PSScriptRoot 'lab-common-usage-allowlist.psd1')).Entries |
                ForEach-Object { @{ rule = $_.Rule; file = $_.File } })
            $stale = @(Get-StaleEntry -Entry $entries -ViolationOf {
                param($f)
                $path = Join-Path $script:RepoRoot $f
                if (Test-Path -LiteralPath $path -PathType Leaf) { Get-LabCommonViolation -Text (Get-Content -Raw -LiteralPath $path) }
            })
            $stale | Should -BeNullOrEmpty -Because 'an entry whose script no longer violates must be removed'
        }
    }

    Context 'Rule <rule>' -ForEach $script:Rules {

        It 'is broken by no lab script outside the allowlist' {
            $allowed = @(
                (Import-PowerShellDataFile -LiteralPath (Join-Path $PSScriptRoot 'lab-common-usage-allowlist.psd1')).Entries |
                    Where-Object { $_.Rule -eq $rule } | ForEach-Object { $_.File })
            $violators = @($script:LabScripts | Where-Object {
                $_ -notin $allowed -and
                $rule -in @(Get-LabCommonViolation -Text (Get-Content -Raw -LiteralPath (Join-Path $script:RepoRoot $_)))
            })
            $violators | Should -BeNullOrEmpty -Because 'a lab script imports tools/LabCommon.psm1 and ends through Exit-Lab (issue #301)'
        }
    }

    Context 'The gate fails a non-conforming script' {

        BeforeAll {
            $script:Import = "Import-Module (Join-Path `$PSScriptRoot '../../../tools/LabCommon.psm1') -Force"
        }

        It 'flags a script that does not import the module' {
            @(Get-LabCommonViolation -Text "Write-Host 'x'`nExit-Lab -FailureCount 0") | Should -Contain 'NoImport'
        }

        It 'does not count an import quoted in a comment' {
            @(Get-LabCommonViolation -Text "# Import-Module LabCommon.psm1`nExit-Lab -FailureCount 0") | Should -Contain 'NoImport'
        }

        It 'flags a direct SetShouldExit call' {
            @(Get-LabCommonViolation -Text "$script:Import`n`$Host.SetShouldExit(1)") | Should -Contain 'DirectSetShouldExit'
        }

        It 'flags exit $failCount' {
            @(Get-LabCommonViolation -Text "$script:Import`nexit `$failCount") | Should -Contain 'BareCountExit'
        }

        It 'does not count exit 0 or a call quoted in a comment' {
            @(Get-LabCommonViolation -Text "$script:Import`n# `$Host.SetShouldExit(1)`nexit 0") | Should -BeNullOrEmpty
        }

        It 'passes a conforming script' {
            @(Get-LabCommonViolation -Text "$script:Import`nExit-Lab -FailureCount `$failCount") | Should -BeNullOrEmpty
        }

        It 'reports an allowlist entry that no longer violates as stale' {
            $entry = @{ rule = 'NoImport'; file = 'fixture/clean.ps1' }
            $stale = @(Get-StaleEntry -Entry @($entry) -ViolationOf { param($f) $null = $f; @() })
            $stale | Should -Be @('fixture/clean.ps1')
        }

        It 'does not report an entry that still violates' {
            $entry = @{ rule = 'NoImport'; file = 'fixture/dirty.ps1' }
            $stale = @(Get-StaleEntry -Entry @($entry) -ViolationOf { param($f) $null = $f; @('NoImport') })
            $stale | Should -BeNullOrEmpty
        }

        It 'scans lab script subfolders' {
            $dir = Join-Path $TestDrive 'module-9-fixture/9.1-fixture/scripts/sub'
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $dir 'Nested.ps1') -Value 'exit 0'
            Get-LabScriptRelativePath -Root $TestDrive | Should -Contain 'module-9-fixture/9.1-fixture/scripts/sub/Nested.ps1'
        }
    }
}
