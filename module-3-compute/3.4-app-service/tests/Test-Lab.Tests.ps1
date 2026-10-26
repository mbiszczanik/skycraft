<#
.SYNOPSIS
    Pester 5 tests: the Lab 3.4 validator finds the plan's autoscale setting by what it scales.

.DESCRIPTION
    Regression cover for issue #355. Test-Lab.ps1 looked the autoscale setting up under the name
    the Bicep gives it, '<plan>-autoscale'. The Portal names it '<plan>-Autoscale-<n>', so a
    learner who followed the guide failed "Autoscale setting ... not found!". These tests run the
    real Test-Lab.ps1 in a child pwsh against a generated stub of the Az commands it calls, and
    assert that:

      1. A setting the Bicep made and a setting the Portal made (another name, the target id in
         other casing) both pass, and the output names the setting it found.
      2. A setting with the Bicep's name that scales something else does not count.
      3. No setting for the plan is a counted [FAIL]; so is a listing that fails, which also
         prints the error and still reaches the summary instead of ending the script.

    No subscription is needed, and none is used: tests/Support/LabScriptStub.psm1 (issue #112)
    imports the real modules first, the stub last, and aborts the child with exit 99 unless every
    stubbed command resolves to the stub.

.EXAMPLE
    Invoke-Pester -Path .\Test-Lab.Tests.ps1

.NOTES
    Project: SkyCraft
    Lab: 3.4 - App Service
    Issue: #355
#>

#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..' '..' '..' 'tests' 'Support' 'LabScriptStub.psm1') -Force

    $script:ScriptPath     = (Resolve-Path (Join-Path $PSScriptRoot '..' 'scripts' 'Test-Lab.ps1')).Path
    $script:StubModuleName = 'SkyCraftLab34ValidatorStub'
    # Exactly the script's '#Requires -Modules' line.
    $script:RequiredModules = @('Az.Accounts', 'Az.Websites', 'Az.Monitor')

    $script:StubCommands = @(
        'Get-AzContext'
        'Get-AzAppServicePlan'
        'Get-AzWebApp'
        'Get-AzWebAppSlot'
        'Get-AzResource'
    )

    # The lab as built: the plan, the app with its VNet integration and staging slot, and the
    # subscription's autoscale settings. One unrelated setting (a scale set's) is always listed.
    #   SKYCRAFT_STUB_AUTOSCALE   'bicep'  the plan's setting under the Bicep's name
    #                             'portal' the plan's setting under a Portal name, its target id
    #                                      spelled in other casing, as ARM ids come back
    #                             'other'  only a setting under the Bicep's name that scales a VM
    #                                      scale set, not the plan
    #                             'none'   no setting besides the unrelated one
    #                             'fail'   the listing fails
    $script:StubBody = @'
$script:Sub = '/subscriptions/00000000-0000-0000-0000-000000000000'
$script:Rg  = "$script:Sub/resourceGroups/dev-skycraft-swc-rg"

function Get-AzContext {
    [CmdletBinding()]
    param()
    [pscustomobject]@{ Subscription = [pscustomobject]@{ Id = '00000000-0000-0000-0000-000000000000' } }
}

function Get-AzAppServicePlan {
    [CmdletBinding()]
    param([string]$ResourceGroupName, [string]$Name, [Parameter(ValueFromRemainingArguments)]$Rest)
    [pscustomobject]@{
        Name   = $Name
        Id     = "$script:Sub/resourceGroups/$ResourceGroupName/providers/Microsoft.Web/serverfarms/$Name"
        Sku    = [pscustomobject]@{ Tier = 'PremiumV4'; Name = 'P0v4' }
        Kind   = 'linux'
        Status = 'Ready'
    }
}

function Get-AzWebApp {
    [CmdletBinding()]
    param([string]$ResourceGroupName, [string]$Name, [Parameter(ValueFromRemainingArguments)]$Rest)
    [pscustomobject]@{
        Name      = $Name
        Id        = "$script:Sub/resourceGroups/$ResourceGroupName/providers/Microsoft.Web/sites/$Name"
        State     = 'Running'
        HttpsOnly = $true
    }
}

function Get-AzWebAppSlot {
    [CmdletBinding()]
    param([string]$ResourceGroupName, [string]$Name, [string]$Slot, [Parameter(ValueFromRemainingArguments)]$Rest)
    [pscustomobject]@{ Name = "$Name/$Slot" }
}

function New-StubAutoscale {
    param([string]$Name, [string]$Target)
    [pscustomobject]@{
        Name              = $Name
        ResourceGroupName = 'dev-skycraft-swc-rg'
        ResourceId        = "$script:Rg/providers/Microsoft.Insights/autoscalesettings/$Name"
        Properties        = [pscustomobject]@{
            targetResourceUri = $Target
            enabled           = $true
            profiles          = @([pscustomobject]@{
                    name     = 'Auto created default scale condition'
                    capacity = [pscustomobject]@{ minimum = '1'; maximum = '3'; default = '1' }
                    rules    = @([pscustomobject]@{ direction = 'Increase' }, [pscustomobject]@{ direction = 'Decrease' })
                })
        }
    }
}

function Get-AzResource {
    [CmdletBinding()]
    param(
        [string]$ResourceId,
        [string]$ResourceType,
        [string]$ResourceGroupName,
        [string]$Name,
        [switch]$ExpandProperties,
        [Parameter(ValueFromRemainingArguments)]$Rest
    )
    if ($ResourceId) {
        # The web app's raw body, read for its VNet integration.
        return [pscustomobject]@{
            ResourceId = $ResourceId
            Properties = [pscustomobject]@{ virtualNetworkSubnetId = "$script:Rg/providers/Microsoft.Network/virtualNetworks/dev-skycraft-swc-vnet/subnets/AppServiceSubnet" }
        }
    }
    if ($ResourceType -ne 'Microsoft.Insights/autoscalesettings') { throw "stub: unexpected Get-AzResource -ResourceType $ResourceType" }
    if ($Name) { throw "stub: the lab finds the autoscale setting through its target, not by name ($Name)" }
    if ($env:SKYCRAFT_STUB_AUTOSCALE -eq 'fail') { Write-Error 'stub lookup failure: Get-AzResource autoscalesettings'; return }

    $plan = "$script:Rg/providers/Microsoft.Web/serverfarms/dev-skycraft-swc-asp"
    $vmss = "$script:Rg/providers/Microsoft.Compute/virtualMachineScaleSets/dev-skycraft-swc-vmss"
    New-StubAutoscale -Name 'dev-skycraft-swc-vmss-autoscale' -Target $vmss
    switch ($env:SKYCRAFT_STUB_AUTOSCALE) {
        'bicep'  { New-StubAutoscale -Name 'dev-skycraft-swc-asp-autoscale' -Target $plan }
        'portal' { New-StubAutoscale -Name 'dev-skycraft-swc-asp-Autoscale-713' -Target ($plan -replace '/resourceGroups/', '/resourcegroups/' -replace 'Microsoft.Web/serverfarms', 'Microsoft.Web/serverFarms') }
        'other'  { New-StubAutoscale -Name 'dev-skycraft-swc-asp-autoscale' -Target $vmss }
    }
}
'@

    function Invoke-ValidatorScript {
        param(
            [pscustomobject]$Stub,
            [ValidateSet('bicep', 'portal', 'other', 'none', 'fail')]
            [string]$Autoscale
        )
        $run = Invoke-LabScriptWithStub -Stub $Stub -ScriptPath $script:ScriptPath -Environment @{
            SKYCRAFT_STUB_AUTOSCALE = $Autoscale
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

    # One child process per scenario, reused by the assertions below.
    $script:BicepMade  = Invoke-ValidatorScript -Stub $script:Stub -Autoscale 'bicep'
    $script:PortalMade = Invoke-ValidatorScript -Stub $script:Stub -Autoscale 'portal'
    $script:OtherOnly  = Invoke-ValidatorScript -Stub $script:Stub -Autoscale 'other'
    $script:NoneMade   = Invoke-ValidatorScript -Stub $script:Stub -Autoscale 'none'
    $script:ListFails  = Invoke-ValidatorScript -Stub $script:Stub -Autoscale 'fail'
    $script:AllRuns    = @($script:BicepMade, $script:PortalMade, $script:OtherOnly, $script:NoneMade, $script:ListFails)
}

AfterAll {
    if ($script:StubDir) { Remove-Item -LiteralPath $script:StubDir -Recurse -Force -ErrorAction SilentlyContinue }
}

Describe 'Lab 3.4 Test-Lab.ps1 - test harness' {

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

Describe 'Lab 3.4 Test-Lab.ps1 - finds the autoscale setting through its target plan (#355)' {

    It 'passes the setting the Bicep made, and names it' {
        $run = $script:BicepMade
        $run.ExitCode | Should -Be 0 -Because "output was:`n$($run.Output)"
        $run.FailLines | Should -Be 0
        $run.Output | Should -Match "Autoscale setting 'dev-skycraft-swc-asp-autoscale' in 'dev-skycraft-swc-rg' targets 'dev-skycraft-swc-asp'"
        $run.Output | Should -Match '\[OK\] Instance limits \(1-3\) correct'
        $run.Output | Should -Match '\[OK\] Found 2 scaling rules'
    }

    It 'passes the setting the Portal made under its own name, whatever the casing of the target id' {
        $run = $script:PortalMade
        $run.ExitCode | Should -Be 0 -Because "a learner who took the Portal path built what the guide asks for; output was:`n$($run.Output)"
        $run.FailLines | Should -Be 0
        $run.Output | Should -Match "Autoscale setting 'dev-skycraft-swc-asp-Autoscale-713' in 'dev-skycraft-swc-rg' targets 'dev-skycraft-swc-asp'"
    }

    It 'does not count a setting under the Bicep''s name that scales something else' {
        $run = $script:OtherOnly
        $run.ExitCode | Should -Be 1 -Because "output was:`n$($run.Output)"
        $run.Output | Should -Match "\[FAIL\] No autoscale setting targets App Service Plan 'dev-skycraft-swc-asp'"
        $run.FailLines | Should -Be 1
    }

    It 'fails, counted, when no setting scales the plan' {
        $run = $script:NoneMade
        $run.ExitCode | Should -Be 1 -Because "output was:`n$($run.Output)"
        $run.Output | Should -Match "\[FAIL\] No autoscale setting targets App Service Plan 'dev-skycraft-swc-asp'"
        $run.Output | Should -Match 'FAILURE: Found 1 issues'
    }

    It 'counts a listing that fails as a [FAIL] that says why, and still reaches the summary' {
        $run = $script:ListFails
        $run.ExitCode | Should -Be 1 -Because "output was:`n$($run.Output)"
        $run.Output | Should -Match '\[FAIL\] Could not list the autoscale settings: stub lookup failure'
        $run.Output | Should -Match 'Validation Summary'
        $run.Output | Should -Match 'FAILURE: Found 1 issues'
    }
}
