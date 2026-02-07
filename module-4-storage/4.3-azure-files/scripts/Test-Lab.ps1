<#
.SYNOPSIS
    Validates Lab 4.3 Deployment
.DESCRIPTION
    Checks if resources exist and are configured correctly.
.NOTES
    Project: SkyCraft
    Author: SkyCraft Team
    Date: 2026-02-07
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$ResourceGroupName = 'prod-skycraft-swc-rg'
)

Write-Host "=== Lab 4.3: Validating Environment ===" -ForegroundColor Cyan

# 1. Verify Connection
if (-not (Get-AzContext)) {
    Write-Host "Not logged in." -ForegroundColor Red; exit 1
}

# 2. Check Storage Account
try {
    Write-Host "Checking Storage Account..." -ForegroundColor Yellow
    $sa = Get-AzStorageAccount -ResourceGroupName $ResourceGroupName -ErrorAction Stop
    if ($sa) {
        Write-Host "  -> Storage Account found: $($sa.StorageAccountName)" -ForegroundColor Green
    }
}
catch {
    Write-Host "  -> [ERROR] Storage Account not found in $ResourceGroupName" -ForegroundColor Red
}

# 3. Check File Shares (Note: Student creates them, but we check if they exist)
try {
    Write-Host "Checking File Shares..." -ForegroundColor Yellow
    # Get connections tring or context
    $ctx = $sa.Context
    $shares = Get-AzStorageShare -Context $ctx -ErrorAction SilentlyContinue

    if ($shares) {
        foreach ($share in $shares) {
            Write-Host "  -> Found Share: $($share.Name) (Quota: $($share.Quota)GB)" -ForegroundColor Green
        }
    }
    else {
        Write-Host "  -> [INFO] No file shares found (Student needs to create them)." -ForegroundColor Gray
    }
}
catch {
    Write-Host "  -> [WARNING] Could not list file shares." -ForegroundColor Yellow
}

Write-Host "Validation Complete." -ForegroundColor Cyan
