<#
.SYNOPSIS
    Pester 5 tests for the Lab 3.3 deploy script's check for a Consumption-only environment.

.DESCRIPTION
    Review of the Lab 3.3 guide PR (#229): main.bicep now declares the Consumption workload profile,
    so the environment it deploys is a Workload profiles environment, the type the Portal creates.
    An environment deployed by an older version of the template is Consumption-only, and Azure
    cannot change an environment's type, so redeploying onto it fails after the registry bootstrap.
    Deploy-Bicep.ps1 now looks for such an environment first and stops with what to do.

    The check is the function Get-LabConsumptionOnlyEnvironment. These tests lift it out of the
    script with the PowerShell parser and run it against a stub Get-AzResource defined in the test
    scope. The script itself is not run: New-AzSubscriptionDeployment and
    Get-AzSubscriptionDeploymentWhatIfResult are aliases in Az.Resources, which take precedence over
    a stub function, so a run whose check regressed could reach Azure. No Azure connection is used.

.EXAMPLE
    Invoke-Pester -Path .\Deploy-Bicep.Tests.ps1

.NOTES
    Project: SkyCraft
    Lab: 3.3 - Containers
#>

#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    $script:ScriptPath = (Resolve-Path (Join-Path $PSScriptRoot '..' 'scripts' 'Deploy-Bicep.ps1')).Path

    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($script:ScriptPath, [ref]$null, [ref]$parseErrors)
    if ($parseErrors) { throw "$($script:ScriptPath) does not parse: $($parseErrors[0].Message)" }
    $definition = $ast.Find({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Get-LabConsumptionOnlyEnvironment' }, $true)
    if (-not $definition) { throw "Get-LabConsumptionOnlyEnvironment not found in $($script:ScriptPath)" }
    . ([scriptblock]::Create($definition.Extent.Text))

    # What the stub returns, set per test.
    $script:Environments = @()
    $script:LookupError  = $null
    $script:LookupCalls  = [System.Collections.Generic.List[string]]::new()

    function Get-AzResource {
        [CmdletBinding()]
        param([string]$ResourceType, [string]$Name, [string]$ResourceGroupName, [switch]$ExpandProperties)
        $script:LookupCalls.Add("$ResourceType|$Name|$ResourceGroupName|$ExpandProperties")
        if ($script:LookupError) { Write-Error -ErrorId 'AuthorizationFailed' -Message $script:LookupError }
        $script:Environments | Where-Object { $_.Name -eq $Name }
    }

    function Get-StubEnvironment {
        param([string]$Name, [string]$ResourceGroupName, [object[]]$WorkloadProfiles)
        [pscustomobject]@{
            Name              = $Name
            ResourceGroupName = $ResourceGroupName
            Properties        = [pscustomobject]@{ workloadProfiles = $WorkloadProfiles }
        }
    }
}

Describe 'Lab 3.3 Deploy-Bicep.ps1 - a Consumption-only environment stops the deployment' {

    BeforeEach {
        $script:Environments = @()
        $script:LookupError  = $null
        $script:LookupCalls.Clear()
    }

    It 'returns the environment an older template deployed, without workload profiles' {
        $script:Environments = @(Get-StubEnvironment -Name 'dev-skycraft-swc-cae-02' -ResourceGroupName 'dev-skycraft-swc-rg' -WorkloadProfiles $null)
        $found = Get-LabConsumptionOnlyEnvironment -ResourceGroupName 'dev-skycraft-swc-rg' -Name 'dev-skycraft-swc-cae-02'
        $found.Name | Should -Be 'dev-skycraft-swc-cae-02'
        $script:LookupCalls | Should -Contain 'Microsoft.App/managedEnvironments|dev-skycraft-swc-cae-02||True'
    }

    It 'returns nothing for a Workload profiles environment, which the template deploys onto' {
        $script:Environments = @(Get-StubEnvironment -Name 'dev-skycraft-swc-cae-02' -ResourceGroupName 'dev-skycraft-swc-rg' `
            -WorkloadProfiles @([pscustomobject]@{ name = 'Consumption'; workloadProfileType = 'Consumption' }))
        Get-LabConsumptionOnlyEnvironment -ResourceGroupName 'dev-skycraft-swc-rg' -Name 'dev-skycraft-swc-cae-02' | Should -BeNullOrEmpty
    }

    It 'returns nothing when no environment exists, or only one in another resource group' {
        Get-LabConsumptionOnlyEnvironment -ResourceGroupName 'dev-skycraft-swc-rg' -Name 'dev-skycraft-swc-cae-02' | Should -BeNullOrEmpty
        $script:Environments = @(Get-StubEnvironment -Name 'dev-skycraft-swc-cae-02' -ResourceGroupName 'another-rg' -WorkloadProfiles $null)
        Get-LabConsumptionOnlyEnvironment -ResourceGroupName 'dev-skycraft-swc-rg' -Name 'dev-skycraft-swc-cae-02' | Should -BeNullOrEmpty
    }

    It 'throws when the lookup fails, so the script reports it instead of deploying blind' {
        $script:LookupError = "The client 'stub' does not have authorization to perform action 'read'."
        { Get-LabConsumptionOnlyEnvironment -ResourceGroupName 'dev-skycraft-swc-rg' -Name 'dev-skycraft-swc-cae-02' } | Should -Throw '*does not have authorization*'
    }

    It 'is called before the what-if and before Phase 1, and its result stops the script through Exit-Lab' {
        $text = Get-Content -LiteralPath $script:ScriptPath -Raw
        $check  = $text.IndexOf('$legacyCae = Get-LabConsumptionOnlyEnvironment')
        $check  | Should -BeGreaterThan 0
        $check  | Should -BeLessThan $text.IndexOf('if ($WhatIf) {')
        $check  | Should -BeLessThan $text.IndexOf('PHASE 1: BOOTSTRAP')
        $text   | Should -Match '(?s)if \(\$legacyCae\) \{.*?Remove-LabResource\.ps1 -Environment \$Environment.*?Exit-Lab -FailureCount 1'
    }
}
