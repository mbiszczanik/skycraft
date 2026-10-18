<#
.SYNOPSIS
    Validates Lab 4.3 Deployment
.DESCRIPTION
    Checks the state Lab 4.3 leaves on the storage account of the selected environment, whichever
    path built it: the Portal steps, the guide's Az PowerShell blocks or the Bicep (issue #362).

      - The storage account exists, is in the Succeeded provisioning state (#371) and has the
        expected redundancy.
      - File share soft delete is on with at least 14 days of retention.
      - Exactly the two lab shares exist: a missing share and an unexpected share both fail. Each
        has its quota and the Hot access tier. A tier the API leaves unset is read as
        TransactionOptimized, the Azure default for a pay-as-you-go share and the default on the
        Portal wizard's Basics tab (docs/powershell-standards.md section 4, rule 7).
      - No Recovery Services vault in the subscription protects a file share of the account. The
        Portal's new share wizard turns Azure Backup on by default (#360); the guide has the
        learner untick it, and the Az PowerShell and Bicep paths create no backup. The vaults are
        found by type with Get-AzResource, which lists them whether or not the
        Microsoft.RecoveryServices provider is registered, and each vault's Azure Files items are
        matched to the account through the account they back up (#355: by relation, not by a
        name the Portal generates).

    A lookup that fails is a counted [FAIL] that prints its error, never a crash or a pass
    (docs/powershell-standards.md section 4, rule 7); a check that needs what it could not read
    is skipped, not passed. Every exit goes through Exit-Lab
    (tools/LabCommon.psm1): 1 when anything failed, 0 otherwise.

    The script does not check the directory, the file, the snapshot or a mount: those are data
    and client-side operations that the Bicep path does not create (the guide's Paths section).
.PARAMETER Environment
    The environment to validate (prod, dev, platform). Default: prod.
.EXAMPLE
    .\Test-Lab.ps1 -Environment prod
.NOTES
    Project: SkyCraft
    Author: SkyCraft
    Version: 3.0.0
    Date: 2026-10-18
    Issues: #355, #360, #362, #371
#>

#Requires -Version 7.0
#Requires -Modules Az.Accounts, Az.Resources, Az.Storage, Az.RecoveryServices

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [ValidateSet('prod', 'dev', 'platform')]
    [string]$Environment = 'prod'
)

$ErrorActionPreference = 'Stop'
# Exit-Lab ends the script with exit code 0 or 1 and leaves an interactive session open (#257).
Import-Module (Join-Path $PSScriptRoot '../../../tools/LabCommon.psm1') -Force -Verbose:$false
$script:failCount = 0

$resourceGroupName  = "$Environment-skycraft-swc-rg"
$storageAccountName = "${Environment}skycraftswcsa"
$expectedSku        = ($Environment -eq 'prod' -or $Environment -eq 'platform') ? 'Standard_GRS' : 'Standard_LRS'

# The two shares the lab creates, with their quota in GiB. Both use the Hot access tier.
$expectedShares = [ordered]@{
    'skycraft-config' = 100
    'skycraft-shared' = 500
}
$expectedTier = 'Hot'
# Azure's default for a share in a StorageV2 (pay-as-you-go) account, and the Portal's.
$defaultTier = 'TransactionOptimized'

# Prints one check as [PASS] or [FAIL] and counts the failures. The parameter is -Check, not
# -Name: tests/Guide-Automation-Names.Tests.ps1 reads every literal after -Name as a resource name.
function Write-LabCheck {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Check,

        [Parameter(Mandatory = $true)]
        [bool]$Passed,

        [Parameter(Mandatory = $false)]
        [string]$Detail = ''
    )

    if ($Passed) {
        Write-Host "  [PASS] $Check" -ForegroundColor Green
    }
    else {
        $script:failCount++
        $suffix = if ($Detail) { " - $Detail" } else { '' }
        Write-Host "  [FAIL] $Check$suffix" -ForegroundColor Red
    }
}

Write-Host "=== Lab 4.3: Validating Azure Files Environment ===" -ForegroundColor Cyan

# 1. Verify Connection
if (-not (Get-AzContext)) {
    Write-Host " [ERROR] Not logged in. Please run Connect-AzAccount." -ForegroundColor Red; Exit-Lab -FailureCount 1
}

# 2. Storage account: without it nothing else can be checked.
Write-Host "Checking Storage Account '$storageAccountName'..." -ForegroundColor Yellow
$sa = $null
try {
    $sa = Get-AzStorageAccount -ResourceGroupName $resourceGroupName -Name $storageAccountName -ErrorAction Stop
}
catch {
    Write-LabCheck -Check "Storage account '$storageAccountName' readable" -Passed $false -Detail "$_"
    Write-Host "`nValidation Complete. Failures: $script:failCount" -ForegroundColor Red
    Exit-Lab -FailureCount $script:failCount
}

Write-LabCheck -Check 'Provisioning state is Succeeded' -Passed ($sa.ProvisioningState -eq 'Succeeded') `
    -Detail "Actual: $($sa.ProvisioningState)"
Write-LabCheck -Check "Redundancy is $expectedSku" -Passed ($sa.Sku.Name -eq $expectedSku) `
    -Detail "Actual: $($sa.Sku.Name)"

