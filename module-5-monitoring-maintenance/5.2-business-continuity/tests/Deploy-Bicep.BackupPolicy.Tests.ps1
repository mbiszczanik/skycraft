<#
.SYNOPSIS
    Pester 5 tests: Lab 5.2's Deploy-Bicep.ps1 grants Azure Backup access to an ADE VM's key vault
    before it enables backup, and creates an operational plus vaulted blob policy.

.DESCRIPTION
    Regression cover for issues #368 and #306.

      1. Grant-LabBackupKeyVaultRole gives Backup Management Service the Key Vault Administrator
         role on the key vault, as a ServicePrincipal, unless it holds that role on the vault or
         above it; another role does not count; a read that fails throws and creates nothing.
      2. In the script, the key vault role is granted before Enable-AzRecoveryServicesBackupProtection,
         with the object id from -BackupManagementServiceObjectId when given, and a failure to
         read the encryption, find the app or grant the role skips enabling and running the backup
         rather than letting it fail with 400198.
      3. Get-LabBlobPolicyBody builds the policy of Microsoft Learn's REST example: an
         OperationalStore retention of 30 days, a VaultStore retention of 7 days and a daily
         VaultStore backup rule with a date-and-time schedule; Test-LabBlobPolicyVaulted accepts
         it and refuses Learn's operational-only example, the policy this lab created before #306.
      4. An existing operational-only policy is reported as an [ERROR], not accepted.

    The script is never run here - its deployment cmdlet New-AzSubscriptionDeployment is an alias
    a function stub cannot shadow. The functions are taken from the script's syntax tree and run
    with Mock in place of the tools/LabCommon.psm1 helpers they call; the order of the steps is
    read from the same tree.

.EXAMPLE
    Invoke-Pester -Path .\Deploy-Bicep.BackupPolicy.Tests.ps1

.NOTES
    Project: SkyCraft
    Lab: 5.2 - Business Continuity & Disaster Recovery
    Issue: #368, #306
#>

#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..' '..' '..' 'tools' 'LabCommon.psm1') -Force

    $script:ScriptPath = (Resolve-Path (Join-Path $PSScriptRoot '..' 'scripts' 'Deploy-Bicep.ps1')).Path
    $script:Source     = Get-Content -LiteralPath $script:ScriptPath -Raw
    $script:Ast        = [System.Management.Automation.Language.Parser]::ParseFile($script:ScriptPath, [ref]$null, [ref]$null)

    foreach ($name in 'Get-LabBlobPolicyBody', 'Test-LabBlobPolicyVaulted', 'Grant-LabBackupKeyVaultRole') {
        $definition = $script:Ast.Find({ param($n)
                $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name }, $true)
        $definition | Should -Not -BeNullOrEmpty -Because "Deploy-Bicep.ps1 defines $name"
        . ([scriptblock]::Create($definition.Extent.Text))
    }

    # The offset of the first call to a command in the script body.
    function Get-CallOffset {
        param([string]$Name)
        $calls = $script:Ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] }, $true)
        foreach ($call in $calls) {
            if ($call.GetCommandName() -eq $Name) { return $call.Extent.StartOffset }
        }
        -1
    }

    $script:KvRg     = '/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/dev-skycraft-swc-rg'
    $script:Kv       = "$script:KvRg/providers/Microsoft.KeyVault/vaults/dev-skycraft-swc-kv"
    $script:Bms      = '33333333-3333-3333-3333-333333333333'
    $script:KvAdmin  = '00482a5a-887f-4fb3-b363-3b7fe8e74483'

    # Microsoft Learn's operational-only request body, the shape of the policy before #306.
    $script:OperationalOnly = @'
{"properties":{"datasourceTypes":["Microsoft.Storage/storageAccounts/blobServices"],"objectType":"BackupPolicy","policyRules":[{"name":"Default","objectType":"AzureRetentionRule","isDefault":true,"lifecycles":[{"deleteAfter":{"duration":"P30D","objectType":"AbsoluteDeleteOption"},"sourceDataStore":{"dataStoreType":"OperationalStore","objectType":"DataStoreInfoBase"}}]}]}}
'@ | ConvertFrom-Json
}

