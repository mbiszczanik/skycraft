<#
.SYNOPSIS
    Pester 5 tests for the Lab 3.1 validator: the App Service subnet and its delegation.

.DESCRIPTION
    Issue #354: Test-Lab.ps1 checked three dev subnets and passed an estate whose
    AppServiceSubnet was missing or had no delegation, which Lab 3.4's VNet integration needs.
    These tests run the real Test-Lab.ps1 in a child pwsh process against a generated stub of
    the Az getters it calls, and assert:

      1. A Bicep-built estate (delegation named after its service) passes: exit 0.
      2. A Portal-built estate (the Portal gives the delegation its own name) passes: the
         delegation is found by its service, not by its name.
      3. A subnet without a delegation, or delegated to another service, fails: exit 1.
      4. A VNet without AppServiceSubnet fails: exit 1.

    No subscription is needed, and none is used. The script runs through
    tests/Support/LabScriptStub.psm1 (issue #112), which aborts the child with exit 99 unless
    every stubbed command resolves to the stub.

.EXAMPLE
    Invoke-Pester -Path .\Test-Lab.Tests.ps1

.NOTES
    Project: SkyCraft
    Lab: 3.1 - Infrastructure as Code
#>

#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..' '..' '..' 'tests' 'Support' 'LabScriptStub.psm1') -Force

    $script:ScriptPath      = (Resolve-Path (Join-Path $PSScriptRoot '..' 'scripts' 'Test-Lab.ps1')).Path
    $script:StubModuleName  = 'SkyCraftLab31TestLabStub'
    # Exactly the script's '#Requires -Modules' line.
    $script:RequiredModules = @('Az.Accounts', 'Az.Resources', 'Az.Network')

    $script:StubCommands = @(
        'Get-AzResourceGroup'
        'Get-AzVirtualNetwork'
        'Get-AzNetworkSecurityGroup'
        'Get-AzLoadBalancer'
        'Get-AzPublicIpAddress'
    )

    # SKYCRAFT_STUB_APPSUBNET picks the App Service subnet's shape:
    #   bicep         delegation named after its service (Lab 2.1 and 3.1 Bicep)
    #   portal        delegation with the Portal's own name
    #   nodelegation  the subnet without a delegation
    #   otherservice  delegated to another service
    #   missing       no AppServiceSubnet in the VNet
    $script:StubBody = @'
function New-StubDelegation {
    param([string]$Name, [string]$ServiceName)
    [pscustomobject]@{ Name = $Name; ServiceName = $ServiceName }
}

function Get-AzResourceGroup {
    [CmdletBinding()]
    param([string]$Name)
    [pscustomobject]@{ ResourceGroupName = $Name }
}

function Get-AzVirtualNetwork {
    [CmdletBinding()]
    param([string]$Name, [string]$ResourceGroupName)
    $subnets = [System.Collections.Generic.List[object]]::new()
    foreach ($sub in 'AuthSubnet', 'WorldSubnet', 'DatabaseSubnet') {
        $subnets.Add([pscustomobject]@{ Name = $sub; Delegations = @() })
    }
    $delegations = switch ($env:SKYCRAFT_STUB_APPSUBNET) {
        'bicep'        { @(New-StubDelegation -Name 'Microsoft.Web/serverFarms' -ServiceName 'Microsoft.Web/serverFarms') }
        'portal'       { @(New-StubDelegation -Name 'delegation' -ServiceName 'Microsoft.Web/serverFarms') }
        'otherservice' { @(New-StubDelegation -Name 'delegation' -ServiceName 'Microsoft.ContainerInstance/containerGroups') }
        default        { @() }
    }
    if ($env:SKYCRAFT_STUB_APPSUBNET -ne 'missing') {
        $subnets.Add([pscustomobject]@{ Name = 'AppServiceSubnet'; Delegations = $delegations })
    }
    [pscustomobject]@{ Name = $Name; Subnets = $subnets }
}

function Get-AzNetworkSecurityGroup {
    [CmdletBinding()]
    param([string]$Name, [string]$ResourceGroupName)
    [pscustomobject]@{ Name = $Name; SecurityRules = @('AllowBastionSSH', 'AllowServicePort') }
}

function Get-AzLoadBalancer {
    [CmdletBinding()]
    param([string]$Name, [string]$ResourceGroupName)
    [pscustomobject]@{ Name = $Name; FrontendIpConfigurations = @('frontend') }
}

function Get-AzPublicIpAddress {
    [CmdletBinding()]
    param([string]$Name, [string]$ResourceGroupName)
    [pscustomobject]@{ Name = $Name; IpAddress = '203.0.113.10' }
}
'@

    function Invoke-TestLab {
        param([string]$AppSubnet)
        Invoke-LabScriptWithStub -Stub $script:Stub -ScriptPath $script:ScriptPath -ArgumentList '-Environment', 'dev' -Environment @{
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
    $script:Missing      = Invoke-TestLab -AppSubnet 'missing'

    $script:AllRuns = @($script:Bicep, $script:Portal, $script:NoDelegation, $script:OtherService, $script:Missing)
}

AfterAll {
    if ($script:StubDir) { Remove-Item -LiteralPath $script:StubDir -Recurse -Force -ErrorAction SilentlyContinue }
}

Describe 'Lab 3.1 Test-Lab.ps1 - test harness' {

    It 'shadows the real Az commands instead of touching a subscription' {
        foreach ($run in $script:AllRuns) {
            $run.Refused | Should -BeFalse -Because "the harness must never fall through to the real Az commands (exit $($run.ExitCode)): $($run.Output)"
        }
    }
}

Describe 'Lab 3.1 Test-Lab.ps1 - the App Service subnet and its delegation (#354)' {

    It 'passes a Bicep-built estate' {
        $script:Bicep.ExitCode | Should -Be 0 -Because "output was:`n$($script:Bicep.Output)"
        $script:Bicep.Output | Should -Match "\[OK\] Subnet 'AppServiceSubnet' found, delegated to Microsoft\.Web/serverFarms"
    }

    It 'passes a Portal-built estate, whose delegation has another name' {
        $script:Portal.ExitCode | Should -Be 0 -Because "the delegation is found by its service, not its name; output was:`n$($script:Portal.Output)"
        $script:Portal.Output | Should -Match "\[OK\] Subnet 'AppServiceSubnet' found, delegated to Microsoft\.Web/serverFarms"
    }

    It 'fails a subnet with no delegation' {
        $script:NoDelegation.ExitCode | Should -Be 1 -Because "output was:`n$($script:NoDelegation.Output)"
        $script:NoDelegation.Output | Should -Match "\[FAIL\] Subnet 'AppServiceSubnet' is not delegated to Microsoft\.Web/serverFarms \(delegations: none\)"
        $script:NoDelegation.Output | Should -Match 'Failures: 1'
    }

    It 'fails a subnet delegated to another service' {
        $script:OtherService.ExitCode | Should -Be 1 -Because "output was:`n$($script:OtherService.Output)"
        $script:OtherService.Output | Should -Match "\[FAIL\] Subnet 'AppServiceSubnet' is not delegated to Microsoft\.Web/serverFarms \(delegations: Microsoft\.ContainerInstance/containerGroups\)"
    }

    It 'fails a VNet without AppServiceSubnet' {
        $script:Missing.ExitCode | Should -Be 1 -Because "output was:`n$($script:Missing.Output)"
        $script:Missing.Output | Should -Match "\[FAIL\] Subnet 'AppServiceSubnet' MISSING"
        $script:Missing.Output | Should -Match 'Failures: 1'
    }
}
