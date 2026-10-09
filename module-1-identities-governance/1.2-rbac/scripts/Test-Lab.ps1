<#
.SYNOPSIS
    Validates infrastructure and role assignments for Lab 1.2.

.DESCRIPTION
    Checks presence of Resource Groups and specific Role Assignments.
    - Malfurion -> Owner (Subscription)
    - SkyCraft-Developers -> Contributor (dev-rg)
    - SkyCraft-Testers -> Reader (dev-rg, prod-rg)
    - Illidan -> Reader (platform-rg)

    Every check prints [OK] or [FAIL] and is counted. The summary states how many passed and how
    many failed, and the script exits 0 only when none failed. It exits 1 when any check failed,
    and also when no one is signed in to Azure, in which case no check runs (issue #254).

.PARAMETER SkipRoleAssignments
    Checks the resource groups only. The five role-assignment checks are reported as skipped and
    not counted. For the automated lab cycle, which deploys the resource groups without the role
    assignments (Deploy-Bicep.ps1 without -IncludeRoleAssignments) and does not run Lab 1.1, so
    the assignments those checks look for are not the cycle's to create.

.EXAMPLE
    .\Test-Lab.ps1
    Runs validation.

.EXAMPLE
    .\Test-Lab.ps1 -SkipRoleAssignments
    Validates the resource groups only, as the lab cycle does.

.NOTES
    Project: SkyCraft
    Lab: 1.2 - RBAC
#>

#Requires -Version 7.0
#Requires -Modules Az.Accounts, Az.Resources

[CmdletBinding()]
param(
    [switch]$SkipRoleAssignments
)

$ErrorActionPreference = "Stop"

Write-Host "=== Lab 1.2 Validation Script ===" -ForegroundColor Cyan -BackgroundColor Black

# Check Azure Connection
Write-Host "`nChecking Azure connection..." -ForegroundColor Cyan
$context = Get-AzContext
if (-not $context) {
    Write-Host "[ERROR] Not logged in. Please run Connect-AzAccount" -ForegroundColor Red
    $Host.SetShouldExit(1)
    exit 1
}
$subId = $context.Subscription.Id
Write-Host "Connected to: $($context.Subscription.Name) ($subId)" -ForegroundColor Green

# Every check below ends in exactly one [OK] or [FAIL], and each is counted here: the summary
# states the counts and the exit code follows them (issue #254). Before that, a run in which every
# check printed [FAIL] still ended "Validation complete." with exit 0, so the lab cycle read a
# failed validation as a passed one.
$passCount = 0
$failCount = 0

# 1. Validate Resource Groups
Write-Host "`n=== Validating Resource Groups ===" -ForegroundColor Cyan
$rgs = @("dev-skycraft-swc-rg", "prod-skycraft-swc-rg", "platform-skycraft-swc-rg")

foreach ($rg in $rgs) {
    # -ErrorAction Stop: a missing resource group and a lookup that failed both land in the catch,
    # so neither can read as found.
    try {
        Get-AzResourceGroup -Name $rg -ErrorAction Stop | Out-Null
        Write-Host "[OK] Resource Group: $rg" -ForegroundColor Green
        $passCount++
    }
    catch {
        Write-Host "[FAIL] Resource Group missing or unreadable: $rg ($($_.Exception.Message))" -ForegroundColor Red
        $failCount++
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
    @{ Name="External Partner";  Principal="^istormrage[@_]";     Role="Reader";      Scope="/subscriptions/$subId/resourceGroups/platform-skycraft-swc-rg" }
)

if ($SkipRoleAssignments) {
    Write-Host "[SKIP] $($checks.Count) role-assignment checks not run (-SkipRoleAssignments) and not counted." -ForegroundColor Yellow
}
else {
    foreach ($check in $checks) {
        Write-Host "Checking: $($check.Name)..." -NoNewline

        # Get assignments at scope. -ErrorAction Stop: a lookup that fails is a failed check that
        # says why, not an empty scope.
        try {
            $assignments = Get-AzRoleAssignment -Scope $check.Scope -ErrorAction Stop
            if (-not $assignments) {
                Write-Host " [FAIL] No assignments at scope." -ForegroundColor Red
                $failCount++
                continue
            }

            # Filter for role and principal
            # Using match for UPN because domain might vary, or DisplayName for groups.
            # Guest sign-in names are rewritten to <alias>_<domain>#EXT#@<tenant>, hence the [@_] pattern for the guest (Illidan).
            $found = $assignments | Where-Object {
                ($_.RoleDefinitionName -eq $check.Role) -and
                ( ($_.SignInName -match $check.Principal) -or ($_.DisplayName -eq $check.Principal) )
            }

            if ($found) {
                Write-Host " [OK] Found '$($check.Role)' assignment." -ForegroundColor Green
                $passCount++
            }
            else {
                Write-Host " [FAIL] Expected Assignment '$($check.Role)' for '$($check.Principal)' NOT found." -ForegroundColor Red
                $failCount++
            }
        }
        catch {
            Write-Host " [FAIL] Could not read role assignments at scope: $($_.Exception.Message)" -ForegroundColor Red
            $failCount++
        }
    }
}

Write-Host "`n=== Validation Summary ===" -ForegroundColor Cyan
Write-Host "  Passed: $passCount" -ForegroundColor Green
Write-Host "  Failed: $failCount" -ForegroundColor $(if ($failCount -gt 0) { 'Red' } else { 'Gray' })

if ($failCount -gt 0) {
    Write-Host "`nLab 1.2 validation failed: $failCount check(s) failed. See the [FAIL] lines above." -ForegroundColor Red
    $Host.SetShouldExit(1)
    exit 1
}

Write-Host "`nLab 1.2 validation passed: all $passCount checks passed." -ForegroundColor Green
