<#
.SYNOPSIS
    Pester 5 tests: the Lab 4.2 validator accepts what every path builds, reads unset dev
    versioning as the Portal default, and fails a lifecycle rule that is not limited to its prefix.

.DESCRIPTION
    Regression cover for issues #355 and #356. These tests run the real Test-Lab.ps1 in a child
    pwsh against a generated stub of the Az commands it calls, and assert that:

      1. Unset dev versioning ($null, the Portal path) and $false (the Bicep path) both pass, and
         exit 0 (#355). Versioning on fails, counted, and exits 1.
      2. A blob service read that fails is a failure that says why, not an "off".
      3. A 'tier-game-logs' rule without a prefix filter fails: it applies to every block blob in
         the account, and its delete action would remove game assets and player backups after
         365 days (#356). So does a rule with a prefix outside 'game-logs/', and an
         'archive-backups' rule without 'player-backups/'.
      4. Production soft delete that is off fails.

    No subscription is needed, and none is used: tests/Support/LabScriptStub.psm1 (issue #112)
    imports the real modules first, the stub last, and aborts the child with exit 99 unless every
    stubbed command resolves to the stub.

.EXAMPLE
    Invoke-Pester -Path .\Test-Lab.Tests.ps1

.NOTES
    Project: SkyCraft
    Lab: 4.2 - Blob Storage
    Issue: #355, #356
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

    # Both accounts as the guide leaves them; one property varies per scenario:
    #   SKYCRAFT_STUB_DEVVERSIONING   'null' (never set, the Portal path), 'false' (the Bicep
    #                                 path), 'true' (turned on), or 'fail' (the read fails)
    #   SKYCRAFT_STUB_LOGSPREFIX      the prefixes of tier-game-logs, comma-separated; 'none' for
    #                                 a rule without a prefix filter (the Portal's "Apply rule to
    #                                 all blobs in your storage account")
    #   SKYCRAFT_STUB_BACKUPSPREFIX   the same for archive-backups
    #   SKYCRAFT_STUB_PRODSOFTDELETE  'on' (7 days, blobs and containers) or 'off' (blobs off)
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
    if ($StorageAccountName -like 'prod*') {
        $blobOn = $env:SKYCRAFT_STUB_PRODSOFTDELETE -ne 'off'
        return [pscustomobject]@{
            IsVersioningEnabled            = $true
            DeleteRetentionPolicy          = [pscustomobject]@{ Enabled = $blobOn; Days = $(if ($blobOn) { 7 } else { $null }) }
            ContainerDeleteRetentionPolicy = [pscustomobject]@{ Enabled = $true; Days = 7 }
        }
    }
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
    function New-StubRule([string]$RuleName, [string]$Prefixes) {
        # The Portal's "Apply rule to all blobs" writes no prefixMatch: Az reads it as $null.
        $prefixMatch = if ($Prefixes -eq 'none') { $null } else { [string[]]($Prefixes -split ',') }
        [pscustomobject]@{
            Name       = $RuleName
            Enabled    = $true
            Definition = [pscustomobject]@{
                Filters = [pscustomobject]@{ BlobTypes = @('blockBlob'); PrefixMatch = $prefixMatch }
            }
        }
    }
    [pscustomobject]@{
        Rules = @(
            New-StubRule 'tier-game-logs' $env:SKYCRAFT_STUB_LOGSPREFIX
            New-StubRule 'archive-backups' $env:SKYCRAFT_STUB_BACKUPSPREFIX
        )
    }
}
'@

    function Invoke-ValidatorScript {
        param(
            [pscustomobject]$Stub,
            [ValidateSet('null', 'false', 'true', 'fail')]
            [string]$DevVersioning = 'null',
            [string]$LogsPrefix = 'game-logs/',
            [string]$BackupsPrefix = 'player-backups/',
            [ValidateSet('on', 'off')]
            [string]$ProdSoftDelete = 'on'
        )
        $run = Invoke-LabScriptWithStub -Stub $Stub -ScriptPath $script:ScriptPath -Environment @{
            SKYCRAFT_STUB_DEVVERSIONING  = $DevVersioning
            SKYCRAFT_STUB_LOGSPREFIX     = $LogsPrefix
            SKYCRAFT_STUB_BACKUPSPREFIX  = $BackupsPrefix
            SKYCRAFT_STUB_PRODSOFTDELETE = $ProdSoftDelete
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

    $script:PortalUnset    = Invoke-ValidatorScript -Stub $script:Stub -DevVersioning 'null'
    $script:BicepFalse     = Invoke-ValidatorScript -Stub $script:Stub -DevVersioning 'false'
    $script:TurnedOn       = Invoke-ValidatorScript -Stub $script:Stub -DevVersioning 'true'
    $script:ReadFails      = Invoke-ValidatorScript -Stub $script:Stub -DevVersioning 'fail'
    $script:LogsUnfiltered = Invoke-ValidatorScript -Stub $script:Stub -LogsPrefix 'none'
    $script:LogsOutside    = Invoke-ValidatorScript -Stub $script:Stub -LogsPrefix 'game-logs/,game-assets/'
    $script:LogsNarrower   = Invoke-ValidatorScript -Stub $script:Stub -LogsPrefix 'game-logs/server'
    $script:BackupsNone    = Invoke-ValidatorScript -Stub $script:Stub -BackupsPrefix 'none'
    $script:SoftDeleteOff  = Invoke-ValidatorScript -Stub $script:Stub -ProdSoftDelete 'off'
    $script:AllRuns        = @($script:PortalUnset, $script:BicepFalse, $script:TurnedOn, $script:ReadFails,
        $script:LogsUnfiltered, $script:LogsOutside, $script:LogsNarrower, $script:BackupsNone, $script:SoftDeleteOff)
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

Describe 'Lab 4.2 Test-Lab.ps1 - the state every path builds' {

    It 'passes the full end state and checks every container, soft delete and both rules' {
        $run = $script:PortalUnset
        $run.ExitCode | Should -Be 0 -Because "output was:`n$($run.Output)"
        $run.Output | Should -Match 'Tests Passed: 23 / 23'
        $run.Output | Should -Match 'SUCCESS: Lab 4.2 compliant!'
        foreach ($name in 'game-assets', 'player-backups', 'server-config', 'game-logs') {
            $run.Output | Should -Match "PROD: '$name' is PRIVATE \.\.\. PASS"
        }
        $run.Output | Should -Match 'PROD: Soft delete for blobs on, 7 days \.\.\. PASS'
        $run.Output | Should -Match 'PROD: Soft delete for containers on, 7 days \.\.\. PASS'
        $run.Output | Should -Match "PROD: 'tier-game-logs' rule limited to 'game-logs/' \.\.\. PASS \(Prefix game-logs/\)"
        $run.Output | Should -Match "PROD: 'archive-backups' rule limited to 'player-backups/' \.\.\. PASS \(Prefix player-backups/\)"
    }
}

Describe 'Lab 4.2 Test-Lab.ps1 - unset dev versioning is the Portal default, off (#355)' {

    It 'passes a dev account whose versioning the Portal never set' {
        $run = $script:PortalUnset
        $run.ExitCode | Should -Be 0 -Because "a learner who took the Portal path built what the guide asks for; output was:`n$($run.Output)"
        $run.Output | Should -Match 'DEV: Versioning disabled \(scope check\) \.\.\. PASS \(Versioning not set \(Portal default: off\)\)'
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
        $run.Output | Should -Match 'Tests Passed: 22 / 23'
    }

    It 'fails a blob service read that fails, says why, and still reaches the summary' {
        $run = $script:ReadFails
        $run.ExitCode | Should -Be 1 -Because "a read that failed is not an 'off'; output was:`n$($run.Output)"
        $run.Output | Should -Match 'DEV: Versioning disabled \(scope check\) \.\.\. FAIL \(Could not read the blob service: stub lookup failure'
        $run.Output | Should -Match 'Test Summary'
    }
}

Describe 'Lab 4.2 Test-Lab.ps1 - each lifecycle rule stays on its own container (#356)' {

    It 'fails tier-game-logs without a prefix filter, says it applies to every blob, and exits 1' {
        $run = $script:LogsUnfiltered
        $run.ExitCode | Should -Be 1 -Because "an unfiltered rule deletes every block blob in the account after 365 days; output was:`n$($run.Output)"
        $run.Output | Should -Match "PROD: 'tier-game-logs' rule limited to 'game-logs/' \.\.\. FAIL \(No prefix filter: the rule applies to every blob in the account"
        $run.Output | Should -Match 'Tests Passed: 22 / 23'
    }

    It 'fails tier-game-logs with a prefix outside game-logs/, and names it' {
        $run = $script:LogsOutside
        $run.ExitCode | Should -Be 1 -Because "output was:`n$($run.Output)"
        $run.Output | Should -Match "PROD: 'tier-game-logs' rule limited to 'game-logs/' \.\.\. FAIL \(Prefix filter game-assets/ reaches outside 'game-logs/'\)"
    }

    It 'passes tier-game-logs with a narrower prefix inside game-logs/' {
        $run = $script:LogsNarrower
        $run.ExitCode | Should -Be 0 -Because "a prefix inside the container still keeps the rule there; output was:`n$($run.Output)"
    }

    It 'fails archive-backups without a prefix filter' {
        $run = $script:BackupsNone
        $run.ExitCode | Should -Be 1 -Because "output was:`n$($run.Output)"
        $run.Output | Should -Match "PROD: 'archive-backups' rule limited to 'player-backups/' \.\.\. FAIL \(No prefix filter"
    }
}

Describe 'Lab 4.2 Test-Lab.ps1 - production soft delete' {

    It 'fails blob soft delete that is off, and exits 1' {
        $run = $script:SoftDeleteOff
        $run.ExitCode | Should -Be 1 -Because "output was:`n$($run.Output)"
        $run.Output | Should -Match 'PROD: Soft delete for blobs on, 7 days \.\.\. FAIL \(Off\)'
        $run.Output | Should -Match 'PROD: Soft delete for containers on, 7 days \.\.\. PASS'
    }
}
