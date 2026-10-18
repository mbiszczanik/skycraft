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
      5. A rule whose actions differ from the guide fails: tier-game-logs saved with the Portal's
         first block at "Delete the blob" (logs deleted after 30 days), and archive-backups that
         deletes every backup after 7 days (#359). So does a disabled rule.
      6. A missing production container fails, and so does a storage account in the provisioning
         state Failed (#371).

    No subscription is needed, and none is used: tests/Support/LabScriptStub.psm1 (issue #112)
    imports the real modules first, the stub last, and aborts the child with exit 99 unless every
    stubbed command resolves to the stub.

.EXAMPLE
    Invoke-Pester -Path .\Test-Lab.Tests.ps1

.NOTES
    Project: SkyCraft
    Lab: 4.2 - Blob Storage
    Issue: #355, #356, #359, #371
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
    #   SKYCRAFT_STUB_LOGSACTIONS     the base blob actions of tier-game-logs, 'Action=days' by
    #                                 days since the last modification, comma-separated
    #   SKYCRAFT_STUB_BACKUPSACTIONS  the same for archive-backups
    #   SKYCRAFT_STUB_LOGSENABLED     'true' or 'false', the state of tier-game-logs
    #   SKYCRAFT_STUB_MISSING         a production container the listing leaves out, or ''
    #   SKYCRAFT_STUB_PRODSTATE       the production account's provisioning state
    #   SKYCRAFT_STUB_DEVSTATE        the dev account's provisioning state
    #   SKYCRAFT_STUB_PRODSOFTDELETE  'on' (7 days, blobs and containers) or 'off' (blobs off)
    $script:StubBody = @'
function Get-AzStorageAccount {
    [CmdletBinding()]
    param([string]$ResourceGroupName, [string]$Name, [Parameter(ValueFromRemainingArguments)]$Rest)
    [pscustomobject]@{
        StorageAccountName    = $Name
        ProvisioningState     = $(if ($Name -like 'prod*') { $env:SKYCRAFT_STUB_PRODSTATE } else { $env:SKYCRAFT_STUB_DEVSTATE })
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
        if ($n -ne $env:SKYCRAFT_STUB_MISSING) { [pscustomobject]@{ Name = $n; PublicAccess = 'Off' } }
    }
}

function Get-AzStorageAccountManagementPolicy {
    [CmdletBinding()]
    param([string]$ResourceGroupName, [string]$StorageAccountName, [Parameter(ValueFromRemainingArguments)]$Rest)
    function New-StubRule([string]$RuleName, [string]$Prefixes, [string]$Actions, [bool]$Enabled) {
        # The Portal's "Apply rule to all blobs" writes no prefixMatch: Az reads it as $null.
        $prefixMatch = if ($Prefixes -eq 'none') { $null } else { [string[]]($Prefixes -split ',') }
        # PSManagementPolicyBaseBlob: an action the rule does not have reads as $null.
        $baseBlob = [pscustomobject]@{ TierToHot = $null; TierToCool = $null; TierToCold = $null; TierToArchive = $null; Delete = $null }
        foreach ($pair in ($Actions -split ',' | Where-Object { $_ })) {
            # 'TierToArchive=180/7': 180 days since modification, rehydrated blobs skipped for 7 days.
            $action, $days = $pair -split '='
            $modified, $rehydrated = $days -split '/'
            $baseBlob.$action = [pscustomobject]@{
                DaysAfterModificationGreaterThan   = [int]$modified
                DaysAfterCreationGreaterThan       = $null
                DaysAfterLastAccessTimeGreaterThan = $null
                DaysAfterLastTierChangeGreaterThan = $(if ($rehydrated) { [int]$rehydrated } else { $null })
            }
        }
        [pscustomobject]@{
            Name       = $RuleName
            Enabled    = $Enabled
            Definition = [pscustomobject]@{
                Actions = [pscustomobject]@{ BaseBlob = $baseBlob }
                Filters = [pscustomobject]@{ BlobTypes = @('blockBlob'); PrefixMatch = $prefixMatch }
            }
        }
    }
    [pscustomobject]@{
        Rules = @(
            New-StubRule 'tier-game-logs' $env:SKYCRAFT_STUB_LOGSPREFIX $env:SKYCRAFT_STUB_LOGSACTIONS ($env:SKYCRAFT_STUB_LOGSENABLED -eq 'true')
            New-StubRule 'archive-backups' $env:SKYCRAFT_STUB_BACKUPSPREFIX $env:SKYCRAFT_STUB_BACKUPSACTIONS $true
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
            [string]$LogsActions = 'TierToCool=30,TierToCold=90,TierToArchive=180/7,Delete=365',
            [string]$BackupsActions = 'TierToArchive=7/7',
            [ValidateSet('true', 'false')]
            [string]$LogsEnabled = 'true',
            [string]$Missing = '',
            [string]$ProdState = 'Succeeded',
            [string]$DevState = 'Succeeded',
            [ValidateSet('on', 'off')]
            [string]$ProdSoftDelete = 'on'
        )
        $run = Invoke-LabScriptWithStub -Stub $Stub -ScriptPath $script:ScriptPath -Environment @{
            SKYCRAFT_STUB_DEVVERSIONING  = $DevVersioning
            SKYCRAFT_STUB_LOGSPREFIX     = $LogsPrefix
            SKYCRAFT_STUB_BACKUPSPREFIX  = $BackupsPrefix
            SKYCRAFT_STUB_LOGSACTIONS    = $LogsActions
            SKYCRAFT_STUB_BACKUPSACTIONS = $BackupsActions
            SKYCRAFT_STUB_LOGSENABLED    = $LogsEnabled
            SKYCRAFT_STUB_MISSING        = $Missing
            SKYCRAFT_STUB_PRODSTATE      = $ProdState
            SKYCRAFT_STUB_DEVSTATE       = $DevState
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
    # The Portal's first If/Then block left at its default, "Delete the blob" (#359).
    $script:LogsDeleteFirst  = Invoke-ValidatorScript -Stub $script:Stub -LogsActions 'TierToCold=90,TierToArchive=180/7,Delete=30'
    $script:BackupsDeleted   = Invoke-ValidatorScript -Stub $script:Stub -BackupsActions 'Delete=7'
    $script:LogsDisabled     = Invoke-ValidatorScript -Stub $script:Stub -LogsEnabled 'false'
    $script:ContainerMissing = Invoke-ValidatorScript -Stub $script:Stub -Missing 'server-config'
    $script:ProdFailed       = Invoke-ValidatorScript -Stub $script:Stub -ProdState 'Failed'
    $script:DevFailed        = Invoke-ValidatorScript -Stub $script:Stub -DevState 'Failed'
    # Step 4.2.9 saved with "Skip blobs that have been rehydrated in the last" unticked.
    $script:BackupsNoSkip    = Invoke-ValidatorScript -Stub $script:Stub -BackupsActions 'TierToArchive=7'
    $script:AllRuns        = @($script:PortalUnset, $script:BicepFalse, $script:TurnedOn, $script:ReadFails,
        $script:LogsUnfiltered, $script:LogsOutside, $script:LogsNarrower, $script:BackupsNone, $script:SoftDeleteOff,
        $script:LogsDeleteFirst, $script:BackupsDeleted, $script:LogsDisabled, $script:ContainerMissing, $script:ProdFailed,
        $script:DevFailed, $script:BackupsNoSkip)
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
        $run.Output | Should -Match 'Tests Passed: 27 / 27'
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
        $run.Output | Should -Match 'Tests Passed: 26 / 27'
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
        $run.Output | Should -Match 'Tests Passed: 26 / 27'
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

Describe 'Lab 4.2 Test-Lab.ps1 - each lifecycle rule does what the guide says (#359)' {

    It 'checks the actions of both rules in the full end state' {
        $run = $script:PortalUnset
        $run.Output | Should -Match "PROD: 'tier-game-logs' rule actions \.\.\. PASS \(TierToCool 30, TierToCold 90, TierToArchive 180 rehydrated 7, Delete 365\)"
        $run.Output | Should -Match "PROD: 'archive-backups' rule actions \.\.\. PASS \(TierToArchive 7 rehydrated 7\)"
    }

    It 'fails tier-game-logs saved with its first block at "Delete the blob", and exits 1' {
        $run = $script:LogsDeleteFirst
        $run.ExitCode | Should -Be 1 -Because "the rule deletes every log after 30 days; output was:`n$($run.Output)"
        $run.Output | Should -Match "PROD: 'tier-game-logs' rule actions \.\.\. FAIL \(Actions TierToCold 90, TierToArchive 180 rehydrated 7, Delete 30, expected TierToCool 30, TierToCold 90, TierToArchive 180 rehydrated 7, Delete 365\. The rule deletes blobs the guide keeps"
        $run.Output | Should -Match 'Tests Passed: 26 / 27'
    }

    It 'fails archive-backups that deletes every backup after 7 days, and exits 1' {
        $run = $script:BackupsDeleted
        $run.ExitCode | Should -Be 1 -Because "output was:`n$($run.Output)"
        $run.Output | Should -Match "PROD: 'archive-backups' rule actions \.\.\. FAIL \(Actions Delete 7, expected TierToArchive 7 rehydrated 7\. The rule deletes blobs the guide keeps"
    }

    It 'fails archive-backups saved without skipping rehydrated blobs, and exits 1' {
        $run = $script:BackupsNoSkip
        $run.ExitCode | Should -Be 1 -Because "a rehydrated backup would go back to Archive at once; output was:`n$($run.Output)"
        $run.Output | Should -Match "PROD: 'archive-backups' rule actions \.\.\. FAIL \(Actions TierToArchive 7, expected TierToArchive 7 rehydrated 7\)"
        $run.Output | Should -Match 'Tests Passed: 26 / 27'
    }

    It 'fails a disabled tier-game-logs rule, and exits 1' {
        $run = $script:LogsDisabled
        $run.ExitCode | Should -Be 1 -Because "output was:`n$($run.Output)"
        $run.Output | Should -Match "PROD: 'tier-game-logs' rule enabled \.\.\. FAIL \(Disabled\)"
        $run.Output | Should -Match 'Tests Passed: 26 / 27'
    }
}

Describe 'Lab 4.2 Test-Lab.ps1 - containers and provisioning state' {

    It 'fails a production container that is missing, and exits 1' {
        $run = $script:ContainerMissing
        $run.ExitCode | Should -Be 1 -Because "output was:`n$($run.Output)"
        $run.Output | Should -Match "PROD: 'server-config' container exists \.\.\. FAIL"
        $run.Output | Should -Match "PROD: 'game-assets' container exists \.\.\. PASS"
        $run.Output | Should -Match 'Tests Passed: 25 / 26'
    }

    It 'fails a storage account Azure left in the Failed state, and exits 1 (#371)' {
        $run = $script:ProdFailed
        $run.ExitCode | Should -Be 1 -Because "output was:`n$($run.Output)"
        $run.Output | Should -Match "PROD: Storage account provisioned \.\.\. FAIL \(Provisioning state 'Failed', expected Succeeded\)"
        $run.Output | Should -Match 'DEV: Storage account provisioned \.\.\. PASS \(Succeeded\)'
        $run.Output | Should -Match 'Tests Passed: 26 / 27'
    }

    It 'fails a dev storage account Azure left in the Failed state, and exits 1 (#371)' {
        $run = $script:DevFailed
        $run.ExitCode | Should -Be 1 -Because "output was:`n$($run.Output)"
        $run.Output | Should -Match "DEV: Storage account provisioned \.\.\. FAIL \(Provisioning state 'Failed', expected Succeeded\)"
        $run.Output | Should -Match 'PROD: Storage account provisioned \.\.\. PASS \(Succeeded\)'
        $run.Output | Should -Match 'Tests Passed: 26 / 27'
    }
}
