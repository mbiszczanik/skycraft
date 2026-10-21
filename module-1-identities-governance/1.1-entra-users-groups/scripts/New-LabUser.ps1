<#
.SYNOPSIS
    Automates the creation of Warcraft-themed users and security groups for the SkyCraft Lab 1.1.

.DESCRIPTION
    This script creates three internal users (Malfurion, Khadgar, Chromie), invites one guest user (Illidan),
    and sets up security groups (Admins, Developers, Testers) with the corresponding memberships.
    It adheres to the SkyCraft PowerShell standards.

.PARAMETER TenantId
    The Microsoft Entra tenant ID to sign in to Microsoft Graph with. If omitted, the script uses
    SKYCRAFT_GRAPH_TENANT_ID, else the tenant of an Az context in this session, including one Az
    PowerShell restored from an earlier session. If a Microsoft Graph sign-in in this session is in
    another tenant than that Az context, it stops with [ERROR] and names both tenants. With none of
    them, Microsoft Graph picks the account's home tenant, which for a personal Microsoft account
    (most free Azure accounts) is not the lab tenant.

.PARAMETER DemoMode
    If specified, the script will simulate the creation process and output what would happen
    without making any actual changes to the tenant.

.PARAMETER InitialPassword
    Initial password applied to every seeded lab user (SecureString). If omitted, a random
    20-character password meeting Entra complexity is generated and printed once at the end
    of the run so the learner can record it. Never commit a real password to source control.

.EXAMPLE
    .\New-LabUser.ps1 -DemoMode
    Simulates the creation of all users and groups.

.EXAMPLE
    .\New-LabUser.ps1
    Creates the users and groups with an auto-generated password, in the tenant that
    SKYCRAFT_GRAPH_TENANT_ID or the current Az context names (see -TenantId).

.EXAMPLE
    .\New-LabUser.ps1 -TenantId '<your tenant id>'
    Creates them in the named tenant (Microsoft Entra ID > Overview > Tenant ID), for example for
    a personal Microsoft account with no Az context in the lab tenant.

.EXAMPLE
    $pwd = Read-Host -AsSecureString 'Lab password'
    .\New-LabUser.ps1 -InitialPassword $pwd

.NOTES
    Project: SkyCraft
    Lab: 1.1 - Entra Users & Groups
    Author: Marcin Biszczanik
    Date: 2026-01-10
#>

#Requires -Version 7.0
#Requires -Modules Microsoft.Graph.Authentication, Microsoft.Graph.Users, Microsoft.Graph.Groups, Microsoft.Graph.Identity.DirectoryManagement, Microsoft.Graph.Identity.SignIns

[CmdletBinding()]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Lab script; -DemoMode dry-run switch fulfils the ShouldProcess intent.')]
param (
    [Parameter(Mandatory = $false, HelpMessage = "The Microsoft Entra Tenant ID.")]
    [string]$TenantId,

    [Parameter(Mandatory = $false, HelpMessage = "Enable demo mode (skips actual creation).")]
    [switch]$DemoMode,

    [Parameter(Mandatory = $false, HelpMessage = "Initial password for all lab users (SecureString). Auto-generated if omitted.")]
    [SecureString]$InitialPassword
)

