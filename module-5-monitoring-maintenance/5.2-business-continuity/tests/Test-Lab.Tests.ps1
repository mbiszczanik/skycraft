<#
.SYNOPSIS
    Pester 5 tests: the Lab 5.2 validator's Backup vault soft delete, Key Vault role, blob policy
    and alert processing rule checks, and what they say.

.DESCRIPTION
    Regression cover for issue #355 (decision on #366). Test-Lab.ps1 requires the Backup vault's
    soft delete to be Off, a lab-friction override the Bicep sets. A Backup vault created in the
    Portal is AlwaysOn ("secure by default", in preview for Backup vaults in Sweden Central), and
    AlwaysOn cannot be turned off, so the lab creates the vault with Az PowerShell or the Bicep.
    The check stays strict while the option exists, and says what to do when it fails. These
    tests run the real Test-Lab.ps1 in a child pwsh against a generated stub of the Az commands
    it calls, and assert that:

      1. A vault with soft delete Off passes the check.
      2. An AlwaysOn vault fails it, and the line says the state cannot be turned off and that
         the vault has to be recreated with Az PowerShell or the Bicep, naming both.
      3. A vault with soft delete On fails it, and the line names the state and the command that
         turns it off.
      4. The Backup Management Service app's Key Vault Administrator role on dev-skycraft-swc-kv
         (issue #368) passes when held, fails when missing, and fails with the Graph sign-in hint
         when the app cannot be looked up.
      5. The blob policy passes without a vaulted rule and fails with one (issue #306).
      6. The alert processing rule passes as Apply action group with skycraft-ops-ag on Sev0 and
         the vault, fails as Suppress notifications, and fails when missing (issue #366).
      7. The Site Recovery target (issue #366) passes with a tagged North Europe group, a vault and
         a Protected, Normal replication item of the world VM; fails an untagged or missing group,
         an item still replicating, an unhealthy item, and a lookup that throws.

    Only these resources are modelled; every other lookup returns nothing, so the other checks
    fail and are not asserted here. No subscription is needed, and none is used:
    tests/Support/LabScriptStub.psm1 (issue #112) imports the real modules first, the stub last,
    and aborts the child with exit 99 unless every stubbed command resolves to the stub.

.EXAMPLE
    Invoke-Pester -Path .\Test-Lab.Tests.ps1

.NOTES
    Project: SkyCraft
    Lab: 5.2 - Business Continuity & Disaster Recovery
    Issue: #355, #366, #368, #306
#>

#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..' '..' '..' 'tests' 'Support' 'LabScriptStub.psm1') -Force

    $script:ScriptPath     = (Resolve-Path (Join-Path $PSScriptRoot '..' 'scripts' 'Test-Lab.ps1')).Path
    $script:StubModuleName = 'SkyCraftLab52ValidatorStub'
    # Exactly the script's '#Requires -Modules' line.
    $script:RequiredModules = @('Az.Accounts', 'Az.Resources', 'Az.RecoveryServices', 'Az.DataProtection', 'Az.Storage', 'Az.Compute')

    $script:StubCommands = @(
        'Get-AzContext'
        'Get-AzRecoveryServicesVault'
        'Set-AzRecoveryServicesAsrVaultContext'
        'Get-AzRecoveryServicesAsrFabric'
        'Get-AzRecoveryServicesAsrProtectionContainer'
        'Get-AzRecoveryServicesAsrReplicationProtectedItem'
        'Get-AzRecoveryServicesBackupProperty'
        'Get-AzRecoveryServicesVaultProperty'
        'Get-AzRecoveryServicesBackupProtectionPolicy'
        'Get-AzRecoveryServicesBackupItem'
        'Get-AzRecoveryServicesBackupJob'
        'Get-AzRecoveryServicesBackupJobDetail'
        'Get-AzResource'
        'Get-AzResourceGroup'
        'Get-AzResourceLock'
        'Get-AzVM'
        'Get-AzDataProtectionBackupVault'
        'Get-AzDataProtectionBackupPolicy'
        'Get-AzDataProtectionBackupInstance'
        'Get-AzStorageAccount'
        'Get-AzDiagnosticSetting'
        'Get-AzADServicePrincipal'
        'Invoke-AzRestMethod'
    )

    #   SKYCRAFT_STUB_BVSOFTDELETE   the Backup vault's softDeleteSettings.state: 'Off' (Az
    #                                PowerShell or Bicep), 'AlwaysOn' (the Portal), or 'On'
    #   SKYCRAFT_STUB_KVROLE         'held': the app holds Key Vault Administrator on the vault;
    #                                'missing'; 'graphfail': the app lookup throws
    #   SKYCRAFT_STUB_BLOBPOLICY     'operational' (the script's), 'vaulted' (the Portal's), 'none'
    #   SKYCRAFT_STUB_APR            'apply', 'suppress' (the Portal's default Rule type), 'none'
    #   SKYCRAFT_STUB_ASR            'protected' (tagged group, vault, Protected and Normal),
    #                                'initial' (still replicating), 'unhealthy' (Protected, health
    #                                Critical), 'untagged' (group without Owner), 'nogroup',
    #                                'lookupfail' (the replication lookup throws)
    $script:StubBody = @'
$script:Sub = '/subscriptions/00000000-0000-0000-0000-000000000000'
$script:BvId = "$script:Sub/resourceGroups/platform-skycraft-swc-rg/providers/Microsoft.DataProtection/backupVaults/platform-skycraft-swc-bv"
$script:RsvId = "$script:Sub/resourceGroups/platform-skycraft-swc-rg/providers/Microsoft.RecoveryServices/vaults/platform-skycraft-swc-rsv"
$script:KvId = "$script:Sub/resourceGroups/dev-skycraft-swc-rg/providers/Microsoft.KeyVault/vaults/dev-skycraft-swc-kv"
$script:AprId = "$script:Sub/resourceGroups/platform-skycraft-swc-rg/providers/Microsoft.AlertsManagement/actionRules/skycraft-backup-critical-apr"
$script:AgId = "$script:Sub/resourceGroups/platform-skycraft-swc-rg/providers/microsoft.insights/actionGroups/skycraft-ops-ag"
$script:BackupSp = '22222222-2222-2222-2222-222222222222'

function Get-AzContext {
    [CmdletBinding()]
    param()
    [pscustomobject]@{
        Account      = [pscustomobject]@{ Id = 'stub-account' }
        Subscription = [pscustomobject]@{ Id = '00000000-0000-0000-0000-000000000000' }
    }
}

function Get-AzDataProtectionBackupVault {
    [CmdletBinding()]
    param([string]$ResourceGroupName, [string]$VaultName, [Parameter(ValueFromRemainingArguments)]$Rest)
    [pscustomobject]@{ Name = $VaultName; Id = $script:BvId; Location = 'swedencentral' }
}

function Get-AzRecoveryServicesVault {
    [CmdletBinding()]
    param([string]$ResourceGroupName, [string]$Name, [Parameter(ValueFromRemainingArguments)]$Rest)
    if ($ResourceGroupName -eq 'platform-skycraft-neu-asr-rg') {
        if ($env:SKYCRAFT_STUB_ASR -eq 'nogroup') { return }
        return [pscustomobject]@{ Name = 'platform-skycraft-neu-asr-rsv'; ID = "$script:Sub/resourceGroups/platform-skycraft-neu-asr-rg/providers/Microsoft.RecoveryServices/vaults/platform-skycraft-neu-asr-rsv"; Location = 'northeurope' }
    }
    [pscustomobject]@{ Name = 'platform-skycraft-swc-rsv'; ID = $script:RsvId; Location = 'swedencentral' }
}

function Get-AzResourceGroup {
    [CmdletBinding()]
    param([string]$Name, [Parameter(ValueFromRemainingArguments)]$Rest)
    if ($Name -ne 'platform-skycraft-neu-asr-rg' -or $env:SKYCRAFT_STUB_ASR -in @('nogroup', '')) { return }
    $tags = @{ Project = 'SkyCraft'; Environment = 'Platform'; CostCenter = 'MSDN'; Owner = 'stub-owner' }
    if ($env:SKYCRAFT_STUB_ASR -eq 'untagged') { $tags.Remove('Owner') }
    [pscustomobject]@{ ResourceGroupName = $Name; Location = 'northeurope'; Tags = $tags }
}

function Set-AzRecoveryServicesAsrVaultContext { [CmdletBinding()] param([Parameter(ValueFromRemainingArguments)]$Rest) }

function Get-AzRecoveryServicesAsrFabric {
    [CmdletBinding()]
    param([Parameter(ValueFromRemainingArguments)]$Rest)
    if ($env:SKYCRAFT_STUB_ASR -eq 'lookupfail') { throw 'The server returned a throttling error (429).' }
    [pscustomobject]@{ Name = 'asr-a2a-swedencentral' }
}

function Get-AzRecoveryServicesAsrProtectionContainer {
    [CmdletBinding()]
    param([Parameter(ValueFromRemainingArguments)]$Rest)
    [pscustomobject]@{ Name = 'asr-a2a-swc-container' }
}

function Get-AzRecoveryServicesAsrReplicationProtectedItem {
    [CmdletBinding()]
    param([Parameter(ValueFromRemainingArguments)]$Rest)
    $state = if ($env:SKYCRAFT_STUB_ASR -eq 'initial') { 'InitialReplicationInProgress' } else { 'Protected' }
    $health = if ($env:SKYCRAFT_STUB_ASR -eq 'unhealthy') { 'Critical' } else { 'Normal' }
    [pscustomobject]@{ FriendlyName = 'dev-skycraft-swc-world-vm'; ProtectionState = $state; ReplicationHealth = $health }
}

function Get-AzVM {
    [CmdletBinding()]
    param([string]$Name, [Parameter(ValueFromRemainingArguments)]$Rest)
    [pscustomobject]@{ Name = $Name }
}

function Get-AzADServicePrincipal {
    [CmdletBinding()]
    param([string]$ApplicationId, [Parameter(ValueFromRemainingArguments)]$Rest)
    if ($env:SKYCRAFT_STUB_KVROLE -eq 'graphfail') {
        throw 'Authentication failed against resource MicrosoftGraphEndpointResourceId. User interaction is required.'
    }
    if ($ApplicationId -ne '262044b1-e2ce-469f-a196-69ab7ada62d3') { return }
    [pscustomobject]@{ Id = $script:BackupSp; AppId = $ApplicationId; DisplayName = 'Backup Management Service' }
}

function Get-StubRoleAssignment {
    [CmdletBinding()]
    param([string]$Scope, [string]$PrincipalId)
    if ($env:SKYCRAFT_STUB_KVROLE -ne 'held') { return }
    [pscustomobject]@{ Name = 'kv-admin'; Scope = $script:KvId; PrincipalId = $script:BackupSp; RoleDefinitionId = '00482a5a-887f-4fb3-b363-3b7fe8e74483'; PrincipalType = 'ServicePrincipal' }
}

function Get-AzResource {
    [CmdletBinding()]
    param([string]$ResourceId, [switch]$ExpandProperties, [string]$ApiVersion, [Parameter(ValueFromRemainingArguments)]$Rest)
    if ($ResourceId -eq $script:KvId) { return [pscustomobject]@{ ResourceId = $script:KvId } }
    if ($ResourceId -eq "$script:BvId/backupPolicies/SkyCraft-Blob-Policy") {
        $operational = [pscustomobject]@{
            name = 'Default'; objectType = 'AzureRetentionRule'; isDefault = $true
            lifecycles = @([pscustomobject]@{
                    deleteAfter     = [pscustomobject]@{ duration = 'P30D'; objectType = 'AbsoluteDeleteOption' }
                    sourceDataStore = [pscustomobject]@{ dataStoreType = 'OperationalStore'; objectType = 'DataStoreInfoBase' }
                })
        }
        switch ($env:SKYCRAFT_STUB_BLOBPOLICY) {
            'operational' {
                return [pscustomobject]@{ Properties = [pscustomobject]@{ datasourceTypes = @('Microsoft.Storage/storageAccounts/blobServices'); policyRules = @($operational) } }
            }
            'vaulted' {
                $rules = @(
                    [pscustomobject]@{ name = 'BackupDaily'; objectType = 'AzureBackupRule'; dataStore = [pscustomobject]@{ dataStoreType = 'VaultStore' } }
                    [pscustomobject]@{
                        name = 'Default'; objectType = 'AzureRetentionRule'; isDefault = $true
                        lifecycles = @([pscustomobject]@{
                                deleteAfter     = [pscustomobject]@{ duration = 'P90D' }
                                sourceDataStore = [pscustomobject]@{ dataStoreType = 'VaultStore' }
                            })
                    }
                    $operational
                )
                return [pscustomobject]@{ Properties = [pscustomobject]@{ datasourceTypes = @('Microsoft.Storage/storageAccounts/blobServices'); policyRules = $rules } }
            }
        }
        return
    }
    if ($ResourceId -eq $script:AprId) {
        $action = switch ($env:SKYCRAFT_STUB_APR) {
            'apply'    { [pscustomobject]@{ actionType = 'AddActionGroups'; actionGroupIds = @($script:AgId) } }
            'suppress' { [pscustomobject]@{ actionType = 'RemoveAllActionGroups' } }
            default    { $null }
        }
        if (-not $action) { return }
        return [pscustomobject]@{
            ResourceId = $script:AprId
            Properties = [pscustomobject]@{
                enabled    = $true
                scopes     = @($script:RsvId)
                actions    = @($action)
                conditions = @([pscustomobject]@{ field = 'Severity'; operator = 'Equals'; values = @('Sev0') })
            }
        }
    }
    if ($ResourceId -ne $script:BvId) { return }
    [pscustomobject]@{
        ResourceId = $ResourceId
        Identity   = [pscustomobject]@{ Type = 'SystemAssigned'; PrincipalId = '11111111-1111-1111-1111-111111111111' }
        Tags       = @{ Project = 'SkyCraft'; Environment = 'Platform'; CostCenter = 'MSDN' }
        Properties = [pscustomobject]@{
            storageSettings  = @([pscustomobject]@{ datastoreType = 'VaultStore'; type = 'LocallyRedundant' })
            securitySettings = [pscustomobject]@{
                softDeleteSettings = [pscustomobject]@{ state = $env:SKYCRAFT_STUB_BVSOFTDELETE; retentionDurationInDays = 14 }
            }
        }
    }
}

# Everything else in the lab is absent: these return nothing.
function Get-AzRecoveryServicesBackupProperty { [CmdletBinding()] param([Parameter(ValueFromRemainingArguments)]$Rest) }
function Get-AzRecoveryServicesVaultProperty { [CmdletBinding()] param([Parameter(ValueFromRemainingArguments)]$Rest) }
function Get-AzRecoveryServicesBackupProtectionPolicy { [CmdletBinding()] param([Parameter(ValueFromRemainingArguments)]$Rest) }
function Get-AzRecoveryServicesBackupItem { [CmdletBinding()] param([Parameter(ValueFromRemainingArguments)]$Rest) }
function Get-AzRecoveryServicesBackupJob { [CmdletBinding()] param([Parameter(ValueFromRemainingArguments)]$Rest) }
function Get-AzRecoveryServicesBackupJobDetail { [CmdletBinding()] param([Parameter(ValueFromRemainingArguments)]$Rest) }
function Get-AzResourceLock { [CmdletBinding()] param([Parameter(ValueFromRemainingArguments)]$Rest) }
function Get-AzDataProtectionBackupPolicy { [CmdletBinding()] param([Parameter(ValueFromRemainingArguments)]$Rest) }
function Get-AzDataProtectionBackupInstance { [CmdletBinding()] param([Parameter(ValueFromRemainingArguments)]$Rest) }
function Get-AzStorageAccount { [CmdletBinding()] param([Parameter(ValueFromRemainingArguments)]$Rest) }
function Get-AzDiagnosticSetting { [CmdletBinding()] param([Parameter(ValueFromRemainingArguments)]$Rest) }
'@

    function Invoke-ValidatorScript {
        param(
            [pscustomobject]$Stub,
            [ValidateSet('Off', 'AlwaysOn', 'On')]
            [string]$SoftDelete,
            [ValidateSet('held', 'missing', 'graphfail')]
            [string]$KeyVaultRole = 'held',
            [ValidateSet('operational', 'vaulted', 'none')]
            [string]$BlobPolicy = 'operational',
            [ValidateSet('apply', 'suppress', 'none')]
            [string]$AlertRule = 'apply',
            [ValidateSet('protected', 'initial', 'unhealthy', 'untagged', 'nogroup', 'lookupfail')]
            [string]$Asr = 'protected'
        )
        $run = Invoke-LabScriptWithStub -Stub $Stub -ScriptPath $script:ScriptPath -Environment @{
            SKYCRAFT_STUB_BVSOFTDELETE = $SoftDelete
            SKYCRAFT_STUB_KVROLE       = $KeyVaultRole
            SKYCRAFT_STUB_BLOBPOLICY   = $BlobPolicy
            SKYCRAFT_STUB_APR          = $AlertRule
            SKYCRAFT_STUB_ASR          = $Asr
        }
        return [pscustomobject]@{
            ExitCode = $run.ExitCode
            Refused  = $run.Refused
            Output   = $run.Output
            # The one line under test.
            Line     = ($run.Output -split '\r?\n' | Where-Object { $_ -match 'Testing: Backup Vault soft delete' }) -join "`n"
            Lines    = @($run.Output -split '\r?\n')
        }
    }

    # The line of one check, by the start of its label.
    function Get-CheckLine {
        param([pscustomobject]$Run, [string]$Label)
        ($Run.Lines | Where-Object { $_ -like "*Testing: $Label*" }) -join "`n"
    }

    $script:Stub    = Initialize-LabScriptStub -Name $script:StubModuleName -Command $script:StubCommands `
        -Body ($script:StubBody + (Get-LabArmRoleAssignmentStub)) -RequiredModule $script:RequiredModules
    $script:StubDir = $script:Stub.Directory

    # One child process per run; each run also carries one state of the other checks.
    $script:ScriptedVault = Invoke-ValidatorScript -Stub $script:Stub -SoftDelete 'Off'
    $script:PortalVault   = Invoke-ValidatorScript -Stub $script:Stub -SoftDelete 'AlwaysOn' -KeyVaultRole 'missing' -BlobPolicy 'vaulted' -AlertRule 'suppress' -Asr 'untagged'
    $script:OnVault       = Invoke-ValidatorScript -Stub $script:Stub -SoftDelete 'On' -KeyVaultRole 'graphfail' -BlobPolicy 'none' -AlertRule 'none' -Asr 'nogroup'
    $script:AsrInitial    = Invoke-ValidatorScript -Stub $script:Stub -SoftDelete 'Off' -Asr 'initial'
    $script:AsrUnhealthy  = Invoke-ValidatorScript -Stub $script:Stub -SoftDelete 'Off' -Asr 'unhealthy'
    $script:AsrLookupFail = Invoke-ValidatorScript -Stub $script:Stub -SoftDelete 'Off' -Asr 'lookupfail'
    $script:AllRuns       = @($script:ScriptedVault, $script:PortalVault, $script:OnVault, $script:AsrInitial, $script:AsrUnhealthy, $script:AsrLookupFail)
}

AfterAll {
    if ($script:StubDir) { Remove-Item -LiteralPath $script:StubDir -Recurse -Force -ErrorAction SilentlyContinue }
}

Describe 'Lab 5.2 Test-Lab.ps1 - test harness' {

    It 'shadows the real Az commands instead of touching a subscription' {
        foreach ($run in $script:AllRuns) {
            $run.Refused | Should -BeFalse -Because "the harness must never fall through to the real Az commands (exit $($run.ExitCode)): $($run.Output)"
        }
    }

    It 'stubs every Az command the script calls' {
        $ast    = [System.Management.Automation.Language.Parser]::ParseFile($script:ScriptPath, [ref]$null, [ref]$null)
        $called = $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] }, $true) |
            ForEach-Object { $_.GetCommandName() } | Where-Object { $_ -match '^\w+-Az' } | Sort-Object -Unique
        @($called | Where-Object { $_ -notin $script:StubCommands }) | Should -BeNullOrEmpty
    }
}

Describe 'Lab 5.2 Test-Lab.ps1 - Backup vault soft delete (#355, decision on #366)' {

    It 'passes a vault with soft delete Off' {
        $script:ScriptedVault.Line | Should -Match 'Testing: Backup Vault soft delete is Off \(lab-friction override, docs/bicep-standards\.md section 4\.5\)\.\.\. PASS$' -Because "output was:`n$($script:ScriptedVault.Output)"
    }

    It 'fails a Portal-built AlwaysOn vault and says it has to be recreated with soft delete Off' {
        $line = $script:PortalVault.Line
        $line | Should -Match 'FAIL$' -Because "output was:`n$($script:PortalVault.Output)"
        $line | Should -Match 'state is AlwaysOn, which cannot be turned off: a vault created in the Portal is AlwaysOn'
        $line | Should -Match 'delete the vault and recreate it with soft delete Off, with New-AzDataProtectionBackupVault -SoftDeleteState Off \(Az PowerShell\) or scripts/Deploy-Bicep\.ps1 \(the Bicep\)'
    }

    It 'fails a vault with soft delete On and names the command that turns it off' {
        $line = $script:OnVault.Line
        $line | Should -Match 'FAIL$' -Because "output was:`n$($script:OnVault.Output)"
        $line | Should -Match "state is 'On' - set it to Off: Update-AzDataProtectionBackupVault -SoftDeleteState Off"
    }
}

Describe 'Lab 5.2 Test-Lab.ps1 - Key Vault role of Backup Management Service (#368)' {

    It 'checks the backup of both dev VMs, and the Key Vault role once, for the encrypted auth VM' {
        foreach ($vm in @('dev-skycraft-swc-auth-vm', 'dev-skycraft-swc-world-vm')) {
            @($script:ScriptedVault.Lines | Where-Object { $_ -like "*Testing: VM '$vm' is registered for backup*" }).Count | Should -Be 1 -Because $vm
            @($script:ScriptedVault.Lines | Where-Object { $_ -like "*Testing: Latest backup job for '$vm' has not failed*" }).Count | Should -Be 1 -Because $vm
        }
        @($script:ScriptedVault.Lines | Where-Object { $_ -like '*Testing: Backup Management Service holds Key Vault Administrator*' }).Count | Should -Be 1
    }

    It 'passes when the app holds Key Vault Administrator on the key vault' {
        Get-CheckLine -Run $script:ScriptedVault -Label "Backup Management Service holds Key Vault Administrator on 'dev-skycraft-swc-kv'" |
            Should -Match 'PASS$' -Because "output was:`n$($script:ScriptedVault.Output)"
    }

    It 'fails when the role is missing and points to Step 5.2.3' {
        $line = Get-CheckLine -Run $script:PortalVault -Label 'Backup Management Service holds Key Vault Administrator'
        $line | Should -Match 'FAIL$' -Because "output was:`n$($script:PortalVault.Output)"
        $line | Should -Match 'grant it before Enable backup - Step 5\.2\.3'
    }

    It 'fails, not passes, when the app cannot be looked up in Microsoft Graph, and names the sign-in' {
        $line = Get-CheckLine -Run $script:OnVault -Label 'Backup Management Service holds Key Vault Administrator'
        $line | Should -Match 'FAIL \(Microsoft Graph lookup of the Backup Management Service app failed' -Because "output was:`n$($script:OnVault.Output)"
        $line | Should -Match 'Connect-AzAccount -AuthScope MicrosoftGraphEndpointResourceId'
    }
}

Describe 'Lab 5.2 Test-Lab.ps1 - blob policy without a vaulted rule (#306)' {

    It 'passes the operational-only policy the script creates' {
        Get-CheckLine -Run $script:ScriptedVault -Label 'Blob policy has no vaulted backup rule' |
            Should -Match 'PASS$' -Because "output was:`n$($script:ScriptedVault.Output)"
    }

    It 'fails a policy with a vaulted rule and names the script that creates the right one' {
        $line = Get-CheckLine -Run $script:PortalVault -Label 'Blob policy has no vaulted backup rule'
        $line | Should -Match 'FAIL$' -Because "output was:`n$($script:PortalVault.Output)"
        $line | Should -Match 'vaulted rule\(s\): BackupDaily, Default - create the policy with New-LabBlobBackup\.ps1 -PolicyOnly'
    }

    It 'fails, not passes, when there is no policy' {
        Get-CheckLine -Run $script:OnVault -Label 'Blob policy has no vaulted backup rule' | Should -Match 'FAIL$'
    }
}

Describe 'Lab 5.2 Test-Lab.ps1 - alert processing rule (#366)' {

    It 'passes every check for Apply action group with skycraft-ops-ag on the vault''s Sev0 alerts' {
        foreach ($label in @(
                "Alert processing rule 'skycraft-backup-critical-apr' exists and is enabled"
                "Alert processing rule applies to 'platform-skycraft-swc-rsv'"
                "Alert processing rule adds action group 'skycraft-ops-ag'"
                'Alert processing rule filters on Critical (Sev0) alerts'
            )) {
            Get-CheckLine -Run $script:ScriptedVault -Label $label | Should -Match 'PASS$' -Because "'$label', output was:`n$($script:ScriptedVault.Output)"
        }
    }

    It 'fails a rule that suppresses notifications, the Portal''s default Rule type' {
        $line = Get-CheckLine -Run $script:PortalVault -Label "Alert processing rule adds action group 'skycraft-ops-ag'"
        $line | Should -Match 'FAIL$' -Because "output was:`n$($script:PortalVault.Output)"
        $line | Should -Match 'the rule suppresses notifications - set Rule type to Apply action group'
    }

    It 'fails every check when the rule is missing' {
        foreach ($label in @("Alert processing rule 'skycraft-backup-critical-apr' exists", 'Alert processing rule applies to', 'Alert processing rule adds action group', 'Alert processing rule filters on')) {
            Get-CheckLine -Run $script:OnVault -Label $label | Should -Match 'FAIL$' -Because "'$label'"
        }
    }
}

Describe 'Lab 5.2 Test-Lab.ps1 - Azure Site Recovery (#366)' {

    It 'passes every check for a tagged North Europe group with a Protected, Normal replication item' {
        foreach ($label in @(
                "Target group 'platform-skycraft-neu-asr-rg' exists in North Europe"
                'Target group carries the tags Project, Environment, CostCenter, Owner'
                'Target group holds a Recovery Services vault'
                "'dev-skycraft-swc-world-vm' has a replication item in the vault"
                "Replication of 'dev-skycraft-swc-world-vm' is Protected"
                "Replication health of 'dev-skycraft-swc-world-vm' is Normal"
            )) {
            Get-CheckLine -Run $script:ScriptedVault -Label $label | Should -Match 'PASS$' -Because "'$label', output was:`n$($script:ScriptedVault.Output)"
        }
    }

    It 'fails a group without the Owner tag and names the missing tag' {
        $line = Get-CheckLine -Run $script:PortalVault -Label 'Target group carries the tags'
        $line | Should -Match 'FAIL$' -Because "output was:`n$($script:PortalVault.Output)"
        $line | Should -Match 'missing: Owner'
    }

    It 'fails every check when the target group is missing' {
        foreach ($label in @("Target group 'platform-skycraft-neu-asr-rg' exists", 'Target group carries the tags', 'Target group holds a Recovery Services vault', "'dev-skycraft-swc-world-vm' has a replication item", 'Replication of', 'Replication health of')) {
            Get-CheckLine -Run $script:OnVault -Label $label | Should -Match 'FAIL' -Because "'$label', output was:`n$($script:OnVault.Output)"
        }
    }

    It 'fails an item that is still replicating and says so' {
        $line = Get-CheckLine -Run $script:AsrInitial -Label "Replication of 'dev-skycraft-swc-world-vm' is Protected"
        $line | Should -Match 'FAIL$' -Because "output was:`n$($script:AsrInitial.Output)"
        $line | Should -Match "state is 'InitialReplicationInProgress'"
    }

    It 'fails an unhealthy item even though it is Protected' {
        Get-CheckLine -Run $script:AsrUnhealthy -Label "Replication of 'dev-skycraft-swc-world-vm' is Protected" | Should -Match 'PASS$'
        $line = Get-CheckLine -Run $script:AsrUnhealthy -Label "Replication health of 'dev-skycraft-swc-world-vm' is Normal"
        $line | Should -Match 'FAIL$' -Because "output was:`n$($script:AsrUnhealthy.Output)"
        $line | Should -Match "health is 'Critical'"
    }

    It 'fails, not skips, when the replication lookup throws' {
        $line = Get-CheckLine -Run $script:AsrLookupFail -Label "'dev-skycraft-swc-world-vm' has a replication item"
        $line | Should -Match 'FAIL$' -Because "output was:`n$($script:AsrLookupFail.Output)"
        $line | Should -Match 'lookup failed: The server returned a throttling error'
    }
}
