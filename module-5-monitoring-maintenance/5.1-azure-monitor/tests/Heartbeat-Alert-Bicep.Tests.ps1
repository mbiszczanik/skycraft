<#
.SYNOPSIS
    Pester 5 tests: the Lab 5.1 Bicep creates the missing-Heartbeat log search alert.

.DESCRIPTION
    Regression cover for issue #357. Lab 5.1 promised log search alerts from KQL in its objectives
    but had only a metric alert. Step 5.1.8 adds a log search alert that fires when the monitored
    VM sends no Heartbeat row for 5 minutes, on the Portal, Az PowerShell and Bicep paths. These
    tests compile bicep/main.bicep and assert on the ARM template the deploy sends:

      1. A scheduled query rule 'skycraft-heartbeat-alert' in the platform group, in the lab's
         region, with the canonical tags.
      2. It is scoped to the VM that gets the agent, counts Heartbeat rows and fires below one,
         every 5 minutes over 5 minutes, severity 1, enabled.
      3. It notifies the lab's action group.

    No subscription is used. Building needs the AVM modules, from mcr.microsoft.com or the local
    ~/.bicep cache.

.EXAMPLE
    Invoke-Pester -Path .\Heartbeat-Alert-Bicep.Tests.ps1

.NOTES
    Project: SkyCraft
    Lab: 5.1 - Azure Monitor
    Issue: #357
#>

#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    $script:LabRoot  = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    $script:RepoRoot = (Resolve-Path (Join-Path $script:LabRoot '..' '..')).Path

    Import-Module (Join-Path $script:RepoRoot 'tools' 'BicepCli.psm1') -Force
    $script:WorkDir = Join-Path ([System.IO.Path]::GetTempPath()) ('skycraft-357-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $script:WorkDir -Force | Out-Null

    # --outfile rather than --stdout, as tests/Network-Redeploy.Tests.ps1 explains.
    $out = Join-Path $script:WorkDir 'lab51.json'
    $null = & (Get-BicepCliPath) build (Join-Path $script:LabRoot 'bicep' 'main.bicep') --outfile $out 2>&1
    if ($LASTEXITCODE -ne 0) { throw 'bicep build failed for Lab 5.1 main.bicep' }
    $script:Template = Get-Content -Raw -LiteralPath $out | ConvertFrom-Json -AsHashtable

    $resources = if ($script:Template.resources -is [System.Collections.IDictionary]) { $script:Template.resources.Values } else { $script:Template.resources }
    $script:Alert = $resources | Where-Object { $_.name -eq 'heartbeat-alert-deployment' } | Select-Object -First 1
    $script:Params = $script:Alert.properties.parameters
}

AfterAll {
    if ($script:WorkDir) { Remove-Item -LiteralPath $script:WorkDir -Recurse -Force -ErrorAction SilentlyContinue }
}

Describe 'Lab 5.1 Bicep - the missing-Heartbeat log search alert (#357)' {

    It 'deploys skycraft-heartbeat-alert into the platform group, in the lab''s region, with the canonical tags' {
        $script:Alert | Should -Not -BeNullOrEmpty -Because 'main.bicep must create the log search alert of Step 5.1.8'
        $script:Params.name.value | Should -Be "[variables('varHeartbeatAlertName')]"
        $script:Template.variables.varHeartbeatAlertName | Should -Be 'skycraft-heartbeat-alert'
        $script:Alert.resourceGroup | Should -Be "[variables('varPlatformRgName')]"
        $script:Params.location.value | Should -Be "[parameters('parLocation')]"
        $script:Params.tags.value | Should -Be "[variables('varCommonTags')]"
        @($script:Alert.properties.template.resources.Values | Where-Object { $_.type -eq 'Microsoft.Insights/scheduledQueryRules' }).Count | Should -Be 1
    }

    It 'watches the VM that gets the agent and fires when it sends no Heartbeat row in 5 minutes' {
        $script:Params.scopes.value | Should -Be @("[parameters('parAgentVmResourceId')]")
        $script:Params.enabled.value | Should -BeTrue
        $script:Params.severity.value | Should -Be 1
        $script:Params.evaluationFrequency.value | Should -Be 'PT5M'
        $script:Params.windowSize.value | Should -Be 'PT5M'
        $criterion = @($script:Params.criterias.value.allOf)
        $criterion.Count | Should -Be 1
        $criterion[0].query | Should -Be 'Heartbeat'
        $criterion[0].timeAggregation | Should -Be 'Count'
        $criterion[0].operator | Should -Be 'LessThan'
        $criterion[0].threshold | Should -Be 1
    }

    It 'notifies the lab''s action group' {
        @($script:Params.actions.value.actionGroupResourceIds) | Should -Be @("[reference('modActionGroup').outputs.resourceId.value]")
    }
}
