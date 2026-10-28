<#
.SYNOPSIS
    Pester 5 tests for the Lab 5.3 validator: the flow log and the connection monitor must be
    healthy, not only present.

.DESCRIPTION
    Issue #371: Test-Lab.ps1 reported 19 passed and exit 0 for a flow log whose provisioningState
    was Failed (Traffic Analytics denied by policy), and a connection monitor whose monitoring
    status was Stopped or Failed passed too. These tests run the real Test-Lab.ps1 in a child pwsh process
    against a generated stub of the Az commands it calls, and assert:

      1. A healthy estate passes: exit 0, no failures.
      2. A flow log in state Failed, or with no state, fails the provisioning state check: exit 1.
      3. A connection monitor in state Failed, or with a status that is Stopped or Failed,
         fails: exit 1, and the line names what Azure reported. One with no status passes
         (a healthy monitor reports none, live 2026-10-28).

    No subscription is needed, and none is used. The script runs through
    tests/Support/LabScriptStub.psm1 (issue #112), which aborts the child with exit 99 unless
    every stubbed command resolves to the stub.

.EXAMPLE
    Invoke-Pester -Path .\Test-Lab.Tests.ps1

.NOTES
    Project: SkyCraft
    Lab: 5.3 - Network Monitoring
    Issue: #371
#>

#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..' '..' '..' 'tests' 'Support' 'LabScriptStub.psm1') -Force

    $script:ScriptPath      = (Resolve-Path (Join-Path $PSScriptRoot '..' 'scripts' 'Test-Lab.ps1')).Path
    $script:StubModuleName  = 'SkyCraftLab53TestLabStub'
    # Exactly the script's '#Requires -Modules' line.
    $script:RequiredModules = @('Az.Accounts', 'Az.Network', 'Az.Resources')

    $script:StubCommands = @(
        'Get-AzContext'
        'Get-AzNetworkWatcher'
        'Get-AzNetworkWatcherFlowLog'
        'Get-AzResource'
    )

    #   SKYCRAFT_STUB_FLOWLOG   'ok', 'failed' (provisioningState Failed) or 'nostate'
    #   SKYCRAFT_STUB_CM        'ok', 'failed' (provisioningState Failed), 'nullstatus',
    #                           'stopped' or 'statusfailed' (monitoring status)
    $script:StubBody = @'
$script:Sub  = '00000000-0000-0000-0000-000000000000'
$script:Tags = @{ Project = 'SkyCraft'; Environment = 'Platform'; CostCenter = 'MSDN' }
$script:FlowLogId = "/subscriptions/$script:Sub/resourceGroups/NetworkWatcherRG/providers/Microsoft.Network/networkWatchers/NetworkWatcher_swedencentral/flowLogs/prod-skycraft-swc-vnet-flowlog"

function Get-AzContext {
    [CmdletBinding()]
    param()
    [pscustomobject]@{
        Account      = [pscustomobject]@{ Id = 'stub-account' }
        Subscription = [pscustomobject]@{ Id = $script:Sub }
    }
}

function Get-AzNetworkWatcher {
    [CmdletBinding()]
    param([Parameter(ValueFromRemainingArguments)]$Rest)
    [pscustomobject]@{ Name = 'NetworkWatcher_swedencentral'; ResourceGroupName = 'NetworkWatcherRG'; Location = 'swedencentral'; ProvisioningState = 'Succeeded' }
}

function Get-AzNetworkWatcherFlowLog {
    [CmdletBinding()]
    param([string]$NetworkWatcherName, [string]$ResourceGroupName, [string]$Name, [Parameter(ValueFromRemainingArguments)]$Rest)
    $state = switch ($env:SKYCRAFT_STUB_FLOWLOG) { 'failed' { 'Failed' } 'nostate' { $null } default { 'Succeeded' } }
    [pscustomobject]@{
        Name                      = $Name
        Id                        = $script:FlowLogId
        ProvisioningState         = $state
        Enabled                   = $true
        Format                    = [pscustomobject]@{ Version = 2 }
        RetentionPolicy           = [pscustomobject]@{ Days = 7; Enabled = $true }
        TargetResourceId          = "/subscriptions/$script:Sub/resourceGroups/prod-skycraft-swc-rg/providers/Microsoft.Network/virtualNetworks/prod-skycraft-swc-vnet"
        FlowAnalyticsConfiguration = [pscustomobject]@{ NetworkWatcherFlowAnalyticsConfiguration = [pscustomobject]@{
            Enabled = $true; TrafficAnalyticsInterval = 10
            WorkspaceResourceId = "/subscriptions/$script:Sub/resourceGroups/platform-skycraft-swc-rg/providers/Microsoft.OperationalInsights/workspaces/platform-skycraft-swc-law"
        } }
    }
}

function Get-AzResource {
    [CmdletBinding()]
    param([string]$ResourceId, [switch]$ExpandProperties, [Parameter(ValueFromRemainingArguments)]$Rest)
    if ($ResourceId -eq $script:FlowLogId) { return [pscustomobject]@{ ResourceId = $ResourceId; Tags = $script:Tags } }
    $provisioning = if ($env:SKYCRAFT_STUB_CM -eq 'failed') { 'Failed' } else { 'Succeeded' }
    $status = switch ($env:SKYCRAFT_STUB_CM) { 'nullstatus' { $null } 'stopped' { 'Stopped' } 'statusfailed' { 'Failed' } default { 'Running' } }
    [pscustomobject]@{
        Name       = 'skycraft-hub-spoke-cm'
        ResourceId = $ResourceId
        Tags       = $script:Tags
        Properties = [pscustomobject]@{
            provisioningState  = $provisioning
            monitoringStatus   = $status
            testGroups         = @([pscustomobject]@{ name = 'hub-spoke-ssh' })
            testConfigurations = @([pscustomobject]@{ name = 'tcp-22-every-5m'; protocol = 'Tcp'; testFrequencySec = 300; tcpConfiguration = [pscustomobject]@{ port = 22 } })
            endpoints          = @([pscustomobject]@{ name = 'dev-auth-destination'; resourceId = '/subscriptions/s/resourceGroups/dev-skycraft-swc-rg/providers/Microsoft.Compute/virtualMachines/dev-skycraft-swc-auth-vm' })
        }
    }
}
'@

    function Invoke-TestLab {
        param([string]$FlowLog = 'ok', [string]$Cm = 'ok')
        Invoke-LabScriptWithStub -Stub $script:Stub -ScriptPath $script:ScriptPath -Environment @{
            SKYCRAFT_STUB_FLOWLOG = $FlowLog
            SKYCRAFT_STUB_CM      = $Cm
        }
    }

    $script:Stub    = Initialize-LabScriptStub -Name $script:StubModuleName -Command $script:StubCommands `
        -Body $script:StubBody -RequiredModule $script:RequiredModules
    $script:StubDir = $script:Stub.Directory

    # One child process per scenario, reused by the assertions below.
    $script:Healthy        = Invoke-TestLab
    $script:FlowLogFailed  = Invoke-TestLab -FlowLog 'failed'
    $script:FlowLogNoState = Invoke-TestLab -FlowLog 'nostate'
    $script:CmFailed       = Invoke-TestLab -Cm 'failed'
    $script:CmNullStatus   = Invoke-TestLab -Cm 'nullstatus'
    $script:CmStopped      = Invoke-TestLab -Cm 'stopped'
    $script:CmStatusFailed = Invoke-TestLab -Cm 'statusfailed'

    $script:AllRuns = @(
        $script:Healthy, $script:FlowLogFailed, $script:FlowLogNoState, $script:CmFailed,
        $script:CmNullStatus, $script:CmStopped, $script:CmStatusFailed
    )
}

AfterAll {
    if ($script:StubDir) { Remove-Item -LiteralPath $script:StubDir -Recurse -Force -ErrorAction SilentlyContinue }
}

Describe 'Lab 5.3 Test-Lab.ps1 - test harness' {

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

Describe 'Lab 5.3 Test-Lab.ps1 - healthy estate' {

    It 'passes a flow log and a connection monitor that are Succeeded and Running' {
        $script:Healthy.ExitCode | Should -Be 0 -Because "output was:`n$($script:Healthy.Output)"
        $script:Healthy.Output | Should -Match 'Flow log provisioning state is Succeeded\.\.\. PASS'
        $script:Healthy.Output | Should -Match 'Connection Monitor provisioning state is Succeeded\.\.\. PASS'
        $script:Healthy.Output | Should -Match 'Connection Monitor monitoring status is not Stopped or Failed\.\.\. PASS'
        $script:Healthy.Output | Should -Match 'Failed: 0'
    }
}

