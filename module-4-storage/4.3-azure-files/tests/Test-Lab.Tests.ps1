<#
.SYNOPSIS
    Pester 5 tests: the Lab 4.3 validator passes the state every path of the guide leaves and
    reports each broken setting, and each failed lookup, as a counted failure.

.DESCRIPTION
    Regression cover for issue #360 (the Lab 4.3 guide PR of #329) and for the Test-Lab
    requirements of #329: find resources by relation (#355), fail a resource in a Failed state
    (#371), read a property the Portal leaves unset as its default and count a failed lookup
    (docs/powershell-standards.md section 4, rule 7), and exit non-zero on any failure. These
    tests run the real Test-Lab.ps1 in a child pwsh against a generated stub of the Az commands it
    calls, and assert that:

      1. The two shares as the guide leaves them (Hot, 100 and 500 GiB, 14-day soft delete, no
         backup) pass, and the script exits 0. So does a share that a vault backs up on another
         storage account.
      2. A share left on the Portal's default tier fails its tier check, counted, with the
         Change tier hint; so does a share whose tier the API leaves unset, read as
         TransactionOptimized, Azure's default.
      3. A share that a Recovery Services vault protects fails, counted, whether the vault's item
         names the account by its source resource id or by its container (#360: the Portal's
         Backup tab is ticked by default).
      4. Soft delete under 14 days, a wrong quota, a missing share and an unexpected share fail,
         one counted failure each.
      5. An account in a Failed provisioning state fails, counted (#371).
      6. A lookup that fails - the account, the file service, the share listing, the vault
         listing, a vault's backup items - is a counted [FAIL] that prints its error, and the
         script still reaches its summary and exits 1.

    No subscription is needed, and none is used: tests/Support/LabScriptStub.psm1 (issue #112)
    imports the real modules first, the stub last, and aborts the child with exit 99 unless every
    stubbed command resolves to the stub.

.EXAMPLE
    Invoke-Pester -Path .\Test-Lab.Tests.ps1

.NOTES
    Project: SkyCraft
    Lab: 4.3 - Azure Files
    Issue: #355, #360, #371
#>

#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..' '..' '..' 'tests' 'Support' 'LabScriptStub.psm1') -Force

    $script:ScriptPath     = (Resolve-Path (Join-Path $PSScriptRoot '..' 'scripts' 'Test-Lab.ps1')).Path
    $script:StubModuleName = 'SkyCraftLab43ValidatorStub'
    # Exactly the script's '#Requires -Modules' line.
    $script:RequiredModules = @('Az.Accounts', 'Az.Resources', 'Az.Storage', 'Az.RecoveryServices')

    $script:StubCommands = @(
        'Get-AzContext'
        'Get-AzStorageAccount'
        'Get-AzStorageFileServiceProperty'
        'Get-AzRmStorageShare'
        'Get-AzResource'
        'Get-AzRecoveryServicesBackupItem'
    )

    # One generated module serves every scenario; environment variables change what it returns:
    #   SKYCRAFT_STUB_FAIL      lookups that throw: account, fileprops, shares, vaults, items
    #   SKYCRAFT_STUB_STATE     the account's provisioning state (default Succeeded)
    #   SKYCRAFT_STUB_DAYS      share soft delete retention in days (default 14)
    #   SKYCRAFT_STUB_SHARES    the share names listed (default skycraft-config,skycraft-shared)
    #   SKYCRAFT_STUB_TIER      '<share>=<tier>' pairs; an empty tier is an unset (null) one
    #   SKYCRAFT_STUB_QUOTA     '<share>=<GiB>' pairs
    #   SKYCRAFT_STUB_BACKUP    what the vault backs up: 'own-source' (skycraft-config, named by
    #                           source resource id), 'own-container' (skycraft-shared, named by
    #                           container only), 'other' (a share of another account)
    $script:StubBody = @'
$script:AccountId = '/subscriptions/sub-stub/resourceGroups/prod-skycraft-swc-rg/providers/Microsoft.Storage/storageAccounts/prodskycraftswcsa'

function Test-StubFails {
    param([string]$Lookup)
    @($env:SKYCRAFT_STUB_FAIL -split ',') -contains $Lookup
}

function Get-StubPair {
    param([string]$Variable, [string]$Key)
    foreach ($pair in @([Environment]::GetEnvironmentVariable($Variable) -split ',')) {
        $parts = $pair -split '=', 2
        if ($parts.Count -eq 2 -and $parts[0] -eq $Key) { return [pscustomobject]@{ Value = $parts[1] } }
    }
    return $null
}

function Get-AzContext {
    [CmdletBinding()]
    param([Parameter(ValueFromRemainingArguments)]$Rest)
    [pscustomobject]@{ Name = 'stub-context' }
}

function Get-AzStorageAccount {
    [CmdletBinding()]
    param([string]$ResourceGroupName, [string]$Name, [Parameter(ValueFromRemainingArguments)]$Rest)
    if (Test-StubFails 'account') { throw "Operation returned an invalid status code 'Forbidden'" }
    $state = if ($env:SKYCRAFT_STUB_STATE) { $env:SKYCRAFT_STUB_STATE } else { 'Succeeded' }
    [pscustomobject]@{
        StorageAccountName = $Name
        Id                 = $script:AccountId
        ProvisioningState  = $state
        Sku                = [pscustomobject]@{ Name = 'Standard_GRS' }
    }
}

function Get-AzStorageFileServiceProperty {
    [CmdletBinding()]
    param([string]$ResourceGroupName, [string]$StorageAccountName, [Parameter(ValueFromRemainingArguments)]$Rest)
    if (Test-StubFails 'fileprops') { throw "Operation returned an invalid status code 'Forbidden'" }
    $days = if ($env:SKYCRAFT_STUB_DAYS) { [int]$env:SKYCRAFT_STUB_DAYS } else { 14 }
    [pscustomobject]@{ ShareDeleteRetentionPolicy = [pscustomobject]@{ Enabled = $true; Days = $days } }
}

function Get-AzRmStorageShare {
    [CmdletBinding()]
    param([string]$ResourceGroupName, [string]$StorageAccountName, [Parameter(ValueFromRemainingArguments)]$Rest)
    if (Test-StubFails 'shares') { throw "Operation returned an invalid status code 'TooManyRequests'" }
    $names = if ($env:SKYCRAFT_STUB_SHARES) { $env:SKYCRAFT_STUB_SHARES -split ',' } else { @('skycraft-config', 'skycraft-shared') }
    foreach ($name in $names) {
        $tierPair  = Get-StubPair 'SKYCRAFT_STUB_TIER' $name
        $quotaPair = Get-StubPair 'SKYCRAFT_STUB_QUOTA' $name
        $tier  = if ($tierPair) { if ($tierPair.Value) { $tierPair.Value } else { $null } } else { 'Hot' }
        $quota = if ($quotaPair) { [int]$quotaPair.Value } else { @{ 'skycraft-config' = 100; 'skycraft-shared' = 500 }[$name] }
        [pscustomobject]@{ Name = $name; QuotaGiB = $quota; AccessTier = $tier }
    }
}

function Get-AzResource {
    [CmdletBinding()]
    param([string]$ResourceType, [Parameter(ValueFromRemainingArguments)]$Rest)
    if (Test-StubFails 'vaults') { throw "Operation returned an invalid status code 'Forbidden'" }
    [pscustomobject]@{
        Name       = 'platform-skycraft-swc-rsv'
        ResourceId = '/subscriptions/sub-stub/resourceGroups/platform-skycraft-swc-rg/providers/Microsoft.RecoveryServices/vaults/platform-skycraft-swc-rsv'
    }
}

function Get-AzRecoveryServicesBackupItem {
    [CmdletBinding()]
    param([string]$BackupManagementType, [string]$WorkloadType, [string]$VaultId, [Parameter(ValueFromRemainingArguments)]$Rest)
    if (Test-StubFails 'items') { throw "Operation returned an invalid status code 'InternalServerError'" }
    switch ($env:SKYCRAFT_STUB_BACKUP) {
        'own-source' {
            [pscustomobject]@{
                Name             = 'AzureFileShare;skycraft-config'
                FriendlyName     = 'skycraft-config'
                ContainerName    = ''
                SourceResourceId = $script:AccountId.ToUpperInvariant()
            }
        }
        'own-container' {
            [pscustomobject]@{
                Name          = 'AzureFileShare;skycraft-shared'
                ContainerName = 'storage;PROD-SKYCRAFT-SWC-RG;prodskycraftswcsa'
            }
        }
        'other' {
            [pscustomobject]@{
                Name             = 'AzureFileShare;other-share'
                FriendlyName     = 'other-share'
                ContainerName    = 'storage;dev-skycraft-swc-rg;devskycraftswcsa'
                SourceResourceId = '/subscriptions/sub-stub/resourceGroups/dev-skycraft-swc-rg/providers/Microsoft.Storage/storageAccounts/devskycraftswcsa'
            }
        }
    }
}
'@

    function Invoke-ValidatorScript {
        param(
            [pscustomobject]$Stub,
            [string]$Fail = '',
            [string]$State = '',
            [string]$Days = '',
            [string]$Shares = '',
            [string]$Tier = '',
            [string]$Quota = '',
            [string]$Backup = ''
        )
        $run = Invoke-LabScriptWithStub -Stub $Stub -ScriptPath $script:ScriptPath -Environment @{
            SKYCRAFT_STUB_FAIL   = $Fail
            SKYCRAFT_STUB_STATE  = $State
            SKYCRAFT_STUB_DAYS   = $Days
            SKYCRAFT_STUB_SHARES = $Shares
            SKYCRAFT_STUB_TIER   = $Tier
            SKYCRAFT_STUB_QUOTA  = $Quota
            SKYCRAFT_STUB_BACKUP = $Backup
        }
        return [pscustomobject]@{
            ExitCode  = $run.ExitCode
            Refused   = $run.Refused
            Output    = $run.Output
            FailLines = ([regex]::Matches($run.Output, '\[FAIL\]')).Count
        }
    }

    $script:Stub    = Initialize-LabScriptStub -Name $script:StubModuleName -Command $script:StubCommands `
        -Body $script:StubBody -RequiredModule $script:RequiredModules
    $script:StubDir = $script:Stub.Directory

    $script:AsGuided         = Invoke-ValidatorScript -Stub $script:Stub
    $script:OtherBackup      = Invoke-ValidatorScript -Stub $script:Stub -Backup 'other'
    $script:DefaultTier      = Invoke-ValidatorScript -Stub $script:Stub -Tier 'skycraft-config=TransactionOptimized'
    $script:UnsetTier        = Invoke-ValidatorScript -Stub $script:Stub -Tier 'skycraft-shared='
    $script:BackupBySource   = Invoke-ValidatorScript -Stub $script:Stub -Backup 'own-source'
    $script:BackupByContainer = Invoke-ValidatorScript -Stub $script:Stub -Backup 'own-container'
    $script:ShortSoftDelete  = Invoke-ValidatorScript -Stub $script:Stub -Days '7'
    $script:WrongQuota       = Invoke-ValidatorScript -Stub $script:Stub -Quota 'skycraft-shared=102400'
    $script:StrayShare       = Invoke-ValidatorScript -Stub $script:Stub -Shares 'skycraft-config,scratch'
    $script:FailedAccount    = Invoke-ValidatorScript -Stub $script:Stub -State 'Failed'
    $script:AccountFails     = Invoke-ValidatorScript -Stub $script:Stub -Fail 'account'
    $script:LookupsFail      = Invoke-ValidatorScript -Stub $script:Stub -Fail 'fileprops,shares,items'
    $script:VaultsFail       = Invoke-ValidatorScript -Stub $script:Stub -Fail 'vaults'
    $script:AllRuns = @($script:AsGuided, $script:OtherBackup, $script:DefaultTier, $script:UnsetTier,
        $script:BackupBySource, $script:BackupByContainer, $script:ShortSoftDelete, $script:WrongQuota,
        $script:StrayShare, $script:FailedAccount, $script:AccountFails, $script:LookupsFail, $script:VaultsFail)
}

AfterAll {
    if ($script:StubDir) { Remove-Item -LiteralPath $script:StubDir -Recurse -Force -ErrorAction SilentlyContinue }
}

Describe 'Lab 4.3 Test-Lab.ps1 - test harness' {

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

Describe 'Lab 4.3 Test-Lab.ps1 - the state every path of the guide leaves passes' {

    It 'passes the two shares as the guide leaves them, and exits 0' {
        $run = $script:AsGuided
        $run.ExitCode | Should -Be 0 -Because "output was:`n$($run.Output)"
        $run.FailLines | Should -Be 0
        $run.Output | Should -Match "\[PASS\] File share 'skycraft-config' access tier is Hot"
        $run.Output | Should -Match '\[PASS\] No Azure Backup protects a file share of the account'
        $run.Output | Should -Match 'Validation Complete\. Failures: 0'
    }

    It 'passes when a vault backs up a share of another storage account' {
        $run = $script:OtherBackup
        $run.ExitCode | Should -Be 0 -Because "output was:`n$($run.Output)"
        $run.FailLines | Should -Be 0
    }
}

Describe 'Lab 4.3 Test-Lab.ps1 - the Portal defaults the guide names (#360)' {

    It 'fails, counted, a share left on the Portal''s default tier and names Change tier' {
        $run = $script:DefaultTier
        $run.ExitCode | Should -Be 1 -Because "output was:`n$($run.Output)"
        $run.Output | Should -Match "\[FAIL\] File share 'skycraft-config' access tier is Hot - Actual: TransactionOptimized"
        $run.Output | Should -Match 'Change tier'
        $run.FailLines | Should -Be 1
        $run.Output | Should -Match 'Validation Complete\. Failures: 1'
    }

    It 'reads an unset tier as TransactionOptimized, Azure''s default, and fails it, counted' {
        $run = $script:UnsetTier
        $run.ExitCode | Should -Be 1 -Because "output was:`n$($run.Output)"
        $run.Output | Should -Match "\[FAIL\] File share 'skycraft-shared' access tier is Hot - Actual: TransactionOptimized"
        $run.FailLines | Should -Be 1
    }

    It 'fails, counted, a share a vault protects when the item names the account by its source resource id' {
        $run = $script:BackupBySource
        $run.ExitCode | Should -Be 1 -Because "output was:`n$($run.Output)"
        $run.Output | Should -Match '\[FAIL\] No Azure Backup protects a file share of the account'
        $run.Output | Should -Match "'skycraft-config' in vault 'platform-skycraft-swc-rsv'"
        $run.Output | Should -Match 'Issue 6'
        $run.FailLines | Should -Be 1
    }

    It 'fails, counted, a share a vault protects when the item names the account by its container only' {
        $run = $script:BackupByContainer
        $run.ExitCode | Should -Be 1 -Because "output was:`n$($run.Output)"
        $run.Output | Should -Match "'AzureFileShare;skycraft-shared' in vault 'platform-skycraft-swc-rsv'"
        $run.FailLines | Should -Be 1
    }
}

Describe 'Lab 4.3 Test-Lab.ps1 - a broken lab fails, one counted failure per broken setting' {

    It 'fails share soft delete under 14 days' {
        $run = $script:ShortSoftDelete
        $run.ExitCode | Should -Be 1 -Because "output was:`n$($run.Output)"
        $run.Output | Should -Match '\[FAIL\] File share soft delete enabled for at least 14 days - Actual: Enabled True, Days 7'
        $run.FailLines | Should -Be 1
    }

    It 'fails a share left at the default quota' {
        $run = $script:WrongQuota
        $run.ExitCode | Should -Be 1 -Because "output was:`n$($run.Output)"
        $run.Output | Should -Match "\[FAIL\] File share 'skycraft-shared' quota is 500 GiB - Actual: 102400 GiB"
        $run.FailLines | Should -Be 1
    }

    It 'fails a missing share and an unexpected one' {
        $run = $script:StrayShare
        $run.ExitCode | Should -Be 1 -Because "output was:`n$($run.Output)"
        $run.Output | Should -Match "\[FAIL\] File share 'skycraft-shared' exists - not found"
        $run.Output | Should -Match "Unexpected: 'scratch'"
        $run.FailLines | Should -Be 2
    }

    It 'fails an account in a Failed provisioning state (#371)' {
        $run = $script:FailedAccount
        $run.ExitCode | Should -Be 1 -Because "output was:`n$($run.Output)"
        $run.Output | Should -Match '\[FAIL\] Provisioning state is Succeeded - Actual: Failed'
        $run.FailLines | Should -Be 1
    }
}

Describe 'Lab 4.3 Test-Lab.ps1 - a failed lookup is a counted failure, never a pass or a crash' {

    It 'fails an account it cannot read, prints the error, and still reaches the summary' {
        $run = $script:AccountFails
        $run.ExitCode | Should -Be 1 -Because "output was:`n$($run.Output)"
        $run.Output | Should -Match "\[FAIL\] Storage account 'prodskycraftswcsa' readable - .*invalid status code 'Forbidden'"
        $run.Output | Should -Match 'Validation Complete\. Failures: 1'
        $run.FailLines | Should -Be 1
    }

    It 'counts a failed file service, share listing and backup item lookup, each with its error' {
        $run = $script:LookupsFail
        $run.ExitCode | Should -Be 1 -Because "output was:`n$($run.Output)"
        $run.Output | Should -Match "\[FAIL\] File service properties readable - .*'Forbidden'"
        $run.Output | Should -Match "\[FAIL\] File shares listable - .*'TooManyRequests'"
        $run.Output | Should -Match "\[FAIL\] Azure Files backup items of vault 'platform-skycraft-swc-rsv' readable - .*'InternalServerError'"
        $run.Output | Should -Not -Match 'Cannot index into a null array'
        $run.FailLines | Should -Be 3
        $run.Output | Should -Match 'Validation Complete\. Failures: 3'
    }

    It 'counts a vault listing that fails, with its error, instead of reading it as "no backup"' {
        $run = $script:VaultsFail
        $run.ExitCode | Should -Be 1 -Because "output was:`n$($run.Output)"
        $run.Output | Should -Match "\[FAIL\] Recovery Services vaults listable - .*'Forbidden'"
        $run.Output | Should -Not -Match '\[PASS\] No Azure Backup protects'
        $run.FailLines | Should -Be 1
    }
}
