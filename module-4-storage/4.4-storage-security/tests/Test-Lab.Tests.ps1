<#
.SYNOPSIS
    Pester 5 tests: the Lab 4.4 validator finds the SAS exercise container by its stored policy.

.DESCRIPTION
    Regression cover for issue #355. Test-Lab.ps1 required a container named 'dev-assets', which
    only the Bicep creates; step 4.4.3 lets the learner pick any container and names only the
    stored access policy, DevRevokePolicy. A learner who followed the guide failed
    "[FAIL] Container 'dev-assets' not found." The old check also printed "Found Policy ''",
    because it read .Id where the returned object names the policy in .Policy. These tests run
    the real Test-Lab.ps1 in a child pwsh against a generated stub of the Az commands it calls,
    and assert that:

      1. A container the learner picked passes when it holds DevRevokePolicy, and the output
         names the container and every policy it found by name.
      2. The Bicep path's 'dev-assets' passes without a policy.
      3. Neither, as after step 4.4.4 deletes the policy, is reported and not counted.
      4. A container listing that fails, or policy reads that fail with nothing else found, are
         counted [FAIL] lines that say why, and the script still reaches its summary.

    No subscription is needed, and none is used: tests/Support/LabScriptStub.psm1 (issue #112)
    imports the real modules first, the stub last, and aborts the child with exit 99 unless every
    stubbed command resolves to the stub.

.EXAMPLE
    Invoke-Pester -Path .\Test-Lab.Tests.ps1

.NOTES
    Project: SkyCraft
    Lab: 4.4 - Storage Security
    Issue: #355
#>

#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..' '..' '..' 'tests' 'Support' 'LabScriptStub.psm1') -Force

    $script:ScriptPath     = (Resolve-Path (Join-Path $PSScriptRoot '..' 'scripts' 'Test-Lab.ps1')).Path
    $script:StubModuleName = 'SkyCraftLab44ValidatorStub'
    # Exactly the script's '#Requires -Modules' line.
    $script:RequiredModules = @('Az.Accounts', 'Az.Storage', 'Az.Network')

    $script:StubCommands = @(
        'Get-AzContext'
        'Get-AzStorageAccount'
        'Get-AzVirtualNetwork'
        'Get-AzRmStorageContainer'
        'Get-AzStorageContainerStoredAccessPolicy'
    )

    # The firewalled account and WorldSubnet with its service endpoint are always in place. The
    # containers and their policies vary:
    #   SKYCRAFT_STUB_CONTAINERS   'portal'  Lab 4.2's containers; game-assets holds
    #                                        DevRevokePolicy, server-config another policy
    #                              'bicep'   Lab 4.2's containers plus dev-assets, no policy
    #                              'deleted' Lab 4.2's containers, no policy (after step 4.4.4)
    #                              'fail'    the container listing fails
    #   SKYCRAFT_STUB_POLICYFAIL   '1' makes every stored access policy read fail, as the storage
    #                              firewall does when the client IP is not allowed
    $script:StubBody = @'
function Get-AzContext {
    [CmdletBinding()]
    param()
    [pscustomobject]@{ Subscription = [pscustomobject]@{ Id = '00000000-0000-0000-0000-000000000000' } }
}

function Get-AzStorageAccount {
    [CmdletBinding()]
    param([string]$ResourceGroupName, [string]$Name, [Parameter(ValueFromRemainingArguments)]$Rest)
    [pscustomobject]@{
        StorageAccountName = $Name
        Context            = [pscustomobject]@{ StorageAccountName = $Name }
        NetworkRuleSet     = [pscustomobject]@{
            DefaultAction       = 'Deny'
            VirtualNetworkRules = @([pscustomobject]@{ VirtualNetworkResourceId = 'stub-subnet' })
        }
    }
}

function Get-AzVirtualNetwork {
    [CmdletBinding()]
    param([string]$ResourceGroupName, [string]$Name, [Parameter(ValueFromRemainingArguments)]$Rest)
    [pscustomobject]@{
        Name    = $Name
        Subnets = @([pscustomobject]@{ Name = 'WorldSubnet'; ServiceEndpoints = @([pscustomobject]@{ Service = 'Microsoft.Storage' }) })
    }
}

function Get-AzRmStorageContainer {
    [CmdletBinding()]
    param([string]$ResourceGroupName, [string]$StorageAccountName, [string]$Name, [Parameter(ValueFromRemainingArguments)]$Rest)
    if ($Name) { throw "stub: the lab lists the containers rather than reading one by name ($Name)" }
    if ($env:SKYCRAFT_STUB_CONTAINERS -eq 'fail') { Write-Error 'stub lookup failure: Get-AzRmStorageContainer'; return }
    $names = @('game-assets', 'player-backups', 'server-config', 'game-logs')
    if ($env:SKYCRAFT_STUB_CONTAINERS -eq 'bicep') { $names += 'dev-assets' }
    foreach ($n in $names) { [pscustomobject]@{ Name = $n } }
}

# Shaped like the real cmdlet's output: the identifier is in .Policy, the permissions in
# .Permissions; there is no .Id.
function Get-AzStorageContainerStoredAccessPolicy {
    [CmdletBinding()]
    param([string]$Container, $Context, [string]$Policy, [Parameter(ValueFromRemainingArguments)]$Rest)
    if ($env:SKYCRAFT_STUB_POLICYFAIL -eq '1') { Write-Error "stub lookup failure: This request is not authorized to perform this operation. ($Container)"; return }
    if ($env:SKYCRAFT_STUB_CONTAINERS -ne 'portal') { return }
    switch ($Container) {
        'game-assets'   { [pscustomobject]@{ Policy = 'DevRevokePolicy'; Permissions = 'rl'; StartTime = $null; ExpiryTime = [datetime]'2026-11-17' } }
        'server-config' { [pscustomobject]@{ Policy = 'OpsReadPolicy'; Permissions = 'r'; StartTime = $null; ExpiryTime = [datetime]'2026-11-17' } }
    }
}
'@

    function Invoke-ValidatorScript {
        param(
            [pscustomobject]$Stub,
            [ValidateSet('portal', 'bicep', 'deleted', 'fail')]
            [string]$Containers,
            [switch]$PolicyFail
        )
        $run = Invoke-LabScriptWithStub -Stub $Stub -ScriptPath $script:ScriptPath -Environment @{
            SKYCRAFT_STUB_CONTAINERS = $Containers
            SKYCRAFT_STUB_POLICYFAIL = if ($PolicyFail) { '1' } else { '0' }
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

    $script:PortalMade      = Invoke-ValidatorScript -Stub $script:Stub -Containers 'portal'
    $script:BicepMade       = Invoke-ValidatorScript -Stub $script:Stub -Containers 'bicep'
    $script:PolicyDeleted   = Invoke-ValidatorScript -Stub $script:Stub -Containers 'deleted'
    $script:ListFails       = Invoke-ValidatorScript -Stub $script:Stub -Containers 'fail'
    $script:PolicyReadFails = Invoke-ValidatorScript -Stub $script:Stub -Containers 'portal' -PolicyFail
    $script:BicepReadFails  = Invoke-ValidatorScript -Stub $script:Stub -Containers 'bicep' -PolicyFail
    $script:AllRuns = @($script:PortalMade, $script:BicepMade, $script:PolicyDeleted, $script:ListFails, $script:PolicyReadFails, $script:BicepReadFails)
}

AfterAll {
    if ($script:StubDir) { Remove-Item -LiteralPath $script:StubDir -Recurse -Force -ErrorAction SilentlyContinue }
}

Describe 'Lab 4.4 Test-Lab.ps1 - test harness' {

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

Describe 'Lab 4.4 Test-Lab.ps1 - finds the SAS exercise container through its stored access policy (#355)' {

    It 'passes the container the learner picked when it holds DevRevokePolicy, and names it' {
        $run = $script:PortalMade
        $run.ExitCode | Should -Be 0 -Because "a learner who took the Portal path built what the guide asks for; output was:`n$($run.Output)"
        $run.FailLines | Should -Be 0
        $run.Output | Should -Match "Container 'game-assets' holds stored access policy 'DevRevokePolicy'\."
        $run.Output | Should -Not -Match "dev-assets' not found"
    }

    It 'prints every stored access policy it finds by name, not an empty one' {
        $run = $script:PortalMade
        $run.Output | Should -Match "Found stored access policy 'DevRevokePolicy' \(permissions: rl\) on container 'game-assets'\."
        $run.Output | Should -Match "Found stored access policy 'OpsReadPolicy' \(permissions: r\) on container 'server-config'\."
        $run.Output | Should -Not -Match "policy ''"
    }

    It 'passes the Bicep path''s dev-assets container, which holds no policy' {
        $run = $script:BicepMade
        $run.ExitCode | Should -Be 0 -Because "output was:`n$($run.Output)"
        $run.FailLines | Should -Be 0
        $run.Output | Should -Match "Container 'dev-assets' found \(the Bicep path's container\); no container holds 'DevRevokePolicy'\."
    }

    It 'reports, without counting, a lab whose policy step 4.4.4 deleted' {
        $run = $script:PolicyDeleted
        $run.ExitCode | Should -Be 0 -Because "the guide ends by deleting the policy; output was:`n$($run.Output)"
        $run.FailLines | Should -Be 0
        $run.Output | Should -Match "\[INFO\] No container holds stored access policy 'DevRevokePolicy', and 'dev-assets' does not exist\..*Not counted\."
    }

    It 'counts a container listing that fails, says why, and still reaches the summary' {
        $run = $script:ListFails
        $run.ExitCode | Should -Be 1 -Because "output was:`n$($run.Output)"
        $run.Output | Should -Match "\[FAIL\] Could not list the containers of 'prodskycraftswcsa': stub lookup failure: Get-AzRmStorageContainer"
        $run.FailLines | Should -Be 1
        $run.Output | Should -Match 'Validation Complete\. Failures: 1'
    }

    It 'counts policy reads that fail when nothing else marks the container, and names the firewall step' {
        $run = $script:PolicyReadFails
        $run.ExitCode | Should -Be 1 -Because "output was:`n$($run.Output)"
        $run.Output | Should -Match "\[FAIL\] No container holds 'DevRevokePolicy' among those readable, and the stored access policies of 4 container\(s\) could not be read \(is your client IP allowed, step 4\.4\.2\?\)"
        $run.FailLines | Should -Be 1
    }

    It 'still passes dev-assets when the policy reads fail, because the container is found by the control plane' {
        $run = $script:BicepReadFails
        $run.ExitCode | Should -Be 0 -Because "output was:`n$($run.Output)"
        $run.Output | Should -Match "Container 'dev-assets' found"
    }
}
