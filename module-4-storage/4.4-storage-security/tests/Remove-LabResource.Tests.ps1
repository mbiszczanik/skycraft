<#
.SYNOPSIS
    Pester 5 tests for the Lab 4.4 cleanup: when it reports an object absent, and when it exits 1.

.DESCRIPTION
    Regression cover for issue #290. The cleanup reported any error from the container step as
    "[INFO] Container 'dev-assets' not found or already removed.", printed the other failures as
    [ERROR] without counting them, and never exited 1 - a failed lookup or a failed step looked
    like a clean teardown. These tests run the real Remove-LabResource.ps1 in a child pwsh process
    against a generated stub of the Az commands it calls, and assert the observable contract:

      1. Everything the lab changes is reverted or removed when it is present, and the run exits
         0. Only the role assignments made on the account itself are removed.
      2. An object that is absent - an empty listing, or an account the getter reports not found
         - is not a failure: the run exits 0.
      3. A lookup that fails with an error is an [ERROR], counted, and the run exits 1 without
         touching or reporting absent the object it could not see. The stub reports the failure
         with Write-Error, as the Az getters do, so a script that passes -ErrorAction
         SilentlyContinue, or reads every error as "not found", swallows it.
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
    Lab: 4.4 - Storage Security
#>

#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..' '..' '..' 'tests' 'Support' 'LabScriptStub.psm1') -Force

    $script:ScriptPath     = (Resolve-Path (Join-Path $PSScriptRoot '..' 'scripts' 'Remove-LabResource.ps1')).Path
    $script:StubModuleName = 'SkyCraftLab44CleanupStub'
    # Exactly the script's '#Requires -Modules' line: these are imported for real before the stub.
    $script:RequiredModules = @('Az.Accounts', 'Az.Resources', 'Az.Storage')

    $script:StubCommands = @(
        'Get-AzContext'
        'Get-AzStorageAccount'
        'Update-AzStorageAccountNetworkRuleSet'
        'Get-AzStorageContainer'
        'Remove-AzStorageContainer'
        'Get-AzRoleAssignment'
        'Remove-AzRoleAssignment'
    )

    # Every command the script calls, recording its own invocation. By default the account holds
    # the dev-assets container and an unrelated one, two Storage Blob Data Contributor assignments
    # made on the account (objects 1111... and 2222...), one inherited from the resource group
    # (3333...) and a Reader assignment on the account (4444...). Environment variables change
    # that, so one generated module serves every scenario:
    #   SKYCRAFT_STUB_EMPTY   '1' leaves nothing to find: Get-AzStorageAccount reports
    #                         ResourceNotFound, as the real one does for a name that does not exist
    #   SKYCRAFT_STUB_BARE    '1' keeps the account but drops dev-assets and the lab's assignments
    #   SKYCRAFT_STUB_LOOKUP  '<lookup>=<kind>,...' makes one lookup fail (denied, throttled)
    #   SKYCRAFT_STUB_FAIL    '<command>:<name>,...' makes one change throw
    # A lookup is named after its command: 'Get-AzStorageAccount', 'Get-AzStorageContainer',
    # 'Get-AzRoleAssignment'.
    $script:StubBody = @'
$script:LogPath = $env:SKYCRAFT_STUB_LOG
$script:AccountId = '/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/prod-skycraft-swc-rg/providers/Microsoft.Storage/storageAccounts/prodskycraftswcsa'

function Write-StubCall {
    param([string]$Name)
    if ($script:LogPath) { Add-Content -LiteralPath $script:LogPath -Value $Name }
}

function Test-StubEmpty { return $env:SKYCRAFT_STUB_EMPTY -eq '1' }
function Test-StubBare { return $env:SKYCRAFT_STUB_BARE -eq '1' }

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
            Write-Error -ErrorId 'ResourceNotFound' -Message "The Resource 'Microsoft.Storage/storageAccounts/stub' under resource group '$ResourceGroup' was not found. For more details please go to https://aka.ms/ARMResourceNotFoundFix"
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
    if (Invoke-StubLookup -Name 'Get-AzStorageAccount' -ResourceGroup $ResourceGroupName -Named) { return }
    [pscustomobject]@{ StorageAccountName = $Name; Id = $script:AccountId; Context = "ctx:$Name" }
}

function Update-AzStorageAccountNetworkRuleSet {
    [CmdletBinding()]
    param([string]$ResourceGroupName, [string]$Name, [string]$DefaultAction)
    Invoke-StubRemoval -Command 'Update-AzStorageAccountNetworkRuleSet' -Name "${Name}:$DefaultAction"
}

function Get-AzStorageContainer {
    [CmdletBinding()]
    param([object]$Context, [string]$Name)
    if (Invoke-StubLookup -Name 'Get-AzStorageContainer') { return }
    [pscustomobject]@{ Name = 'unrelated' }
    if (Test-StubBare) { return }
    [pscustomobject]@{ Name = 'dev-assets' }
}

function Remove-AzStorageContainer {
    [CmdletBinding()]
    param([string]$Name, [object]$Context, [switch]$Force)
    Invoke-StubRemoval -Command 'Remove-AzStorageContainer' -Name $Name
}

