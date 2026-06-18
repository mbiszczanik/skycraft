<#
.SYNOPSIS
    Configures Azure Blob Backup protection on the production storage account.

.DESCRIPTION
    Post-deployment script for Lab 5.2. After running Deploy-Bicep.ps1 this script:
    1. Assigns required RBAC roles to the Backup Vault managed identity on
       prodskycraftswcsa:
         - Storage Blob Data Owner
         - Storage Account Backup Contributor
    2. Creates the blob backup protection instance (backup instance) connecting
       prodskycraftswcsa to the SkyCraft-Blob-Policy backup policy.

    Requires Owner or User Access Administrator role at storage account scope
    to create role assignments.

.PARAMETER WhatIf
    Display planned actions without making changes.

.EXAMPLE
    .\New-LabBlobBackup.ps1

.EXAMPLE
    .\New-LabBlobBackup.ps1 -WhatIf

.NOTES
    Project: SkyCraft
    Lab: 5.2 - Business Continuity & Disaster Recovery
    Version: 1.0.0
    Date: 2026-04-06
#>

[CmdletBinding()]
param(
    [Parameter()]
    [switch]$WhatIf
)

$ErrorActionPreference = 'Stop'

$platformRg     = 'platform-skycraft-swc-rg'
$prodRg         = 'prod-skycraft-swc-rg'
$bvName         = 'platform-skycraft-swc-bv'
$storageAccount = 'prodskycraftswcsa'
$policyName     = 'SkyCraft-Blob-Policy'
$location       = 'swedencentral'

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  Lab 5.2 - Configure Blob Backup" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# ── [1/4] Validate prerequisites ──────────────────────────────────────────
Write-Host "[1/4] Validating prerequisites..." -ForegroundColor Yellow

$account = az account show --output json 2>$null | ConvertFrom-Json
if (-not $account) {
    Write-Host "  [ERROR] Not logged into Azure CLI. Run 'az login' first." -ForegroundColor Red
    exit 1
}
Write-Host "  ✓ Logged in as: $($account.user.name)" -ForegroundColor Green

az config set extension.use_dynamic_install=yes_without_prompt --only-show-errors | Out-Null

# ── [2/4] Resolve resource IDs ────────────────────────────────────────────
Write-Host "`n[2/4] Resolving resource IDs..." -ForegroundColor Yellow

$bvJson = az dataprotection backup-vault show `
    --resource-group $platformRg `
    --vault-name $bvName `
    --output json 2>$null | ConvertFrom-Json
if (-not $bvJson) {
    Write-Host "  [ERROR] Backup Vault '$bvName' not found. Run Deploy-Bicep.ps1 first." -ForegroundColor Red
    exit 1
}
$bvPrincipalId = $bvJson.identity.principalId
Write-Host "  ✓ Backup Vault found: $bvName (Principal: $bvPrincipalId)" -ForegroundColor Green

$storageJson = az storage account show `
    --name $storageAccount `
    --resource-group $prodRg `
    --output json 2>$null | ConvertFrom-Json
if (-not $storageJson) {
    Write-Host "  [ERROR] Storage account '$storageAccount' not found in '$prodRg'. Deploy Lab 4.1 first." -ForegroundColor Red
    exit 1
}
$storageId = $storageJson.id
Write-Host "  ✓ Storage account found: $storageAccount" -ForegroundColor Green

$policyJson = az dataprotection backup-policy show `
    --resource-group $platformRg `
    --vault-name $bvName `
    --name $policyName `
    --output json 2>$null | ConvertFrom-Json
if (-not $policyJson) {
    Write-Host "  [ERROR] Backup policy '$policyName' not found. Run Deploy-Bicep.ps1 first." -ForegroundColor Red
    exit 1
}
$policyId = $policyJson.id
Write-Host "  ✓ Backup policy found: $policyName" -ForegroundColor Green

