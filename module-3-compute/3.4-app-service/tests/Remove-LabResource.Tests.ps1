<#
.SYNOPSIS
    Pester 5 tests for the Lab 3.4 cleanup: when it reports a resource absent, when it keeps the
    App Service Plan, and when it exits 1.

.DESCRIPTION
    Regression cover for issue #290. The cleanup looked the Web App, its slots, the autoscale
    setting, the plan and the VNet up with -ErrorAction SilentlyContinue, so a lookup that failed
    (a 403, throttling) read as "not found". A Web App it could not see was "not found - nothing to
    detach", and the plan was then deleted with that app - and its VNet integration - possibly
    still on it, which can orphan a serviceAssociationLink on the subnet. These tests run the real
    Remove-LabResource.ps1 in a child pwsh process against a generated stub of the Az commands it
    calls, and assert the observable contract:

      1. Everything the lab creates is detached and removed when it is present, and the run
         exits 0.
      2. A resource that is absent - a getter that reports it not found - is not a failure: the
         run exits 0.
      3. A lookup that fails with an error is an [ERROR], counted, and the run exits 1 without
         touching or reporting absent the resource it could not see. The stub reports the failure
         with Write-Error, as the Az getters do, so a script that passes -ErrorAction
         SilentlyContinue swallows it.
      4. The plan stays when the Web App or its slots could not be looked up, or the Web App could
         not be deleted; the Web App stays when its slots could not be listed.
      5. A deletion that fails is an [ERROR], counted, and the later steps still run: exit 1.
      6. The subnet checks stay diagnostic: a VNet they cannot read is a [WARN], not a failure.

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
    Lab: 3.4 - App Service
#>

#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..' '..' '..' 'tests' 'Support' 'LabScriptStub.psm1') -Force

    $script:ScriptPath     = (Resolve-Path (Join-Path $PSScriptRoot '..' 'scripts' 'Remove-LabResource.ps1')).Path
    $script:StubModuleName = 'SkyCraftLab34CleanupStub'
    # Exactly the script's '#Requires -Modules' line: these are imported for real before the stub.
    $script:RequiredModules = @('Az.Accounts', 'Az.Websites', 'Az.Monitor', 'Az.Network')

    $script:StubCommands = @(
        'Get-AzContext'
        'Get-AzVirtualNetwork'
        'Get-AzWebApp'
        'Get-AzWebAppSlot'
        'Remove-AzWebApp'
        'Invoke-AzRestMethod'
        'Get-AzAutoscaleSetting'
        'Remove-AzAutoscaleSetting'
        'Get-AzAppServicePlan'
        'Remove-AzAppServicePlan'
        'Start-Sleep'
    )

    # Every command the script calls, recording its own invocation. By default the resource group
    # holds everything the lab creates: the Web App with one deployment slot, the autoscale
    # setting, the plan, and the VNet whose integration subnet carries no links. The integration
    # DELETE answers 200 and the verification GET 404 (detached). Environment variables change
    # that, so one generated module serves every scenario:
    #   SKYCRAFT_STUB_EMPTY   '1' leaves nothing to find: every getter reports ResourceNotFound,
    #                         as the real ones do for a name that does not exist
    #   SKYCRAFT_STUB_LOOKUP  '<lookup>=<kind>,...' makes one lookup fail (denied, throttled) or
    #                         report its resource not found (notfound)
    #   SKYCRAFT_STUB_FAIL    '<Remove-command>:<name>,...' makes one removal throw
    # A lookup is named after its command and the resource it reads: 'Get-AzWebApp:<app>',
    # 'Get-AzWebAppSlot:<app>', 'Get-AzAutoscaleSetting:<name>', 'Get-AzAppServicePlan:<plan>',
    # 'Get-AzVirtualNetwork:<vnet>'. A REST call is logged as 'Invoke-AzRestMethod:<method>:<path>'.
    $script:StubBody = @'