# --- Microsoft Graph sign-in (issue #76) ---------------------------------------------------
# Lab 1.1 is the only lab that talks to Entra ID rather than ARM, and the only one that hung.
# Connect-MgGraph with -Scopes binds the DELEGATED parameter set, so a run whose cached token
# needed a refresh the broker could not complete silently sat on a prompt nobody could answer -
# and the lab-cycle mitigation was a step timeout, which turns a hang into a killed phase rather
# than into a run that works.
#
# The sign-in is therefore a decision, and Get-LabGraphAuthPlan is that decision on its own,
# taking no Graph call with it so it can be tested without a tenant. It reads four environment
# variables and returns the APP-ONLY parameter set - client credentials, which never prompt -
# when a service principal is configured:
#
#   SKYCRAFT_GRAPH_TENANT_ID        the azureflame tenant the principal lives in
#   SKYCRAFT_GRAPH_CLIENT_ID        the app registration's application (client) ID
#   SKYCRAFT_GRAPH_CLIENT_SECRET    client secret, or
#   SKYCRAFT_GRAPH_CERT_THUMBPRINT  thumbprint of a certificate in CurrentUser\My (preferred)
#
# With none of them set it returns the interactive plan the lab has always used. Set by halves it
# returns neither: falling back to a prompt there would reintroduce exactly the hang this exists
# to remove, so a half-configured principal is reported rather than degraded into.
#
# The interactive sign-in names a tenant: -TenantId (New-LabUser.ps1 only), else
# SKYCRAFT_GRAPH_TENANT_ID, else the tenant of an Az context in the session, including one Az
# PowerShell restored from an earlier session. A Graph sign-in in this session in another tenant
# than that Az context stops the script instead of being replaced. With none, Microsoft Graph picks
# the account's home tenant, which for a personal Microsoft account is not the lab tenant (#300).
#
# The variables are deliberately NOT the Azure SDK's AZURE_CLIENT_ID / AZURE_TENANT_ID trio. Those
# are commonly already exported for the ARM subscription identity, which in this project is a
# different account from the one that administers Entra ID - consuming them would sign Graph in as
# the wrong principal, silently. See TROUBLESHOOTING.md for how to set these from a secret store.
#
# Duplicated verbatim in New-LabUser.ps1, Test-Lab.ps1 and Remove-LabResource.ps1, and in Lab
# 1.2's New-LabRoleAssignment.ps1, which reads Lab 1.1's users, rather than factored into a shared
# helper: docs/powershell-standards.md 7.3 requires every lab folder to be readable on its own,
# and tests/Lab11-Graph-Auth.Tests.ps1 asserts that the four copies do not drift apart.
function Get-LabGraphAuthPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string[]]$Scope = @(),

        [Parameter(Mandatory = $false)]
        [string]$TenantId,

        # The current Az context's tenant, passed in so the decision makes no Az call itself.
        [Parameter(Mandatory = $false)]
        [string]$AzContextTenantId,

        [Parameter(Mandatory = $false)]
        [hashtable]$EnvironmentValue,

        [Parameter(Mandatory = $false)]
        [bool]$Unattended
    )

    if (-not $PSBoundParameters.ContainsKey('EnvironmentValue')) {
        $EnvironmentValue = @{
            TenantId       = $env:SKYCRAFT_GRAPH_TENANT_ID
            ClientId       = $env:SKYCRAFT_GRAPH_CLIENT_ID
            ClientSecret   = $env:SKYCRAFT_GRAPH_CLIENT_SECRET
            CertThumbprint = $env:SKYCRAFT_GRAPH_CERT_THUMBPRINT
        }
    }

    if (-not $PSBoundParameters.ContainsKey('Unattended')) {
        # SKYCRAFT_UNATTENDED, and nothing else. Sniffing the console instead - [Console]::
        # IsInputRedirected was tried here - refuses to prompt a human who is sitting right there
        # the moment anything redirects a stream, and this lab is run BY HAND. Refusing a learner
        # a sign-in they could have completed is a worse failure than the hang it would catch,
        # because it is the case that actually happens. An automated caller says so explicitly.
        $Unattended = -not [string]::IsNullOrWhiteSpace($env:SKYCRAFT_UNATTENDED)
    }

    # Whitespace is absence. An exported-but-empty variable is a half-configured principal, not a
    # configured one, and a value pasted out of the portal often arrives with a trailing space.
    $setting = @{}
    foreach ($key in 'TenantId', 'ClientId', 'ClientSecret', 'CertThumbprint') {
        $value = [string]$EnvironmentValue[$key]
        $setting[$key] = if ([string]::IsNullOrWhiteSpace($value)) { $null } else { $value.Trim() }
    }

    # An explicit -TenantId beats the environment: the caller knows which tenant it means.
    $tenantSource = if ($setting['TenantId']) { 'SKYCRAFT_GRAPH_TENANT_ID' } else { $null }
    if (-not [string]::IsNullOrWhiteSpace($TenantId)) {
        $setting['TenantId'] = $TenantId.Trim()
        $tenantSource = '-TenantId'
    }

    $credentialSet = @('ClientId', 'ClientSecret', 'CertThumbprint') |
        Where-Object { $setting[$_] }

    if (@($credentialSet).Count -eq 0) {
        # Then the Az context's tenant. Without any tenant, a personal Microsoft account's sign-in
        # lands outside the lab tenant (live pass of 2026-10-20, #300). Interactive only: an
        # app-only principal names its tenant in its own configuration.
        if (-not $setting['TenantId'] -and -not [string]::IsNullOrWhiteSpace($AzContextTenantId)) {
            $setting['TenantId'] = $AzContextTenantId.Trim()
            $tenantSource = 'the Az context'
        }

        if ($Unattended) {
            return [pscustomobject]@{
                Mode             = 'Blocked'
                Reason           = 'No service principal is configured and this session cannot answer a sign-in prompt. Set SKYCRAFT_GRAPH_TENANT_ID, SKYCRAFT_GRAPH_CLIENT_ID and SKYCRAFT_GRAPH_CLIENT_SECRET (or SKYCRAFT_GRAPH_CERT_THUMBPRINT), or run the script from an interactive console. See TROUBLESHOOTING.md.'
                TenantId         = $setting['TenantId']
                ClientId         = $null
                ConnectParameter = $null
            }
        }

        # No ContextScope here on purpose: the interactive sign-in writes to the user token cache,
        # so a learner running three scripts in a row authenticates once, as before.
        $interactiveParameter = @{ Scopes = $Scope; ErrorAction = 'Stop' }
        $reason = 'No service principal configured - signing in interactively.'
        if ($setting['TenantId']) {
            $interactiveParameter['TenantId'] = $setting['TenantId']
            $reason = "No service principal configured - signing in interactively to tenant $($setting['TenantId']) (from $tenantSource)."
        }

        return [pscustomobject]@{
            Mode             = 'Interactive'
            Reason           = $reason
            TenantId         = $setting['TenantId']
            TenantSource     = $tenantSource
            ClientId         = $null
            ConnectParameter = $interactiveParameter
        }
    }

    $missing = @()
    if (-not $setting['ClientId']) { $missing += 'SKYCRAFT_GRAPH_CLIENT_ID' }
    if (-not $setting['TenantId']) { $missing += 'SKYCRAFT_GRAPH_TENANT_ID' }
    if (-not $setting['ClientSecret'] -and -not $setting['CertThumbprint']) {
        $missing += 'SKYCRAFT_GRAPH_CLIENT_SECRET or SKYCRAFT_GRAPH_CERT_THUMBPRINT'
    }

    if ($missing.Count -gt 0) {
        return [pscustomobject]@{
            Mode             = 'Blocked'
            Reason           = "The SkyCraft Graph service principal is only half configured - missing $($missing -join ', '). Set the rest, or unset every SKYCRAFT_GRAPH_* variable to sign in interactively."
            TenantId         = $setting['TenantId']
            ClientId         = $setting['ClientId']
            ConnectParameter = $null
        }
    }

    # Certificate before secret when both are set: it is the credential that does not sit in an
    # environment variable, and the one TROUBLESHOOTING.md documents first.
    if ($setting['CertThumbprint']) {
        return [pscustomobject]@{
            Mode             = 'Certificate'
            Reason           = "Signing in app-only as $($setting['ClientId']) with certificate $($setting['CertThumbprint'])."
            TenantId         = $setting['TenantId']
            ClientId         = $setting['ClientId']
            ConnectParameter = @{
                TenantId              = $setting['TenantId']
                ClientId              = $setting['ClientId']
                CertificateThumbprint = $setting['CertThumbprint']
                ContextScope          = 'Process'
                NoWelcome             = $true
                ErrorAction           = 'Stop'
            }
        }
    }

    # AppendChar rather than ConvertTo-SecureString -AsPlainText: the secret never becomes a
    # [string] this script owns, and the analyzer rule that forbids the shortcut needs no
    # suppression. The plan carries the credential and never the plaintext, so printing or logging
    # the plan cannot spill it.
    $secureSecret = [System.Security.SecureString]::new()
    foreach ($character in $setting['ClientSecret'].ToCharArray()) { $secureSecret.AppendChar($character) }
    $secureSecret.MakeReadOnly()

    return [pscustomobject]@{
        Mode             = 'ClientSecret'
        Reason           = "Signing in app-only as $($setting['ClientId']) with a client secret."
        TenantId         = $setting['TenantId']
        ClientId         = $setting['ClientId']
        ConnectParameter = @{
            TenantId               = $setting['TenantId']
            ClientSecretCredential = [System.Management.Automation.PSCredential]::new($setting['ClientId'], $secureSecret)
            ContextScope           = 'Process'
            NoWelcome              = $true
            ErrorAction            = 'Stop'
        }
    }
}