# ── [3/4] Assign RBAC roles ───────────────────────────────────────────────
Write-Host "`n[3/4] Assigning RBAC roles to Backup Vault managed identity..." -ForegroundColor Yellow

$requiredRoles = @(
    @{ Name = 'Storage Blob Data Owner';            RoleId = 'b7e6dc6d-f1e8-4753-8033-0f276bb0955b' },
    @{ Name = 'Storage Account Backup Contributor'; RoleId = 'e5e2a7ff-d759-4cd2-bb51-3152d37e2eb1' }
)

foreach ($role in $requiredRoles) {
    Write-Host "  Checking: $($role.Name)..." -ForegroundColor Gray
    $existing = az role assignment list `
        --assignee $bvPrincipalId `
        --role $role.RoleId `
        --scope $storageId `
        --output json 2>$null | ConvertFrom-Json
    if ($existing.Count -gt 0) {
        Write-Host "  ✓ Already assigned: $($role.Name)" -ForegroundColor Green
    } elseif ($WhatIf) {
        Write-Host "  [WhatIf] Would assign: $($role.Name)" -ForegroundColor Cyan
    } else {
        try {
            az role assignment create `
                --assignee $bvPrincipalId `
                --role $role.RoleId `
                --scope $storageId `
                --output none
            Write-Host "  ✓ Assigned: $($role.Name)" -ForegroundColor Green
        } catch {
            Write-Host "  [ERROR] Failed to assign '$($role.Name)': $_" -ForegroundColor Red
            Write-Host "  Ensure you have Owner or User Access Administrator on the storage account." -ForegroundColor Yellow
            exit 1
        }
    }
}

if (-not $WhatIf) {
    Write-Host "`n  Waiting 30 seconds for RBAC propagation..." -ForegroundColor Gray
    Start-Sleep -Seconds 30
}

# ── [4/4] Create blob backup instance ────────────────────────────────────
Write-Host "`n[4/4] Configuring blob backup protection instance..." -ForegroundColor Yellow

$existingInstances = az dataprotection backup-instance list `
    --resource-group $platformRg `
    --vault-name $bvName `
    --output json 2>$null | ConvertFrom-Json
$existingInstance = $existingInstances | Where-Object {
    $_.properties.dataSourceInfo.resourceId -eq $storageId
}

if ($existingInstance) {
    Write-Host "  ✓ Blob backup instance already exists for $storageAccount" -ForegroundColor Green
} elseif ($WhatIf) {
    Write-Host "  [WhatIf] Would create blob backup instance for $storageAccount" -ForegroundColor Cyan
} else {
    try {
        $tempFile = Join-Path $env:TEMP 'blob-instance.json'
        az dataprotection backup-instance initialize `
            --datasource-type AzureBlob `
            --datasource-location $location `
            --datasource-id $storageId `
            --policy-id $policyId `
            --output json | Out-File -FilePath $tempFile -Encoding utf8

        az dataprotection backup-instance create `
            --resource-group $platformRg `
            --vault-name $bvName `
            --backup-instance "@$tempFile" `
            --output none

        Remove-Item -Path $tempFile -ErrorAction SilentlyContinue
        Write-Host "  ✓ Blob backup instance created for $storageAccount" -ForegroundColor Green
    } catch {
        Write-Host "  [ERROR] Failed to create blob backup instance: $_" -ForegroundColor Red
        Write-Host "  If the error is 'UserErrorMissingRequiredPermissions', wait 5-10 minutes and retry." -ForegroundColor Yellow
        exit 1
    }
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  Blob Backup Configuration Complete" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan
Write-Host "  Next Steps:" -ForegroundColor Cyan
Write-Host "    1. Run .\Test-Lab.ps1 to validate full BCDR deployment" -ForegroundColor Gray
Write-Host "    2. Configure Azure Site Recovery via Azure Portal (Step 5.2.8)" -ForegroundColor Gray
