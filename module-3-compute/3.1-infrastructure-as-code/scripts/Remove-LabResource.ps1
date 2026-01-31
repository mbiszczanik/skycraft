<#
.SYNOPSIS
    Removes Lab 3.1 Infrastructure Resources.

.DESCRIPTION
    Deletes the Resource Groups created by the lab.
    WARNING: This is a destructive operation.

.PARAMETER Environment
    Target environment to clean (dev, prod, all). Default: 'dev'
    'all' will remove Platform, Dev, and Prod RGs.

.EXAMPLE
    .\Cleanup-Resources.ps1 -Environment all
#>

[CmdletBinding()]
param(
    [ValidateSet('dev', 'prod', 'all')]
    [string]$Environment = 'dev'
)

Write-Host "=== Lab 3.1 Cleanup Script ===" -ForegroundColor Cyan

$project = 'skycraft'
$locationShortCode = 'swc'

$groupsToRemove = @()

if ($Environment -eq 'dev' -or $Environment -eq 'all') {
    $groupsToRemove += "dev-$project-$locationShortCode-rg"
}
if ($Environment -eq 'prod' -or $Environment -eq 'all') {
    $groupsToRemove += "prod-$project-$locationShortCode-rg"
}
if ($Environment -eq 'all') {
    $groupsToRemove += "platform-$project-$locationShortCode-rg"
}

if ($groupsToRemove.Count -eq 0) {
    Write-Host "No groups selected." -ForegroundColor Yellow
    exit
}

Write-Host "The following Resource Groups will be DELETED:" -ForegroundColor Red
$groupsToRemove | ForEach-Object { Write-Host " - $_" }

$confirm = Read-Host "Are you sure? (Type 'yes' to confirm)"
if ($confirm -ne 'yes') {
    Write-Host "Cancelled." -ForegroundColor Gray
    exit
}

foreach ($rgName in $groupsToRemove) {
    Write-Host "Deleting '$rgName'..." -ForegroundColor Yellow
    try {
        Remove-AzResourceGroup -Name $rgName -Force -ErrorAction Stop
        Write-Host "[SUCCESS] Deleted '$rgName'." -ForegroundColor Green
    }
    catch {
        Write-Host "[FAIL] Could not delete '$rgName'. It may not exist." -ForegroundColor Red
        Write-Host "Error: $_" -ForegroundColor Red
    }
}

Write-Host "`nCleanup Complete." -ForegroundColor Cyan
