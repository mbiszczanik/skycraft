<#
.SYNOPSIS
    Pester 5 tests for Lab 3.2's Enable-Encryption.ps1: it encrypts the auth VM only, and every
    way it can end short of that is exit 1.

.DESCRIPTION
    Regression cover for issue #368 (maintainer decision 2026-10-16): Lab 3.2 encrypts only one
    dev VM with Azure Disk Encryption, the auth VM, so Lab 5.2 can run file-level recovery and
    Site Recovery on the world VM. The script used to encrypt both VMs, read its confirmation with
    Read-Host (an empty answer at end of input cancelled it with exit 0, the #103 pattern), waited
    30 minutes for an encryption that took about 2 hours on Standard_B2s_v2, and ended 0 when the
    encryption had not finished. These tests run the real script in a child pwsh process against a
    generated stub of the Az commands it calls and assert the contract:

      1. With -Force it resizes the auth VM to 8 GB, encrypts it with -SkipVmBackup (Az.Compute
         refuses a Linux VM with managed disks without it), waits for the OS volume, resizes it
         back and exits 0. It never touches the world VM. -KeyVaultName picks another vault.
      2. An auth VM that is already encrypted is left as it is: exit 0, no extension call.
      3. An extension refused by policy is exit 1, names the Inherit-Project-Tag assignment of
         Lab 1.3, and the VM gets its size back.
      4. An encryption that has not finished by -TimeoutMinutes is exit 1, and the VM keeps the
         8 GB size, because a resize would restart it mid-encryption.
      5. No key vault, or no console to confirm on without -Force, is exit 1 with nothing changed.

    No subscription is needed, and none is used: tests/Support/LabScriptStub.psm1 aborts the child
    with exit 99 unless every stubbed command resolves to the stub.

.EXAMPLE
    Invoke-Pester -Path .\Enable-Encryption.Tests.ps1

.NOTES
    Project: SkyCraft
    Lab: 3.2 - Virtual Machines
#>

#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..' '..' '..' 'tests' 'Support' 'LabScriptStub.psm1') -Force

    $script:ScriptPath = (Resolve-Path (Join-Path $PSScriptRoot '..' 'scripts' 'Enable-Encryption.ps1')).Path
    # Exactly the script's '#Requires -Modules' line: these are imported for real before the stub.
    $script:RequiredModules = @('Az.Accounts', 'Az.Compute', 'Az.KeyVault')
    $script:StubCommands = @(
        'Get-AzContext'
        'Get-AzKeyVault'
        'Get-AzVM'
        'Update-AzVM'
        'Set-AzVMDiskEncryptionExtension'
        'Get-AzVMDiskEncryptionStatus'
    )

    # Every call is logged to SKYCRAFT_STUB_LOG. SKYCRAFT_STUB_ADE picks how the encryption goes:
    #   completes  the OS volume reads Encrypted once the extension was set
    #   never      it stays EncryptionInProgress
    #   already    the auth VM is encrypted before the script runs
    #   refused    the extension is refused by the tag policy
    # SKYCRAFT_STUB_NOKV '1' leaves no key vault.
    $script:StubBody = @'
$script:LogPath = $env:SKYCRAFT_STUB_LOG

function Write-StubCall { param([string]$Name) Add-Content -LiteralPath $script:LogPath -Value $Name }

function Test-StubCalled { param([string]$Like) (Test-Path -LiteralPath $script:LogPath) -and @(Get-Content -LiteralPath $script:LogPath | Where-Object { $_ -like $Like }).Count -gt 0 }

function Get-AzContext {
    [CmdletBinding()]
    param()
    [pscustomobject]@{ Account = [pscustomobject]@{ Id = 'stub-account' } }
}

function Get-AzKeyVault {
    [CmdletBinding()]
    param([string]$VaultName, [string]$ResourceGroupName)
    Write-StubCall "Get-AzKeyVault:$VaultName"
    if ($env:SKYCRAFT_STUB_NOKV -eq '1') { return }
    [pscustomobject]@{ VaultName = $VaultName; VaultUri = "https://$VaultName.vault.azure.net/"; ResourceId = "/stub/vaults/$VaultName"; EnabledForDiskEncryption = $true }
}

function Get-AzVM {
    [CmdletBinding()]
    param([string]$ResourceGroupName, [string]$Name, [switch]$Status)
    if ($Name -notmatch '-(auth|world)-vm$') {
        Write-Error -ErrorId 'ResourceNotFound' -Message "The Resource 'Microsoft.Compute/virtualMachines/$Name' was not found."
        return
    }
    if ($Status) {
        return [pscustomobject]@{ Statuses = @([pscustomobject]@{ Code = 'PowerState/running'; DisplayStatus = 'VM running' }) }
    }
    $resized = (Test-Path -LiteralPath $script:LogPath) -and @(Get-Content -LiteralPath $script:LogPath | Where-Object { $_ -like "Update-AzVM:${Name}:*" })[-1]
    $size = if ($resized) { ($resized -split ':')[-1] } else { 'Standard_B2ls_v2' }
    [pscustomobject]@{ Name = $Name; HardwareProfile = [pscustomobject]@{ VmSize = $size } }
}

function Update-AzVM {
    [CmdletBinding()]
    param([string]$ResourceGroupName, $VM)
    Write-StubCall "Update-AzVM:$($VM.Name):$($VM.HardwareProfile.VmSize)"
}

function Set-AzVMDiskEncryptionExtension {
    [CmdletBinding()]
    param([string]$ResourceGroupName, [string]$VMName, [string]$DiskEncryptionKeyVaultUrl, [string]$DiskEncryptionKeyVaultId,
        [string]$VolumeType, [switch]$Force, [switch]$SkipVmBackup)
    # Az.Compute refuses a Linux VM with managed disks without -SkipVmBackup.
    if (-not $SkipVmBackup) { throw '-skipVmBackup parameter is a required parameter for encrypting Linux VMs with managed disks.' }
    Write-StubCall "Set-AzVMDiskEncryptionExtension:${VMName}:${VolumeType}:SkipVmBackup:$DiskEncryptionKeyVaultId"
    if ($env:SKYCRAFT_STUB_ADE -eq 'refused') {
        throw "(RequestDisallowedByPolicy) Resource 'AzureDiskEncryptionForLinux' was disallowed by policy. Reasons: 'All resources must be tagged with Project=SkyCraft'."
    }
}

function Get-AzVMDiskEncryptionStatus {
    [CmdletBinding()]
    param([string]$ResourceGroupName, [string]$VMName)
    $os = 'NotEncrypted'
    if ($VMName -like '*-auth-vm') {
        $set = Test-StubCalled "Set-AzVMDiskEncryptionExtension:${VMName}:All:*"
        $os = switch ($env:SKYCRAFT_STUB_ADE) {
            'already'   { 'Encrypted' }
            'completes' { if ($set) { 'Encrypted' } else { 'NotEncrypted' } }
            'never'     { if ($set) { 'EncryptionInProgress' } else { 'NotEncrypted' } }
            default     { 'NotEncrypted' }
        }
    }
    [pscustomobject]@{ OsVolumeEncrypted = $os; DataVolumesEncrypted = 'NotMounted'; ProgressMessage = "stub $os" }
}
'@

    function Invoke-EncryptionScript {
        param([string]$Ade = 'completes', [switch]$NoKeyVault, [string[]]$ArgumentList = @('-Force', '-PollSeconds', '0'))
        $log = Join-Path $script:Stub.Directory ('calls-' + [guid]::NewGuid().ToString('N') + '.log')
        $run = Invoke-LabScriptWithStub -Stub $script:Stub -ScriptPath $script:ScriptPath -ArgumentList $ArgumentList -Environment @{
            SKYCRAFT_STUB_LOG  = $log
            SKYCRAFT_STUB_ADE  = $Ade
            SKYCRAFT_STUB_NOKV = if ($NoKeyVault) { '1' } else { '0' }
        }
        $calls = if (Test-Path -LiteralPath $log) { @(Get-Content -LiteralPath $log) } else { @() }
        [pscustomobject]@{ ExitCode = $run.ExitCode; Refused = $run.Refused; Output = $run.Output; Calls = $calls }
    }

    $script:Stub = Initialize-LabScriptStub -Name 'SkyCraftLab32EncryptionStub' -Command $script:StubCommands `
        -Body $script:StubBody -RequiredModule $script:RequiredModules

    $script:Completes  = Invoke-EncryptionScript
    $script:Already    = Invoke-EncryptionScript -Ade 'already'
    $script:PolicyDeny = Invoke-EncryptionScript -Ade 'refused'
    $script:TimesOut   = Invoke-EncryptionScript -Ade 'never' -ArgumentList '-Force', '-PollSeconds', '0', '-TimeoutMinutes', '0'
    $script:NoKv       = Invoke-EncryptionScript -NoKeyVault
    $script:NoConsole  = Invoke-EncryptionScript -ArgumentList '-PollSeconds', '0'
    $script:OwnVault   = Invoke-EncryptionScript -ArgumentList '-Force', '-PollSeconds', '0', '-KeyVaultName', 'dev-skycraft-swc-kv-mb'

    $script:AllRuns = @($script:Completes, $script:Already, $script:PolicyDeny, $script:TimesOut, $script:NoKv, $script:NoConsole, $script:OwnVault)
}

AfterAll {
    if ($script:Stub.Directory) { Remove-Item -LiteralPath $script:Stub.Directory -Recurse -Force -ErrorAction SilentlyContinue }
}

Describe 'Lab 3.2 Enable-Encryption.ps1 - test harness' {
    It 'shadows the real Az commands instead of touching a subscription' {
        foreach ($run in $script:AllRuns) {
            $run.Refused | Should -BeFalse -Because "the harness must never fall through to the real Az commands (exit $($run.ExitCode)): $($run.Output)"
        }
    }
}

Describe 'Lab 3.2 Enable-Encryption.ps1 - encrypts the auth VM only (#368)' {
    It 'resizes the auth VM to 8 GB, encrypts it with -SkipVmBackup, resizes it back and exits 0' {
        $run = $script:Completes
        $run.ExitCode | Should -Be 0 -Because "output was:`n$($run.Output)"
        $run.Calls | Should -Contain 'Update-AzVM:dev-skycraft-swc-auth-vm:Standard_B2s_v2'
        $run.Calls | Should -Contain 'Set-AzVMDiskEncryptionExtension:dev-skycraft-swc-auth-vm:All:SkipVmBackup:/stub/vaults/dev-skycraft-swc-kv'
        $run.Calls[-1] | Should -Be 'Update-AzVM:dev-skycraft-swc-auth-vm:Standard_B2ls_v2'
    }

    It 'uses the vault -KeyVaultName names, for a learner whose default name was taken' {
        $run = $script:OwnVault
        $run.ExitCode | Should -Be 0 -Because "output was:`n$($run.Output)"
        $run.Calls | Should -Contain 'Get-AzKeyVault:dev-skycraft-swc-kv-mb'
        $run.Calls | Should -Contain 'Set-AzVMDiskEncryptionExtension:dev-skycraft-swc-auth-vm:All:SkipVmBackup:/stub/vaults/dev-skycraft-swc-kv-mb'
    }

    It 'never encrypts or resizes the world VM' {
        foreach ($run in $script:AllRuns) {
            @($run.Calls | Where-Object { $_ -match 'world-vm' }) | Should -BeNullOrEmpty -Because "output was:`n$($run.Output)"
        }
    }

    It 'leaves an auth VM that is already encrypted as it is' {
        $run = $script:Already
        $run.ExitCode | Should -Be 0 -Because "output was:`n$($run.Output)"
        @($run.Calls | Where-Object { $_ -like 'Set-AzVMDiskEncryptionExtension:*' -or $_ -like 'Update-AzVM:*' }) | Should -BeNullOrEmpty
    }
}