# Applies the plan above and returns the resulting Graph context. Throws on a plan that cannot
# sign in, so the caller reports one clear failure instead of waiting out a prompt.
function Connect-LabGraph {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string[]]$Scope,

        [Parameter(Mandatory = $false)]
        [string]$TenantId
    )

    # A context is signed in only when it names a tenant and an identity - an account, or an app
    # name (app-only, or a delegated sign-in that reports no account, #300). Connect-MgGraph can
    # leave one that names neither and still return without an error: a delegated sign-in for
    # scopes the account has never consented to does exactly that, with no consent prompt (issue
    # #242). Accepting it printed "Connected to Tenant:  as", and every Graph call after it failed
    # with "Authentication needed". One test, used for both the context reused below and the one
    # a sign-in leaves.
    $isSignedIn = { param($context) [bool]($context -and $context.TenantId -and ($context.Account -or $context.AppName)) }

    # The requested scopes a delegated context does not hold (issue #273). A context left in the
    # session by an earlier `Connect-MgGraph -Scopes User.Read.All`, or by another tool, is signed
    # in but cannot write: reused as is, the script failed later with a 403 on its first write. A
    # ReadWrite scope covers its Read counterpart (User.ReadWrite.All covers User.Read.All), as it
    # does in Microsoft Graph; the comparison ignores case, as scope names do.
    $missingScope = {
        param($context, [string[]]$requested)
        $granted = @($context.Scopes | ForEach-Object { [string]$_ })
        @($requested | Where-Object {
            $readWrite = $_ -replace '^([^.]+)\.Read(?=\.|$)', '$1.ReadWrite'
            ($granted -notcontains $_) -and ($granted -notcontains $readWrite)
        })
    }

    # The Az context's tenant, for a plan given no other. Read only when Az.Accounts is already
    # imported: Lab 1.1 does not require Az, and this must not import it. Get-Command -Name would:
    # it auto-loads the module, even with -ListImported. Imported is not signed in here: Az
    # PowerShell restores the context it saved in an earlier session (context autosave).
    $azContextTenantId = $null
    if (Get-Module -Name Az.Accounts) {
        try { $azContextTenantId = [string](Get-AzContext -ErrorAction Stop).Tenant.Id } catch { $azContextTenantId = $null }
    }

    $plan = Get-LabGraphAuthPlan -Scope $Scope -TenantId $TenantId -AzContextTenantId $azContextTenantId

    if ($plan.Mode -eq 'Blocked') { throw $plan.Reason }

    if ($plan.Mode -eq 'Interactive') {
        $existingContext = Get-MgContext

        # A tenant taken from the Az context, which may be a restored one, does not silently
        # replace a Graph sign-in in another tenant: the learner chooses, before anything is
        # created, checked or deleted in either (#300).
        if ($plan.TenantSource -eq 'the Az context' -and (& $isSignedIn $existingContext) -and $existingContext.TenantId -ne $plan.TenantId) {
            throw "Microsoft Graph is signed in to tenant $($existingContext.TenantId) in this session, but the Az context names tenant $($plan.TenantId) (Az PowerShell may have restored it from an earlier session). To use tenant $($existingContext.TenantId), set SKYCRAFT_GRAPH_TENANT_ID to it or run Connect-AzAccount -TenantId $($existingContext.TenantId). To use tenant $($plan.TenantId), run Disconnect-MgGraph. Then run the script again."
        }

        # Reuse a signed-in context, which is what a learner running the lab expects. Note this is
        # only reached when no service principal is configured: an unattended run never gets here.
        # A partial one is not reused: the sign-in below replaces it, as it does one in a tenant
        # other than the one -TenantId or SKYCRAFT_GRAPH_TENANT_ID names. A delegated one is reused
        # only when its scopes cover every scope this script requests, also when it reports no
        # account, as a personal Microsoft account's sign-in can (#300). An app-only one, told by
        # AuthType alone, holds the app's application permissions, which a new sign-in with -Scopes
        # cannot add to, so it is reused as before.
        if ((& $isSignedIn $existingContext) -and (-not $plan.TenantId -or $existingContext.TenantId -eq $plan.TenantId)) {
            $isAppOnly = "$($existingContext.AuthType)" -eq 'AppOnly'
            $missing = @(if (-not $isAppOnly) { & $missingScope $existingContext $Scope })
            if ($missing.Count -eq 0) {
                return $existingContext
            }
            Write-Host "  -> The Microsoft Graph context in this session lacks $($missing -join ', ') - signing in again with the scopes this script requests." -ForegroundColor Yellow
        }
    }
    elseif (Get-MgContext) {
        # A cached DELEGATED context is exactly what hangs on refresh, so app-only never reuses
        # one - it replaces it.
        Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null
    }

    Write-Host "  -> $($plan.Reason)" -ForegroundColor Yellow
    if ($plan.Mode -eq 'Interactive' -and -not $plan.TenantId) {
        Write-Host "  -> [INFO] No tenant named (-TenantId, SKYCRAFT_GRAPH_TENANT_ID or an Az context), so Microsoft Graph picks the account's home tenant. With a personal Microsoft account, sign in first with Connect-MgGraph -TenantId <tenant id> and the scopes in TROUBLESHOOTING.md, or set SKYCRAFT_GRAPH_TENANT_ID to the lab tenant's ID, then run the script again." -ForegroundColor Gray
    }

    $connectParameter = $plan.ConnectParameter
    Connect-MgGraph @connectParameter

    $context = Get-MgContext
    if (-not (& $isSignedIn $context)) {
        throw "Microsoft Graph sign-in did not complete: Connect-MgGraph returned without an error but left no signed-in account or tenant. A likely cause is missing consent for the permissions this script requests ($($Scope -join ', ')), or for the app registration's application permissions when signing in app-only. See TROUBLESHOOTING.md."
    }

    return $context
}

