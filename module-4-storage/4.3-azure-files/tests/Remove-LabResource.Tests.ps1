<#
.SYNOPSIS
    Pester 5 tests for the Lab 4.3 cleanup: when it reports a share absent, and when it exits 1.

.DESCRIPTION
    Regression cover for issue #290. The cleanup looked the storage account and each share up
    with -ErrorAction SilentlyContinue, so a lookup that failed (a 403, throttling) read as "not
    found": an unreadable account ended the run with "Nothing to clean up." and exit 0. A share
    that could not be removed was a [WARNING], and the run still exited 0. These tests run the
    real Remove-LabResource.ps1 in a child pwsh process against a generated stub of the Az
    commands it calls, and assert the observable contract:

      1. Both lab shares are removed when they are present, and the run exits 0.
      2. An object that is absent - a share missing from the listing, or an account the getter
         reports not found - is not a failure: the run exits 0.
      3. A lookup that fails with an error is an [ERROR], counted, and the run exits 1 without
         touching or reporting absent what it could not see. The stub reports the failure with
         Write-Error, as the Az getters do, so a script that passes -ErrorAction
         SilentlyContinue swallows it.
      4. A removal that fails is an [ERROR], counted, and the other share is still removed: exit 1.

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
    Lab: 4.3 - Azure Files
#>

#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..' '..' '..' 'tests' 'Support' 'LabScriptStub.psm1') -Force

    $script:ScriptPath     = (Resolve-Path (Join-Path $PSScriptRoot '..' 'scripts' 'Remove-LabResource.ps1')).Path
    $script:StubModuleName = 'SkyCraftLab43CleanupStub'
    # Exactly the script's '#Requires -Modules' line: these are imported for real before the stub.
    # Remove-AzResource comes from Az.Resources, which the line does not name; the stub exports
    # it, so it resolves to the stub all the same.
    $script:RequiredModules = @('Az.Accounts', 'Az.Storage')

    $script:StubCommands = @(
        'Get-AzContext'
        'Get-AzStorageAccount'
        'Get-AzRmStorageShare'
        'Remove-AzResource'
    )

    # Every command the script calls, recording its own invocation. By default the account holds
    # both lab shares and an unrelated one. Environment variables change that, so one generated
    # module serves every scenario:
    #   SKYCRAFT_STUB_EMPTY   '1' leaves only the unrelated share in the listing
    #   SKYCRAFT_STUB_LOOKUP  '<lookup>=<kind>,...' makes one lookup fail (denied, throttled) or
    #                         report its object not found (notfound, rgnotfound)
    #   SKYCRAFT_STUB_FAIL    'Remove-AzResource:<share>,...' makes one removal throw
    # A lookup is named after its command and the object it reads: 'Get-AzStorageAccount:<sa>',
    # 'Get-AzRmStorageShare:<sa>'.
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

function Get-AzContext {
    [CmdletBinding()]
    param()
    [pscustomobject]@{
        Subscription = [pscustomobject]@{ Id = '00000000-0000-0000-0000-000000000000'; Name = 'stub-subscription' }
    }
}

function Get-AzStorageAccount {
    [CmdletBinding()]
    param([string]$ResourceGroupName, [string]$Name)
    if (Invoke-StubLookup -Name "Get-AzStorageAccount:$Name" -ResourceGroup $ResourceGroupName) { return }
    [pscustomobject]@{ StorageAccountName = $Name }
}

function Get-AzRmStorageShare {
    [CmdletBinding()]
    param([string]$ResourceGroupName, [string]$StorageAccountName)
    if (Invoke-StubLookup -Name "Get-AzRmStorageShare:$StorageAccountName" -ResourceGroup $ResourceGroupName) { return }
    [pscustomobject]@{ Name = 'unrelated' }
    if (Test-StubEmpty) { return }
    [pscustomobject]@{ Name = 'skycraft-config' }
    [pscustomobject]@{ Name = 'skycraft-shared' }
}

function Remove-AzResource {
    [CmdletBinding()]
    param([string]$ResourceId, [switch]$Force)
    Write-StubCall -Name "Remove-AzResource@$ResourceId"
    Invoke-StubRemoval -Command 'Remove-AzResource' -Name (($ResourceId -split '/')[-1])
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
    $script:Clean          = Invoke-CleanupScript -Stub $script:Stub
    $script:Dev            = Invoke-CleanupScript -Stub $script:Stub -ArgumentList '-Force', '-Environment', 'dev'
    $script:NoShares       = Invoke-CleanupScript -Stub $script:Stub -Empty
    $script:NoAccount      = Invoke-CleanupScript -Stub $script:Stub -Lookup 'Get-AzStorageAccount:prodskycraftswcsa=rgnotfound'
    $script:WhatIf         = Invoke-CleanupScript -Stub $script:Stub -ArgumentList '-WhatIf'
    $script:AccountDenied  = Invoke-CleanupScript -Stub $script:Stub -Lookup 'Get-AzStorageAccount:prodskycraftswcsa=denied'
    $script:SharesThrottled = Invoke-CleanupScript -Stub $script:Stub -Lookup 'Get-AzRmStorageShare:prodskycraftswcsa=throttled'
    $script:RemovalFails   = Invoke-CleanupScript -Stub $script:Stub -Fail 'Remove-AzResource:skycraft-config'

    $script:AllRuns = @(
        $script:Clean, $script:Dev, $script:NoShares, $script:NoAccount, $script:WhatIf, $script:AccountDenied,
        $script:SharesThrottled, $script:RemovalFails
    )
}

AfterAll {
    if ($script:StubDir) { Remove-Item -LiteralPath $script:StubDir -Recurse -Force -ErrorAction SilentlyContinue }
}

