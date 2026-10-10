<#
.SYNOPSIS
    Pester 5 tests for the Lab 4.2 cleanup: when it reports an object absent, and when it exits 1.

.DESCRIPTION
    Regression cover for issue #290. The cleanup looked the containers and the lifecycle policy up
    with -ErrorAction SilentlyContinue, so a lookup that failed (a 403, throttling) read as "not
    there", and it caught every error per environment, printed it and still exited 0 - one failed
    step also skipped the rest of that environment. These tests run the real
    Remove-LabResource.ps1 in a child pwsh process against a generated stub of the Az commands it
    calls, and assert the observable contract:

      1. Everything the lab creates is removed or reverted when it is present, and the run exits 0.
      2. An object that is absent - an empty listing, or a getter that reports it not found - is
         not a failure: the run exits 0.
      3. A lookup that fails with an error is an [ERROR], counted, and the run exits 1 without
         touching or reporting absent the object it could not see. The stub reports the failure
         with Write-Error, as the Az getters do, so a script that passes -ErrorAction
         SilentlyContinue swallows it.
      4. A step that fails is an [ERROR], counted, and the later steps still run: exit 1.

    Which errors mean "not found" is pinned for every cleanup that carries the helpers by
    tests/Lab-Cleanup-Lookup.Tests.ps1.

    Scope limit, as in the Lab 5.2 suite: the child is launched with -Command, so these tests
    prove the failure counter reaches `exit`, not that `pwsh -File` carries the code out of the
    process. That half is issue #104's guard, enforced by tests/Exit-Code-Propagation.Tests.ps1.

    No subscription is needed, and none is used. The script runs through
    tests/Support/LabScriptStub.psm1 (issue #112), which aborts the child with exit 99 unless every
    stubbed command resolves to the stub.

.EXAMPLE
    Invoke-Pester -Path .\Remove-LabResource.Tests.ps1

.NOTES
    Project: SkyCraft
    Lab: 4.2 - Blob Storage
#>

#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..' '..' '..' 'tests' 'Support' 'LabScriptStub.psm1') -Force

    $script:ScriptPath     = (Resolve-Path (Join-Path $PSScriptRoot '..' 'scripts' 'Remove-LabResource.ps1')).Path
    $script:StubModuleName = 'SkyCraftLab42CleanupStub'
    # Exactly the script's '#Requires -Modules' line: these are imported for real before the stub.
    $script:RequiredModules = @('Az.Accounts', 'Az.Storage')

    $script:StubCommands = @(
        'Get-AzStorageAccount'
        'Get-AzStorageContainer'
        'Remove-AzStorageContainer'
        'Get-AzStorageAccountManagementPolicy'
        'Remove-AzStorageAccountManagementPolicy'
        'Update-AzStorageBlobServiceProperty'
        'Set-AzStorageAccount'
    )

    # Every command the script calls, recording its own invocation. By default both accounts
    # exist: prod holds the four lab containers, an unrelated one and a lifecycle policy; dev holds
    # public-demo. Environment variables change that, so one generated module serves every
    # scenario:
    #   SKYCRAFT_STUB_EMPTY   '1' leaves nothing to find: Get-AzStorageAccount reports
    #                         ResourceNotFound, as the real one does for a name that does not exist
    #   SKYCRAFT_STUB_LOOKUP  '<lookup>=<kind>,...' makes one lookup fail (denied, throttled) or
    #                         report its object not found (notfound)
    #   SKYCRAFT_STUB_FAIL    '<command>:<name>,...' makes one removal or update throw
    # A lookup is named after its command and the object it reads: 'Get-AzStorageAccount:<sa>',
    # 'Get-AzStorageContainer:<sa>', 'Get-AzStorageAccountManagementPolicy:<sa>'.
    $script:StubBody = @'
$script:LogPath = $env:SKYCRAFT_STUB_LOG

function Write-StubCall {
    param([string]$Name)
    if ($script:LogPath) { Add-Content -LiteralPath $script:LogPath -Value $Name }
}

function Test-StubEmpty { return $env:SKYCRAFT_STUB_EMPTY -eq '1' }

function Invoke-StubRemoval {
    param([string]$Command, [string]$Name)
    Write-StubCall -Name $Command
    Write-StubCall -Name "${Command}:$Name"
    if (@($env:SKYCRAFT_STUB_FAIL -split ',') -contains "${Command}:$Name") { throw "stub failure: ${Command} $Name" }
}

# How the lookup named here fails, if at all. The failure is reported with Write-Error, as the
# Az getters do, so the caller's -ErrorAction decides what happens to it. Returns $true when the
# lookup failed, so the stub returns nothing after it. -Named lookups report a missing object as
# ResourceNotFound when the stub is empty.
function Invoke-StubLookup {
    param([string]$Name, [string]$ResourceGroup, [switch]$Named)
    Write-StubCall -Name $Name
    $kind = foreach ($entry in @($env:SKYCRAFT_STUB_LOOKUP -split ',')) {
        $key, $value = $entry -split '=', 2
        if ($key -eq $Name) { $value }
    }
    if (-not $kind -and $Named -and (Test-StubEmpty)) { $kind = 'notfound' }
    switch ($kind) {
        'denied' {
            Write-Error -ErrorId 'AuthorizationFailed' -Message "The client 'stub' does not have authorization to perform action 'read' over scope '$Name' or the scope is invalid."
            return $true
        }
        'throttled' {
            Write-Error -ErrorId 'TooManyRequests' -Message "Number of 'read' requests exceeded the limit for $Name. Please try again after '17' seconds."
            return $true
        }
        'notfound' {
            Write-Error -ErrorId 'ResourceNotFound' -Message "The Resource 'Microsoft.Storage/stubs/$(($Name -split ':')[-1])' under resource group '$ResourceGroup' was not found. For more details please go to https://aka.ms/ARMResourceNotFoundFix"
            return $true
        }
    }
    return $false
}

function Get-AzStorageAccount {
    [CmdletBinding()]
    param([string]$ResourceGroupName, [string]$Name)
    if (Invoke-StubLookup -Name "Get-AzStorageAccount:$Name" -ResourceGroup $ResourceGroupName -Named) { return }
    # The context only has to identify the account to the data-plane stubs below.
    [pscustomobject]@{ StorageAccountName = $Name; Context = "ctx:$Name" }
}

function Get-AzStorageContainer {
    [CmdletBinding()]
    param([object]$Context, [string]$Name)
    $account = ([string]$Context) -replace '^ctx:', ''
    if (Invoke-StubLookup -Name "Get-AzStorageContainer:$account") { return }
    $names = if ($account -eq 'prodskycraftswcsa') { 'game-assets', 'player-backups', 'server-config', 'game-logs', 'unrelated' } else { 'public-demo', 'unrelated' }
    foreach ($n in $names) { [pscustomobject]@{ Name = $n } }
}

function Remove-AzStorageContainer {
    [CmdletBinding()]
    param([object]$Context, [string]$Name, [switch]$Force)
    Invoke-StubRemoval -Command 'Remove-AzStorageContainer' -Name $Name
}

function Get-AzStorageAccountManagementPolicy {
    [CmdletBinding()]
    param([string]$ResourceGroupName, [string]$StorageAccountName)
    if (Invoke-StubLookup -Name "Get-AzStorageAccountManagementPolicy:$StorageAccountName" -ResourceGroup $ResourceGroupName) { return }
    [pscustomobject]@{ Name = 'DefaultManagementPolicy' }
}

function Remove-AzStorageAccountManagementPolicy {
    [CmdletBinding()]
    param([string]$ResourceGroupName, [string]$StorageAccountName)
    Invoke-StubRemoval -Command 'Remove-AzStorageAccountManagementPolicy' -Name $StorageAccountName
}

function Update-AzStorageBlobServiceProperty {
    [CmdletBinding()]
    param([string]$ResourceGroupName, [string]$StorageAccountName, [bool]$IsVersioningEnabled)
    Invoke-StubRemoval -Command 'Update-AzStorageBlobServiceProperty' -Name $StorageAccountName
}

function Set-AzStorageAccount {
    [CmdletBinding()]
    param([string]$ResourceGroupName, [string]$Name, [bool]$AllowBlobPublicAccess)
    Invoke-StubRemoval -Command 'Set-AzStorageAccount' -Name $Name
}
'@

    # Runs the real script in a child process with the stubs shadowing the Az commands, and
    # returns the exit code it hands back together with the stub's call log.
    function Invoke-CleanupScript {
        param(
            [pscustomobject]$Stub,
            [string[]]$Fail = @(),
            [string[]]$Lookup = @(),
            [string[]]$ArgumentList = @('-Force'),
            [switch]$Empty
        )

        $logPath = Join-Path $Stub.Directory 'calls.log'
        Remove-Item -LiteralPath $logPath -Force -ErrorAction SilentlyContinue

        $run = Invoke-LabScriptWithStub -Stub $Stub -ScriptPath $script:ScriptPath -ArgumentList $ArgumentList -Environment @{
            SKYCRAFT_STUB_FAIL   = $Fail -join ','
            SKYCRAFT_STUB_LOOKUP = $Lookup -join ','
            SKYCRAFT_STUB_EMPTY  = if ($Empty) { '1' } else { '0' }
            SKYCRAFT_STUB_LOG    = $logPath
        }

        $calls = if (Test-Path -LiteralPath $logPath) { @(Get-Content -LiteralPath $logPath) } else { @() }
        return [pscustomobject]@{
            ExitCode = $run.ExitCode
            Refused  = $run.Refused
            Output   = $run.Output
            Calls    = $calls
        }
    }

    $script:Stub    = Initialize-LabScriptStub -Name $script:StubModuleName -Command $script:StubCommands `
        -Body $script:StubBody -RequiredModule $script:RequiredModules
    $script:StubDir = $script:Stub.Directory

    # A change the script makes: a removal, an update or a setting.
    $script:ChangePattern = '^(Remove|Update|Set)-'

    # One invocation per scenario, reused by the assertions below - each child process costs
    # several seconds.
    $script:Clean    = Invoke-CleanupScript -Stub $script:Stub
    $script:Nothing  = Invoke-CleanupScript -Stub $script:Stub -Empty
    $script:WhatIf   = Invoke-CleanupScript -Stub $script:Stub -ArgumentList '-WhatIf'
    $script:NotFound = Invoke-CleanupScript -Stub $script:Stub -Lookup 'Get-AzStorageAccountManagementPolicy:prodskycraftswcsa=notfound'
    $script:AccountDenied = Invoke-CleanupScript -Stub $script:Stub -Lookup 'Get-AzStorageAccount:prodskycraftswcsa=denied'
    $script:LookupsFail   = Invoke-CleanupScript -Stub $script:Stub -Lookup @(
        'Get-AzStorageContainer:prodskycraftswcsa=denied'
        'Get-AzStorageAccountManagementPolicy:prodskycraftswcsa=throttled'
        'Get-AzStorageContainer:devskycraftswcsa=throttled'
    )
    $script:StepsFail = Invoke-CleanupScript -Stub $script:Stub -Fail @(
        'Remove-AzStorageContainer:game-assets'
        'Update-AzStorageBlobServiceProperty:prodskycraftswcsa'
    )

    $script:AllRuns = @(
        $script:Clean, $script:Nothing, $script:WhatIf, $script:NotFound, $script:AccountDenied, $script:LookupsFail,
        $script:StepsFail
    )
}

AfterAll {
    if ($script:StubDir) { Remove-Item -LiteralPath $script:StubDir -Recurse -Force -ErrorAction SilentlyContinue }
}

Describe 'Lab 4.2 Remove-LabResource.ps1 - test harness' {

    It 'shadows the real Az commands instead of touching a subscription' {
        # Refused is the child exiting 99 before the script ran. Asserted on every scenario: a
        # refusal in one of them is a half-stubbed session, not a scenario-specific failure.
        foreach ($run in $script:AllRuns) {
            $run.Refused | Should -BeFalse -Because "the harness must never fall through to the real Az commands (exit $($run.ExitCode)): $($run.Output)"
        }
    }
}

Describe 'Lab 4.2 Remove-LabResource.ps1 - removes what the lab creates' {

    It 'exits 0 when every object is found and removed' {
        $script:Clean.ExitCode | Should -Be 0 -Because "a clean teardown must report success; output was:`n$($script:Clean.Output)"
        $script:Clean.Output   | Should -Match 'Cleanup Complete'
        $script:Clean.Output   | Should -Not -Match '\[ERROR\]'
    }

    It 'removes the lab containers and no other, the policy, and reverts versioning and public access' {
        $calls = $script:Clean.Calls
        foreach ($call in 'Remove-AzStorageContainer:game-assets', 'Remove-AzStorageContainer:player-backups',
            'Remove-AzStorageContainer:server-config', 'Remove-AzStorageContainer:game-logs',
            'Remove-AzStorageContainer:public-demo', 'Remove-AzStorageAccountManagementPolicy:prodskycraftswcsa',
            'Update-AzStorageBlobServiceProperty:prodskycraftswcsa', 'Set-AzStorageAccount:devskycraftswcsa') {
            $calls | Should -Contain $call
        }
        $calls | Should -Not -Contain 'Remove-AzStorageContainer:unrelated'
    }
}

