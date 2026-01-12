<#
.SYNOPSIS
    Cleans up resources created in Lab 1.3 (Locks and Policies).

.DESCRIPTION
    Removes the resource locks from production/platform RGs.
    Removes the subscription-level policy assignments.
    Prompts for confirmation unless -Force is specified.

.PARAMETER Force
    Skip confirmation prompt.

.EXAMPLE
    .\Cleanup-Resources.ps1
    Interactive cleanup.

.NOTES
    Project: SkyCraft
    Lab: 1.3 - Governance
#>

[CmdletBinding()]
param(
    [switch]$Force
)

$ErrorActionPreference = "Stop"

Write-Host "=== Lab 1.3: Cleanup Resources ===" -ForegroundColor Cyan -BackgroundColor Black

# Check Azure Context
$context = Get-AzContext
if (-not $context) {
    Write-Host "Not logged in. Connecting..." -ForegroundColor Yellow
    $context = Connect-AzAccount
}
$subId = $context.Subscription.Id
Write-Host "Using Subscription: $($context.Subscription.Name)" -ForegroundColor Green

# Confirm
if (-not $Force) {
    $c = Read-Host "Are you sure you want to remove Lab 1.3 Governance (Locks, Policies)? (y/N)"
    if ($c -notmatch "^y$") {
        Write-Host "Cancelled." -ForegroundColor Yellow
        exit 0
    }
}

# 1. Remove Locks
Write-Host "`n1. Removing Resource Locks..." -ForegroundColor Cyan
$locks = @(
    @{ RG = "prod-skycraft-swc-rg"; Name = "lock-no-delete-prod" },
    @{ RG = "platform-skycraft-swc-rg"; Name = "lock-no-delete-platform" }
)

foreach ($lock in $locks) {
    if (Get-AzResourceLock -ResourceGroupName $lock.RG -LockName $lock.Name -ErrorAction SilentlyContinue) {
        try {
            Remove-AzResourceLock -ResourceGroupName $lock.RG -LockName $lock.Name -Force -ErrorAction Stop
            Write-Host "  -> [SUCCESS] Removed lock: $($lock.Name)" -ForegroundColor Green
        }
        catch {
            Write-Host "  -> [ERROR] Failed to remove lock $($lock.Name): $_" -ForegroundColor Red
        }
    }
    else {
        Write-Host "  -> [INFO] Lock $($lock.Name) not found." -ForegroundColor Gray
    }
}

# 2. Remove Policies
Write-Host "`n2. Removing Policy Assignments..." -ForegroundColor Cyan
$policies = @("Require-Environment-Tag-RG", "Enforce-Project-Tag", "Restrict-Azure-Regions")

foreach ($policy in $policies) {
    if (Get-AzPolicyAssignment -Name $policy -Scope "/subscriptions/$subId" -ErrorAction SilentlyContinue) {
        try {
            Remove-AzPolicyAssignment -Name $policy -Scope "/subscriptions/$subId" -ErrorAction Stop
            Write-Host "  -> [SUCCESS] Removed policy: $policy" -ForegroundColor Green
        }
        catch {
             Write-Host "  -> [ERROR] Failed to remove policy ${policy}: $_" -ForegroundColor Red
        }
    }
    else {
        Write-Host "  -> [INFO] Policy $policy not found." -ForegroundColor Gray
    }
}

Write-Host "`nCleanup complete." -ForegroundColor Green
