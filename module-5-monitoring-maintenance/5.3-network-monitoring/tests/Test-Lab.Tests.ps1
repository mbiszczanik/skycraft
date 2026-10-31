<#
.SYNOPSIS
    Pester 5 tests: the Lab 5.3 validator reads the connection monitor at an explicit api-version
    and reports a failed lookup as an error, not as a missing monitor.

.DESCRIPTION
    Regression cover for issue #452. Get-AzResource -ResourceId without -ApiVersion asks ARM with
    the newest version the provider lists. On 2026-10-28 that was 2026-07-01 for connection
    monitors, which Sweden Central did not serve yet, and Test-Lab.ps1 swallowed the error with
    -ErrorAction SilentlyContinue, so the monitor was reported as missing. These tests run the
    real Test-Lab.ps1 in a child pwsh against a generated stub of the Az commands it calls. The
    stub serves connection monitors only at 2024-05-01, as the region did, and throws the
    region's error for any other version, and for a call with none. They assert that:

      1. With the monitor present, the connection monitor checks pass, which they cannot do
         unless the script sends an api-version the region serves.
      2. When the monitor is genuinely missing (ResourceNotFound), the check fails as a missing
         monitor.
      3. When ARM refuses the read (AuthorizationFailed), the checks fail and print that error.

    No subscription is needed, and none is used: tests/Support/LabScriptStub.psm1 (issue #112)
    aborts the child with exit 99 unless every stubbed command resolves to the stub.

.EXAMPLE
    Invoke-Pester -Path .\Test-Lab.Tests.ps1

.NOTES
    Project: SkyCraft
    Lab: 5.3 - Network Monitoring & Diagnostics
    Issue: #452
#>

#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..' '..' '..' 'tests' 'Support' 'LabScriptStub.psm1') -Force

    $script:ScriptPath     = (Resolve-Path (Join-Path $PSScriptRoot '..' 'scripts' 'Test-Lab.ps1')).Path
    $script:StubModuleName = 'SkyCraftLab53ValidatorStub'
    # Exactly the script's '#Requires -Modules' line.
    $script:RequiredModules = @('Az.Accounts', 'Az.Network', 'Az.Resources')

    $script:StubCommands = @(
        'Get-AzContext'
        'Get-AzNetworkWatcher'
        'Get-AzNetworkWatcherFlowLog'
        'Get-AzResource'
    )

    #   SKYCRAFT_STUB_CM   'present' (the monitor exists), 'gone' (ARM answers ResourceNotFound) or 'denied' (ARM refuses the read)
    $script:StubBody = @'
function Get-AzContext {
    [CmdletBinding()]
    param()
    [pscustomobject]@{
        Account      = [pscustomobject]@{ Id = 'stub-account' }
        Subscription = [pscustomobject]@{ Id = '00000000-0000-0000-0000-000000000000' }
    }
}

function Get-AzNetworkWatcher { [CmdletBinding()] param([Parameter(ValueFromRemainingArguments)]$Rest) }
function Get-AzNetworkWatcherFlowLog { [CmdletBinding()] param([Parameter(ValueFromRemainingArguments)]$Rest) }

# Connection monitors are served at 2024-05-01 only; the provider lists 2026-07-01 as the newest,
# which is what ARM uses when the call names no version.
function Get-AzResource {
    [CmdletBinding()]
    param([string]$ResourceId, [string]$ApiVersion, [switch]$ExpandProperties, [Parameter(ValueFromRemainingArguments)]$Rest)
    if ($ResourceId -notlike '*/connectionMonitors/*') { return }
    $version = if ($ApiVersion) { $ApiVersion } else { '2026-07-01' }
    if ($version -ne '2024-05-01') {
        throw "No registered resource provider found for location 'swedencentral' and API version '$version' for type 'networkWatchers/connectionMonitors'. The supported api-versions are '2017-09-01, 2024-05-01'."
    }
    if ($env:SKYCRAFT_STUB_CM -eq 'denied') {
        throw "AuthorizationFailed: The client does not have authorization to perform action 'Microsoft.Network/networkWatchers/connectionMonitors/read'."
    }
    if ($env:SKYCRAFT_STUB_CM -eq 'gone') {
        throw "ResourceNotFound: The Resource 'Microsoft.Network/networkWatchers/NetworkWatcher_swedencentral/connectionMonitors/skycraft-hub-spoke-cm' under resource group 'NetworkWatcherRG' was not found."
    }
    [pscustomobject]@{
        Name       = ($ResourceId -split '/')[-1]
        ResourceId = $ResourceId
        Tags       = @{ Project = 'SkyCraft'; CostCenter = 'MSDN' }
        Properties = [pscustomobject]@{ monitoringStatus = 'Running' }
    }
}
'@

    function Invoke-ValidatorScript {
        param(
            [pscustomobject]$Stub,
            [ValidateSet('present', 'gone', 'denied')]
            [string]$Monitor
        )
        $run = Invoke-LabScriptWithStub -Stub $Stub -ScriptPath $script:ScriptPath -Environment @{
            SKYCRAFT_STUB_CM = $Monitor
        }
        return [pscustomobject]@{
            ExitCode = $run.ExitCode
            Refused  = $run.Refused
            Output   = $run.Output
            # The two lines under test.
            Exists   = ($run.Output -split '\r?\n' | Where-Object { $_ -match "Testing: Connection Monitor 'skycraft-hub-spoke-cm' exists" }) -join "`n"
            Status   = ($run.Output -split '\r?\n' | Where-Object { $_ -match 'Testing: Connection Monitor monitoring status' }) -join "`n"
        }
    }

    $script:Stub    = Initialize-LabScriptStub -Name $script:StubModuleName -Command $script:StubCommands `
        -Body $script:StubBody -RequiredModule $script:RequiredModules
    $script:StubDir = $script:Stub.Directory

    $script:Present = Invoke-ValidatorScript -Stub $script:Stub -Monitor 'present'
    $script:Gone    = Invoke-ValidatorScript -Stub $script:Stub -Monitor 'gone'
    $script:Denied  = Invoke-ValidatorScript -Stub $script:Stub -Monitor 'denied'
    $script:AllRuns = @($script:Present, $script:Gone, $script:Denied)
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
            ForEach-Object { $_.GetCommandName() } | Where-Object { $_ -match '^\w+-Az' -and $_ -ne 'Connect-AzAccount' } | Sort-Object -Unique
        @($called | Where-Object { $_ -notin $script:StubCommands }) | Should -BeNullOrEmpty
    }
}

Describe 'Lab 5.3 Test-Lab.ps1 - connection monitor lookup (#452)' {

    It 'passes the connection monitor checks when the region serves the version the script sends' {
        $script:Present.Exists | Should -Match 'PASS$' -Because "output was:`n$($script:Present.Output)"
        $script:Present.Status | Should -Match 'PASS$' -Because "output was:`n$($script:Present.Output)"
    }

    It 'fails a missing monitor as missing, without a provider error' {
        $script:Gone.Exists | Should -Match 'FAIL$' -Because "output was:`n$($script:Gone.Output)"
        $script:Gone.Exists | Should -Not -Match 'No registered resource provider'
    }
}

