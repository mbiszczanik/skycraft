<#
.SYNOPSIS
    Cleans up resources created in Lab 1.2 (Resource Groups and Assignments).

.DESCRIPTION
    Deletes the 'dev', 'prod', and 'platform' resource groups.
    Removes the subscription-level Owner assignment for Malfurion Stormrage.
    Prompts for confirmation unless -Force is specified.

.PARAMETER Force
    Skip confirmation prompt.

.EXAMPLE
    .\Remove-LabResource.ps1
    Interactive cleanup.

.NOTES
    Project: SkyCraft
    Lab: 1.2 - RBAC
#>

#Requires -Version 7.0
#Requires -Modules Az.Accounts, Az.Resources

[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [switch]$Force
)

$ErrorActionPreference = "Stop"
if ($Force) { $ConfirmPreference = 'None' }

Write-Host "=== Lab 1.2: Cleanup Resources ===" -ForegroundColor Cyan -BackgroundColor Black

# Check Azure Context
$context = Get-AzContext
if (-not $context) {
    Write-Host "Not logged in. Connecting..." -ForegroundColor Yellow
    $context = Connect-AzAccount
}
$subId = $context.Subscription.Id
Write-Host "Using Subscription: $($context.Subscription.Name)" -ForegroundColor Green


Write-Host "`n1. Removing Subscription-Level Role Assignment (Owner)..." -ForegroundColor Cyan
# Need to find it first because Remove-AzRoleAssignment by logic can be tricky
try {
    # Resolve UPN via Graph to get ObjectId, or just search by SignInName
    # We will search assignments by SignInName for simplicity
    $assignments = Get-AzRoleAssignment -Scope "/subscriptions/$subId" -IncludeClassicAdministrators:$false -ErrorAction SilentlyContinue 
    $malfurion = $assignments | Where-Object { ($_.SignInName -like "malfurion.stormrage@*") -and ($_.RoleDefinitionName -eq "Owner") }
    
    if ($malfurion) {
        if ($PSCmdlet.ShouldProcess("/subscriptions/$subId", "Remove Owner role assignment for Malfurion")) {
            Remove-AzRoleAssignment -ObjectId $malfurion.ObjectId -RoleDefinitionName "Owner" -Scope "/subscriptions/$subId" -ErrorAction Stop
            Write-Host "  -> [SUCCESS] Removed Owner role for Malfurion." -ForegroundColor Green
        }
    }
    else {
        Write-Host "  -> [INFO] Assignment not found." -ForegroundColor Gray
    }
}
catch {
    Write-Host "  -> [ERROR] Failed to remove role: $_" -ForegroundColor Red
}

Write-Host "`n2. Deleting Resource Groups..." -ForegroundColor Cyan
$rgs = @("dev-skycraft-swc-rg", "prod-skycraft-swc-rg", "platform-skycraft-swc-rg")

foreach ($rg in $rgs) {
    if (Get-AzResourceGroup -Name $rg -ErrorAction SilentlyContinue) {
        if ($PSCmdlet.ShouldProcess($rg, "Remove resource group")) {
            Write-Host "  Deleting $rg... (this may take a moment)" -ForegroundColor Yellow
            try {
                Remove-AzResourceGroup -Name $rg -Force -ErrorAction Stop
                Write-Host "  -> [SUCCESS] Deleted $rg" -ForegroundColor Green
            }
            catch {
                 Write-Host "  -> [ERROR] Failed to delete $($rg): $_" -ForegroundColor Red
            }
        }
    }
    else {
        Write-Host "  -> [INFO] $rg not found." -ForegroundColor Gray
    }
}

Write-Host "`nCleanup complete." -ForegroundColor Green
