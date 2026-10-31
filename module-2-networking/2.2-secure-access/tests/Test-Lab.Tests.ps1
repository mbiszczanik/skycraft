<#
.SYNOPSIS
    Pester 5 tests for the Lab 2.2 validator: the Bastion must be in provisioning state Succeeded.

.DESCRIPTION
    Issue #371: Test-Lab.ps1 confirmed that the Bastion exists and read its SKU and tags, but never
    its provisioningState, so a Bastion Azure left Failed passed. These tests run the real
    Test-Lab.ps1 in a child pwsh process against a generated stub of the Az getters it calls, and
    assert:

      1. An estate with the Bastion Succeeded passes: exit 0, no failures.
      2. A Bastion in state Failed, or with no state, fails: exit 1, one failure, and the line
         names the state.
      3. An estate without a Bastion passes (the Bastion is optional).

    No subscription is needed, and none is used. The script runs through
    tests/Support/LabScriptStub.psm1 (issue #112), which aborts the child with exit 99 unless
    every stubbed command resolves to the stub.

.EXAMPLE
    Invoke-Pester -Path .\Test-Lab.Tests.ps1

.NOTES
    Project: SkyCraft
    Lab: 2.2 - Secure Access
    Issue: #371
#>

#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..' '..' '..' 'tests' 'Support' 'LabScriptStub.psm1') -Force

    $script:ScriptPath      = (Resolve-Path (Join-Path $PSScriptRoot '..' 'scripts' 'Test-Lab.ps1')).Path
    $script:StubModuleName  = 'SkyCraftLab22TestLabStub'
    # Exactly the script's '#Requires -Modules' line.
    $script:RequiredModules = @('Az.Accounts', 'Az.Network')

    $script:StubCommands = @(
        'Get-AzContext'
        'Get-AzApplicationSecurityGroup'
        'Get-AzNetworkSecurityGroup'
        'Get-AzVirtualNetwork'
        'Get-AzBastion'
        'Get-AzPublicIpAddress'
    )

    # SKYCRAFT_STUB_BASTION: 'succeeded', 'failed', 'nostate' or 'none' (no Bastion deployed).
    $script:StubBody = @'
$script:Tags = @{ Project = 'SkyCraft'; Environment = 'Platform'; CostCenter = 'MSDN'; Owner = 'learner' }

function Get-AzContext {
    [CmdletBinding()]
    param()
    [pscustomobject]@{ Subscription = [pscustomobject]@{ Id = '00000000-0000-0000-0000-000000000000'; Name = 'stub-subscription' } }
}

function Get-AzApplicationSecurityGroup {
    [CmdletBinding()]
    param([string]$ResourceGroupName, [string]$Name)
    [pscustomobject]@{ Name = $Name }
}

function Get-AzNetworkSecurityGroup {
    [CmdletBinding()]
    param([string]$ResourceGroupName, [string]$Name)
    $port = switch -Wildcard ($Name) { '*-auth-nsg' { '3724' } '*-world-nsg' { '8085' } default { '3306' } }
    [pscustomobject]@{ Name = $Name; SecurityRules = @([pscustomobject]@{ Name = 'Allow-Port'; DestinationPortRange = $port; Access = 'Allow' }) }
}

function Get-AzVirtualNetwork {
    [CmdletBinding()]
    param([string]$Name, [string]$ResourceGroupName)
    $env = ($Name -split '-')[0]
    function New-Subnet($SubnetName, $Role, $Endpoints) {
        [pscustomobject]@{
            Name = $SubnetName
            NetworkSecurityGroup = [pscustomobject]@{ Id = "/subscriptions/s/resourceGroups/rg/providers/Microsoft.Network/networkSecurityGroups/$env-skycraft-swc-$Role-nsg" }
            ServiceEndpoints = @($Endpoints | ForEach-Object { [pscustomobject]@{ Service = $_ } })
        }
    }
    [pscustomobject]@{
        Name    = $Name
        Subnets = @(
            (New-Subnet 'AuthSubnet' 'auth' @())
            (New-Subnet 'WorldSubnet' 'world' @('Microsoft.Storage'))
            (New-Subnet 'DatabaseSubnet' 'db' @('Microsoft.Sql', 'Microsoft.Storage'))
        )
    }
}

function Get-AzBastion {
    [CmdletBinding()]
    param([string]$ResourceGroupName, [string]$Name)
    if ($env:SKYCRAFT_STUB_BASTION -eq 'none') { return }
    $state = switch ($env:SKYCRAFT_STUB_BASTION) { 'failed' { 'Failed' } 'nostate' { $null } default { 'Succeeded' } }
    [pscustomobject]@{ Name = $Name; Sku = [pscustomobject]@{ Name = 'Basic' }; ProvisioningState = $state; Tag = $script:Tags }
}

function Get-AzPublicIpAddress {
    [CmdletBinding()]
    param([string]$Name, [string]$ResourceGroupName)
    [pscustomobject]@{ Name = $Name; Sku = [pscustomobject]@{ Name = 'Standard' }; PublicIpAllocationMethod = 'Static'; Tag = $script:Tags }
}
'@

    function Invoke-TestLab {
        param([string]$Bastion)
        Invoke-LabScriptWithStub -Stub $script:Stub -ScriptPath $script:ScriptPath -Environment @{
            SKYCRAFT_STUB_BASTION = $Bastion
        }
    }

    $script:Stub    = Initialize-LabScriptStub -Name $script:StubModuleName -Command $script:StubCommands `
        -Body $script:StubBody -RequiredModule $script:RequiredModules
    $script:StubDir = $script:Stub.Directory

    # One child process per scenario, reused by the assertions below.
    $script:Succeeded = Invoke-TestLab -Bastion 'succeeded'
    $script:Failed    = Invoke-TestLab -Bastion 'failed'
    $script:NoState   = Invoke-TestLab -Bastion 'nostate'
    $script:NoBastion = Invoke-TestLab -Bastion 'none'

    $script:AllRuns = @($script:Succeeded, $script:Failed, $script:NoState, $script:NoBastion)
}

AfterAll {
    if ($script:StubDir) { Remove-Item -LiteralPath $script:StubDir -Recurse -Force -ErrorAction SilentlyContinue }
}

Describe 'Lab 2.2 Test-Lab.ps1 - test harness' {

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

Describe 'Lab 2.2 Test-Lab.ps1 - the Bastion provisioning state (#371)' {

    It 'passes a Bastion in state Succeeded' {
        $script:Succeeded.ExitCode | Should -Be 0 -Because "output was:`n$($script:Succeeded.Output)"
        $script:Succeeded.Output | Should -Match 'Bastion provisioning state is Succeeded'
        $script:Succeeded.Output | Should -Match 'Failures: 0'
    }

    It 'fails a Bastion left in state Failed, and names the state' {
        $script:Failed.ExitCode | Should -Be 1 -Because "output was:`n$($script:Failed.Output)"
        $script:Failed.Output | Should -Match "\[FAIL\] Bastion provisioning state is 'Failed' \(Expected Succeeded\)"
        $script:Failed.Output | Should -Match 'Failures: 1'
    }

    It 'fails a Bastion that reports no provisioning state' {
        $script:NoState.ExitCode | Should -Be 1 -Because "output was:`n$($script:NoState.Output)"
        $script:NoState.Output | Should -Match "\[FAIL\] Bastion provisioning state is '' \(Expected Succeeded\)"
    }

    It 'still passes an estate without a Bastion, which is optional' {
        $script:NoBastion.ExitCode | Should -Be 0 -Because "output was:`n$($script:NoBastion.Output)"
        $script:NoBastion.Output | Should -Match '\[INFO\] Bastion not found'
    }
}