# --- The users' domain (issues #193, #237) --------------------------------------------------
# Lab 1.1 creates its users on the tenant's INITIAL *.onmicrosoft.com domain, the one the guide's
# '<name>@[yourtenant].onmicrosoft.com' means. Not the default domain: in a tenant whose default
# is a custom domain, that names users the guide never creates. And no guess when the tenant
# lists no initial domain: a guessed domain creates, checks, assigns or deletes users nobody
# meant. Every Module 1 script that builds a Lab 1.1 user's address picks the domain with this
# function, given the tenant's domains as Get-MgDomain (or GET /v1.0/domains) returns them:
# New-LabUser.ps1, Test-Lab.ps1 and Remove-LabResource.ps1 here, New-LabRoleAssignment.ps1 and
# Deploy-Bicep.ps1 in Lab 1.2. The copies are byte-identical, for the reason given above
# Get-LabGraphAuthPlan, and tests/Module1-Initial-Domain.Tests.ps1 holds them together.
function Select-LabInitialDomain {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [AllowNull()]
        [object[]]$Domain
    )

    $initial = @($Domain | Where-Object { $_ -and $_.IsInitial -eq $true } | ForEach-Object { [string]$_.Id } | Where-Object { $_ })
    if ($initial.Count -eq 0) { throw 'the tenant lists no domain marked IsInitial' }
    return $initial[0]
}

