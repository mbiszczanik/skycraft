<#
.SYNOPSIS
    Pester 5 tests asserting that Lab 1.2's New-LabRoleAssignment.ps1 signs in to Microsoft Graph
    and finds Lab 1.1's users the way Lab 1.1 does.

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
      3. The Microsoft Graph sign-in is Lab 1.1's (issue #273): a context in the session is reused
         only when its scopes cover the request (the one Lab 1.1's setup leaves does), one that
         holds a Read scope only makes the script sign in again with the scopes it needs, and a
         sign-in that leaves no context is an [ERROR] and exit 1 (issue #242). The script used to
         reuse any context, an empty one included.
      4. With no SKYCRAFT_GRAPH_TENANT_ID, the Graph sign-in goes to the Az context's tenant
         (#300). Azure PowerShell is set up first, so with no Az context the tenant comes from the
         Connect-AzAccount the script runs. A Graph sign-in in another tenant than the Az context
         is neither reused nor replaced: the script stops with [ERROR] and exit 1 and names both,
         since that Az context may be one Az PowerShell restored from an earlier session.

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
        'Disconnect-MgGraph'
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
    # SKYCRAFT_STUB_SCOPES is the comma-separated scope list of the Graph context found in the
    # session; after Connect-MgGraph the context holds the scopes it was asked for, which it logs
    # as 'Connect-MgGraph:Scopes=a,b,c'. SKYCRAFT_STUB_NOCONTEXT '1' leaves no context at all,
    # before or after the sign-in (the #242 shape). SKYCRAFT_STUB_MGTENANT is the tenant of the Graph
    # context found in the session (default: the Az context's); Connect-MgGraph logs the tenant it
    # was asked for, as 'Connect-MgGraph:TenantId=<id>', and leaves a context in that tenant (the
    # Az context's when it was asked for none). SKYCRAFT_STUB_MGFRESH '1' leaves no Graph context
    # until Connect-MgGraph has run. SKYCRAFT_STUB_NOAZCONTEXT '1' leaves no Az context until
    # Connect-AzAccount has run, which signs in to tenant 88888888-8888-8888-8888-888888888888.
    $script:StubBody = @'
$script:LogPath  = $env:SKYCRAFT_STUB_LOG
$script:Scopes   = @($env:SKYCRAFT_STUB_SCOPES -split ',' | Where-Object { $_ })
$script:MgTenant = if ($env:SKYCRAFT_STUB_MGTENANT) { $env:SKYCRAFT_STUB_MGTENANT } else { '00000000-0000-0000-0000-000000000000' }
$script:AzTenant = '00000000-0000-0000-0000-000000000000'
$script:MgConnected = $false
$script:AzConnected = $false

function Write-StubCall {
    param([string]$Name)
    if ($script:LogPath) { Add-Content -LiteralPath $script:LogPath -Value $Name }
}

function Get-MgContext {
    [CmdletBinding()]
    param()
    if ($env:SKYCRAFT_STUB_NOCONTEXT -eq '1') { return }
    if ($env:SKYCRAFT_STUB_MGFRESH -eq '1' -and -not $script:MgConnected) { return }
    [pscustomobject]@{
        TenantId = $script:MgTenant
        Account  = 'stub-admin@contoso.example'
        AppName  = 'Microsoft Graph Command Line Tools'
        AuthType = 'Delegated'
        Scopes   = $script:Scopes
    }
}

function Connect-MgGraph {
    [CmdletBinding()]
    param([string[]]$Scopes, [string]$TenantId, [Parameter(ValueFromRemainingArguments)]$Rest)
    Write-StubCall -Name 'Connect-MgGraph'
    Write-StubCall -Name "Connect-MgGraph:Scopes=$($Scopes -join ',')"
    Write-StubCall -Name "Connect-MgGraph:TenantId=$TenantId"
    $script:Scopes      = $Scopes
    $script:MgTenant    = if ($TenantId) { $TenantId } else { $script:AzTenant }
    $script:MgConnected = $true
}

function Disconnect-MgGraph {
    [CmdletBinding()]
    param()
    Write-StubCall -Name 'Disconnect-MgGraph'
}

function Get-AzContext {
    [CmdletBinding()]
    param()
    if ($env:SKYCRAFT_STUB_NOAZCONTEXT -eq '1' -and -not $script:AzConnected) { return }
    [pscustomobject]@{
        Subscription = [pscustomobject]@{ Id = '11111111-1111-1111-1111-111111111111'; Name = 'stub-subscription' }
        Tenant       = [pscustomobject]@{ Id = $script:AzTenant }
    }
}

function Connect-AzAccount {
    [CmdletBinding()]
    param([Parameter(ValueFromRemainingArguments)]$Rest)
    Write-StubCall -Name 'Connect-AzAccount'
    $script:AzConnected = $true
    $script:AzTenant    = '88888888-8888-8888-8888-888888888888'
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

    # The scopes the script requests - Lab 1.1's Test-Lab.ps1 set - and a context left by Lab 1.1's
    # New-LabUser.ps1, whose ReadWrite scopes cover them.
    $script:RequestedScopes = 'User.ReadWrite.All,Group.ReadWrite.All,Directory.ReadWrite.All'
    $script:Lab11Scopes     = 'User.ReadWrite.All,Group.ReadWrite.All,Directory.ReadWrite.All,Domain.Read.All,User.Invite.All'

    function Invoke-RoleAssignmentScript {
        param([string]$Domain = 'custom', [string]$Scopes = $script:Lab11Scopes, [switch]$NoContext, [string]$MgTenant = '', [switch]$MgFresh, [switch]$NoAzContext)

        $logPath = Join-Path $script:Stub.Directory 'calls.log'
        Remove-Item -LiteralPath $logPath -Force -ErrorAction SilentlyContinue

        $run = Invoke-LabScriptWithStub -Stub $script:Stub -ScriptPath $script:ScriptPath -Environment @{
            SKYCRAFT_STUB_DOMAIN           = $Domain
            SKYCRAFT_STUB_SCOPES           = $Scopes
            SKYCRAFT_STUB_NOCONTEXT        = if ($NoContext) { '1' } else { '0' }
            SKYCRAFT_STUB_MGTENANT         = $MgTenant
            SKYCRAFT_STUB_MGFRESH          = if ($MgFresh) { '1' } else { '0' }
            SKYCRAFT_STUB_NOAZCONTEXT      = if ($NoAzContext) { '1' } else { '0' }
            SKYCRAFT_STUB_LOG              = $logPath
            # Interactive plan, so the script reuses the stub's context or calls the stub's
            # Connect-MgGraph instead of signing in.
            SKYCRAFT_GRAPH_TENANT_ID       = ''
            SKYCRAFT_GRAPH_CLIENT_ID       = ''
            SKYCRAFT_GRAPH_CLIENT_SECRET   = ''
            SKYCRAFT_GRAPH_CERT_THUMBPRINT = ''
            SKYCRAFT_UNATTENDED            = ''
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
    # The #273 shape: a context in the session that holds a Read scope only.
    $script:ReadOnly  = Invoke-RoleAssignmentScript -Scopes 'User.Read.All'
    # The #242 shape: a sign-in that returns without a context.
    $script:NoContext = Invoke-RoleAssignmentScript -NoContext
    # The #381 step 3 shape: a covering Graph context in one tenant, the Az context in another.
    $script:OtherTenant = Invoke-RoleAssignmentScript -MgTenant '99999999-9999-9999-9999-999999999999'
    # The #300 shape: a fresh session, no Az context and no Graph context.
    $script:NoAz = Invoke-RoleAssignmentScript -MgFresh -NoAzContext
}

AfterAll {
    if ($script:Stub) { Remove-Item -LiteralPath $script:Stub.Directory -Recurse -Force -ErrorAction SilentlyContinue }
}

Describe 'Lab 1.2 New-LabRoleAssignment.ps1 - test harness' {

    It 'shadows the real Microsoft Graph and Az commands instead of touching a tenant' {
        foreach ($run in @($script:Custom, $script:Fail, $script:NoInitial, $script:ReadOnly, $script:NoContext, $script:OtherTenant, $script:NoAz)) {
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

Describe 'Lab 1.2 New-LabRoleAssignment.ps1 - signs in to Microsoft Graph the way Lab 1.1 does (#273, #242)' {

    It 'reuses a Graph context whose scopes cover the request, such as the one Lab 1.1 leaves' {
        $script:Custom.Calls | Should -Not -Contain 'Connect-MgGraph' -Because "Lab 1.1's ReadWrite scopes cover this script's; calls were: $($script:Custom.Calls -join ', ')"
        $script:Custom.Output | Should -Match 'Connected to Tenant: 00000000-0000-0000-0000-000000000000 as stub-admin@contoso\.example'
    }

    It 'signs in again with the scopes it needs when the context in the session holds a Read scope only' {
        $run = $script:ReadOnly
        $run.ExitCode | Should -Be 0 -Because "output was:`n$($run.Output)"
        $run.Output | Should -Match 'lacks User\.ReadWrite\.All, Group\.ReadWrite\.All, Directory\.ReadWrite\.All'
        @($run.Calls | Where-Object { $_ -like 'Connect-MgGraph:Scopes=*' }) |
            Should -Be @("Connect-MgGraph:Scopes=$($script:RequestedScopes)")
        $run.Calls | Should -Contain "Get-MgUser|UserPrincipalName eq 'malfurion.stormrage@contoso.onmicrosoft.com'"
    }

    It 'stops with [ERROR] and exit 1 when the sign-in leaves no Graph context, before any lookup' {
        $run = $script:NoContext
        $run.ExitCode | Should -Be 1 -Because "a sign-in that did not complete must not look like a connection; output was:`n$($run.Output)"
        $run.Output | Should -Match '\[ERROR\] Failed to connect to Microsoft Graph: [^\r\n]*sign-in did not complete'
        $run.Output | Should -Not -Match 'Connected to Tenant'
        $run.Calls | Should -Contain 'Connect-MgGraph'
        $run.Calls | Should -Not -Contain 'Get-MgDomain'
        @($run.Calls | Where-Object { $_ -like 'Get-MgUser|*' -or $_ -eq 'New-AzRoleAssignment' }) | Should -BeNullOrEmpty
    }
}

Describe 'Lab 1.2 New-LabRoleAssignment.ps1 - signs in to Microsoft Graph in the Az context''s tenant (#300)' {

    It 'stops with [ERROR] and exit 1, naming both tenants, when the Graph context in the session belongs to another tenant' {
        $run = $script:OtherTenant
        $run.ExitCode | Should -Be 1 -Because "the Az context may be a restored one; output was:`n$($run.Output)"
        $run.Output | Should -Match '\[ERROR\] Failed to connect to Microsoft Graph: [^\r\n]*99999999-9999-9999-9999-999999999999[^\r\n]*00000000-0000-0000-0000-000000000000'
        $run.Calls | Should -Not -Contain 'Connect-MgGraph' -Because 'the Graph context must not be replaced silently'
        $run.Calls | Should -Not -Contain 'Get-MgDomain'
        @($run.Calls | Where-Object { $_ -like 'Get-MgUser|*' -or $_ -eq 'New-AzRoleAssignment' }) | Should -BeNullOrEmpty
    }

    It 'with no Az context, runs Connect-AzAccount before Connect-MgGraph and signs in to Graph in the new Az tenant' {
        $run = $script:NoAz
        $run.ExitCode | Should -Be 0 -Because "output was:`n$($run.Output)"
        $azIndex = [array]::IndexOf([string[]]$run.Calls, 'Connect-AzAccount')
        $mgIndex = [array]::IndexOf([string[]]$run.Calls, 'Connect-MgGraph')
        $azIndex | Should -BeGreaterOrEqual 0 -Because "calls were: $($run.Calls -join ', ')"
        $mgIndex | Should -BeGreaterThan $azIndex
        $run.Calls | Should -Contain 'Connect-MgGraph:TenantId=88888888-8888-8888-8888-888888888888'
        $run.Output | Should -Not -Match 'Tenant Mismatch'
    }

    It 'prints no missing-tenant hint when the Az context names the tenant' {
        $script:Custom.Output | Should -Not -Match 'No tenant named'
    }
}
