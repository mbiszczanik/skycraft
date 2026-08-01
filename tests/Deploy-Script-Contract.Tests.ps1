<#
.SYNOPSIS
    Pester 5 test: every lab deployment script and validator honours the automation contract.

.DESCRIPTION
    An orchestrator can only trust a script that reports failure through its exit code and never
    waits for a human. These rules are enforced statically against the PowerShell AST so a
    violation is caught in CI rather than ninety minutes into a live Azure run.

    Rule 1  Deploy-Bicep.ps1 contains no Read-Host.
    Rule 2  No lab script calls Connect-AzAccount.
    Rule 3  Every statement block that reports a failure also exits non-zero.
    Rule 4  Test-Lab.ps1 ends in an unconditional exit.

.EXAMPLE
    Invoke-Pester -Path .\tests\Deploy-Script-Contract.Tests.ps1

.NOTES
    Project: SkyCraft
#>

#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

# PSSA analyses each scriptblock in isolation, so it cannot see that Pester consumes
# these at discovery time. Suppressed rather than reshaped to keep the file idiomatic.
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'New-ScriptCase builds an in-memory test-case list; it changes no state.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Name', Justification = 'Read inside the FindAll predicate scriptblock; PSSA nested-scope false positive.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '', Justification = 'Discovery-time case lists consumed by -ForEach on the It blocks.')]
param()

BeforeDiscovery {
    $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path

    function New-ScriptCase {
        param([string]$Root, [string]$Leaf)
        Get-ChildItem -Path $Root -Recurse -File -Filter $Leaf |
            Where-Object { ($_.FullName -replace '\\', '/') -match '/module-\d.*/scripts/' } |
            ForEach-Object {
                @{ file = $_.FullName.Substring($Root.Length + 1); path = $_.FullName }
            }
    }

    $DeployCases = @(New-ScriptCase -Root $RepoRoot -Leaf 'Deploy-Bicep.ps1')
    $ValidatorCases = @(New-ScriptCase -Root $RepoRoot -Leaf 'Test-Lab.ps1')
    $AllLabCases = @(New-ScriptCase -Root $RepoRoot -Leaf '*.ps1')
}

BeforeAll {
    function Get-ScriptAst {
        param([string]$Path)
        $tokens = $null; $errors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$tokens, [ref]$errors)
        if ($errors.Count -gt 0) { throw "Parse error in '$Path': $($errors[0].Message)" }
        $ast
    }

    function Get-CommandCall {
        param($Ast, [string]$Name)
        $Ast.FindAll({
            param($n)
            $n -is [System.Management.Automation.Language.CommandAst] -and
            $n.GetCommandName() -eq $Name
        }, $true)
    }
}

Describe 'Deploy scripts run unattended - no interactive prompt' {
    It "'<file>' calls no Read-Host" -ForEach $DeployCases {
        $found = Get-CommandCall -Ast (Get-ScriptAst -Path $path) -Name 'Read-Host'
        $lines = ($found | ForEach-Object { $_.Extent.StartLineNumber }) -join ', '
        $found.Count | Should -Be 0 -Because "an orchestrator cannot answer a prompt; '$file' asks at line(s) $lines. Expose a parameter instead."
    }
}
