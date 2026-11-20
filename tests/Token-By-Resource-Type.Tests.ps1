<#
.SYNOPSIS
    Pester 5 tests asserting no script requests an access token by URL.

.DESCRIPTION
    Guards requirement 2 of issue #530 (and the Lab 4.4 fix of #529). In an Az session started
    with 'Connect-AzAccount -AccessToken' (an unattended agent or CI run), 'Get-AzAccessToken
    -ResourceUrl' cannot mint the token and the check fails or is skipped; '-ResourceTypeName'
    (Arm, MSGraph, ...) works in both kinds of session.

    Every tracked .ps1 and .psm1 file outside a 'tests' folder is parsed with the PowerShell
    parser, so a mention in a comment or a string is not a call. A Get-AzAccessToken call is a
    violation when it passes a '-Resource*' parameter other than '-ResourceTypeName' (an
    abbreviation of -ResourceUrl, or an alias of it, is treated as the URL form), or splats a
    hashtable that holds a ResourceUrl key. The scan fails when it lists no file or finds no call,
    so it cannot pass by looking at nothing.

.EXAMPLE
    Invoke-Pester -Path .\tests\Token-By-Resource-Type.Tests.ps1 -CI

.NOTES
    Project: SkyCraft
    Issue: #530
#>

#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path

    # True for -ResourceTypeName and its unambiguous abbreviations (-ResourceT and longer).
    function Test-TypeNameParameter {
        param([string]$Name)
        $Name.Length -ge 9 -and 'ResourceTypeName'.StartsWith($Name, [System.StringComparison]::OrdinalIgnoreCase)
    }

    # True for the URL form: -ResourceUrl, any shorter -Res* abbreviation, or a bare -Resource.
    function Test-UrlParameter {
        param([string]$Name)
        $Name.Length -ge 2 -and
            $Name.StartsWith('Re', [System.StringComparison]::OrdinalIgnoreCase) -and
            -not (Test-TypeNameParameter -Name $Name) -and
            ('ResourceUrl'.StartsWith($Name, [System.StringComparison]::OrdinalIgnoreCase) -or
             $Name.StartsWith('Resource', [System.StringComparison]::OrdinalIgnoreCase))
    }

    # Parses one file; returns one record per Get-AzAccessToken call with the lines that use the URL form.
    function Get-AccessTokenCall {
        param([Parameter(Mandatory)][string]$Path)

        $tokens = $null; $errors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$tokens, [ref]$errors)
        $commands = $ast.FindAll({
                param($node)
                $node -is [System.Management.Automation.Language.CommandAst] -and
                $node.GetCommandName() -eq 'Get-AzAccessToken'
            }, $true)

        foreach ($command in $commands) {
            $badLines = [System.Collections.Generic.List[int]]::new()
            foreach ($element in $command.CommandElements) {
                if ($element -is [System.Management.Automation.Language.CommandParameterAst]) {
                    if (Test-UrlParameter -Name $element.ParameterName) { $badLines.Add($element.Extent.StartLineNumber) }
                } elseif ($element -is [System.Management.Automation.Language.VariableExpressionAst] -and $element.Splatted) {
                    $variable = $element.VariablePath.UserPath
                    $assignments = $ast.FindAll({
                            param($node)
                            $node -is [System.Management.Automation.Language.AssignmentStatementAst] -and
                            $node.Left -is [System.Management.Automation.Language.VariableExpressionAst] -and
                            $node.Left.VariablePath.UserPath -eq $variable
                        }, $true)
                    foreach ($assignment in $assignments) {
                        $tables = $assignment.Right.FindAll({ param($node) $node -is [System.Management.Automation.Language.HashtableAst] }, $true)
                        foreach ($table in $tables) {
                            foreach ($pair in $table.KeyValuePairs) {
                                if ($pair.Item1 -is [System.Management.Automation.Language.StringConstantExpressionAst] -and
                                    (Test-UrlParameter -Name $pair.Item1.Value)) { $badLines.Add($pair.Item1.Extent.StartLineNumber) }
                            }
                        }
                    }
                }
            }
            [pscustomobject]@{ Path = $Path; Line = $command.Extent.StartLineNumber; BadLines = @($badLines | Sort-Object -Unique) }
        }
    }

    # Scans a file list; returns the problems found (empty when the scan is clean and non-vacuous).
    function Get-TokenProblem {
        param([string[]]$File = @(), [string]$Root = '')

        if ($File.Count -eq 0) { return , @('no tracked PowerShell file to scan') }
        $calls = @($File | ForEach-Object { Get-AccessTokenCall -Path $_ })
        $problems = [System.Collections.Generic.List[string]]::new()
        if ($calls.Count -eq 0) { $problems.Add('no Get-AzAccessToken call found in any scanned file') }
        foreach ($call in $calls) {
            foreach ($line in $call.BadLines) {
                $shown = if ($Root) { [System.IO.Path]::GetRelativePath($Root, $call.Path) -replace '\\', '/' } else { $call.Path }
                $problems.Add("${shown}:${line} requests a token by URL; use -ResourceTypeName")
            }
        }
        , @($problems)
    }

    function Initialize-FixtureTree {
        param([hashtable]$Files)
        $root = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $root | Out-Null
        foreach ($name in $Files.Keys) { Set-Content -LiteralPath (Join-Path $root $name) -Value $Files[$name] -Encoding utf8 }
        , @(Get-ChildItem -LiteralPath $root -Filter '*.ps1' | ForEach-Object FullName)
    }
}

