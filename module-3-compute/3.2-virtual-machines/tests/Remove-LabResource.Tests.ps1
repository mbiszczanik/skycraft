<#
.SYNOPSIS
    Pester 5 tests for the Lab 3.2 cleanup: when it reports a resource absent, and when it exits 1.

.DESCRIPTION
    Regression cover for issue #290. The cleanup looked the VMs, the data disk and the Key Vault up
    with -ErrorAction SilentlyContinue, so a lookup that failed (a 403, throttling) read as "not
    found": with nothing else found it printed "No Lab 3.2 resources found to delete." and exited
    0. A deletion that failed stopped the script before the later steps. These tests run the real
    Remove-LabResource.ps1 in a child pwsh process against a generated stub of the Az commands it
    calls, and assert the observable contract:

      1. Everything the lab creates is removed when it is present, and the run exits 0.
      2. A resource that is absent - a getter that reports it not found - is not a failure: the
         run exits 0.
      3. A lookup that fails with an error is an [ERROR], counted, and the run exits 1 without
         touching or reporting absent the resource it could not see. The stub reports the failure
         with Write-Error, as the Az getters do, so a script that passes -ErrorAction
         SilentlyContinue swallows it.
      4. A deletion that fails is an [ERROR], counted, and the later steps still run: exit 1.

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
    Lab: 3.2 - Virtual Machines
#>

#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..' '..' '..' 'tests' 'Support' 'LabScriptStub.psm1') -Force

    $script:ScriptPath     = (Resolve-Path (Join-Path $PSScriptRoot '..' 'scripts' 'Remove-LabResource.ps1')).Path
    $script:StubModuleName = 'SkyCraftLab32CleanupStub'
    # Exactly the script's '#Requires -Modules' line: these are imported for real before the stub.
    $script:RequiredModules = @('Az.Accounts', 'Az.Compute', 'Az.KeyVault')

    $script:StubCommands = @(
        'Get-AzContext'
        'Get-AzVM'
        'Remove-AzVM'
        'Get-AzDisk'
        'Remove-AzDisk'
        'Get-AzKeyVault'
        'Remove-AzKeyVault'
    )

    # Every command the script calls, recording its own invocation. By default the resource group
    # holds everything the lab creates: both VMs, the data disk and the Key Vault. Environment
    # variables change that, so one generated module serves every scenario:
    #   SKYCRAFT_STUB_EMPTY   '1' leaves nothing to find: Get-AzVM and Get-AzDisk report
    #                         ResourceNotFound, as the real ones do, and Get-AzKeyVault returns
    #                         nothing, as the real one does for a vault that does not exist
    #   SKYCRAFT_STUB_LOOKUP  '<lookup>=<kind>,...' makes one lookup fail (denied, throttled) or
    #                         report its resource not found (notfound, rgnotfound)
    #   SKYCRAFT_STUB_FAIL    '<Remove-command>:<name>,...' makes one removal throw
    # A lookup is named after its command and the resource it reads: 'Get-AzVM:<vm>',
    # 'Get-AzDisk:<disk>', 'Get-AzKeyVault:<vault>'. The vault purge is logged as
    # 'Remove-AzKeyVault:purge:<vault>'.
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
# lookup failed, so the stub returns nothing after it. -Named lookups report a missing resource
# as ResourceNotFound when the stub is empty.
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
            Write-Error -ErrorId 'ResourceNotFound' -Message "The Resource 'Microsoft.Compute/stubs/$(($Name -split ':')[-1])' under resource group '$ResourceGroup' was not found. For more details please go to https://aka.ms/ARMResourceNotFoundFix"
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

function Get-AzVM {
    [CmdletBinding()]
    param([string]$Name, [string]$ResourceGroupName)
    if (Invoke-StubLookup -Name "Get-AzVM:$Name" -ResourceGroup $ResourceGroupName -Named) { return }
    [pscustomobject]@{ Name = $Name }
}

function Remove-AzVM {
    [CmdletBinding()]
    param([string]$Name, [string]$ResourceGroupName, [switch]$Force)
    Invoke-StubRemoval -Command 'Remove-AzVM' -Name $Name
}