$script:LogPath = $env:SKYCRAFT_STUB_LOG
$script:SiteId  = '/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/dev-skycraft-swc-rg/providers/Microsoft.Web/sites/dev-skycraft-swc-app01'

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
            Write-Error -ErrorId 'ResourceNotFound' -Message "The Resource 'Microsoft.Web/stubs/$(($Name -split ':')[-1])' under resource group '$ResourceGroup' was not found. For more details please go to https://aka.ms/ARMResourceNotFoundFix"
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

function Get-AzVirtualNetwork {
    [CmdletBinding()]
    param([string]$Name, [string]$ResourceGroupName)
    if (Invoke-StubLookup -Name "Get-AzVirtualNetwork:$Name" -ResourceGroup $ResourceGroupName -Named) { return }
    [pscustomobject]@{
        Name    = $Name
        Subnets = @([pscustomobject]@{ Name = 'AppServiceSubnet'; ServiceAssociationLinks = @() })
    }
}

function Get-AzWebApp {
    [CmdletBinding()]
    param([string]$ResourceGroupName, [string]$Name)
    if (Invoke-StubLookup -Name "Get-AzWebApp:$Name" -ResourceGroup $ResourceGroupName -Named) { return }
    [pscustomobject]@{ Name = $Name; Id = $script:SiteId }
}

function Get-AzWebAppSlot {
    [CmdletBinding()]
    param([string]$ResourceGroupName, [string]$Name)
    if (Invoke-StubLookup -Name "Get-AzWebAppSlot:$Name" -ResourceGroup $ResourceGroupName) { return }
    [pscustomobject]@{ Name = "$Name/staging"; Id = "$script:SiteId/slots/staging" }
}

function Remove-AzWebApp {
    [CmdletBinding()]
    param([string]$ResourceGroupName, [string]$Name, [switch]$Force)
    Invoke-StubRemoval -Command 'Remove-AzWebApp' -Name $Name
}

function Invoke-AzRestMethod {
    [CmdletBinding()]
    param([string]$Method, [string]$Path)
    Write-StubCall -Name "Invoke-AzRestMethod:${Method}:$(($Path -split '\?')[0])"
    if ($Method -eq 'DELETE') { return [pscustomobject]@{ StatusCode = 200; Content = '' } }
    [pscustomobject]@{ StatusCode = 404; Content = '' }
}

function Get-AzAutoscaleSetting {
    [CmdletBinding()]
    param([string]$ResourceGroupName, [string]$Name)
    if (Invoke-StubLookup -Name "Get-AzAutoscaleSetting:$Name" -ResourceGroup $ResourceGroupName -Named) { return }
    [pscustomobject]@{ Name = $Name }
}

function Remove-AzAutoscaleSetting {
    [CmdletBinding()]
    param([string]$ResourceGroupName, [string]$Name)
    Invoke-StubRemoval -Command 'Remove-AzAutoscaleSetting' -Name $Name
}

function Get-AzAppServicePlan {
    [CmdletBinding()]
    param([string]$ResourceGroupName, [string]$Name)
    if (Invoke-StubLookup -Name "Get-AzAppServicePlan:$Name" -ResourceGroup $ResourceGroupName -Named) { return }
    [pscustomobject]@{ Name = $Name }
}

function Remove-AzAppServicePlan {
    [CmdletBinding()]
    param([string]$ResourceGroupName, [string]$Name, [switch]$Force)
    Invoke-StubRemoval -Command 'Remove-AzAppServicePlan' -Name $Name
}

