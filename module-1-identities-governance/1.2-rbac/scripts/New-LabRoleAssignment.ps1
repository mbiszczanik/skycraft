<#
.SYNOPSIS
    Assigns RBAC roles for Lab 1.2 - Identities & Governance.

.DESCRIPTION
    This script assigns the required Azure RBAC roles to the Warcraft-themed users and groups.
    It resolves users via Microsoft Graph and assigns roles via Azure PowerShell.

    It signs in to Microsoft Graph the way Lab 1.1's scripts do, reusing a Graph context already
    in the session only when that context holds the scopes it requests, and it looks Lab 1.1's
    users up on the tenant's initial *.onmicrosoft.com domain, where Lab 1.1 creates them. When
    the tenant lists no initial domain it stops with [ERROR] and exit code 1.

    The Graph sign-in goes to the tenant SKYCRAFT_GRAPH_TENANT_ID names, else to the tenant of the
    current Az context, so after Connect-AzAccount to the lab tenant a personal Microsoft account
    reaches that tenant too.

    This is the imperative path. The declarative equivalent is bicep/role-assignments.bicep,
    deployed by Deploy-Bicep.ps1 -IncludeRoleAssignments, which creates the same five assignments
    under names derived from guid(scope, role, principal). Pick one path per subscription: this
    script skips an assignment that already exists, whichever path created it, but the template
    cannot adopt an assignment this script created (ARM answers RoleAssignmentExists).
    
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
#Requires -Modules Az.Accounts, Az.Resources, Microsoft.Graph.Authentication, Microsoft.Graph.Identity.DirectoryManagement, Microsoft.Graph.Users, Microsoft.Graph.Groups

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
#   - The interactive sign-in uses SKYCRAFT_GRAPH_TENANT_ID, else the Az context's tenant, so a
#     personal Microsoft account reaches the lab tenant after Connect-AzAccount alone (#300).
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
Import-Module (Join-Path $PSScriptRoot '../../../tools/LabCommon.psm1') -Force -Verbose:$false

Write-Host "=== Lab 1.2: RBAC Role Assignment ===" -ForegroundColor Cyan -BackgroundColor Black

# 1. Connect to Microsoft Graph (for User/Group/Domain resolution)
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
    )
    # A delegated sign-in can report no account (#300); its AppName is the client tool, not the user.
    $identity = if ($mgContext.Account) { $mgContext.Account } elseif ("$($mgContext.AuthType)" -eq 'AppOnly') { $mgContext.AppName } else { 'a delegated sign-in (no account reported)' }
    Write-Host "Connected to Tenant: $($mgContext.TenantId) as $identity" -ForegroundColor Green
}
catch {
    Write-Host "  -> [ERROR] Failed to connect to Microsoft Graph: $_" -ForegroundColor Red
    Exit-Lab -FailureCount 1
}

# 2. Connect to Azure PowerShell (for Role Assignment)
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

    # Tenant Check
    if ($azContext.Tenant.Id -ne $mgContext.TenantId) {
        Write-Host "`n[WARNING] Tenant Mismatch Detected!" -ForegroundColor Red
        Write-Host "Azure Subscription Tenant: $($azContext.Tenant.Id)" -ForegroundColor Yellow
        Write-Host "Microsoft Graph Tenant:    $($mgContext.TenantId)" -ForegroundColor Yellow
        Write-Host "Role Assignments between different tenants are not possible unless B2B is configured." -ForegroundColor Red
        Write-Host "Please ensure your Azure Context and Graph Context point to the same directory." -ForegroundColor Red
        # We will not exit, but subsequent commands will likely fail with BadRequest
    }
}
catch {
    Write-Host "  -> [ERROR] Failed to connect to Azure: $_" -ForegroundColor Red
    Exit-Lab -FailureCount 1
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

foreach ($item in $assignments) {
    Write-Host "Processing: $($item.PrincipalName) -> $($item.Role) on $($item.ScopeName)..." -NoNewline
    
    # A. Resolve Principal ObjectId
    $objectId = $null
    try {
        if ($item.Type -eq "Group") {
            $obj = Get-MgGroup -Filter "DisplayName eq '$($item.PrincipalName)'" -ErrorAction Stop
            $objectId = $obj.Id
        }
        elseif ($item.Type -eq "Guest") {
             # Guests might be found by Mail or UPN depending on invitation state
             # Try Mail first
             $obj = Get-MgUser -Filter "Mail eq '$($item.PrincipalName)'" -ErrorAction SilentlyContinue
             if (-not $obj) {
                 # Fallback to broad search if needed or check UPN if known format
                 # For now, assume UPN might be complex for guest, so stick to mail filter
             }
             $objectId = $obj.Id
        }
        else {
            # Standard User
            $obj = Get-MgUser -Filter "UserPrincipalName eq '$($item.PrincipalName)'" -ErrorAction Stop
            $objectId = $obj.Id
        }
    }
    catch {
        Write-Host " [ERROR] Failed to resolve principal." -ForegroundColor Red
        continue
    }

    if (-not $objectId) {
        Write-Host " [SKIP] Principal not found in Entra ID." -ForegroundColor Red
        continue
    }

    # B. Assign Role
    try {
        # Check if exists to avoid error
        # Note: Get-AzRoleAssignment needs exact scope
        $exists = Get-AzRoleAssignment -ObjectId $objectId -RoleDefinitionName $item.Role -Scope $item.Scope -ErrorAction SilentlyContinue
        
        if ($exists) {
            Write-Host " [SKIPPED] Already assigned." -ForegroundColor Yellow
        }
        else {
            New-AzRoleAssignment -ObjectId $objectId -RoleDefinitionName $item.Role -Scope $item.Scope -ErrorAction Stop | Out-Null
            Write-Host " [SUCCESS]" -ForegroundColor Green
        }
    }
    catch {
        Write-Host " [FAIL] $_" -ForegroundColor Red
    }
}

Write-Host "`nRole assignment complete." -ForegroundColor Green