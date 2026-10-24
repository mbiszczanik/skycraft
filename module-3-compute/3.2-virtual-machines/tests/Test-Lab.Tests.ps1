<#
.SYNOPSIS
    Pester 5 tests for the Lab 3.2 validator: it passes on a Portal-built lab, a Bicep-built lab,
    and fails, without crashing, on a broken one.

.DESCRIPTION
    Regression cover for issues #353, #355 and #368. Test-Lab.ps1 looked the NICs up by the
    names only main.bicep gives them (<prefix>-auth-nic, <prefix>-world-nic) and the data disk by
    <prefix>-world-datadisk. The Portal names a NIC <vm-name><digits> and the guide names the disk
    <prefix>-world-vm-data, so on a Portal-built lab the script stopped with "Cannot index into a
    null array" after four checks. These tests run the real Test-Lab.ps1 in a child pwsh process
    against a generated stub of the Az commands it calls, fed by an estate file per scenario, and
    assert the contract:

      1. A lab built the Portal way (Portal NIC and disk names) passes: exit 0.
      2. A lab built the Bicep way (Bicep NIC names) passes: exit 0.
      3. Each broken state fails with its own [FAIL] line and exit 1: a NIC outside its
         application security group or the egress pool, a missing data disk, the auth VM not
         encrypted with Azure Disk Encryption, the world VM encrypted (Lab 5.2 needs it plain,
         #368), no key vault.
      4. A missing VM is a failure, not a crash: the summary is still printed and the run exits 1.

    No subscription is needed, and none is used: tests/Support/LabScriptStub.psm1 aborts the child
    with exit 99 unless every stubbed command resolves to the stub.

.EXAMPLE
    Invoke-Pester -Path .\Test-Lab.Tests.ps1

.NOTES
    Project: SkyCraft
    Lab: 3.2 - Virtual Machines
#>

#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..' '..' '..' 'tests' 'Support' 'LabScriptStub.psm1') -Force

    $script:ScriptPath = (Resolve-Path (Join-Path $PSScriptRoot '..' 'scripts' 'Test-Lab.ps1')).Path
    # Exactly the script's '#Requires -Modules' line: these are imported for real before the stub.
    $script:RequiredModules = @('Az.Accounts', 'Az.Compute', 'Az.Network', 'Az.KeyVault')
    $script:StubCommands = @(
        'Get-AzContext'
        'Get-AzVM'
        'Get-AzNetworkInterface'
        'Get-AzLoadBalancer'
        'Get-AzKeyVault'
        'Get-AzVMDiskEncryptionStatus'
        'Get-AzVmss'
    )

    # The stub answers from the estate file named by SKYCRAFT_STUB_ESTATE (JSON). A VM or scale
    # set that is not in it is reported as ResourceNotFound, as the real getters do.
    $script:StubBody = @'
$script:Estate = Get-Content -Raw -LiteralPath $env:SKYCRAFT_STUB_ESTATE | ConvertFrom-Json

function Write-StubNotFound {
    param([string]$Type, [string]$Name, [string]$ResourceGroup)
    Write-Error -ErrorId 'ResourceNotFound' -Message "The Resource '$Type/$Name' under resource group '$ResourceGroup' was not found."
}

function Get-AzContext {
    [CmdletBinding()]
    param()
    [pscustomobject]@{ Subscription = [pscustomobject]@{ Id = '00000000-0000-0000-0000-000000000000' } }
}

function Get-AzVM {
    [CmdletBinding()]
    param([string]$ResourceGroupName, [string]$Name, [switch]$Status)
    $vm = $script:Estate.vms.$Name
    if (-not $vm) { Write-StubNotFound -Type 'Microsoft.Compute/virtualMachines' -Name $Name -ResourceGroup $ResourceGroupName; return }
    if ($Status) {
        return [pscustomobject]@{
            Name     = $Name
            Statuses = @(
                [pscustomobject]@{ Code = 'ProvisioningState/succeeded'; DisplayStatus = 'Provisioning succeeded' }
                [pscustomobject]@{ Code = "PowerState/$($vm.power)"; DisplayStatus = "VM $($vm.power)" }
            )
        }
    }
    [pscustomobject]@{
        Name           = $Name
        Zones          = @($vm.zones)
        NetworkProfile = [pscustomobject]@{ NetworkInterfaces = @($vm.nicIds | ForEach-Object { [pscustomobject]@{ Id = $_ } }) }
        StorageProfile = [pscustomobject]@{
            DataDisks = @($vm.dataDisks | ForEach-Object {
                [pscustomobject]@{ Lun = $_.lun; Name = $_.name; DiskSizeGB = $_.sizeGB; ManagedDisk = [pscustomobject]@{ Id = "/subscriptions/s/resourceGroups/rg/providers/Microsoft.Compute/disks/$($_.name)" } }
            })
        }
    }
}

function Get-AzNetworkInterface {
    [CmdletBinding()]
    param([string]$ResourceId, [string]$Name, [string]$ResourceGroupName)
    $nic = $script:Estate.nics.$ResourceId
    if (-not $nic) { Write-StubNotFound -Type 'Microsoft.Network/networkInterfaces' -Name $ResourceId -ResourceGroup 'rg'; return }
    [pscustomobject]@{
        Id               = $ResourceId
        IpConfigurations = @([pscustomobject]@{
            Id                        = "$ResourceId/ipConfigurations/ipconfig1"
            Subnet                    = [pscustomobject]@{ Id = $nic.subnetId }
            ApplicationSecurityGroups = @($nic.asgIds | ForEach-Object { [pscustomobject]@{ Id = $_ } })
        })
    }
}

function Get-AzLoadBalancer {
    [CmdletBinding()]
    param([string]$ResourceGroupName, [string]$Name)
    [pscustomobject]@{
        Name                = $Name
        BackendAddressPools = @($script:Estate.lb.pools.PSObject.Properties | ForEach-Object {
            [pscustomobject]@{ Name = $_.Name; BackendIpConfigurations = @($_.Value | ForEach-Object { [pscustomobject]@{ Id = $_ } }) }
        })
    }
}

function Get-AzKeyVault {
    [CmdletBinding()]
    param([string]$VaultName, [string]$ResourceGroupName)
    $kv = $script:Estate.keyVault
    if (-not $kv -or $kv.name -ne $VaultName) { return }
    [pscustomobject]@{ VaultName = $kv.name; EnabledForDiskEncryption = [bool]$kv.enabledForDiskEncryption }
}

function Get-AzVMDiskEncryptionStatus {
    [CmdletBinding()]
    param([string]$ResourceGroupName, [string]$VMName)
    $vm = $script:Estate.vms.$VMName
    if (-not $vm) { Write-StubNotFound -Type 'Microsoft.Compute/virtualMachines' -Name $VMName -ResourceGroup $ResourceGroupName; return }
    [pscustomobject]@{ OsVolumeEncrypted = $vm.ade.os; DataVolumesEncrypted = $vm.ade.data }
}

function Get-AzVmss {
    [CmdletBinding()]
    param([string]$ResourceGroupName, [string]$VMScaleSetName)
    if (@($script:Estate.vmss) -notcontains $VMScaleSetName) {
        Write-StubNotFound -Type 'Microsoft.Compute/virtualMachineScaleSets' -Name $VMScaleSetName -ResourceGroup $ResourceGroupName
        return
    }
    [pscustomobject]@{ Name = $VMScaleSetName }
}
'@

    # A dev estate as the guide leaves it. -Bicep switches to the names main.bicep gives the NICs;
    # every other switch breaks one thing.
    function New-Estate {
        param(
            [switch]$Bicep,
            [switch]$NoAuthAsg,
            [switch]$WorldNotInEgress,
            [switch]$NoDataDisk,
            [switch]$AuthUnencrypted,
            [switch]$WorldEncrypted,
            [switch]$NoKeyVault,
            [switch]$NoWorldVm,
            [switch]$LeftoverVmss
        )
        $rg      = '/subscriptions/s/resourceGroups/dev-skycraft-swc-rg/providers'
        $subnets = "$rg/Microsoft.Network/virtualNetworks/dev-skycraft-swc-vnet/subnets"
        $asgs    = "$rg/Microsoft.Network/applicationSecurityGroups"
        $authNic  = if ($Bicep) { "$rg/Microsoft.Network/networkInterfaces/dev-skycraft-swc-auth-nic" } else { "$rg/Microsoft.Network/networkInterfaces/dev-skycraft-swc-auth-vm628" }
        $worldNic = if ($Bicep) { "$rg/Microsoft.Network/networkInterfaces/dev-skycraft-swc-world-nic" } else { "$rg/Microsoft.Network/networkInterfaces/dev-skycraft-swc-world-vm113" }
        # The guide's name; main.bicep uses it too since #355.
        $diskName = 'dev-skycraft-swc-world-vm-data'

        $vms = [ordered]@{
            'dev-skycraft-swc-auth-vm' = @{
                power = 'running'; zones = @('1'); nicIds = @($authNic); dataDisks = @()
                ade = @{ os = $(if ($AuthUnencrypted) { 'NotEncrypted' } else { 'Encrypted' }); data = 'NotMounted' }
            }
        }
        if (-not $NoWorldVm) {
            $vms['dev-skycraft-swc-world-vm'] = @{
                power = 'running'; zones = @('2'); nicIds = @($worldNic)
                dataDisks = @(if (-not $NoDataDisk) { @{ lun = 0; name = $diskName; sizeGB = 64 } })
                ade = $(if ($WorldEncrypted) { @{ os = 'Encrypted'; data = 'Encrypted' } } else { @{ os = 'NotEncrypted'; data = 'NotEncrypted' } })
            }
        }
        $egress = @("$authNic/ipConfigurations/ipconfig1")
        if (-not $WorldNotInEgress) { $egress += "$worldNic/ipConfigurations/ipconfig1" }

        @{
            vms  = $vms
            nics = @{
                $authNic  = @{ subnetId = "$subnets/AuthSubnet"; asgIds = @(if (-not $NoAuthAsg) { "$asgs/dev-skycraft-swc-asg-auth" }) }
                $worldNic = @{ subnetId = "$subnets/WorldSubnet"; asgIds = @("$asgs/dev-skycraft-swc-asg-world") }
            }
            lb   = @{ pools = [ordered]@{
                'dev-skycraft-swc-lb-be-auth'     = @("$authNic/ipConfigurations/ipconfig1")
                'dev-skycraft-swc-lb-be-world'    = @("$worldNic/ipConfigurations/ipconfig1")
                'dev-skycraft-swc-lb-be-outbound' = $egress
            } }
            keyVault = $(if ($NoKeyVault) { $null } else { @{ name = 'dev-skycraft-swc-kv'; enabledForDiskEncryption = $true } })
            vmss     = @(if ($LeftoverVmss) { 'dev-skycraft-swc-world-vmss' })
        }
    }

    function Invoke-Validator {
        param([hashtable]$Estate)
        $path = Join-Path $script:Stub.Directory ('estate-' + [guid]::NewGuid().ToString('N') + '.json')
        $Estate | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $path -Encoding utf8
        Invoke-LabScriptWithStub -Stub $script:Stub -ScriptPath $script:ScriptPath -Environment @{ SKYCRAFT_STUB_ESTATE = $path }
    }

    $script:Stub = Initialize-LabScriptStub -Name 'SkyCraftLab32TestLabStub' -Command $script:StubCommands `
        -Body $script:StubBody -RequiredModule $script:RequiredModules

    # One child process per scenario, reused by the assertions below.
    $script:Portal          = Invoke-Validator (New-Estate)
    $script:BicepBuilt      = Invoke-Validator (New-Estate -Bicep)
    $script:NoAuthAsg       = Invoke-Validator (New-Estate -NoAuthAsg)
    $script:NoEgress        = Invoke-Validator (New-Estate -WorldNotInEgress)
    $script:NoDataDisk      = Invoke-Validator (New-Estate -NoDataDisk)
    $script:AuthUnencrypted = Invoke-Validator (New-Estate -AuthUnencrypted)
    $script:WorldEncrypted  = Invoke-Validator (New-Estate -WorldEncrypted)
    $script:NoKeyVault      = Invoke-Validator (New-Estate -NoKeyVault)
    $script:NoWorldVm       = Invoke-Validator (New-Estate -NoWorldVm)
    $script:LeftoverVmss    = Invoke-Validator (New-Estate -LeftoverVmss)

    $script:AllRuns = @(
        $script:Portal, $script:BicepBuilt, $script:NoAuthAsg, $script:NoEgress, $script:NoDataDisk,
        $script:AuthUnencrypted, $script:WorldEncrypted, $script:NoKeyVault, $script:NoWorldVm, $script:LeftoverVmss
    )
}

AfterAll {
    if ($script:Stub.Directory) { Remove-Item -LiteralPath $script:Stub.Directory -Recurse -Force -ErrorAction SilentlyContinue }
}

Describe 'Lab 3.2 Test-Lab.ps1 - test harness' {
    It 'shadows the real Az commands instead of touching a subscription' {
        foreach ($run in $script:AllRuns) {
            $run.Refused | Should -BeFalse -Because "the harness must never fall through to the real Az commands (exit $($run.ExitCode)): $($run.Output)"
        }
    }
}

Describe 'Lab 3.2 Test-Lab.ps1 - passes whichever path built the lab (#355, #362)' {
    It 'passes a lab built in the Portal, whose NICs are named after the VM plus digits' {
        $script:Portal.ExitCode | Should -Be 0 -Because "output was:`n$($script:Portal.Output)"
        $script:Portal.Output   | Should -Match 'Failed: 0'
        $script:Portal.Output   | Should -Not -MatchExactly 'FAIL'
    }

    It 'passes a lab built with the Bicep, whose NICs carry the template names' {
        $script:BicepBuilt.ExitCode | Should -Be 0 -Because "output was:`n$($script:BicepBuilt.Output)"
        $script:BicepBuilt.Output   | Should -Match 'Failed: 0'
    }

    It 'warns about a scale set left behind without failing the run' {
        $script:LeftoverVmss.ExitCode | Should -Be 0 -Because "output was:`n$($script:LeftoverVmss.Output)"
        $script:LeftoverVmss.Output   | Should -Match '\[WARN\][^\r\n]*dev-skycraft-swc-world-vmss'
    }
}

