<#
.SYNOPSIS
    Pester 5 tests for the Lab 3.1 deploy script's dev-only guard.

.DESCRIPTION
    main.bicep declares the dev VNet, NSGs and load balancer whatever parEnvironment says (#275),
    so Deploy-Bicep.ps1 stops on any -Environment other than dev before it touches Azure.
    The script is read with the PowerShell parser, not run: New-AzSubscriptionDeployment is an
    alias in Az.Resources, so a run whose guard regressed could reach Azure.

.NOTES
    Project: SkyCraft
    Lab: 3.1 - Infrastructure as Code
#>

#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    $script:ScriptPath = (Resolve-Path (Join-Path $PSScriptRoot '..' 'scripts' 'Deploy-Bicep.ps1')).Path
    $parseErrors = $null
    $script:Ast = [System.Management.Automation.Language.Parser]::ParseFile($script:ScriptPath, [ref]$null, [ref]$parseErrors)
    if ($parseErrors) { throw "$($script:ScriptPath) does not parse: $($parseErrors[0].Message)" }

    $script:Guard = $script:Ast.Find({
            param($n)
            $n -is [System.Management.Automation.Language.IfStatementAst] -and
            $n.Clauses[0].Item1.Extent.Text -match '^\$Environment\s+-ne\s+''dev''$'
        }, $false)
    $script:FirstAzCall = $script:Ast.Find({
            param($n)
            $n -is [System.Management.Automation.Language.CommandAst] -and $n.GetCommandName() -like '*-Az*'
        }, $true)
}

Describe 'Lab 3.1 Deploy-Bicep.ps1 dev-only guard (#275)' {
    It 'has a top-level guard on $Environment -ne ''dev''' {
        $script:Guard | Should -Not -BeNullOrEmpty
    }

    It 'ends the guard through Exit-Lab -FailureCount 1' {
        $script:Guard.Clauses[0].Item2.Extent.Text | Should -Match 'Exit-Lab\s+-FailureCount\s+1'
    }

    It 'places the guard before the first Az cmdlet call' {
        $script:FirstAzCall | Should -Not -BeNullOrEmpty
        $script:Guard.Extent.StartOffset | Should -BeLessThan $script:FirstAzCall.Extent.StartOffset
    }

    It 'still accepts prod at parameter binding, so the guard explains instead of a binding error' {
        $envParam = $script:Ast.ParamBlock.Parameters | Where-Object { $_.Name.VariablePath.UserPath -eq 'Environment' }
        $envParam.Attributes.Extent.Text -join ' ' | Should -Match "ValidateSet\('dev', 'prod'\)"
    }
}