# 3. File share soft delete (Step 4.3.3), read through the management plane: PSStorageAccount
#    has no file service properties.
try {
    $fileServiceProps = Get-AzStorageFileServiceProperty -ResourceGroupName $resourceGroupName `
        -StorageAccountName $storageAccountName -ErrorAction Stop
    $softDelete = $fileServiceProps.ShareDeleteRetentionPolicy
    $softDeleteOk = [bool]($softDelete -and $softDelete.Enabled -and $softDelete.Days -ge 14)
    Write-LabCheck -Check 'File share soft delete enabled for at least 14 days' -Passed $softDeleteOk `
        -Detail "Actual: Enabled $($softDelete.Enabled), Days $($softDelete.Days)"
}
catch {
    Write-LabCheck -Check 'File service properties readable' -Passed $false -Detail "$_"
}

# 4. File shares (Steps 4.3.1 and 4.3.2). Enumerated rather than probed one name at a time: a
#    hard-coded probe list can only catch a missing share, never a stray one left behind by a
#    hand-made experiment (#99). The listing leaves out soft-deleted shares and snapshots.
Write-Host "Checking File Shares..." -ForegroundColor Yellow
try {
    $actualShares = @(Get-AzRmStorageShare -ResourceGroupName $resourceGroupName `
            -StorageAccountName $storageAccountName -ErrorAction Stop)

    foreach ($name in $expectedShares.Keys) {
        $share = $actualShares | Where-Object { $_.Name -eq $name } | Select-Object -First 1
        if (-not $share) {
            Write-LabCheck -Check "File share '$name' exists" -Passed $false -Detail 'not found'
            continue
        }
        Write-LabCheck -Check "File share '$name' exists" -Passed $true

        Write-LabCheck -Check "File share '$name' quota is $($expectedShares[$name]) GiB" `
            -Passed ($share.QuotaGiB -eq $expectedShares[$name]) -Detail "Actual: $($share.QuotaGiB) GiB"

        $tier = if ($share.AccessTier) { [string]$share.AccessTier } else { $defaultTier }
        $tierHint = if ($tier -ne $expectedTier) {
            " - the Basics tab's Access tier defaults to Transaction optimized; change it on the share's Overview with Change tier (Troubleshooting, Issue 7)"
        } else { '' }
        Write-LabCheck -Check "File share '$name' access tier is $expectedTier" -Passed ($tier -eq $expectedTier) `
            -Detail "Actual: $tier$tierHint"
    }

    $unexpected = @($actualShares | Where-Object { -not $expectedShares.Contains($_.Name) })
    foreach ($share in $unexpected) {
        Write-LabCheck -Check "No file share other than $($expectedShares.Keys -join ', ')" -Passed $false `
            -Detail "Unexpected: '$($share.Name)'"
    }
}
catch {
    Write-LabCheck -Check 'File shares listable' -Passed $false -Detail "$_"
}

# 5. Azure Backup (#360). Lab 4.3 creates no backup on any path; the Portal wizard's Backup tab
#    does unless the learner unticks Enable backup. An item belongs to this account when its
#    source resource is the account, or when its container is the account
#    ('storage;<resource group>;<account>').
Write-Host "Checking Azure Backup protection of the file shares..." -ForegroundColor Yellow
try {
    $vaults = @(Get-AzResource -ResourceType 'Microsoft.RecoveryServices/vaults' -ErrorAction Stop)
    $containerSuffix = ";$resourceGroupName;$storageAccountName"
    $protected = [System.Collections.Generic.List[string]]::new()
    $unreadableVaults = 0

    foreach ($vault in $vaults) {
        try {
            $items = @(Get-AzRecoveryServicesBackupItem -BackupManagementType AzureStorage -WorkloadType AzureFiles `
                    -VaultId $vault.ResourceId -ErrorAction Stop)
        }
        catch {
            Write-LabCheck -Check "Azure Files backup items of vault '$($vault.Name)' readable" -Passed $false -Detail "$_"
            $unreadableVaults++
            continue
        }

        foreach ($item in $items) {
            $ofThisAccount = ($item.SourceResourceId -and ([string]$item.SourceResourceId -ieq [string]$sa.Id)) -or
                ([string]$item.ContainerName).EndsWith($containerSuffix, [System.StringComparison]::OrdinalIgnoreCase)
            if ($ofThisAccount) {
                $shareName = @($item.FriendlyName, $item.Name) | Where-Object { $_ } | Select-Object -First 1
                $protected.Add("'$shareName' in vault '$($vault.Name)'")
            }
        }
    }

    # A vault that could not be read may protect a share: it is already a counted [FAIL] above, and
    # the summary must not then claim a [PASS] for what it could not see. A protection found in
    # another vault still fails the summary.
    $backupCheck = 'No Azure Backup protects a file share of the account (backups are Lab 5.2)'
    if ($protected.Count -gt 0) {
        Write-LabCheck -Check $backupCheck -Passed $false `
            -Detail "Protected: $($protected -join ', '). Enable backup was left ticked on the wizard's Backup tab; stop the backup as in Troubleshooting, Issue 6"
    }
    elseif ($unreadableVaults -eq 0) {
        Write-LabCheck -Check $backupCheck -Passed $true
    }
    else {
        Write-Host "  [SKIP] $backupCheck - $unreadableVaults vault(s) could not be read (counted above)" -ForegroundColor Yellow
    }
}
catch {
    Write-LabCheck -Check 'Recovery Services vaults listable' -Passed $false -Detail "$_"
}

Write-Host "`nValidation Complete. Failures: $script:failCount" -ForegroundColor $(if ($script:failCount -eq 0) { 'Cyan' } else { 'Red' })
Exit-Lab -FailureCount $script:failCount
