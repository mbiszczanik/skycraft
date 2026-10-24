<#
.SYNOPSIS
    Pester 5 tests for the outputs Lab 3.1's Deploy-Bicep.ps1 prints after a deployment.

.DESCRIPTION
    Issue #354, step 3.1.19: the script piped $dep.Outputs to Format-Table, which printed the
    output names with empty values. Each entry of that dictionary is a DeploymentVariable whose
    value sits in .Value. These tests lift Get-DeploymentOutputRow out of the script with the
    PowerShell parser and feed it a dictionary of the same shape; nothing reaches Azure.

.EXAMPLE
    Invoke-Pester -Path .\Deploy-Bicep.Tests.ps1

.NOTES
    Project: SkyCraft
    Lab: 3.1 - Infrastructure as Code
#>

#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    $script:ScriptPath = (Resolve-Path (Join-Path $PSScriptRoot '..' 'scripts' 'Deploy-Bicep.ps1')).Path
    $script:Text = Get-Content -Raw -LiteralPath $script:ScriptPath

    $parseError = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($script:ScriptPath, [ref]$null, [ref]$parseError)
    if ($parseError) { throw "$script:ScriptPath does not parse: $($parseError[0].Message)" }
    $script:Definition = $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Get-DeploymentOutputRow' }, $true) |
        Select-Object -First 1
    if ($script:Definition) { . ([scriptblock]::Create($script:Definition.Extent.Text)) }

    # The shape New-AzSubscriptionDeployment returns: name -> DeploymentVariable (Type, Value).
    function Get-StubOutputDictionary {
        $outputs = [System.Collections.Generic.Dictionary[string, object]]::new()
        $outputs['outDevVnetId']               = [pscustomobject]@{ Type = 'String'; Value = '/subscriptions/stub/resourceGroups/dev-skycraft-swc-rg/providers/Microsoft.Network/virtualNetworks/dev-skycraft-swc-vnet' }
        $outputs['outDevLoadBalancerPublicIp'] = [pscustomobject]@{ Type = 'String'; Value = '203.0.113.10' }
        $outputs['outDevVnetDeployed']         = [pscustomobject]@{ Type = 'Bool'; Value = $false }
        $outputs
    }
}

Describe 'Lab 3.1 Deploy-Bicep.ps1 - deployment outputs printout (#354)' {

    It 'defines Get-DeploymentOutputRow' {
        $script:Definition | Should -Not -BeNullOrEmpty
    }

    It 'returns every output with its value, sorted by name' {
        $rows = @(Get-DeploymentOutputRow -Outputs (Get-StubOutputDictionary))
        @($rows.Name) | Should -Be @('outDevLoadBalancerPublicIp', 'outDevVnetDeployed', 'outDevVnetId')
        $rows[0].Value | Should -Be '203.0.113.10'
        $rows[1].Value | Should -BeFalse
        $rows[1].Value | Should -Not -BeNullOrEmpty -Because 'false is a value, not a blank'
        $rows[2].Value | Should -Match '/virtualNetworks/dev-skycraft-swc-vnet$'
    }

    It 'returns nothing for a deployment without outputs' {
        @(Get-DeploymentOutputRow -Outputs $null).Count | Should -Be 0
    }

    It 'prints the rows instead of formatting the outputs dictionary' {
        $script:Text | Should -Not -Match '\.Outputs\s*\|\s*Format-Table' -Because 'Format-Table on the dictionary prints the names with empty values'
        $script:Text | Should -Match 'Get-DeploymentOutputRow -Outputs \$dep\.Outputs'
    }
}
