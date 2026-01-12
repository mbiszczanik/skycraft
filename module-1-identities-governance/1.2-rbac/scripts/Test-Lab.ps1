<#
.SYNOPSIS
    Validates infrastructure and role assignments for Lab 1.2.

.DESCRIPTION
    Checks presence of Resource Groups and specific Role Assignments.
    - Malfurion -> Owner (Subscription)
    - SkyCraft-Developers -> Contributor (dev-rg)
    - SkyCraft-Testers -> Reader (dev-rg, prod-rg)
    - Illidan -> Reader (platform-rg)

.EXAMPLE
    .\Test-Lab-1.2.ps1
    Runs validation.

.NOTES
    Project: SkyCraft
    Lab: 1.2 - RBAC
#>

[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

Write-Host "=== Lab 1.2 Validation Script ===" -ForegroundColor Cyan -BackgroundColor Black

# Check Azure Connection
Write-Host "`nChecking Azure connection..." -ForegroundColor Cyan
$context = Get-AzContext
if (-not $context) {
    Write-Host "Not logged in. Please run Connect-AzAccount" -ForegroundColor Red
    return
}
$subId = $context.Subscription.Id
Write-Host "Connected to: $($context.Subscription.Name) ($subId)" -ForegroundColor Green

# 1. Validate Resource Groups
Write-Host "`n=== Validating Resource Groups ===" -ForegroundColor Cyan
$rgs = @("dev-skycraft-swc-rg", "prod-skycraft-swc-rg", "platform-skycraft-swc-rg")

foreach ($rg in $rgs) {
    if (Get-AzResourceGroup -Name $rg -ErrorAction SilentlyContinue) {
        Write-Host "[OK] Resource Group: $rg" -ForegroundColor Green
    }
    else {
        Write-Host "[FAIL] Resource Group missing: $rg" -ForegroundColor Red
    }
}

# 2. Validate Role Assignments
Write-Host "`n=== Validating Role Assignments ===" -ForegroundColor Cyan

# Define checks
# Note: We check specifically for the Principal's assignment at the scope
$checks = @(
    @{ Name="Malfurion (Admin)"; Principal="malfurion.stormrage@"; Role="Owner"; Scope="/subscriptions/$subId" }
    @{ Name="Developers Group";  Principal="SkyCraft-Developers";  Role="Contributor"; Scope="/subscriptions/$subId/resourceGroups/dev-skycraft-swc-rg" }
    @{ Name="Testers Group (Dev)"; Principal="SkyCraft-Testers";   Role="Reader";      Scope="/subscriptions/$subId/resourceGroups/dev-skycraft-swc-rg" }
    @{ Name="Testers Group (Prod)"; Principal="SkyCraft-Testers";  Role="Reader";      Scope="/subscriptions/$subId/resourceGroups/prod-skycraft-swc-rg" }
    @{ Name="External Partner";  Principal="illidan@";             Role="Reader";      Scope="/subscriptions/$subId/resourceGroups/platform-skycraft-swc-rg" }
)

foreach ($check in $checks) {
    Write-Host "Checking: $($check.Name)..." -NoNewline
    
    # Get assignments at scope
    try {
        $assignments = Get-AzRoleAssignment -Scope $check.Scope -ErrorAction SilentlyContinue
        if (-not $assignments) {
             Write-Host " [FAIL] No assignments at scope." -ForegroundColor Red
             continue
        }
        
        # Filter for role and principal
        # Using match for UPN because domain might vary, or DisplayName for groups
        $found = $assignments | Where-Object { 
            ($_.RoleDefinitionName -eq $check.Role) -and 
            ( ($_.SignInName -match $check.Principal) -or ($_.DisplayName -eq $check.Principal) )
        }

        if ($found) {
            Write-Host " [OK] Found '$($check.Role)' assignment." -ForegroundColor Green
        }
        else {
            Write-Host " [FAIL] Expected Assignment '$($check.Role)' for '$($check.Principal)' NOT found." -ForegroundColor Red
        }
    }
    catch {
        Write-Host " [ERROR] $_" -ForegroundColor Red
    }
}

Write-Host "`nValidation complete." -ForegroundColor Green
