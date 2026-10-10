<#
.SYNOPSIS
    Pester 5 tests for the Lab 3.3 cleanup script's failure reporting and exit code.

.DESCRIPTION
    Found by the #121 live pass: after the 24-minute Container Apps environment delete, the
    container instance and registry deletes both threw, the script printed
    "[INFO] Not found or already deleted." for each, ended with "Cleanup Complete." and exited
    0 - while both resources were still standing in the resource group. Every catch in the
    script treated any error as absence, and the two generic ARM deletes ran with
    -ErrorAction SilentlyContinue, so nothing a delete could do was visible to the caller.

    Issue #290: the lookups still ran with -ErrorAction SilentlyContinue, so a lookup that failed
    (a 403, throttling) read as "Not found - nothing to delete." and the run exited 0 while the
    resource still stood.

    These tests run the real Remove-LabResource.ps1 in a child pwsh against a generated stub
    module and assert the observable contract, the way Lab 5.2's suite does (#105):
      1. A clean run exits 0; a run in which nothing exists exits 0, and so does one whose
         getter reports a resource not found.
      2. A resource that exists but cannot be deleted is reported as [ERROR] with the message,
         counted, and the script exits 1 without claiming completion.
      3. A lookup that fails is an [ERROR], counted, and the script exits 1 without touching or
         reporting absent the resource it could not see. The Container Apps environment stays
         when its app could not be looked up or deleted. The stub reports the failure with Write-Error, as
         the Az getters do, so a script that passes -ErrorAction SilentlyContinue swallows it.
      4. A failure does not stop the later steps.
      5. -Environment and the name overrides reach the delete calls; -WhatIf deletes nothing.
    Which errors mean "not found" is pinned for every cleanup that carries the helpers by
    tests/Lab-Cleanup-Lookup.Tests.ps1.
    No Azure connection is needed, and none is used: the script runs through
    tests/Support/LabScriptStub.psm1 (#112), which aborts the child with exit 99 unless every
    stubbed command resolves to the stub.

.EXAMPLE
    Invoke-Pester -Path .\Remove-LabResource.Tests.ps1

.NOTES
    Project: SkyCraft
    Lab: 3.3 - Containers
#>

#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..' '..' '..' 'tests' 'Support' 'LabScriptStub.psm1') -Force

    $script:ScriptPath      = (Resolve-Path (Join-Path $PSScriptRoot '..' 'scripts' 'Remove-LabResource.ps1')).Path
    $script:StubModuleName  = 'SkyCraftAzStub33'
    # Exactly the script's '#Requires -Modules' line: these are imported for real before the stub.
    $script:RequiredModules = @('Az.Accounts', 'Az.Resources', 'Az.ContainerInstance', 'Az.ContainerRegistry')
    $script:StubCommands    = @(
        'Get-AzContext'
        'Get-AzResource'
        'Remove-AzResource'
        'Remove-AzContainerGroup'
        'Remove-AzContainerRegistry'
    )

    # Every Az command the script calls, as a stub that records its own invocation (with the
    # name it was handed) and optionally throws. Driven by environment variables so one
    # generated module serves every scenario:
    #   SKYCRAFT_STUB_EMPTY   '1' leaves nothing to find: Get-AzResource returns nothing
    #   SKYCRAFT_STUB_LOOKUP  'Get-AzResource:<name>=<kind>,...' makes one lookup fail (denied,
    #                         throttled) or report its resource not found (notfound)
    #   SKYCRAFT_STUB_FAIL    '<Remove-command>,...' makes every call of that removal throw
    $script:StubBody = @'
$script:LogPath = $env:SKYCRAFT_STUB_LOG

function Write-StubCall {
    param([string]$Name)
    if ($script:LogPath) { Add-Content -LiteralPath $script:LogPath -Value $Name }
}

function Invoke-StubGate {
    param([string]$Name, [string]$Target)
    Write-StubCall -Name "$Name $Target"
    if (@($env:SKYCRAFT_STUB_FAIL -split ',') -contains $Name) { throw "stub failure: $Name $Target" }
}

function Test-StubEmpty { return $env:SKYCRAFT_STUB_EMPTY -eq '1' }

function Get-AzContext {
    [CmdletBinding()]
    param()
    [pscustomobject]@{ Name = 'stub-context' }
}

# How the lookup named here fails, if at all. The failure is reported with Write-Error, as the
# Az getters do, so the caller's -ErrorAction decides what happens to it. Returns $true when the
# lookup failed, so the stub returns nothing after it.
function Invoke-StubLookup {
    param([string]$Name, [string]$ResourceGroup)
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
            Write-Error -ErrorId 'ResourceNotFound' -Message "The Resource 'Microsoft.App/stubs/$(($Name -split ':')[-1])' under resource group '$ResourceGroup' was not found. For more details please go to https://aka.ms/ARMResourceNotFoundFix"
            return $true
        }
    }
    return $false
}