function New-LabRandomPassword {
    $upper   = [char[]]'ABCDEFGHJKLMNPQRSTUVWXYZ'
    $lower   = [char[]]'abcdefghijkmnpqrstuvwxyz'
    $digits  = [char[]]'23456789'
    $symbols = [char[]]'!@#$%^&*()-_=+[]{}'
    $pool    = $upper + $lower + $digits + $symbols
    $chars = @(
        (Get-Random -InputObject $upper   -Count 3)
        (Get-Random -InputObject $lower   -Count 3)
        (Get-Random -InputObject $digits  -Count 3)
        (Get-Random -InputObject $symbols -Count 3)
        (Get-Random -InputObject $pool    -Count 8)
    ) | ForEach-Object { $_ }
    -join ($chars | Sort-Object { Get-Random })
}

$passwordAutoGenerated = $false
if (-not $InitialPassword) {
    $plainPassword = New-LabRandomPassword
    $passwordAutoGenerated = $true
}
else {
    $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($InitialPassword)
    try { $plainPassword = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr) }
    finally { [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
}

Write-Host "=== Lab 1.1: Create Users & Groups ===" -ForegroundColor Cyan -BackgroundColor Black

$ErrorActionPreference = 'Stop'
# Exit-Lab ends the script with exit code 0 or 1 and leaves an interactive session open (#257).
Import-Module (Join-Path $PSScriptRoot '../../../tools/LabCommon.psm1') -Force -Verbose:$false

# Connect to Graph
try {
    Write-Host "Checking Microsoft Graph connection..." -ForegroundColor Yellow
    $mgContext = Connect-LabGraph -TenantId $TenantId -Scope @(
        'User.ReadWrite.All'
        'Group.ReadWrite.All'
        'Directory.ReadWrite.All'
        'Domain.Read.All'
        'User.Invite.All'
    )
    # A delegated sign-in can report no account (#300); its AppName is the client tool, not the user.
    $identity = if ($mgContext.Account) { $mgContext.Account } elseif ("$($mgContext.AuthType)" -eq 'AppOnly') { $mgContext.AppName } else { 'a delegated sign-in (no account reported)' }
    Write-Host "Connected to Tenant: $($mgContext.TenantId) as $identity" -ForegroundColor Green
}
catch {
    Write-Host "  -> [ERROR] Failed to connect to Microsoft Graph: $_" -ForegroundColor Red
    Exit-Lab -FailureCount 1
}

# Resolve the users' domain: the tenant's initial *.onmicrosoft.com domain (Select-LabInitialDomain
# above), never the default domain and never a guess.
Write-Host "Resolving the initial domain..." -ForegroundColor Yellow
try {
    $domain = Select-LabInitialDomain -Domain @(Get-MgDomain -ErrorAction Stop)
    Write-Host "  -> Initial domain: $domain" -ForegroundColor Green
}
catch {
    Write-Host "  -> [ERROR] Could not determine the tenant's initial *.onmicrosoft.com domain: $_" -ForegroundColor Red
    Exit-Lab -FailureCount 1
}

# Define Users (Warcraft Theme)
$users = @(
    @{
        UserPrincipalName = "malfurion.stormrage"
        DisplayName       = "Malfurion Stormrage"
        Department        = "IT Operations"
        JobTitle          = "Cloud Infrastructure Manager"
    },
    @{
        UserPrincipalName = "khadgar.archmage"
        DisplayName       = "Khadgar Archmage"
        Department        = "Development"
        JobTitle          = "Cloud Developer"
    },
    @{
        UserPrincipalName = "chromie.timewalker"
        DisplayName       = "Chromie Timewalker"
        Department        = "QA"
        JobTitle          = "Quality Assurance Lead"
    }
)

Write-Host "`n=== Creating Internal Users ===" -ForegroundColor Cyan

foreach ($user in $users) {
    $upn = "$($user.UserPrincipalName)@$domain"
    
    try {
        Write-Host "Processing User: $($user.DisplayName)..." -ForegroundColor Yellow
        if ($DemoMode) {
            Write-Host "  -> [DEMO] Should create user: $upn" -ForegroundColor Gray
        }
        else {
            # Check if user exists
            $existing = Get-MgUser -Filter "UserPrincipalName eq '$upn'" -ErrorAction SilentlyContinue
            if ($existing) {
                Write-Host "  -> [INFO] User $upn already exists. Skipping." -ForegroundColor Gray
            }
            else {
                $userParams = @{
                    UserPrincipalName = $upn
                    DisplayName       = $user.DisplayName
                    PasswordProfile   = @{ Password = $plainPassword; ForceChangePasswordNextSignIn = $false }
                    AccountEnabled    = $true
                    MailNickname      = $user.UserPrincipalName
                    UsageLocation     = "US"
                    Department        = $user.Department
                    JobTitle          = $user.JobTitle
                }
                $newUser = New-MgUser @userParams -ErrorAction Stop
                Write-Host "  -> [SUCCESS] Created user: $($newUser.DisplayName)" -ForegroundColor Green
            }
        }
    }
    catch {
        Write-Host "  -> [ERROR] Failed to create user $upn. $_" -ForegroundColor Red
    }
}

Write-Host "`n=== Inviting Guest User ===" -ForegroundColor Cyan

$guestUsers = @(
    @{
        DisplayName = "Illidan Stormrage"
        Email       = "istormrage@illidari.com" # The address the guide invites in step 1.1.5
        Message     = "You are not prepared... to miss this collaboration."
    }
)

foreach ($guest in $guestUsers) {
    try {
        Write-Host "Inviting Guest: $($guest.DisplayName)..." -ForegroundColor Yellow
        if ($DemoMode) {
            Write-Host "  -> [DEMO] Should invite guest: $($guest.Email)" -ForegroundColor Gray
        }
        else {
            # Check if user invite exists (by mail) - Approximate check
            $existing = Get-MgUser -Filter "Mail eq '$($guest.Email)'" -ErrorAction SilentlyContinue
            if ($existing) {
                Write-Host "  -> [INFO] User with email $($guest.Email) already exists. Skipping invite." -ForegroundColor Gray
            }
            else {
                $invitationParams = @{
                    InvitedUserEmailAddress = $guest.Email
                    InvitedUserDisplayName  = $guest.DisplayName
                    InviteRedirectUrl       = "https://myapplications.microsoft.com"
                    SendInvitationMessage   = $false # Don't send actual email for lab
                    InvitedUserMessageInfo  = @{ CustomizedMessageBody = $guest.Message }
                }
                New-MgInvitation @invitationParams -ErrorAction Stop
                Write-Host "  -> [SUCCESS] Invitation created for: $($guest.Email)" -ForegroundColor Green
            }
        }
    }
    catch {
        Write-Host "  -> [ERROR] Failed to invite guest $($guest.Email). $_" -ForegroundColor Red
    }
}

Write-Host "`n=== Creating Security Groups ===" -ForegroundColor Cyan

$groups = @(
    @{
        DisplayName = "SkyCraft-Admins"
        Description = "Administrative team for SkyCraft infrastructure"
    },
    @{
        DisplayName = "SkyCraft-Developers"
        Description = "Development team for SkyCraft deployment"
    },
    @{
        DisplayName = "SkyCraft-Testers"
        Description = "Testing and monitoring team"
    }
)

foreach ($group in $groups) {
    try {
        Write-Host "Processing Group: $($group.DisplayName)..." -ForegroundColor Yellow
        if ($DemoMode) {
             Write-Host "  -> [DEMO] Should create group: $($group.DisplayName)" -ForegroundColor Gray
        }
        else {
            $existing = Get-MgGroup -Filter "DisplayName eq '$($group.DisplayName)'" -ErrorAction SilentlyContinue
            if ($existing) {
                Write-Host "  -> [INFO] Group exists. Skipping." -ForegroundColor Gray
            }
            else {
                $groupParams = @{
                    DisplayName     = $group.DisplayName
                    Description     = $group.Description
                    MailEnabled     = $false
                    SecurityEnabled = $true
                    MailNickname    = ($group.DisplayName -replace "[^a-zA-Z0-9]", "")
                }
                $newGroup = New-MgGroup @groupParams -ErrorAction Stop
                Write-Host "  -> [SUCCESS] Created group: $($newGroup.DisplayName)" -ForegroundColor Green
            }
        }
    }
    catch {
         Write-Host "  -> [ERROR] Failed to create group $($group.DisplayName). $_" -ForegroundColor Red
    }
}

Write-Host "`n=== Assigning Memberships ===" -ForegroundColor Cyan

$assignments = @(
    @{ GroupName = "SkyCraft-Admins";     UserUPN = "malfurion.stormrage@$domain" },
    @{ GroupName = "SkyCraft-Developers"; UserUPN = "khadgar.archmage@$domain" },
    @{ GroupName = "SkyCraft-Testers";    UserUPN = "chromie.timewalker@$domain" }
)

foreach ($assign in $assignments) {
    try {
        Write-Host "Assigning $($assign.UserUPN) to $($assign.GroupName)..." -ForegroundColor Yellow
        if ($DemoMode) {
            Write-Host "  -> [DEMO] Should assign membership." -ForegroundColor Gray
        }
        else {
            $user = Get-MgUser -Filter "UserPrincipalName eq '$($assign.UserUPN)'" -ErrorAction SilentlyContinue
            $group = Get-MgGroup -Filter "DisplayName eq '$($assign.GroupName)'" -ErrorAction SilentlyContinue

            if ($user -and $group) {
                # Check if already member
                $isMember = Get-MgGroupMember -GroupId $group.Id -Filter "id eq '$($user.Id)'" -ErrorAction SilentlyContinue
                if ($isMember) {
                    Write-Host "  -> [INFO] Already a member." -ForegroundColor Gray
                }
                else {
                    New-MgGroupMember -GroupId $group.Id -DirectoryObjectId $user.Id -ErrorAction Stop
                    Write-Host "  -> [SUCCESS] member added." -ForegroundColor Green
                }
            }
            else {
                Write-Host "  -> [WARNING] User or Group not found. Skipping." -ForegroundColor Yellow
            }
        }
    }
    catch {
        Write-Host "  -> [ERROR] Failed to assign membership. $_" -ForegroundColor Red
    }
}

Write-Host "`n=== Automation Complete ===" -ForegroundColor Cyan
Write-Host "Lab 1.1 setup finished." -ForegroundColor Green

if ($passwordAutoGenerated -and -not $DemoMode) {
    Write-Host "`n=== Auto-Generated Initial Password ===" -ForegroundColor Yellow
    Write-Host "Record this now — it will not be shown again:" -ForegroundColor Yellow
    Write-Host "  $plainPassword" -ForegroundColor Cyan
    Write-Host "(Rotate via Microsoft-Entra-ID > Users > Reset password once the lab is complete.)" -ForegroundColor Gray
}

Remove-Variable -Name plainPassword -ErrorAction SilentlyContinue
Exit-Lab -FailureCount 0
