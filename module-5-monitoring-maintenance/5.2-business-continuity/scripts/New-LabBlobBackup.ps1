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
       prodskycraftswcsa to the SkyCraft-Blob-Policy backup policy. The policy is
       operational plus vaulted (issue #306), and vaulted backup protects the containers
       the instance lists, so the instance names every container in the account (Lab 4.2
       creates them). An account with no container stops the run: Microsoft Learn says
       vaulted backup needs at least one.

    Requires Owner or User Access Administrator role at storage account scope
    to create role assignments. The role assignments are read and created
    through the Azure Resource Manager role assignments API
    (tools/LabCommon.psm1), so the script needs no Microsoft Graph sign-in
    (issue #397); a read that fails stops the run with exit 1.

.PARAMETER WhatIf
    Display planned actions without making changes.

.EXAMPLE
    .\New-LabBlobBackup.ps1

.EXAMPLE
    .\New-LabBlobBackup.ps1 -WhatIf

.NOTES
    Project: SkyCraft
    Lab: 5.2 - Business Continuity & Disaster Recovery
    Version: 1.1.0
    Date: 2026-10-28
#>

#Requires -Version 7.0
#Requires -Modules Az.Accounts, Az.Resources, Az.DataProtection, Az.Storage

[CmdletBinding()]
param(
    [Parameter()]
    [switch]$WhatIf
)

$ErrorActionPreference = 'Stop'
# Exit-Lab ends the script with exit code 0 or 1 and leaves an interactive session open (#257).
# The module's role assignment helpers use the ARM API, not Microsoft Graph (#397).
Import-Module (Join-Path $PSScriptRoot '../../../tools/LabCommon.psm1') -Force -Verbose:$false

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

$context = Get-AzContext
if (-not $context) {
    Write-Host "  [ERROR] Not logged into Azure. Run 'Connect-AzAccount' first." -ForegroundColor Red
    Exit-Lab -FailureCount 1
}
Write-Host "  ✓ Logged in as: $($context.Account.Id)" -ForegroundColor Green

# ── [2/4] Resolve resource IDs ────────────────────────────────────────────
Write-Host "`n[2/4] Resolving resource IDs..." -ForegroundColor Yellow

$bv = Get-AzDataProtectionBackupVault -ResourceGroupName $platformRg -VaultName $bvName -ErrorAction SilentlyContinue
if (-not $bv) {
    Write-Host "  [ERROR] Backup Vault '$bvName' not found. Run Deploy-Bicep.ps1 first." -ForegroundColor Red
    Exit-Lab -FailureCount 1
}
$bvPrincipalId = $bv.IdentityPrincipalId
Write-Host "  ✓ Backup Vault found: $bvName (Principal: $bvPrincipalId)" -ForegroundColor Green

$storage = Get-AzStorageAccount -ResourceGroupName $prodRg -Name $storageAccount -ErrorAction SilentlyContinue
if (-not $storage) {
    Write-Host "  [ERROR] Storage account '$storageAccount' not found in '$prodRg'. Deploy Lab 4.1 first." -ForegroundColor Red
    Exit-Lab -FailureCount 1
}
$storageId = $storage.Id
Write-Host "  ✓ Storage account found: $storageAccount" -ForegroundColor Green

# SkyCraft-Blob-Policy is operational plus vaulted (#306): the operational part covers the
# whole account, the vaulted part only the containers the backup configuration lists.
# Get-AzRmStorageContainer is a control-plane listing, which the storage firewall does not block.
try {
    $containerNames = @(Get-AzRmStorageContainer -ResourceGroupName $prodRg -StorageAccountName $storageAccount -ErrorAction Stop |
        ForEach-Object { $_.Name } | Where-Object { $_ })
} catch {
    Write-Host "  [ERROR] Could not list the containers of '$storageAccount': $_" -ForegroundColor Red
    Exit-Lab -FailureCount 1
}
if ($containerNames.Count -eq 0) {
    Write-Host "  [ERROR] '$storageAccount' has no container. Vaulted blob backup needs at least one: run Lab 4.2 first." -ForegroundColor Red
    Exit-Lab -FailureCount 1
}
Write-Host "  Containers for vaulted backup: $($containerNames -join ', ')" -ForegroundColor Gray

$policy = Get-AzDataProtectionBackupPolicy -ResourceGroupName $platformRg -VaultName $bvName -Name $policyName -ErrorAction SilentlyContinue
if (-not $policy) {
    Write-Host "  [ERROR] Backup policy '$policyName' not found. Run Deploy-Bicep.ps1 first." -ForegroundColor Red
    Exit-Lab -FailureCount 1
}
$policyId = $policy.Id
Write-Host "  ✓ Backup policy found: $policyName" -ForegroundColor Green

# ── [3/4] Assign RBAC roles ───────────────────────────────────────────────
Write-Host "`n[3/4] Assigning RBAC roles to Backup Vault managed identity..." -ForegroundColor Yellow

$requiredRoles = @(
    @{ Name = 'Storage Blob Data Owner';            RoleId = 'b7e6dc6d-f1e8-4753-8033-0f276bb0955b' },
    @{ Name = 'Storage Account Backup Contributor'; RoleId = 'e5e2a7ff-d759-4cd2-bb51-3152d37e2eb1' }
)

# Read and granted through the ARM role assignments API (tools/LabCommon.psm1), not
# Get-AzRoleAssignment / New-AzRoleAssignment: those resolve the principal through Microsoft Graph
# and fail where the Az sign-in cannot get a Graph token (issue #397). A role the identity holds on
# the account or above it (the resource group, the subscription, a management group or the root)
# counts as held, as Get-AzRoleAssignment -Scope counted it; one held only below the account (on a
# container) does not cover the account. A read that fails stops the run: it cannot tell whether
# the role is there.
$coversAccount = {
    param([string]$Scope)
    $Scope -eq $storageId -or $storageId -like "$Scope/*" -or $Scope -eq '/' -or
        $Scope -like '/providers/Microsoft.Management/managementGroups/*'
}
foreach ($role in $requiredRoles) {
    Write-Host "  Checking: $($role.Name)..." -ForegroundColor Gray
    try {
        $existing = @(Get-LabArmRoleAssignment -Scope $storageId -PrincipalId $bvPrincipalId |
            Where-Object { $_.RoleDefinitionId -eq $role.RoleId -and (& $coversAccount $_.Scope) })
    } catch {
        Write-Host "  [ERROR] Could not read the role assignments of the Backup Vault identity on '$storageAccount': $_" -ForegroundColor Red
        Exit-Lab -FailureCount 1
    }
    if ($existing.Count -gt 0) {
        Write-Host "  ✓ Already assigned: $($role.Name)" -ForegroundColor Green
    } elseif ($WhatIf) {
        Write-Host "  [WhatIf] Would assign: $($role.Name)" -ForegroundColor Cyan
    } else {
        try {
            # ServicePrincipal: the vault's managed identity, so ARM does not look it up in the
            # directory first.
            New-LabArmRoleAssignment `
                -Scope $storageId `
                -RoleDefinitionId $role.RoleId `
                -PrincipalId $bvPrincipalId `
                -PrincipalType 'ServicePrincipal' | Out-Null
            Write-Host "  ✓ Assigned: $($role.Name)" -ForegroundColor Green
        } catch {
            Write-Host "  [ERROR] Failed to assign '$($role.Name)': $_" -ForegroundColor Red
            Write-Host "  Ensure you have Owner or User Access Administrator on the storage account." -ForegroundColor Yellow
            Exit-Lab -FailureCount 1
        }
    }
}

if (-not $WhatIf) {
    Write-Host "`n  Waiting 360 seconds for RBAC propagation (Azure Backup requires 5-10 min)..." -ForegroundColor Gray
    Start-Sleep -Seconds 360
}

# ── [4/4] Create blob backup instance ────────────────────────────────────
Write-Host "`n[4/4] Configuring blob backup protection instance..." -ForegroundColor Yellow

$existingInstances = Get-AzDataProtectionBackupInstance -ResourceGroupName $platformRg -VaultName $bvName -ErrorAction SilentlyContinue
$existingInstance = $existingInstances | Where-Object {
    $_.Property.DataSourceInfo.ResourceId -eq $storageId
}

if ($existingInstance) {
    Write-Host "  ✓ Blob backup instance already exists for $storageAccount" -ForegroundColor Green
} elseif ($WhatIf) {
    Write-Host "  [WhatIf] Would create blob backup instance for $storageAccount" -ForegroundColor Cyan
} else {
    try {
        # -ErrorAction Stop is required because the autorest DataProtection cmdlets emit
        # non-terminating errors, which previously printed a false "created" success.
        $backupConfig = New-AzDataProtectionBackupConfigurationClientObject `
            -DatasourceType AzureBlob `
            -VaultedBackupContainer $containerNames `
            -ErrorAction Stop

        $backupInstance = Initialize-AzDataProtectionBackupInstance `
            -DatasourceType AzureBlob `
            -DatasourceLocation $location `
            -DatasourceId $storageId `
            -PolicyId $policyId `
            -BackupConfiguration $backupConfig `
            -ErrorAction Stop

        New-AzDataProtectionBackupInstance `
            -ResourceGroupName $platformRg `
            -VaultName $bvName `
            -BackupInstance $backupInstance `
            -ErrorAction Stop | Out-Null

        Write-Host "  ✓ Blob backup instance created for $storageAccount" -ForegroundColor Green
    } catch {
        Write-Host "  [ERROR] Failed to create blob backup instance: $_" -ForegroundColor Red
        Write-Host "  If the error is 'UserErrorMissingRequiredPermissions', wait 5-10 minutes and retry." -ForegroundColor Yellow
        Exit-Lab -FailureCount 1
    }
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  Blob Backup Configuration Complete" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan
Write-Host "  Next Steps:" -ForegroundColor Cyan
Write-Host "    1. Run .\Test-Lab.ps1 to validate full BCDR deployment" -ForegroundColor Gray
Write-Host "    2. Configure Azure Site Recovery via Azure Portal (Step 5.2.6)" -ForegroundColor Gray