Describe 'Lab 4.2 Remove-LabResource.ps1 - an absent object is not a failure' {

    It 'exits 0 and changes nothing when neither account is there' {
        $run = $script:Nothing
        $run.ExitCode | Should -Be 0 -Because "nothing to clean is a clean teardown; output was:`n$($run.Output)"
        $run.Output | Should -Not -Match '\[ERROR\]'
        $run.Output | Should -Match 'Storage account prodskycraftswcsa not found - nothing to clean'
        $run.Output | Should -Match 'Storage account devskycraftswcsa not found - nothing to clean'
        @($run.Calls | Where-Object { $_ -match $script:ChangePattern }) | Should -BeNullOrEmpty
    }

    It 'exits 0 when the policy getter reports it not found, and does the rest' {
        $run = $script:NotFound
        $run.ExitCode | Should -Be 0 -Because "a not-found lookup means absent; output was:`n$($run.Output)"
        $run.Output | Should -Not -Match '\[ERROR\]'
        $run.Calls  | Should -Not -Contain 'Remove-AzStorageAccountManagementPolicy:prodskycraftswcsa'
        $run.Calls  | Should -Contain 'Update-AzStorageBlobServiceProperty:prodskycraftswcsa'
    }
}

Describe 'Lab 4.2 Remove-LabResource.ps1 - a failed lookup is not "absent" (#290)' {

    It 'exits 1 when an account could not be looked up, leaves it alone and still cleans the other' {
        $run = $script:AccountDenied
        $run.ExitCode | Should -Be 1 -Because "output was:`n$($run.Output)"
        $run.Output | Should -Match '\[ERROR\] Could not look up storage account prodskycraftswcsa[^\r\n]*does not have authorization'
        $run.Output | Should -Match 'Cleanup finished with 1 failure\(s\)'
        $run.Output | Should -Not -Match 'prodskycraftswcsa not found'
        $run.Output | Should -Not -Match 'Cleanup Complete'
        @($run.Calls | Where-Object { $_ -match $script:ChangePattern -and $_ -match 'prodskycraftswcsa|game-|player-|server-' }) | Should -BeNullOrEmpty
        $run.Calls  | Should -Contain 'Set-AzStorageAccount:devskycraftswcsa'
    }

    It 'exits 1, counts each failed lookup and removes nothing it could not see' {
        $run = $script:LookupsFail
        $run.ExitCode | Should -Be 1 -Because "output was:`n$($run.Output)"
        $run.Output | Should -Match '\[ERROR\] Could not look up the containers in prodskycraftswcsa[^\r\n]*does not have authorization'
        $run.Output | Should -Match '\[ERROR\] Could not look up the lifecycle policy of prodskycraftswcsa[^\r\n]*requests exceeded the limit'
        $run.Output | Should -Match '\[ERROR\] Could not look up the containers in devskycraftswcsa'
        $run.Output | Should -Match 'Cleanup finished with 3 failure\(s\)'
        @($run.Calls | Where-Object { $_ -like 'Remove-AzStorageContainer*' }) | Should -BeNullOrEmpty
        $run.Calls  | Should -Not -Contain 'Remove-AzStorageAccountManagementPolicy:prodskycraftswcsa'
    }

    It 'still runs the steps that need no lookup' {
        $script:LookupsFail.Calls | Should -Contain 'Update-AzStorageBlobServiceProperty:prodskycraftswcsa'
        $script:LookupsFail.Calls | Should -Contain 'Set-AzStorageAccount:devskycraftswcsa'
    }
}

