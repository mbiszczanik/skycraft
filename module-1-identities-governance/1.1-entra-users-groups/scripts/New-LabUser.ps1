<#
.SYNOPSIS
    Automates the creation of Warcraft-themed users and security groups for the SkyCraft Lab 1.1.

.DESCRIPTION
    This script creates three internal users (Malfurion, Khadgar, Chromie), invites one guest user (Illidan),
    and sets up security groups (Admins, Developers, Testers) with the corresponding memberships.
    It adheres to the SkyCraft PowerShell standards.

.PARAMETER TenantId
    The Microsoft Entra Tenant ID to use. If omitted, it will be detected from the current Azure context.

.PARAMETER DemoMode
    If specified, the script will simulate the creation process and output what would happen 
    without making any actual changes to the tenant.

.EXAMPLE
    .\Create-Users.ps1 -DemoMode
    Simulates the creation of all users and groups.

.EXAMPLE
    .\Create-Users.ps1
    Executes the creation process using the current Azure context.

.NOTES
    Project: SkyCraft
    Lab: 1.1 - Entra Users & Groups
    Author: Marcin Biszczanik
    Date: 2026-01-10
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory = $false, HelpMessage = "The Microsoft Entra Tenant ID.")]
    [string]$TenantId,
    
    [Parameter(Mandatory = $false, HelpMessage = "Enable demo mode (skips actual creation).")]
    [switch]$DemoMode
)

Write-Host "=== Lab 1.1: Create Users & Groups ===" -ForegroundColor Cyan -BackgroundColor Black

# Check module requirements
if (-not (Get-Module -ListAvailable -Name Microsoft.Graph)) {
    Write-Host "Installing Microsoft.Graph module..." -ForegroundColor Yellow
    Install-Module -Name Microsoft.Graph -Scope CurrentUser -Force -AllowClobber
}

$ErrorActionPreference = "Stop"

# Connect to Graph
try {
    Write-Host "Checking Microsoft Graph connection..." -ForegroundColor Yellow
    $mgContext = Get-MgContext
    if (-not $mgContext) {
        Write-Host "Not connected. connecting..." -ForegroundColor Yellow
        Connect-MgGraph -Scopes "User.ReadWrite.All", "Group.ReadWrite.All", "Directory.ReadWrite.All", "Domain.Read.All", "User.Invite.All" -ErrorAction Stop
        $mgContext = Get-MgContext
    }
    Write-Host "Connected to Tenant: $($mgContext.TenantId)" -ForegroundColor Green
}
catch {
    Write-Host "  -> [ERROR] Failed to connect to Microsoft Graph: $_" -ForegroundColor Red
    exit 1
}

# Resolve Domain
Write-Host "Resolving default domain..." -ForegroundColor Yellow
try {
    $mgDomain = Get-MgDomain | Where-Object { $_.IsDefault }
    if ($mgDomain) {
        $domain = $mgDomain.Id
        Write-Host "  -> Use Default Domain: $domain" -ForegroundColor Green
    }
    else {
        $domain = "onmicrosoft.com"
        Write-Host "  -> [WARNING] Default domain not found. Using '$domain'." -ForegroundColor Yellow
    }
}
catch {
    $domain = "onmicrosoft.com"
    Write-Host "  -> [ERROR] Failed to get domain: $_. Using '$domain'." -ForegroundColor Red
}

# Define Users (Warcraft Theme)
$users = @(
    @{
        UserPrincipalName = "malfurion.stormrage"
        DisplayName       = "Malfurion Stormrage"
        Password          = "LoveAzeroth!2004"
        Department        = "IT Operations"
        JobTitle          = "Cloud Infrastructure Manager"
    },
    @{
        UserPrincipalName = "khadgar.archmage"
        DisplayName       = "Khadgar Archmage"
        Password          = "LoveAzeroth!2004"
        Department        = "Development"
        JobTitle          = "Cloud Developer"
    },
    @{
        UserPrincipalName = "chromie.timewalker"
        DisplayName       = "Chromie Timewalker"
        Password          = "LoveAzeroth!2004"
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
                    PasswordProfile   = @{ Password = $user.Password; ForceChangePasswordNextSignIn = $false }
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
        Email       = "illidan@externalcompany.com" # Simulated external email
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