Describe 'Lab 5.3 Test-Lab.ps1 - a resource left unhealthy fails (#371)' {

    It 'fails a flow log in provisioning state Failed, and names the state' {
        $script:FlowLogFailed.ExitCode | Should -Be 1 -Because "output was:`n$($script:FlowLogFailed.Output)"
        $script:FlowLogFailed.Output | Should -Match "Flow log provisioning state is Succeeded\.\.\. \(state is 'Failed'\) FAIL"
        $script:FlowLogFailed.Output | Should -Match 'Failed: 1'
    }

    It 'fails a flow log that reports no provisioning state' {
        $script:FlowLogNoState.ExitCode | Should -Be 1 -Because "output was:`n$($script:FlowLogNoState.Output)"
        $script:FlowLogNoState.Output | Should -Match "Flow log provisioning state is Succeeded\.\.\. \(state is ''\) FAIL"
    }

    It 'fails a connection monitor in provisioning state Failed' {
        $script:CmFailed.ExitCode | Should -Be 1 -Because "output was:`n$($script:CmFailed.Output)"
        $script:CmFailed.Output | Should -Match "Connection Monitor provisioning state is Succeeded\.\.\. \(state is 'Failed'\) FAIL"
        $script:CmFailed.Output | Should -Match 'Failed: 1'
    }

    It 'passes a connection monitor that reports no monitoring status' {
        $script:CmNullStatus.ExitCode | Should -Be 0 -Because "a healthy monitor reports no status; output was:`n$($script:CmNullStatus.Output)"
        $script:CmNullStatus.Output | Should -Match 'monitoring status is not Stopped or Failed\.\.\. PASS'
    }

    It 'fails a connection monitor whose monitoring status is <status>' -ForEach @(
        @{ status = 'Stopped'; run = 'CmStopped' }
        @{ status = 'Failed'; run = 'CmStatusFailed' }
    ) {
        $result = (Get-Variable -Scope Script -Name $run).Value
        $result.ExitCode | Should -Be 1 -Because "output was:`n$($result.Output)"
        $result.Output | Should -Match "monitoring status is not Stopped or Failed\.\.\. \(status is '$status'\) FAIL"
    }
}
