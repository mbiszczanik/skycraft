<#
.SYNOPSIS
    Pester 5 tests: Lab 5.2's main.bicep creates the alert processing rule and the Key Vault role
    the guide's Portal steps create, and Deploy-Bicep.ps1 hands it the app's object ID.

.DESCRIPTION
    Issue #366 (decision 2026-10-16): the alert processing rule is on all three paths, with Rule
    type Apply action group (AddActionGroups) on skycraft-ops-ag; the Portal's default, Suppress
    notifications (RemoveAllActionGroups), silences the alerts. Issue #368 (decision 2026-10-16):
    the Backup Management Service app gets Key Vault Administrator on dev-skycraft-swc-kv before
    Enable backup, on all three paths. This suite compiles main.bicep with the standalone Bicep
    CLI (tools/BicepCli.psm1) and asserts:

      1. The rule's module scopes it to the Recovery Services vault, filters Severity Equals Sev0,
         adds skycraft-ops-ag in platform-skycraft-swc-rg and carries the canonical tags.
      2. The role's module is deployed only when an object ID is passed, grants Key Vault
         Administrator (00482a5a-...) to a ServicePrincipal on dev-skycraft-swc-kv in
         dev-skycraft-swc-rg.
      3. Deploy-Bicep.ps1 passes parBackupManagementServicePrincipalId and looks the app up by
         its built-in application ID.

    No Azure sign-in is needed.

.EXAMPLE
    Invoke-Pester -Path .\Bicep-Alerts-KeyVaultRole.Tests.ps1

.NOTES
    Project: SkyCraft
    Lab: 5.2 - Business Continuity & Disaster Recovery
    Issue: #366, #368
#>

#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    $script:LabRoot  = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    $script:RepoRoot = (Resolve-Path (Join-Path $script:LabRoot '..' '..')).Path
    Import-Module (Join-Path $script:RepoRoot 'tools' 'BicepCli.psm1') -Force
    $script:Bicep   = Get-BicepCliPath
    $script:WorkDir = Join-Path ([System.IO.Path]::GetTempPath()) ('skycraft-52-' + [guid]::NewGuid().ToString('N'))
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

    # A "[variables('x')]" expression resolved to the variable's value; anything else as it is.
    function Resolve-TemplateValue {
        param($Value)
        if ($Value -is [string] -and $Value -match "^\[variables\('(?<name>[^']+)'\)\]$") { return $script:Template.variables[$Matches.name] }
        $Value
    }

    $script:Apr  = if ($script:Template) { Get-TemplateModule -DeploymentName 'bcdr-apr-deployment' } else { $null }
    $script:Role = if ($script:Template) { Get-TemplateModule -DeploymentName 'bcdr-kv-backup-role-deployment' } else { $null }
    $script:DeployText = Get-Content -Raw -LiteralPath (Join-Path $script:LabRoot 'scripts' 'Deploy-Bicep.ps1')
}

AfterAll {
    if ($script:WorkDir) { Remove-Item -LiteralPath $script:WorkDir -Recurse -Force -ErrorAction SilentlyContinue }
}

Describe 'Lab 5.2 main.bicep - alert processing rule (#366)' {

    It 'compiles' {
        $script:BuildExit | Should -Be 0
    }

    It 'deploys the rule into platform-skycraft-swc-rg as skycraft-backup-critical-apr' {
        $script:Apr | Should -Not -BeNullOrEmpty
        Resolve-TemplateValue $script:Apr.resourceGroup | Should -Be 'platform-skycraft-swc-rg'
        Resolve-TemplateValue $script:Apr.properties.parameters.name.value | Should -Be 'skycraft-backup-critical-apr'
        $script:Apr.properties.parameters.enabled.value | Should -BeTrue
    }

    It 'scopes the rule to the Recovery Services vault' {
        @($script:Apr.properties.parameters.scopes.value) | Should -HaveCount 1
        @($script:Apr.properties.parameters.scopes.value)[0] | Should -Match "'bcdr-rsv-deployment'\).*outputs\.resourceId\.value"
    }

    It 'adds skycraft-ops-ag (Apply action group), never removes the action groups' {
        $actions = @($script:Apr.properties.parameters.actions.value)
        $actions | Should -HaveCount 1
        $actions[0].actionType | Should -Be 'AddActionGroups'
        Resolve-TemplateValue @($actions[0].actionGroupIds)[0] |
            Should -Be "[resourceId(subscription().subscriptionId, variables('varPlatformRgName'), 'Microsoft.Insights/actionGroups', 'skycraft-ops-ag')]"
    }

    It 'filters on Critical (Sev0) alerts' {
        $conditions = @($script:Apr.properties.parameters.conditions.value)
        $severity = @($conditions | Where-Object { $_.field -eq 'Severity' })
        $severity | Should -HaveCount 1
        $severity[0].operator | Should -Be 'Equals'
        @($severity[0].values) | Should -Be @('Sev0')
    }

    It 'tags the rule with the canonical tags' {
        $tags = Resolve-TemplateValue $script:Apr.properties.parameters.tags.value
        @($tags.Keys | Sort-Object) | Should -Be @('CostCenter', 'Environment', 'Owner', 'Project')
        $tags.Project | Should -Be 'SkyCraft'
    }
}

Describe 'Lab 5.2 main.bicep - Key Vault role of Backup Management Service (#368)' {

    It 'grants the role only when Deploy-Bicep.ps1 passes an object ID' {
        $script:Role | Should -Not -BeNullOrEmpty
        $script:Role.condition | Should -Be "[not(empty(parameters('parBackupManagementServicePrincipalId')))]"
        $script:Template.parameters.parBackupManagementServicePrincipalId.defaultValue | Should -Be ''
    }

    It 'grants Key Vault Administrator to a ServicePrincipal on dev-skycraft-swc-kv' {
        $p = $script:Role.properties.parameters
        Resolve-TemplateValue $script:Role.resourceGroup | Should -Be 'dev-skycraft-swc-rg'
        Resolve-TemplateValue $p.roleDefinitionId.value | Should -Be '00482a5a-887f-4fb3-b363-3b7fe8e74483'
        $p.principalType.value | Should -Be 'ServicePrincipal'
        $p.principalId.value | Should -Be "[parameters('parBackupManagementServicePrincipalId')]"
        $p.resourceId.value | Should -Be "[resourceId(subscription().subscriptionId, variables('varKeyVaultRgName'), 'Microsoft.KeyVault/vaults', parameters('parKeyVaultName'))]"
    }

    It 'takes the vault name as parKeyVaultName, dev-skycraft-swc-kv by default, and Deploy-Bicep.ps1 passes it' {
        $script:Template.parameters.parKeyVaultName.defaultValue | Should -Be 'dev-skycraft-swc-kv'
        $script:Template.parameters.parKeyVaultName.minLength | Should -Be 3
        $script:Template.parameters.parKeyVaultName.maxLength | Should -Be 24
        $script:DeployText | Should -Match 'parKeyVaultName\s*=\s*\$KeyVaultName'
    }


    It 'is fed by Deploy-Bicep.ps1, which finds the app by its built-in application ID' {
        $script:DeployText | Should -Match 'parBackupManagementServicePrincipalId\s*=\s*\$backupServicePrincipalId'
        $script:DeployText | Should -Match "\`$backupManagementServiceAppId = '262044b1-e2ce-469f-a196-69ab7ada62d3'"
        $script:DeployText | Should -Match 'Get-AzADServicePrincipal -ApplicationId \$backupManagementServiceAppId'
    }
}
