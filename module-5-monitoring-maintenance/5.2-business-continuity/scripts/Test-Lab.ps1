<#
.SYNOPSIS
    Validates Lab 5.2 Business Continuity & Disaster Recovery deployment.

.DESCRIPTION
    Verifies all Lab 5.2 BCDR resources are deployed and correctly configured:
    - Recovery Services Vault (platform-skycraft-swc-rsv): exists, LRS, required tags
    - VM Backup Policy (SkyCraft-Daily-Prod): daily schedule, 30-day retention
    - VM backup protection enabled on prod-skycraft-swc-auth-vm
    - Backup Vault (platform-skycraft-swc-bv): exists, LRS, system-assigned identity
    - Blob Backup Policy (SkyCraft-Blob-Policy): correct datasource type
    - Blob backup instance configured for prodskycraftswcsa

    Note: Azure Site Recovery replication status must be verified manually
    in the Azure Portal (the ASR replication flow is portal-only per Step 5.2.8).

.EXAMPLE
    .\Test-Lab.ps1

.NOTES
    Project: SkyCraft
    Lab: 5.2 - Business Continuity & Disaster Recovery
    Version: 1.0.0
    Date: 2026-04-06
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$platformRg     = 'platform-skycraft-swc-rg'
$prodRg         = 'prod-skycraft-swc-rg'
$rsvName        = 'platform-skycraft-swc-rsv'
$bvName         = 'platform-skycraft-swc-bv'
$vmName         = 'prod-skycraft-swc-auth-vm'
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

$account = az account show --output json 2>$null | ConvertFrom-Json
if (-not $account) {
    Write-Host "  [ERROR] Not logged into Azure CLI. Run 'az login' first." -ForegroundColor Red
    exit 1
}
Write-Host "  Account: $($account.user.name)" -ForegroundColor Gray

az config set extension.use_dynamic_install=yes_without_prompt --only-show-errors | Out-Null
Write-Host ""

# ============================================================================
# Recovery Services Vault Tests
# ============================================================================
Write-Host "[Recovery Services Vault]" -ForegroundColor Yellow

Invoke-Test "RSV '$rsvName' exists" {
    $rsv = az backup vault show `
        --resource-group $platformRg `
        --name $rsvName `
        --output json 2>$null | ConvertFrom-Json
    return ($null -ne $rsv -and $rsv.name -eq $rsvName)
}

Invoke-Test "RSV location is swedencentral" {
    $rsv = az backup vault show `
        --resource-group $platformRg `
        --name $rsvName `
        --output json 2>$null | ConvertFrom-Json
    return ($rsv.location -eq 'swedencentral')
}

Invoke-Test "RSV storage redundancy is LocallyRedundant" {
    $props = az backup vault backup-properties show `
        --resource-group $platformRg `
        --name $rsvName `
        --output json 2>$null | ConvertFrom-Json
    return ($props.properties.storageModelType -eq 'LocallyRedundant')
}

Invoke-Test "RSV tag 'Project' = 'SkyCraft'" {
    $rsv = az backup vault show `
        --resource-group $platformRg `
        --name $rsvName `
        --output json 2>$null | ConvertFrom-Json
    return ($rsv.tags.Project -eq 'SkyCraft')
}

Invoke-Test "RSV tag 'Environment' = 'Platform'" {
    $rsv = az backup vault show `
        --resource-group $platformRg `
        --name $rsvName `
        --output json 2>$null | ConvertFrom-Json
    return ($rsv.tags.Environment -eq 'Platform')
}

Invoke-Test "RSV tag 'CostCenter' = 'MSDN'" {
    $rsv = az backup vault show `
        --resource-group $platformRg `
        --name $rsvName `
        --output json 2>$null | ConvertFrom-Json
    return ($rsv.tags.CostCenter -eq 'MSDN')
}

