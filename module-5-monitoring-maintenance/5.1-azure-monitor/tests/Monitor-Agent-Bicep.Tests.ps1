<#
.SYNOPSIS
    Pester 5 tests: the Lab 5.1 Bicep installs a tagged Azure Monitor Agent and sends Perf.

.DESCRIPTION
    Regression cover for issue #369. No path installed the Azure Monitor Agent, so Heartbeat
    (Step 5.1.3) stayed empty, and the rule sent InsightsMetrics and Syslog only, so the Perf
    query of Step 5.1.4 was empty even with an agent. These tests compile bicep/main.bicep and
    assert on the ARM template the deploy sends:

      1. An Azure Monitor Agent extension (Microsoft.Azure.Monitor / AzureMonitorLinuxAgent) is
         deployed into the group of the VM Deploy-Bicep.ps1 associates the rule with, with the
         canonical tags, Project = SkyCraft among them (Lab 1.3's Enforce-Project-Tag denies an
         untagged extension, #350).
      2. The rule collects '% Processor Time' into Microsoft-Perf and sends Perf and Syslog to
         the lab's workspace.
      3. Deploy-Bicep.ps1 passes the agent's VM to the template.

    No subscription is used. Building needs the AVM modules, from mcr.microsoft.com or the local
    ~/.bicep cache.

.EXAMPLE
    Invoke-Pester -Path .\Monitor-Agent-Bicep.Tests.ps1

.NOTES
    Project: SkyCraft
    Lab: 5.1 - Azure Monitor
    Issue: #369
#>

#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    $script:LabRoot  = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    $script:RepoRoot = (Resolve-Path (Join-Path $script:LabRoot '..' '..')).Path

    Import-Module (Join-Path $script:RepoRoot 'tools' 'BicepCli.psm1') -Force
    $script:WorkDir = Join-Path ([System.IO.Path]::GetTempPath()) ('skycraft-369-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $script:WorkDir -Force | Out-Null

    # --outfile rather than --stdout, as tests/Network-Redeploy.Tests.ps1 explains.
    $out = Join-Path $script:WorkDir 'lab51.json'
    $null = & (Get-BicepCliPath) build (Join-Path $script:LabRoot 'bicep' 'main.bicep') --outfile $out 2>&1
    if ($LASTEXITCODE -ne 0) { throw 'bicep build failed for Lab 5.1 main.bicep' }
    $script:Template = Get-Content -Raw -LiteralPath $out | ConvertFrom-Json -AsHashtable

    # A template compiled with languageVersion 2.0 keys resources by symbolic name; a classic one lists them.
    function Get-TemplateModule {
        param([string]$DeploymentName)
        $resources = if ($script:Template.resources -is [System.Collections.IDictionary]) { $script:Template.resources.Values } else { $script:Template.resources }
        $resources | Where-Object { $_.name -eq $DeploymentName } | Select-Object -First 1
    }

    function Get-InnerResource {
        param([System.Collections.IDictionary]$Module, [string]$Type)
        $inner = $Module.properties.template.resources
        $list = if ($inner -is [System.Collections.IDictionary]) { $inner.Values } else { $inner }
        @($list | Where-Object { $_.type -eq $Type })
    }

    $script:Agent = Get-TemplateModule -DeploymentName 'ama-deployment'
    $script:Dcr   = Get-TemplateModule -DeploymentName 'dcr-deployment'
}

AfterAll {
    if ($script:WorkDir) { Remove-Item -LiteralPath $script:WorkDir -Recurse -Force -ErrorAction SilentlyContinue }
}

Describe 'Lab 5.1 Bicep - installs the Azure Monitor Agent (#369)' {

    It 'deploys the Azure Monitor Agent extension' {
        $script:Agent | Should -Not -BeNullOrEmpty -Because 'main.bicep must install the agent; without it Heartbeat stays empty'
        $p = $script:Agent.properties.parameters
        $p.publisher.value | Should -Be 'Microsoft.Azure.Monitor'
        $p.type.value | Should -Be 'AzureMonitorLinuxAgent'
        $p.name.value | Should -Be 'AzureMonitorLinuxAgent'
        $p.enableAutomaticUpgrade.value | Should -BeTrue
        @(Get-InnerResource -Module $script:Agent -Type 'Microsoft.Compute/virtualMachines/extensions').Count | Should -Be 1
    }

    It 'deploys it into the group, and onto the VM, that Deploy-Bicep.ps1 associates the rule with' {
        $script:Agent.resourceGroup | Should -Be "[variables('varAgentVmRgName')]"
        $script:Agent.properties.parameters.virtualMachineName.value | Should -Be "[variables('varAgentVmName')]"
        $script:Template.variables.varAgentVmRgName | Should -Match "parameters\('parAgentVmResourceId'\)"
        $script:Template.variables.varAgentVmName | Should -Match "parameters\('parAgentVmResourceId'\)"
    }

    It 'tags the extension with the canonical tags, Project = SkyCraft among them' {
        $script:Agent.properties.parameters.tags.value | Should -Be "[variables('varAgentTags')]"
        $script:Template.variables.varAgentTags | Should -Match "^\[union\(variables\('varCommonTags'\), createObject\('Environment', "
        $script:Template.variables.varCommonTags.Project | Should -Be 'SkyCraft'
        $script:Template.variables.varCommonTags.Keys | Sort-Object | Should -Be @('CostCenter', 'Environment', 'Owner', 'Project')
        # The module must pass the tags on to the extension it creates.
        @(Get-InnerResource -Module $script:Agent -Type 'Microsoft.Compute/virtualMachines/extensions')[0].tags | Should -Be "[parameters('tags')]"
    }

    It 'is passed the VM by Deploy-Bicep.ps1' {
        $deploy = Get-Content -Raw -LiteralPath (Join-Path $script:LabRoot 'scripts' 'Deploy-Bicep.ps1')
        $deploy | Should -Match '(?m)^\s*parAgentVmResourceId\s*=\s*\$devVmId\s*$'
        # The association goes to the same VM.
        $deploy | Should -Match 'New-AzDataCollectionRuleAssociation -ResourceUri \$devVmId'
    }
}

Describe 'Lab 5.1 Bicep - the rule sends the Perf stream Step 5.1.4 queries (#369)' {

    BeforeAll {
        $script:Rule = $script:Dcr.properties.parameters.dataCollectionRuleProperties.value
        $script:Destination = @($script:Rule.destinations.logAnalytics)[0].name
    }

    It 'collects % Processor Time into Microsoft-Perf' {
        $perf = @($script:Rule.dataSources.performanceCounters | Where-Object { $_.streams -contains 'Microsoft-Perf' })
        $perf.Count | Should -Be 1
        $perf[0].counterSpecifiers | Should -Contain 'Processor(*)\% Processor Time'
    }

    It 'sends Perf and Syslog to the lab''s workspace' {
        $flows = @($script:Rule.dataFlows | Where-Object { $_.destinations -contains $script:Destination })
        $streams = @($flows | ForEach-Object { $_.streams })
        $streams | Should -Contain 'Microsoft-Perf'
        $streams | Should -Contain 'Microsoft-Syslog'
        @($script:Rule.destinations.logAnalytics)[0].workspaceResourceId | Should -Match "reference\('modWorkspace'\)"
    }
}
