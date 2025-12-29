# Lab 1.1 - Validation Script
# Validates Users, Groups, and Memberships

Write-Host "=== Lab 1.1 Validation Script ===" -ForegroundColor Cyan -BackgroundColor Black

# Check Microsoft Graph Connection
Write-Host "`nChecking Microsoft Graph connection..." -ForegroundColor Cyan
$mgContext = Get-MgContext
if (-not $mgContext) {
    Write-Host "Not connected to Microsoft Graph. Attempting to connect..." -ForegroundColor Yellow
    Connect-MgGraph -Scopes "User.Read.All", "Group.Read.All", "Directory.Read.All" -ErrorAction Stop
    $mgContext = Get-MgContext
}

if (-not $mgContext) {
    Write-Host "Failed to connect to Microsoft Graph. Cannot proceed." -ForegroundColor Red
    exit 1
}
Write-Host "Connected to Tenant: $($mgContext.TenantId)" -ForegroundColor Green

# Get Default Domain
$domain = (Get-MgDomain | Where-Object { $_.IsDefault }).Id
Write-Host "Default Domain: $domain" -ForegroundColor Gray

# Define Expected Users
$expectedUsers = @(
    "skycraft-admin@$domain"
    "skycraft-dev@$domain"
    "skycraft-tester@$domain"
    "partner@externalcompany.com" # Guest user
)

# Validate Users
Write-Host "`nValidating Users..." -ForegroundColor Cyan
foreach ($upn in $expectedUsers) {
    $filter = if ($upn -like "*@externalcompany.com") { "Mail eq '$upn'" } else { "UserPrincipalName eq '$upn'" }
    try {
        $user = Get-MgUser -Filter $filter -ErrorAction Stop
        if ($user) {
            Write-Host "[OK] User exists: $($user.DisplayName) ($upn)" -ForegroundColor Green
        }
        else {
            Write-Host "[FAIL] User missing: $upn" -ForegroundColor Red
        }
    }
    catch {
        Write-Host "[FAIL] User missing: $upn" -ForegroundColor Red
    }
}

# Define Expected Groups
$expectedGroups = @(
    "SkyCraft-Admins"
    "SkyCraft-Developers"
    "SkyCraft-Testers"
)

# Validate Groups & Members
Write-Host "`nValidating Groups & Memberships..." -ForegroundColor Cyan
foreach ($groupName in $expectedGroups) {
    try {
        $group = Get-MgGroup -Filter "DisplayName eq '$groupName'" -ErrorAction Stop
        if ($group) {
            Write-Host "[OK] Group exists: $groupName" -ForegroundColor Green
            
            # Check Members
            $members = Get-MgGroupMember -GroupId $group.Id -All
            if ($members) {
                # Fetch full user details for members to get DisplayName/UPN
                foreach ($memberId in $members.Id) {
                    $memberUser = Get-MgUser -UserId $memberId -ErrorAction SilentlyContinue
                    if ($memberUser) {
                        Write-Host "  -> Member: $($memberUser.DisplayName) ($($memberUser.UserPrincipalName))" -ForegroundColor Gray
                    }
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
        Write-Host "[FAIL] Error checking group: $groupName" -ForegroundColor Red
    }
}

Write-Host "`n=== Validation Summary ===" -ForegroundColor Cyan
Write-Host "Lab 1.1 validation complete" -ForegroundColor Green