Invoke-Test "RSV soft delete is enabled" {
    $props = az backup vault backup-properties show `
        --resource-group $platformRg `
        --name $rsvName `
        --output json 2>$null | ConvertFrom-Json
    return ($props.properties.softDeleteFeatureState -eq 'Enabled')
}

# ============================================================================
# VM Backup Policy Tests
# ============================================================================
Write-Host ""
Write-Host "[VM Backup Policy]" -ForegroundColor Yellow

Invoke-Test "Policy 'SkyCraft-Daily-Prod' exists" {
    $policy = az backup policy show `
        --resource-group $platformRg `
        --vault-name $rsvName `
        --name 'SkyCraft-Daily-Prod' `
        --output json 2>$null | ConvertFrom-Json
    return ($null -ne $policy -and $policy.name -eq 'SkyCraft-Daily-Prod')
}

Invoke-Test "Policy backup frequency is Daily" {
    $policy = az backup policy show `
        --resource-group $platformRg `
        --vault-name $rsvName `
        --name 'SkyCraft-Daily-Prod' `
        --output json 2>$null | ConvertFrom-Json
    $freq = $policy.properties.schedulePolicy.scheduleRunFrequency
    return ($freq -eq 'Daily')
}

Invoke-Test "Policy daily retention is 30 days" {
    $policy = az backup policy show `
        --resource-group $platformRg `
        --vault-name $rsvName `
        --name 'SkyCraft-Daily-Prod' `
        --output json 2>$null | ConvertFrom-Json
    $count = $policy.properties.retentionPolicy.dailySchedule.retentionDuration.count
    return ($count -eq 30)
}

Invoke-Test "Policy instant restore retention is 2 days" {
    $policy = az backup policy show `
        --resource-group $platformRg `
        --vault-name $rsvName `
        --name 'SkyCraft-Daily-Prod' `
        --output json 2>$null | ConvertFrom-Json
    return ($policy.properties.instantRpRetentionRangeInDays -eq 2)
}

Invoke-Test "Policy schedule time contains 02:00 UTC" {
    $policy = az backup policy show `
        --resource-group $platformRg `
        --vault-name $rsvName `
        --name 'SkyCraft-Daily-Prod' `
        --output json 2>$null | ConvertFrom-Json
    $times = $policy.properties.schedulePolicy.scheduleRunTimes
    # Normalize each stored time to UTC and compare — handles both +00:00 and offset formats
    return ($null -ne ($times | Where-Object {
        ([datetime]::Parse($_, $null, [System.Globalization.DateTimeStyles]::RoundtripKind)).ToUniversalTime().ToString('HH:mm') -eq '02:00'
    }))
}

# ============================================================================
# VM Backup Protection Tests
# ============================================================================
Write-Host ""
Write-Host "[VM Backup Protection]" -ForegroundColor Yellow

Invoke-Test "VM '$vmName' is registered for backup" {
    $items = az backup item list `
        --resource-group $platformRg `
        --vault-name $rsvName `
        --backup-management-type AzureIaasVM `
        --output json 2>$null | ConvertFrom-Json
    $item = $items | Where-Object { $_.properties.friendlyName -eq $vmName }
    return ($null -ne $item)
}

Invoke-Test "VM backup policy is 'SkyCraft-Daily-Prod'" {
    $items = az backup item list `
        --resource-group $platformRg `
        --vault-name $rsvName `
        --backup-management-type AzureIaasVM `
        --output json 2>$null | ConvertFrom-Json
    $item = $items | Where-Object { $_.properties.friendlyName -eq $vmName }
    return ($null -ne $item -and $item.properties.policyName -eq 'SkyCraft-Daily-Prod')
}

# ============================================================================
# Backup Vault Tests
# ============================================================================
Write-Host ""
Write-Host "[Backup Vault]" -ForegroundColor Yellow

Invoke-Test "Backup Vault '$bvName' exists" {
    $bv = az dataprotection backup-vault show `
        --resource-group $platformRg `
        --vault-name $bvName `
        --output json 2>$null | ConvertFrom-Json
    return ($null -ne $bv -and $bv.name -eq $bvName)
}

Invoke-Test "Backup Vault location is swedencentral" {
    $bv = az dataprotection backup-vault show `
        --resource-group $platformRg `
        --vault-name $bvName `
        --output json 2>$null | ConvertFrom-Json
    return ($bv.location -eq 'swedencentral')
}

Invoke-Test "Backup Vault storage type is LocallyRedundant" {
    $bv = az dataprotection backup-vault show `
        --resource-group $platformRg `
        --vault-name $bvName `
        --output json 2>$null | ConvertFrom-Json
    $storageType = $bv.properties.storageSettings[0].type
    return ($storageType -eq 'LocallyRedundant')
}

