<#
.SYNOPSIS
    Validates the Lab 1.3 infrastructure (Governance Controls).

.DESCRIPTION
    Checks for the existence and correct configuration of:
    1. Resource Group Tags
    2. Policy Assignments
    3. Resource Locks
    4. Budgets (manual check)

    Every check in sections 1-3 prints [OK] or [FAIL] and is counted. The summary states how many
    passed and how many failed, and the script exits 0 only when none failed. It exits 1 when any
    check failed, and also when no one is signed in to Azure, in which case no check runs
    (issue #254).

    Section 4 is a manual check and is not counted: it only lists the budgets it can read, as
    [INFO]. Budgets are created in the portal (the Bicep deployment does not create them), a new
    one can take a while to appear, and reading them needs Cost Management access some
    subscriptions do not grant - so their absence cannot fail validation, and their presence is
    not counted as a pass. Confirm them in the portal under Cost Management > Budgets.

.EXAMPLE
    .\Test-Lab.ps1

.NOTES
    Project: SkyCraft
    Lab: 1.3 - Governance
#>

#Requires -Version 7.0
#Requires -Modules Az.Accounts, Az.Resources, Az.Billing

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

Write-Host "=== Lab 1.3: Validation ===" -ForegroundColor Cyan -BackgroundColor Black

# Check Azure Connection
$context = Get-AzContext
if (-not $context) {
    Write-Host "[ERROR] Not logged in. Please run Connect-AzAccount" -ForegroundColor Red
    $Host.SetShouldExit(1)
    exit 1
}
Write-Host "Connected to: $($context.Subscription.Name)" -ForegroundColor Green

$subscriptionId = $context.Subscription.Id

# Every check in sections 1-3 ends in exactly one [OK] or [FAIL], and each is counted here: the
# summary states the counts and the exit code follows them (issue #254). Before that, a run in
# which every check printed [FAIL] still ended "Validation Complete." with exit 0, so the lab
# cycle read a failed validation as a passed one. Every lookup below uses -ErrorAction Stop, so a
# lookup that fails is a [FAIL] that says why, never an empty result read as something else.
$passCount = 0
$failCount = 0

# Define Resource Groups
$resourceGroups = @(
    "dev-skycraft-swc-rg",
    "prod-skycraft-swc-rg",
    "platform-skycraft-swc-rg"
)

# 1. Validate Tags
Write-Host "`n=== 1. Validating Tags ===" -ForegroundColor Cyan
foreach ($rgName in $resourceGroups) {
    try {
        $rg = Get-AzResourceGroup -Name $rgName -ErrorAction Stop
        $tags = $rg.Tags
        if ($tags) {
            Write-Host "  Checking $rgName..." -NoNewline

            # Check for 'Project' tag specifically
            if ($tags.ContainsKey("Project") -and $tags["Project"] -eq "SkyCraft") {
                Write-Host " [OK] Project tag verified." -ForegroundColor Green
                $passCount++
            }
            else {
                Write-Host " [FAIL] Missing or incorrect 'Project' tag." -ForegroundColor Red
                $failCount++
            }
        }
        else {
            Write-Host "  Checking $rgName... [FAIL] No tags found." -ForegroundColor Red
            $failCount++
        }
    }
    catch {
        Write-Host "  Checking $rgName... [FAIL] Not found or unreadable: $($_.Exception.Message)" -ForegroundColor Red
        $failCount++
    }
}

# 2. Validate Policies
Write-Host "`n=== 2. Validating Policy Assignments ===" -ForegroundColor Cyan
$expectedPolicies = @(
    "Require-Environment-Tag-RG",
    "Enforce-Project-Tag",
    "Restrict-Azure-Regions"
)

foreach ($policyName in $expectedPolicies) {
    Write-Host "  Policy: $policyName" -NoNewline
    try {
        # A policy assignment that does not exist is an error from this cmdlet, so it lands in the
        # catch together with a lookup that failed for any other reason.
        $assignment = Get-AzPolicyAssignment -Name $policyName -Scope "/subscriptions/$subscriptionId" -ErrorAction Stop
        if ($assignment) {
            Write-Host " [OK]" -ForegroundColor Green
            $passCount++
        }
        else {
            Write-Host " [FAIL] Not found." -ForegroundColor Red
            $failCount++
        }
    }
    catch {
        Write-Host " [FAIL] Not found or unreadable: $($_.Exception.Message)" -ForegroundColor Red
        $failCount++
    }
}

# 3. Validate Locks
# One check per resource group: it passes when the group carries at least one lock, and every
# lock found is listed on the same line.
Write-Host "`n=== 3. Validating Locks ===" -ForegroundColor Cyan
$lockTargets = @("prod-skycraft-swc-rg", "platform-skycraft-swc-rg")

foreach ($rgName in $lockTargets) {
    Write-Host "  Lock on $rgName" -NoNewline
    try {
        $locks = @(Get-AzResourceLock -ResourceGroupName $rgName -ErrorAction Stop | Where-Object { $_ })
        if ($locks.Count -gt 0) {
            $lockList = ($locks | ForEach-Object { "$($_.Name) ($($_.Level))" }) -join ', '
            Write-Host " : $lockList" -NoNewline
            Write-Host " [OK]" -ForegroundColor Green
            $passCount++
        }
        else {
            Write-Host " [FAIL] Not found." -ForegroundColor Red
            $failCount++
        }
    }
    catch {
        Write-Host " [FAIL] Could not read locks: $($_.Exception.Message)" -ForegroundColor Red
        $failCount++
    }
}

# 4. Validate Budgets - a manual check, not counted (see the help above for why). Nothing here
# prints [OK] or [FAIL] or touches the counts; a budget lookup that fails says so, rather than
# reading as "no budgets".
Write-Host "`n=== 4. Budgets (manual check, not counted) ===" -ForegroundColor Cyan
# Budgets are technically Consumption resources.
try {
    $budgets = @(Get-AzConsumptionBudget -ErrorAction Stop | Where-Object { $_ })
    if ($budgets.Count -gt 0) {
        foreach ($budget in $budgets) {
            Write-Host "  [INFO] Budget found: $($budget.Name) (Amount: $($budget.Amount) $($budget.Unit))" -ForegroundColor Gray
        }
    }
    else {
        Write-Host "  [INFO] No budgets found. (If you created them recently, they might take time to appear)" -ForegroundColor Yellow
    }
}
catch {
    Write-Host "  [INFO] Budgets could not be read: $($_.Exception.Message)" -ForegroundColor Yellow
}
Write-Host "  Confirm your budgets in the portal: Cost Management > Budgets." -ForegroundColor Gray

Write-Host "`n=== Validation Summary ===" -ForegroundColor Cyan
Write-Host "  Passed: $passCount" -ForegroundColor Green
Write-Host "  Failed: $failCount" -ForegroundColor $(if ($failCount -gt 0) { 'Red' } else { 'Gray' })
Write-Host "  (Budgets are a manual check and are not counted.)" -ForegroundColor Gray

if ($failCount -gt 0) {
    Write-Host "`nLab 1.3 validation failed: $failCount check(s) failed. See the [FAIL] lines above." -ForegroundColor Red
    $Host.SetShouldExit(1)
    exit 1
}

Write-Host "`nLab 1.3 validation passed: all $passCount checks passed." -ForegroundColor Green
