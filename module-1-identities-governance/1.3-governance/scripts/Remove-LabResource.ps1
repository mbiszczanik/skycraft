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
    .\Remove-LabResource.ps1
    Interactive cleanup.

.NOTES
    Project: SkyCraft
    Lab: 1.3 - Governance
#>

#Requires -Version 7.0
#Requires -Modules Az.Accounts, Az.Resources

[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [switch]$Force
)

$ErrorActionPreference = "Stop"
if ($Force) { $ConfirmPreference = 'None' }

Write-Host "=== Lab 1.3: Cleanup Resources ===" -ForegroundColor Cyan -BackgroundColor Black

# Check Azure Context
$context = Get-AzContext
if (-not $context) {
    Write-Host "Not logged in. Connecting..." -ForegroundColor Yellow
    $context = Connect-AzAccount
}
$subId = $context.Subscription.Id
Write-Host "Using Subscription: $($context.Subscription.Name)" -ForegroundColor Green

# 1. Remove Locks
Write-Host "`n1. Removing Resource Locks..." -ForegroundColor Cyan
$locks = @(
    @{ RG = "prod-skycraft-swc-rg"; Name = "lock-no-delete-prod" },
    @{ RG = "platform-skycraft-swc-rg"; Name = "lock-no-delete-platform" }
)

foreach ($lock in $locks) {
    if (Get-AzResourceLock -ResourceGroupName $lock.RG -LockName $lock.Name -ErrorAction SilentlyContinue) {
        if ($PSCmdlet.ShouldProcess("$($lock.Name) on $($lock.RG)", 'Remove resource lock')) {
            try {
                Remove-AzResourceLock -ResourceGroupName $lock.RG -LockName $lock.Name -Force -ErrorAction Stop
                Write-Host "  -> [SUCCESS] Removed lock: $($lock.Name)" -ForegroundColor Green
            }
            catch {
                Write-Host "  -> [ERROR] Failed to remove lock $($lock.Name): $_" -ForegroundColor Red
            }
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
        if ($PSCmdlet.ShouldProcess("$policy on /subscriptions/$subId", 'Remove policy assignment')) {
            try {
                Remove-AzPolicyAssignment -Name $policy -Scope "/subscriptions/$subId" -ErrorAction Stop
                Write-Host "  -> [SUCCESS] Removed policy: $policy" -ForegroundColor Green
            }
            catch {
                 Write-Host "  -> [ERROR] Failed to remove policy ${policy}: $_" -ForegroundColor Red
            }
        }
    }
    else {
        Write-Host "  -> [INFO] Policy $policy not found." -ForegroundColor Gray
    }
}

Write-Host "`nCleanup complete." -ForegroundColor Green