Describe 'Lab 4.3 Remove-LabResource.ps1 - test harness' {

    It 'shadows the real Az commands instead of touching a subscription' {
        # Refused is the child exiting 99 before the script ran. Asserted on every scenario: a
        # refusal in one of them is a half-stubbed session, not a scenario-specific failure.
        foreach ($run in $script:AllRuns) {
            $run.Refused | Should -BeFalse -Because "the harness must never fall through to the real Az commands (exit $($run.ExitCode)): $($run.Output)"
        }
    }
}

Describe 'Lab 4.3 Remove-LabResource.ps1 - removes what the lab creates' {

    It 'exits 0 and removes both lab shares and no other' {
        $run = $script:Clean
        $run.ExitCode | Should -Be 0 -Because "a clean teardown must report success; output was:`n$($run.Output)"
        $run.Output   | Should -Match 'Lab 4.3 Cleanup Complete'
        $run.Output   | Should -Not -Match '\[ERROR\]'
        $run.Calls    | Should -Contain 'Remove-AzResource:skycraft-config'
        $run.Calls    | Should -Contain 'Remove-AzResource:skycraft-shared'
        $run.Calls    | Should -Not -Contain 'Remove-AzResource:unrelated'
        $run.Calls    | Should -Contain 'Remove-AzResource@/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/prod-skycraft-swc-rg/providers/Microsoft.Storage/storageAccounts/prodskycraftswcsa/fileServices/default/shares/skycraft-config'
    }

    It 'targets the dev account with -Environment dev' {
        $script:Dev.ExitCode | Should -Be 0 -Because "output was:`n$($script:Dev.Output)"
        $script:Dev.Calls    | Should -Contain 'Get-AzRmStorageShare:devskycraftswcsa'
        $script:Dev.Calls    | Should -Contain 'Remove-AzResource@/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/dev-skycraft-swc-rg/providers/Microsoft.Storage/storageAccounts/devskycraftswcsa/fileServices/default/shares/skycraft-shared'
    }
}

Describe 'Lab 4.3 Remove-LabResource.ps1 - an absent object is not a failure' {

    It 'exits 0 and skips the shares that are not in the listing' {
        $run = $script:NoShares
        $run.ExitCode | Should -Be 0 -Because "output was:`n$($run.Output)"
        $run.Output   | Should -Match "Share 'skycraft-config' not found, skipping"
        $run.Output   | Should -Match "Share 'skycraft-shared' not found, skipping"
        $run.Output   | Should -Not -Match '\[ERROR\]'
        @($run.Calls | Where-Object { $_ -match '^Remove-' }) | Should -BeNullOrEmpty
    }

    It 'exits 0 when the getter reports the storage account not found' {
        $run = $script:NoAccount
        $run.ExitCode | Should -Be 0 -Because "output was:`n$($run.Output)"
        $run.Output   | Should -Match "Storage account 'prodskycraftswcsa' not found. Nothing to clean up."
        @($run.Calls | Where-Object { $_ -match '^Remove-' }) | Should -BeNullOrEmpty
    }
}

Describe 'Lab 4.3 Remove-LabResource.ps1 - a failed lookup is not "absent" (#290)' {

    It 'exits 1 when the storage account could not be looked up, without reporting it absent' {
        $run = $script:AccountDenied
        $run.ExitCode | Should -Be 1 -Because "an account that may still exist must not look like a clean cleanup; output was:`n$($run.Output)"
        $run.Output   | Should -Match "\[ERROR\] Could not look up storage account 'prodskycraftswcsa'[^\r\n]*does not have authorization"
        $run.Output   | Should -Match 'cleanup finished with 1 failure\(s\)'
        $run.Output   | Should -Not -Match 'Nothing to clean up'
        $run.Output   | Should -Not -Match 'Cleanup Complete'
        @($run.Calls | Where-Object { $_ -match '^Remove-' }) | Should -BeNullOrEmpty
    }

    It 'exits 1 when the shares could not be listed, and removes none' {
        $run = $script:SharesThrottled
        $run.ExitCode | Should -Be 1 -Because "output was:`n$($run.Output)"
        $run.Output   | Should -Match "\[ERROR\] Could not look up the file shares in 'prodskycraftswcsa'[^\r\n]*requests exceeded the limit"
        $run.Output   | Should -Not -Match 'not found, skipping'
        @($run.Calls | Where-Object { $_ -match '^Remove-' }) | Should -BeNullOrEmpty
    }
}

Describe 'Lab 4.3 Remove-LabResource.ps1 - a failed removal is counted' {

    It 'exits 1, reports the removal that failed and still removes the other share' {
        $run = $script:RemovalFails
        $run.ExitCode | Should -Be 1 -Because "a stuck share must not look like a clean cleanup; output was:`n$($run.Output)"
        $run.Output   | Should -Match "\[ERROR\] Could not remove 'skycraft-config': stub failure"
        $run.Output   | Should -Match 'cleanup finished with 1 failure\(s\)'
        $run.Output   | Should -Not -Match 'Cleanup Complete'
        $run.Calls    | Should -Contain 'Remove-AzResource:skycraft-shared'
    }
}

Describe 'Lab 4.3 Remove-LabResource.ps1 - -WhatIf' {

    It 'lists the shares and removes nothing' {
        $run = $script:WhatIf
        $run.ExitCode | Should -Be 0 -Because "output was:`n$($run.Output)"
        @($run.Calls | Where-Object { $_ -match '^Remove-' }) | Should -BeNullOrEmpty
        $run.Calls    | Should -Contain 'Get-AzRmStorageShare:prodskycraftswcsa'
        $run.Output   | Should -Match 'What if: .*skycraft-config'
    }
}
