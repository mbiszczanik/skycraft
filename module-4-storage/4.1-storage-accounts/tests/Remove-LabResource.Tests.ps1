<#
.SYNOPSIS
    Pester 5 tests for the Lab 4.1 cleanup: when it reports a storage account absent, and when it
    exits 1.

.DESCRIPTION
    Regression cover for issue #290. The cleanup looked each storage account up with -ErrorAction
    SilentlyContinue, so a lookup that failed (a 403, throttling) read as "SKIPPED (not found)",
    and it never exited 1 - not even when a deletion failed. These tests run the real
    Remove-LabResource.ps1 in a child pwsh process against a generated stub of the Az commands it
    calls, and assert the observable contract:

      1. Every account the lab creates is deleted when it is present, and the run exits 0.
      2. An account that is absent - a getter that reports it not found - is skipped, not a
         failure: the run exits 0.
      3. A lookup that fails with an error is an [ERROR], counted, and the run exits 1 without
         touching or reporting absent the account it could not see. The stub reports the failure
         with Write-Error, as the Az getters do, so a script that passes -ErrorAction
         SilentlyContinue swallows it.
      4. A deletion that fails is an [ERROR], counted, and the other accounts are still deleted:
         exit 1.

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
    Lab: 4.1 - Storage Accounts
#>

#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..' '..' '..' 'tests' 'Support' 'LabScriptStub.psm1') -Force

    $script:ScriptPath     = (Resolve-Path (Join-Path $PSScriptRoot '..' 'scripts' 'Remove-LabResource.ps1')).Path
    $script:StubModuleName = 'SkyCraftLab41CleanupStub'
    # Exactly the script's '#Requires -Modules' line: these are imported for real before the stub.
    $script:RequiredModules = @('Az.Accounts', 'Az.Storage')

    $script:StubCommands = @(
        'Get-AzStorageAccount'
        'Remove-AzStorageAccount'
    )

    # Every command the script calls, recording its own invocation. By default the three lab
    # accounts exist. Environment variables change that, so one generated module serves every
    # scenario:
    #   SKYCRAFT_STUB_EMPTY   '1' leaves nothing to find: Get-AzStorageAccount reports
    #                         ResourceNotFound, as the real one does for a name that does not exist
    #   SKYCRAFT_STUB_LOOKUP  'Get-AzStorageAccount:<name>=<kind>,...' makes one lookup fail
    #                         (denied, throttled) or report its account not found (notfound,
    #                         rgnotfound)
    #   SKYCRAFT_STUB_FAIL    'Remove-AzStorageAccount:<name>,...' makes one removal throw
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
# lookup failed, so the stub returns nothing after it.
function Invoke-StubLookup {
    param([string]$Name, [string]$ResourceGroup)
    Write-StubCall -Name $Name
    $kind = foreach ($entry in @($env:SKYCRAFT_STUB_LOOKUP -split ',')) {
        $key, $value = $entry -split '=', 2
        if ($key -eq $Name) { $value }
    }
    if (-not $kind -and (Test-StubEmpty)) { $kind = 'notfound' }
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
            Write-Error -ErrorId 'ResourceNotFound' -Message "The Resource 'Microsoft.Storage/storageAccounts/$(($Name -split ':')[-1])' under resource group '$ResourceGroup' was not found. For more details please go to https://aka.ms/ARMResourceNotFoundFix"
            return $true
        }
        'rgnotfound' {
            Write-Error -ErrorId 'ResourceGroupNotFound' -Message "Resource group '$ResourceGroup' could not be found."
            return $true
        }
    }
    return $false
}

function Get-AzStorageAccount {
    [CmdletBinding()]
    param([string]$ResourceGroupName, [string]$Name)
    if (Invoke-StubLookup -Name "Get-AzStorageAccount:$Name" -ResourceGroup $ResourceGroupName) { return }
    [pscustomobject]@{ StorageAccountName = $Name; ResourceGroupName = $ResourceGroupName }
}

function Remove-AzStorageAccount {
    [CmdletBinding()]
    param([string]$ResourceGroupName, [string]$Name, [switch]$Force)
    Invoke-StubRemoval -Command 'Remove-AzStorageAccount' -Name $Name
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

    # One invocation per scenario, reused by the assertions below - each child process costs
    # several seconds.
    $script:Clean    = Invoke-CleanupScript -Stub $script:Stub
    $script:Nothing  = Invoke-CleanupScript -Stub $script:Stub -Empty
    $script:WhatIf   = Invoke-CleanupScript -Stub $script:Stub -ArgumentList '-WhatIf'
    $script:DevOnly  = Invoke-CleanupScript -Stub $script:Stub -ArgumentList '-Force', '-Environment', 'dev'
    $script:NotFound = Invoke-CleanupScript -Stub $script:Stub -Lookup @(
        'Get-AzStorageAccount:devskycraftswcsa=notfound'
        'Get-AzStorageAccount:prodskycraftswcsa=rgnotfound'
    )
    $script:LookupFails  = Invoke-CleanupScript -Stub $script:Stub -Lookup 'Get-AzStorageAccount:devskycraftswcsa=denied'
    $script:RemovalFails = Invoke-CleanupScript -Stub $script:Stub -Fail 'Remove-AzStorageAccount:platformskycraftswcsa'

    $script:AllRuns = @(
        $script:Clean, $script:Nothing, $script:WhatIf, $script:DevOnly, $script:NotFound, $script:LookupFails,
        $script:RemovalFails
    )
}