Describe 'Lab 5.2 Deploy-Bicep.ps1 - Key Vault Administrator for Backup Management Service (#368)' {

    It 'creates the role on the key vault for a ServicePrincipal when it is not held' {
        Mock Get-LabArmRoleAssignment {
            # Another role on the vault does not count.
            [pscustomobject]@{ RoleDefinitionId = '21090545-7ca7-4776-b22c-e363652d74d2'; Scope = $script:Kv }
        }
        Mock New-LabArmRoleAssignment { }
        Grant-LabBackupKeyVaultRole -KeyVaultId $script:Kv -PrincipalId $script:Bms | Should -Be 'Created'
        Should -Invoke Get-LabArmRoleAssignment -Times 1 -ParameterFilter { $Scope -eq $script:Kv -and $PrincipalId -eq $script:Bms }
        Should -Invoke New-LabArmRoleAssignment -Times 1 -ParameterFilter {
            $Scope -eq $script:Kv -and $RoleDefinitionId -eq $script:KvAdmin -and $PrincipalId -eq $script:Bms -and $PrincipalType -eq 'ServicePrincipal'
        }
    }

    It 'creates nothing when the role is held on <case>' -ForEach @(
        @{ case = 'the key vault'; heldScope = '/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/dev-skycraft-swc-rg/providers/Microsoft.KeyVault/vaults/dev-skycraft-swc-kv' }
        @{ case = 'its resource group'; heldScope = '/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/dev-skycraft-swc-rg' }
        @{ case = 'a management group'; heldScope = '/providers/Microsoft.Management/managementGroups/stub-mg' }
    ) {
        Mock Get-LabArmRoleAssignment { [pscustomobject]@{ RoleDefinitionId = $script:KvAdmin; Scope = $heldScope } }
        Mock New-LabArmRoleAssignment { throw 'stub: must not be called' }
        Grant-LabBackupKeyVaultRole -KeyVaultId $script:Kv -PrincipalId $script:Bms | Should -Be 'Held'
        Should -Invoke New-LabArmRoleAssignment -Times 0
    }

    It 'does not count the role held only on another key vault' {
        Mock Get-LabArmRoleAssignment { [pscustomobject]@{ RoleDefinitionId = $script:KvAdmin; Scope = "$script:KvRg/providers/Microsoft.KeyVault/vaults/dev-skycraft-swc-kv2" } }
        Mock New-LabArmRoleAssignment { }
        Grant-LabBackupKeyVaultRole -KeyVaultId $script:Kv -PrincipalId $script:Bms | Should -Be 'Created'
    }

    It 'throws, and creates nothing, when the role assignments cannot be read' {
        Mock Get-LabArmRoleAssignment { throw 'ARM GET returned HTTP 403 (AuthorizationFailed)' }
        Mock New-LabArmRoleAssignment { }
        { Grant-LabBackupKeyVaultRole -KeyVaultId $script:Kv -PrincipalId $script:Bms } | Should -Throw -ExpectedMessage '*AuthorizationFailed*'
        Should -Invoke New-LabArmRoleAssignment -Times 0
    }

    It 'grants the role before it enables backup on the VM' {
        $grant  = Get-CallOffset -Name 'Grant-LabBackupKeyVaultRole'
        $enable = Get-CallOffset -Name 'Enable-AzRecoveryServicesBackupProtection'
        $grant  | Should -BeGreaterThan 0
        $enable | Should -BeGreaterThan $grant
        (Get-CallOffset -Name 'Get-LabAdeKeyVaultId') | Should -BeLessThan $grant
    }

    It 'passes -BackupManagementServiceObjectId to the app lookup' {
        $script:Source | Should -Match 'Get-LabBackupManagementServiceId -ObjectId \$BackupManagementServiceObjectId'
        $parameter = $script:Ast.ParamBlock.Parameters | Where-Object { $_.Name.VariablePath.UserPath -eq 'BackupManagementServiceObjectId' }
        $parameter | Should -Not -BeNullOrEmpty
    }

    It 'skips enabling and running the backup when the key vault access could not be set' {
        # The first branch of the chain that enables protection is the blocked one, and it leaves
        # no backup item, so the initial backup below does not run either.
        $chain = $script:Ast.Find({ param($n)
                $n -is [System.Management.Automation.Language.IfStatementAst] -and $n.Clauses[0].Item1.Extent.Text -eq '$vmBackupBlocked' }, $true)
        $chain | Should -Not -BeNullOrEmpty
        $chain.Clauses[0].Item2.Extent.Text | Should -Match '\$vmItem = \$null'
        $chain.Clauses[0].Item2.Extent.Text | Should -Not -Match 'Enable-AzRecoveryServicesBackupProtection'
        $chain.ElseClause.Extent.Text | Should -Match 'Enable-AzRecoveryServicesBackupProtection'
        # Every failure path of the key vault step sets the flag and counts the failure.
        ([regex]::Matches($script:Source, '\$vmBackupBlocked = \$true\s+\$script:deployFailures\+\+')).Count | Should -Be 3
    }
}