function Get-AzRoleAssignment {
    [CmdletBinding()]
    param([string]$Scope)
    if (Invoke-StubLookup -Name 'Get-AzRoleAssignment') { return }
    $rg = '/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/prod-skycraft-swc-rg'
    [pscustomobject]@{ ObjectId = '33333333-3333-3333-3333-333333333333'; DisplayName = 'inherited'; RoleDefinitionName = 'Storage Blob Data Contributor'; Scope = $rg }
    [pscustomobject]@{ ObjectId = '44444444-4444-4444-4444-444444444444'; DisplayName = 'reader'; RoleDefinitionName = 'Reader'; Scope = $Scope }
    if (Test-StubBare) { return }
    [pscustomobject]@{ ObjectId = '11111111-1111-1111-1111-111111111111'; DisplayName = 'first'; RoleDefinitionName = 'Storage Blob Data Contributor'; Scope = $Scope }
    [pscustomobject]@{ ObjectId = '22222222-2222-2222-2222-222222222222'; DisplayName = 'second'; RoleDefinitionName = 'Storage Blob Data Contributor'; Scope = $Scope }
}

function Remove-AzRoleAssignment {
    [CmdletBinding()]
    param([string]$ObjectId, [string]$RoleDefinitionName, [string]$Scope)
    Invoke-StubRemoval -Command 'Remove-AzRoleAssignment' -Name $ObjectId
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
            [switch]$Empty,
            [switch]$Bare
        )

        $logPath = Join-Path $Stub.Directory 'calls.log'
        Remove-Item -LiteralPath $logPath -Force -ErrorAction SilentlyContinue

        $run = Invoke-LabScriptWithStub -Stub $Stub -ScriptPath $script:ScriptPath -ArgumentList $ArgumentList -Environment @{
            SKYCRAFT_STUB_FAIL   = $Fail -join ','
            SKYCRAFT_STUB_LOOKUP = $Lookup -join ','
            SKYCRAFT_STUB_EMPTY  = if ($Empty) { '1' } else { '0' }
            SKYCRAFT_STUB_BARE   = if ($Bare) { '1' } else { '0' }
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

    # A change the script makes: a removal or an update.
    $script:ChangePattern = '^(Remove|Update)-'

    # One invocation per scenario, reused by the assertions below - each child process costs
    # several seconds.
    $script:Clean         = Invoke-CleanupScript -Stub $script:Stub
    $script:Nothing       = Invoke-CleanupScript -Stub $script:Stub -Empty
    $script:Bare          = Invoke-CleanupScript -Stub $script:Stub -Bare
    $script:WhatIf        = Invoke-CleanupScript -Stub $script:Stub -ArgumentList '-WhatIf'
    $script:AccountDenied = Invoke-CleanupScript -Stub $script:Stub -Lookup 'Get-AzStorageAccount=denied'
    $script:LookupsFail   = Invoke-CleanupScript -Stub $script:Stub -Lookup @(
        'Get-AzStorageContainer=denied'
        'Get-AzRoleAssignment=throttled'
    )
    $script:StepsFail = Invoke-CleanupScript -Stub $script:Stub -Fail @(
        'Update-AzStorageAccountNetworkRuleSet:prodskycraftswcsa:Allow'
        'Remove-AzRoleAssignment:11111111-1111-1111-1111-111111111111'
    )

    $script:AllRuns = @(
        $script:Clean, $script:Nothing, $script:Bare, $script:WhatIf, $script:AccountDenied, $script:LookupsFail,
        $script:StepsFail
    )
}

AfterAll {
    if ($script:StubDir) { Remove-Item -LiteralPath $script:StubDir -Recurse -Force -ErrorAction SilentlyContinue }
}

Describe 'Lab 4.4 Remove-LabResource.ps1 - test harness' {

    It 'shadows the real Az commands instead of touching a subscription' {
        # Refused is the child exiting 99 before the script ran. Asserted on every scenario: a
        # refusal in one of them is a half-stubbed session, not a scenario-specific failure.
        foreach ($run in $script:AllRuns) {
            $run.Refused | Should -BeFalse -Because "the harness must never fall through to the real Az commands (exit $($run.ExitCode)): $($run.Output)"
        }
    }
}

Describe 'Lab 4.4 Remove-LabResource.ps1 - reverts what the lab changes' {

    It 'exits 0 when everything is found and reverted' {
        $script:Clean.ExitCode | Should -Be 0 -Because "a clean teardown must report success; output was:`n$($script:Clean.Output)"
        $script:Clean.Output   | Should -Match 'Cleanup Complete'
        $script:Clean.Output   | Should -Not -Match '\[ERROR\]'
    }

    It 'reverts the firewall, removes dev-assets and the lab''s role assignments on the account' {
        $calls = $script:Clean.Calls
        $calls | Should -Contain 'Update-AzStorageAccountNetworkRuleSet:prodskycraftswcsa:Allow'
        $calls | Should -Contain 'Remove-AzStorageContainer:dev-assets'
        $calls | Should -Not -Contain 'Remove-AzStorageContainer:unrelated'
        $calls | Should -Contain 'Remove-AzRoleAssignment:11111111-1111-1111-1111-111111111111'
        $calls | Should -Contain 'Remove-AzRoleAssignment:22222222-2222-2222-2222-222222222222'
    }

    It 'leaves an inherited assignment and another role alone' {
        $script:Clean.Calls | Should -Not -Contain 'Remove-AzRoleAssignment:33333333-3333-3333-3333-333333333333'
        $script:Clean.Calls | Should -Not -Contain 'Remove-AzRoleAssignment:44444444-4444-4444-4444-444444444444'
    }
}

