<#
.SYNOPSIS
    Validates Lab 5.2 Business Continuity & Disaster Recovery deployment.

.DESCRIPTION
    Verifies all Lab 5.2 BCDR resources are deployed and correctly configured:
    - Recovery Services Vault (platform-skycraft-swc-rsv): exists, LRS, required tags
    - VM Backup Policy (SkyCraft-Daily-Prod): daily schedule, 30-day retention
    - VM backup protection enabled on dev-skycraft-swc-auth-vm (skipped if VM absent)
    - Backup Vault (platform-skycraft-swc-bv): exists, LRS, system-assigned identity
    - Blob Backup Policy (SkyCraft-Blob-Policy): AzureBlob datasource, 30-day retention
    - Blob backup instance configured for prodskycraftswcsa

    Property reads with uncertain typed-object names (storage type, identity,
    soft-delete state, datasource type, retention) use Get-AzResource against the
    raw ARM body for reliability.

    Note: Azure Site Recovery replication status must be verified manually
    in the Azure Portal (the ASR replication flow is portal-only per Step 5.2.6).

.EXAMPLE
    .\Test-Lab.ps1

.NOTES
    Project: SkyCraft
    Lab: 5.2 - Business Continuity & Disaster Recovery
    Version: 1.0.0
    Date: 2026-04-06
#>

#Requires -Version 7.0
#Requires -Modules Az.Accounts, Az.Resources, Az.RecoveryServices, Az.DataProtection, Az.Storage, Az.Compute

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$platformRg     = 'platform-skycraft-swc-rg'
$prodRg         = 'prod-skycraft-swc-rg'
$rsvName        = 'platform-skycraft-swc-rsv'
$bvName         = 'platform-skycraft-swc-bv'
$vmName         = 'dev-skycraft-swc-auth-vm'
$vmRg           = 'dev-skycraft-swc-rg'
$storageAccount = 'prodskycraftswcsa'

$passCount = 0
$failCount = 0

