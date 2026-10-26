<#
.SYNOPSIS
    Pester 5 tests: the Lab 4.2 validator reads unset dev versioning as the Portal default, off.

.DESCRIPTION
    Regression cover for issue #355. Test-Lab.ps1 required the dev account's
    IsVersioningEnabled to equal $false. The Bicep writes $false, but a dev account created in
    the Portal never sets the property, so it reads $null and a learner who followed every step
    failed "DEV: Versioning disabled" (10/11, exit 1). These tests run the real Test-Lab.ps1 in a
    child pwsh against a generated stub of the Az commands it calls, and assert that:

      1. Unset ($null, the Portal path) and $false (the Bicep path) both pass, and exit 0.
      2. Versioning on fails, counted, and exits 1.
      3. A blob service read that fails is a failure that says why, not an "off".

    No subscription is needed, and none is used: tests/Support/LabScriptStub.psm1 (issue #112)
    imports the real modules first, the stub last, and aborts the child with exit 99 unless every
    stubbed command resolves to the stub.

.EXAMPLE
    Invoke-Pester -Path .\Test-Lab.Tests.ps1

.NOTES
    Project: SkyCraft
    Lab: 4.2 - Blob Storage
    Issue: #355
#>

#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..' '..' '..' 'tests' 'Support' 'LabScriptStub.psm1') -Force

    $script:ScriptPath     = (Resolve-Path (Join-Path $PSScriptRoot '..' 'scripts' 'Test-Lab.ps1')).Path
    $script:StubModuleName = 'SkyCraftLab42ValidatorStub'
    # Exactly the script's '#Requires -Modules' line.
    $script:RequiredModules = @('Az.Accounts', 'Az.Storage')

    $script:StubCommands = @(
        'Get-AzStorageAccount'
        'Get-AzStorageBlobServiceProperty'
        'Get-AzStorageContainer'
        'Get-AzStorageAccountManagementPolicy'
    )

    # Both accounts as the guide leaves them; only the dev blob service's versioning varies:
    #   SKYCRAFT_STUB_DEVVERSIONING   'null' (never set, the Portal path), 'false' (the Bicep
    #                                 path), 'true' (turned on), or 'fail' (the read fails)
    $script:StubBody = @'
function Get-AzStorageAccount {
    [CmdletBinding()]
    param([string]$ResourceGroupName, [string]$Name, [Parameter(ValueFromRemainingArguments)]$Rest)
    [pscustomobject]@{
        StorageAccountName    = $Name
        AllowBlobPublicAccess = $false
        Context               = [pscustomobject]@{ StorageAccountName = $Name }
    }
}

function Get-AzStorageBlobServiceProperty {
    [CmdletBinding()]
    param([string]$ResourceGroupName, [string]$StorageAccountName, [Parameter(ValueFromRemainingArguments)]$Rest)
    if ($StorageAccountName -like 'prod*') { return [pscustomobject]@{ IsVersioningEnabled = $true } }
    switch ($env:SKYCRAFT_STUB_DEVVERSIONING) {
        'null'  { return [pscustomobject]@{ IsVersioningEnabled = $null } }
        'false' { return [pscustomobject]@{ IsVersioningEnabled = $false } }
        'true'  { return [pscustomobject]@{ IsVersioningEnabled = $true } }
        'fail'  { Write-Error "stub lookup failure: Get-AzStorageBlobServiceProperty ($StorageAccountName)"; return }
    }
}

function Get-AzStorageContainer {
    [CmdletBinding()]
    param($Context, [string]$Name, [Parameter(ValueFromRemainingArguments)]$Rest)
    if ($Name) { return [pscustomobject]@{ Name = $Name; PublicAccess = 'Off' } }
    foreach ($n in 'game-assets', 'player-backups', 'server-config', 'game-logs') {
        [pscustomobject]@{ Name = $n; PublicAccess = 'Off' }
    }
}

function Get-AzStorageAccountManagementPolicy {
    [CmdletBinding()]
    param([string]$ResourceGroupName, [string]$StorageAccountName, [Parameter(ValueFromRemainingArguments)]$Rest)
    [pscustomobject]@{ Rules = @([pscustomobject]@{ Name = 'tier-game-logs' }, [pscustomobject]@{ Name = 'archive-backups' }) }
}
'@

    function Invoke-ValidatorScript {
        param(
            [pscustomobject]$Stub,
            [ValidateSet('null', 'false', 'true', 'fail')]
            [string]$DevVersioning
        )
        $run = Invoke-LabScriptWithStub -Stub $Stub -ScriptPath $script:ScriptPath -Environment @{
            SKYCRAFT_STUB_DEVVERSIONING = $DevVersioning
        }
        return [pscustomobject]@{
            ExitCode = $run.ExitCode
            Refused  = $run.Refused
            Output   = $run.Output
        }
    }

    $script:Stub    = Initialize-LabScriptStub -Name $script:StubModuleName -Command $script:StubCommands `
        -Body $script:StubBody -RequiredModule $script:RequiredModules
    $script:StubDir = $script:Stub.Directory

    $script:PortalUnset = Invoke-ValidatorScript -Stub $script:Stub -DevVersioning 'null'
    $script:BicepFalse  = Invoke-ValidatorScript -Stub $script:Stub -DevVersioning 'false'
    $script:TurnedOn    = Invoke-ValidatorScript -Stub $script:Stub -DevVersioning 'true'
    $script:ReadFails   = Invoke-ValidatorScript -Stub $script:Stub -DevVersioning 'fail'
    $script:AllRuns     = @($script:PortalUnset, $script:BicepFalse, $script:TurnedOn, $script:ReadFails)
}

AfterAll {
    if ($script:StubDir) { Remove-Item -LiteralPath $script:StubDir -Recurse -Force -ErrorAction SilentlyContinue }
}

Describe 'Lab 4.2 Test-Lab.ps1 - test harness' {

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

Describe 'Lab 4.2 Test-Lab.ps1 - unset dev versioning is the Portal default, off (#355)' {

    It 'passes a dev account whose versioning the Portal never set' {
        $run = $script:PortalUnset
        $run.ExitCode | Should -Be 0 -Because "a learner who took the Portal path built what the guide asks for; output was:`n$($run.Output)"
        $run.Output | Should -Match 'DEV: Versioning disabled \(scope check\) \.\.\. PASS \(Versioning not set \(Portal default: off\)\)'
        $run.Output | Should -Match 'Tests Passed: 11 / 11'
    }

    It 'passes a dev account whose versioning the Bicep set to false' {
        $run = $script:BicepFalse
        $run.ExitCode | Should -Be 0 -Because "output was:`n$($run.Output)"
        $run.Output | Should -Match 'DEV: Versioning disabled \(scope check\) \.\.\. PASS \(Versioning OFF\)'
    }

    It 'fails a dev account with versioning on, and exits 1' {
        $run = $script:TurnedOn
        $run.ExitCode | Should -Be 1 -Because "output was:`n$($run.Output)"
        $run.Output | Should -Match 'DEV: Versioning disabled \(scope check\) \.\.\. FAIL \(Versioning ON\)'
        $run.Output | Should -Match 'Tests Passed: 10 / 11'
    }

    It 'fails a blob service read that fails, says why, and still reaches the summary' {
        $run = $script:ReadFails
        $run.ExitCode | Should -Be 1 -Because "a read that failed is not an 'off'; output was:`n$($run.Output)"
        $run.Output | Should -Match 'DEV: Versioning disabled \(scope check\) \.\.\. FAIL \(Could not read the blob service: stub lookup failure'
        $run.Output | Should -Match 'Test Summary'
    }
}
