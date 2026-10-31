<#
.SYNOPSIS
    Pester 5 tests for the Lab 2.3 validator: the private DNS links and the load balancers must be
    in provisioning state Succeeded.

.DESCRIPTION
    Issue #371: Test-Lab.ps1 confirmed that each private DNS link and load balancer exists and read
    its settings, but never its provisioningState, so a resource Azure left Failed passed. These
    tests run the real Test-Lab.ps1 in a child pwsh process against a generated stub of the Az
    getters it calls, and assert:

      1. An estate with every link and load balancer Succeeded passes: exit 0, no errors.
      2. A private DNS link in state Failed, or without a state, fails: exit 1, one error, and the
         line names the link and the state.
      3. A load balancer in state Failed fails the same way, and names the load balancer.

    No subscription is needed, and none is used. The script runs through
    tests/Support/LabScriptStub.psm1 (issue #112), which aborts the child with exit 99 unless
    every stubbed command resolves to the stub.

.EXAMPLE
    Invoke-Pester -Path .\Test-Lab.Tests.ps1

.NOTES
    Project: SkyCraft
    Lab: 2.3 - Name Resolution and Load Balancing
    Issue: #371
#>

#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..' '..' '..' 'tests' 'Support' 'LabScriptStub.psm1') -Force

    $script:ScriptPath      = (Resolve-Path (Join-Path $PSScriptRoot '..' 'scripts' 'Test-Lab.ps1')).Path
    $script:StubModuleName  = 'SkyCraftLab23TestLabStub'
    # Exactly the script's '#Requires -Modules' line.
    $script:RequiredModules = @('Az.Accounts', 'Az.Dns', 'Az.Network')

    $script:StubCommands = @(
        'Get-AzContext'
        'Get-AzDnsZone'
        'Get-AzDnsRecordSet'
        'Get-AzPublicIpAddress'
        'Get-AzPrivateDnsZone'
        'Get-AzPrivateDnsVirtualNetworkLink'
        'Get-AzLoadBalancer'
    )

    # SKYCRAFT_STUB_LINK: 'dev-vnet-link' (or another link name) is the one link left in state
    # Failed, 'nostate' gives dev-vnet-link no state. SKYCRAFT_STUB_LB: the load balancer left Failed.
    $script:StubBody = @'
function Get-StubTags($Environment) { @{ Project = 'SkyCraft'; Environment = $Environment; CostCenter = 'MSDN'; Owner = 'learner' } }

function Get-AzContext {
    [CmdletBinding()]
    param()
    [pscustomobject]@{ Subscription = [pscustomobject]@{ Id = '00000000-0000-0000-0000-000000000000'; Name = 'stub-subscription' } }
}

function Get-AzDnsZone {
    [CmdletBinding()]
    param([string]$ResourceGroupName, [string]$Name)
    [pscustomobject]@{ Name = $Name; Tags = Get-StubTags 'Platform' }
}

function Get-AzDnsRecordSet {
    [CmdletBinding()]
    param([string]$ResourceGroupName, [string]$ZoneName, [string]$Name, [string]$RecordType)
    [pscustomobject]@{ Name = $Name; RecordType = $RecordType; Records = @([pscustomobject]@{ Ipv4Address = '192.0.2.10' }) }
}

function Get-AzPublicIpAddress {
    [CmdletBinding()]
    param([string]$ResourceGroupName, [string]$Name)
    [pscustomobject]@{ Name = $Name; IpAddress = '192.0.2.10' }
}

function Get-AzPrivateDnsZone {
    [CmdletBinding()]
    param([string]$ResourceGroupName, [string]$Name)
    [pscustomobject]@{ Name = $Name; Tags = Get-StubTags 'Platform' }
}

function Get-AzPrivateDnsVirtualNetworkLink {
    [CmdletBinding()]
    param([string]$ResourceGroupName, [string]$ZoneName)
    foreach ($name in 'hub-vnet-link', 'dev-vnet-link', 'prod-vnet-link') {
        $state = 'Succeeded'
        if ($env:SKYCRAFT_STUB_LINK -eq $name) { $state = 'Failed' }
        if ($env:SKYCRAFT_STUB_LINK -eq 'nostate' -and $name -eq 'dev-vnet-link') { $state = $null }
        [pscustomobject]@{ Name = $name; RegistrationEnabled = ($name -ne 'hub-vnet-link'); ProvisioningState = $state }
    }
}

function Get-AzLoadBalancer {
    [CmdletBinding()]
    param([string]$ResourceGroupName, [string]$Name)
    $environment = if ($Name -like 'dev-*') { 'Development' } else { 'Production' }
    $pool = "$Name-be-outbound"
    [pscustomobject]@{
        Name                = $Name
        ProvisioningState   = if ($env:SKYCRAFT_STUB_LB -eq $Name) { 'Failed' } else { 'Succeeded' }
        Sku                 = [pscustomobject]@{ Name = 'Standard' }
        Probes              = @([pscustomobject]@{ Name = 'p1'; ProbeThreshold = 1 }, [pscustomobject]@{ Name = 'p2'; ProbeThreshold = 1 })
        LoadBalancingRules  = @([pscustomobject]@{ Name = 'r1'; DisableOutboundSnat = $true }, [pscustomobject]@{ Name = 'r2'; DisableOutboundSnat = $true })
        BackendAddressPools = @([pscustomobject]@{ Name = $pool })
        OutboundRules       = @([pscustomobject]@{ Name = 'egress'; Protocol = 'All'; AllocatedOutboundPorts = 1024; BackendAddressPool = [pscustomobject]@{ Id = "/subscriptions/s/lb/backendAddressPools/$pool" } })
        Tag                 = Get-StubTags $environment
    }
}
'@

    function Invoke-TestLab {
        param([string]$Link = '', [string]$Lb = '')
        Invoke-LabScriptWithStub -Stub $script:Stub -ScriptPath $script:ScriptPath -Environment @{
            SKYCRAFT_STUB_LINK = $Link
            SKYCRAFT_STUB_LB   = $Lb
        }
    }

    $script:Stub    = Initialize-LabScriptStub -Name $script:StubModuleName -Command $script:StubCommands `
        -Body $script:StubBody -RequiredModule $script:RequiredModules
    $script:StubDir = $script:Stub.Directory

    # One child process per scenario, reused by the assertions below.
    $script:Healthy    = Invoke-TestLab
    $script:LinkFailed = Invoke-TestLab -Link 'dev-vnet-link'
    $script:LinkNoState = Invoke-TestLab -Link 'nostate'
    $script:LbFailed   = Invoke-TestLab -Lb 'prod-skycraft-swc-lb'

    $script:AllRuns = @($script:Healthy, $script:LinkFailed, $script:LinkNoState, $script:LbFailed)
}

AfterAll {
    if ($script:StubDir) { Remove-Item -LiteralPath $script:StubDir -Recurse -Force -ErrorAction SilentlyContinue }
}

Describe 'Lab 2.3 Test-Lab.ps1 - test harness' {

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

Describe 'Lab 2.3 Test-Lab.ps1 - provisioning state (#371)' {

    It 'passes links and load balancers in state Succeeded' {
        $script:Healthy.ExitCode | Should -Be 0 -Because "output was:`n$($script:Healthy.Output)"
        $script:Healthy.Output | Should -Match "Link 'dev-vnet-link' provisioning state is Succeeded"
        $script:Healthy.Output | Should -Match 'All checks passed'
    }

    It 'fails a private DNS link left in state Failed, and names it' {
        $script:LinkFailed.ExitCode | Should -Be 1 -Because "output was:`n$($script:LinkFailed.Output)"
        $script:LinkFailed.Output | Should -Match "\[FAIL\] Link 'dev-vnet-link' provisioning state is 'Failed' \(Expected Succeeded\)"
        $script:LinkFailed.Output | Should -Match 'failed with 1 error'
    }

    It 'fails a private DNS link that reports no provisioning state' {
        $script:LinkNoState.ExitCode | Should -Be 1 -Because "output was:`n$($script:LinkNoState.Output)"
        $script:LinkNoState.Output | Should -Match "\[FAIL\] Link 'dev-vnet-link' provisioning state is '' \(Expected Succeeded\)"
    }

    It 'fails a load balancer left in state Failed' {
        $script:LbFailed.ExitCode | Should -Be 1 -Because "output was:`n$($script:LbFailed.Output)"
        $script:LbFailed.Output | Should -Match "\[FAIL\] Provisioning state is 'Failed' \(Expected Succeeded\)"
        $script:LbFailed.Output | Should -Match 'failed with 1 error'
    }
}
