<#
.SYNOPSIS
    Pester 5 tests for Lab 5.2's New-LabBlobBackup.ps1: the blob backup policy it creates and the
    role assignments it gives the Backup Vault identity.

.DESCRIPTION
    New-LabBlobBackup.ps1 gives the Backup Vault's managed identity two roles on
    prodskycraftswcsa (Storage Blob Data Owner, Storage Account Backup Contributor) before it
    protects the account. It used Get-AzRoleAssignment -ErrorAction SilentlyContinue and
    New-AzRoleAssignment, which call Microsoft Graph and fail where the Az sign-in cannot get a
    Graph token; a failed read then looked like "not assigned" (issue #397). It now reads and
    creates them through the ARM role assignments API (tools/LabCommon.psm1). These tests run the
    real script in a child pwsh process against a generated stub of the Az commands it calls, and
    assert:

      1. With no assignment, both roles are created on the storage account, through the ARM API,
         for a ServicePrincipal, so ARM does not look the identity up in the directory.
      2. A role the identity holds on the account or above it - the resource group, a management
         group - counts as held and is not created again; one held only below the account (on a
         container) does not cover the account, and the role is created.
      3. A read that fails stops the run with [ERROR] and exit 1 before anything is created,
         before the wait for RBAC propagation and before the backup instance.
      4. A create that fails stops the run with [ERROR] and exit 1.
      5. With no SkyCraft-Blob-Policy, the script creates it with exactly one retention rule,
         'Default', OperationalStore, P30D, and no vaulted (AzureBackupRule) rule, whatever the
         template ships (issues #306, #366).
      6. A SkyCraft-Blob-Policy with a vaulted rule (one made in the Portal) stops the run with
         [ERROR] and exit 1 before any role is touched.
      7. -PolicyOnly ends after the policy: no role, no wait, no backup instance.

    No subscription is needed, and none is used: the script runs through
    tests/Support/LabScriptStub.psm1 (issue #112), which aborts the child with exit 99 unless
    every stubbed command resolves to the stub. Start-Sleep is stubbed too, so the 360-second
    wait is recorded instead of waited.

.EXAMPLE
    Invoke-Pester -Path .\New-LabBlobBackup.Tests.ps1

.NOTES
    Project: SkyCraft
    Lab: 5.2 - Business Continuity & Disaster Recovery
    Issue: #397, #306
#>

#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..' '..' '..' 'tests' 'Support' 'LabScriptStub.psm1') -Force

    $script:ScriptPath = (Resolve-Path (Join-Path $PSScriptRoot '..' 'scripts' 'New-LabBlobBackup.ps1')).Path
    # Exactly the script's '#Requires -Modules' line: these are imported for real before the stub.
    $script:RequiredModules = @('Az.Accounts', 'Az.Resources', 'Az.DataProtection', 'Az.Storage')
    $script:StubCommands = @(
        'Get-AzContext'
        'Get-AzDataProtectionBackupVault'
        'Get-AzStorageAccount'
        'Get-AzDataProtectionBackupPolicy'
        'Get-AzDataProtectionBackupInstance'
        'Initialize-AzDataProtectionBackupInstance'
        'New-AzDataProtectionBackupInstance'
        'Get-AzResource'
        'Get-AzDataProtectionPolicyTemplate'
        'New-AzDataProtectionRetentionLifeCycleClientObject'
        'New-AzDataProtectionBackupPolicy'
        'Invoke-AzRestMethod'
        'Start-Sleep'
    )

    # The Backup Vault, the storage account and the policy exist, and the account is already
    # protected, so the run ends at the roles. The role assignments are served by the ARM role
    # assignments API fake from tests/Support/LabScriptStub.psm1 (issue #397). Scenario variables:
    #   SKYCRAFT_STUB_ROLES            'none' (default), 'above' (Storage Blob Data Owner on the
    #                                  resource group, Storage Account Backup Contributor on a
    #                                  management group) or 'below' (Storage Blob Data Owner on a
    #                                  container only, Storage Account Backup Contributor on the
    #                                  account)
    #   SKYCRAFT_STUB_ROLELOOKUPFAIL   '1' refuses every role assignment listing (HTTP 403)
    #   SKYCRAFT_STUB_CREATEFAIL       '1' refuses every role assignment create (HTTP 403)
    #   SKYCRAFT_STUB_POLICY           'operational' (default, the script's own), 'vaulted' (the
    #                                  Portal's) or 'none'
    $script:StubBody = @'
$script:LogPath = $env:SKYCRAFT_STUB_LOG
$script:VaultPrincipal = '11111111-1111-1111-1111-111111111111'
$script:Rg = '/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/prod-skycraft-swc-rg'
$script:StorageId = "$script:Rg/providers/Microsoft.Storage/storageAccounts/prodskycraftswcsa"
$script:BvId = '/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/platform-skycraft-swc-rg/providers/Microsoft.DataProtection/backupVaults/platform-skycraft-swc-bv'

function Write-StubCall {
    param([string]$Name)
    if ($script:LogPath) { Add-Content -LiteralPath $script:LogPath -Value $Name }
}

function Get-AzContext {
    [CmdletBinding()]
    param()
    [pscustomobject]@{ Account = [pscustomobject]@{ Id = 'stub-account' }; Subscription = [pscustomobject]@{ Id = '00000000-0000-0000-0000-000000000000' } }
}

function Get-AzDataProtectionBackupVault {
    [CmdletBinding()]
    param($ResourceGroupName, $VaultName)
    [pscustomobject]@{ Name = $VaultName; Id = $script:BvId; IdentityPrincipalId = $script:VaultPrincipal }
}

function Get-AzStorageAccount {
    [CmdletBinding()]
    param($ResourceGroupName, $Name)
    [pscustomobject]@{ Id = $script:StorageId }
}

function Get-AzDataProtectionBackupPolicy {
    [CmdletBinding()]
    param($ResourceGroupName, $VaultName, $Name)
    if ($env:SKYCRAFT_STUB_POLICY -eq 'none') { return }
    [pscustomobject]@{ Id = "$script:BvId/backupPolicies/$Name" }
}

# The policy's raw ARM body.
function Get-AzResource {
    [CmdletBinding()]
    param([string]$ResourceId, [string]$ApiVersion, [switch]$ExpandProperties)
    Write-StubCall -Name "Get-AzResource:$ResourceId"
    $operational = [pscustomobject]@{
        name = 'Default'; objectType = 'AzureRetentionRule'; isDefault = $true
        lifecycles = @([pscustomobject]@{
                deleteAfter     = [pscustomobject]@{ duration = 'P30D'; objectType = 'AbsoluteDeleteOption' }
                sourceDataStore = [pscustomobject]@{ dataStoreType = 'OperationalStore'; objectType = 'DataStoreInfoBase' }
            })
    }
    $rules = if ($env:SKYCRAFT_STUB_POLICY -eq 'vaulted') {
        @(
            [pscustomobject]@{ name = 'BackupDaily'; objectType = 'AzureBackupRule'; dataStore = [pscustomobject]@{ dataStoreType = 'VaultStore' } }
            $operational
        )
    } else { @($operational) }
    [pscustomobject]@{ Properties = [pscustomobject]@{ policyRules = $rules } }
}

# What Az.DataProtection 3.x ships: a vaulted weekly rule and a 7-day VaultStore retention.
function Get-AzDataProtectionPolicyTemplate {
    [CmdletBinding()]
    param([string]$DatasourceType)
    [pscustomobject]@{
        DatasourceType = @('Microsoft.Storage/storageAccounts/blobServices')
        ObjectType     = 'BackupPolicy'
        PolicyRule     = @(
            [pscustomobject]@{ Name = 'BackupWeekly'; ObjectType = 'AzureBackupRule'; DataStoreType = 'VaultStore' }
            [pscustomobject]@{
                Name = 'Default'; ObjectType = 'AzureRetentionRule'; IsDefault = $true
                Lifecycle = @([pscustomobject]@{ DeleteAfterDuration = 'P7D'; SourceDataStoreType = 'VaultStore' })
            }
        )
    }
}

function New-AzDataProtectionRetentionLifeCycleClientObject {
    [CmdletBinding()]
    param([string]$SourceDataStore, [string]$SourceRetentionDurationType, [int]$SourceRetentionDurationCount)
    [pscustomobject]@{ DeleteAfterDuration = "P$($SourceRetentionDurationCount)D"; SourceDataStoreType = $SourceDataStore }
}

function New-AzDataProtectionBackupPolicy {
    [CmdletBinding()]
    param($ResourceGroupName, $VaultName, $Name, $Policy)
    Write-StubCall -Name "New-AzDataProtectionBackupPolicy:$Name|$($Policy | ConvertTo-Json -Depth 6 -Compress)"
    [pscustomobject]@{ Id = "$script:BvId/backupPolicies/$Name" }
}

function Get-AzDataProtectionBackupInstance {
    [CmdletBinding()]
    param($ResourceGroupName, $VaultName)
    Write-StubCall -Name 'Get-AzDataProtectionBackupInstance'
    [pscustomobject]@{ Property = [pscustomobject]@{ DataSourceInfo = [pscustomobject]@{ ResourceId = $script:StorageId } } }
}

function Initialize-AzDataProtectionBackupInstance {
    [CmdletBinding()]
    param([Parameter(ValueFromRemainingArguments)]$Rest)
    Write-StubCall -Name 'Initialize-AzDataProtectionBackupInstance'
}

function New-AzDataProtectionBackupInstance {
    [CmdletBinding()]
    param([Parameter(ValueFromRemainingArguments)]$Rest)
    Write-StubCall -Name 'New-AzDataProtectionBackupInstance'
}

function Start-Sleep {
    [CmdletBinding()]
    param([int]$Seconds, [Parameter(ValueFromRemainingArguments)]$Rest)
    Write-StubCall -Name "Start-Sleep:$Seconds"
}

# What ARM lists at the storage account for the vault identity: the assignments at it, above it
# and below it.
function Get-StubRoleAssignment {
    [CmdletBinding()]
    param([string]$Scope, [string]$PrincipalId)
    Write-StubCall -Name "Get-RoleAssignment|$Scope|$PrincipalId"
    if ($env:SKYCRAFT_STUB_ROLELOOKUPFAIL -eq '1') {
        Write-Error -ErrorId 'AuthorizationFailed' -Message "The client 'stub' does not have authorization to perform action 'Microsoft.Authorization/roleAssignments/read' over scope '$Scope'."
        return
    }
    $blobDataOwner = 'b7e6dc6d-f1e8-4753-8033-0f276bb0955b'
    $backupContributor = 'e5e2a7ff-d759-4cd2-bb51-3152d37e2eb1'
    switch ($env:SKYCRAFT_STUB_ROLES) {
        'above' {
            [pscustomobject]@{ Name = 'on-rg'; Scope = $script:Rg; PrincipalId = $script:VaultPrincipal; RoleDefinitionId = $blobDataOwner; PrincipalType = 'ServicePrincipal' }
            [pscustomobject]@{ Name = 'on-mg'; Scope = '/providers/Microsoft.Management/managementGroups/stub-mg'; PrincipalId = $script:VaultPrincipal; RoleDefinitionId = $backupContributor; PrincipalType = 'ServicePrincipal' }
        }
        'below' {
            [pscustomobject]@{ Name = 'on-container'; Scope = "$script:StorageId/blobServices/default/containers/game-assets"; PrincipalId = $script:VaultPrincipal; RoleDefinitionId = $blobDataOwner; PrincipalType = 'ServicePrincipal' }
            [pscustomobject]@{ Name = 'on-account'; Scope = $script:StorageId; PrincipalId = $script:VaultPrincipal; RoleDefinitionId = $backupContributor; PrincipalType = 'ServicePrincipal' }
        }
    }
}

function New-StubRoleAssignment {
    [CmdletBinding()]
    param([string]$Scope, [string]$Name, [string]$RoleDefinitionId, [string]$PrincipalId, [string]$PrincipalType)
    if ($env:SKYCRAFT_STUB_CREATEFAIL -eq '1') {
        throw "AuthorizationFailed: The client 'stub' does not have authorization to perform action 'Microsoft.Authorization/roleAssignments/write' over scope '$Scope'."
    }
    Write-StubCall -Name "New-RoleAssignment:$PrincipalId|$PrincipalType|$(($RoleDefinitionId -split '/')[-1])|$Scope"
}
'@

    function Invoke-BlobBackupScript {
        param([string]$Roles = 'none', [switch]$RoleLookupFail, [switch]$CreateFail, [string]$Policy = 'operational', [string[]]$ArgumentList = @())

        $logPath = Join-Path $script:Stub.Directory 'calls.log'
        Remove-Item -LiteralPath $logPath -Force -ErrorAction SilentlyContinue

        $run = Invoke-LabScriptWithStub -Stub $script:Stub -ScriptPath $script:ScriptPath -ArgumentList $ArgumentList -Environment @{
            SKYCRAFT_STUB_POLICY         = $Policy
            SKYCRAFT_STUB_ROLES          = $Roles
            SKYCRAFT_STUB_ROLELOOKUPFAIL = if ($RoleLookupFail) { '1' } else { '0' }
            SKYCRAFT_STUB_CREATEFAIL     = if ($CreateFail) { '1' } else { '0' }
            SKYCRAFT_STUB_LOG            = $logPath
        }

        $calls = if (Test-Path -LiteralPath $logPath) { @(Get-Content -LiteralPath $logPath) } else { @() }
        return [pscustomobject]@{
            ExitCode = $run.ExitCode
            Refused  = $run.Refused
            Output   = $run.Output
            Calls    = $calls
        }
    }

    $script:Stub = Initialize-LabScriptStub -Name 'SkyCraftLab52BlobBackupStub' -Command $script:StubCommands `
        -Body ($script:StubBody + (Get-LabArmRoleAssignmentStub)) -RequiredModule $script:RequiredModules

    $script:StorageId  = '/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/prod-skycraft-swc-rg/providers/Microsoft.Storage/storageAccounts/prodskycraftswcsa'
    $script:BlobOwner  = 'b7e6dc6d-f1e8-4753-8033-0f276bb0955b'
    $script:BackupRole = 'e5e2a7ff-d759-4cd2-bb51-3152d37e2eb1'
    $script:Vault      = '11111111-1111-1111-1111-111111111111'

    # One invocation per scenario - each child process costs several seconds.
    $script:Fresh      = Invoke-BlobBackupScript
    $script:HeldAbove  = Invoke-BlobBackupScript -Roles 'above'
    $script:HeldBelow  = Invoke-BlobBackupScript -Roles 'below'
    $script:ReadFails  = Invoke-BlobBackupScript -RoleLookupFail
    $script:CreateFail = Invoke-BlobBackupScript -CreateFail
    $script:NewPolicy  = Invoke-BlobBackupScript -Policy 'none' -Roles 'above'
    $script:Vaulted    = Invoke-BlobBackupScript -Policy 'vaulted'
    $script:PolicyOnly = Invoke-BlobBackupScript -Policy 'none' -ArgumentList '-PolicyOnly'
    $script:AllRuns    = @($script:Fresh, $script:HeldAbove, $script:HeldBelow, $script:ReadFails, $script:CreateFail, $script:NewPolicy, $script:Vaulted, $script:PolicyOnly)
}

AfterAll {
    if ($script:Stub) { Remove-Item -LiteralPath $script:Stub.Directory -Recurse -Force -ErrorAction SilentlyContinue }
}

Describe 'Lab 5.2 New-LabBlobBackup.ps1 - test harness' {

    It 'shadows the real Az commands instead of touching a subscription' {
        foreach ($run in $script:AllRuns) {
            $run.Refused | Should -BeFalse -Because "the harness must never fall through to the real Az commands (exit $($run.ExitCode)): $($run.Output)"
        }
    }
}

Describe 'Lab 5.2 New-LabBlobBackup.ps1 - the vault identity''s roles through the ARM API (#397)' {

    It 'creates both roles on the storage account for a ServicePrincipal, then waits and checks the backup instance' {
        $run = $script:Fresh
        $run.ExitCode | Should -Be 0 -Because "output was:`n$($run.Output)"
        @($run.Calls | Where-Object { $_ -like 'New-RoleAssignment:*' }) | Should -Be @(
            "New-RoleAssignment:$script:Vault|ServicePrincipal|$script:BlobOwner|$script:StorageId"
            "New-RoleAssignment:$script:Vault|ServicePrincipal|$script:BackupRole|$script:StorageId"
        )
        @($run.Calls | Where-Object { $_ -eq "Get-RoleAssignment|$script:StorageId|$script:Vault" }).Count | Should -Be 2
        $run.Calls | Should -Contain 'Start-Sleep:360'
        $run.Calls | Should -Contain 'Get-AzDataProtectionBackupInstance'
    }

    It 'counts a role held on the resource group or on a management group as held, and creates neither' {
        $run = $script:HeldAbove
        $run.ExitCode | Should -Be 0 -Because "output was:`n$($run.Output)"
        @($run.Calls | Where-Object { $_ -like 'New-RoleAssignment:*' }) | Should -BeNullOrEmpty
        $run.Output | Should -Match 'Already assigned: Storage Blob Data Owner'
        $run.Output | Should -Match 'Already assigned: Storage Account Backup Contributor'
    }

    It 'creates a role the identity holds only on a container, and skips the one it holds on the account' {
        $run = $script:HeldBelow
        $run.ExitCode | Should -Be 0 -Because "output was:`n$($run.Output)"
        @($run.Calls | Where-Object { $_ -like 'New-RoleAssignment:*' }) | Should -Be @(
            "New-RoleAssignment:$script:Vault|ServicePrincipal|$script:BlobOwner|$script:StorageId"
        )
        $run.Output | Should -Match 'Already assigned: Storage Account Backup Contributor'
    }

    It 'stops with [ERROR] and exit 1 when the role assignments cannot be read, before anything is created' {
        # The read used -ErrorAction SilentlyContinue: a refused read looked like "not assigned".
        $run = $script:ReadFails
        $run.ExitCode | Should -Be 1 -Because "output was:`n$($run.Output)"
        $run.Output | Should -Match "\[ERROR\] Could not read the role assignments of the Backup Vault identity on 'prodskycraftswcsa':[^\r\n]*HTTP 403 \(AuthorizationFailed\)"
        @($run.Calls | Where-Object { $_ -like 'New-RoleAssignment:*' -or $_ -like 'Start-Sleep:*' -or $_ -like '*BackupInstance' }) | Should -BeNullOrEmpty
        @($run.Calls | Where-Object { $_ -like 'Get-RoleAssignment|*' }).Count | Should -Be 1
    }

    It 'stops with [ERROR] and exit 1 when a role cannot be created' {
        $run = $script:CreateFail
        $run.ExitCode | Should -Be 1 -Because "output was:`n$($run.Output)"
        $run.Output | Should -Match "\[ERROR\] Failed to assign 'Storage Blob Data Owner':[^\r\n]*AuthorizationFailed"
        @($run.Calls | Where-Object { $_ -like 'Start-Sleep:*' -or $_ -like '*BackupInstance' }) | Should -BeNullOrEmpty
    }
}

Describe 'Lab 5.2 New-LabBlobBackup.ps1 - SkyCraft-Blob-Policy, operational only (#306)' {

    It 'creates the policy with one 30-day OperationalStore rule and no vaulted rule, whatever the template ships' {
        $run = $script:NewPolicy
        $run.ExitCode | Should -Be 0 -Because "output was:`n$($run.Output)"
        $created = @($run.Calls | Where-Object { $_ -like 'New-AzDataProtectionBackupPolicy:*' })
        $created.Count | Should -Be 1
        $name, $json = ($created[0] -replace '^New-AzDataProtectionBackupPolicy:', '') -split '\|', 2
        $name | Should -Be 'SkyCraft-Blob-Policy'
        $policy = $json | ConvertFrom-Json
        @($policy.PolicyRule).Count | Should -Be 1
        $rule = @($policy.PolicyRule)[0]
        $rule.ObjectType | Should -Be 'AzureRetentionRule'
        $rule.Name | Should -Be 'Default'
        $rule.IsDefault | Should -BeTrue
        @($rule.Lifecycle).Count | Should -Be 1
        @($rule.Lifecycle)[0].SourceDataStoreType | Should -Be 'OperationalStore'
        @($rule.Lifecycle)[0].DeleteAfterDuration | Should -Be 'P30D'
        $run.Output | Should -Match 'Policy created: SkyCraft-Blob-Policy \(OperationalStore 30 days, no vaulted rule'
        $run.Calls | Should -Contain 'Get-AzDataProtectionBackupInstance'
    }

    It 'stops with [ERROR] and exit 1 on a policy with a vaulted rule, before any role is touched' {
        $run = $script:Vaulted
        $run.ExitCode | Should -Be 1 -Because "output was:`n$($run.Output)"
        $run.Output | Should -Match "\[ERROR\] 'SkyCraft-Blob-Policy' is not the lab's policy: vaulted backup rule 'BackupDaily'"
        $run.Output | Should -Match 'UserErrorBMSUpdatePolicyNotSupported'
        @($run.Calls | Where-Object { $_ -like 'Get-RoleAssignment|*' -or $_ -like 'New-RoleAssignment:*' -or $_ -like 'New-AzDataProtectionBackupPolicy:*' -or $_ -like '*BackupInstance' }) | Should -BeNullOrEmpty
    }

    It 'keeps an existing operational policy and creates none' {
        @($script:Fresh.Calls | Where-Object { $_ -like 'New-AzDataProtectionBackupPolicy:*' }) | Should -BeNullOrEmpty
        $script:Fresh.Output | Should -Match 'Policy found: SkyCraft-Blob-Policy \(operational, 30 days, no vaulted rule\)'
    }

    It 'ends after the policy with -PolicyOnly: no role, no wait, no backup instance' {
        $run = $script:PolicyOnly
        $run.ExitCode | Should -Be 0 -Because "output was:`n$($run.Output)"
        @($run.Calls | Where-Object { $_ -like 'New-AzDataProtectionBackupPolicy:SkyCraft-Blob-Policy|*' }).Count | Should -Be 1
        @($run.Calls | Where-Object { $_ -like '*RoleAssignment*' -or $_ -like 'Start-Sleep:*' -or $_ -like '*BackupInstance' }) | Should -BeNullOrEmpty
    }
}
