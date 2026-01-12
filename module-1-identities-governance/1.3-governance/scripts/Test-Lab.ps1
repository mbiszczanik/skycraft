<#
.SYNOPSIS
    Validates the Lab 1.3 infrastructure (Governance Controls).

.DESCRIPTION
    Checks for the existence and correct configuration of:
    1. Resource Group Tags
    2. Policy Assignments
    3. Resource Locks
    4. Budgets (manual check)

.EXAMPLE
    .\Test-Lab-1.3.ps1

.NOTES
    Project: SkyCraft
    Lab: 1.3 - Governance
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

Write-Host "=== Lab 1.3: Validation ===" -ForegroundColor Cyan -BackgroundColor Black

# Check Azure Connection
$context = Get-AzContext
if (-not $context) {
    Write-Host "Not logged in. Please run Connect-AzAccount" -ForegroundColor Red
    exit 1
}
Write-Host "Connected to: $($context.Subscription.Name)" -ForegroundColor Green

$subscriptionId = $context.Subscription.Id

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
            }
            else {
                Write-Host " [FAIL] Missing or incorrect 'Project' tag." -ForegroundColor Red
            }
        }
        else {
            Write-Host "  Checking $rgName... [FAIL] No tags found." -ForegroundColor Red
        }
    }
    catch {
        Write-Host "  Checking $rgName... [FAIL] Not found." -ForegroundColor Red
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
    $assignment = Get-AzPolicyAssignment -Name $policyName -Scope "/subscriptions/$subscriptionId" -ErrorAction SilentlyContinue
    if ($assignment) {
        Write-Host "  Policy: $policyName" -NoNewline
        Write-Host " [OK]" -ForegroundColor Green
    }
    else {
        Write-Host "  Policy: $policyName" -NoNewline
        Write-Host " [FAIL]" -ForegroundColor Red
    }
}

# 3. Validate Locks
Write-Host "`n=== 3. Validating Locks ===" -ForegroundColor Cyan
$lockTargets = @("prod-skycraft-swc-rg", "platform-skycraft-swc-rg")

foreach ($rgName in $lockTargets) {
    $locks = Get-AzResourceLock -ResourceGroupName $rgName -ErrorAction SilentlyContinue
    if ($locks) {
        foreach ($lock in $locks) {
            Write-Host "  Lock on $rgName : $($lock.Name) ($($lock.Level))" -NoNewline
            Write-Host " [OK]" -ForegroundColor Green
        }
    }
    else {
        Write-Host "  Lock on $rgName" -NoNewline
        Write-Host " [FAIL] Not found." -ForegroundColor Red
    }
}

# 4. Validate Budgets
Write-Host "`n=== 4. Validating Budgets ===" -ForegroundColor Cyan
# Budgets are technically Consumption resources.
$budgets = Get-AzConsumptionBudget -ErrorAction SilentlyContinue
if ($budgets) {
    foreach ($budget in $budgets) {
        Write-Host "  Budget found: $($budget.Name) (Amount: $($budget.Amount) $($budget.Unit))" -NoNewline
        Write-Host " [OK]" -ForegroundColor Green
    }
}
else {
    Write-Host "  [INFO] No budgets found. (If you created them recently, they might take time to appear)" -ForegroundColor Yellow
}

Write-Host "`nValidation Complete." -ForegroundColor Green
