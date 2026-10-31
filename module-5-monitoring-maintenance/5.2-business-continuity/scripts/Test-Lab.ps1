<#
.SYNOPSIS
    Validates Lab 5.2 Business Continuity & Disaster Recovery deployment.

.DESCRIPTION
    Verifies all Lab 5.2 BCDR resources are deployed and correctly configured:
    - Recovery Services Vault (platform-skycraft-swc-rsv): exists, LRS, required tags
    - VM Backup Policy (SkyCraft-Daily-Prod): daily schedule, 30-day retention, instant-restore
      snapshots in platform-skycraft-swc-rpc1-rg
    - Snapshot resource group (platform-skycraft-swc-rpc1-rg): exists, tagged, not locked
    - VM backup protection enabled on dev-skycraft-swc-auth-vm and dev-skycraft-swc-world-vm
      (each skipped if the VM is absent), and each one's latest backup job did not fail - configuration alone stayed green while every
      backup was refused by policy (issue #184)
    - The Backup Management Service app holds Key Vault Administrator on dev-skycraft-swc-kv,
      the key vault of the VM's Azure Disk Encryption (issue #368; checked with the VM).
      Finding the app's service principal needs Microsoft Graph; a lookup that fails is a FAIL
      that names the sign-in
    - Backup Vault (platform-skycraft-swc-bv): exists, LRS, system-assigned identity, soft delete
      Off. A vault created in the Portal is AlwaysOn, which cannot be undone, so the lab creates
      it with Az PowerShell or the Bicep (decision on issue #366); the check says so when it
      fails, and accepts On/AlwaysOn once $backupVaultSoftDeleteAccepted is widened for the GA
      of secure by default in the region (issue #376)
    - Blob Backup Policy (SkyCraft-Blob-Policy): AzureBlob datasource, 30-day retention, no
      vaulted backup rule (a Portal-made policy always has one, and it is billed, issue #306)
    - Blob backup instance configured for prodskycraftswcsa, protection configured and provisioned
    - Alert processing rule (skycraft-backup-critical-apr): enabled, scoped to the Recovery
      Services vault, Rule type Apply action group with skycraft-ops-ag, Critical (Sev0) alerts

    Property reads with uncertain typed-object names (storage type, identity,
    soft-delete state, datasource type, retention) use Get-AzResource against the
    raw ARM body for reliability.

    - Azure Site Recovery (Step 5.2.6, issue #366), checked with the world VM: the target group
      platform-skycraft-neu-asr-rg exists in North Europe with the four SkyCraft tags (Lab 1.3
      denies what Site Recovery creates in an untagged group), holds a Recovery Services vault,
      and that vault has a replication item for dev-skycraft-swc-world-vm that reads Protected
      with health Normal. A lookup that fails is a FAIL, never a skip. The test failover of
      Step 5.2.7 is optional (a subscription may be unable to start the failover VM): the lab's
      end state is the Protected replication, so no check reads or requires a test failover.

.PARAMETER ProdSaName
    Production storage account name. Default: prodskycraftswcsa. Pass the name given to Lab 4.1's
    Deploy-Bicep.ps1.
.PARAMETER KeyVaultName
    Name of Lab 3.2's key vault in dev-skycraft-swc-rg, when it was created under another name
    (key vault names are globally unique). Default: dev-skycraft-swc-kv
.PARAMETER ProtectionTimeoutSeconds
    How long the blob backup instance check keeps polling while the instance is still
    configuring (protection state ConfiguringProtection, or provisioning state Creating or
    Updating), before it fails with the state named. New-LabBlobBackup.ps1 returns before the
    service finishes configuring protection, so a test right after it sees that state (#371).
    A terminal state such as Failed or ProtectionError fails at once. Default 300.

.PARAMETER ProtectionPollSeconds
    Seconds between polls of the instance while it is configuring. Default 15.

.EXAMPLE
    .\Test-Lab.ps1

.EXAMPLE
    .\Test-Lab.ps1 -KeyVaultName dev-skycraft-swc-kv-ab

.NOTES
    Project: SkyCraft
    Lab: 5.2 - Business Continuity & Disaster Recovery
    Version: 1.3.0
    Date: 2026-10-29
#>

#Requires -Version 7.0
#Requires -Modules Az.Accounts, Az.Resources, Az.RecoveryServices, Az.DataProtection, Az.Storage, Az.Compute

[CmdletBinding()]
param(
    [Parameter()]
    [ValidatePattern('^[a-z0-9]{3,24}$')]
    [string]$ProdSaName = 'prodskycraftswcsa',

    [ValidateLength(3, 24)]
    [string]$KeyVaultName = 'dev-skycraft-swc-kv',

    [Parameter()]
    [ValidateRange(0, 3600)]
    [int]$ProtectionTimeoutSeconds = 300,

    [Parameter()]
    [ValidateRange(0, 300)]
    [int]$ProtectionPollSeconds = 15
)

$ErrorActionPreference = 'Stop'
# Exit-Lab ends the script with exit code 0 or 1 and leaves an interactive session open (#257).
Import-Module (Join-Path $PSScriptRoot '../../../tools/LabCommon.psm1') -Force -Verbose:$false

$platformRg     = 'platform-skycraft-swc-rg'
$prodRg         = 'prod-skycraft-swc-rg'
$rsvName        = 'platform-skycraft-swc-rsv'
$bvName         = 'platform-skycraft-swc-bv'
# The auth VM is ADE-encrypted (Lab 3.2); the world VM is the one Step 5.2.10 restores files from.
$encryptedVmName = 'dev-skycraft-swc-auth-vm'
$backupVmNames  = @($encryptedVmName, 'dev-skycraft-swc-world-vm')
$vmRg           = 'dev-skycraft-swc-rg'
$storageAccount = $ProdSaName
$aprName        = 'skycraft-backup-critical-apr'
# Azure Site Recovery target (Step 5.2.6): main.bicep creates the group and vault, or the learner does.
$asrVm          = 'dev-skycraft-swc-world-vm'
$asrRgName      = 'platform-skycraft-neu-asr-rg'
$asrLocation    = 'northeurope'
$asrTags        = @('Project', 'Environment', 'CostCenter', 'Owner')
$actionGroupName = 'skycraft-ops-ag'
# Built-in ids, the same in every tenant: the Backup Management Service app and Key Vault Administrator.
$backupManagementServiceAppId = '262044b1-e2ce-469f-a196-69ab7ada62d3'
$keyVaultAdministratorRoleId  = '00482a5a-887f-4fb3-b363-3b7fe8e74483'
# Azure Backup names the snapshot group <prefix><n><suffix>; main.bicep creates n = 1.
$snapshotRgPrefix = 'platform-skycraft-swc-rpc'
$snapshotRgSuffix = '-rg'
$snapshotRgName   = "${snapshotRgPrefix}1${snapshotRgSuffix}"
# Backup vault soft delete states the lab accepts (#355, decision on #366). 'Off' while the option
# exists in Sweden Central: secure by default is in preview for Backup vaults there, and Microsoft
# Learn says the option to turn soft delete off may go when it reaches GA. Once it does, add 'On'
# and 'AlwaysOn' here (tracked in #376); the Recovery Services vault check below already expects
# AlwaysON.
$backupVaultSoftDeleteAccepted = @('Off')

# Explicit api-versions for the raw ARM reads (#452); Sweden Central serves both.
$vaultApiVersion       = '2024-04-01'
$backupVaultApiVersion = '2024-04-01'

$passCount = 0
$failCount = 0

# Whether a lookup's error says the object does not exist rather than that the lookup failed.
# Same rule as Test-LabNotFoundError in this lab's Remove-LabResource.ps1.
function Test-LabNotFoundError {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [System.Management.Automation.ErrorRecord]$ErrorRecord
    )

    $evidence = [System.Collections.Generic.List[string]]::new()
    $evidence.Add([string]$ErrorRecord)
    $evidence.Add([string]$ErrorRecord.FullyQualifiedErrorId)
    $status404 = $false
    for ($exception = $ErrorRecord.Exception; $exception; $exception = $exception.InnerException) {
        $evidence.Add([string]$exception.Message)
        foreach ($code in @($exception.Body.Code, $exception.Body.Error.Code, $exception.ErrorCode)) {
            if ($code) { $evidence.Add([string]$code) }
        }
        foreach ($status in @($exception.Response.StatusCode, $exception.ResponseStatusCode, $exception.Status)) {
            if ("$status" -in @('404', 'NotFound')) { $status404 = $true }
        }
    }
    $text = $evidence -join "`n"

    if ($text -match 'SubscriptionNotFound|subscription .{0,80}(could not be|was not) found') { return $false }
    if ($status404) { return $true }
    return $text -match '\bResource(Group)?NotFound\b|was not found|Resource group .{0,100}could not be found|invalid status code ''NotFound''|\b404 \(Not Found\)'
}

# Reads one resource by id at an explicit api-version (#452: without one ARM uses the newest version
# the provider lists, which a region may not serve yet). A missing resource is $null; any other
# error throws, so the check that asked fails with the error instead of reading the resource as missing.
function Get-LabArmResource {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ResourceId,

        [Parameter(Mandatory = $true)]
        [string]$ApiVersion,

        [switch]$ExpandProperties
    )

    try {
        if ($ExpandProperties) {
            return Get-AzResource -ResourceId $ResourceId -ApiVersion $ApiVersion -ExpandProperties -ErrorAction Stop
        }
        return Get-AzResource -ResourceId $ResourceId -ApiVersion $ApiVersion -ErrorAction Stop
    }
    catch {
        if (Test-LabNotFoundError -ErrorRecord $_) { return $null }
        throw
    }
}

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
    Exit-Lab -FailureCount 1
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
# A lookup error other than not found is kept and thrown by the checks that read the tags.
$rsvTags = $null
$rsvTagsError = $null
if ($rsv) {
    try { $rsvTags = (Get-LabArmResource -ResourceId $rsv.ID -ApiVersion $vaultApiVersion).Tags } catch { $rsvTagsError = $_ }
}

Invoke-Test "RSV tag 'Project' = 'SkyCraft'" {
    if ($rsvTagsError) { throw $rsvTagsError }
    return ($null -ne $rsvTags -and $rsvTags.Project -eq 'SkyCraft')
}

Invoke-Test "RSV tag 'Environment' = 'Platform'" {
    if ($rsvTagsError) { throw $rsvTagsError }
    return ($null -ne $rsvTags -and $rsvTags.Environment -eq 'Platform')
}

Invoke-Test "RSV tag 'CostCenter' = 'MSDN'" {
    if ($rsvTagsError) { throw $rsvTagsError }
    return ($null -ne $rsvTags -and $rsvTags.CostCenter -eq 'MSDN')
}

Invoke-Test "RSV soft delete is AlwaysON (platform-enforced, docs/bicep-standards.md section 4.5)" {
    if (-not $rsv) { return $false }
    # Read soft-delete state from the raw ARM backupconfig sub-resource (reliable). Azure Backup
    # "secure by default" enforces AlwaysON on every new vault; the template sends no
    # softDeleteSettings at all, and no API version or tool can turn it off.
    $state = $null
    $cfg = Get-LabArmResource -ResourceId "$($rsv.ID)/backupconfig/vaultconfig" -ApiVersion '2023-06-01' -ExpandProperties
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
    $pol = Get-LabArmResource -ResourceId "$($rsv.ID)/backupPolicies/SkyCraft-Daily-Prod" -ApiVersion '2023-06-01' -ExpandProperties
    if ($pol -and $null -ne $pol.Properties.instantRpRetentionRangeInDays) {
        return ($pol.Properties.instantRpRetentionRangeInDays -eq 2)
    }
    return ($rsvPolicy.SnapshotRetentionInDays -eq 2)
}

Invoke-Test "Policy schedule time contains 02:00 UTC" {
    if (-not $rsvPolicy) { return $false }
    # The Enhanced policy (#113) returns a SimpleSchedulePolicyV2, which nests the run times under
    # DailySchedule; a Standard SimpleSchedulePolicy exposes them flat. Read whichever is populated.
    $schedule = $rsvPolicy.SchedulePolicy
    $times = @(if ($schedule.PSObject.Properties['DailySchedule'] -and $schedule.DailySchedule) {
            $schedule.DailySchedule.ScheduleRunTimes
        } else {
            $schedule.ScheduleRunTimes
        }) | Where-Object { $null -ne $_ }
    # ScheduleRunTimes are stored as UTC DateTime values — normalize and compare the time-of-day
    return ($null -ne ($times | Where-Object {
        ([datetime]::SpecifyKind([datetime]$_, [System.DateTimeKind]::Utc)).ToString('HH:mm') -eq '02:00'
    }))
}

Invoke-Test "Policy stores instant-restore snapshots in '$snapshotRgName'" {
    if (-not $rsvPolicy -or -not $rsv) { return $false }
    # Without a named group Azure Backup creates an untagged AzureBackupRG_* group, which Lab 1.3's
    # Require-Environment-Tag-RG denies (#184). Raw ARM first, typed properties as the fallback.
    $pol = Get-LabArmResource -ResourceId "$($rsv.ID)/backupPolicies/SkyCraft-Daily-Prod" -ApiVersion '2023-06-01' -ExpandProperties
    $details = if ($pol) { $pol.Properties.instantRPDetails } else { $null }
    if ($details -and $details.azureBackupRGNamePrefix) {
        return ($details.azureBackupRGNamePrefix -eq $snapshotRgPrefix -and "$($details.azureBackupRGNameSuffix)" -eq $snapshotRgSuffix)
    }
    return ($rsvPolicy.AzureBackupRGName -eq $snapshotRgPrefix -and "$($rsvPolicy.AzureBackupRGNameSuffix)" -eq $snapshotRgSuffix)
}

# ============================================================================
# Snapshot Resource Group Tests
# ============================================================================
Write-Host ""
Write-Host "[Snapshot Resource Group]" -ForegroundColor Yellow

$snapshotRg = Get-AzResourceGroup -Name $snapshotRgName -ErrorAction SilentlyContinue

Invoke-Test "Resource group '$snapshotRgName' exists" {
    return ($null -ne $snapshotRg)
}

Invoke-Test "Snapshot RG tag 'Environment' = 'Platform' (Lab 1.3 denies an RG without it)" {
    return ($null -ne $snapshotRg -and $snapshotRg.Tags.Environment -eq 'Platform')
}

Invoke-Test "Snapshot RG tag 'Project' = 'SkyCraft'" {
    return ($null -ne $snapshotRg -and $snapshotRg.Tags.Project -eq 'SkyCraft')
}

Invoke-Test "Snapshot RG has no resource lock (a lock blocks restore-point cleanup)" {
    if (-not $snapshotRg) { return $false }
    return (@(Get-AzResourceLock -ResourceGroupName $snapshotRgName -ErrorAction SilentlyContinue).Count -eq 0)
}

# ============================================================================
# VM Backup Protection Tests
# ============================================================================
Write-Host ""
Write-Host "[VM Backup Protection]" -ForegroundColor Yellow

$vmItems = if ($rsv) {
    Get-AzRecoveryServicesBackupItem -VaultId $rsv.ID -BackupManagementType AzureVM -WorkloadType AzureVM -ErrorAction SilentlyContinue
} else { $null }

# The cycle protects the dev VMs only. A VM never deployed (Lab 3.2 skipped) is a WARN and a skip,
# not a failure.
foreach ($vmName in $backupVmNames) {
    $devVm = Get-AzVM -Name $vmName -ResourceGroupName $vmRg -ErrorAction SilentlyContinue
    if (-not $devVm) {
        Write-Host "  [WARNING] VM '$vmName' not found in '$vmRg' - skipping its backup checks (not counted as failures)." -ForegroundColor Yellow
        continue
    }
    # The backup item's .FriendlyName is empty; the VM name lives in .Name
    # (e.g. 'VM;iaasvmcontainerv2;<rg>;dev-skycraft-swc-auth-vm').
    Invoke-Test "VM '$vmName' is registered for backup" {
        if (-not $rsv) { return $false }
        $item = $vmItems | Where-Object { $_.Name -like "*$vmName" }
        return ($null -ne $item)
    }

    Invoke-Test "VM '$vmName' backup policy is 'SkyCraft-Daily-Prod'" {
        if (-not $rsv) { return $false }
        $item = $vmItems | Where-Object { $_.Name -like "*$vmName" }
        return ($null -ne $item -and $item.ProtectionPolicyName -eq 'SkyCraft-Daily-Prod')
    }

    # The checks above are configuration. This one is the outcome: after Lab 1.3 every job failed
    # in seconds while the lab stayed green (#184). InProgress passes - Deploy-Bicep.ps1 triggers
    # the backup just before this runs, and the vault transfer takes far longer than the test.
    $lastJob = if ($rsv) {
        Get-AzRecoveryServicesBackupJob `
            -VaultId $rsv.ID `
            -BackupManagementType AzureVM `
            -Operation Backup `
            -From ((Get-Date).ToUniversalTime().AddDays(-7)) `
            -ErrorAction SilentlyContinue |
            Where-Object { $_.WorkloadName -eq $vmName } |
            Sort-Object StartTime -Descending |
            Select-Object -First 1
    } else { $null }

    Invoke-Test "Latest backup job for '$vmName' has not failed" {
        if (-not $lastJob) {
            Write-Host " (no backup job in the last 7 days - run Backup now, Step 5.2.3)" -NoNewline -ForegroundColor Gray
            return $false
        }
        if ($lastJob.Status -eq 'Failed') {
            $detail = Get-AzRecoveryServicesBackupJobDetail -JobId $lastJob.JobId -VaultId $rsv.ID -ErrorAction SilentlyContinue
            # ErrorCode is numeric (400211); the message is what names the cause.
            $jobErrors = @($detail.ErrorDetails | ForEach-Object { "$($_.ErrorCode): $($_.ErrorMessage)" }) -join '; '
            Write-Host " ($jobErrors - see lab-guide-5.2.md, Troubleshooting)" -NoNewline -ForegroundColor Gray
            return $false
        }
        return ($lastJob.Status -in @('InProgress', 'Completed', 'CompletedWithWarnings'))
    }

    if ($vmName -ne $encryptedVmName) { continue }

    # Lab 3.2 encrypts this VM with Azure Disk Encryption; Azure Backup reads its keys as the
    # Backup Management Service app (#368). Without the role Enable backup fails with 400198.
    Invoke-Test "Backup Management Service holds Key Vault Administrator on '$keyVaultName'" {
        $kvId = "/subscriptions/$($context.Subscription.Id)/resourceGroups/$vmRg/providers/Microsoft.KeyVault/vaults/$keyVaultName"
        $kv = Get-AzResource -ResourceId $kvId -ApiVersion '2023-07-01' -ErrorAction SilentlyContinue
        if (-not $kv) {
            Write-Host " (key vault not found in '$vmRg' - Lab 3.2, Step 3.2.17)" -NoNewline -ForegroundColor Gray
            return $false
        }
        try {
            $sp = Get-AzADServicePrincipal -ApplicationId $backupManagementServiceAppId -ErrorAction Stop | Select-Object -First 1
        } catch {
            throw "Microsoft Graph lookup of the Backup Management Service app failed: $($_.Exception.Message) $(Get-LabGraphSignInHint -Client Az)"
        }
        if (-not $sp) {
            Write-Host " (the Backup Management Service app has no service principal in this tenant)" -NoNewline -ForegroundColor Gray
            return $false
        }
        $held = @(Get-LabArmRoleAssignment -Scope $kvId -PrincipalId $sp.Id | Where-Object {
                $_.RoleDefinitionId -eq $keyVaultAdministratorRoleId -and ($_.Scope -eq $kvId -or $kvId -like "$($_.Scope)/*")
            })
        if ($held.Count -eq 0) {
            Write-Host " (grant it before Enable backup - Step 5.2.3)" -NoNewline -ForegroundColor Gray
        }
        return ($held.Count -gt 0)
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
$bvArm = $null
$bvArmError = $null
if ($bv) {
    try { $bvArm = Get-LabArmResource -ResourceId $bv.Id -ApiVersion $backupVaultApiVersion -ExpandProperties } catch { $bvArmError = $_ }
}

Invoke-Test "Backup Vault '$bvName' exists" {
    return ($null -ne $bv -and $bv.Name -eq $bvName)
}

Invoke-Test "Backup Vault location is swedencentral" {
    if (-not $bv) { return $false }
    return ($bv.Location -eq 'swedencentral')
}

Invoke-Test "Backup Vault storage type is LocallyRedundant" {
    if ($bvArmError) { throw $bvArmError }
    if (-not $bvArm) { return $false }
    return ($bvArm.Properties.storageSettings[0].type -eq 'LocallyRedundant')
}

Invoke-Test "Backup Vault has system-assigned managed identity" {
    if ($bvArmError) { throw $bvArmError }
    if (-not $bvArm) { return $false }
    # Identity is a top-level ARM block; fall back to the typed object if absent.
    $idType    = if ($bvArm.Identity) { "$($bvArm.Identity.Type)" }        else { "$($bv.IdentityType)" }
    $principal = if ($bvArm.Identity -and $bvArm.Identity.PrincipalId) { $bvArm.Identity.PrincipalId } else { $bv.IdentityPrincipalId }
    return (($idType -like '*SystemAssigned*') -and -not [string]::IsNullOrEmpty($principal))
}

Invoke-Test "Backup Vault tag 'Project' = 'SkyCraft'" {
    if ($bvArmError) { throw $bvArmError }
    if (-not $bvArm) { return $false }
    return ($bvArm.Tags.Project -eq 'SkyCraft')
}

Invoke-Test "Backup Vault tag 'Environment' = 'Platform'" {
    if ($bvArmError) { throw $bvArmError }
    if (-not $bvArm) { return $false }
    return ($bvArm.Tags.Environment -eq 'Platform')
}

Invoke-Test "Backup Vault tag 'CostCenter' = 'MSDN'" {
    if ($bvArmError) { throw $bvArmError }
    if (-not $bvArm) { return $false }
    return ($bvArm.Tags.CostCenter -eq 'MSDN')
}

Invoke-Test "Backup Vault soft delete is $($backupVaultSoftDeleteAccepted -join ' or ') (lab-friction override, docs/bicep-standards.md section 4.5)" {
    if ($bvArmError) { throw $bvArmError }
    if (-not $bvArm) { return $false }
    $softDeleteState = "$($bvArm.Properties.securitySettings.softDeleteSettings.state)"
    if ($softDeleteState -in $backupVaultSoftDeleteAccepted) { return $true }
    if ($softDeleteState -eq 'AlwaysOn') {
        # The Portal creates Backup vaults AlwaysOn, and AlwaysOn cannot be turned off.
        Write-Host " (state is AlwaysOn, which cannot be turned off: a vault created in the Portal is AlwaysOn - delete the vault and recreate it with soft delete Off, with scripts/Deploy-Bicep.ps1 (the Bicep) or the request in lab-guide-5.2.md Step 5.2.4; New-AzDataProtectionBackupVault -SoftDeleteState Off is refused)" -NoNewline -ForegroundColor Gray
    } else {
        Write-Host " (state is '$softDeleteState' - set it to Off: Update-AzDataProtectionBackupVault -SoftDeleteState Off)" -NoNewline -ForegroundColor Gray
    }
    return $false
}

# ============================================================================
# Blob Backup Policy Tests
# ============================================================================
Write-Host ""
Write-Host "[Blob Backup Policy]" -ForegroundColor Yellow

$blobPolicy = Get-AzDataProtectionBackupPolicy -ResourceGroupName $platformRg -VaultName $bvName -Name 'SkyCraft-Blob-Policy' -ErrorAction SilentlyContinue
# Raw ARM body — typed object property is ambiguously DatasourceType vs DatasourceTypes
# across module versions; ARM exposes the canonical 'datasourceTypes' array.
$blobPolicyArm = $null
$blobPolicyArmError = $null
if ($bv) {
    try { $blobPolicyArm = Get-LabArmResource -ResourceId "$($bv.Id)/backupPolicies/SkyCraft-Blob-Policy" -ApiVersion '2023-01-01' -ExpandProperties } catch { $blobPolicyArmError = $_ }
}

Invoke-Test "Policy 'SkyCraft-Blob-Policy' exists" {
    return ($null -ne $blobPolicy -and $blobPolicy.Name -eq 'SkyCraft-Blob-Policy')
}

Invoke-Test "Blob policy datasource type is AzureBlob" {
    if ($blobPolicyArmError) { throw $blobPolicyArmError }
    if (-not $blobPolicyArm) { return $false }
    return ($blobPolicyArm.Properties.datasourceTypes -contains 'Microsoft.Storage/storageAccounts/blobServices')
}

Invoke-Test "Blob policy operational retention is 30 days" {
    if ($blobPolicyArmError) { throw $blobPolicyArmError }
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

Invoke-Test "Blob policy has no vaulted backup rule (operational only, no Azure Backup charge)" {
    if (-not $blobPolicyArm) { return $false }
    # A policy made in the Portal always adds a vaulted rule (VaultStore), which is billed (#306).
    $vaulted = @(@($blobPolicyArm.Properties.policyRules) | Where-Object {
            $_ -and ($_.objectType -eq 'AzureBackupRule' -or
                @($_.lifecycles | Where-Object { $_ -and "$($_.sourceDataStore.dataStoreType)" -ne 'OperationalStore' }).Count -gt 0)
        })
    if ($vaulted.Count -gt 0) {
        Write-Host " (vaulted rule(s): $(($vaulted | ForEach-Object { $_.name }) -join ', ') - create the policy with New-LabBlobBackup.ps1 -PolicyOnly, Step 5.2.5)" -NoNewline -ForegroundColor Gray
    }
    return ($vaulted.Count -eq 0)
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

Invoke-Test "Blob backup instance protection is configured and provisioned" {
    if (-not $bv) { return $false }
    $storageId = (Get-AzStorageAccount -ResourceGroupName $prodRg -Name $storageAccount -ErrorAction SilentlyContinue).Id
    if (-not $storageId) { return $false }
    $deadline = (Get-Date).AddSeconds($ProtectionTimeoutSeconds)
    while ($true) {
        $instances = Get-AzDataProtectionBackupInstance -ResourceGroupName $platformRg -VaultName $bvName -ErrorAction SilentlyContinue
        $instance = @($instances | Where-Object { $_.Property.DataSourceInfo.ResourceId -eq $storageId }) | Select-Object -First 1
        if (-not $instance) { return $false }
        $protection = "$($instance.Property.CurrentProtectionState)"
        $provisioning = "$($instance.Property.ProvisioningState)"
        if ($protection -eq 'ProtectionConfigured' -and $provisioning -eq 'Succeeded') { return $true }
        # Only an in-progress state is retried; Failed, ProtectionError and the rest fail at once,
        # also when the other field is still in progress.
        $terminal = $provisioning -in @('Failed', 'Canceled') -or $protection -like '*Error*' -or $protection -like '*Failed*'
        $inProgress = -not $terminal -and ($protection -eq 'ConfiguringProtection' -or $provisioning -in @('Creating', 'Updating'))
        if ($inProgress -and (Get-Date) -lt $deadline) {
            Write-Host "`n    ... protection state '$protection', provisioning state '$provisioning'; checking again in $ProtectionPollSeconds s" -NoNewline -ForegroundColor Yellow
            Start-Sleep -Seconds $ProtectionPollSeconds
            continue
        }
        Write-Host " (protection state '$protection', provisioning state '$provisioning'; expected ProtectionConfigured and Succeeded)" -NoNewline -ForegroundColor Gray
        return $false
    }
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
# Alert Processing Rule Tests
# ============================================================================
Write-Host ""
Write-Host "[Alert Processing Rule]" -ForegroundColor Yellow

$aprId = "/subscriptions/$($context.Subscription.Id)/resourceGroups/$platformRg/providers/Microsoft.AlertsManagement/actionRules/$aprName"
$apr = Get-AzResource -ResourceId $aprId -ApiVersion '2021-08-08' -ExpandProperties -ErrorAction SilentlyContinue

Invoke-Test "Alert processing rule '$aprName' exists and is enabled" {
    return ($null -ne $apr -and $apr.Properties.enabled -eq $true)
}

Invoke-Test "Alert processing rule applies to '$rsvName'" {
    if (-not $apr -or -not $rsv) { return $false }
    # The vault, its resource group or the subscription: each covers the vault's alerts.
    $covering = @(@($apr.Properties.scopes) | Where-Object { $_ -and ($rsv.ID -eq $_ -or $rsv.ID -like "$_/*") })
    return ($covering.Count -gt 0)
}

Invoke-Test "Alert processing rule adds action group '$actionGroupName' (Rule type: Apply action group)" {
    if (-not $apr) { return $false }
    # The Portal's Rule type defaults to Suppress notifications (RemoveAllActionGroups), which
    # silences the alerts instead (#366).
    $add = @(@($apr.Properties.actions) | Where-Object { $_ -and $_.actionType -eq 'AddActionGroups' })
    $groups = @($add | ForEach-Object { @($_.actionGroupIds) } | Where-Object { $_ -like "*/actionGroups/$actionGroupName" })
    $suppress = @(@($apr.Properties.actions) | Where-Object { $_ -and $_.actionType -eq 'RemoveAllActionGroups' })
    if ($suppress.Count -gt 0) {
        Write-Host " (the rule suppresses notifications - set Rule type to Apply action group)" -NoNewline -ForegroundColor Gray
    }
    return ($groups.Count -gt 0 -and $suppress.Count -eq 0)
}

Invoke-Test "Alert processing rule filters on Critical (Sev0) alerts" {
    if (-not $apr) { return $false }
    $severity = @(@($apr.Properties.conditions) | Where-Object {
            $_ -and $_.field -eq 'Severity' -and $_.operator -eq 'Equals' -and @($_.values) -contains 'Sev0'
        })
    return ($severity.Count -gt 0)
}

# ============================================================================
# Azure Site Recovery Tests (Step 5.2.6)
# ============================================================================
Write-Host ""
Write-Host "[Azure Site Recovery]" -ForegroundColor Yellow

$asrRg = Get-AzResourceGroup -Name $asrRgName -ErrorAction SilentlyContinue

Invoke-Test "Target group '$asrRgName' exists in North Europe" {
    return ($null -ne $asrRg -and $asrRg.Location -eq $asrLocation)
}

Invoke-Test "Target group carries the tags $($asrTags -join ', ')" {
    if (-not $asrRg) { return $false }
    $missing = @($asrTags | Where-Object { -not $asrRg.Tags -or -not $asrRg.Tags.ContainsKey($_) -or -not $asrRg.Tags[$_] })
    if ($missing.Count -gt 0) {
        Write-Host " (missing: $($missing -join ', ') - Lab 1.3 denies what Site Recovery creates in an untagged group)" -NoNewline -ForegroundColor Gray
    }
    return ($missing.Count -eq 0)
}

# The vaults of the target group: main.bicep makes one, the Portal wizard may make its own.
$asrVaults = @()
$asrItem = $null
$asrLookupError = $null
if ($asrRg) {
    try {
        $asrVaults = @(Get-AzRecoveryServicesVault -ResourceGroupName $asrRgName -ErrorAction Stop)
        foreach ($vault in $asrVaults) {
            if ($asrItem) { break }
            Set-AzRecoveryServicesAsrVaultContext -Vault $vault | Out-Null
            foreach ($fabric in @(Get-AzRecoveryServicesAsrFabric -ErrorAction Stop)) {
                foreach ($container in @(Get-AzRecoveryServicesAsrProtectionContainer -Fabric $fabric -ErrorAction Stop)) {
                    if (-not $asrItem) {
                        $asrItem = Get-AzRecoveryServicesAsrReplicationProtectedItem -ProtectionContainer $container -ErrorAction Stop |
                            Where-Object { $_.FriendlyName -eq $asrVm } | Select-Object -First 1
                    }
                }
            }
        }
    } catch {
        $asrLookupError = $_.Exception.Message
    }
}

Invoke-Test "Target group holds a Recovery Services vault" {
    if ($asrLookupError) { Write-Host " (lookup failed: $asrLookupError)" -NoNewline -ForegroundColor Gray }
    return ($asrVaults.Count -gt 0)
}

# A VM never deployed (Lab 3.2 skipped) has nothing to replicate: a WARN and a skip, as for its backup.
if (-not (Get-AzVM -Name $asrVm -ResourceGroupName $vmRg -ErrorAction SilentlyContinue)) {
    Write-Host "  [WARNING] VM '$asrVm' not found in '$vmRg' - skipping its replication checks (not counted as failures)." -ForegroundColor Yellow
} else {
    Invoke-Test "'$asrVm' has a replication item in the vault" {
        if ($asrLookupError) { Write-Host " (lookup failed: $asrLookupError)" -NoNewline -ForegroundColor Gray }
        return ($null -ne $asrItem)
    }

    Invoke-Test "Replication of '$asrVm' is Protected" {
        if (-not $asrItem) { return $false }
        if ($asrItem.ProtectionState -ne 'Protected') {
            Write-Host " (state is '$($asrItem.ProtectionState)' - the initial replication takes about 45 minutes; Lab 5.2 Troubleshooting Issue 7)" -NoNewline -ForegroundColor Gray
        }
        return ($asrItem.ProtectionState -eq 'Protected')
    }

    Invoke-Test "Replication health of '$asrVm' is Normal" {
        if (-not $asrItem) { return $false }
        if ($asrItem.ReplicationHealth -ne 'Normal') {
            Write-Host " (health is '$($asrItem.ReplicationHealth)')" -NoNewline -ForegroundColor Gray
        }
        return ($asrItem.ReplicationHealth -eq 'Normal')
    }
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
Exit-Lab -FailureCount $failCount