function Start-Sleep {
    [CmdletBinding()]
    param([int]$Seconds)
    Write-StubCall -Name "Start-Sleep:$Seconds"
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
    $script:Clean       = Invoke-CleanupScript -Stub $script:Stub
    $script:Nothing     = Invoke-CleanupScript -Stub $script:Stub -Empty
    $script:WhatIf      = Invoke-CleanupScript -Stub $script:Stub -ArgumentList '-WhatIf'
    $script:NotFound    = Invoke-CleanupScript -Stub $script:Stub -Lookup 'Get-AzAutoscaleSetting:dev-skycraft-swc-asp-autoscale=notfound'
    $script:AppDenied   = Invoke-CleanupScript -Stub $script:Stub -Lookup 'Get-AzWebApp:dev-skycraft-swc-app01=denied'
    $script:SlotsDenied = Invoke-CleanupScript -Stub $script:Stub -Lookup 'Get-AzWebAppSlot:dev-skycraft-swc-app01=throttled'
    $script:LookupsFail = Invoke-CleanupScript -Stub $script:Stub -Lookup @(
        'Get-AzAutoscaleSetting:dev-skycraft-swc-asp-autoscale=denied'
        'Get-AzAppServicePlan:dev-skycraft-swc-asp=throttled'
    )
    $script:VnetDenied  = Invoke-CleanupScript -Stub $script:Stub -Lookup 'Get-AzVirtualNetwork:dev-skycraft-swc-vnet=denied'
    $script:AppStuck    = Invoke-CleanupScript -Stub $script:Stub -Fail 'Remove-AzWebApp:dev-skycraft-swc-app01'
    $script:RemovalsFail = Invoke-CleanupScript -Stub $script:Stub -Fail @(
        'Remove-AzAutoscaleSetting:dev-skycraft-swc-asp-autoscale'
        'Remove-AzAppServicePlan:dev-skycraft-swc-asp'
    )

    $script:AllRuns = @(
        $script:Clean, $script:Nothing, $script:WhatIf, $script:NotFound, $script:AppDenied, $script:SlotsDenied,
        $script:LookupsFail, $script:VnetDenied, $script:AppStuck, $script:RemovalsFail
    )
}

AfterAll {
    if ($script:StubDir) { Remove-Item -LiteralPath $script:StubDir -Recurse -Force -ErrorAction SilentlyContinue }
}

Describe 'Lab 3.4 Remove-LabResource.ps1 - test harness' {

    It 'shadows the real Az commands instead of touching a subscription' {
        # Refused is the child exiting 99 before the script ran. Asserted on every scenario: a
        # refusal in one of them is a half-stubbed session, not a scenario-specific failure.
        foreach ($run in $script:AllRuns) {
            $run.Refused | Should -BeFalse -Because "the harness must never fall through to the real Az commands (exit $($run.ExitCode)): $($run.Output)"
        }
    }
}

Describe 'Lab 3.4 Remove-LabResource.ps1 - removes what the lab creates' {

    It 'exits 0 when every resource is found and removed' {
        $script:Clean.ExitCode | Should -Be 0 -Because "a clean teardown must report success; output was:`n$($script:Clean.Output)"
        $script:Clean.Output   | Should -Match 'Cleanup completed successfully'
        $script:Clean.Output   | Should -Not -Match '\[ERROR\]'
    }

    It 'detaches the integration from the app and its slot before deleting the app, the autoscale setting and the plan' {
        $calls = $script:Clean.Calls
        $siteId = '/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/dev-skycraft-swc-rg/providers/Microsoft.Web/sites/dev-skycraft-swc-app01'
        $calls | Should -Contain "Invoke-AzRestMethod:DELETE:$siteId/networkConfig/virtualNetwork"
        $calls | Should -Contain "Invoke-AzRestMethod:DELETE:$siteId/slots/staging/networkConfig/virtualNetwork"
        foreach ($call in 'Remove-AzWebApp:dev-skycraft-swc-app01', 'Remove-AzAutoscaleSetting:dev-skycraft-swc-asp-autoscale',
            'Remove-AzAppServicePlan:dev-skycraft-swc-asp') {
            $calls | Should -Contain $call
        }
        [array]::IndexOf($calls, "Invoke-AzRestMethod:DELETE:$siteId/networkConfig/virtualNetwork") |
            Should -BeLessThan ([array]::IndexOf($calls, 'Remove-AzWebApp:dev-skycraft-swc-app01'))
        [array]::IndexOf($calls, 'Remove-AzWebApp:dev-skycraft-swc-app01') |
            Should -BeLessThan ([array]::IndexOf($calls, 'Remove-AzAppServicePlan:dev-skycraft-swc-asp'))
    }
}

