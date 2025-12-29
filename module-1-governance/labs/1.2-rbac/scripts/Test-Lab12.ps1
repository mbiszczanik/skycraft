# Lab 1.2 - Validation Script (PowerShell version)
# Validates Resource Groups and role assignments

Write-Host "=== Lab 1.2 Validation Script ===" -ForegroundColor Cyan -BackgroundColor Black

# Check Azure Connection
Write-Host "`nChecking Azure connection..." -ForegroundColor Cyan
$context = Get-AzContext
if (-not $context) {
    Write-Host "Not logged in. Please run Connect-AzAccount" -ForegroundColor Red
    return
}
Write-Host "Connected to: $($context.Subscription.Name)" -ForegroundColor Green

$resourceGroups = @("dev-skycraft-swc-rg", "prod-skycraft-swc-rg", "platform-skycraft-swc-rg")

# Validate Resource Groups
Write-Host "`nValidating Resource Groups..." -ForegroundColor Cyan
foreach ($rgName in $resourceGroups) {
    try {
        Get-AzResourceGroup -Name $rgName -ErrorAction Stop | Out-Null
        Write-Host "[OK] Resource Group exists: $rgName" -ForegroundColor Green
    }
    catch {
        Write-Host "[FAIL] Resource Group missing: $rgName" -ForegroundColor Red
    }
}

# Validate Role Assignments
Write-Host "`nChecking Role Assignments..." -ForegroundColor Cyan
foreach ($rgName in $resourceGroups) {
    Write-Host "`n--- $rgName ---" -ForegroundColor Yellow
    $assignments = Get-AzRoleAssignment -ResourceGroupName $rgName -ErrorAction SilentlyContinue
    if ($assignments) {
        $assignments | Select-Object DisplayName, SignInName, RoleDefinitionName | Format-Table
    }
    else {
        Write-Host "No role assignments found for this Resource Group." -ForegroundColor Gray
    }
}

Write-Host "`n=== Validation Summary ===" -ForegroundColor Cyan
Write-Host "Lab 1.2 validation complete" -ForegroundColor Green
