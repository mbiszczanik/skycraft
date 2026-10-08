<#
.SYNOPSIS
    Pester 5 tests asserting that Lab 1.1's three scripts use the addresses the guide gives.

.DESCRIPTION
    Regression cover for issue #193. The guide creates the users as
    <name>@[yourtenant].onmicrosoft.com - the tenant's initial domain - and invites the guest named
    in step 1.1.5. The scripts built the users' names on the tenant's DEFAULT domain (falling back
    to the bare string 'onmicrosoft.com' when the lookup failed) and invited, checked and deleted a
    different guest. In a tenant whose default domain is a custom one, a learner who followed the
    guide was validated and cleaned up against objects they never created.

    These tests run the real New-LabUser.ps1, Test-Lab.ps1 and Remove-LabResource.ps1 in a child
    pwsh process against a generated stub of the Microsoft Graph commands, in a stub tenant whose
    default domain is a custom one, and assert:

      1. Every user each script creates, looks up or deletes is the guide's user principal name on
         the initial *.onmicrosoft.com domain.
      2. The guest each script invites, looks up or deletes is the guide's step 1.1.5 address.
      3. When the initial domain cannot be determined (the lookup fails, or returns no initial
         domain) each script stops with [ERROR] and exit 1 before it touches a user, instead of
         guessing a domain.

    The expected values are read from lab-guide-1.1.md itself, so a guide edit that changes a
    user principal name or the guest address fails here until the scripts follow.

    No tenant is needed, and none is used: the scripts run through tests/Support/LabScriptStub.psm1
    (issue #112), which aborts the child with exit 99 unless every stubbed command resolves to
    the stub. Every SKYCRAFT_GRAPH_* variable and SKYCRAFT_UNATTENDED are cleared for the child,
    so each script plans the interactive sign-in and reuses the stub's Graph context.

.EXAMPLE
    Invoke-Pester -Path .\Guide-Addresses.Tests.ps1

.NOTES
    Project: SkyCraft
    Lab: 1.1 - Entra Users & Groups
#>

#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..' '..' '..' 'tests' 'Support' 'LabScriptStub.psm1') -Force

    $labRoot = Join-Path $PSScriptRoot '..'
    $script:NewUserPath = (Resolve-Path (Join-Path $labRoot 'scripts' 'New-LabUser.ps1')).Path
    $script:TestLabPath = (Resolve-Path (Join-Path $labRoot 'scripts' 'Test-Lab.ps1')).Path
    $script:RemovePath  = (Resolve-Path (Join-Path $labRoot 'scripts' 'Remove-LabResource.ps1')).Path

    # The stub tenant: a custom default domain, and the initial domain the guide means.
    $script:TenantPrefix  = 'contoso'
    $script:InitialDomain = "$($script:TenantPrefix).onmicrosoft.com"
    $script:DefaultDomain = 'contoso.example'

    # What the guide says, read from the guide.
    $guide = Get-Content -Raw -LiteralPath (Join-Path $labRoot 'lab-guide-1.1.md')
    $script:GuideUpns = @(
        [regex]::Matches($guide, '(?m)^\|\s*User principal name\s*\|\s*(?<upn>[^\s|]+@\[yourtenant\]\.onmicrosoft\.com)\s*\|') |
            ForEach-Object { $_.Groups['upn'].Value -replace '\[yourtenant\]', $script:TenantPrefix }
    )
    $guestMatch = [regex]::Match($guide, '(?ms)^### Step 1\.1\.5:.*?^\|\s*Email\s*\|\s*(?<email>[^\s|]+)\s*\|')
    $script:GuideGuest = $guestMatch.Groups['email'].Value

    $script:StubModuleName = 'SkyCraftGraphAddressStub'
    # The union of the three scripts' '#Requires -Modules' lines: imported for real before the stub.
    $script:RequiredModules = @(
        'Microsoft.Graph.Authentication'
        'Microsoft.Graph.Users'
        'Microsoft.Graph.Groups'
        'Microsoft.Graph.Identity.DirectoryManagement'
        'Microsoft.Graph.Identity.SignIns'
    )
    # Every Graph command any of the three scripts calls.
    $script:StubCommands = @(
        'Get-MgContext'
        'Connect-MgGraph'
        'Disconnect-MgGraph'
        'Get-MgDomain'
        'Get-MgUser'
        'New-MgUser'
        'Remove-MgUser'
        'New-MgInvitation'
        'Get-MgGroup'
        'New-MgGroup'
        'Remove-MgGroup'
        'Get-MgGroupMember'
        'New-MgGroupMember'
    )

    # An empty tenant: every lookup succeeds and finds nothing, so New-LabUser creates everything,
    # Test-Lab reports everything missing and Remove-LabResource deletes nothing. Each call that
    # names a user is logged with that name, which is what the assertions read.
    # SKYCRAFT_STUB_DOMAIN picks the Get-MgDomain answer: 'custom' (default), 'fail', 'noinitial'.
    $script:StubBody = @'
$script:LogPath = $env:SKYCRAFT_STUB_LOG

function Write-StubCall {
    param([string]$Name)
    if ($script:LogPath) { Add-Content -LiteralPath $script:LogPath -Value $Name }
}

function Get-MgContext {
    [CmdletBinding()]
    param()
    [pscustomobject]@{
        TenantId = '00000000-0000-0000-0000-000000000000'
        Account  = 'stub-admin@contoso.example'
        AppName  = $null
    }
}

function Connect-MgGraph {
    [CmdletBinding()]
    param([Parameter(ValueFromRemainingArguments)]$Rest)
    Write-StubCall -Name 'Connect-MgGraph'
}

function Disconnect-MgGraph {
    [CmdletBinding()]
    param()
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
    param([string]$Filter, [string]$UserId, [Parameter(ValueFromRemainingArguments)]$Rest)
    Write-StubCall -Name "Get-MgUser|$Filter"
}

function New-MgUser {
    [CmdletBinding()]
    param(
        [string]$UserPrincipalName, [string]$DisplayName, $PasswordProfile, $AccountEnabled,
        [string]$MailNickname, [string]$UsageLocation, [string]$Department, [string]$JobTitle
    )
    Write-StubCall -Name "New-MgUser|$UserPrincipalName"
    [pscustomobject]@{ Id = 'member'; DisplayName = $DisplayName }
}

function Remove-MgUser {
    [CmdletBinding()]
    param([string]$UserId)
    Write-StubCall -Name "Remove-MgUser|$UserId"
}

function New-MgInvitation {
    [CmdletBinding()]
    param(
        [string]$InvitedUserEmailAddress, [string]$InvitedUserDisplayName, [string]$InviteRedirectUrl,
        $SendInvitationMessage, $InvitedUserMessageInfo
    )
    Write-StubCall -Name "New-MgInvitation|$InvitedUserEmailAddress"
}

function Get-MgGroup {
    [CmdletBinding()]
    param([string]$Filter, [Parameter(ValueFromRemainingArguments)]$Rest)
}

function New-MgGroup {
    [CmdletBinding()]
    param([string]$DisplayName, [string]$Description, $MailEnabled, $SecurityEnabled, [string]$MailNickname)
    [pscustomobject]@{ Id = 'group'; DisplayName = $DisplayName }
}

function Remove-MgGroup {
    [CmdletBinding()]
    param([string]$GroupId)
}

function Get-MgGroupMember {
    [CmdletBinding()]
    param([string]$GroupId, [Parameter(ValueFromRemainingArguments)]$Rest)
}

function New-MgGroupMember {
    [CmdletBinding()]
    param([string]$GroupId, [string]$DirectoryObjectId)
}
'@

    # Runs one script in a child process with the stubs shadowing the Graph commands, and returns
    # its exit code, its output and the stub's call log.
    function Invoke-AddressScript {
        param(
            [string]$ScriptPath,
            [string[]]$ArgumentList = @(),
            [string]$Domain = 'custom'
        )

        $logPath = Join-Path $script:Stub.Directory 'calls.log'
        Remove-Item -LiteralPath $logPath -Force -ErrorAction SilentlyContinue

        $run = Invoke-LabScriptWithStub -Stub $script:Stub -ScriptPath $ScriptPath -ArgumentList $ArgumentList -Environment @{
            SKYCRAFT_STUB_DOMAIN           = $Domain
            SKYCRAFT_STUB_LOG              = $logPath
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

    # The user principal names and the guest address a run named, from the stub's call log.
    function Get-NamedUpn {
        param([string[]]$Calls)
        @($Calls | ForEach-Object {
                if ($_ -match "^(Get-MgUser\|UserPrincipalName eq '(?<n>[^']+)'|New-MgUser\|(?<n>.+))$") { $Matches['n'] }
            } | Sort-Object -Unique)
    }
    function Get-NamedGuest {
        param([string[]]$Calls)
        @($Calls | ForEach-Object {
                if ($_ -match "^(Get-MgUser\|Mail eq '(?<n>[^']+)'|New-MgInvitation\|(?<n>.+))$") { $Matches['n'] }
            } | Sort-Object -Unique)
    }

    $script:Stub = Initialize-LabScriptStub -Name $script:StubModuleName -Command $script:StubCommands `
        -Body $script:StubBody -RequiredModule $script:RequiredModules

    # One invocation per scenario, reused by the assertions below - each child process costs
    # several seconds.
    $script:Runs = [ordered]@{
        'New-LabUser.ps1'        = Invoke-AddressScript -ScriptPath $script:NewUserPath
        'Test-Lab.ps1'           = Invoke-AddressScript -ScriptPath $script:TestLabPath
        'Remove-LabResource.ps1' = Invoke-AddressScript -ScriptPath $script:RemovePath -ArgumentList '-Force'
    }
    $script:Failed = [ordered]@{}
    foreach ($domainCase in 'fail', 'noinitial') {
        $script:Failed["New-LabUser.ps1/$domainCase"]        = Invoke-AddressScript -ScriptPath $script:NewUserPath -Domain $domainCase
        $script:Failed["Test-Lab.ps1/$domainCase"]           = Invoke-AddressScript -ScriptPath $script:TestLabPath -Domain $domainCase
        $script:Failed["Remove-LabResource.ps1/$domainCase"] = Invoke-AddressScript -ScriptPath $script:RemovePath -ArgumentList '-Force' -Domain $domainCase
    }
}

AfterAll {
    if ($script:Stub) { Remove-Item -LiteralPath $script:Stub.Directory -Recurse -Force -ErrorAction SilentlyContinue }
}

Describe 'Lab 1.1 addresses - test harness' {

    It 'reads three user principal names and the guest address from the guide' {
        $script:GuideUpns.Count | Should -Be 3
        $script:GuideGuest | Should -Match '^[^@\s]+@[^@\s]+\.[a-z]+$'
    }

    It 'shadows the real Microsoft Graph commands instead of touching a tenant' {
        foreach ($entry in @($script:Runs.GetEnumerator()) + @($script:Failed.GetEnumerator())) {
            $entry.Value.Refused | Should -BeFalse -Because "the harness must never fall through to the real Graph commands ($($entry.Key), exit $($entry.Value.ExitCode)): $($entry.Value.Output)"
        }
    }
}

Describe 'Lab 1.1 addresses - the scripts use the guide''s users and guest (#193)' {

    It '<script> names exactly the guide''s users, on the initial domain' -ForEach @(
        @{ script = 'New-LabUser.ps1' }
        @{ script = 'Test-Lab.ps1' }
        @{ script = 'Remove-LabResource.ps1' }
    ) {
        $run = $script:Runs[$script]
        $named = Get-NamedUpn -Calls $run.Calls
        $named | Should -Be ($script:GuideUpns | Sort-Object -Unique) -Because "the guide creates them on the tenant's initial domain; output was:`n$($run.Output)"
        ($named -join ' ') | Should -Not -Match ([regex]::Escape("@$($script:DefaultDomain)"))
    }

    It '<script> names exactly the guide''s guest' -ForEach @(
        @{ script = 'New-LabUser.ps1' }
        @{ script = 'Test-Lab.ps1' }
        @{ script = 'Remove-LabResource.ps1' }
    ) {
        $run = $script:Runs[$script]
        Get-NamedGuest -Calls $run.Calls | Should -Be @($script:GuideGuest) -Because "step 1.1.5 invites that address; output was:`n$($run.Output)"
    }

    It 'New-LabUser.ps1 creates the guide''s users and invites the guide''s guest' {
        $calls = $script:Runs['New-LabUser.ps1'].Calls
        @($calls | Where-Object { $_ -like 'New-MgUser|*' }).Count | Should -Be 3
        $calls | Should -Contain "New-MgInvitation|$($script:GuideGuest)"
    }

    It '<script> exits 0 against a tenant whose default domain is a custom one' -ForEach @(
        @{ script = 'New-LabUser.ps1' }
        @{ script = 'Test-Lab.ps1' }
        @{ script = 'Remove-LabResource.ps1' }
    ) {
        $run = $script:Runs[$script]
        $run.ExitCode | Should -Be 0 -Because "output was:`n$($run.Output)"
    }
}

Describe 'Lab 1.1 addresses - no guessed domain (#193)' {

    It '<script> stops with [ERROR] and exit 1 when the domain lookup <case>' -ForEach @(
        @{ script = 'New-LabUser.ps1';        domain = 'fail';      case = 'fails' }
        @{ script = 'Test-Lab.ps1';           domain = 'fail';      case = 'fails' }
        @{ script = 'Remove-LabResource.ps1'; domain = 'fail';      case = 'fails' }
        @{ script = 'New-LabUser.ps1';        domain = 'noinitial'; case = 'finds no initial domain' }
        @{ script = 'Test-Lab.ps1';           domain = 'noinitial'; case = 'finds no initial domain' }
        @{ script = 'Remove-LabResource.ps1'; domain = 'noinitial'; case = 'finds no initial domain' }
    ) {
        $run = $script:Failed["$script/$domain"]
        $run.ExitCode | Should -Be 1 -Because "a guessed domain names users the learner never created; output was:`n$($run.Output)"
        $run.Output | Should -Match '\[ERROR\][^\r\n]*initial \*\.onmicrosoft\.com domain'
        $run.Calls | Should -Contain 'Get-MgDomain'
        @($run.Calls | Where-Object { $_ -match '^(Get|New|Remove)-MgUser\||^New-MgInvitation\|' }) |
            Should -BeNullOrEmpty -Because 'nothing may be looked up, created or deleted on a guessed domain'
    }
}