Describe 'Lab 3.4 Remove-LabResource.ps1 - an absent resource is not a failure' {

    It 'exits 0 and removes nothing when nothing is there' {
        $run = $script:Nothing
        $run.ExitCode | Should -Be 0 -Because "nothing to remove is a clean teardown; output was:`n$($run.Output)"
        $run.Output | Should -Not -Match '\[ERROR\]'
        $run.Output | Should -Match "Web App 'dev-skycraft-swc-app01' not found - nothing to detach"
        $run.Output | Should -Match 'Not found or already deleted'
        @($run.Calls | Where-Object { $_ -match '^Remove-|:DELETE:' }) | Should -BeNullOrEmpty
    }

    It 'exits 0 when a getter reports its resource not found, and removes the rest' {
        $run = $script:NotFound
        $run.ExitCode | Should -Be 0 -Because "a not-found lookup means absent; output was:`n$($run.Output)"
        $run.Output | Should -Not -Match '\[ERROR\]'
        $run.Calls  | Should -Not -Contain 'Remove-AzAutoscaleSetting:dev-skycraft-swc-asp-autoscale'
        $run.Calls  | Should -Contain 'Remove-AzAppServicePlan:dev-skycraft-swc-asp'
    }
}

Describe 'Lab 3.4 Remove-LabResource.ps1 - a failed lookup is not "absent" (#290)' {

    It 'exits 1 when the Web App could not be looked up, without reporting it absent' {
        $run = $script:AppDenied
        $run.ExitCode | Should -Be 1 -Because "an app that may still exist must not look like a clean cleanup; output was:`n$($run.Output)"
        $run.Output | Should -Match "\[ERROR\] Could not look up Web App 'dev-skycraft-swc-app01'[^\r\n]*does not have authorization"
        $run.Output | Should -Match 'Cleanup finished with 1 failure\(s\)'
        $run.Output | Should -Not -Match 'nothing to detach'
        $run.Output | Should -Not -Match 'Cleanup completed successfully'
    }

    It 'keeps the App Service Plan when the Web App on it could not be looked up' {
        $run = $script:AppDenied
        $run.Output | Should -Match "Keeping App Service Plan 'dev-skycraft-swc-asp': Web App 'dev-skycraft-swc-app01' could not be looked up"
        $run.Calls  | Should -Not -Contain 'Get-AzAppServicePlan:dev-skycraft-swc-asp'
        $run.Calls  | Should -Not -Contain 'Remove-AzAppServicePlan:dev-skycraft-swc-asp'
        # The autoscale setting does not hold an app; it still goes.
        $run.Calls  | Should -Contain 'Remove-AzAutoscaleSetting:dev-skycraft-swc-asp-autoscale'
    }

    It 'keeps the Web App and the plan when the deployment slots could not be listed' {
        $run = $script:SlotsDenied
        $run.ExitCode | Should -Be 1 -Because "output was:`n$($run.Output)"
        $run.Output | Should -Match "\[ERROR\] Could not look up the deployment slots of 'dev-skycraft-swc-app01'"
        $run.Output | Should -Match 'Cleanup finished with 1 failure\(s\)'
        $run.Output | Should -Match "Keeping Web App 'dev-skycraft-swc-app01'"
        $run.Output | Should -Match "Keeping App Service Plan 'dev-skycraft-swc-asp'"
        $run.Calls  | Should -Not -Contain 'Remove-AzWebApp:dev-skycraft-swc-app01'
        $run.Calls  | Should -Not -Contain 'Remove-AzAppServicePlan:dev-skycraft-swc-asp'
    }

    It 'exits 1 when the autoscale setting and the plan could not be looked up, and removes neither' {
        $run = $script:LookupsFail
        $run.ExitCode | Should -Be 1 -Because "output was:`n$($run.Output)"
        $run.Output | Should -Match "\[ERROR\] Could not look up autoscale setting 'dev-skycraft-swc-asp-autoscale'"
        $run.Output | Should -Match "\[ERROR\] Could not look up App Service Plan 'dev-skycraft-swc-asp'[^\r\n]*requests exceeded the limit"
        $run.Output | Should -Match 'Cleanup finished with 2 failure\(s\)'
        $run.Output | Should -Not -Match 'Not found or already deleted'
        $run.Calls  | Should -Not -Contain 'Remove-AzAutoscaleSetting:dev-skycraft-swc-asp-autoscale'
        $run.Calls  | Should -Not -Contain 'Remove-AzAppServicePlan:dev-skycraft-swc-asp'
        $run.Calls  | Should -Contain 'Remove-AzWebApp:dev-skycraft-swc-app01'
    }

    It 'reports a VNet it cannot read as a warning, not a failure: the subnet checks are diagnostic' {
        $run = $script:VnetDenied
        $run.ExitCode | Should -Be 0 -Because "output was:`n$($run.Output)"
        $run.Output | Should -Match "\[WARN\] VNet 'dev-skycraft-swc-vnet' could not be read"
        $run.Output | Should -Not -Match '\[ERROR\]'
        $run.Calls  | Should -Contain 'Remove-AzAppServicePlan:dev-skycraft-swc-asp'
    }
}

