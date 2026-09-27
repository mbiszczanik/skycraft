<#
.SYNOPSIS
    Pester 5 tests: offline Bicep builds resolve one standalone compiler, never 'az bicep'.

.DESCRIPTION
    Issue #144. The tests and tools/Invoke-DryRun.ps1 compiled through 'az bicep', the copy
    the Azure CLI manages, while the deploy scripts compile through the 'bicep' on PATH -
    two toolchains that can be two versions. 'az bicep build --stdout' also crashes with a
    UnicodeEncodeError on Windows once a template pulls in an AVM module with non-ANSI
    metadata (Lab 2.3's dns-zone). tools/BicepCli.psm1 now resolves the compiler for all of
    them. These tests pin:
      - the resolver prefers PATH, falls back to the Azure-CLI-managed binary, and throws
        with an install hint when neither exists
      - no PowerShell file or workflow invokes 'az bicep' again

    Lab guides are out of scope: they teach 'az bicep' next to the other options.

.EXAMPLE
    Invoke-Pester -Path .\tests\Bicep-Cli.Tests.ps1

.NOTES
    Project: SkyCraft
#>

#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path

# Discovery-phase data: -ForEach evaluates here, not in BeforeAll.
Push-Location $RepoRoot
try {
    $PsCases       = @(git ls-files -- '*.ps1' '*.psm1' | ForEach-Object { @{ file = $_; path = (Join-Path $RepoRoot $_) } })
    $WorkflowCases = @(git ls-files -- '.github/workflows/*.yml' | ForEach-Object { @{ file = $_; path = (Join-Path $RepoRoot $_) } })
} finally { Pop-Location }

Describe 'Bicep CLI resolver' {
    BeforeAll {
        Import-Module (Join-Path $PSScriptRoot '..' 'tools' 'BicepCli.psm1') -Force
        $script:SavedConfigDir = $env:AZURE_CONFIG_DIR
    }

    AfterEach {
        $env:AZURE_CONFIG_DIR = $script:SavedConfigDir
    }

    It 'returns the bicep on PATH when there is one' {
        Mock -ModuleName BicepCli Get-Command { [pscustomobject]@{ Source = '/opt/bicep/bicep' } }

        Get-BicepCliPath | Should -Be '/opt/bicep/bicep'
    }

    It 'falls back to the Azure-CLI-managed binary when PATH has none' {
        Mock -ModuleName BicepCli Get-Command { $null }
        $env:AZURE_CONFIG_DIR = Join-Path $TestDrive 'azure'
        $managed = Get-AzCliBicepPath
        New-Item -ItemType File -Path $managed -Force | Out-Null

        Get-BicepCliPath | Should -Be $managed
    }

    It 'places the Azure-CLI-managed binary under the config dir bin folder' {
        $env:AZURE_CONFIG_DIR = Join-Path $TestDrive 'cfg'
        $expectedName = if ($IsWindows) { 'bicep.exe' } else { 'bicep' }

        Get-AzCliBicepPath | Should -Be (Join-Path $TestDrive 'cfg' 'bin' $expectedName)
    }

    It 'throws with both install routes when neither exists' {
        Mock -ModuleName BicepCli Get-Command { $null }
        $env:AZURE_CONFIG_DIR = Join-Path $TestDrive 'empty'

        { Get-BicepCliPath } | Should -Throw '*aka.ms/bicep-install*az bicep install*'
    }
}

Describe "Bicep CLI - no PowerShell file invokes 'az bicep'" {
    It "'<file>' has no 'az bicep' command" -ForEach $PsCases {
        # Commands from the AST, not raw text: comments and help may still explain the history.
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$null, [ref]$null)
        $calls = $ast.FindAll({
                param($node)
                $node -is [System.Management.Automation.Language.CommandAst] -and
                $node.GetCommandName() -eq 'az' -and
                $node.CommandElements.Count -gt 1 -and
                $node.CommandElements[1].Extent.Text -eq 'bicep'
            }, $true)
        $lines = @($calls | ForEach-Object { $_.Extent.StartLineNumber })

        $lines | Should -BeNullOrEmpty -Because "compile through Get-BicepCliPath (tools/BicepCli.psm1); 'az bicep' calls at line(s) $($lines -join ', ')"
    }
}

Describe "Bicep CLI - no workflow invokes 'az bicep'" {
    It "'<file>' has no 'az bicep' step" -ForEach $WorkflowCases {
        $hits = @(Select-String -LiteralPath $path -Pattern '^\s*[^#\s].*\baz bicep\b' | ForEach-Object LineNumber)

        $hits | Should -BeNullOrEmpty -Because "CI installs the standalone Bicep CLI; 'az bicep' at line(s) $($hits -join ', ')"
    }
}
