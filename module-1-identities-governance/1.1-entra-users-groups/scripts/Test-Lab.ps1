<#
.SYNOPSIS
    Validates the configuration of Lab 1.1 - Entra Users & Groups.

.DESCRIPTION
    This script verifies that the required Warcraft-themed users (Malfurion, Khadgar, Chromie)
    and Guest user (Illidan) exist in the tenant. It also checks that the security groups
    (Admins, Developers, Testers) exist and have the correct members assigned.

.EXAMPLE
    .\Test-Lab-1.1.ps1
    Runs the validation suite.

.NOTES
    Project: SkyCraft
    Lab: 1.1 - Entra Users & Groups
    Author: Marcin Biszczanik
    Date: 2026-01-10
#>

[CmdletBinding()]
param()

Write-Host "=== Lab 1.1 Validation Script ===" -ForegroundColor Cyan -BackgroundColor Black

# Check Microsoft Graph Connection
try {
    Write-Host "`nChecking Microsoft Graph connection..." -ForegroundColor Yellow
    $mgContext = Get-MgContext
    if (-not $mgContext) {
        Write-Host "Not connected. Connecting..." -ForegroundColor Yellow
        Connect-MgGraph -Scopes "User.Read.All", "Group.Read.All", "Directory.Read.All" -ErrorAction Stop
        $mgContext = Get-MgContext
    }
    Write-Host "Connected to Tenant: $($mgContext.TenantId)" -ForegroundColor Green
}
catch {
    Write-Host "  -> [ERROR] Failed to connect to Microsoft Graph: $_" -ForegroundColor Red
    exit 1
}

# Get Default Domain
try {
    $domain = (Get-MgDomain | Where-Object { $_.IsDefault }).Id
    Write-Host "Default Domain: $domain" -ForegroundColor Gray
}
catch {
    $domain = "onmicrosoft.com"
    Write-Host "  -> [WARNING] Failed to detect domain. using $domain" -ForegroundColor Yellow
}

# Define Expected Users (Warcraft Theme)
$expectedUsers = @(
    "malfurion.stormrage@$domain"
    "khadgar.archmage@$domain"
    "chromie.timewalker@$domain"
    "istormrage@externalcompany.com" # Guest user
)

# Validate Users
Write-Host "`n=== Validating Users ===" -ForegroundColor Cyan
foreach ($upn in $expectedUsers) {
    # Special handling for Guest User filtering
    if ($upn -like "*@externalcompany.com") {
         $filter = "Mail eq '$upn'"
    } else {
         $filter = "UserPrincipalName eq '$upn'"
    }

    try {
        $user = Get-MgUser -Filter $filter -ErrorAction Stop
        if ($user) {
            Write-Host "[OK] User found: $($user.DisplayName) ($upn)" -ForegroundColor Green
        }
        else {
            Write-Host "[FAIL] User missing: $upn" -ForegroundColor Red
        }
    }
    catch {
        Write-Host "[FAIL] Error checking user $($upn): $_" -ForegroundColor Red
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

foreach ($item in $expectedGroups) {
    $groupName = $item.Name
    try {
        $group = Get-MgGroup -Filter "DisplayName eq '$groupName'" -ErrorAction Stop
        if ($group) {
            Write-Host "[OK] Group exists: $groupName" -ForegroundColor Green
            
            # Check Members
            $members = Get-MgGroupMember -GroupId $group.Id -All -ErrorAction SilentlyContinue
            if ($members) {
                # Fetch full user details for members to get DisplayName
                $memberFound = $false
                foreach ($memberId in $members.Id) {
                    $memberUser = Get-MgUser -UserId $memberId -ErrorAction SilentlyContinue
                    if ($memberUser) {
                        Write-Host "  -> Member: $($memberUser.DisplayName) ($($memberUser.UserPrincipalName))" -ForegroundColor Gray
                        if ($memberUser.DisplayName -eq $item.ExpectedMember) {
                            $memberFound = $true
                        }
                    }
                }
                
                if ($memberFound) {
                     Write-Host "  -> [OK] Verify: $($item.ExpectedMember) is a member." -ForegroundColor Green
                }
                else {
                     Write-Host "  -> [FAIL] Verify: $($item.ExpectedMember) NOT found in group." -ForegroundColor Red
                }
            }
            else {
                Write-Host "  -> [WARNING] No members found." -ForegroundColor Yellow
            }
        }
        else {
            Write-Host "[FAIL] Group missing: $groupName" -ForegroundColor Red
        }
    }
    catch {
        Write-Host "[FAIL] Error checking group: $groupName. $_" -ForegroundColor Red
    }
}

Write-Host "`n=== Validation Summary ===" -ForegroundColor Cyan
Write-Host "Lab 1.1 validation complete" -ForegroundColor Green