Describe 'Lab 5.2 Deploy-Bicep.ps1 - blob policy operational plus vaulted (#306)' {

    BeforeAll {
        $script:Body = Get-LabBlobPolicyBody | ConvertFrom-Json
        $script:Rules = @($script:Body.properties.policyRules)
    }

    It 'is a blob policy' {
        $script:Body.properties.datasourceTypes | Should -Be @('Microsoft.Storage/storageAccounts/blobServices')
        $script:Body.properties.objectType | Should -Be 'BackupPolicy'
    }

    It 'keeps operational backups 30 days and vaulted backups 7 days, as two Default retention rules' {
        $retention = @($script:Rules | Where-Object { $_.objectType -eq 'AzureRetentionRule' })
        $retention | Should -HaveCount 2
        $retention.name | Should -Be @('Default', 'Default')
        $byStore = @{}
        foreach ($rule in $retention) { $byStore[$rule.lifecycles[0].sourceDataStore.dataStoreType] = $rule.lifecycles[0].deleteAfter.duration }
        $byStore['OperationalStore'] | Should -Be 'P30D'
        $byStore['VaultStore'] | Should -Be 'P7D'
    }

    It 'backs up to the vault daily at 03:30 UTC, with a date in the schedule' {
        $backup = @($script:Rules | Where-Object { $_.objectType -eq 'AzureBackupRule' })
        $backup | Should -HaveCount 1
        $backup[0].dataStore.dataStoreType | Should -Be 'VaultStore'
        $backup[0].backupParameters.backupType | Should -Be 'Discrete'
        $backup[0].trigger.schedule.timeZone | Should -Be 'UTC'
        $backup[0].trigger.schedule.repeatingTimeIntervals | Should -Be @('R/2026-01-01T03:30:00+00:00/P1D')
        $backup[0].trigger.taggingCriteria[0].tagInfo.tagName | Should -Be 'Default'
    }

    It 'accepts the policy it builds as vaulted, and refuses an operational-only one' {
        Test-LabBlobPolicyVaulted -Policy $script:Body | Should -BeTrue
        Test-LabBlobPolicyVaulted -Policy $script:OperationalOnly | Should -BeFalse
    }

    It 'reports an existing operational-only policy as an [ERROR] and does not overwrite it' {
        $script:Source | Should -Match '\$script:deployFailures\+\+\s+Write-Host "  \[ERROR\] Policy ''\$blobPolicyName'' exists but is operational only'
        # One PUT, on the path that found no policy.
        ([regex]::Matches($script:Source, 'Invoke-LabArmRequest -Method PUT')).Count | Should -Be 1
    }

    It 'no longer strips the vaulted backup rule from the policy template' {
        $script:Source | Should -Not -Match "ObjectType -ne 'AzureBackupRule'"
        $script:Source | Should -Not -Match 'Get-AzDataProtectionPolicyTemplate'
    }
}