function Get-AzDisk {
    [CmdletBinding()]
    param([string]$DiskName, [string]$ResourceGroupName)
    if (Invoke-StubLookup -Name "Get-AzDisk:$DiskName" -ResourceGroup $ResourceGroupName -Named) { return }
    [pscustomobject]@{ Name = $DiskName }
}

function Remove-AzDisk {
    [CmdletBinding()]
    param([string]$DiskName, [string]$ResourceGroupName, [switch]$Force)
    Invoke-StubRemoval -Command 'Remove-AzDisk' -Name $DiskName
}

function Get-AzKeyVault {
    [CmdletBinding()]
    param([string]$VaultName, [string]$ResourceGroupName)
    if (Invoke-StubLookup -Name "Get-AzKeyVault:$VaultName" -ResourceGroup $ResourceGroupName) { return }
    if (Test-StubEmpty) { return }
    [pscustomobject]@{ VaultName = $VaultName; Location = 'swedencentral' }
}

function Remove-AzKeyVault {
    [CmdletBinding()]
    param([string]$VaultName, [string]$ResourceGroupName, [string]$Location, [switch]$InRemovedState, [switch]$Force)
    if ($InRemovedState) {
        Invoke-StubRemoval -Command 'Remove-AzKeyVault' -Name "purge:$VaultName"
        return
    }
    Invoke-StubRemoval -Command 'Remove-AzKeyVault' -Name $VaultName
}
'@

    # Runs the real script in a child process with the stubs shadowing the Az commands, and
    # returns the exit code it hands back together with the stub's call log.
    function Invoke-CleanupScript {
        param(
            [pscustomobject]$Stub,
            [string[]]$Fail = @(),
            [string[]]$Lookup = @(),
            [string[]]$ArgumentList = @('-Force', '-IncludeKeyVault'),
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
    $script:WhatIf   = Invoke-CleanupScript -Stub $script:Stub -ArgumentList '-WhatIf', '-IncludeKeyVault'
    $script:NotFound = Invoke-CleanupScript -Stub $script:Stub -Lookup @(
        'Get-AzVM:dev-skycraft-swc-auth-vm=notfound'
        'Get-AzDisk:dev-skycraft-swc-world-datadisk=rgnotfound'
    )
    # Every lookup fails: nothing is found, which must not read as "nothing to delete". The data
    # disk is not even looked up: its VM could not be.
    $script:LookupsFail = Invoke-CleanupScript -Stub $script:Stub -Lookup @(
        'Get-AzVM:dev-skycraft-swc-auth-vm=denied'
        'Get-AzVM:dev-skycraft-swc-world-vm=throttled'
        'Get-AzKeyVault:dev-skycraft-swc-kv=denied'
    )
    $script:AuthDenied   = Invoke-CleanupScript -Stub $script:Stub -Lookup 'Get-AzVM:dev-skycraft-swc-auth-vm=denied'
    $script:WorldDenied  = Invoke-CleanupScript -Stub $script:Stub -Lookup 'Get-AzVM:dev-skycraft-swc-world-vm=denied'
    $script:DiskDenied   = Invoke-CleanupScript -Stub $script:Stub -Lookup 'Get-AzDisk:dev-skycraft-swc-world-datadisk=denied'
    $script:RemovalsFail = Invoke-CleanupScript -Stub $script:Stub -Fail @(
        'Remove-AzVM:dev-skycraft-swc-world-vm'
        'Remove-AzKeyVault:dev-skycraft-swc-kv'
    )

    $script:AllRuns = @(
        $script:Clean, $script:Nothing, $script:WhatIf, $script:NotFound, $script:LookupsFail,
        $script:AuthDenied, $script:WorldDenied, $script:DiskDenied, $script:RemovalsFail
    )
}

AfterAll {
    if ($script:StubDir) { Remove-Item -LiteralPath $script:StubDir -Recurse -Force -ErrorAction SilentlyContinue }
}

Describe 'Lab 3.2 Remove-LabResource.ps1 - test harness' {

    It 'shadows the real Az commands instead of touching a subscription' {
        # Refused is the child exiting 99 before the script ran. Asserted on every scenario: a
        # refusal in one of them is a half-stubbed session, not a scenario-specific failure.
        foreach ($run in $script:AllRuns) {
            $run.Refused | Should -BeFalse -Because "the harness must never fall through to the real Az commands (exit $($run.ExitCode)): $($run.Output)"
        }
    }
}

Describe 'Lab 3.2 Remove-LabResource.ps1 - removes what the lab creates' {

    It 'exits 0 when every resource is found and removed' {
        $script:Clean.ExitCode | Should -Be 0 -Because "a clean teardown must report success; output was:`n$($script:Clean.Output)"
        $script:Clean.Output   | Should -Match 'Cleanup Complete'
        $script:Clean.Output   | Should -Not -Match '\[ERROR\]'
    }

    It 'removes both VMs, the data disk, and deletes and purges the Key Vault' {
        foreach ($call in 'Remove-AzVM:dev-skycraft-swc-auth-vm', 'Remove-AzVM:dev-skycraft-swc-world-vm',
            'Remove-AzDisk:dev-skycraft-swc-world-datadisk', 'Remove-AzKeyVault:dev-skycraft-swc-kv',
            'Remove-AzKeyVault:purge:dev-skycraft-swc-kv') {
            $script:Clean.Calls | Should -Contain $call
        }
    }
}

Describe 'Lab 3.2 Remove-LabResource.ps1 - an absent resource is not a failure' {

    It 'exits 0 and removes nothing when nothing is there' {
        $run = $script:Nothing
        $run.ExitCode | Should -Be 0 -Because "nothing to remove is a clean teardown; output was:`n$($run.Output)"
        $run.Output | Should -Not -Match '\[ERROR\]'
        $run.Output | Should -Match 'No Lab 3.2 resources found to delete'
        @($run.Calls | Where-Object { $_ -match '^Remove-' }) | Should -BeNullOrEmpty
    }

    It 'exits 0 when a getter reports its resource not found, and removes the rest' {
        $run = $script:NotFound
        $run.ExitCode | Should -Be 0 -Because "a not-found lookup means absent; output was:`n$($run.Output)"
        $run.Output | Should -Not -Match '\[ERROR\]'
        $run.Calls  | Should -Not -Contain 'Remove-AzVM:dev-skycraft-swc-auth-vm'
        $run.Calls  | Should -Not -Contain 'Remove-AzDisk:dev-skycraft-swc-world-datadisk'
        $run.Calls  | Should -Contain 'Remove-AzVM:dev-skycraft-swc-world-vm'
        $run.Calls  | Should -Contain 'Remove-AzKeyVault:dev-skycraft-swc-kv'
    }
}

Describe 'Lab 3.2 Remove-LabResource.ps1 - a failed lookup is not "absent" (#290)' {

    It 'exits 1, counts each failed lookup and carries the Azure error' {
        $run = $script:LookupsFail
        $run.ExitCode | Should -Be 1 -Because "a resource that may still exist must not look like a clean cleanup; output was:`n$($run.Output)"
        $run.Output | Should -Match '\[ERROR\] Could not look up VM dev-skycraft-swc-auth-vm[^\r\n]*does not have authorization'
        $run.Output | Should -Match '\[ERROR\] Could not look up VM dev-skycraft-swc-world-vm[^\r\n]*requests exceeded the limit'
        $run.Output | Should -Match '\[ERROR\] Could not look up Key Vault dev-skycraft-swc-kv'
        $run.Output | Should -Match 'Cleanup finished with 3 failure\(s\)'
        $run.Output | Should -Not -Match 'Cleanup Complete'
    }

    It 'does not report what it could not see as absent, and removes none of it' {
        $run = $script:LookupsFail
        $run.Output | Should -Not -Match 'No Lab 3.2 resources found'
        @($run.Calls | Where-Object { $_ -match '^Remove-' }) | Should -BeNullOrEmpty
    }

    It 'still removes the other resources when one VM could not be looked up' {
        $run = $script:AuthDenied
        $run.ExitCode | Should -Be 1 -Because "output was:`n$($run.Output)"
        $run.Output | Should -Match 'Cleanup finished with 1 failure\(s\)'
        $run.Calls  | Should -Not -Contain 'Remove-AzVM:dev-skycraft-swc-auth-vm'
        $run.Calls  | Should -Contain 'Remove-AzVM:dev-skycraft-swc-world-vm'
        $run.Calls  | Should -Contain 'Remove-AzDisk:dev-skycraft-swc-world-datadisk'
        $run.Calls  | Should -Contain 'Remove-AzKeyVault:dev-skycraft-swc-kv'
    }

    It 'leaves the data disk alone when the VM that holds it could not be looked up' {
        $run = $script:WorldDenied
        $run.ExitCode | Should -Be 1 -Because "output was:`n$($run.Output)"
        $run.Output | Should -Match '\[SKIP\] Disk dev-skycraft-swc-world-datadisk kept: VM dev-skycraft-swc-world-vm could not be looked up'
        $run.Output | Should -Match 'Cleanup finished with 1 failure\(s\)'
        $run.Calls  | Should -Not -Contain 'Get-AzDisk:dev-skycraft-swc-world-datadisk'
        $run.Calls  | Should -Not -Contain 'Remove-AzDisk:dev-skycraft-swc-world-datadisk'
        $run.Calls  | Should -Contain 'Remove-AzVM:dev-skycraft-swc-auth-vm'
        $run.Calls  | Should -Contain 'Remove-AzKeyVault:dev-skycraft-swc-kv'
    }

    It 'exits 1 when the data disk could not be looked up, and still removes the VMs' {
        $run = $script:DiskDenied
        $run.ExitCode | Should -Be 1 -Because "output was:`n$($run.Output)"
        $run.Output | Should -Match '\[ERROR\] Could not look up disk dev-skycraft-swc-world-datadisk[^\r\n]*does not have authorization'
        $run.Output | Should -Match 'Cleanup finished with 1 failure\(s\)'
        $run.Calls  | Should -Not -Contain 'Remove-AzDisk:dev-skycraft-swc-world-datadisk'
        $run.Calls  | Should -Contain 'Remove-AzVM:dev-skycraft-swc-world-vm'
    }
}

Describe 'Lab 3.2 Remove-LabResource.ps1 - a failed deletion is counted' {

    It 'exits 1 and counts each deletion that failed' {
        $run = $script:RemovalsFail
        $run.ExitCode | Should -Be 1 -Because "a stuck resource must not look like a clean cleanup; output was:`n$($run.Output)"
        $run.Output | Should -Match '\[ERROR\] Could not delete VM dev-skycraft-swc-world-vm: stub failure'
        $run.Output | Should -Match '\[ERROR\] Could not delete Key Vault dev-skycraft-swc-kv: stub failure'
        $run.Output | Should -Match 'Cleanup finished with 2 failure\(s\)'
        $run.Output | Should -Not -Match 'Cleanup Complete'
    }

    It 'keeps going after a failed deletion, and does not purge a vault it could not delete' {
        $run = $script:RemovalsFail
        $run.Calls | Should -Contain 'Remove-AzVM:dev-skycraft-swc-auth-vm'
        $run.Calls | Should -Contain 'Remove-AzDisk:dev-skycraft-swc-world-datadisk'
        $run.Calls | Should -Not -Contain 'Remove-AzKeyVault:purge:dev-skycraft-swc-kv'
    }
}

Describe 'Lab 3.2 Remove-LabResource.ps1 - -WhatIf' {

    It 'looks everything up and removes nothing' {
        $run = $script:WhatIf
        $run.ExitCode | Should -Be 0 -Because "output was:`n$($run.Output)"
        @($run.Calls | Where-Object { $_ -match '^Remove-' }) | Should -BeNullOrEmpty
        $run.Calls  | Should -Contain 'Get-AzVM:dev-skycraft-swc-auth-vm'
        $run.Calls  | Should -Contain 'Get-AzKeyVault:dev-skycraft-swc-kv'
        $run.Output | Should -Match 'What if: .*dev-skycraft-swc-world-vm'
    }
}