Describe 'Lab 3.4 Remove-LabResource.ps1 - a failed deletion is counted' {

    It 'keeps the plan when the Web App could not be deleted, and still removes the autoscale setting' {
        $run = $script:AppStuck
        $run.ExitCode | Should -Be 1 -Because "output was:`n$($run.Output)"
        $run.Output | Should -Match "\[ERROR\] Could not delete Web App 'dev-skycraft-swc-app01': stub failure"
        $run.Output | Should -Match "Keeping App Service Plan 'dev-skycraft-swc-asp': Web App 'dev-skycraft-swc-app01' could not be deleted"
        $run.Output | Should -Match 'Cleanup finished with 1 failure\(s\)'
        $run.Calls  | Should -Not -Contain 'Remove-AzAppServicePlan:dev-skycraft-swc-asp'
        $run.Calls  | Should -Contain 'Remove-AzAutoscaleSetting:dev-skycraft-swc-asp-autoscale'
    }

    It 'exits 1 and counts each deletion that failed, running the later steps' {
        $run = $script:RemovalsFail
        $run.ExitCode | Should -Be 1 -Because "output was:`n$($run.Output)"
        $run.Output | Should -Match "\[ERROR\] Could not delete autoscale setting 'dev-skycraft-swc-asp-autoscale': stub failure"
        $run.Output | Should -Match "\[ERROR\] Could not delete App Service Plan 'dev-skycraft-swc-asp': stub failure"
        $run.Output | Should -Match 'Cleanup finished with 2 failure\(s\)'
        $run.Output | Should -Not -Match 'Cleanup completed successfully'
        $run.Calls  | Should -Contain 'Remove-AzAppServicePlan:dev-skycraft-swc-asp'
    }
}

Describe 'Lab 3.4 Remove-LabResource.ps1 - -WhatIf' {

    It 'looks the Web App up and detaches or removes nothing' {
        $run = $script:WhatIf
        $run.ExitCode | Should -Be 0 -Because "output was:`n$($run.Output)"
        @($run.Calls | Where-Object { $_ -match '^Remove-|:DELETE:' }) | Should -BeNullOrEmpty
        $run.Calls  | Should -Contain 'Get-AzWebApp:dev-skycraft-swc-app01'
        $run.Output | Should -Match 'What if: .*dev-skycraft-swc-asp'
    }
}
