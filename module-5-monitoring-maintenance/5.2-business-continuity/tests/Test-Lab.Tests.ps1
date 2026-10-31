<#
.SYNOPSIS
    Pester 5 tests: the Lab 5.2 validator's Backup vault soft delete check, its key vault role
    check for an ADE-encrypted VM, and its blob policy checks.

.DESCRIPTION
    Regression cover for issues #355 (decision on #366), #368 and #306. These tests run the real
    Test-Lab.ps1 in a child pwsh against a generated stub of the Az commands it calls, and
    assert that:

      1. A Backup vault with soft delete Off passes the check; an AlwaysOn vault fails it, and the
         line says the state cannot be turned off and that the vault has to be recreated with Az
         PowerShell or the Bicep, naming both; a vault with soft delete On fails it, and the line
         names the state and the command that turns it off (#355).
      2. When the VM is ADE-encrypted, the validator checks that Backup Management Service holds
         Key Vault Administrator on the VM's key vault (#368): held on the vault or on its
         resource group passes; not held fails and says so; a failed read of the encryption, of
         the app in Microsoft Graph or of the role assignments fails the check, never passes or
         skips it. -BackupManagementServiceObjectId avoids the Graph lookup. A VM that is not
         encrypted has no key vault check.
      3. The blob policy checks pass a policy that is operational (30 days) plus vaulted (daily,
         kept 7 days), and fail the vaulted check for an operational-only policy (#306).
      4. When ARM refuses the raw reads (AuthorizationFailed), the RSV tag and soft delete, Backup
         vault and blob policy checks fail and print that error, and the script exits 1 (#452).

    Only the Backup vault, and in run 4 the Recovery Services vault, is modelled besides the ADE
    VM and blob policy fakes. Every other lookup returns nothing, so the other checks fail and are not asserted here. No
    subscription is needed, and none is used: tests/Support/LabScriptStub.psm1 (issue #112)
    imports the real modules first, the stub last, and aborts the child with exit 99 unless every
    stubbed command resolves to the stub. The role assignments are served by its ARM role
    assignments fake, so nothing reaches Invoke-AzRestMethod's real endpoint.

.EXAMPLE
    Invoke-Pester -Path .\Test-Lab.Tests.ps1

.NOTES
    Project: SkyCraft
    Lab: 5.2 - Business Continuity & Disaster Recovery
    Issue: #355, #368, #306
#>

#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..' '..' '..' 'tests' 'Support' 'LabScriptStub.psm1') -Force

    $script:ScriptPath     = (Resolve-Path (Join-Path $PSScriptRoot '..' 'scripts' 'Test-Lab.ps1')).Path
    $script:StubModuleName = 'SkyCraftLab52ValidatorStub'
    # Exactly the script's '#Requires -Modules' line.
    $script:RequiredModules = @('Az.Accounts', 'Az.Resources', 'Az.RecoveryServices', 'Az.DataProtection', 'Az.Storage', 'Az.Compute')

    # The script's own Az calls, and those of the tools/LabCommon.psm1 helpers it uses
    # (Get-AzVMDiskEncryptionStatus, Get-AzADServicePrincipal, Invoke-AzRestMethod).
    $script:StubCommands = @(
        'Get-AzContext'
        'Get-AzRecoveryServicesVault'
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
        'Get-AzVMDiskEncryptionStatus'
        'Get-AzADServicePrincipal'
        'Invoke-AzRestMethod'
        'Get-AzDataProtectionBackupVault'
        'Get-AzDataProtectionBackupPolicy'
        'Get-AzDataProtectionBackupInstance'
        'Get-AzStorageAccount'
        'Get-AzDiagnosticSetting'
    )

    #   SKYCRAFT_STUB_BVSOFTDELETE   the Backup vault's softDeleteSettings.state: 'Off' (Az
    #                                PowerShell or Bicep), 'AlwaysOn' (the Portal), or 'On'
    #   SKYCRAFT_STUB_ADE            'absent' (no VM, the default), 'none' (VM not encrypted),
    #                                'encrypted', or 'fail' (the encryption status read fails)
    #   SKYCRAFT_STUB_GRAPH          'ok', or 'fail' for a Graph lookup that is refused
    #   SKYCRAFT_STUB_KVROLE         where Backup Management Service holds Key Vault
    #                                Administrator: 'vault', 'rg', 'none', or 'fail' (the read
    #                                is refused)
    #   SKYCRAFT_STUB_BLOBPOLICY     'vaulted' (operational + vaulted), 'operational' (before #306)
    #   SKYCRAFT_STUB_LOG            call log
    #   SKYCRAFT_STUB_ARM            'denied': the Recovery Services vault exists and every
    #                                Get-AzResource read throws AuthorizationFailed
    $script:StubBody = @'
$script:BvId = '/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/platform-skycraft-swc-rg/providers/Microsoft.DataProtection/backupVaults/platform-skycraft-swc-bv'
$script:KvRg = '/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/dev-skycraft-swc-rg'
$script:KvId = "$script:KvRg/providers/Microsoft.KeyVault/vaults/dev-skycraft-swc-kv"
$script:Bms  = '33333333-3333-3333-3333-333333333333'

function Write-StubCall {
    param([string]$Name)
    if ($env:SKYCRAFT_STUB_LOG) { Add-Content -LiteralPath $env:SKYCRAFT_STUB_LOG -Value $Name }
}

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

function New-StubRetention {
    param([string]$DataStore, [string]$Duration)
    [pscustomobject]@{
        name = 'Default'; objectType = 'AzureRetentionRule'; isDefault = $true
        lifecycles = @([pscustomobject]@{
                deleteAfter     = [pscustomobject]@{ duration = $Duration; objectType = 'AbsoluteDeleteOption' }
                sourceDataStore = [pscustomobject]@{ dataStoreType = $DataStore; objectType = 'DataStoreInfoBase' }
            })
    }
}

function Get-AzResource {
    [CmdletBinding()]
    param([string]$ResourceId, [switch]$ExpandProperties, [string]$ApiVersion, [Parameter(ValueFromRemainingArguments)]$Rest)
    if ($env:SKYCRAFT_STUB_ARM -eq 'denied') {
        throw "AuthorizationFailed: The client does not have authorization to perform action 'read' over scope '$ResourceId'."
    }
    if ($ResourceId -eq "$script:BvId/backupPolicies/SkyCraft-Blob-Policy") {
        $rules = @(New-StubRetention -DataStore 'OperationalStore' -Duration 'P30D')
        if ($env:SKYCRAFT_STUB_BLOBPOLICY -eq 'vaulted') {
            $rules += New-StubRetention -DataStore 'VaultStore' -Duration 'P7D'
            $rules += [pscustomobject]@{
                name = 'BackupDaily'; objectType = 'AzureBackupRule'
                dataStore = [pscustomobject]@{ dataStoreType = 'VaultStore'; objectType = 'DataStoreInfoBase' }
                trigger = [pscustomobject]@{ schedule = [pscustomobject]@{ timeZone = 'UTC'; repeatingTimeIntervals = @('R/2026-01-01T03:30:00+00:00/P1D') } }
            }
        }
        return [pscustomobject]@{
            ResourceId = $ResourceId
            Properties = [pscustomobject]@{ datasourceTypes = @('Microsoft.Storage/storageAccounts/blobServices'); policyRules = $rules }
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

function Get-AzVM {
    [CmdletBinding()]
    param([string]$Name, [string]$ResourceGroupName, [switch]$Status, [Parameter(ValueFromRemainingArguments)]$Rest)
    if ($env:SKYCRAFT_STUB_ADE -in @('', 'absent')) { return }
    if (-not $Status) { return [pscustomobject]@{ Name = $Name; ResourceGroupName = $ResourceGroupName } }
    $settings = if ($env:SKYCRAFT_STUB_ADE -eq 'encrypted') {
        @([pscustomobject]@{ Enabled = $true; DiskEncryptionKey = [pscustomobject]@{ SecretUrl = 'https://dev-skycraft-swc-kv.vault.azure.net/secrets/s/1'; SourceVault = [pscustomobject]@{ Id = $script:KvId } } })
    } else { $null }
    [pscustomobject]@{ Name = $Name; Disks = @([pscustomobject]@{ Name = "$Name-osdisk"; EncryptionSettings = $settings }) }
}

function Get-AzVMDiskEncryptionStatus {
    [CmdletBinding()]
    param([string]$ResourceGroupName, [string]$VMName)
    if ($env:SKYCRAFT_STUB_ADE -eq 'fail') { throw "stub: AuthorizationFailed reading the disk encryption of $VMName" }
    $state = if ($env:SKYCRAFT_STUB_ADE -eq 'encrypted') { 'Encrypted' } else { 'NotEncrypted' }
    [pscustomobject]@{ OsVolumeEncrypted = $state; DataVolumesEncrypted = 'NotMounted' }
}

function Get-AzADServicePrincipal {
    [CmdletBinding()]
    param([string]$ApplicationId)
    Write-StubCall -Name "Get-AzADServicePrincipal|$ApplicationId"
    if ($env:SKYCRAFT_STUB_GRAPH -eq 'fail') { throw 'Authentication failed against resource MicrosoftGraphEndpointResourceId. User interaction is required.' }
    [pscustomobject]@{ Id = $script:Bms; AppId = $ApplicationId; DisplayName = 'Backup Management Service' }
}

# The ARM role assignments fake appended to this body calls this one.
function Get-StubRoleAssignment {
    [CmdletBinding()]
    param([string]$Scope, [string]$PrincipalId)
    Write-StubCall -Name "Get-RoleAssignment|$Scope|$PrincipalId"
    $kvAdmin = '00482a5a-887f-4fb3-b363-3b7fe8e74483'
    switch ($env:SKYCRAFT_STUB_KVROLE) {
        'fail'  { Write-Error -ErrorId 'AuthorizationFailed' -Message "The client 'stub' does not have authorization to perform action 'Microsoft.Authorization/roleAssignments/read' over scope '$Scope'." }
        'vault' { [pscustomobject]@{ Name = 'kv-admin'; Scope = $script:KvId; PrincipalId = $script:Bms; RoleDefinitionId = $kvAdmin; PrincipalType = 'ServicePrincipal' } }
        'rg'    { [pscustomobject]@{ Name = 'kv-admin-rg'; Scope = $script:KvRg; PrincipalId = $script:Bms; RoleDefinitionId = $kvAdmin; PrincipalType = 'ServicePrincipal' } }
        default {
            # Another role on the vault, which does not count.
            [pscustomobject]@{ Name = 'kv-reader'; Scope = $script:KvId; PrincipalId = $script:Bms; RoleDefinitionId = '21090545-7ca7-4776-b22c-e363652d74d2'; PrincipalType = 'ServicePrincipal' }
        }
    }
}

function Get-AzRecoveryServicesVault {
    [CmdletBinding()]
    param([string]$ResourceGroupName, [string]$Name, [Parameter(ValueFromRemainingArguments)]$Rest)
    if ($env:SKYCRAFT_STUB_ARM -ne 'denied') { return }
    [pscustomobject]@{
        Name     = $Name
        ID       = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/$ResourceGroupName/providers/Microsoft.RecoveryServices/vaults/$Name"
        Location = 'swedencentral'
    }
}

# Everything else in the lab is absent: these return nothing.
function Get-AzRecoveryServicesBackupProperty { [CmdletBinding()] param([Parameter(ValueFromRemainingArguments)]$Rest) }
function Get-AzRecoveryServicesVaultProperty { [CmdletBinding()] param([Parameter(ValueFromRemainingArguments)]$Rest) }
function Get-AzRecoveryServicesBackupProtectionPolicy { [CmdletBinding()] param([Parameter(ValueFromRemainingArguments)]$Rest) }
function Get-AzRecoveryServicesBackupItem { [CmdletBinding()] param([Parameter(ValueFromRemainingArguments)]$Rest) }
function Get-AzRecoveryServicesBackupJob { [CmdletBinding()] param([Parameter(ValueFromRemainingArguments)]$Rest) }
function Get-AzRecoveryServicesBackupJobDetail { [CmdletBinding()] param([Parameter(ValueFromRemainingArguments)]$Rest) }
function Get-AzResourceGroup { [CmdletBinding()] param([Parameter(ValueFromRemainingArguments)]$Rest) }
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
            [string]$SoftDelete = 'Off',
            [string]$Ade = 'absent',
            [string]$Graph = 'ok',
            [string]$KvRole = 'vault',
            [string]$BlobPolicy = 'vaulted',
            [string[]]$ArgumentList = @(),
            [ValidateSet('', 'denied')]
            [string]$Arm = ''
        )
        $logPath = Join-Path $Stub.Directory 'calls.log'
        Remove-Item -LiteralPath $logPath -Force -ErrorAction SilentlyContinue
        $run = Invoke-LabScriptWithStub -Stub $Stub -ScriptPath $script:ScriptPath -ArgumentList $ArgumentList -Environment @{
            SKYCRAFT_STUB_BVSOFTDELETE = $SoftDelete
            SKYCRAFT_STUB_ADE          = $Ade
            SKYCRAFT_STUB_GRAPH        = $Graph
            SKYCRAFT_STUB_KVROLE       = $KvRole
            SKYCRAFT_STUB_BLOBPOLICY   = $BlobPolicy
            SKYCRAFT_STUB_LOG          = $logPath
            SKYCRAFT_STUB_ARM          = $Arm
        }
        $lines = $run.Output -split '\r?\n'
        return [pscustomobject]@{
            ExitCode   = $run.ExitCode
            Refused    = $run.Refused
            Output     = $run.Output
            Calls      = if (Test-Path -LiteralPath $logPath) { @(Get-Content -LiteralPath $logPath) } else { @() }
            # The lines under test.
            Line       = ($lines | Where-Object { $_ -match 'Testing: Backup Vault soft delete' }) -join "`n"
            KvLine     = ($lines | Where-Object { $_ -match 'Testing: (Backup Management Service holds|Disk encryption of)' }) -join "`n"
            VaultedLine = ($lines | Where-Object { $_ -match 'Testing: Blob policy takes a daily vaulted backup' }) -join "`n"
            OperationalLine = ($lines | Where-Object { $_ -match 'Testing: Blob policy operational retention' }) -join "`n"
        }
    }

    $script:Stub    = Initialize-LabScriptStub -Name $script:StubModuleName -Command $script:StubCommands `
        -Body ($script:StubBody + (Get-LabArmRoleAssignmentStub)) -RequiredModule $script:RequiredModules
    $script:StubDir = $script:Stub.Directory

    $script:Bms = '33333333-3333-3333-3333-333333333333'
    $script:KvId = '/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/dev-skycraft-swc-rg/providers/Microsoft.KeyVault/vaults/dev-skycraft-swc-kv'

    $script:ScriptedVault = Invoke-ValidatorScript -Stub $script:Stub -SoftDelete 'Off'
    $script:PortalVault   = Invoke-ValidatorScript -Stub $script:Stub -SoftDelete 'AlwaysOn'
    $script:OnVault       = Invoke-ValidatorScript -Stub $script:Stub -SoftDelete 'On'

    $script:Denied        = Invoke-ValidatorScript -Stub $script:Stub -SoftDelete 'Off' -Arm 'denied'

    $script:AdeHeld        = Invoke-ValidatorScript -Stub $script:Stub -Ade 'encrypted' -KvRole 'vault'
    $script:AdeHeldOnRg    = Invoke-ValidatorScript -Stub $script:Stub -Ade 'encrypted' -KvRole 'rg'
    $script:AdeMissing     = Invoke-ValidatorScript -Stub $script:Stub -Ade 'encrypted' -KvRole 'none'
    $script:AdeRoleFails   = Invoke-ValidatorScript -Stub $script:Stub -Ade 'encrypted' -KvRole 'fail'
    $script:AdeGraphFails  = Invoke-ValidatorScript -Stub $script:Stub -Ade 'encrypted' -Graph 'fail'
    $script:AdeStatusFails = Invoke-ValidatorScript -Stub $script:Stub -Ade 'fail'
    $script:AdeObjectId    = Invoke-ValidatorScript -Stub $script:Stub -Ade 'encrypted' -Graph 'fail' -ArgumentList "-BackupManagementServiceObjectId $script:Bms"
    $script:NotEncrypted   = Invoke-ValidatorScript -Stub $script:Stub -Ade 'none'
    $script:OperationalOnly = Invoke-ValidatorScript -Stub $script:Stub -BlobPolicy 'operational'

    $script:AllRuns = @($script:ScriptedVault, $script:PortalVault, $script:OnVault, $script:AdeHeld, $script:AdeHeldOnRg,
        $script:AdeMissing, $script:AdeRoleFails, $script:AdeGraphFails, $script:AdeStatusFails, $script:AdeObjectId,
        $script:NotEncrypted, $script:OperationalOnly, $script:Denied)
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

Describe 'Lab 5.2 Test-Lab.ps1 - key vault role for an ADE-encrypted VM (#368)' {

    It 'passes when Backup Management Service holds Key Vault Administrator on <case>' -ForEach @(
        @{ case = 'the key vault'; name = 'AdeHeld' }
        @{ case = 'the key vault''s resource group'; name = 'AdeHeldOnRg' }
    ) {
        $run = (Get-Variable -Name $name -Scope Script).Value
        $run.KvLine | Should -Match "Testing: Backup Management Service holds Key Vault Administrator on 'dev-skycraft-swc-kv' \(ADE\)\.\.\. PASS$" -Because "output was:`n$($run.Output)"
        $run.Calls | Should -Contain 'Get-AzADServicePrincipal|262044b1-e2ce-469f-a196-69ab7ada62d3'
        $run.Calls | Should -Contain "Get-RoleAssignment|$script:KvId|$script:Bms"
    }

    It 'fails, and says the role is not assigned, when only another role is held' {
        $script:AdeMissing.KvLine | Should -Match '\(not assigned - Step 5\.2\.3, step 1\) FAIL$' -Because "output was:`n$($script:AdeMissing.Output)"
    }

    It 'fails the check when <case>' -ForEach @(
        @{ case = 'the role assignments cannot be read'; name = 'AdeRoleFails'; message = 'HTTP 403 \(AuthorizationFailed\)' }
        @{ case = 'Microsoft Graph refuses the app lookup, and names the sign-in and the parameter'; name = 'AdeGraphFails'; message = 'Connect-AzAccount -AuthScope MicrosoftGraphEndpointResourceId.*-BackupManagementServiceObjectId' }
        @{ case = 'the disk encryption cannot be read'; name = 'AdeStatusFails'; message = "Testing: Disk encryption of 'dev-skycraft-swc-auth-vm' read for the key vault role check\.\.\. FAIL \(stub: AuthorizationFailed" }
    ) {
        $run = (Get-Variable -Name $name -Scope Script).Value
        $run.KvLine | Should -Match '\.\.\. FAIL' -Because "output was:`n$($run.Output)"
        $run.KvLine | Should -Match $message
        $run.KvLine | Should -Not -MatchExactly '\.\.\. PASS'
    }

    It 'uses -BackupManagementServiceObjectId without calling Microsoft Graph' {
        $run = $script:AdeObjectId
        $run.KvLine | Should -Match 'PASS$' -Because "output was:`n$($run.Output)"
        @($run.Calls | Where-Object { $_ -like 'Get-AzADServicePrincipal|*' }) | Should -BeNullOrEmpty
    }

    It 'has no key vault check for a VM that is not encrypted, and says why' {
        $run = $script:NotEncrypted
        $run.KvLine | Should -BeNullOrEmpty -Because "output was:`n$($run.Output)"
        $run.Output | Should -Match "\[INFO\] 'dev-skycraft-swc-auth-vm' is not encrypted with Azure Disk Encryption - no key vault role to check\."
        @($run.Calls | Where-Object { $_ -like 'Get-AzADServicePrincipal|*' -or $_ -like 'Get-RoleAssignment|*' }) | Should -BeNullOrEmpty
    }
}

Describe 'Lab 5.2 Test-Lab.ps1 - blob policy operational plus vaulted (#306)' {

    It 'passes the operational and the vaulted checks for an operational plus vaulted policy' {
        $script:ScriptedVault.OperationalLine | Should -Match 'PASS$' -Because "output was:`n$($script:ScriptedVault.Output)"
        $script:ScriptedVault.VaultedLine | Should -Match 'Testing: Blob policy takes a daily vaulted backup, kept 7 days in the vault\.\.\. PASS$'
    }

    It 'fails the vaulted check for an operational-only policy, and points to the guide' {
        $run = $script:OperationalOnly
        $run.OperationalLine | Should -Match 'PASS$' -Because "output was:`n$($run.Output)"
        $run.VaultedLine | Should -Match 'operational-only policy from before issue #306 - see lab-guide-5\.2\.md, Step 5\.2\.5\) FAIL$'
    }
}

Describe 'Lab 5.2 Test-Lab.ps1 - a raw ARM read that fails is not a missing resource (#452)' {

    It 'fails <label> with the lookup error' -ForEach @(
        @{ label = "RSV tag 'Project'"; pattern = "Testing: RSV tag 'Project'" }
        @{ label = 'RSV soft delete'; pattern = 'Testing: RSV soft delete' }
        @{ label = 'Backup Vault storage type'; pattern = 'Testing: Backup Vault storage type' }
        @{ label = 'Backup Vault soft delete'; pattern = 'Testing: Backup Vault soft delete' }
        @{ label = 'blob policy datasource type'; pattern = 'Testing: Blob policy datasource type' }
    ) {
        $line = ($script:Denied.Output -split '\r?\n' | Where-Object { $_ -match $pattern }) -join "`n"
        $line | Should -Match 'FAIL \(.*AuthorizationFailed' -Because "output was:`n$($script:Denied.Output)"
    }

    It 'exits 1' {
        $script:Denied.ExitCode | Should -Be 1
    }
}
