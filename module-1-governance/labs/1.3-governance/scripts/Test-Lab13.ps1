# Lab 1.3 - Validation Script
# Validates Tags, Policies, Locks, and Budgets

Write-Host "=== Lab 1.3 Validation Script ===" -ForegroundColor Cyan -BackgroundColor Black

# Check Azure Connection
$context = Get-AzContext
if (-not $context) {
    Write-Host "Not logged in. Please run Connect-AzAccount" -ForegroundColor Red
    return
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
            Write-Host "[OK] $rgName has tags:" -ForegroundColor Green
            foreach ($key in $tags.Keys) {
                Write-Host "  - $key : $($tags[$key])" -ForegroundColor Gray
            }
            # Check for 'Project' tag specifically
            if ($tags.ContainsKey("Project") -and $tags["Project"] -eq "SkyCraft") {
                Write-Host "  -> Project tag verified." -ForegroundColor Green
            }
            else {
                Write-Host "  -> [FAIL] Missing or incorrect 'Project' tag." -ForegroundColor Red
            }
        }
        else {
            Write-Host "[FAIL] $rgName has NO tags." -ForegroundColor Red
        }
    }
    catch {
        Write-Host "[FAIL] Resource Group $rgName not found." -ForegroundColor Red
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
        Write-Host "[OK] Policy assigned: $policyName" -ForegroundColor Green
    }
    else {
        Write-Host "[FAIL] Policy assignment missing: $policyName" -ForegroundColor Red
    }
}

# 3. Validate Locks
Write-Host "`n=== 3. Validating Locks ===" -ForegroundColor Cyan
$lockTargets = @("prod-skycraft-swc-rg", "platform-skycraft-swc-rg")

foreach ($rgName in $lockTargets) {
    $locks = Get-AzResourceLock -ResourceGroupName $rgName -ErrorAction SilentlyContinue
    if ($locks) {
        foreach ($lock in $locks) {
            Write-Host "[OK] Lock found on $rgName : $($lock.Name) ($($lock.Level))" -ForegroundColor Green
        }
    }
    else {
        Write-Host "[FAIL] No locks found on $rgName" -ForegroundColor Red
    }
}

# 4. Validate Budgets
Write-Host "`n=== 4. Validating Budgets ===" -ForegroundColor Cyan
# Budgets are technically Consumption resources.
$budgets = Get-AzConsumptionBudget -ErrorAction SilentlyContinue
if ($budgets) {
    foreach ($budget in $budgets) {
        Write-Host "[OK] Budget found: $($budget.Name) (Amount: $($budget.Amount) $($budget.Unit))" -ForegroundColor Green
    }
}
else {
    Write-Host "[INFO] No budgets found. (If you created them recently, they might take time to appear or require different permission scope)" -ForegroundColor Yellow
}

Write-Host "`n=== Validation Summary ===" -ForegroundColor Cyan
Write-Host "Lab 1.3 validation complete" -ForegroundColor Green
