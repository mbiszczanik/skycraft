<#
.SYNOPSIS
    Assigns RBAC roles for Lab 1.2 - Identities & Governance.

.DESCRIPTION
    This script assigns the required Azure RBAC roles to the Warcraft-themed users and groups.
    It finds the users and groups by name through Microsoft Graph PowerShell (Connect-MgGraph),
    and reads and creates the role assignments through the Azure Resource Manager role
    assignments API (tools/LabCommon.psm1), which needs only the Az sign-in's ARM token. The Az
    role cmdlets are not used: every form of Get-AzRoleAssignment, and New-AzRoleAssignment,
    calls Microsoft Graph through the Az sign-in and fails where the tenant asks for interaction
    before it issues that token (issue #397).

    A principal that cannot be looked up, a name that matches several principals, a role
    assignment read that fails, an Owner for Malfurion that has a condition (not the lab's; guide
    Troubleshooting, Issue 6) and a create that fails are each an [ERROR] and counted; the script
    exits 1 when there was one. A failed read is never taken for "not assigned yet".

    It signs in to Microsoft Graph the way Lab 1.1's scripts do, reusing a Graph context already
    in the session only when that context holds the scopes it requests, and it looks Lab 1.1's
    users up on the tenant's initial *.onmicrosoft.com domain, where Lab 1.1 creates them. When
    the tenant lists no initial domain it stops with [ERROR] and exit code 1. When a Microsoft
    Graph module it calls is not installed (Azure Cloud Shell does not ship Microsoft.Graph.Users),
    it names the module and the command that installs it, and exits 1 before signing in (issue #375).

    It sets up Azure PowerShell first, running Connect-AzAccount when the session has no Az
    context, then signs in to Microsoft Graph in the tenant SKYCRAFT_GRAPH_TENANT_ID names, else in
    the tenant of a Microsoft Graph sign-in already in this session (one that lacks a scope it
    requests is replaced in its own tenant), else in the Az context's tenant, so a personal
    Microsoft account reaches the lab tenant too. The Az context can be one Az PowerShell
    restored from an earlier session: if a Microsoft Graph sign-in in this session is in another
    tenant, the script stops with [ERROR] and names both tenants.

    This is the imperative path. The declarative equivalent is bicep/role-assignments.bicep,
    deployed by Deploy-Bicep.ps1 -IncludeRoleAssignments, which creates the same five assignments
    under names derived from guid(scope, role, principal). The paths can be mixed: this script
    skips an assignment that already exists, whichever path created it, and Deploy-Bicep.ps1
    lists the existing ones in the template's parExistingAssignments, so the template creates
    only the missing ones (issue #406).
    
    Assignments:
    - Malfurion Stormrage -> Owner (Subscription)
    - SkyCraft-Developers -> Contributor (dev-skycraft-swc-rg)
    - SkyCraft-Testers    -> Reader (dev-skycraft-swc-rg, prod-skycraft-swc-rg)
    - Illidan Stormrage   -> Reader (platform-skycraft-swc-rg)

.EXAMPLE
    .\New-LabRoleAssignment.ps1
    Assigns roles to the current subscription.

.NOTES
    Project: SkyCraft
    Lab: 1.2 - RBAC
#>

#Requires -Version 7.0
#Requires -Modules Az.Accounts, Az.Resources

[CmdletBinding()]
param()

# --- Microsoft Graph sign-in (issues #76, #242, #273) -------------------------------------
# This script reads the users and groups Lab 1.1 creates, through Microsoft Graph, so it signs in
# the way Lab 1.1's scripts do. Get-LabGraphAuthPlan and Connect-LabGraph are byte-identical copies
# of the functions in Lab 1.1's New-LabUser.ps1, Test-Lab.ps1 and Remove-LabResource.ps1, where
# their header explains them; tests/Lab11-Graph-Auth.Tests.ps1 asserts the four copies do not
# drift apart (docs/powershell-standards.md 7.3: each lab folder reads on its own). In short:
#
#   - With SKYCRAFT_GRAPH_TENANT_ID, SKYCRAFT_GRAPH_CLIENT_ID and SKYCRAFT_GRAPH_CLIENT_SECRET
#     (or SKYCRAFT_GRAPH_CERT_THUMBPRINT) set, it signs in app-only and never prompts. With none
#     set it signs in interactively; set by halves, or with SKYCRAFT_UNATTENDED and nothing else,
#     it refuses instead of waiting on a prompt nobody can answer.
#   - It reuses a Graph context already in the session only when that context is signed in and,
#     for a delegated one, holds every scope requested here (a ReadWrite scope covers its Read
#     counterpart). This script used to reuse any context at all, an empty one included (#273).
#   - A sign-in that returns without a signed-in context is an error, not a connection (#242).
#   - The interactive sign-in uses SKYCRAFT_GRAPH_TENANT_ID, else the tenant of a Graph sign-in in
#     the session (#408), else the Az context's tenant, so a personal Microsoft account reaches the
#     lab tenant after Connect-AzAccount alone (#300). A Graph sign-in in another tenant than the
#     Az context's stops the script instead of either winning silently: the Az context may be one
#     Az PowerShell restored from an earlier session.
#   - In Azure Cloud Shell it signs in with Cloud Shell's own sign-in (Get-AzAccessToken), which
#     never prompts; -CoveredBy below names the scope of that token that allows its reads (#418).
function Get-LabGraphAuthPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string[]]$Scope = @(),

        [Parameter(Mandatory = $false)]
        [string]$TenantId,

        # The tenant of a signed-in Graph context in the session, passed in for the same reason.
        [Parameter(Mandatory = $false)]
        [string]$GraphContextTenantId,

        # The current Az context's tenant, passed in so the decision makes no Az call itself.
        [Parameter(Mandatory = $false)]
        [string]$AzContextTenantId,

        [Parameter(Mandatory = $false)]
        [hashtable]$EnvironmentValue,

        [Parameter(Mandatory = $false)]
        [bool]$Unattended,

        # Running in Azure Cloud Shell; read from the host when omitted.
        [Parameter(Mandatory = $false)]
        [bool]$CloudShell
    )

    if (-not $PSBoundParameters.ContainsKey('CloudShell')) {
        $CloudShell = ($env:POWERSHELL_DISTRIBUTION_CHANNEL -eq 'CloudShell') -or ("$env:AZUREPS_HOST_ENVIRONMENT" -like 'cloud-shell*')
    }

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
        # Then the tenant of a Graph sign-in in this session, so a sign-in again for missing scopes
        # stays in it (#408), then the Az context's. Without any tenant, a personal Microsoft
        # account's sign-in lands outside the lab tenant (live pass of 2026-10-20, #300).
        # Interactive only: an app-only principal names its tenant in its own configuration.
        if (-not $setting['TenantId'] -and -not [string]::IsNullOrWhiteSpace($GraphContextTenantId)) {
            $setting['TenantId'] = $GraphContextTenantId.Trim()
            $tenantSource = 'the Microsoft Graph context'
        }
        if (-not $setting['TenantId'] -and -not [string]::IsNullOrWhiteSpace($AzContextTenantId)) {
            $setting['TenantId'] = $AzContextTenantId.Trim()
            $tenantSource = 'the Az context'
        }

        # Cloud Shell has no browser for an interactive sign-in, and security defaults refuse a
        # device code (AADSTS530035; on by default in tenants created from 2026-07-01). Its own
        # sign-in already holds a delegated Graph token, which never prompts, so it serves an
        # unattended run too (#418). TokenParameter is for Get-AzAccessToken.
        if ($CloudShell) {
            $tokenParameter = @{ ResourceTypeName = 'MSGraph'; AsSecureString = $true; ErrorAction = 'Stop' }
            $reason = "No service principal configured - in Azure Cloud Shell, signing in with Cloud Shell's own sign-in."
            if ($setting['TenantId']) {
                $tokenParameter['TenantId'] = $setting['TenantId']
                $reason = "No service principal configured - in Azure Cloud Shell, signing in with Cloud Shell's own sign-in to tenant $($setting['TenantId']) (from $tenantSource)."
            }

            return [pscustomobject]@{
                Mode             = 'CloudShell'
                Reason           = $reason
                TenantId         = $setting['TenantId']
                TenantSource     = $tenantSource
                ClientId         = $null
                ConnectParameter = $null
                TokenParameter   = $tokenParameter
            }
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
        [string]$TenantId,

        # Per requested scope, other scopes that allow every call this script makes with it, as the
        # Microsoft Graph permissions reference lists them (#418). Per script, not one table:
        # Directory.ReadWrite.All covers creating and reading users, not deleting them.
        [Parameter(Mandatory = $false)]
        [hashtable]$CoveredBy = @{}
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
    # does in Microsoft Graph, and so does a scope -CoveredBy names for it; the comparison ignores
    # case, as scope names do.
    $missingScope = {
        param($context, [string[]]$requested)
        $granted = @($context.Scopes | ForEach-Object { [string]$_ })
        @($requested | Where-Object {
            $readWrite = $_ -replace '^([^.]+)\.Read(?=\.|$)', '$1.ReadWrite'
            $covering = @($_, $readWrite) + @($CoveredBy[$_])
            -not ($covering | Where-Object { $_ -and ($granted -contains $_) })
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

    # The tenant of a Graph sign-in already in this session, ranked above the Az context (#408).
    $existingContext = Get-MgContext
    $graphContextTenantId = if (& $isSignedIn $existingContext) { [string]$existingContext.TenantId } else { $null }
    # The personal Microsoft account directory, which a failed sign-in can leave, is never a lab tenant (#408).
    if ($graphContextTenantId -eq '9188040d-6c67-4c5b-b112-36a304b66dad') { $graphContextTenantId = $null }

    $plan = Get-LabGraphAuthPlan -Scope $Scope -TenantId $TenantId -GraphContextTenantId $graphContextTenantId -AzContextTenantId $azContextTenantId

    if ($plan.Mode -eq 'Blocked') { throw $plan.Reason }

    if ($plan.Mode -in 'Interactive', 'CloudShell') {
        # The two implicit sources disagree: the Graph sign-in and an Az context, which may be a
        # restored one. Neither silently wins: the learner chooses, before anything is created,
        # checked or deleted in either tenant (#300). -TenantId or SKYCRAFT_GRAPH_TENANT_ID decides.
        if ($plan.TenantSource -eq 'the Microsoft Graph context' -and -not [string]::IsNullOrWhiteSpace($azContextTenantId) -and $azContextTenantId.Trim() -ne $plan.TenantId) {
            $azTenant = $azContextTenantId.Trim()
            throw "Microsoft Graph is signed in to tenant $($plan.TenantId) in this session, but the Az context names tenant $azTenant (Az PowerShell may have restored it from an earlier session). To use tenant $($plan.TenantId), set SKYCRAFT_GRAPH_TENANT_ID to it or run Connect-AzAccount -TenantId $($plan.TenantId). To use tenant $azTenant, run Disconnect-MgGraph. Then run the script again."
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
        Write-Host "  -> [INFO] No tenant named (-TenantId, SKYCRAFT_GRAPH_TENANT_ID, a Microsoft Graph sign-in or an Az context), so Microsoft Graph picks the account's home tenant. With a personal Microsoft account, sign in first with Connect-MgGraph -TenantId <tenant id> and the scopes in TROUBLESHOOTING.md, or set SKYCRAFT_GRAPH_TENANT_ID to the lab tenant's ID, then run the script again." -ForegroundColor Gray
    }

    $connectParameter = $plan.ConnectParameter
    if ($plan.Mode -eq 'CloudShell') {
        # Get-AzAccessToken loads Az.Accounts, which Cloud Shell ships.
        $tokenParameter = $plan.TokenParameter
        $connectParameter = @{ AccessToken = (Get-AzAccessToken @tokenParameter).Token; NoWelcome = $true; ErrorAction = 'Stop' }
    }
    Connect-MgGraph @connectParameter

    $context = Get-MgContext
    if (-not (& $isSignedIn $context)) {
        throw "Microsoft Graph sign-in did not complete: Connect-MgGraph returned without an error but left no signed-in account or tenant. A likely cause is missing consent for the permissions this script requests ($($Scope -join ', ')), or for the app registration's application permissions when signing in app-only. See TROUBLESHOOTING.md."
    }

    # Cloud Shell's token holds the scopes Cloud Shell was granted, not the requested ones: stop
    # before any Graph change when they fall short (#418).
    if ($plan.Mode -eq 'CloudShell') {
        $missing = @(& $missingScope $context $Scope)
        if ($missing.Count -gt 0) {
            Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null
            throw "In Azure Cloud Shell this script signs in with Cloud Shell's own sign-in, and its Microsoft Graph token lacks $($missing -join ', '), which this script needs. Cloud Shell has no browser for a sign-in with other permissions, and a tenant with security defaults refuses a device code sign-in (error 530035). Run this script in PowerShell 7 on your own machine, or do its steps in the Portal. See TROUBLESHOOTING.md."
        }
    }

    return $context
}

# --- The users' domain (issues #193, #237) --------------------------------------------------
# Lab 1.1 creates its users on the tenant's INITIAL *.onmicrosoft.com domain, the one its guide's
# '<name>@[yourtenant].onmicrosoft.com' means, so this script looks them up there. Not the default
# domain: in a tenant whose default is a custom domain, that names users Lab 1.1 never created.
# And no guess when the tenant lists no initial domain. A byte-identical copy of the function in
# Lab 1.1's scripts and in Deploy-Bicep.ps1; tests/Module1-Initial-Domain.Tests.ps1 holds the
# copies together.
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

$ErrorActionPreference = "Stop"
# Exit-Lab ends the script with exit code 0 or 1 and leaves an interactive session open (#257).
# The module's role assignment helpers use the ARM API, not Microsoft Graph (#397).
Import-Module (Join-Path $PSScriptRoot '../../../tools/LabCommon.psm1') -Force -Verbose:$false

# The Microsoft Graph modules this script calls, imported here rather than with '#Requires -Modules'
# (issue #375): Azure Cloud Shell does not ship Microsoft.Graph.Users, and #Requires would stop the
# script with PowerShell's own error, which names no install command. Import-LabModule imports them
# in this order and at one version (a session loads only one Microsoft.Graph.Authentication), or
# names the command that installs what is missing and returns $false.
# The Az modules stay in #Requires: Cloud Shell ships them, and they are imported before these.
$labModule = @(
    'Microsoft.Graph.Authentication'
    'Microsoft.Graph.Identity.DirectoryManagement'
    'Microsoft.Graph.Users'
    'Microsoft.Graph.Groups'
)
if (-not (Import-LabModule -Name $labModule)) { Exit-Lab -FailureCount 1 }

Write-Host "=== Lab 1.2: RBAC Role Assignment ===" -ForegroundColor Cyan -BackgroundColor Black

# 1. Connect to Azure PowerShell (for Role Assignment). First, so the Graph sign-in below can take
# its tenant from the Az context, also one Connect-AzAccount creates here (#300).
try {
    Write-Host "`nChecking Azure PowerShell connection..." -ForegroundColor Yellow
    $azContext = Get-AzContext
    if (-not $azContext) {
        Write-Host "Connecting to Azure..." -ForegroundColor Yellow
        Connect-AzAccount -ErrorAction Stop
        $azContext = Get-AzContext
    }
    $subscriptionId = $azContext.Subscription.Id
    Write-Host "Connected to Subscription: $($azContext.Subscription.Name) ($subscriptionId)" -ForegroundColor Green
}
catch {
    Write-Host "  -> [ERROR] Failed to connect to Azure: $_" -ForegroundColor Red
    Exit-Lab -FailureCount 1
}

# 2. Connect to Microsoft Graph (for User/Group/Domain resolution)
try {
    Write-Host "`nChecking Microsoft Graph connection..." -ForegroundColor Yellow
    # The scopes Lab 1.1's Test-Lab.ps1 requests, although this script only reads: each ReadWrite
    # scope includes its Read counterpart, so the consent Lab 1.1 already gave covers it, and a
    # context Lab 1.1 left in this session is reused. The Read.All scopes this used to ask for may
    # be consented nowhere in a tenant set up by the lab's scripts, and a sign-in for them then
    # returned no context and no prompt (issue #242).
    $mgContext = Connect-LabGraph -Scope @(
        'User.ReadWrite.All'
        'Group.ReadWrite.All'
        'Directory.ReadWrite.All'
    ) -CoveredBy @{
        # Only reads here; Directory.ReadWrite.All reads users, which Cloud Shell's token allows (#418).
        'User.ReadWrite.All' = 'Directory.ReadWrite.All'
    }
    # A delegated sign-in can report no account (#300); its AppName is the client tool, not the user.
    $identity = if ($mgContext.Account) { $mgContext.Account } elseif ("$($mgContext.AuthType)" -eq 'AppOnly') { $mgContext.AppName } else { 'a delegated sign-in (no account reported)' }
    Write-Host "Connected to Tenant: $($mgContext.TenantId) as $identity" -ForegroundColor Green
}
catch {
    Write-Host "  -> [ERROR] Failed to connect to Microsoft Graph: $_" -ForegroundColor Red
    # Connect-LabGraph's own stops (tenant mismatch, blocked plan, no context) already say what to do.
    if ("$_" -notmatch 'SKYCRAFT_GRAPH_|TROUBLESHOOTING\.md') {
        Write-Host "     $(Get-LabGraphSignInHint -Client MgGraph)" -ForegroundColor Gray
    }
    Exit-Lab -FailureCount 1
}

# Tenant Check
if ($azContext.Tenant.Id -ne $mgContext.TenantId) {
    Write-Host "`n[WARNING] Tenant Mismatch Detected!" -ForegroundColor Red
    Write-Host "Azure Subscription Tenant: $($azContext.Tenant.Id)" -ForegroundColor Yellow
    Write-Host "Microsoft Graph Tenant:    $($mgContext.TenantId)" -ForegroundColor Yellow
    Write-Host "Role Assignments between different tenants are not possible unless B2B is configured." -ForegroundColor Red
    Write-Host "Please ensure your Azure Context and Graph Context point to the same directory." -ForegroundColor Red
    # We will not exit, but subsequent commands will likely fail with BadRequest
}

# 3. Resolve the users' domain: the tenant's initial *.onmicrosoft.com domain, where Lab 1.1
# creates them (issue #237, the Lab 1.2 twin of #193), with the same Select-LabInitialDomain Lab
# 1.1's scripts use. Not the default domain, and no guess when the lookup fails.
try {
    $domain = Select-LabInitialDomain -Domain @(Get-MgDomain -ErrorAction Stop)
    Write-Host "Initial domain: $domain" -ForegroundColor Gray
}
catch {
    Write-Host "  -> [ERROR] Could not determine the tenant's initial *.onmicrosoft.com domain: $_" -ForegroundColor Red
    Exit-Lab -FailureCount 1
}

# 4. Define Assignments
$assignments = @(
    # Malfurion -> Owner on Subscription
    @{
        Type           = "User"
        PrincipalName  = "malfurion.stormrage@$domain"
        Role           = "Owner"
        Scope          = "/subscriptions/$subscriptionId"
        ScopeName      = "Subscription Root"
        NoCondition    = $true
    },
    # Developers -> Contributor on Dev RG
    @{
        Type           = "Group"
        PrincipalName  = "SkyCraft-Developers"
        Role           = "Contributor"
        Scope          = "/subscriptions/$subscriptionId/resourceGroups/dev-skycraft-swc-rg"
        ScopeName      = "dev-skycraft-swc-rg"
    },
    # Testers -> Reader on Dev RG
    @{
        Type           = "Group"
        PrincipalName  = "SkyCraft-Testers"
        Role           = "Reader"
        Scope          = "/subscriptions/$subscriptionId/resourceGroups/dev-skycraft-swc-rg"
        ScopeName      = "dev-skycraft-swc-rg"
    },
    # Testers -> Reader on Prod RG
    @{
        Type           = "Group"
        PrincipalName  = "SkyCraft-Testers"
        Role           = "Reader"
        Scope          = "/subscriptions/$subscriptionId/resourceGroups/prod-skycraft-swc-rg"
        ScopeName      = "prod-skycraft-swc-rg"
    },
    # Illidan -> Reader on Platform RG
    @{
        Type           = "Guest"
        PrincipalName  = "istormrage@illidari.com" # Search by mail
        Role           = "Reader"
        Scope          = "/subscriptions/$subscriptionId/resourceGroups/platform-skycraft-swc-rg"
        ScopeName      = "platform-skycraft-swc-rg"
    }
)

Write-Host "`n=== Processing Assignments ===" -ForegroundColor Cyan

# Every [ERROR] below is counted, and the script exits 1 at the end when there was one.
$failCount = 0

foreach ($item in $assignments) {
    Write-Host "Processing: $($item.PrincipalName) -> $($item.Role) on $($item.ScopeName)..." -NoNewline

    # A. Resolve Principal ObjectId (Microsoft Graph). A guest is found by mail: its
    # userPrincipalName is rewritten to <alias>_<domain>#EXT#@<tenant> on invitation.
    $found = @()
    try {
        if ($item.Type -eq "Group") {
            $obj = Get-MgGroup -Filter "DisplayName eq '$($item.PrincipalName)'" -ErrorAction Stop
        }
        elseif ($item.Type -eq "Guest") {
            $obj = Get-MgUser -Filter "Mail eq '$($item.PrincipalName)'" -ErrorAction Stop
        }
        else {
            $obj = Get-MgUser -Filter "UserPrincipalName eq '$($item.PrincipalName)'" -ErrorAction Stop
        }
        $found = @($obj | Where-Object { $_ })
    }
    catch {
        $failCount++
        Write-Host " [ERROR] Failed to resolve principal: $_ $(Get-LabGraphSignInHint -Client MgGraph)" -ForegroundColor Red
        continue
    }

    # No guess between namesakes, as in Deploy-Bicep.ps1 and Test-Lab.ps1.
    if ($found.Count -gt 1) {
        $failCount++
        Write-Host " [ERROR] '$($item.PrincipalName)' matched $($found.Count) principals ($(($found | ForEach-Object { $_.Id }) -join ', ')); expected exactly one." -ForegroundColor Red
        continue
    }
    $objectId = if ($found.Count -eq 1) { [string]$found[0].Id } else { $null }

    if (-not $objectId) {
        Write-Host " [SKIP] Principal not found in Entra ID." -ForegroundColor Red
        continue
    }

    # B. Assign Role, through the ARM role assignments API (issue #397). Only an assignment made
    # at the scope itself counts as there: one inherited from above is not the lab's, as in
    # Deploy-Bicep.ps1 and Test-Lab.ps1. A read that fails creates nothing and is counted.
    $roleId = Get-LabBuiltInRoleId -Name $item.Role
    try {
        $exists = @(Get-LabArmRoleAssignment -Scope $item.Scope -PrincipalId $objectId |
            Where-Object { $_.RoleDefinitionId -eq $roleId -and $_.Scope -eq $item.Scope })
    }
    catch {
        $failCount++
        Write-Host " [ERROR] Could not read the role assignments at $($item.ScopeName): $_" -ForegroundColor Red
        continue
    }

    # As Test-Lab.ps1 checks it; ARM keeps one assignment per principal, role and scope, so it cannot be replaced here.
    if ($item.NoCondition -and $exists.Count -gt 0 -and -not @($exists | Where-Object { -not $_.Condition })) {
        $failCount++
        Write-Host " [ERROR] Assigned, but with a condition; the lab's has none. Remove it in the Portal (guide Troubleshooting, Issue 6) and run again." -ForegroundColor Red
        continue
    }
    if ($exists.Count -gt 0) {
        Write-Host " [SKIPPED] Already assigned." -ForegroundColor Yellow
        continue
    }
    try {
        $principalType = if ($item.Type -eq 'Group') { 'Group' } else { 'User' }
        New-LabArmRoleAssignment -Scope $item.Scope -RoleDefinitionId $roleId -PrincipalId $objectId -PrincipalType $principalType | Out-Null
        Write-Host " [SUCCESS]" -ForegroundColor Green
    }
    catch {
        $failCount++
        Write-Host " [ERROR] Failed to assign the role: $_" -ForegroundColor Red
    }
}

if ($failCount -gt 0) {
    Write-Host "`nRole assignment finished with $failCount error(s). See the [ERROR] lines above." -ForegroundColor Red
    Exit-Lab -FailureCount $failCount
}

Write-Host "`nRole assignment complete." -ForegroundColor Green
Exit-Lab -FailureCount 0
