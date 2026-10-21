<#
.SYNOPSIS
    Validates the configuration of Lab 1.1 - Entra Users & Groups.

.DESCRIPTION
    This script verifies that the required Warcraft-themed users (Malfurion, Khadgar, Chromie)
    and Guest user (Illidan) exist in the tenant. It also checks that the security groups
    (Admins, Developers, Testers) exist and have the correct members assigned.

    Every check prints [OK] or [FAIL] and is counted. The summary states how many passed and how
    many failed, and the script exits 0 only when none failed. It exits 1 when any check failed,
    and also when it cannot sign in to Microsoft Graph or determine the tenant's initial domain,
    in which case no check runs (issue #241).

    It signs in with the same Microsoft Graph scopes as Remove-LabResource.ps1, which
    New-LabUser.ps1 requests too, so the consent given to the lab's setup covers the validator
    (issue #242). A sign-in that returns without a Graph context is a failed sign-in.

    It signs in to the tenant SKYCRAFT_GRAPH_TENANT_ID names, else to the tenant of the current Az
    context when Connect-AzAccount has run in this PowerShell session. With neither, Microsoft
    Graph picks the account's home tenant, which for a personal Microsoft account is not the lab
    tenant.

.EXAMPLE
    .\Test-Lab.ps1
    Runs the validation suite.

.NOTES
    Project: SkyCraft
    Lab: 1.1 - Entra Users & Groups
    Author: Marcin Biszczanik
    Date: 2026-01-10
#>

#Requires -Version 7.0
#Requires -Modules Microsoft.Graph.Authentication, Microsoft.Graph.Users, Microsoft.Graph.Groups, Microsoft.Graph.Identity.DirectoryManagement

[CmdletBinding()]
param()

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
# SKYCRAFT_GRAPH_TENANT_ID, else the Az context's tenant when Connect-AzAccount ran in this session.
# With none, Microsoft Graph picks the account's home tenant, which for a personal Microsoft account
# is not the lab tenant (#300).
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
    # imported (Connect-AzAccount ran in this session): Lab 1.1 does not require Az, and this must
    # not import it. Get-Command -Name would: it auto-loads the module, even with -ListImported.
    $azContextTenantId = $null
    if (Get-Module -Name Az.Accounts) {
        try { $azContextTenantId = [string](Get-AzContext -ErrorAction Stop).Tenant.Id } catch { $azContextTenantId = $null }
    }

    $plan = Get-LabGraphAuthPlan -Scope $Scope -TenantId $TenantId -AzContextTenantId $azContextTenantId

    if ($plan.Mode -eq 'Blocked') { throw $plan.Reason }

    if ($plan.Mode -eq 'Interactive') {
        if (-not $plan.TenantId) {
            Write-Host "  -> [INFO] No tenant named (-TenantId, SKYCRAFT_GRAPH_TENANT_ID or an Az context), so Microsoft Graph picks the account's home tenant. With a personal Microsoft account, set SKYCRAFT_GRAPH_TENANT_ID to the lab tenant's ID, or run Connect-AzAccount -TenantId <tenant id> first." -ForegroundColor Gray
        }

        # Reuse a signed-in context, which is what a learner running the lab expects. Note this is
        # only reached when no service principal is configured: an unattended run never gets here.
        # A partial one is not reused: the sign-in below replaces it, as it does one in a tenant
        # other than the plan's. A delegated one is reused only when its scopes cover every scope
        # this script requests, also when it reports no account, as a personal Microsoft account's
        # sign-in can (#300). An app-only one, told by AuthType alone, holds the app's application
        # permissions, which a new sign-in with -Scopes cannot add to, so it is reused as before.
        $existingContext = Get-MgContext
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

$ErrorActionPreference = 'Stop'
# Exit-Lab ends the script with exit code 0 or 1 and leaves an interactive session open (#257).
Import-Module (Join-Path $PSScriptRoot '../../../tools/LabCommon.psm1') -Force -Verbose:$false

Write-Host "=== Lab 1.1 Validation Script ===" -ForegroundColor Cyan -BackgroundColor Black

# Check Microsoft Graph Connection
try {
    Write-Host "`nChecking Microsoft Graph connection..." -ForegroundColor Yellow
    # The ReadWrite scopes Remove-LabResource.ps1 requests (and New-LabUser.ps1 with them), although
    # this script only reads: in Microsoft Graph each one includes its Read counterpart, so one
    # consent covers all three scripts. The Read.All scopes this used to ask for are consented
    # nowhere else in the lab, and in a tenant set up by its own scripts they were missing - the
    # sign-in then returned no context and no prompt (issue #242).
    $mgContext = Connect-LabGraph -Scope @(
        'User.ReadWrite.All'
        'Group.ReadWrite.All'
        'Directory.ReadWrite.All'
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
# above). Not the default domain, and no guess when the lookup fails - a guessed domain reports
# users the learner did create as missing.
try {
    $domain = Select-LabInitialDomain -Domain @(Get-MgDomain -ErrorAction Stop)
    Write-Host "Initial domain: $domain" -ForegroundColor Gray
}
catch {
    Write-Host "  -> [ERROR] Could not determine the tenant's initial *.onmicrosoft.com domain: $_" -ForegroundColor Red
    Exit-Lab -FailureCount 1
}

# The guest the guide invites in step 1.1.5 (and New-LabUser.ps1 invites).
$guestEmail = "istormrage@illidari.com"

# Define Expected Users (Warcraft Theme)
$expectedUsers = @(
    "malfurion.stormrage@$domain"
    "khadgar.archmage@$domain"
    "chromie.timewalker@$domain"
    $guestEmail
)

# Every check below ends in exactly one [OK] or [FAIL], and each is counted here: the summary
# states the counts and the exit code follows them (issue #241). Before that, a run in which every
# check printed [FAIL] still ended "validation complete" with exit 0, so a caller reading the
# exit code - and a learner reading the last line - could not tell it from a passing run.
$passCount = 0
$failCount = 0

# Validate Users
Write-Host "`n=== Validating Users ===" -ForegroundColor Cyan
foreach ($upn in $expectedUsers) {
    # A guest's user principal name is rewritten on invitation, so the guest is found by mail.
    if ($upn -eq $guestEmail) {
         $filter = "Mail eq '$upn'"
    } else {
         $filter = "UserPrincipalName eq '$upn'"
    }

    try {
        $user = Get-MgUser -Filter $filter -ErrorAction Stop
        if ($user) {
            Write-Host "[OK] User found: $($user.DisplayName) ($upn)" -ForegroundColor Green
            $passCount++
        }
        else {
            Write-Host "[FAIL] User missing: $upn" -ForegroundColor Red
            $failCount++
        }
    }
    catch {
        Write-Host "[FAIL] Error checking user $($upn): $_" -ForegroundColor Red
        $failCount++
    }
}

# Define Expected Groups
$expectedGroups = @(
    @{ Name = "SkyCraft-Admins";     ExpectedMember = "Malfurion Stormrage" }
    @{ Name = "SkyCraft-Developers"; ExpectedMember = "Khadgar Archmage" }
    @{ Name = "SkyCraft-Testers";    ExpectedMember = "Chromie Timewalker" }
)

# Validate Groups & Members
Write-Host "`n=== Validating Groups & Memberships ===" -ForegroundColor Cyan

# Two checks per group, always both: the group exists, and it holds its expected member. A group
# that is missing or cannot be read fails its membership check too, so every run counts the same
# ten checks and "Failed: N" always means N out of ten.
foreach ($item in $expectedGroups) {
    $groupName = $item.Name
    $group = $null
    try {
        $group = Get-MgGroup -Filter "DisplayName eq '$groupName'" -ErrorAction Stop
        if ($group) {
            Write-Host "[OK] Group exists: $groupName" -ForegroundColor Green
            $passCount++
        }
        else {
            Write-Host "[FAIL] Group missing: $groupName" -ForegroundColor Red
            $failCount++
        }
    }
    catch {
        Write-Host "[FAIL] Error checking group: $groupName. $_" -ForegroundColor Red
        $failCount++
    }

    if (-not $group) {
        Write-Host "  -> [FAIL] Membership of $($groupName): group not found or not readable, so $($item.ExpectedMember) cannot be a member." -ForegroundColor Red
        $failCount++
        continue
    }

    # -ErrorAction Stop on both lookups: a refused or throttled read must not pass for an empty
    # group or a missing member, so it is reported with the Graph error as one failed check.
    try {
        $members = Get-MgGroupMember -GroupId $group.Id -All -ErrorAction Stop
        if ($members) {
            # Fetch full user details for members to get DisplayName. Only user members: a nested
            # group, service principal or device has no /users/{id}, and its 404 must not fail a
            # group that does hold the expected user. Get-MgGroupMember returns directoryObjects,
            # whose derived type is in AdditionalProperties['@odata.type'].
            $memberFound = $false
            foreach ($member in $members) {
                $memberType = $member.AdditionalProperties['@odata.type']
                if ($memberType -ne '#microsoft.graph.user') {
                    Write-Host "  -> Member: $($member.Id) ($memberType) - not a user, skipped" -ForegroundColor Gray
                    continue
                }

                $memberUser = Get-MgUser -UserId $member.Id -ErrorAction Stop
                if ($memberUser) {
                    Write-Host "  -> Member: $($memberUser.DisplayName) ($($memberUser.UserPrincipalName))" -ForegroundColor Gray
                    if ($memberUser.DisplayName -eq $item.ExpectedMember) {
                        $memberFound = $true
                    }
                }
            }

            if ($memberFound) {
                 Write-Host "  -> [OK] Verify: $($item.ExpectedMember) is a member." -ForegroundColor Green
                 $passCount++
            }
            else {
                 Write-Host "  -> [FAIL] Verify: $($item.ExpectedMember) NOT found in group." -ForegroundColor Red
                 $failCount++
            }
        }
        else {
            # An empty group is missing its expected member just as surely as a group holding
            # someone else, so it fails the membership check rather than only warning.
            Write-Host "  -> [FAIL] No members found - expected $($item.ExpectedMember)." -ForegroundColor Red
            $failCount++
        }
    }
    catch {
        Write-Host "  -> [FAIL] Error checking members of $($groupName): $_" -ForegroundColor Red
        $failCount++
    }
}

Write-Host "`n=== Validation Summary ===" -ForegroundColor Cyan
Write-Host "  Passed: $passCount" -ForegroundColor Green
Write-Host "  Failed: $failCount" -ForegroundColor $(if ($failCount -gt 0) { 'Red' } else { 'Gray' })

if ($failCount -gt 0) {
    Write-Host "`nLab 1.1 validation failed: $failCount check(s) failed. See the [FAIL] lines above." -ForegroundColor Red
    Exit-Lab -FailureCount 1
}

Write-Host "`nLab 1.1 validation passed: all $passCount checks passed." -ForegroundColor Green
