<#
.SYNOPSIS
    Pester 5 test: Lab 2.2's Bicep, PowerShell script and validator create and expect only the
    ASGs and NSGs the guide creates.

.DESCRIPTION
    Issue #345: the template and Deploy-Security.ps1 created three prod ASGs and an empty hub NSG
    that the guide never creates, and Test-Lab.ps1 failed a Portal-built lab on them (exit 4).
    The cleanup keeps removing them, for estates built before the change.

.EXAMPLE
    Invoke-Pester -Path .\tests\Lab22-Guide-Resources.Tests.ps1

.NOTES
    Project: SkyCraft
    Issue:   #345
#>

#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    $script:Lab22 = Join-Path (Resolve-Path (Join-Path $PSScriptRoot '..')).Path 'module-2-networking/2.2-secure-access'
    $script:Removed = 'platform-skycraft-swc-nsg', 'prod-skycraft-swc-asg'
}

Describe 'Lab 2.2 - only the resources the guide creates' {

    It '<file> neither creates nor expects the prod ASGs or the hub NSG' -ForEach @(
        @{ file = 'bicep/main.bicep' }
        @{ file = 'scripts/Deploy-Security.ps1' }
        @{ file = 'scripts/Test-Lab.ps1' }
    ) {
        $text = Get-Content -Raw -LiteralPath (Join-Path $script:Lab22 $file)
        foreach ($name in $script:Removed) { $text | Should -Not -Match ([regex]::Escape($name)) }
    }

    It 'creates the three dev ASGs the guide creates' {
        $text = Get-Content -Raw -LiteralPath (Join-Path $script:Lab22 'bicep/main.bicep')
        $text | Should -Match "varAsgTiers = \['auth', 'world', 'db'\]"
        $text | Should -Match "name: 'dev-skycraft-swc-asg-\$\{tier\}'"
    }

    It 'Deploy-Security.ps1 re-adds an existing rule, so a rule switched to ASG sources in step 2.2.9 is replaced' {
        $ast = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $script:Lab22 'scripts/Deploy-Security.ps1'), [ref]$null, [ref]$null)
        $commands = foreach ($c in $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] }, $true)) { $c.GetCommandName() }
        $commands | Should -Contain 'Remove-AzNetworkSecurityRuleConfig'
        $commands | Should -Not -Contain 'Set-AzNetworkSecurityRuleConfig' -Because 'updating in place keeps the ASG sources and Azure refuses the rule'
    }

    It 'the cleanup still removes them from estates built before #345' {
        $text = Get-Content -Raw -LiteralPath (Join-Path $script:Lab22 'scripts/Remove-LabResource.ps1')
        foreach ($name in $script:Removed) { $text | Should -Match ([regex]::Escape($name)) }
    }
}
