<#
.SYNOPSIS
    Pester 5 tests asserting that Lab 1.2's New-LabRoleAssignment.ps1 finds Lab 1.1's users where
    Lab 1.1 creates them.

.DESCRIPTION
    Regression cover for issue #237, the Lab 1.2 twin of #193. Lab 1.1 creates its users on the
    tenant's initial *.onmicrosoft.com domain, as its guide says ('[yourtenant].onmicrosoft.com').
    New-LabRoleAssignment.ps1 looked them up on the tenant's DEFAULT domain, falling back to the
    bare string 'onmicrosoft.com' when the lookup failed, so in a tenant whose default domain is a
    custom one it found none of them.

    These tests run the real script in a child pwsh process against a generated stub of the
    Microsoft Graph and Az commands it calls, and assert:

      1. In a tenant whose default domain is a custom one, the user is looked up on the initial
         domain.
      2. When the initial domain cannot be determined (the lookup fails, or returns no initial
         domain) the script stops with [ERROR] and exit 1 before it looks up a user or assigns a
         role, instead of guessing a domain.

    No tenant or subscription is needed, and none is used: the script runs through
    tests/Support/LabScriptStub.psm1 (issue #112), which aborts the child with exit 99 unless
    every stubbed command resolves to the stub.

.EXAMPLE
    Invoke-Pester -Path .\New-LabRoleAssignment.Tests.ps1

.NOTES
    Project: SkyCraft
    Lab: 1.2 - RBAC
#>

#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..' '..' '..' 'tests' 'Support' 'LabScriptStub.psm1') -Force

    $script:ScriptPath = (Resolve-Path (Join-Path $PSScriptRoot '..' 'scripts' 'New-LabRoleAssignment.ps1')).Path

    # Exactly the script's '#Requires -Modules' line: these are imported for real before the stub.
    $script:RequiredModules = @(
        'Az.Accounts'
        'Az.Resources'
        'Microsoft.Graph.Authentication'
        'Microsoft.Graph.Identity.DirectoryManagement'
        'Microsoft.Graph.Users'
        'Microsoft.Graph.Groups'
    )
    $script:StubCommands = @(
        'Get-MgContext'
        'Connect-MgGraph'
        'Get-AzContext'
        'Connect-AzAccount'
        'Get-MgDomain'
        'Get-MgUser'
        'Get-MgGroup'
        'Get-AzRoleAssignment'
        'New-AzRoleAssignment'
    )

    # An empty tenant with one subscription: every principal lookup succeeds and finds nothing, so
    # no role is assigned. SKYCRAFT_STUB_DOMAIN picks the Get-MgDomain answer: 'custom' (a custom
    # default domain next to the initial one), 'fail', 'noinitial'.
    $script:StubBody = @'
$script:LogPath = $env:SKYCRAFT_STUB_LOG

function Write-StubCall {
    param([string]$Name)
    if ($script:LogPath) { Add-Content -LiteralPath $script:LogPath -Value $Name }
}

function Get-MgContext {
    [CmdletBinding()]
    param()
    [pscustomobject]@{ TenantId = '00000000-0000-0000-0000-000000000000' }
}

function Connect-MgGraph {
    [CmdletBinding()]
    param([Parameter(ValueFromRemainingArguments)]$Rest)
    Write-StubCall -Name 'Connect-MgGraph'
}

function Get-AzContext {
    [CmdletBinding()]
    param()
    [pscustomobject]@{
        Subscription = [pscustomobject]@{ Id = '11111111-1111-1111-1111-111111111111'; Name = 'stub-subscription' }
        Tenant       = [pscustomobject]@{ Id = '00000000-0000-0000-0000-000000000000' }
    }
}

function Connect-AzAccount {
    [CmdletBinding()]
    param([Parameter(ValueFromRemainingArguments)]$Rest)
    Write-StubCall -Name 'Connect-AzAccount'
}

function Get-MgDomain {
    [CmdletBinding()]
    param([Parameter(ValueFromRemainingArguments)]$Rest)
    Write-StubCall -Name 'Get-MgDomain'
    switch ($env:SKYCRAFT_STUB_DOMAIN) {
        'fail'      { throw 'stub failure: Get-MgDomain' }
        'noinitial' { [pscustomobject]@{ Id = 'contoso.example'; IsDefault = $true; IsInitial = $false } }
        default {
            [pscustomobject]@{ Id = 'contoso.example'; IsDefault = $true; IsInitial = $false }
            [pscustomobject]@{ Id = 'contoso.onmicrosoft.com'; IsDefault = $false; IsInitial = $true }
        }
    }
}

function Get-MgUser {
    [CmdletBinding()]
    param([string]$Filter, [Parameter(ValueFromRemainingArguments)]$Rest)
    Write-StubCall -Name "Get-MgUser|$Filter"
}

function Get-MgGroup {
    [CmdletBinding()]
    param([string]$Filter, [Parameter(ValueFromRemainingArguments)]$Rest)
}

function Get-AzRoleAssignment {
    [CmdletBinding()]
    param([Parameter(ValueFromRemainingArguments)]$Rest)
}

function New-AzRoleAssignment {
    [CmdletBinding()]
    param([Parameter(ValueFromRemainingArguments)]$Rest)
    Write-StubCall -Name 'New-AzRoleAssignment'
}
'@

    function Invoke-RoleAssignmentScript {
        param([string]$Domain = 'custom')

        $logPath = Join-Path $script:Stub.Directory 'calls.log'
        Remove-Item -LiteralPath $logPath -Force -ErrorAction SilentlyContinue

        $run = Invoke-LabScriptWithStub -Stub $script:Stub -ScriptPath $script:ScriptPath -Environment @{
            SKYCRAFT_STUB_DOMAIN = $Domain
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

    $script:Stub = Initialize-LabScriptStub -Name 'SkyCraftLab12Stub' -Command $script:StubCommands `
        -Body $script:StubBody -RequiredModule $script:RequiredModules

    # One invocation per scenario - each child process costs several seconds.
    $script:Custom    = Invoke-RoleAssignmentScript -Domain 'custom'
    $script:Fail      = Invoke-RoleAssignmentScript -Domain 'fail'
    $script:NoInitial = Invoke-RoleAssignmentScript -Domain 'noinitial'
}

AfterAll {
    if ($script:Stub) { Remove-Item -LiteralPath $script:Stub.Directory -Recurse -Force -ErrorAction SilentlyContinue }
}

Describe 'Lab 1.2 New-LabRoleAssignment.ps1 - test harness' {

    It 'shadows the real Microsoft Graph and Az commands instead of touching a tenant' {
        foreach ($run in @($script:Custom, $script:Fail, $script:NoInitial)) {
            $run.Refused | Should -BeFalse -Because "the harness must never fall through to the real commands (exit $($run.ExitCode)): $($run.Output)"
        }
    }
}

Describe 'Lab 1.2 New-LabRoleAssignment.ps1 - Lab 1.1''s users on the initial domain (#237)' {

    It 'looks Malfurion up on the initial domain in a tenant whose default domain is a custom one' {
        $script:Custom.Calls | Should -Contain "Get-MgUser|UserPrincipalName eq 'malfurion.stormrage@contoso.onmicrosoft.com'" -Because "Lab 1.1 creates him there; output was:`n$($script:Custom.Output)"
        ($script:Custom.Calls -join "`n") | Should -Not -Match '@contoso\.example'
        $script:Custom.ExitCode | Should -Be 0 -Because "output was:`n$($script:Custom.Output)"
    }

    It 'stops with [ERROR] and exit 1 when the domain lookup <case>' -ForEach @(
        @{ scenario = 'Fail';      case = 'fails' }
        @{ scenario = 'NoInitial'; case = 'finds no initial domain' }
    ) {
        $run = Get-Variable -Scope Script -Name $scenario -ValueOnly
        $run.ExitCode | Should -Be 1 -Because "a guessed domain names users Lab 1.1 never created; output was:`n$($run.Output)"
        $run.Output | Should -Match '\[ERROR\][^\r\n]*initial \*\.onmicrosoft\.com domain'
        $run.Calls | Should -Contain 'Get-MgDomain'
        @($run.Calls | Where-Object { $_ -like 'Get-MgUser|*' -or $_ -eq 'New-AzRoleAssignment' }) |
            Should -BeNullOrEmpty -Because 'nothing may be looked up or assigned on a guessed domain'
    }
}
