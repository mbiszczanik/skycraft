<#
.SYNOPSIS
    Assigns RBAC roles for Lab 1.2 - Identities & Governance.

.DESCRIPTION
    This script assigns the required Azure RBAC roles to the Warcraft-themed users and groups.
    It resolves users via Microsoft Graph and assigns roles via Azure PowerShell.
    
    Assignments:
    - Malfurion Stormrage -> Owner (Subscription)
    - SkyCraft-Developers -> Contributor (dev-skycraft-swc-rg)
    - SkyCraft-Testers    -> Reader (dev-skycraft-swc-rg, prod-skycraft-swc-rg)
    - Illidan Stormrage   -> Reader (platform-skycraft-swc-rg)

.EXAMPLE
    .\Assign-Roles.ps1
    Assigns roles to the current subscription.

.NOTES
    Project: SkyCraft
    Lab: 1.2 - RBAC
#>

[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

Write-Host "=== Lab 1.2: RBAC Role Assignment ===" -ForegroundColor Cyan -BackgroundColor Black

# 1. Connect to Microsoft Graph (for User/Group/Domain resolution)
try {
    Write-Host "`nChecking Microsoft Graph connection..." -ForegroundColor Yellow
    $mgContext = Get-MgContext
    if (-not $mgContext) {
        Write-Host "Connecting to Microsoft Graph..." -ForegroundColor Yellow
        Connect-MgGraph -Scopes "User.Read.All", "Group.Read.All", "Directory.Read.All" -ErrorAction Stop
        $mgContext = Get-MgContext
    }
    Write-Host "Connected to Tenant: $($mgContext.TenantId)" -ForegroundColor Green
}
catch {
    Write-Host "  -> [ERROR] Failed to connect to Graph: $_" -ForegroundColor Red
    exit 1
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
    exit 1
}

# 3. Resolve Default Domain
try {
    $domain = (Get-MgDomain | Where-Object { $_.IsDefault }).Id
    Write-Host "Default Domain: $domain" -ForegroundColor Gray
}
catch {
    $domain = "onmicrosoft.com"
    Write-Host "  -> [WARNING] Failed to detect domain, using fallback: $domain" -ForegroundColor Yellow
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
        PrincipalName  = "illidan@externalcompany.com" # Search by mail
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