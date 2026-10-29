<#
.SYNOPSIS
    Pester 5 tests for the Azure Disk Encryption backup helpers of tools/LabCommon.psm1 (issue #368).

.DESCRIPTION
    Lab 5.2 backs up a VM that Lab 3.2 encrypts with Azure Disk Encryption. Azure Backup reads that
    VM's key vault as the Microsoft Entra app Backup Management Service, which needs the Key Vault
    Administrator role on an RBAC key vault before backup is enabled (Microsoft Learn, "Back up and
    restore encrypted Azure virtual machines"). These tests pin the two helpers the lab's scripts
    use for it:

      1. Get-LabAdeKeyVaultId returns the key vault each encrypted disk names in the VM's instance
         view, once, and nothing for a VM that is not encrypted.
      2. It throws when a lookup fails, and when the VM reports an encrypted volume but names no
         key vault: neither may read as "not encrypted".
      3. Get-LabBackupManagementServiceId returns a given object id without calling Microsoft
         Graph, looks the app up by its fixed app id otherwise, and throws, naming the Graph
         sign-in and -BackupManagementServiceObjectId, when the lookup fails or finds no single
         service principal.
      4. Get-LabBuiltInRoleId knows Key Vault Administrator by its fixed id.

    No subscription is needed, and none is used: global functions stand in for the Az commands,
    and Mock replaces them inside the module.

.EXAMPLE
    Invoke-Pester -Path .\tests\LabCommon-BackupKeyVault.Tests.ps1

.NOTES
    Project: SkyCraft
    Issue: #368
#>

#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    # Something for Mock to replace on a runner without Az (CI).
    function global:Get-AzVMDiskEncryptionStatus { param($ResourceGroupName, $VMName) $null = $ResourceGroupName, $VMName }
    function global:Get-AzVM { param($ResourceGroupName, $Name, [switch]$Status) $null = $ResourceGroupName, $Name, $Status }
    function global:Get-AzADServicePrincipal { param($ApplicationId) $null = $ApplicationId }

    Import-Module (Join-Path $PSScriptRoot '..' 'tools' 'LabCommon.psm1') -Force

    $script:Kv = '/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/dev-skycraft-swc-rg/providers/Microsoft.KeyVault/vaults/dev-skycraft-swc-kv'

    function Get-TestInstanceView {
        param([string[]]$VaultId)
        [pscustomobject]@{
            Disks = @(foreach ($id in $VaultId) {
                    [pscustomobject]@{
                        Name               = 'disk'
                        EncryptionSettings = @([pscustomobject]@{
                                Enabled           = $true
                                DiskEncryptionKey = [pscustomobject]@{ SecretUrl = 'https://dev-skycraft-swc-kv.vault.azure.net/secrets/x/1'; SourceVault = [pscustomobject]@{ Id = $id } }
                            })
                    }
                })
        }
    }
}

AfterAll {
    Remove-Item -Path 'function:global:Get-AzVMDiskEncryptionStatus', 'function:global:Get-AzVM', 'function:global:Get-AzADServicePrincipal' -ErrorAction SilentlyContinue
}

Describe 'Get-LabAdeKeyVaultId' {

    It 'returns the key vault of an ADE-encrypted VM once, however many disks name it' {
        Mock Get-AzVMDiskEncryptionStatus -ModuleName LabCommon { [pscustomobject]@{ OsVolumeEncrypted = 'Encrypted'; DataVolumesEncrypted = 'Encrypted' } }
        Mock Get-AzVM -ModuleName LabCommon { Get-TestInstanceView -VaultId $script:Kv, $script:Kv.ToUpperInvariant() }
        $result = @(Get-LabAdeKeyVaultId -ResourceGroupName 'dev-skycraft-swc-rg' -VMName 'dev-skycraft-swc-auth-vm')
        $result | Should -HaveCount 1
        $result[0] | Should -Be $script:Kv
        Should -Invoke Get-AzVM -ModuleName LabCommon -Times 1 -ParameterFilter { $Status -and $Name -eq 'dev-skycraft-swc-auth-vm' }
    }

    It 'returns nothing for a VM that is not encrypted' {
        Mock Get-AzVMDiskEncryptionStatus -ModuleName LabCommon { [pscustomobject]@{ OsVolumeEncrypted = 'NotEncrypted'; DataVolumesEncrypted = 'NotMounted' } }
        Mock Get-AzVM -ModuleName LabCommon { [pscustomobject]@{ Disks = @([pscustomobject]@{ Name = 'disk'; EncryptionSettings = $null }) } }
        @(Get-LabAdeKeyVaultId -ResourceGroupName 'dev-skycraft-swc-rg' -VMName 'dev-skycraft-swc-world-vm') | Should -HaveCount 0
    }

    It 'throws when the VM reports an encrypted volume but names no key vault' {
        Mock Get-AzVMDiskEncryptionStatus -ModuleName LabCommon { [pscustomobject]@{ OsVolumeEncrypted = 'Encrypted'; DataVolumesEncrypted = 'NotMounted' } }
        Mock Get-AzVM -ModuleName LabCommon { [pscustomobject]@{ Disks = @([pscustomobject]@{ Name = 'disk'; EncryptionSettings = $null }) } }
        { Get-LabAdeKeyVaultId -ResourceGroupName 'dev-skycraft-swc-rg' -VMName 'dev-skycraft-swc-auth-vm' } | Should -Throw -ExpectedMessage '*names no key vault*'
    }

    It 'throws when the <lookup> lookup fails' -ForEach @(
        @{ lookup = 'encryption status' }
        @{ lookup = 'instance view' }
    ) {
        if ($lookup -eq 'encryption status') {
            Mock Get-AzVMDiskEncryptionStatus -ModuleName LabCommon { throw 'stub: AuthorizationFailed' }
        } else {
            Mock Get-AzVMDiskEncryptionStatus -ModuleName LabCommon { [pscustomobject]@{ OsVolumeEncrypted = 'NotEncrypted' } }
            Mock Get-AzVM -ModuleName LabCommon { throw 'stub: AuthorizationFailed' }
        }
        { Get-LabAdeKeyVaultId -ResourceGroupName 'dev-skycraft-swc-rg' -VMName 'dev-skycraft-swc-auth-vm' } | Should -Throw -ExpectedMessage '*AuthorizationFailed*'
    }
}

Describe 'Get-LabBackupManagementServiceId' {

    It 'returns a given object id without calling Microsoft Graph' {
        Mock Get-AzADServicePrincipal -ModuleName LabCommon { throw 'stub: must not be called' }
        Get-LabBackupManagementServiceId -ObjectId '22222222-2222-2222-2222-222222222222' | Should -Be '22222222-2222-2222-2222-222222222222'
        Should -Invoke Get-AzADServicePrincipal -ModuleName LabCommon -Times 0
    }

    It 'looks the app up by its fixed app id' {
        Mock Get-AzADServicePrincipal -ModuleName LabCommon { [pscustomobject]@{ Id = '33333333-3333-3333-3333-333333333333'; AppId = $ApplicationId } }
        Get-LabBackupManagementServiceId | Should -Be '33333333-3333-3333-3333-333333333333'
        Should -Invoke Get-AzADServicePrincipal -ModuleName LabCommon -Times 1 -ParameterFilter { $ApplicationId -eq '262044b1-e2ce-469f-a196-69ab7ada62d3' }
    }

    It 'throws, naming the Graph sign-in and the parameter, when <case>' -ForEach @(
        @{ case = 'the lookup fails'; fails = $true }
        @{ case = 'no service principal is found'; fails = $false }
    ) {
        if ($fails) { Mock Get-AzADServicePrincipal -ModuleName LabCommon { throw 'Authentication failed against resource MicrosoftGraphEndpointResourceId' } }
        else { Mock Get-AzADServicePrincipal -ModuleName LabCommon { } }
        { Get-LabBackupManagementServiceId } | Should -Throw -ExpectedMessage '*Connect-AzAccount -AuthScope MicrosoftGraphEndpointResourceId*-BackupManagementServiceObjectId*'
    }
}

Describe 'Get-LabBuiltInRoleId - Key Vault Administrator' {

    It 'returns the fixed id Microsoft Learn lists for Key Vault Administrator' {
        Get-LabBuiltInRoleId -Name 'Key Vault Administrator' | Should -Be '00482a5a-887f-4fb3-b363-3b7fe8e74483'
    }
}
