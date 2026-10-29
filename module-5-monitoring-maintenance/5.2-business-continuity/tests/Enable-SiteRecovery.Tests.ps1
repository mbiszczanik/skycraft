<#
.SYNOPSIS
    Pester 5 tests: Enable-SiteRecovery.ps1 replicates the world VM into the tagged North Europe
    group and says so honestly when it cannot.

.DESCRIPTION
    Issue #366 (decisions 2026-10-16/17): Site Recovery targets North Europe, with a pre-created
    tagged group used as both the VM group and the vault group; the initial replication takes
    about 45 minutes; the failover VM size is the source size; a full test failover is cleaned up.
    These tests run the real Enable-SiteRecovery.ps1 in a child pwsh against a generated stub of
    the Az commands it calls (tests/Support/LabScriptStub.psm1, issue #112) and assert that:

      1. A missing VM, an untagged target group, a missing group and a missing vault each stop the
         script with exit 1 before anything is created.
      2. A vault that already has a replication item for the VM is left alone, with exit 0.
      3. On a fresh vault, the script creates the target network and cache account in the group,
         the fabrics, containers, policy and mappings, enables replication into the target group,
         waits for Protected and sets the failover size to the source size.
      4. A failed enable job, and a wait that ends before Protected, exit 1.
      5. A failover size that cannot be set is a warning, not a failure.
      6. -TestFailover starts the test failover and then cleans it up.
      7. Without -Force a session that cannot prompt exits 1 and creates nothing.

    No Azure connection is needed, and none is used.

.EXAMPLE
    Invoke-Pester -Path .\Enable-SiteRecovery.Tests.ps1

.NOTES
    Project: SkyCraft
    Lab: 5.2 - Business Continuity & Disaster Recovery
    Issue: #366
#>

#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..' '..' '..' 'tests' 'Support' 'LabScriptStub.psm1') -Force

    $script:ScriptPath     = (Resolve-Path (Join-Path $PSScriptRoot '..' 'scripts' 'Enable-SiteRecovery.ps1')).Path
    $script:StubModuleName = 'SkyCraftLab52AsrStub'
    # Exactly the script's '#Requires -Modules' line.
    $script:RequiredModules = @('Az.Accounts', 'Az.Resources', 'Az.RecoveryServices', 'Az.Compute', 'Az.Network', 'Az.Storage')

    $script:StubCommands = @(
        'Get-AzContext'
        'Get-AzVM'
        'Get-AzResourceGroup'
        'Get-AzRecoveryServicesVault'
        'Set-AzRecoveryServicesAsrVaultContext'
        'Get-AzVirtualNetwork'
        'New-AzVirtualNetworkSubnetConfig'
        'New-AzVirtualNetwork'
        'Get-AzStorageAccount'
        'New-AzStorageAccount'
        'Get-AzRecoveryServicesAsrFabric'
        'New-AzRecoveryServicesAsrFabric'
        'Get-AzRecoveryServicesAsrProtectionContainer'
        'New-AzRecoveryServicesAsrProtectionContainer'
        'Get-AzRecoveryServicesAsrPolicy'
        'New-AzRecoveryServicesAsrPolicy'
        'Get-AzRecoveryServicesAsrProtectionContainerMapping'
        'New-AzRecoveryServicesAsrProtectionContainerMapping'
        'Get-AzRecoveryServicesAsrNetworkMapping'
        'New-AzRecoveryServicesAsrNetworkMapping'
        'New-AzRecoveryServicesAsrAzureToAzureDiskReplicationConfig'
        'New-AzRecoveryServicesAsrReplicationProtectedItem'
        'Get-AzRecoveryServicesAsrReplicationProtectedItem'
        'Set-AzRecoveryServicesAsrReplicationProtectedItem'
        'Get-AzRecoveryServicesAsrJob'
        'Start-AzRecoveryServicesAsrTestFailoverJob'
        'Start-AzRecoveryServicesAsrTestFailoverCleanupJob'
    )

    #   SKYCRAFT_STUB_VM      'missing' for no VM
    #   SKYCRAFT_STUB_GROUP   'ok', 'untagged' (no Owner) or 'missing'
    #   SKYCRAFT_STUB_VAULT   'ok' or 'missing'
    #   SKYCRAFT_STUB_ITEM    'existing' (Protected before the script runs) or 'none'
    #   SKYCRAFT_STUB_STATE   what the item reads after Enable replication: 'Protected' or 'InitialReplicationInProgress'
    #   SKYCRAFT_STUB_FAIL    comma list of commands whose job ends Failed
    #   SKYCRAFT_STUB_LOG     file the stub appends every call to
    $script:StubBody = @'
$script:LogPath = $env:SKYCRAFT_STUB_LOG
function Write-StubCall { param([string]$Name) Add-Content -LiteralPath $script:LogPath -Value $Name }
function Test-StubCalled {
    param([string]$Name)
    if (-not (Test-Path -LiteralPath $script:LogPath)) { return $false }
    return @(Get-Content -LiteralPath $script:LogPath) -contains $Name
}
function New-StubJob {
    param([string]$Name)
    Write-StubCall -Name $Name
    $failed = @($env:SKYCRAFT_STUB_FAIL -split ',') -contains $Name
    [pscustomobject]@{ State = $(if ($failed) { 'Failed' } else { 'Succeeded' }); Errors = @([pscustomobject]@{ ServiceErrorDetails = [pscustomobject]@{ Message = "stub failure: $Name" } }) }
}
# Present before the script ran when the vault is pre-built, or once the script created it.
function Test-StubBuilt { param([string]$CreateCall) return ($env:SKYCRAFT_STUB_ITEM -eq 'existing') -or (Test-StubCalled -Name $CreateCall) }

function Get-AzContext { [pscustomobject]@{ Account = [pscustomobject]@{ Id = 'stub' }; Subscription = [pscustomobject]@{ Id = '00000000-1111-2222-3333-444444444444' } } }

function Get-AzVM {
    [CmdletBinding()]
    param([string]$ResourceGroupName, [string]$Name, [Parameter(ValueFromRemainingArguments)]$Rest)
    if ($Name -like '*-test') {
        if (-not (Test-StubCalled -Name 'Start-AzRecoveryServicesAsrTestFailoverJob')) { return }
        return [pscustomobject]@{ Name = $Name; HardwareProfile = [pscustomobject]@{ VmSize = 'Standard_B2ls_v2' } }
    }
    if ($env:SKYCRAFT_STUB_VM -eq 'missing') { return }
    [pscustomobject]@{
        Id              = '/subscriptions/0/resourceGroups/dev-skycraft-swc-rg/providers/Microsoft.Compute/virtualMachines/dev-skycraft-swc-world-vm'
        Name            = $Name
        HardwareProfile = [pscustomobject]@{ VmSize = 'Standard_B2ls_v2' }
        StorageProfile  = [pscustomobject]@{
            OsDisk    = [pscustomobject]@{ ManagedDisk = [pscustomobject]@{ Id = '/disks/os'; StorageAccountType = 'StandardSSD_LRS' } }
            DataDisks = @([pscustomobject]@{ ManagedDisk = [pscustomobject]@{ Id = '/disks/data'; StorageAccountType = 'StandardSSD_LRS' } })
        }
    }
}

function Get-AzResourceGroup {
    [CmdletBinding()]
    param([string]$Name)
    if ($env:SKYCRAFT_STUB_GROUP -eq 'missing') { return }
    $tags = @{ Project = 'SkyCraft'; Environment = 'Platform'; CostCenter = 'MSDN'; Owner = 'stub-owner' }
    if ($env:SKYCRAFT_STUB_GROUP -eq 'untagged') { $tags.Remove('Owner') }
    [pscustomobject]@{ ResourceGroupName = $Name; Location = 'northeurope'; ResourceId = "/subscriptions/0/resourceGroups/$Name"; Tags = $tags }
}

function Get-AzRecoveryServicesVault {
    [CmdletBinding()]
    param([string]$ResourceGroupName, [string]$Name)
    if ($env:SKYCRAFT_STUB_VAULT -eq 'missing') { return }
    [pscustomobject]@{ Name = $Name; ID = "/subscriptions/0/resourceGroups/$ResourceGroupName/providers/Microsoft.RecoveryServices/vaults/$Name" }
}
function Set-AzRecoveryServicesAsrVaultContext { [CmdletBinding()] param($Vault) Write-StubCall -Name 'Set-AzRecoveryServicesAsrVaultContext' }

function Get-AzVirtualNetwork {
    [CmdletBinding()]
    param([string]$ResourceGroupName, [string]$Name)
    if ($Name -like '*neu*' -and -not (Test-StubBuilt -CreateCall 'New-AzVirtualNetwork')) { return }
    [pscustomobject]@{ Name = $Name; Id = "/subscriptions/0/resourceGroups/$ResourceGroupName/providers/Microsoft.Network/virtualNetworks/$Name" }
}
function New-AzVirtualNetworkSubnetConfig { [CmdletBinding()] param($Name, $AddressPrefix) Write-StubCall -Name 'New-AzVirtualNetworkSubnetConfig'; [pscustomobject]@{ Name = $Name } }
function New-AzVirtualNetwork {
    [CmdletBinding()]
    param($ResourceGroupName, $Name, $Location, $AddressPrefix, $Subnet, $Tag)
    Write-StubCall -Name 'New-AzVirtualNetwork'
    Write-StubCall -Name "New-AzVirtualNetwork:${ResourceGroupName}:${Location}:$(@($Tag.Keys | Sort-Object) -join '+')"
    [pscustomobject]@{ Name = $Name; Id = "/subscriptions/0/resourceGroups/$ResourceGroupName/providers/Microsoft.Network/virtualNetworks/$Name" }
}

function Get-AzStorageAccount {
    [CmdletBinding()]
    param([string]$ResourceGroupName, [string]$Name)
    if (-not (Test-StubBuilt -CreateCall 'New-AzStorageAccount')) { return }
    [pscustomobject]@{ StorageAccountName = $Name; Id = "/storage/$Name" }
}
function New-AzStorageAccount {
    [CmdletBinding()]
    param($ResourceGroupName, $Name, $Location, $SkuName, $Kind, $Tag)
    Write-StubCall -Name 'New-AzStorageAccount'
    Write-StubCall -Name "New-AzStorageAccount:${ResourceGroupName}:${Location}:$(@($Tag.Keys | Sort-Object) -join '+')"
    [pscustomobject]@{ StorageAccountName = $Name; Id = "/storage/$Name" }
}

function Get-AzRecoveryServicesAsrFabric {
    [CmdletBinding()] param()
    if (-not (Test-StubBuilt -CreateCall 'New-AzRecoveryServicesAsrFabric')) { return }
    [pscustomobject]@{ Name = 'asr-a2a-swedencentral' }
    [pscustomobject]@{ Name = 'asr-a2a-northeurope' }
}
function New-AzRecoveryServicesAsrFabric { [CmdletBinding()] param([switch]$Azure, $Location, $Name) New-StubJob -Name 'New-AzRecoveryServicesAsrFabric' }
function Get-AzRecoveryServicesAsrProtectionContainer {
    [CmdletBinding()] param($Fabric)
    if (-not (Test-StubBuilt -CreateCall 'New-AzRecoveryServicesAsrProtectionContainer')) { return }
    [pscustomobject]@{ Name = 'asr-a2a-swc-container' }
    [pscustomobject]@{ Name = 'asr-a2a-neu-container' }
}
function New-AzRecoveryServicesAsrProtectionContainer { [CmdletBinding()] param($InputObject, $Name) New-StubJob -Name 'New-AzRecoveryServicesAsrProtectionContainer' }
function Get-AzRecoveryServicesAsrPolicy {
    [CmdletBinding()] param()
    if (-not (Test-StubBuilt -CreateCall 'New-AzRecoveryServicesAsrPolicy')) { return }
    [pscustomobject]@{ Name = 'SkyCraft-24h-ASR-Policy' }
}
function New-AzRecoveryServicesAsrPolicy { [CmdletBinding()] param([switch]$AzureToAzure, $Name, $RecoveryPointRetentionInHours, $ApplicationConsistentSnapshotFrequencyInHours) New-StubJob -Name 'New-AzRecoveryServicesAsrPolicy' }
function Get-AzRecoveryServicesAsrProtectionContainerMapping {
    [CmdletBinding()] param($ProtectionContainer)
    if (-not (Test-StubBuilt -CreateCall 'New-AzRecoveryServicesAsrProtectionContainerMapping')) { return }
    [pscustomobject]@{ Name = 'asr-swc-to-neu' }
    [pscustomobject]@{ Name = 'asr-neu-to-swc' }
}
function New-AzRecoveryServicesAsrProtectionContainerMapping { [CmdletBinding()] param($Name, $Policy, $PrimaryProtectionContainer, $RecoveryProtectionContainer) New-StubJob -Name 'New-AzRecoveryServicesAsrProtectionContainerMapping' }
function Get-AzRecoveryServicesAsrNetworkMapping {
    [CmdletBinding()] param($PrimaryFabric)
    if (-not (Test-StubBuilt -CreateCall 'New-AzRecoveryServicesAsrNetworkMapping')) { return }
    [pscustomobject]@{ Name = 'asr-netmap-swc-to-neu' }
    [pscustomobject]@{ Name = 'asr-netmap-neu-to-swc' }
}
function New-AzRecoveryServicesAsrNetworkMapping { [CmdletBinding()] param([switch]$AzureToAzure, $Name, $PrimaryFabric, $PrimaryAzureNetworkId, $RecoveryFabric, $RecoveryAzureNetworkId) New-StubJob -Name 'New-AzRecoveryServicesAsrNetworkMapping' }

function New-AzRecoveryServicesAsrAzureToAzureDiskReplicationConfig {
    [CmdletBinding()]
    param([switch]$ManagedDisk, $LogStorageAccountId, $DiskId, $RecoveryResourceGroupId, $RecoveryReplicaDiskAccountType, $RecoveryTargetDiskAccountType)
    Write-StubCall -Name "DiskConfig:${DiskId}:${RecoveryResourceGroupId}:${RecoveryReplicaDiskAccountType}"
    [pscustomobject]@{ DiskId = $DiskId }
}
function New-AzRecoveryServicesAsrReplicationProtectedItem {
    [CmdletBinding()]
    param([switch]$AzureToAzure, $AzureVmId, $Name, $ProtectionContainerMapping, $AzureToAzureDiskReplicationConfiguration, $RecoveryResourceGroupId)
    Write-StubCall -Name "Enable:${RecoveryResourceGroupId}:$(@($AzureToAzureDiskReplicationConfiguration).Count)"
    New-StubJob -Name 'New-AzRecoveryServicesAsrReplicationProtectedItem'
}
function Get-AzRecoveryServicesAsrReplicationProtectedItem {
    [CmdletBinding()] param($ProtectionContainer)
    if ($env:SKYCRAFT_STUB_ITEM -eq 'existing') {
        return [pscustomobject]@{ FriendlyName = 'dev-skycraft-swc-world-vm'; ProtectionState = 'Protected'; ReplicationHealth = 'Normal' }
    }
    if (-not (Test-StubCalled -Name 'New-AzRecoveryServicesAsrReplicationProtectedItem')) { return }
    [pscustomobject]@{ FriendlyName = 'dev-skycraft-swc-world-vm'; ProtectionState = $env:SKYCRAFT_STUB_STATE; ReplicationHealth = 'Normal' }
}
function Set-AzRecoveryServicesAsrReplicationProtectedItem {
    [CmdletBinding()] param($InputObject, $Size)
    Write-StubCall -Name "Size:$Size"
    New-StubJob -Name 'Set-AzRecoveryServicesAsrReplicationProtectedItem'
}
function Get-AzRecoveryServicesAsrJob { [CmdletBinding()] param($Job) $Job }
function Start-AzRecoveryServicesAsrTestFailoverJob { [CmdletBinding()] param($ReplicationProtectedItem, $Direction, $AzureVMNetworkId) New-StubJob -Name 'Start-AzRecoveryServicesAsrTestFailoverJob' }
function Start-AzRecoveryServicesAsrTestFailoverCleanupJob { [CmdletBinding()] param($ReplicationProtectedItem, $Comment) New-StubJob -Name 'Start-AzRecoveryServicesAsrTestFailoverCleanupJob' }
'@

    function Invoke-EnableScript {
        param(
            [pscustomobject]$Stub,
            [string[]]$ArgumentList = @('-Force', '-WaitMinutes', '1', '-PollSeconds', '0'),
            [string]$Vm = 'ok',
            [string]$Group = 'ok',
            [string]$Vault = 'ok',
            [string]$Item = 'none',
            [string]$State = 'Protected',
            [string[]]$Fail = @()
        )
        $logPath = Join-Path $Stub.Directory 'calls.log'
        Remove-Item -LiteralPath $logPath -Force -ErrorAction SilentlyContinue
        $run = Invoke-LabScriptWithStub -Stub $Stub -ScriptPath $script:ScriptPath -ArgumentList $ArgumentList -Environment @{
            SKYCRAFT_STUB_VM    = $Vm
            SKYCRAFT_STUB_GROUP = $Group
            SKYCRAFT_STUB_VAULT = $Vault
            SKYCRAFT_STUB_ITEM  = $Item
            SKYCRAFT_STUB_STATE = $State
            SKYCRAFT_STUB_FAIL  = $Fail -join ','
            SKYCRAFT_STUB_LOG   = $logPath
        }
        [pscustomobject]@{
            ExitCode = $run.ExitCode
            Refused  = $run.Refused
            Output   = $run.Output
            Calls    = $(if (Test-Path -LiteralPath $logPath) { @(Get-Content -LiteralPath $logPath) } else { @() })
        }
    }

    $script:Stub    = Initialize-LabScriptStub -Name $script:StubModuleName -Command $script:StubCommands `
        -Body $script:StubBody -RequiredModule $script:RequiredModules
    $script:StubDir = $script:Stub.Directory

    $script:Fresh        = Invoke-EnableScript -Stub $script:Stub
    $script:Existing     = Invoke-EnableScript -Stub $script:Stub -Item 'existing'
    $script:NoVm         = Invoke-EnableScript -Stub $script:Stub -Vm 'missing'
    $script:Untagged     = Invoke-EnableScript -Stub $script:Stub -Group 'untagged'
    $script:NoGroup      = Invoke-EnableScript -Stub $script:Stub -Group 'missing'
    $script:NoVault      = Invoke-EnableScript -Stub $script:Stub -Vault 'missing'
    $script:EnableFailed = Invoke-EnableScript -Stub $script:Stub -Fail 'New-AzRecoveryServicesAsrReplicationProtectedItem'
    $script:StillReplicating = Invoke-EnableScript -Stub $script:Stub -ArgumentList @('-Force', '-WaitMinutes', '0', '-PollSeconds', '0') -State 'InitialReplicationInProgress'
    $script:SizeFailed   = Invoke-EnableScript -Stub $script:Stub -Fail 'Set-AzRecoveryServicesAsrReplicationProtectedItem'
    $script:WithFailover = Invoke-EnableScript -Stub $script:Stub -ArgumentList @('-Force', '-WaitMinutes', '1', '-PollSeconds', '0', '-TestFailover')
    $script:FailoverFailed = Invoke-EnableScript -Stub $script:Stub -ArgumentList @('-Force', '-WaitMinutes', '1', '-PollSeconds', '0', '-TestFailover') -Fail 'Start-AzRecoveryServicesAsrTestFailoverJob'
    $script:NoForce      = Invoke-EnableScript -Stub $script:Stub -ArgumentList @('-WaitMinutes', '1', '-PollSeconds', '0')
    $script:AllRuns      = @($script:Fresh, $script:Existing, $script:NoVm, $script:Untagged, $script:NoGroup, $script:NoVault, $script:EnableFailed,
        $script:StillReplicating, $script:SizeFailed, $script:WithFailover, $script:FailoverFailed, $script:NoForce)
}

AfterAll {
    if ($script:StubDir) { Remove-Item -LiteralPath $script:StubDir -Recurse -Force -ErrorAction SilentlyContinue }
}

Describe 'Lab 5.2 Enable-SiteRecovery.ps1 - test harness' {

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

Describe 'Lab 5.2 Enable-SiteRecovery.ps1 - prerequisites stop the script before anything is created (#366)' {

    It 'exits 1 without a VM' {
        $script:NoVm.ExitCode | Should -Be 1
        $script:NoVm.Output | Should -Match "VM 'dev-skycraft-swc-world-vm' not found"
    }

    It 'exits 1 for a target group without the Owner tag and names the tag' {
        $script:Untagged.ExitCode | Should -Be 1
        $script:Untagged.Output | Should -Match "lacks the tag\(s\) Owner"
    }

    It 'exits 1 without the target group, and without the vault' {
        $script:NoGroup.ExitCode | Should -Be 1
        $script:NoGroup.Output | Should -Match "Resource group 'platform-skycraft-neu-asr-rg' not found"
        $script:NoVault.ExitCode | Should -Be 1
        $script:NoVault.Output | Should -Match "Vault 'platform-skycraft-neu-asr-rsv' not found"
    }

    It 'creates nothing in any of those cases' {
        foreach ($run in @($script:NoVm, $script:Untagged, $script:NoGroup, $script:NoVault, $script:NoForce)) {
            @($run.Calls | Where-Object { $_ -like 'New-*' -or $_ -like 'Enable:*' }) | Should -BeNullOrEmpty -Because $run.Output
        }
    }
}

Describe 'Lab 5.2 Enable-SiteRecovery.ps1 - replication into the tagged North Europe group (#366)' {

    It 'exits 0 and reports Protected' {
        $script:Fresh.ExitCode | Should -Be 0 -Because $script:Fresh.Output
        $script:Fresh.Output | Should -Match 'Protected, health Normal'
    }

    It 'creates the target VNet and the cache account in the group, with the SkyCraft tags' {
        $script:Fresh.Calls | Should -Contain 'New-AzVirtualNetwork:platform-skycraft-neu-asr-rg:northeurope:CostCenter+Environment+Owner+Project'
        $script:Fresh.Calls | Should -Contain 'New-AzStorageAccount:platform-skycraft-neu-asr-rg:swedencentral:CostCenter+Environment+Owner+Project'
    }

    It 'enables replication of both disks into the target group' {
        $script:Fresh.Calls | Should -Contain 'Enable:/subscriptions/0/resourceGroups/platform-skycraft-neu-asr-rg:2'
        $script:Fresh.Calls | Should -Contain 'DiskConfig:/disks/os:/subscriptions/0/resourceGroups/platform-skycraft-neu-asr-rg:StandardSSD_LRS'
        $script:Fresh.Calls | Should -Contain 'DiskConfig:/disks/data:/subscriptions/0/resourceGroups/platform-skycraft-neu-asr-rg:StandardSSD_LRS'
    }

    It 'sets the failover VM size to the source size' {
        $script:Fresh.Calls | Should -Contain 'Size:Standard_B2ls_v2'
    }

    It 'leaves a vault that already replicates the VM alone' {
        $script:Existing.ExitCode | Should -Be 0 -Because $script:Existing.Output
        $script:Existing.Output | Should -Match 'already has a replication item'
        @($script:Existing.Calls | Where-Object { $_ -like 'New-*' -or $_ -like 'Enable:*' }) | Should -BeNullOrEmpty
    }

    It 'exits 1 when the enable job fails, and says why' {
        $script:EnableFailed.ExitCode | Should -Be 1
        $script:EnableFailed.Output | Should -Match 'Enable replication of dev-skycraft-swc-world-vm ended Failed: stub failure'
    }

    It 'exits 1, not 0, when the item is not Protected within the wait' {
        $script:StillReplicating.ExitCode | Should -Be 1
        $script:StillReplicating.Output | Should -Match 'is not Protected after 0 minutes \(state: InitialReplicationInProgress\)'
    }

    It 'warns, and exits 0, when the failover size cannot be set' {
        $script:SizeFailed.ExitCode | Should -Be 0 -Because $script:SizeFailed.Output
        $script:SizeFailed.Output | Should -Match '\[WARNING\] Could not set the failover VM size to Standard_B2ls_v2'
    }

    It 'asks before it creates anything, and exits 1 when it cannot ask' {
        $script:NoForce.ExitCode | Should -Be 1
        $script:NoForce.Output | Should -Match 'no interactive console'
    }
}

Describe 'Lab 5.2 Enable-SiteRecovery.ps1 - test failover (#366)' {

    It 'runs the test failover, then cleans it up' {
        $script:WithFailover.ExitCode | Should -Be 0 -Because $script:WithFailover.Output
        $calls = $script:WithFailover.Calls
        [array]::IndexOf($calls, 'Start-AzRecoveryServicesAsrTestFailoverJob') | Should -BeGreaterOrEqual 0
        [array]::IndexOf($calls, 'Start-AzRecoveryServicesAsrTestFailoverJob') |
            Should -BeLessThan ([array]::IndexOf($calls, 'Start-AzRecoveryServicesAsrTestFailoverCleanupJob'))
        $script:WithFailover.Output | Should -Match "test VM 'dev-skycraft-swc-world-vm-test' \(Standard_B2ls_v2\)"
    }

    It 'does not run it without -TestFailover' {
        $script:Fresh.Calls | Should -Not -Contain 'Start-AzRecoveryServicesAsrTestFailoverJob'
    }

    It 'exits 1 and starts no cleanup when the test failover fails' {
        $script:FailoverFailed.ExitCode | Should -Be 1
        $script:FailoverFailed.Output | Should -Match 'Test failover ended Failed'
        $script:FailoverFailed.Calls | Should -Not -Contain 'Start-AzRecoveryServicesAsrTestFailoverCleanupJob'
    }
}
