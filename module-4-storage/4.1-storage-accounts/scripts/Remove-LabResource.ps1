<#
.SYNOPSIS
    Removes Lab 4.1 - Storage Account resources.

.DESCRIPTION
    Deletes storage accounts created in Lab 4.1. Includes confirmation
    prompts unless -Force is specified.

.PARAMETER Environment
    Target environment to clean up: dev, prod, platform, or all.

.PARAMETER Force
    Skip confirmation prompts.

.EXAMPLE
    .\Remove-LabResource.ps1 -Environment dev
    Removes development storage account with confirmation.

.EXAMPLE
    .\Remove-LabResource.ps1 -Environment all -Force
    Removes all storage accounts without confirmation.

.NOTES
    Project: SkyCraft
    Lab: 4.1 - Storage Accounts
    Version: 1.0.0
    Date: 2026-02-05
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory = $false)]
    [ValidateSet('dev', 'prod', 'platform', 'all')]
    [string]$Environment = 'all',

    [Parameter(Mandatory = $false)]
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

Write-Host "=== Lab 4.1: Remove Storage Accounts ===" -ForegroundColor Cyan
Write-Host ""

# Storage account configurations
$storageConfigs = @{
    platform = @{
        Name          = 'platformskycraftswcsa'
        ResourceGroup = 'platform-skycraft-swc-rg'
        DisplayName   = 'Platform'
    }
    dev      = @{
        Name          = 'devskycraftswcsa'
        ResourceGroup = 'dev-skycraft-swc-rg'
        DisplayName   = 'Development'
    }
    prod     = @{
        Name          = 'prodskycraftswcsa'
        ResourceGroup = 'prod-skycraft-swc-rg'
        DisplayName   = 'Production'
    }
}

# Determine which environments to clean
$envsToClean = if ($Environment -eq 'all') {
    @('platform', 'dev', 'prod')
}
else {
    @($Environment)
}

# Display what will be deleted
Write-Host "--- Resources to Delete ---" -ForegroundColor Yellow
foreach ($env in $envsToClean) {
    $config = $storageConfigs[$env]
    Write-Host "  $($config.DisplayName): $($config.Name)" -ForegroundColor White
}
Write-Host ""

# Confirmation
if (-not $Force) {
    Write-Host "[WARNING] This action will permanently delete the above storage accounts!" -ForegroundColor Yellow
    Write-Host "          All data in these accounts will be lost." -ForegroundColor Yellow
    Write-Host ""
    $confirm = Read-Host "Type 'yes' to confirm deletion"
    
    if ($confirm -ne 'yes') {
        Write-Host ""
        Write-Host "Operation cancelled." -ForegroundColor Gray
        exit 0
    }
}

# Delete storage accounts
Write-Host ""
Write-Host "--- Deleting Storage Accounts ---" -ForegroundColor Yellow

$deleted = 0
$skipped = 0
$failed = 0

foreach ($env in $envsToClean) {
    $config = $storageConfigs[$env]
    
    Write-Host "  $($config.DisplayName) ($($config.Name))..." -ForegroundColor White -NoNewline
    
    try {
        # Check if exists
        $sa = Get-AzStorageAccount -ResourceGroupName $config.ResourceGroup -Name $config.Name -ErrorAction SilentlyContinue
        
        if (-not $sa) {
            Write-Host " SKIPPED (not found)" -ForegroundColor Gray
            $skipped++
            continue
        }
        
        # Delete
        if ($PSCmdlet.ShouldProcess($config.Name, "Delete storage account")) {
            Remove-AzStorageAccount `
                -ResourceGroupName $config.ResourceGroup `
                -Name $config.Name `
                -Force `
                -ErrorAction Stop
            
            Write-Host " DELETED" -ForegroundColor Green
            $deleted++
        }
    }
    catch {
        Write-Host " FAILED" -ForegroundColor Red
        Write-Host "    Error: $($_.Exception.Message)" -ForegroundColor Red
        $failed++
    }
}

# Summary
Write-Host ""
Write-Host "=== Cleanup Summary ===" -ForegroundColor Cyan
Write-Host "  Deleted: $deleted" -ForegroundColor Green
Write-Host "  Skipped: $skipped" -ForegroundColor Gray
Write-Host "  Failed:  $failed" -ForegroundColor $(if ($failed -gt 0) { 'Red' } else { 'Green' })
Write-Host ""

if ($failed -eq 0) {
    Write-Host "Cleanup complete." -ForegroundColor Green
}
else {
    Write-Host "Some resources failed to delete. Review errors above." -ForegroundColor Yellow
}