Describe 'Lab 4.2 Remove-LabResource.ps1 - a failed step is counted' {

    It 'exits 1 and counts each step that failed' {
        $run = $script:StepsFail
        $run.ExitCode | Should -Be 1 -Because "output was:`n$($run.Output)"
        $run.Output | Should -Match '\[ERROR\] Could not delete container game-assets: stub failure'
        $run.Output | Should -Match '\[ERROR\] Could not disable versioning: stub failure'
        $run.Output | Should -Match 'Cleanup finished with 2 failure\(s\)'
        $run.Output | Should -Not -Match 'Cleanup Complete'
    }

    It 'keeps going after a failed step' {
        $calls = $script:StepsFail.Calls
        $calls | Should -Contain 'Remove-AzStorageContainer:player-backups'
        $calls | Should -Contain 'Remove-AzStorageAccountManagementPolicy:prodskycraftswcsa'
        $calls | Should -Contain 'Remove-AzStorageContainer:public-demo'
        $calls | Should -Contain 'Set-AzStorageAccount:devskycraftswcsa'
    }
}

Describe 'Lab 4.2 Remove-LabResource.ps1 - -WhatIf' {

    It 'looks the accounts up and changes nothing' {
        $run = $script:WhatIf
        $run.ExitCode | Should -Be 0 -Because "output was:`n$($run.Output)"
        @($run.Calls | Where-Object { $_ -match $script:ChangePattern }) | Should -BeNullOrEmpty
        $run.Calls  | Should -Contain 'Get-AzStorageAccount:prodskycraftswcsa'
        $run.Output | Should -Match 'What if: .*prodskycraftswcsa'
    }
}