Describe 'Lab 5.3 Test-Lab.ps1 - a failed lookup is an error, not a missing monitor (#452)' {

    It 'fails the check and prints the error when ARM refuses the read' {
        $script:Denied.Exists | Should -Match 'FAIL \(.*AuthorizationFailed' -Because "output was:`n$($script:Denied.Output)"
    }

    It 'fails every connection monitor check that reads the monitor' {
        $script:Denied.Status | Should -Match 'FAIL \(.*AuthorizationFailed' -Because "output was:`n$($script:Denied.Output)"
    }

    It 'exits 1' {
        $script:Denied.ExitCode | Should -Be 1
    }

    It 'sends -ApiVersion with every Get-AzResource call in the script' {
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($script:ScriptPath, [ref]$null, [ref]$null)
        $calls = @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] -and $n.GetCommandName() -eq 'Get-AzResource' }, $true))
        $calls.Count | Should -BeGreaterThan 0
        foreach ($call in $calls) {
            @($call.CommandElements | Where-Object { $_ -is [System.Management.Automation.Language.CommandParameterAst] -and $_.ParameterName -eq 'ApiVersion' }) |
                Should -Not -BeNullOrEmpty -Because "line $($call.Extent.StartLineNumber): $($call.Extent.Text)"
        }
    }
}
