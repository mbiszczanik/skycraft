<#
.SYNOPSIS
    Pester 5 tests: Lab 5.2's main.bicep creates the tagged North Europe Site Recovery target, and
    the scripts agree on its names.

.DESCRIPTION
    Issue #366 (decisions 2026-10-16/17): Site Recovery targets North Europe, an allowed region of
    Lab 1.3, with one pre-created tagged group used as both the VM group and the vault group;
    Site Recovery's own default groups carry no tags and are denied. This suite compiles
    main.bicep with the standalone Bicep CLI (tools/BicepCli.psm1) and asserts:

      1. The group platform-skycraft-neu-asr-rg is created in northeurope with the four canonical
         tags, and a Recovery Services vault platform-skycraft-neu-asr-rsv in it, also in
         northeurope and tagged.
      2. Deploy-Bicep.ps1 runs Enable-SiteRecovery.ps1 unless -SkipSiteRecovery is passed, skips
         it for a missing VM, and counts a non-zero exit as a deployment failure.
      3. main.bicep, Enable-SiteRecovery.ps1, Test-Lab.ps1 and Remove-LabResource.ps1 name the
         same group and vault.

    No Azure sign-in is needed.

.EXAMPLE
    Invoke-Pester -Path .\Bicep-SiteRecovery.Tests.ps1

.NOTES
    Project: SkyCraft
    Lab: 5.2 - Business Continuity & Disaster Recovery
    Issue: #366
#>

#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    $script:LabRoot  = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    $script:RepoRoot = (Resolve-Path (Join-Path $script:LabRoot '..' '..')).Path
    Import-Module (Join-Path $script:RepoRoot 'tools' 'BicepCli.psm1') -Force
    $script:Bicep   = Get-BicepCliPath
    $script:WorkDir = Join-Path ([System.IO.Path]::GetTempPath()) ('skycraft-52asr-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $script:WorkDir -Force | Out-Null

    $out = Join-Path $script:WorkDir 'lab52.json'
    $null = & $script:Bicep build (Join-Path $script:LabRoot 'bicep' 'main.bicep') --outfile $out 2>&1
    $script:BuildExit = $LASTEXITCODE
    $script:Template = if ($script:BuildExit -eq 0) { Get-Content -Raw -LiteralPath $out | ConvertFrom-Json -AsHashtable } else { $null }

    function Get-TemplateModule {
        param([string]$DeploymentName)
        $resources = if ($script:Template.resources -is [System.Collections.IDictionary]) { $script:Template.resources.Values } else { $script:Template.resources }
        $resources | Where-Object { $_.name -eq $DeploymentName } | Select-Object -First 1
    }
    function Resolve-TemplateValue {
        param($Value)
        if ($Value -is [string] -and $Value -match "^\[variables\('(?<name>[^']+)'\)\]$") { return $script:Template.variables[$Matches.name] }
        $Value
    }
    function Read-Script { param([string]$Name) Get-Content -Raw -LiteralPath (Join-Path $script:LabRoot 'scripts' $Name) }

    $script:AsrRg    = if ($script:Template) { Get-TemplateModule -DeploymentName 'bcdr-asr-rg-deployment' } else { $null }
    $script:AsrVault = if ($script:Template) { Get-TemplateModule -DeploymentName 'bcdr-asr-rsv-deployment' } else { $null }
}

AfterAll {
    if ($script:WorkDir) { Remove-Item -LiteralPath $script:WorkDir -Recurse -Force -ErrorAction SilentlyContinue }
}

Describe 'Lab 5.2 main.bicep - Site Recovery target (#366)' {

    It 'compiles' {
        $script:BuildExit | Should -Be 0
    }

    It 'creates the tagged group platform-skycraft-neu-asr-rg in North Europe' {
        $script:AsrRg | Should -Not -BeNullOrEmpty
        $p = $script:AsrRg.properties.parameters
        Resolve-TemplateValue $p.name.value | Should -Be 'platform-skycraft-neu-asr-rg'
        Resolve-TemplateValue $p.location.value | Should -Be 'northeurope'
        $tags = Resolve-TemplateValue $p.tags.value
        @($tags.Keys | Sort-Object) | Should -Be @('CostCenter', 'Environment', 'Owner', 'Project')
        $tags.Project | Should -Be 'SkyCraft'
    }

    It 'creates the vault platform-skycraft-neu-asr-rsv in that group, in North Europe, tagged' {
        $script:AsrVault | Should -Not -BeNullOrEmpty
        $p = $script:AsrVault.properties.parameters
        Resolve-TemplateValue $script:AsrVault.resourceGroup | Should -Be 'platform-skycraft-neu-asr-rg'
        Resolve-TemplateValue $p.name.value | Should -Be 'platform-skycraft-neu-asr-rsv'
        Resolve-TemplateValue $p.location.value | Should -Be 'northeurope'
        (Resolve-TemplateValue $p.tags.value).Project | Should -Be 'SkyCraft'
        @($script:AsrVault.dependsOn) -join ' ' | Should -Match 'bcdr-asr-rg-deployment'
    }

    It 'uses only Lab 1.3 allowed regions' {
        $script:Template.variables.varAsrLocation | Should -BeIn @('swedencentral', 'northeurope')
    }
}

Describe 'Lab 5.2 Deploy-Bicep.ps1 - starts the replication (#366)' {

    BeforeAll { $script:Deploy = Read-Script 'Deploy-Bicep.ps1' }

    It 'has -SkipSiteRecovery and runs Enable-SiteRecovery.ps1 -Force otherwise' {
        $script:Deploy | Should -Match '\[switch\]\$SkipSiteRecovery'
        $script:Deploy | Should -Match "if \(\`$SkipSiteRecovery\)"
        $script:Deploy | Should -Match "& \(Join-Path \`$scriptPath 'Enable-SiteRecovery\.ps1'\) -Force"
    }

    It 'skips with a warning when the world VM is absent' {
        $script:Deploy | Should -Match "Get-AzVM -Name 'dev-skycraft-swc-world-vm' -ResourceGroupName \`$vmRg"
        $script:Deploy | Should -Match 'no replication started'
    }

    It 'counts a non-zero exit of Enable-SiteRecovery.ps1 as a deployment failure' {
        $script:Deploy | Should -Match '(?s)Enable-SiteRecovery\.ps1.{0,120}if \(\$LASTEXITCODE -ne 0\) \{\s+\$script:deployFailures\+\+'
    }
}

Describe 'Lab 5.2 scripts - one name for the target group and vault (#366)' {

    It 'agree in main.bicep, Enable-SiteRecovery, Test-Lab and Remove-LabResource' {
        $script:Template.variables.varAsrRgName | Should -Be 'platform-skycraft-neu-asr-rg'
        $script:Template.variables.varAsrVaultName | Should -Be 'platform-skycraft-neu-asr-rsv'
        (Read-Script 'Enable-SiteRecovery.ps1') | Should -Match "\`$targetRg\s+= 'platform-skycraft-neu-asr-rg'"
        (Read-Script 'Enable-SiteRecovery.ps1') | Should -Match "\`$vaultName\s+= 'platform-skycraft-neu-asr-rsv'"
        (Read-Script 'Test-Lab.ps1') | Should -Match "\`$asrRgName\s+= 'platform-skycraft-neu-asr-rg'"
        (Read-Script 'Remove-LabResource.ps1') | Should -Match "\`$asrRgName\s+= 'platform-skycraft-neu-asr-rg'"
        (Read-Script 'Remove-LabResource.ps1') | Should -Match "\`$asrVaultName\s+= 'platform-skycraft-neu-asr-rsv'"
    }
}
