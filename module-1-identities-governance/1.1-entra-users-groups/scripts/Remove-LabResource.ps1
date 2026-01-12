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
    .\Cleanup-Resources.ps1
    Prompts for confirmation before deleting resources.

.EXAMPLE
    .\Cleanup-Resources.ps1 -Force
    Deletes resources without prompting.

.NOTES
    Project: SkyCraft
    Lab: 1.1 - Entra Users & Groups
    Author: Marcin Biszczanik
    Date: 2026-01-10
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [switch]$Force
)

Write-Host "=== Lab 1.1 - Resource Cleanup ===" -ForegroundColor Cyan -BackgroundColor Black

# Check Microsoft Graph Connection
try {
    Write-Host "Checking Microsoft Graph connection..." -ForegroundColor Yellow
    $mgContext = Get-MgContext
    if (-not $mgContext) {
        Write-Host "Not connected. Connecting..." -ForegroundColor Yellow
        Connect-MgGraph -Scopes "User.ReadWrite.All", "Group.ReadWrite.All", "Directory.ReadWrite.All" -ErrorAction Stop
        $mgContext = Get-MgContext
    }
    Write-Host "Connected to Tenant: $($mgContext.TenantId)" -ForegroundColor Green
}
catch {
    Write-Host "  -> [ERROR] Failed to connect to Microsoft Graph: $_" -ForegroundColor Red
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

# Confirmation
if (-not $Force) {
    $confirm = Read-Host "Are you sure you want to delete Lab 1.1 Users & Groups (Malfurion, Khadgar, etc.)? (y/N)"
    if ($confirm -notmatch "^y$") {
        Write-Host "Cleanup cancelled." -ForegroundColor Yellow
        exit 0
    }
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
            Remove-MgUser -UserId $user.Id -ErrorAction Stop
            Write-Host "  -> [SUCCESS] Deleted user: $upn" -ForegroundColor Green
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
        Remove-MgUser -UserId $guest.Id -ErrorAction Stop
        Write-Host "  -> [SUCCESS] Deleted guest: $guestEmail" -ForegroundColor Green
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
            Remove-MgGroup -GroupId $group.Id -ErrorAction Stop
            Write-Host "  -> [SUCCESS] Deleted group: $groupName" -ForegroundColor Green
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
