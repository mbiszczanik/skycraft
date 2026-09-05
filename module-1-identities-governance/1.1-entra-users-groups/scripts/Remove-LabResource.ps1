<#
.SYNOPSIS
    Cleans up resources (Users and Groups) created in Lab 1.1.

.DESCRIPTION
    This script deletes the Warcraft-themed users (Malfurion, Khadgar, Chromie) and Guest user (Illidan),
    as well as the security groups (Admins, Developers, Testers).
    It prompts for confirmation unless -Force is used.

.PARAMETER Force
    Skip the confirmation prompt.

.EXAMPLE
    .\Remove-LabResource.ps1
    Prompts for confirmation before deleting resources.

.EXAMPLE
    .\Remove-LabResource.ps1 -Force
    Deletes resources without prompting.

.NOTES
    Project: SkyCraft
    Lab: 1.1 - Entra Users & Groups
    Author: Marcin Biszczanik
    Date: 2026-01-10
#>

#Requires -Version 7.0
#Requires -Modules Microsoft.Graph.Authentication, Microsoft.Graph.Users, Microsoft.Graph.Groups, Microsoft.Graph.Identity.DirectoryManagement

[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory = $false)]
    [switch]$Force
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
# The variables are deliberately NOT the Azure SDK's AZURE_CLIENT_ID / AZURE_TENANT_ID trio. Those
# are commonly already exported for the ARM subscription identity, which in this project is a
# different account from the one that administers Entra ID - consuming them would sign Graph in as
# the wrong principal, silently. See TROUBLESHOOTING.md for how to set these from a secret store.
#
# Duplicated verbatim in New-LabUser.ps1, Test-Lab.ps1 and Remove-LabResource.ps1 rather than
# factored into a shared helper: docs/powershell-standards.md 7.3 requires every lab folder to be
# runnable and readable on its own, and tests/Lab11-Graph-Auth.Tests.ps1 asserts that the three
# copies do not drift apart.
function Get-LabGraphAuthPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string[]]$Scope = @(),

        [Parameter(Mandatory = $false)]
        [string]$TenantId,

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
    if (-not [string]::IsNullOrWhiteSpace($TenantId)) { $setting['TenantId'] = $TenantId.Trim() }

    $credentialSet = @('ClientId', 'ClientSecret', 'CertThumbprint') |
        Where-Object { $setting[$_] }

    if (@($credentialSet).Count -eq 0) {
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
        if ($setting['TenantId']) { $interactiveParameter['TenantId'] = $setting['TenantId'] }

        return [pscustomobject]@{
            Mode             = 'Interactive'
            Reason           = 'No service principal configured - signing in interactively.'
            TenantId         = $setting['TenantId']
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

    $plan = Get-LabGraphAuthPlan -Scope $Scope -TenantId $TenantId

    if ($plan.Mode -eq 'Blocked') { throw $plan.Reason }

    if ($plan.Mode -eq 'Interactive') {
        # Reuse a signed-in context, which is what a learner running the lab expects. Note this is
        # only reached when no service principal is configured: an unattended run never gets here.
        $existingContext = Get-MgContext
        if ($existingContext -and (-not $plan.TenantId -or $existingContext.TenantId -eq $plan.TenantId)) {
            return $existingContext
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

    return Get-MgContext
}

$ErrorActionPreference = 'Stop'
if ($Force) { $ConfirmPreference = 'None' }

Write-Host "=== Lab 1.1 - Resource Cleanup ===" -ForegroundColor Cyan -BackgroundColor Black

# Check Microsoft Graph Connection
try {
    Write-Host "Checking Microsoft Graph connection..." -ForegroundColor Yellow
    $mgContext = Connect-LabGraph -Scope @(
        'User.ReadWrite.All'
        'Group.ReadWrite.All'
        'Directory.ReadWrite.All'
    )
    $identity = if ($mgContext.Account) { $mgContext.Account } else { $mgContext.AppName }
    Write-Host "Connected to Tenant: $($mgContext.TenantId) as $identity" -ForegroundColor Green
}
catch {
    Write-Host "  -> [ERROR] Failed to connect to Microsoft Graph: $_" -ForegroundColor Red
    $Host.SetShouldExit(1)
    exit 1
}

# Resolve Domain
try {
    $domain = (Get-MgDomain | Where-Object { $_.IsDefault }).Id
    Write-Host "Default Domain: $domain" -ForegroundColor Gray
}
catch {
    $domain = "onmicrosoft.com"
    Write-Host "  -> [WARNING] Failed to detect domain. using $domain" -ForegroundColor Yellow
}

Write-Host "`nStarting cleanup..." -ForegroundColor Cyan

# Cleanup Users
$usersToDelete = @(
    "malfurion.stormrage@$domain"
    "khadgar.archmage@$domain"
    "chromie.timewalker@$domain"
)

Write-Host "Deleting Internal Users..." -ForegroundColor Yellow

foreach ($upn in $usersToDelete) {
    try {
        $user = Get-MgUser -Filter "UserPrincipalName eq '$upn'" -ErrorAction SilentlyContinue
        if ($user) {
            if ($PSCmdlet.ShouldProcess($upn, 'Remove user')) {
                Remove-MgUser -UserId $user.Id -ErrorAction Stop
                Write-Host "  -> [SUCCESS] Deleted user: $upn" -ForegroundColor Green
            }
        }
        else {
            Write-Host "  -> [INFO] User not found: $upn" -ForegroundColor Gray
        }
    }
    catch {
        Write-Host "  -> [ERROR] Failed to delete user $($upn): $_" -ForegroundColor Red
    }
}

# Cleanup Guest
Write-Host "`nDeleting Guest User..." -ForegroundColor Yellow
$guestEmail = "illidan@externalcompany.com"
try {
    # Find guest by mail
    $guest = Get-MgUser -Filter "Mail eq '$guestEmail'" -ErrorAction SilentlyContinue
    if ($guest) {
        if ($PSCmdlet.ShouldProcess($guestEmail, 'Remove guest user')) {
            Remove-MgUser -UserId $guest.Id -ErrorAction Stop
            Write-Host "  -> [SUCCESS] Deleted guest: $guestEmail" -ForegroundColor Green
        }
    }
    else {
        Write-Host "  -> [INFO] Guest not found: $guestEmail" -ForegroundColor Gray
    }
}
catch {
    Write-Host "  -> [ERROR] Failed to delete guest $($guestEmail): $_" -ForegroundColor Red
}

# Cleanup Groups
Write-Host "`nDeleting Security Groups..." -ForegroundColor Yellow
$groupsToDelete = @(
    "SkyCraft-Admins"
    "SkyCraft-Developers"
    "SkyCraft-Testers"
)

foreach ($groupName in $groupsToDelete) {
    try {
        $group = Get-MgGroup -Filter "DisplayName eq '$groupName'" -ErrorAction SilentlyContinue
        if ($group) {
            if ($PSCmdlet.ShouldProcess($groupName, 'Remove group')) {
                Remove-MgGroup -GroupId $group.Id -ErrorAction Stop
                Write-Host "  -> [SUCCESS] Deleted group: $groupName" -ForegroundColor Green
            }
        }
        else {
            Write-Host "  -> [INFO] Group not found: $groupName" -ForegroundColor Gray
        }
    }
    catch {
        Write-Host "  -> [ERROR] Failed to delete group $($groupName): $_" -ForegroundColor Red
    }
}

Write-Host "`nCleanup Complete." -ForegroundColor Green
