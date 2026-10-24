<#
.SYNOPSIS
    Pester 5 tests for the Lab 2.1 validator: the AppServiceSubnet delegation.

.DESCRIPTION
    Issue #354 found that Lab 3.1's Test-Lab.ps1 passed an AppServiceSubnet without its
    delegation to Microsoft.Web/serverFarms, which Lab 3.4's VNet integration needs. Lab 2.1,
    which creates the subnet, had the same gap: it checked only the subnet's name and prefix, so a
    Portal build that skipped "Delegate subnet to a service" passed Lab 2.1 and failed only later.
    These tests run the real Test-Lab.ps1 in a child pwsh process against a generated stub of the
    Az getters it calls, and assert:

      1. A Bicep-built estate (delegation named after its service) passes: exit 0.
      2. A Portal-built estate (the Portal gives the delegation its own name) passes: the
         delegation is found by its service, not by its name.
      3. A dev AppServiceSubnet without a delegation, or delegated to another service, fails:
         exit 1, one failure.

    No subscription is needed, and none is used. The script runs through
    tests/Support/LabScriptStub.psm1 (issue #112), which aborts the child with exit 99 unless
    every stubbed command resolves to the stub.

.EXAMPLE
    Invoke-Pester -Path .\Test-Lab.Tests.ps1

.NOTES
    Project: SkyCraft
    Lab: 2.1 - Virtual Networks
#>

#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..' '..' '..' 'tests' 'Support' 'LabScriptStub.psm1') -Force

    $script:ScriptPath      = (Resolve-Path (Join-Path $PSScriptRoot '..' 'scripts' 'Test-Lab.ps1')).Path
    $script:StubModuleName  = 'SkyCraftLab21TestLabStub'
    # Exactly the script's '#Requires -Modules' line.
    $script:RequiredModules = @('Az.Accounts', 'Az.Network')

    $script:StubCommands = @(
        'Get-AzVirtualNetwork'
        'Get-AzVirtualNetworkPeering'
        'Get-AzPublicIpAddress'
    )

    # SKYCRAFT_STUB_APPSUBNET picks the dev App Service subnet's delegation (prod keeps Bicep's):
    #   bicep         named after its service (Lab 2.1 Bicep)
    #   portal        the Portal's own name
    #   nodelegation  none
    #   otherservice  another service
    $script:StubBody = @'
function New-StubSubnet {
    param([string]$Name, [string]$Prefix, [object[]]$Delegations = @())
    [pscustomobject]@{ Name = $Name; AddressPrefix = $Prefix; DefaultOutboundAccess = $false; Delegations = $Delegations }
}

function New-StubDelegation {
    param([string]$Name, [string]$ServiceName)
    [pscustomobject]@{ Name = $Name; ServiceName = $ServiceName }
}

function Get-AzVirtualNetwork {
    [CmdletBinding()]
    param([string]$Name, [string]$ResourceGroupName)
    $bicep = @(New-StubDelegation -Name 'Microsoft.Web/serverFarms' -ServiceName 'Microsoft.Web/serverFarms')
    switch ($Name) {
        'platform-skycraft-swc-vnet' {
            return [pscustomobject]@{ Name = $Name; AddressSpace = [pscustomobject]@{ AddressPrefixes = @('10.0.0.0/16') }
                Subnets = @((New-StubSubnet 'AzureBastionSubnet' '10.0.0.0/26'), (New-StubSubnet 'GatewaySubnet' '10.0.1.0/27')) }
        }
        'dev-skycraft-swc-vnet' {
            $delegations = switch ($env:SKYCRAFT_STUB_APPSUBNET) {
                'bicep'        { $bicep }
                'portal'       { @(New-StubDelegation -Name 'delegation' -ServiceName 'Microsoft.Web/serverFarms') }
                'otherservice' { @(New-StubDelegation -Name 'delegation' -ServiceName 'Microsoft.ContainerInstance/containerGroups') }
                default        { @() }
            }
            return [pscustomobject]@{ Name = $Name; AddressSpace = [pscustomobject]@{ AddressPrefixes = @('10.1.0.0/16') }
                Subnets = @((New-StubSubnet 'AuthSubnet' '10.1.1.0/24'), (New-StubSubnet 'WorldSubnet' '10.1.2.0/24'),
                            (New-StubSubnet 'DatabaseSubnet' '10.1.3.0/24'), (New-StubSubnet 'AppServiceSubnet' '10.1.4.0/24' $delegations)) }
        }
        'prod-skycraft-swc-vnet' {
            return [pscustomobject]@{ Name = $Name; AddressSpace = [pscustomobject]@{ AddressPrefixes = @('10.2.0.0/16') }
                Subnets = @((New-StubSubnet 'AuthSubnet' '10.2.1.0/24'), (New-StubSubnet 'WorldSubnet' '10.2.2.0/24'),
                            (New-StubSubnet 'DatabaseSubnet' '10.2.3.0/24'), (New-StubSubnet 'AppServiceSubnet' '10.2.4.0/24' $bicep)) }
        }
    }
    throw "stub: no VNet '$Name'"
}

function Get-AzVirtualNetworkPeering {
    [CmdletBinding()]
    param([string]$VirtualNetworkName, [string]$ResourceGroupName, [string]$Name)
    [pscustomobject]@{ Name = $Name; PeeringState = 'Connected'; AllowVirtualNetworkAccess = $true; AllowForwardedTraffic = $true }
}

function Get-AzPublicIpAddress {
    [CmdletBinding()]
    param([string]$Name, [string]$ResourceGroupName)
    [pscustomobject]@{ Name = $Name; Sku = [pscustomobject]@{ Name = 'Standard' }; PublicIpAllocationMethod = 'Static' }
}
'@

    function Invoke-TestLab {
        param([string]$AppSubnet)
        Invoke-LabScriptWithStub -Stub $script:Stub -ScriptPath $script:ScriptPath -Environment @{
            SKYCRAFT_STUB_APPSUBNET = $AppSubnet
        }
    }

    $script:Stub    = Initialize-LabScriptStub -Name $script:StubModuleName -Command $script:StubCommands `
        -Body $script:StubBody -RequiredModule $script:RequiredModules
    $script:StubDir = $script:Stub.Directory

    # One child process per scenario, reused by the assertions below.
    $script:Bicep        = Invoke-TestLab -AppSubnet 'bicep'
    $script:Portal       = Invoke-TestLab -AppSubnet 'portal'
    $script:NoDelegation = Invoke-TestLab -AppSubnet 'nodelegation'
    $script:OtherService = Invoke-TestLab -AppSubnet 'otherservice'

    $script:AllRuns = @($script:Bicep, $script:Portal, $script:NoDelegation, $script:OtherService)
}

AfterAll {
    if ($script:StubDir) { Remove-Item -LiteralPath $script:StubDir -Recurse -Force -ErrorAction SilentlyContinue }
}

Describe 'Lab 2.1 Test-Lab.ps1 - test harness' {

    It 'shadows the real Az commands instead of touching a subscription' {
        foreach ($run in $script:AllRuns) {
            $run.Refused | Should -BeFalse -Because "the harness must never fall through to the real Az commands (exit $($run.ExitCode)): $($run.Output)"
        }
    }
}

Describe 'Lab 2.1 Test-Lab.ps1 - the AppServiceSubnet delegation (#354)' {

    It 'passes a Bicep-built estate' {
        $script:Bicep.ExitCode | Should -Be 0 -Because "output was:`n$($script:Bicep.Output)"
        $script:Bicep.Output | Should -Match 'Subnet AppServiceSubnet is delegated to Microsoft\.Web/serverFarms'
    }

    It 'passes a Portal-built estate, whose delegation has another name' {
        $script:Portal.ExitCode | Should -Be 0 -Because "the delegation is found by its service, not its name; output was:`n$($script:Portal.Output)"
    }

    It 'fails a dev AppServiceSubnet with no delegation' {
        $script:NoDelegation.ExitCode | Should -Be 1 -Because "output was:`n$($script:NoDelegation.Output)"
        $script:NoDelegation.Output | Should -Match '\[FAIL\] Subnet AppServiceSubnet is not delegated to Microsoft\.Web/serverFarms \(delegations: none\)'
        $script:NoDelegation.Output | Should -Match 'Failures: 1'
    }

    It 'fails a dev AppServiceSubnet delegated to another service' {
        $script:OtherService.ExitCode | Should -Be 1 -Because "output was:`n$($script:OtherService.Output)"
        $script:OtherService.Output | Should -Match '\[FAIL\] Subnet AppServiceSubnet is not delegated to Microsoft\.Web/serverFarms \(delegations: Microsoft\.ContainerInstance/containerGroups\)'
        $script:OtherService.Output | Should -Match 'Failures: 1'
    }
}