Describe 'Lab 3.2 Test-Lab.ps1 - fails on a broken lab' {
    It 'fails <name> with a [FAIL] line that names it' -ForEach @(
        @{ name = 'an auth NIC outside its application security group'; run = 'NoAuthAsg'; pattern = 'Auth NIC in application security group dev-skycraft-swc-asg-auth[^\r\n]*FAIL' }
        @{ name = 'a world NIC outside the egress pool'; run = 'NoEgress'; pattern = 'World VM NIC in egress pool[^\r\n]*FAIL' }
        @{ name = 'a world VM without its data disk'; run = 'NoDataDisk'; pattern = 'data disk at LUN 0[^\r\n]*FAIL' }
        @{ name = 'an auth VM that is not encrypted'; run = 'AuthUnencrypted'; pattern = 'Auth VM OS disk encrypted[^\r\n]*FAIL' }
        @{ name = 'a world VM that is encrypted (#368)'; run = 'WorldEncrypted'; pattern = 'World VM not encrypted[^\r\n]*FAIL' }
        @{ name = 'a missing key vault'; run = 'NoKeyVault'; pattern = 'Key vault dev-skycraft-swc-kv[^\r\n]*FAIL' }
    ) {
        $result = (Get-Variable -Scope Script -Name $run).Value
        $result.ExitCode | Should -Be 1 -Because "output was:`n$($result.Output)"
        $result.Output   | Should -Match $pattern
    }

    It 'reports a missing VM as failures and still prints the summary, instead of crashing' {
        $run = $script:NoWorldVm
        $run.ExitCode | Should -Be 1 -Because "output was:`n$($run.Output)"
        $run.Output   | Should -Match 'Test Results Summary'
        $run.Output   | Should -Not -Match 'Cannot index into a null array'
        $run.Output   | Should -Match 'World VM exists and running[^\r\n]*FAIL'
    }
}