Describe 'Lab 3.2 Enable-Encryption.ps1 - every way short of an encrypted auth VM is exit 1' {
    It 'exits 1 when the policy refuses the extension, names Inherit-Project-Tag and restores the size' {
        $run = $script:PolicyDeny
        $run.ExitCode | Should -Be 1 -Because "output was:`n$($run.Output)"
        $run.Output | Should -Match 'Inherit-Project-Tag'
        $run.Calls[-1] | Should -Be 'Update-AzVM:dev-skycraft-swc-auth-vm:Standard_B2ls_v2'
    }

    It 'exits 1 when the encryption has not finished in time, and keeps the 8 GB size' {
        $run = $script:TimesOut
        $run.ExitCode | Should -Be 1 -Because "output was:`n$($run.Output)"
        $run.Calls | Should -Not -Contain 'Update-AzVM:dev-skycraft-swc-auth-vm:Standard_B2ls_v2'
        $run.Output | Should -Match 'NOT resized back'
    }

    It 'exits 1 without a key vault and changes nothing' {
        $run = $script:NoKv
        $run.ExitCode | Should -Be 1 -Because "output was:`n$($run.Output)"
        @($run.Calls | Where-Object { $_ -notlike 'Get-*' }) | Should -BeNullOrEmpty
    }

    It 'exits 1 without -Force when there is no console to confirm on, and changes nothing' {
        $run = $script:NoConsole
        $run.ExitCode | Should -Be 1 -Because "output was:`n$($run.Output)"
        @($run.Calls | Where-Object { $_ -notlike 'Get-*' }) | Should -BeNullOrEmpty
    }
}