Invoke-Test "Backup Vault has system-assigned managed identity" {
    $bv = az dataprotection backup-vault show `
        --resource-group $platformRg `
        --vault-name $bvName `
        --output json 2>$null | ConvertFrom-Json
    return ($bv.identity.type -eq 'SystemAssigned' -and -not [string]::IsNullOrEmpty($bv.identity.principalId))
}

Invoke-Test "Backup Vault tag 'Project' = 'SkyCraft'" {
    $bv = az dataprotection backup-vault show `
        --resource-group $platformRg `
        --vault-name $bvName `
        --output json 2>$null | ConvertFrom-Json
    return ($bv.tags.Project -eq 'SkyCraft')
}

Invoke-Test "Backup Vault tag 'Environment' = 'Platform'" {
    $bv = az dataprotection backup-vault show `
        --resource-group $platformRg `
        --vault-name $bvName `
        --output json 2>$null | ConvertFrom-Json
    return ($bv.tags.Environment -eq 'Platform')
}

Invoke-Test "Backup Vault tag 'CostCenter' = 'MSDN'" {
    $bv = az dataprotection backup-vault show `
        --resource-group $platformRg `
        --vault-name $bvName `
        --output json 2>$null | ConvertFrom-Json
    return ($bv.tags.CostCenter -eq 'MSDN')
}

# ============================================================================
# Blob Backup Policy Tests
# ============================================================================
Write-Host ""
Write-Host "[Blob Backup Policy]" -ForegroundColor Yellow

Invoke-Test "Policy 'SkyCraft-Blob-Policy' exists" {
    $policy = az dataprotection backup-policy show `
        --resource-group $platformRg `
        --vault-name $bvName `
        --name 'SkyCraft-Blob-Policy' `
        --output json 2>$null | ConvertFrom-Json
    return ($null -ne $policy -and $policy.name -eq 'SkyCraft-Blob-Policy')
}

Invoke-Test "Blob policy datasource type is AzureBlob" {
    $policy = az dataprotection backup-policy show `
        --resource-group $platformRg `
        --vault-name $bvName `
        --name 'SkyCraft-Blob-Policy' `
        --output json 2>$null | ConvertFrom-Json
    return ($policy.properties.datasourceTypes -contains 'Microsoft.Storage/storageAccounts/blobServices')
}

# ============================================================================
# Blob Backup Instance Tests
# ============================================================================
Write-Host ""
Write-Host "[Blob Backup Instance]" -ForegroundColor Yellow

Invoke-Test "Blob backup instance exists for '$storageAccount'" {
    $storageId = az storage account show `
        --name $storageAccount `
        --resource-group $prodRg `
        --query id --output tsv 2>$null
    $instances = az dataprotection backup-instance list `
        --resource-group $platformRg `
        --vault-name $bvName `
        --output json 2>$null | ConvertFrom-Json
    $instance = $instances | Where-Object { $_.properties.dataSourceInfo.resourceId -eq $storageId }
    return ($null -ne $instance)
}

# ============================================================================
# Diagnostic Settings Tests
# ============================================================================
Write-Host ""
Write-Host "[Diagnostic Settings]" -ForegroundColor Yellow

Invoke-Test "RSV diagnostic setting 'rsv-backup-reports-diag' exists and targets LAW" {
    $rsvId = az backup vault show `
        --resource-group $platformRg `
        --name $rsvName `
        --query id --output tsv 2>$null
    $diag = az monitor diagnostic-settings show `
        --name 'rsv-backup-reports-diag' `
        --resource $rsvId `
        --output json 2>$null | ConvertFrom-Json
    # az monitor diagnostic-settings returns a flat object (workspaceId at root, not under .properties)
    return ($null -ne $diag -and $diag.workspaceId -like "*/platform-skycraft-swc-law")
}

Invoke-Test "BV diagnostic setting 'bv-backup-reports-diag' exists and targets LAW" {
    $bvId = az dataprotection backup-vault show `
        --resource-group $platformRg `
        --vault-name $bvName `
        --query id --output tsv 2>$null
    $diag = az monitor diagnostic-settings show `
        --name 'bv-backup-reports-diag' `
        --resource $bvId `
        --output json 2>$null | ConvertFrom-Json
    return ($null -ne $diag -and $diag.workspaceId -like "*/platform-skycraft-swc-law")
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
Write-Host "  must be verified manually in the Azure Portal (Step 5.2.9)." -ForegroundColor Gray
Write-Host ""

exit $failCount