function Get-AzResource {
    [CmdletBinding()]
    param($ResourceGroupName, $ResourceType, $Name)
    Write-StubCall -Name "Get-AzResource $Name"
    if (Invoke-StubLookup -Name "Get-AzResource:$Name" -ResourceGroup $ResourceGroupName) { return }
    if (Test-StubEmpty) { return }
    [pscustomobject]@{
        Name         = $Name
        ResourceType = $ResourceType
        ResourceId   = "/subscriptions/0/resourceGroups/$ResourceGroupName/providers/$ResourceType/$Name"
    }
}

function Remove-AzResource {
    [CmdletBinding()]
    param($ResourceId, [switch]$Force)
    Invoke-StubGate -Name 'Remove-AzResource' -Target (($ResourceId -split '/')[-1])
}

function Remove-AzContainerGroup {
    [CmdletBinding()]
    param($Name, $ResourceGroupName)
    Invoke-StubGate -Name 'Remove-AzContainerGroup' -Target $Name
}

function Remove-AzContainerRegistry {
    [CmdletBinding()]
    param($Name, $ResourceGroupName)
    Invoke-StubGate -Name 'Remove-AzContainerRegistry' -Target $Name
}
'@

    function Invoke-CleanupScript {
        param(
            [pscustomobject]$Stub,
            [string[]]$Fail = @(),
            [string[]]$Lookup = @(),
            [string[]]$Arguments = @('-Force'),
            [switch]$Empty
        )

        $logPath = Join-Path $Stub.Directory 'calls.log'
        Remove-Item -LiteralPath $logPath -Force -ErrorAction SilentlyContinue

        $run = Invoke-LabScriptWithStub -Stub $Stub -ScriptPath $script:ScriptPath -ArgumentList $Arguments -Environment @{
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
    $script:AciStuck = Invoke-CleanupScript -Stub $script:Stub -Fail 'Remove-AzContainerGroup'
    $script:TwoStuck = Invoke-CleanupScript -Stub $script:Stub -Fail 'Remove-AzResource', 'Remove-AzContainerRegistry'
    $script:Prod     = Invoke-CleanupScript -Stub $script:Stub -Arguments '-Force', '-Environment', 'prod', '-AcaName', 'prod-skycraft-swc-aca-world-02'
    $script:WhatIf   = Invoke-CleanupScript -Stub $script:Stub -Arguments '-WhatIf'
    $script:NotFound = Invoke-CleanupScript -Stub $script:Stub -Lookup 'Get-AzResource:dev-skycraft-swc-aci-auth=notfound'
    $script:LookupsFail = Invoke-CleanupScript -Stub $script:Stub -Lookup @(
        'Get-AzResource:dev-skycraft-swc-aci-auth=denied'
        'Get-AzResource:devskycraftswcacr01=throttled'
    )
    $script:AppDenied = Invoke-CleanupScript -Stub $script:Stub -Lookup 'Get-AzResource:dev-skycraft-swc-aca-world=denied'

    $script:AllRuns = @(
        $script:Clean, $script:Nothing, $script:AciStuck, $script:TwoStuck, $script:Prod, $script:WhatIf,
        $script:NotFound, $script:LookupsFail, $script:AppDenied
    )
}

AfterAll {
    if ($script:StubDir) { Remove-Item -LiteralPath $script:StubDir -Recurse -Force -ErrorAction SilentlyContinue }
}

Describe 'Lab 3.3 Remove-LabResource.ps1 - test harness' {

    It 'shadows the real Az cmdlets instead of touching Azure' {
        foreach ($run in $script:AllRuns) {
            $run.Refused | Should -BeFalse -Because "the harness must never fall through to the real Az cmdlets (exit $($run.ExitCode)): $($run.Output)"
        }
    }
}

Describe 'Lab 3.3 Remove-LabResource.ps1 - exit code contract' {

    It 'exits 0 when every step succeeds' {
        $script:Clean.ExitCode | Should -Be 0 -Because "a clean teardown must report success; output was:`n$($script:Clean.Output)"
        $script:Clean.Output   | Should -Match 'Cleanup Complete'
        $script:Clean.Output   | Should -Not -Match '\[ERROR\]'
    }

    It 'exits 0 when there is nothing to delete, and says so' {
        $script:Nothing.ExitCode | Should -Be 0
        $script:Nothing.Output   | Should -Match 'Not found'
        $script:Nothing.Calls    | Should -Not -Match '^Remove-'
    }

    It 'exits 1 when a resource exists but cannot be deleted' {
        $script:AciStuck.ExitCode | Should -Be 1 -Because "a stuck resource must not look like a clean cleanup; output was:`n$($script:AciStuck.Output)"
        $script:AciStuck.Output   | Should -Match '\[ERROR\] Could not delete Container Instance ''dev-skycraft-swc-aci-auth'': stub failure'
        $script:AciStuck.Output   | Should -Match 'Cleanup finished with 1 failure\(s\)'
        $script:AciStuck.Output   | Should -Not -Match 'Cleanup Complete'
        $script:AciStuck.Output   | Should -Not -Match 'Not found or already deleted'
    }

    It 'counts every failed step rather than stopping at the first' {
        # Remove-AzResource fails for the app, which keeps its environment; the registry fails too.
        $script:TwoStuck.ExitCode | Should -Be 1
        $script:TwoStuck.Output   | Should -Match 'Cleanup finished with 2 failure\(s\)'
    }

    It 'keeps the Container Apps environment when its app could not be deleted, counted once' {
        $run = $script:TwoStuck
        $run.Output | Should -Match "\[ERROR\] Could not delete Container App 'dev-skycraft-swc-aca-world': stub failure"
        $run.Output | Should -Match 'Kept: the Container App could not be deleted and may still be in it'
        $run.Calls  | Should -Not -Contain 'Remove-AzResource dev-skycraft-swc-cae-02'
        $run.Calls  | Should -Contain 'Remove-AzContainerGroup dev-skycraft-swc-aci-auth'
    }

    It 'keeps running the later steps after a failure' {
        $script:AciStuck.Calls | Should -Contain 'Remove-AzContainerRegistry devskycraftswcacr01'
    }

    It 'exits 0 when a getter reports its resource not found, and deletes the rest' {
        $run = $script:NotFound
        $run.ExitCode | Should -Be 0 -Because "a not-found lookup means absent; output was:`n$($run.Output)"
        $run.Output   | Should -Not -Match '\[ERROR\]'
        $run.Calls    | Should -Not -Contain 'Remove-AzContainerGroup dev-skycraft-swc-aci-auth'
        $run.Calls    | Should -Contain 'Remove-AzContainerRegistry devskycraftswcacr01'
    }
}

Describe 'Lab 3.3 Remove-LabResource.ps1 - a failed lookup is not "absent" (#290)' {

    It 'exits 1, counts each failed lookup and carries the Azure error' {
        $run = $script:LookupsFail
        $run.ExitCode | Should -Be 1 -Because "a resource that may still exist must not look like a clean cleanup; output was:`n$($run.Output)"
        $run.Output   | Should -Match "\[ERROR\] Could not look up Container Instance 'dev-skycraft-swc-aci-auth'[^\r\n]*does not have authorization"
        $run.Output   | Should -Match "\[ERROR\] Could not look up Container Registry 'devskycraftswcacr01'[^\r\n]*requests exceeded the limit"
        $run.Output   | Should -Match 'Cleanup finished with 2 failure\(s\)'
        $run.Output   | Should -Not -Match 'Cleanup Complete'
    }

    It 'does not report what it could not see as absent, and deletes none of it' {
        $run = $script:LookupsFail
        $run.Output | Should -Not -Match 'Not found'
        $run.Calls  | Should -Not -Contain 'Remove-AzContainerGroup dev-skycraft-swc-aci-auth'
        $run.Calls  | Should -Not -Contain 'Remove-AzContainerRegistry devskycraftswcacr01'
    }

    It 'still deletes the resources it could look up' {
        $script:LookupsFail.Calls | Should -Contain 'Remove-AzResource dev-skycraft-swc-aca-world'
        $script:LookupsFail.Calls | Should -Contain 'Remove-AzResource dev-skycraft-swc-cae-02'
    }

    It 'keeps the Container Apps environment when its app could not be looked up' {
        $run = $script:AppDenied
        $run.ExitCode | Should -Be 1 -Because "output was:`n$($run.Output)"
        $run.Output   | Should -Match 'Cleanup finished with 1 failure\(s\)'
        $run.Output   | Should -Match 'Kept: the Container App could not be looked up'
        $run.Calls    | Should -Not -Contain 'Get-AzResource dev-skycraft-swc-cae-02'
        $run.Calls    | Should -Not -Contain 'Remove-AzResource dev-skycraft-swc-cae-02'
        $run.Calls    | Should -Contain 'Remove-AzContainerGroup dev-skycraft-swc-aci-auth'
        $run.Calls    | Should -Contain 'Remove-AzContainerRegistry devskycraftswcacr01'
    }
}

Describe 'Lab 3.3 Remove-LabResource.ps1 - -WhatIf' {

    It 'deletes nothing and exits 0' {
        $run = $script:WhatIf
        $run.ExitCode | Should -Be 0 -Because "output was:`n$($run.Output)"
        $run.Calls    | Should -Not -Match '^Remove-'
        $run.Output   | Should -Match 'What if: .*dev-skycraft-swc-cae-02'
    }
}

Describe 'Lab 3.3 Remove-LabResource.ps1 - names follow -Environment and the overrides' {

    It 'deletes the dev names by default' {
        $script:Clean.Calls | Should -Contain 'Remove-AzResource dev-skycraft-swc-aca-world'
        $script:Clean.Calls | Should -Contain 'Remove-AzResource dev-skycraft-swc-cae-02'
        $script:Clean.Calls | Should -Contain 'Remove-AzContainerGroup dev-skycraft-swc-aci-auth'
        $script:Clean.Calls | Should -Contain 'Remove-AzContainerRegistry devskycraftswcacr01'
    }

    It 'deletes the prod names with -Environment prod, honouring an -AcaName override' {
        $script:Prod.ExitCode | Should -Be 0
        $script:Prod.Calls | Should -Contain 'Remove-AzResource prod-skycraft-swc-aca-world-02'
        $script:Prod.Calls | Should -Contain 'Remove-AzResource prod-skycraft-swc-cae-02'
        $script:Prod.Calls | Should -Contain 'Remove-AzContainerGroup prod-skycraft-swc-aci-auth'
        $script:Prod.Calls | Should -Contain 'Remove-AzContainerRegistry prodskycraftswcacr01'
    }

    It 'deletes the app before its environment' {
        $app = [array]::IndexOf($script:Clean.Calls, 'Remove-AzResource dev-skycraft-swc-aca-world')
        $env = [array]::IndexOf($script:Clean.Calls, 'Remove-AzResource dev-skycraft-swc-cae-02')
        $app | Should -BeLessThan $env
    }
}