function Invoke-Test {
    param(
        [string]$Label,
        [scriptblock]$Test
    )
    Write-Host "  Testing: $Label..." -NoNewline
    try {
        $result = & $Test
        if ($result) {
            Write-Host " PASS" -ForegroundColor Green
            $script:passCount++
        } else {
            Write-Host " FAIL" -ForegroundColor Red
            $script:failCount++
        }
    } catch {
        Write-Host " FAIL ($($_.Exception.Message))" -ForegroundColor Red
        $script:failCount++
    }
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Lab 5.2 - BCDR Deployment Validation" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

$context = Get-AzContext
if (-not $context) {
    Write-Host "  [ERROR] Not logged into Azure. Run 'Connect-AzAccount' first." -ForegroundColor Red
    exit 1
}
Write-Host "  Account: $($context.Account.Id)" -ForegroundColor Gray
Write-Host ""

# ============================================================================
# Recovery Services Vault Tests
# ============================================================================
Write-Host "[Recovery Services Vault]" -ForegroundColor Yellow

$rsv = Get-AzRecoveryServicesVault -ResourceGroupName $platformRg -Name $rsvName -ErrorAction SilentlyContinue

Invoke-Test "RSV '$rsvName' exists" {
    return ($null -ne $rsv -and $rsv.Name -eq $rsvName)
}

Invoke-Test "RSV location is swedencentral" {
    if (-not $rsv) { return $false }
    return ($rsv.Location -eq 'swedencentral')
}

Invoke-Test "RSV storage redundancy is LocallyRedundant" {
    if (-not $rsv) { return $false }
    $props = Get-AzRecoveryServicesBackupProperty -Vault $rsv
    return ($props.BackupStorageRedundancy -eq 'LocallyRedundant')
}

# Read tags from the raw ARM resource — Get-AzRecoveryServicesVault does not
# reliably populate .Tags across Az.RecoveryServices versions.
$rsvTags = if ($rsv) { (Get-AzResource -ResourceId $rsv.ID -ErrorAction SilentlyContinue).Tags } else { $null }

Invoke-Test "RSV tag 'Project' = 'SkyCraft'" {
    return ($null -ne $rsvTags -and $rsvTags.Project -eq 'SkyCraft')
}

Invoke-Test "RSV tag 'Environment' = 'Platform'" {
    return ($null -ne $rsvTags -and $rsvTags.Environment -eq 'Platform')
}

Invoke-Test "RSV tag 'CostCenter' = 'MSDN'" {
    return ($null -ne $rsvTags -and $rsvTags.CostCenter -eq 'MSDN')
}

Invoke-Test "RSV soft delete is AlwaysON (platform-enforced, docs/bicep-standards.md section 4.5)" {
    if (-not $rsv) { return $false }
    # Read soft-delete state from the raw ARM backupconfig sub-resource (reliable). Azure Backup
    # "secure by default" enforces AlwaysON on every new vault; the template sends no
    # softDeleteSettings at all, and no API version or tool can turn it off.
    $state = $null
    $cfg = Get-AzResource -ResourceId "$($rsv.ID)/backupconfig/vaultconfig" -ApiVersion '2023-06-01' -ExpandProperties -ErrorAction SilentlyContinue
    if ($cfg) { $state = $cfg.Properties.softDeleteFeatureState }
    if (-not $state) {
        $props = Get-AzRecoveryServicesVaultProperty -VaultId $rsv.ID -ErrorAction SilentlyContinue
        $state = $props.SoftDeleteFeatureState
    }
    return ($state -eq 'AlwaysON')
}

# ============================================================================
# VM Backup Policy Tests
# ============================================================================
Write-Host ""
Write-Host "[VM Backup Policy]" -ForegroundColor Yellow

$rsvPolicy = if ($rsv) {
    Get-AzRecoveryServicesBackupProtectionPolicy -Name 'SkyCraft-Daily-Prod' -VaultId $rsv.ID -ErrorAction SilentlyContinue
} else { $null }

Invoke-Test "Policy 'SkyCraft-Daily-Prod' exists" {
    return ($null -ne $rsvPolicy -and $rsvPolicy.Name -eq 'SkyCraft-Daily-Prod')
}

Invoke-Test "Policy backup frequency is Daily" {
    if (-not $rsvPolicy) { return $false }
    $freq = $rsvPolicy.SchedulePolicy.ScheduleRunFrequency
    return ($freq -eq 'Daily')
}

Invoke-Test "Policy daily retention is 30 days" {
    if (-not $rsvPolicy) { return $false }
    $count = $rsvPolicy.RetentionPolicy.DailySchedule.DurationCountInDays
    return ($count -eq 30)
}

Invoke-Test "Policy instant restore retention is 2 days" {
    if (-not $rsvPolicy -or -not $rsv) { return $false }
    # SnapshotRetentionInDays naming is version-sensitive; read the raw ARM property
    # instantRpRetentionRangeInDays and fall back to the typed property.
    $pol = Get-AzResource -ResourceId "$($rsv.ID)/backupPolicies/SkyCraft-Daily-Prod" -ApiVersion '2023-06-01' -ExpandProperties -ErrorAction SilentlyContinue
    if ($pol -and $null -ne $pol.Properties.instantRpRetentionRangeInDays) {
        return ($pol.Properties.instantRpRetentionRangeInDays -eq 2)
    }
    return ($rsvPolicy.SnapshotRetentionInDays -eq 2)
}

Invoke-Test "Policy schedule time contains 02:00 UTC" {
    if (-not $rsvPolicy) { return $false }
    $times = $rsvPolicy.SchedulePolicy.ScheduleRunTimes
    # ScheduleRunTimes are stored as UTC DateTime values — normalize and compare the time-of-day
    return ($null -ne ($times | Where-Object {
        ([datetime]::SpecifyKind([datetime]$_, [System.DateTimeKind]::Utc)).ToString('HH:mm') -eq '02:00'
    }))
}

# ============================================================================
# VM Backup Protection Tests
# ============================================================================
Write-Host ""
Write-Host "[VM Backup Protection]" -ForegroundColor Yellow

# The cycle protects the dev VM only. If it was never deployed (Lab 3.2 skipped),
# WARN and skip these checks rather than failing the validation.
$devVm = Get-AzVM -Name $vmName -ResourceGroupName $vmRg -ErrorAction SilentlyContinue
if (-not $devVm) {
    Write-Host "  [WARNING] VM '$vmName' not found in '$vmRg' — skipping VM backup protection checks (not counted as failures)." -ForegroundColor Yellow
} else {
    $vmItems = if ($rsv) {
        Get-AzRecoveryServicesBackupItem -VaultId $rsv.ID -BackupManagementType AzureVM -WorkloadType AzureVM -ErrorAction SilentlyContinue
    } else { $null }

    # The backup item's .FriendlyName is empty; the VM name lives in .Name
    # (e.g. 'VM;iaasvmcontainerv2;<rg>;dev-skycraft-swc-auth-vm').
    Invoke-Test "VM '$vmName' is registered for backup" {
        if (-not $rsv) { return $false }
        $item = $vmItems | Where-Object { $_.Name -like "*$vmName" }
        return ($null -ne $item)
    }

    Invoke-Test "VM backup policy is 'SkyCraft-Daily-Prod'" {
        if (-not $rsv) { return $false }
        $item = $vmItems | Where-Object { $_.Name -like "*$vmName" }
        return ($null -ne $item -and $item.ProtectionPolicyName -eq 'SkyCraft-Daily-Prod')
    }
}

# ============================================================================
# Backup Vault Tests
# ============================================================================
Write-Host ""
Write-Host "[Backup Vault]" -ForegroundColor Yellow

$bv = Get-AzDataProtectionBackupVault -ResourceGroupName $platformRg -VaultName $bvName -ErrorAction SilentlyContinue
# Raw ARM body — reliable for storageSettings, identity and tag casing (typed
# object exposes these as .StorageSetting/.IdentityPrincipalId/.Tag which vary by module version).
$bvArm = if ($bv) { Get-AzResource -ResourceId $bv.Id -ExpandProperties -ErrorAction SilentlyContinue } else { $null }

Invoke-Test "Backup Vault '$bvName' exists" {
    return ($null -ne $bv -and $bv.Name -eq $bvName)
}

Invoke-Test "Backup Vault location is swedencentral" {
    if (-not $bv) { return $false }
    return ($bv.Location -eq 'swedencentral')
}

Invoke-Test "Backup Vault storage type is LocallyRedundant" {
    if (-not $bvArm) { return $false }
    return ($bvArm.Properties.storageSettings[0].type -eq 'LocallyRedundant')
}

Invoke-Test "Backup Vault has system-assigned managed identity" {
    if (-not $bvArm) { return $false }
    # Identity is a top-level ARM block; fall back to the typed object if absent.
    $idType    = if ($bvArm.Identity) { "$($bvArm.Identity.Type)" }        else { "$($bv.IdentityType)" }
    $principal = if ($bvArm.Identity -and $bvArm.Identity.PrincipalId) { $bvArm.Identity.PrincipalId } else { $bv.IdentityPrincipalId }
    return (($idType -like '*SystemAssigned*') -and -not [string]::IsNullOrEmpty($principal))
}

Invoke-Test "Backup Vault tag 'Project' = 'SkyCraft'" {
    if (-not $bvArm) { return $false }
    return ($bvArm.Tags.Project -eq 'SkyCraft')
}

Invoke-Test "Backup Vault tag 'Environment' = 'Platform'" {
    if (-not $bvArm) { return $false }
    return ($bvArm.Tags.Environment -eq 'Platform')
}

Invoke-Test "Backup Vault tag 'CostCenter' = 'MSDN'" {
    if (-not $bvArm) { return $false }
    return ($bvArm.Tags.CostCenter -eq 'MSDN')
}

Invoke-Test "Backup Vault soft delete is off (lab-friction override, docs/bicep-standards.md section 4.5)" {
    if (-not $bvArm) { return $false }
    return ($bvArm.Properties.securitySettings.softDeleteSettings.state -eq 'Off')
}

# ============================================================================
# Blob Backup Policy Tests
# ============================================================================
Write-Host ""
Write-Host "[Blob Backup Policy]" -ForegroundColor Yellow

$blobPolicy = Get-AzDataProtectionBackupPolicy -ResourceGroupName $platformRg -VaultName $bvName -Name 'SkyCraft-Blob-Policy' -ErrorAction SilentlyContinue
# Raw ARM body — typed object property is ambiguously DatasourceType vs DatasourceTypes
# across module versions; ARM exposes the canonical 'datasourceTypes' array.
$blobPolicyArm = if ($bv) {
    Get-AzResource -ResourceId "$($bv.Id)/backupPolicies/SkyCraft-Blob-Policy" -ApiVersion '2023-01-01' -ExpandProperties -ErrorAction SilentlyContinue
} else { $null }

Invoke-Test "Policy 'SkyCraft-Blob-Policy' exists" {
    return ($null -ne $blobPolicy -and $blobPolicy.Name -eq 'SkyCraft-Blob-Policy')
}

Invoke-Test "Blob policy datasource type is AzureBlob" {
    if (-not $blobPolicyArm) { return $false }
    return ($blobPolicyArm.Properties.datasourceTypes -contains 'Microsoft.Storage/storageAccounts/blobServices')
}

Invoke-Test "Blob policy operational retention is 30 days" {
    if (-not $blobPolicyArm) { return $false }
    # Operational retention is an ISO-8601 duration (P30D) on a lifecycle deleteAfter.
    $found = $false
    foreach ($rule in @($blobPolicyArm.Properties.policyRules)) {
        foreach ($lc in @($rule.lifecycles)) {
            if ("$($lc.deleteAfter.duration)" -eq 'P30D') { $found = $true }
        }
    }
    return $found
}

# ============================================================================
# Blob Backup Instance Tests
# ============================================================================
Write-Host ""
Write-Host "[Blob Backup Instance]" -ForegroundColor Yellow

Invoke-Test "Blob backup instance exists for '$storageAccount'" {
    if (-not $bv) { return $false }
    $storageId = (Get-AzStorageAccount -ResourceGroupName $prodRg -Name $storageAccount -ErrorAction SilentlyContinue).Id
    if (-not $storageId) { return $false }
    $instances = Get-AzDataProtectionBackupInstance -ResourceGroupName $platformRg -VaultName $bvName -ErrorAction SilentlyContinue
    $instance = $instances | Where-Object { $_.Property.DataSourceInfo.ResourceId -eq $storageId }
    return ($null -ne $instance)
}

# ============================================================================
# Diagnostic Settings Tests
# ============================================================================
Write-Host ""
Write-Host "[Diagnostic Settings]" -ForegroundColor Yellow

Invoke-Test "RSV diagnostic setting 'rsv-backup-reports-diag' exists and targets LAW" {
    if (-not $rsv) { return $false }
    # Diagnostic settings are extension resources — Get-AzDiagnosticSetting reads them
    # reliably (Get-AzResource on the sub-resource id returns null).
    $diag = Get-AzDiagnosticSetting -ResourceId $rsv.ID -Name 'rsv-backup-reports-diag' -ErrorAction SilentlyContinue
    return ($null -ne $diag -and $diag.WorkspaceId -like "*/platform-skycraft-swc-law")
}

Invoke-Test "BV diagnostic setting 'bv-backup-reports-diag' exists and targets LAW" {
    if (-not $bv) { return $false }
    $diag = Get-AzDiagnosticSetting -ResourceId $bv.Id -Name 'bv-backup-reports-diag' -ErrorAction SilentlyContinue
    return ($null -ne $diag -and $diag.WorkspaceId -like "*/platform-skycraft-swc-law")
}

# ============================================================================
# Summary
# ============================================================================
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Test Results Summary" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Passed: $passCount" -ForegroundColor Green
if ($failCount -gt 0) {
    Write-Host "  Failed: $failCount" -ForegroundColor Red
} else {
    Write-Host "  Failed: $failCount" -ForegroundColor Gray
}
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Note: Azure Site Recovery (ASR) replication and test failover" -ForegroundColor Gray
Write-Host "  must be verified manually in the Azure Portal (Steps 5.2.6-5.2.7)." -ForegroundColor Gray
Write-Host ""

exit $failCount