AfterAll {
    if ($script:StubDir) { Remove-Item -LiteralPath $script:StubDir -Recurse -Force -ErrorAction SilentlyContinue }
}

Describe 'Lab 4.1 Remove-LabResource.ps1 - test harness' {

    It 'shadows the real Az commands instead of touching a subscription' {
        # Refused is the child exiting 99 before the script ran. Asserted on every scenario: a
        # refusal in one of them is a half-stubbed session, not a scenario-specific failure.
        foreach ($run in $script:AllRuns) {
            $run.Refused | Should -BeFalse -Because "the harness must never fall through to the real Az commands (exit $($run.ExitCode)): $($run.Output)"
        }
    }
}

Describe 'Lab 4.1 Remove-LabResource.ps1 - removes what the lab creates' {

    It 'exits 0 when every account is found and deleted' {
        $run = $script:Clean
        $run.ExitCode | Should -Be 0 -Because "a clean teardown must report success; output was:`n$($run.Output)"
        $run.Output   | Should -Match 'Cleanup complete'
        $run.Output   | Should -Match 'Deleted: 3'
        $run.Output   | Should -Match 'Failed:  0'
        foreach ($name in 'platformskycraftswcsa', 'devskycraftswcsa', 'prodskycraftswcsa') {
            $run.Calls | Should -Contain "Remove-AzStorageAccount:$name"
        }
    }

    It 'deletes only the dev account with -Environment dev' {
        $script:DevOnly.ExitCode | Should -Be 0 -Because "output was:`n$($script:DevOnly.Output)"
        @($script:DevOnly.Calls | Where-Object { $_ -like 'Remove-AzStorageAccount:*' }) | Should -Be @('Remove-AzStorageAccount:devskycraftswcsa')
    }
}

Describe 'Lab 4.1 Remove-LabResource.ps1 - an absent account is not a failure' {

    It 'exits 0 and skips every account when none is there' {
        $run = $script:Nothing
        $run.ExitCode | Should -Be 0 -Because "nothing to remove is a clean teardown; output was:`n$($run.Output)"
        $run.Output   | Should -Not -Match '\[ERROR\]'
        $run.Output   | Should -Match 'Skipped: 3'
        @($run.Calls | Where-Object { $_ -match '^Remove-' }) | Should -BeNullOrEmpty
    }

    It 'exits 0 when a getter reports its account or group not found, and deletes the rest' {
        $run = $script:NotFound
        $run.ExitCode | Should -Be 0 -Because "a not-found lookup means absent; output was:`n$($run.Output)"
        $run.Output   | Should -Not -Match '\[ERROR\]'
        $run.Output   | Should -Match 'Skipped: 2'
        $run.Calls    | Should -Contain 'Remove-AzStorageAccount:platformskycraftswcsa'
    }
}

Describe 'Lab 4.1 Remove-LabResource.ps1 - a failed lookup is not "absent" (#290)' {

    It 'exits 1, counts the failed lookup and carries the Azure error' {
        $run = $script:LookupFails
        $run.ExitCode | Should -Be 1 -Because "an account that may still exist must not look like a clean cleanup; output was:`n$($run.Output)"
        $run.Output   | Should -Match '\[ERROR\] Could not look up storage account devskycraftswcsa[^\r\n]*does not have authorization'
        $run.Output   | Should -Match 'Failed:  1'
        $run.Output   | Should -Match 'Skipped: 0'
        $run.Output   | Should -Not -Match 'Cleanup complete'
    }

    It 'leaves the account it could not see alone, and deletes the others' {
        $run = $script:LookupFails
        $run.Calls | Should -Not -Contain 'Remove-AzStorageAccount:devskycraftswcsa'
        $run.Calls | Should -Contain 'Remove-AzStorageAccount:platformskycraftswcsa'
        $run.Calls | Should -Contain 'Remove-AzStorageAccount:prodskycraftswcsa'
    }
}

Describe 'Lab 4.1 Remove-LabResource.ps1 - a failed deletion is counted' {

    It 'exits 1 and reports the deletion that failed' {
        $run = $script:RemovalFails
        $run.ExitCode | Should -Be 1 -Because "a stuck account must not look like a clean cleanup; output was:`n$($run.Output)"
        $run.Output   | Should -Match '\[ERROR\] stub failure: Remove-AzStorageAccount platformskycraftswcsa'
        $run.Output   | Should -Match 'Failed:  1'
        $run.Output   | Should -Not -Match 'Cleanup complete'
    }

    It 'keeps going after a failed deletion' {
        $script:RemovalFails.Calls | Should -Contain 'Remove-AzStorageAccount:devskycraftswcsa'
        $script:RemovalFails.Calls | Should -Contain 'Remove-AzStorageAccount:prodskycraftswcsa'
    }
}

Describe 'Lab 4.1 Remove-LabResource.ps1 - -WhatIf' {

    It 'looks the accounts up and deletes nothing' {
        $run = $script:WhatIf
        $run.ExitCode | Should -Be 0 -Because "output was:`n$($run.Output)"
        @($run.Calls | Where-Object { $_ -match '^Remove-' }) | Should -BeNullOrEmpty
        $run.Calls    | Should -Contain 'Get-AzStorageAccount:prodskycraftswcsa'
        $run.Output   | Should -Match 'What if: .*prodskycraftswcsa'
    }
}