Describe 'Lab 4.4 Remove-LabResource.ps1 - an absent object is not a failure' {

    It 'exits 0 and changes nothing when the storage account is not there' {
        $run = $script:Nothing
        $run.ExitCode | Should -Be 0 -Because "output was:`n$($run.Output)"
        $run.Output   | Should -Match "Storage account 'prodskycraftswcsa' not found - nothing to revert"
        $run.Output   | Should -Not -Match '\[ERROR\]'
        @($run.Calls | Where-Object { $_ -match $script:ChangePattern }) | Should -BeNullOrEmpty
    }

    It 'exits 0 when the container and the assignments are already gone' {
        $run = $script:Bare
        $run.ExitCode | Should -Be 0 -Because "output was:`n$($run.Output)"
        $run.Output   | Should -Match "Container 'dev-assets' not found or already removed"
        $run.Output   | Should -Match "No 'Storage Blob Data Contributor' assignments found"
        $run.Output   | Should -Not -Match '\[ERROR\]'
    }
}

Describe 'Lab 4.4 Remove-LabResource.ps1 - a failed lookup is not "absent" (#290)' {

    It 'exits 1 when the storage account could not be looked up, and changes nothing' {
        $run = $script:AccountDenied
        $run.ExitCode | Should -Be 1 -Because "output was:`n$($run.Output)"
        $run.Output   | Should -Match "\[ERROR\] Could not look up storage account 'prodskycraftswcsa'[^\r\n]*does not have authorization"
        $run.Output   | Should -Match 'Cleanup finished with 1 failure\(s\)'
        $run.Output   | Should -Not -Match 'nothing to revert'
        $run.Output   | Should -Not -Match 'Cleanup Complete'
        @($run.Calls | Where-Object { $_ -match $script:ChangePattern }) | Should -BeNullOrEmpty
    }

    It 'exits 1, counts each failed lookup and does not report what it could not see as absent' {
        $run = $script:LookupsFail
        $run.ExitCode | Should -Be 1 -Because "output was:`n$($run.Output)"
        $run.Output   | Should -Match "\[ERROR\] Could not look up the containers in 'prodskycraftswcsa'[^\r\n]*does not have authorization"
        $run.Output   | Should -Match "\[ERROR\] Could not look up the role assignments on 'prodskycraftswcsa'[^\r\n]*requests exceeded the limit"
        $run.Output   | Should -Match 'Cleanup finished with 2 failure\(s\)'
        $run.Output   | Should -Not -Match 'not found or already removed'
        $run.Output   | Should -Not -Match 'No .Storage Blob Data Contributor. assignments found'
        @($run.Calls | Where-Object { $_ -like 'Remove-*' }) | Should -BeNullOrEmpty
    }

    It 'still reverts the firewall when the later lookups fail' {
        $script:LookupsFail.Calls | Should -Contain 'Update-AzStorageAccountNetworkRuleSet:prodskycraftswcsa:Allow'
    }
}

Describe 'Lab 4.4 Remove-LabResource.ps1 - a failed step is counted' {

    It 'exits 1 and counts each step that failed' {
        $run = $script:StepsFail
        $run.ExitCode | Should -Be 1 -Because "output was:`n$($run.Output)"
        $run.Output   | Should -Match '\[ERROR\] Failed to revert firewall'
        $run.Output   | Should -Match "\[ERROR\] Failed to remove the assignment for 'first'"
        $run.Output   | Should -Match 'Cleanup finished with 2 failure\(s\)'
        $run.Output   | Should -Not -Match 'Cleanup Complete'
    }

    It 'keeps going after a failed step' {
        $script:StepsFail.Calls | Should -Contain 'Remove-AzStorageContainer:dev-assets'
        $script:StepsFail.Calls | Should -Contain 'Remove-AzRoleAssignment:22222222-2222-2222-2222-222222222222'
    }
}

Describe 'Lab 4.4 Remove-LabResource.ps1 - -WhatIf' {

    It 'looks the account up and changes nothing' {
        $run = $script:WhatIf
        $run.ExitCode | Should -Be 0 -Because "output was:`n$($run.Output)"
        @($run.Calls | Where-Object { $_ -match $script:ChangePattern }) | Should -BeNullOrEmpty
        $run.Calls    | Should -Contain 'Get-AzStorageAccount'
        $run.Output   | Should -Match 'What if: .*dev-assets'
    }
}
