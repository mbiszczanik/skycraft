<#
.SYNOPSIS
    Creates the blob backup policy and protects the production storage account with it.

.DESCRIPTION
    Lab 5.2 script, run after the Backup Vault exists (Step 5.2.4 or Deploy-Bicep.ps1):
    1. Creates SkyCraft-Blob-Policy in platform-skycraft-swc-bv when it is missing: operational
       backup only, 30 days in the OperationalStore, no vaulted backup rule, so the policy has
       no Azure Backup charge. Every retention value is set here; nothing is taken from the
       defaults of Get-AzDataProtectionPolicyTemplate, which now ships a vaulted weekly rule
       with 7 days in the VaultStore (issues #306, #366). A policy of that name that has a
       vaulted rule (one created in the Portal) stops the run: a policy cannot be updated in
       place.
    2. Assigns required RBAC roles to the Backup Vault managed identity on
       prodskycraftswcsa:
         - Storage Blob Data Owner
         - Storage Account Backup Contributor
    3. Creates the blob backup protection instance (backup instance) connecting
       prodskycraftswcsa to the SkyCraft-Blob-Policy backup policy.

    Requires Owner or User Access Administrator role at storage account scope
    to create role assignments. The role assignments are read and created
    through the Azure Resource Manager role assignments API
    (tools/LabCommon.psm1), so the script needs no Microsoft Graph sign-in
    (issue #397); a read that fails stops the run with exit 1.

.PARAMETER ProdSaName
    Production storage account name. Default: prodskycraftswcsa. Pass the name given to Lab 4.1's
    Deploy-Bicep.ps1.
.PARAMETER PolicyOnly
    Create (or check) SkyCraft-Blob-Policy and stop: Step 5.2.5 a. The roles and the backup
    instance are then done in the Portal (Step 5.2.5 b and c), or by running the script again
    without the switch.

.PARAMETER WhatIf
    Display planned actions without making changes.

.EXAMPLE
    .\New-LabBlobBackup.ps1 -PolicyOnly

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
    [ValidatePattern('^[a-z0-9]{3,24}$')]
    [string]$ProdSaName = 'prodskycraftswcsa',
    [switch]$PolicyOnly,

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
$storageAccount = $ProdSaName
$policyName     = 'SkyCraft-Blob-Policy'
$location       = 'swedencentral'
$retentionDays  = 30

# What is wrong with a blob policy's ARM body for this lab: a vaulted rule, or no 30-day
# OperationalStore retention. Empty when it is the lab's policy.
function Get-LabBlobPolicyProblem {
    param([object]$Properties)

    $problems = @()
    $rules = @($Properties.policyRules | Where-Object { $_ })
    foreach ($rule in $rules) {
        if ($rule.objectType -eq 'AzureBackupRule') {
            $problems += "vaulted backup rule '$($rule.name)' (data store $($rule.dataStore.dataStoreType))"
        }
        foreach ($lc in @($rule.lifecycles | Where-Object { $_ })) {
            if ("$($lc.sourceDataStore.dataStoreType)" -ne 'OperationalStore') {
                $problems += "retention '$($rule.name)' in $($lc.sourceDataStore.dataStoreType)"
            }
        }
    }
    $operational = @($rules | ForEach-Object { @($_.lifecycles) } | Where-Object {
            $_ -and "$($_.sourceDataStore.dataStoreType)" -eq 'OperationalStore' -and "$($_.deleteAfter.duration)" -eq "P$($retentionDays)D"
        })
    if ($operational.Count -eq 0) { $problems += "no ${retentionDays}-day OperationalStore retention" }
    return $problems
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  Lab 5.2 - Configure Blob Backup" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# ── [1/5] Validate prerequisites ──────────────────────────────────────────
Write-Host "[1/5] Validating prerequisites..." -ForegroundColor Yellow

$context = Get-AzContext
if (-not $context) {
    Write-Host "  [ERROR] Not logged into Azure. Run 'Connect-AzAccount' first." -ForegroundColor Red
    Exit-Lab -FailureCount 1
}
Write-Host "  ✓ Logged in as: $($context.Account.Id)" -ForegroundColor Green

$bv = Get-AzDataProtectionBackupVault -ResourceGroupName $platformRg -VaultName $bvName -ErrorAction SilentlyContinue
if (-not $bv) {
    Write-Host "  [ERROR] Backup Vault '$bvName' not found. Create it first (Step 5.2.4, or Deploy-Bicep.ps1)." -ForegroundColor Red
    Exit-Lab -FailureCount 1
}
$bvPrincipalId = $bv.IdentityPrincipalId
Write-Host "  ✓ Backup Vault found: $bvName (Principal: $bvPrincipalId)" -ForegroundColor Green

# ── [2/5] Blob backup policy ──────────────────────────────────────────────
Write-Host "`n[2/5] Ensuring blob backup policy '$policyName' (operational, $retentionDays days)..." -ForegroundColor Yellow

$policy = Get-AzDataProtectionBackupPolicy -ResourceGroupName $platformRg -VaultName $bvName -Name $policyName -ErrorAction SilentlyContinue
if ($policy) {
    # Raw ARM body: the typed object's property names vary across Az.DataProtection versions.
    $policyArm = Get-AzResource -ResourceId "$($bv.Id)/backupPolicies/$policyName" -ApiVersion '2023-01-01' -ExpandProperties -ErrorAction SilentlyContinue
    if (-not $policyArm) {
        Write-Host "  [ERROR] Could not read the rules of '$policyName'." -ForegroundColor Red
        Exit-Lab -FailureCount 1
    }
    $problems = @(Get-LabBlobPolicyProblem -Properties $policyArm.Properties)
    if ($problems.Count -gt 0) {
        Write-Host "  [ERROR] '$policyName' is not the lab's policy: $($problems -join '; ')." -ForegroundColor Red
        Write-Host "    A policy created in the Portal always has a vaulted rule, which is billed." -ForegroundColor Gray
        Write-Host "    Azure Backup cannot update a policy in place (UserErrorBMSUpdatePolicyNotSupported):" -ForegroundColor Gray
        Write-Host "    delete it (Lab 1.3's lock on $platformRg blocks the delete, see Troubleshooting) and run this script again." -ForegroundColor Gray
        Exit-Lab -FailureCount 1
    }
    Write-Host "  ✓ Policy found: $policyName (operational, $retentionDays days, no vaulted rule)" -ForegroundColor Green
} elseif ($WhatIf) {
    Write-Host "  [WhatIf] Would create $policyName (OperationalStore $retentionDays days, no vaulted rule)" -ForegroundColor Cyan
} else {
    try {
        # Every rule is replaced: the template only supplies the object types. One retention rule,
        # 'Default', OperationalStore, P30D; no AzureBackupRule, so nothing is copied to the vault.
        # The lifecycle is set directly because Edit-AzDataProtectionPolicyRetentionRuleClientObject
        # 3.x reserves 'Default' for the VaultStore.
        $blobPolicy = Get-AzDataProtectionPolicyTemplate -DatasourceType AzureBlob
        $retentionRule = @($blobPolicy.PolicyRule | Where-Object { $_.ObjectType -eq 'AzureRetentionRule' }) | Select-Object -First 1
        if (-not $retentionRule) { throw 'the AzureBlob policy template has no retention rule to build on' }
        $retentionRule.Name = 'Default'
        $retentionRule.IsDefault = $true
        $retentionRule.Lifecycle = @(
            New-AzDataProtectionRetentionLifeCycleClientObject `
                -SourceDataStore OperationalStore `
                -SourceRetentionDurationType Days `
                -SourceRetentionDurationCount $retentionDays
        )
        $blobPolicy.PolicyRule = @($retentionRule)

        $policy = New-AzDataProtectionBackupPolicy `
            -ResourceGroupName $platformRg `
            -VaultName $bvName `
            -Name $policyName `
            -Policy $blobPolicy `
            -ErrorAction Stop
        Write-Host "  ✓ Policy created: $policyName (OperationalStore $retentionDays days, no vaulted rule, no Azure Backup charge)" -ForegroundColor Green
    } catch {
        Write-Host "  [ERROR] Failed to create '$policyName': $_" -ForegroundColor Red
        Exit-Lab -FailureCount 1
    }
}

if ($PolicyOnly) {
    Write-Host "`n  -PolicyOnly: roles and backup instance skipped (Step 5.2.5 b and c)." -ForegroundColor Gray
    Exit-Lab -FailureCount 0
}

$policyId = $policy.Id

# ── [3/5] Resolve the storage account ─────────────────────────────────────
Write-Host "`n[3/5] Resolving the storage account..." -ForegroundColor Yellow

$storage = Get-AzStorageAccount -ResourceGroupName $prodRg -Name $storageAccount -ErrorAction SilentlyContinue
if (-not $storage) {
    Write-Host "  [ERROR] Storage account '$storageAccount' not found in '$prodRg'. Deploy Lab 4.1 first." -ForegroundColor Red
    Exit-Lab -FailureCount 1
}
$storageId = $storage.Id
Write-Host "  ✓ Storage account found: $storageAccount" -ForegroundColor Green

# ── [4/5] Assign RBAC roles ───────────────────────────────────────────────
Write-Host "`n[4/5] Assigning RBAC roles to Backup Vault managed identity..." -ForegroundColor Yellow

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

# ── [5/5] Create blob backup instance ────────────────────────────────────
Write-Host "`n[5/5] Configuring blob backup protection instance..." -ForegroundColor Yellow

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
        # SkyCraft-Blob-Policy is an operational (continuous) blob policy and protects the whole
        # storage account. A backup configuration listing containers belongs to vaulted blob
        # backup; passing one here makes the service reject the request with
        # 'UserErrorInvalidRequestParameter: Parameter NO_PARAM in request is invalid'.
        # -ErrorAction Stop is required because the autorest DataProtection cmdlets emit
        # non-terminating errors, which previously printed a false "created" success.
        $backupInstance = Initialize-AzDataProtectionBackupInstance `
            -DatasourceType AzureBlob `
            -DatasourceLocation $location `
            -DatasourceId $storageId `
            -PolicyId $policyId `
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
Exit-Lab -FailureCount 0