Describe 'Token by resource type - repository scan' {

    BeforeAll {
        Push-Location $script:RepoRoot
        try {
            $listed = @(& git ls-files -- '*.ps1' '*.psm1')
            $script:ListExit = $LASTEXITCODE
        } finally { Pop-Location }
        $script:Scanned = @(
            $listed |
                ForEach-Object { $_ -replace '\\', '/' } |
                Where-Object { $_ -notmatch '(^|/)tests/' } |
                ForEach-Object { Join-Path $script:RepoRoot $_ } |
                Where-Object { Test-Path -LiteralPath $_ -PathType Leaf }
        )
    }

    It 'lists the tracked PowerShell files' {
        $script:ListExit | Should -Be 0 -Because 'git ls-files must succeed or the scan is blind'
        $script:Scanned.Count | Should -BeGreaterThan 0
    }

    It 'requests every token by resource type name, never by URL' {
        $problems = Get-TokenProblem -File $script:Scanned -Root $script:RepoRoot
        $problems | Should -BeNullOrEmpty -Because ("a token requested by URL fails in a token-only session (#530, #529):`n" + ($problems -join "`n"))
    }
}

Describe 'Token by resource type - fixture cases' {

    It 'fails a file that calls Get-AzAccessToken -ResourceUrl and names file and line' {
        $files = Initialize-FixtureTree @{ 'Bad.ps1' = "`$x = 1`n`$t = Get-AzAccessToken -ResourceUrl 'https://management.azure.com/'`n" }
        $problems = Get-TokenProblem -File $files -Root (Split-Path $files[0])
        $problems.Count | Should -Be 1
        $problems[0] | Should -Match '^Bad\.ps1:2 '
    }

    It 'fails an abbreviation of -ResourceUrl and the bare -Resource' {
        $files = Initialize-FixtureTree @{
            'Abbrev.ps1' = "Get-AzAccessToken -ResourceU 'https://graph.microsoft.com/'`n"
            'Bare.ps1'   = "Get-AzAccessToken -Resource 'https://graph.microsoft.com/'`n"
        }
        (Get-TokenProblem -File $files).Count | Should -Be 2
    }

    It 'fails a splatted hashtable with a ResourceUrl key' {
        $files = Initialize-FixtureTree @{ 'Splat.ps1' = "`$p = @{ ResourceUrl = 'https://management.azure.com/' }`nGet-AzAccessToken @p`n" }
        $problems = Get-TokenProblem -File $files -Root (Split-Path $files[0])
        $problems.Count | Should -Be 1
        $problems[0] | Should -Match '^Splat\.ps1:1 '
    }

    It 'passes when -ResourceUrl appears only in a comment' {
        $files = Initialize-FixtureTree @{ 'Comment.ps1' = "# Not Get-AzAccessToken -ResourceUrl: it fails with -AccessToken sessions`n`$t = Get-AzAccessToken -ResourceTypeName Arm`n" }
        Get-TokenProblem -File $files | Should -BeNullOrEmpty
    }

    It 'passes -ResourceTypeName, its abbreviation, a splat with ResourceTypeName, and no resource parameter' {
        $files = Initialize-FixtureTree @{
            'Type.ps1'   = "Get-AzAccessToken -ResourceTypeName MSGraph`n"
            'Short.ps1'  = "Get-AzAccessToken -ResourceT Arm`n"
            'Splat.ps1'  = "`$p = @{ ResourceTypeName = 'Arm' }`nGet-AzAccessToken @p`n"
            'None.ps1'   = "Get-AzAccessToken -AsSecureString`n"
        }
        Get-TokenProblem -File $files | Should -BeNullOrEmpty
    }

    It 'fails on an empty tree' {
        $problems = Get-TokenProblem -File @()
        $problems.Count | Should -Be 1
        $problems[0] | Should -Match 'no tracked PowerShell file'
    }

    It 'fails when files exist but none calls Get-AzAccessToken' {
        $files = Initialize-FixtureTree @{ 'Other.ps1' = "Write-Host 'hello'`n" }
        $problems = Get-TokenProblem -File $files
        $problems.Count | Should -Be 1
        $problems[0] | Should -Match 'no Get-AzAccessToken call'
    }
}
