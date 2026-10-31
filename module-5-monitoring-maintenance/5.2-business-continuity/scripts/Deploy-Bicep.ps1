<#
.SYNOPSIS
    Deploys Lab 5.2 Business Continuity & Disaster Recovery infrastructure using Bicep.

.DESCRIPTION
    Deploys the Lab 5.2 Bicep templates to Azure, including:
    - Recovery Services Vault (platform-skycraft-swc-rsv) with LRS redundancy
    - VM Backup Policy (SkyCraft-Daily-Prod): Enhanced subtype, daily 02:00 UTC,
      30-day retention, 2-day instant restore. Enhanced is required because Azure
      defaults VM deployments to Trusted Launch, which a Standard policy cannot protect.
      The policy stores its instant-restore snapshots in platform-skycraft-swc-rpc1-rg.
    - Instant-restore snapshot resource group (platform-skycraft-swc-rpc1-rg), tagged, so
      Azure Backup does not create an untagged AzureBackupRG_* group that Lab 1.3's
      Require-Environment-Tag-RG policy denies (issue #184)
    - Backup Vault (platform-skycraft-swc-bv) with LRS and system-assigned identity
    - Blob Backup Policy (SkyCraft-Blob-Policy): 30-day operational retention plus a daily
      vaulted backup kept 7 days. Azure no longer creates an operational-only blob policy
      (issue #306), so the policy carries both, as Microsoft Learn's REST example does.
    - Diagnostic settings for both vaults -> Log Analytics Workspace
    - When dev-skycraft-swc-auth-vm is encrypted with Azure Disk Encryption (Lab 3.2), the
      Key Vault Administrator role for the Microsoft Entra app Backup Management Service on
      the VM's key vault, before backup is enabled (issue #368). Without it Enable backup
      fails with 400198 UserErrorKeyVaultPermissionsNotConfigured. Finding the app needs
      Microsoft Graph unless -BackupManagementServiceObjectId is given.
    - VM backup protection enabled on dev-skycraft-swc-auth-vm (when present), plus an
      on-demand backup whenever the VM has no recovery point yet. A backup job that fails
      within the first minutes counts as a deployment failure.

    After deployment:
    1. Run .\New-LabBlobBackup.ps1 to assign RBAC roles and configure blob
       protection on prodskycraftswcsa.
    2. Configure Azure Site Recovery (ASR) via the Azure Portal (Step 5.2.6)
       — ASR replication requires portal-based setup.

    Prerequisites: Lab 3.2 (VM) and Lab 5.1 (Log Analytics Workspace) must be deployed.

.PARAMETER WhatIf
    Run deployment in what-if mode (dry run).

.PARAMETER Force
    Skip the confirmation prompt for non-interactive execution (master-lab-cycle.ps1 passes this).

.PARAMETER BackupManagementServiceObjectId
    Object id of the Backup Management Service app in this tenant, for a sign-in that cannot
    get a Microsoft Graph token. In Azure Cloud Shell:
    (Get-AzADServicePrincipal -ApplicationId 262044b1-e2ce-469f-a196-69ab7ada62d3).Id

.EXAMPLE
    .\Deploy-Bicep.ps1

.EXAMPLE
    .\Deploy-Bicep.ps1 -WhatIf

.EXAMPLE
    .\Deploy-Bicep.ps1 -Force

.NOTES
    Project: SkyCraft
    Lab: 5.2 - Business Continuity & Disaster Recovery
    Version: 1.2.0
    Date: 2026-10-28
#>

#Requires -Version 7.0
#Requires -Modules Az.Accounts, Az.Resources, Az.RecoveryServices, Az.DataProtection, Az.Compute, Az.OperationalInsights

[CmdletBinding()]
param(
    [Parameter()]
    [switch]$WhatIf,

    [Parameter()]
    [switch]$Force,

    [Parameter()]
    [ValidatePattern('^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$')]
    [string]$BackupManagementServiceObjectId
)

$ErrorActionPreference = 'Stop'
# Exit-Lab ends the script with exit code 0 or 1 and leaves an interactive session open (#257).
Import-Module (Join-Path $PSScriptRoot '../../../tools/LabCommon.psm1') -Force -Verbose:$false

$scriptPath     = Split-Path -Parent $MyInvocation.MyCommand.Path
$templatePath   = Join-Path $scriptPath '..\bicep\main.bicep'
$location       = 'swedencentral'
$platformRg     = 'platform-skycraft-swc-rg'
$workspaceName  = 'platform-skycraft-swc-law'
$vmName         = 'dev-skycraft-swc-auth-vm'
$vmRg           = 'dev-skycraft-swc-rg'
$deploymentName = "lab52-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
$blobPolicyName = 'SkyCraft-Blob-Policy'
$dataProtectionApiVersion = '2024-04-01'
# Observed 2026-10-16: the new role took effect within two minutes (#368).
$keyVaultRoleWaitSeconds = 120

# The blob backup policy body, operational plus vaulted, in the shape of Microsoft Learn's REST
# example ("Create Azure Data Protection backup policies for blobs using REST API"): two Default
# retention rules, OperationalStore and VaultStore, and a daily VaultStore backup rule. The
# Az.DataProtection client objects hold one Default rule only, so the body is sent as JSON.
function Get-LabBlobPolicyBody {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter()] [int]$OperationalRetentionDays = 30,
        [Parameter()] [int]$VaultRetentionDays = 7,
        [Parameter()] [string]$DailyRunTimeUtc = '03:30:00'
    )

    $retention = {
        param([string]$DataStore, [int]$Days)
        [ordered]@{
            name       = 'Default'
            objectType = 'AzureRetentionRule'
            isDefault  = $true
            lifecycles = @(
                [ordered]@{
                    deleteAfter                 = [ordered]@{ duration = "P$($Days)D"; objectType = 'AbsoluteDeleteOption' }
                    sourceDataStore             = [ordered]@{ dataStoreType = $DataStore; objectType = 'DataStoreInfoBase' }
                    targetDataStoreCopySettings = @()
                }
            )
        }
    }
    $backupRule = [ordered]@{
        name             = 'BackupDaily'
        objectType       = 'AzureBackupRule'
        backupParameters = [ordered]@{ backupType = 'Discrete'; objectType = 'AzureBackupParams' }
        dataStore        = [ordered]@{ dataStoreType = 'VaultStore'; objectType = 'DataStoreInfoBase' }
        trigger          = [ordered]@{
            objectType      = 'ScheduleBasedTriggerContext'
            # A date and a time: Learn says the service takes no time without a date.
            schedule        = [ordered]@{ timeZone = 'UTC'; repeatingTimeIntervals = @("R/2026-01-01T$($DailyRunTimeUtc)+00:00/P1D") }
            taggingCriteria = @(
                [ordered]@{ isDefault = $true; taggingPriority = 99; tagInfo = [ordered]@{ id = 'Default_'; tagName = 'Default' } }
            )
        }
    }
    $body = [ordered]@{
        properties = [ordered]@{
            datasourceTypes = @('Microsoft.Storage/storageAccounts/blobServices')
            objectType      = 'BackupPolicy'
            policyRules     = @(
                (& $retention 'OperationalStore' $OperationalRetentionDays)
                (& $retention 'VaultStore' $VaultRetentionDays)
                $backupRule
            )
        }
    }
    $body | ConvertTo-Json -Depth 20 -Compress
}

# Whether a blob policy as ARM returns it backs up to the vault: a VaultStore backup rule and a
# VaultStore retention lifecycle. An operational-only policy from before issue #306 has neither.
function Test-LabBlobPolicyVaulted {
    [CmdletBinding()]
    [OutputType([bool])]
    param([Parameter(Mandatory)] [object]$Policy)

    $rules = @($Policy.properties.policyRules)
    $backupRules = @($rules | Where-Object { $_.objectType -eq 'AzureBackupRule' -and $_.dataStore.dataStoreType -eq 'VaultStore' })
    $vaultLifecycles = @($rules | Where-Object { $_.objectType -eq 'AzureRetentionRule' } |
            ForEach-Object { @($_.lifecycles) } | Where-Object { $_.sourceDataStore.dataStoreType -eq 'VaultStore' })
    $backupRules.Count -gt 0 -and $vaultLifecycles.Count -gt 0
}

# Grants Backup Management Service the Key Vault Administrator role on one key vault: the role
# Microsoft Learn names for backing up ADE VMs with an RBAC key vault ("Back up and restore
# encrypted Azure virtual machines", "Back up ADE-encrypted VMs with RBAC-enabled key vaults").
# A role held on the vault or above it counts. Returns 'Held' or 'Created'; a failed read or
# create throws.
function Grant-LabBackupKeyVaultRole {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [string]$KeyVaultId,
        [Parameter(Mandatory)] [string]$PrincipalId
    )

    $roleId = Get-LabBuiltInRoleId -Name 'Key Vault Administrator'
    $held = @(Get-LabArmRoleAssignment -Scope $KeyVaultId -PrincipalId $PrincipalId | Where-Object {
            $_.RoleDefinitionId -eq $roleId -and (
                $_.Scope -eq $KeyVaultId -or $KeyVaultId -like "$($_.Scope)/*" -or $_.Scope -eq '/' -or
                $_.Scope -like '/providers/Microsoft.Management/managementGroups/*')
        })
    if ($held.Count -gt 0) { return 'Held' }
    # ServicePrincipal: ARM skips its directory check of the principal.
    New-LabArmRoleAssignment -Scope $KeyVaultId -RoleDefinitionId $roleId -PrincipalId $PrincipalId -PrincipalType 'ServicePrincipal' | Out-Null
    'Created'
}

# Counts lab resources that were meant to be created but were not. A step that only warns
# and lets the script exit 0 lets an orchestrated cycle record a half-built lab as a success.
$script:deployFailures = 0

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  Lab 5.2 - BCDR Deployment" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# ── [1/7] Validate prerequisites ──────────────────────────────────────────
Write-Host "[1/7] Validating prerequisites..." -ForegroundColor Yellow

$context = Get-AzContext
if (-not $context) {
    Write-Host "  [ERROR] Not logged into Azure. Run 'Connect-AzAccount' first." -ForegroundColor Red
    Exit-Lab -FailureCount 1
}
Write-Host "  ✓ Logged in as: $($context.Account.Id)" -ForegroundColor Green

# Register required resource providers (idempotent)
foreach ($ns in @('Microsoft.RecoveryServices', 'Microsoft.DataProtection')) {
    $provider = Get-AzResourceProvider -ProviderNamespace $ns -ErrorAction SilentlyContinue | Select-Object -First 1
    $state = if ($provider) { $provider.RegistrationState } else { 'NotRegistered' }
    if ($state -ne 'Registered') {
        if ($WhatIf) {
            Write-Host "  What-if: would register provider $ns (skipped)" -ForegroundColor Cyan
            continue
        }
        Write-Host "  Registering provider: $ns..." -ForegroundColor Gray
        Register-AzResourceProvider -ProviderNamespace $ns | Out-Null
        Write-Host "  ✓ Registered: $ns" -ForegroundColor Green
    }
}

# ── [2/7] Resolve resource IDs ────────────────────────────────────────────
Write-Host "`n[2/7] Resolving existing resource IDs..." -ForegroundColor Yellow

$platformRgExists = Get-AzResourceGroup -Name $platformRg -ErrorAction SilentlyContinue
if (-not $platformRgExists) {
    Write-Host "  [ERROR] Resource group '$platformRg' not found. Complete earlier labs first." -ForegroundColor Red
    Exit-Lab -FailureCount 1
}
Write-Host "  ✓ Platform RG found: $platformRg" -ForegroundColor Green

$workspace = Get-AzOperationalInsightsWorkspace -ResourceGroupName $platformRg -Name $workspaceName -ErrorAction SilentlyContinue
if (-not $workspace) {
    Write-Host "  [ERROR] Log Analytics Workspace '$workspaceName' not found. Deploy Lab 5.1 first." -ForegroundColor Red
    Exit-Lab -FailureCount 1
}
$workspaceId = $workspace.ResourceId
Write-Host "  ✓ Log Analytics Workspace found: $workspaceName" -ForegroundColor Green

# ── [3/7] Display deployment configuration ────────────────────────────────
Write-Host "`n[3/7] Deployment Configuration:" -ForegroundColor Yellow
Write-Host "  Platform RG:     $platformRg"
Write-Host "  Workspace:       $workspaceName"
Write-Host "  Location:        $location"
Write-Host "  Template:        $templatePath"
Write-Host "  Deployment Name: $deploymentName"

if (-not $WhatIf -and -not $Force) {
    $confirm = Read-Host "`nProceed with deployment? (y/N)"
    if ($confirm -ne 'y') {
        Write-Host "Deployment cancelled." -ForegroundColor Yellow
        exit 0
    }
}

# ── [4/7] Run Bicep deployment ────────────────────────────────────────────
Write-Host "`n[4/7] Running Bicep deployment..." -ForegroundColor Yellow

$deployParams = @{
    Name           = $deploymentName
    Location       = $location
    TemplateFile   = $templatePath
    parWorkspaceId = $workspaceId
    ErrorAction    = 'Stop'
}

$deployment = $null
$result     = $null

try {
    if ($WhatIf) {
        Write-Host "  Running in what-if mode (dry run)..." -ForegroundColor Cyan
        $result = Get-AzSubscriptionDeploymentWhatIfResult @deployParams
    } else {
        $deployment = New-AzSubscriptionDeployment @deployParams
    }
} catch {
    Write-Host "`n  [ERROR] Deployment failed: $($_.Exception.Message)" -ForegroundColor Red
    Exit-Lab -FailureCount 1
}

if ($WhatIf) {
    $result
    Write-Host "`n  What-if completed. Review changes above." -ForegroundColor Cyan
} else {
    if ($deployment.ProvisioningState -ne 'Succeeded') {
        Write-Host "`n  [FAILED] Deployment finished with state: $($deployment.ProvisioningState)" -ForegroundColor Red
        Exit-Lab -FailureCount 1
    }

    Write-Host "  ✓ Vaults deployed successfully!" -ForegroundColor Green
    $rsvId = $deployment.Outputs['outRsvId'].Value
    $bvPrincipalId = $deployment.Outputs['outBvPrincipalId'].Value
    # The VM backup policy names the snapshot group by prefix and suffix; Azure Backup inserts the
    # number. The template owns all three values, so the policy cannot drift from the group.
    $snapshotRgName   = $deployment.Outputs['outSnapshotRgName'].Value
    $snapshotRgPrefix = $deployment.Outputs['outSnapshotRgPrefix'].Value
    $snapshotRgSuffix = $deployment.Outputs['outSnapshotRgSuffix'].Value

    Write-Host "    RSV ID:          $rsvId"
    Write-Host "    Backup Vault ID: $($deployment.Outputs['outBvId'].Value)"
    Write-Host "    BV Principal ID: $bvPrincipalId"
    Write-Host "    Snapshot RG:     $snapshotRgName"

    # Resolve the Recovery Services Vault object for the backup cmdlets below
    $vault = Get-AzRecoveryServicesVault -ResourceGroupName $platformRg -Name 'platform-skycraft-swc-rsv' -ErrorAction SilentlyContinue

    # ── Set RSV storage redundancy to LRS (idempotent) ────────────────────
    Write-Host "`n[5/7] Ensuring RSV storage redundancy is LocallyRedundant..." -ForegroundColor Yellow
    $rsvProps = Get-AzRecoveryServicesBackupProperty -Vault $vault -ErrorAction SilentlyContinue
    $currentRedundancy = $rsvProps.BackupStorageRedundancy
    $isLocked = $rsvProps.StorageTypeState -eq 'Locked'

    if ($currentRedundancy -eq 'LocallyRedundant') {
        Write-Host "  ✓ Redundancy already set to LocallyRedundant$(if ($isLocked) { ' (Locked — first backup has run)' })" -ForegroundColor Green
    } else {
        Write-Host "  Setting redundancy to LocallyRedundant..." -ForegroundColor Gray
        try {
            Set-AzRecoveryServicesBackupProperty -Vault $vault -BackupStorageRedundancy LocallyRedundant | Out-Null
            Write-Host "  ✓ Redundancy set to LocallyRedundant" -ForegroundColor Green
        } catch {
            Write-Host "  [WARNING] Could not set redundancy (vault may already be in use): $_" -ForegroundColor Yellow
        }
    }

    # ── Create VM Backup Policy (idempotent) ──────────────────────────────
    Write-Host "`n[6/7] Ensuring backup policies (SkyCraft-Daily-Prod, SkyCraft-Blob-Policy)..." -ForegroundColor Yellow
    $existingRsvPolicy = Get-AzRecoveryServicesBackupProtectionPolicy `
        -Name 'SkyCraft-Daily-Prod' `
        -VaultId $vault.ID `
        -ErrorAction SilentlyContinue

    if ($existingRsvPolicy) {
        # Azure cannot convert a policy between subtypes, so a 'SkyCraft-Daily-Prod' left behind
        # by an earlier revision of this script is Standard and still cannot protect a Trusted
        # Launch VM. Say so instead of letting step [7/7] fail with a service error (#113).
        $enhancedPolicyNames = @(
            Get-AzRecoveryServicesBackupProtectionPolicy `
                -WorkloadType AzureVM `
                -BackupManagementType AzureVM `
                -PolicySubType Enhanced `
                -VaultId $vault.ID `
                -ErrorAction SilentlyContinue
        ).Name
        if ($enhancedPolicyNames -contains 'SkyCraft-Daily-Prod') {
            Write-Host "  ✓ Policy 'SkyCraft-Daily-Prod' already exists in RSV (Enhanced)" -ForegroundColor Green
            # A policy created before issue #184 names no snapshot group, so Azure Backup keeps
            # creating an untagged AzureBackupRG_* group that Lab 1.3's policy denies. Point it at
            # the tagged group; recovery points already taken stay where they are and expire.
            if ($existingRsvPolicy.AzureBackupRGName -ne $snapshotRgPrefix -or
                "$($existingRsvPolicy.AzureBackupRGNameSuffix)" -ne $snapshotRgSuffix) {
                try {
                    Set-AzRecoveryServicesBackupProtectionPolicy `
                        -Policy $existingRsvPolicy `
                        -BackupSnapshotResourceGroup $snapshotRgPrefix `
                        -BackupSnapshotResourceGroupSuffix $snapshotRgSuffix `
                        -VaultId $vault.ID | Out-Null
                    Write-Host "  ✓ Policy now stores instant-restore snapshots in $snapshotRgName" -ForegroundColor Green
                } catch {
                    $script:deployFailures++
                    Write-Host "  [ERROR] Could not point the policy at snapshot group '$snapshotRgName': $_" -ForegroundColor Red
                }
            } else {
                Write-Host "  ✓ Instant-restore snapshots go to $snapshotRgName" -ForegroundColor Green
            }
        } else {
            $script:deployFailures++
            Write-Host "  [ERROR] Policy 'SkyCraft-Daily-Prod' exists but is a Standard policy." -ForegroundColor Red
            Write-Host "    A Standard policy cannot protect a Trusted Launch VM, and Azure cannot" -ForegroundColor Gray
            Write-Host "    change a policy's subtype. Delete it once nothing is protected by it and" -ForegroundColor Gray
            Write-Host "    re-run this script, or run Remove-LabResource.ps1 for a clean rebuild:" -ForegroundColor Gray
            Write-Host "      Remove-AzRecoveryServicesBackupProtectionPolicy -Name 'SkyCraft-Daily-Prod' -VaultId <id>" -ForegroundColor Gray
        }
    } else {
        Write-Host "  Creating 'SkyCraft-Daily-Prod' backup policy..." -ForegroundColor Gray
        try {
            # Daily schedule at 02:00 UTC with 30-day daily retention, on an *Enhanced*
            # policy. Azure defaults VM deployments to Trusted Launch from Ignite 2023 onward,
            # and a Trusted Launch VM cannot be protected by a Standard policy - it fails with
            # UserErrorThisVMBackupIsSupportedUsingEnhancedPolicy (#113). Every SkyCraft VM is
            # affected, so this is the default path, not an edge case.
            # Enhanced returns a SimpleSchedulePolicyV2, which nests the run times under
            # DailySchedule instead of exposing a flat ScheduleRunTimes collection.
            $runTimeUtc = [datetime]::SpecifyKind([datetime]'02:00:00', [System.DateTimeKind]::Utc)
            $schedulePolicy = Get-AzRecoveryServicesBackupSchedulePolicyObject `
                -WorkloadType AzureVM `
                -BackupManagementType AzureVM `
                -PolicySubType Enhanced `
                -ScheduleRunFrequency Daily
            $schedulePolicy.DailySchedule.ScheduleRunTimes.Clear()
            $schedulePolicy.DailySchedule.ScheduleRunTimes.Add($runTimeUtc)

            $retentionPolicy = Get-AzRecoveryServicesBackupRetentionPolicyObject `
                -WorkloadType AzureVM `
                -BackupManagementType AzureVM `
                -ScheduleRunFrequency Daily
            $retentionPolicy.DailySchedule.DurationCountInDays = 30
            $retentionPolicy.DailySchedule.RetentionTimes.Clear()
            $retentionPolicy.DailySchedule.RetentionTimes.Add($runTimeUtc)

            # The snapshot group is named here, at creation: without it Azure Backup creates an
            # untagged AzureBackupRG_<region>_<n> group, which Lab 1.3's Require-Environment-Tag-RG
            # denies, and every backup fails with UserErrorRequestDisallowedByPolicy (#184).
            New-AzRecoveryServicesBackupProtectionPolicy `
                -Name 'SkyCraft-Daily-Prod' `
                -WorkloadType AzureVM `
                -BackupManagementType AzureVM `
                -SchedulePolicy $schedulePolicy `
                -RetentionPolicy $retentionPolicy `
                -BackupSnapshotResourceGroup $snapshotRgPrefix `
                -BackupSnapshotResourceGroupSuffix $snapshotRgSuffix `
                -VaultId $vault.ID | Out-Null

            # Enhanced keeps instant-restore snapshots for 7 days by default, where Standard kept
            # 2. Snapshots are billed, so pull it back to 2 and keep the cost estimate in
            # ARCHITECTURE.md honest. The snapshot group is passed again so this update cannot
            # drop it.
            $createdPolicy = Get-AzRecoveryServicesBackupProtectionPolicy -Name 'SkyCraft-Daily-Prod' -VaultId $vault.ID
            $createdPolicy.SnapshotRetentionInDays = 2
            Set-AzRecoveryServicesBackupProtectionPolicy `
                -Policy $createdPolicy `
                -BackupSnapshotResourceGroup $snapshotRgPrefix `
                -BackupSnapshotResourceGroupSuffix $snapshotRgSuffix `
                -VaultId $vault.ID | Out-Null

            Write-Host "  ✓ Policy 'SkyCraft-Daily-Prod' created (Enhanced, daily 02:00 UTC, 30-day retention, snapshots in $snapshotRgName)" -ForegroundColor Green
        } catch {
            $script:deployFailures++
            Write-Host "  [ERROR] Failed to create RSV policy: $_" -ForegroundColor Red
        }
    }

    # ── Create Blob Backup Policy (idempotent) ────────────────────────────
    # Microsoft Learn ("Overview of Azure Blob backup"): a new blob policy cannot be operational
    # only; vaulted backup is part of it and cannot be turned off (#306). Read and written through
    # ARM, so the stored rules are what is checked and a failed read is not "absent".
    $blobPolicyPath = "$($deployment.Outputs['outBvId'].Value)/backupPolicies/$($blobPolicyName)?api-version=$dataProtectionApiVersion"
    $existingBlobPolicy = $null
    $blobPolicyReadFailed = $false
    try {
        $existingBlobPolicy = Invoke-LabArmRequest -Method GET -Path $blobPolicyPath
    } catch {
        if ($_.Exception.Data['StatusCode'] -ne 404) {
            $blobPolicyReadFailed = $true
            $script:deployFailures++
            Write-Host "  [ERROR] Could not read policy '$blobPolicyName': $_" -ForegroundColor Red
        }
    }

    if ($blobPolicyReadFailed) {
        Write-Host "    The policy was not created or checked; re-run this script." -ForegroundColor Gray
    } elseif ($existingBlobPolicy -and (Test-LabBlobPolicyVaulted -Policy $existingBlobPolicy)) {
        Write-Host "  ✓ Policy '$blobPolicyName' already exists in Backup Vault (operational + vaulted)" -ForegroundColor Green
    } elseif ($existingBlobPolicy) {
        # Azure does not update a blob policy in place, and a policy in use cannot be deleted.
        $script:deployFailures++
        Write-Host "  [ERROR] Policy '$blobPolicyName' exists but is operational only (created before issue #306)." -ForegroundColor Red
        Write-Host "    Azure no longer creates such a policy, and New-LabBlobBackup.ps1 now configures vaulted" -ForegroundColor Gray
        Write-Host "    backup. Run Remove-LabResource.ps1 for a clean rebuild, or delete the blob backup" -ForegroundColor Gray
        Write-Host "    instance and the policy, then re-run this script." -ForegroundColor Gray
    } else {
        Write-Host "  Creating '$blobPolicyName' blob backup policy (operational 30 days, vaulted daily kept 7 days)..." -ForegroundColor Gray
        try {
            Invoke-LabArmRequest -Method PUT -Path $blobPolicyPath -Payload (Get-LabBlobPolicyBody) | Out-Null
            Write-Host "  ✓ Policy '$blobPolicyName' created (operational 30 days; vaulted daily 03:30 UTC, kept 7 days)" -ForegroundColor Green
        } catch {
            $script:deployFailures++
            Write-Host "  [ERROR] Failed to create Blob policy: $_" -ForegroundColor Red
        }
    }

    # ── Enable VM Backup Protection (idempotent, dev VM only) ─────────────
    # The automated cycle deploys a standalone dev VM only; no prod VM exists.
    # If the dev VM is absent (Lab 3.2 not run), WARN and skip — do not fail.
    Write-Host "`n[7/7] Ensuring VM backup protection for $vmName..." -ForegroundColor Yellow
    $vm = Get-AzVM -Name $vmName -ResourceGroupName $vmRg -ErrorAction SilentlyContinue
    # Set when Azure Backup may lack access to the VM's key vault: enabling or running a backup
    # would only fail with 400198 UserErrorKeyVaultPermissionsNotConfigured.
    $vmBackupBlocked = $false

    # Azure Backup reads an ADE VM's key vault as the Backup Management Service app, not as the
    # vault's identity, and needs the role before Enable backup (#368). Lab 3.2 stays unchanged.
    if ($vm) {
        $keyVaultIds = @()
        try {
            $keyVaultIds = @(Get-LabAdeKeyVaultId -ResourceGroupName $vmRg -VMName $vmName)
        } catch {
            $vmBackupBlocked = $true
            $script:deployFailures++
            Write-Host "  [ERROR] Could not read the disk encryption of ${vmName}: $_" -ForegroundColor Red
        }
        if ($keyVaultIds.Count -eq 0 -and -not $vmBackupBlocked) {
            Write-Host "  ✓ $vmName is not encrypted with Azure Disk Encryption - no key vault role needed" -ForegroundColor Green
        } elseif ($keyVaultIds.Count -gt 0) {
            $backupServiceId = $null
            try {
                $backupServiceId = Get-LabBackupManagementServiceId -ObjectId $BackupManagementServiceObjectId
            } catch {
                $vmBackupBlocked = $true
                $script:deployFailures++
                Write-Host "  [ERROR] $_" -ForegroundColor Red
            }
            $roleCreated = $false
            foreach ($keyVaultId in @(if ($backupServiceId) { $keyVaultIds })) {
                $keyVaultName = ($keyVaultId -split '/')[-1]
                try {
                    $outcome = Grant-LabBackupKeyVaultRole -KeyVaultId $keyVaultId -PrincipalId $backupServiceId
                    if ($outcome -eq 'Created') {
                        $roleCreated = $true
                        Write-Host "  ✓ Backup Management Service granted Key Vault Administrator on $keyVaultName" -ForegroundColor Green
                    } else {
                        Write-Host "  ✓ Backup Management Service already holds Key Vault Administrator on $keyVaultName" -ForegroundColor Green
                    }
                } catch {
                    $vmBackupBlocked = $true
                    $script:deployFailures++
                    Write-Host "  [ERROR] Could not grant Backup Management Service Key Vault Administrator on ${keyVaultName}: $_" -ForegroundColor Red
                    Write-Host "    Assigning a role needs Owner, User Access Administrator or Role Based Access Control Administrator on the key vault." -ForegroundColor Gray
                }
            }
            if ($roleCreated -and -not $vmBackupBlocked) {
                Write-Host "  Waiting $keyVaultRoleWaitSeconds seconds for the role to take effect..." -ForegroundColor Gray
                Start-Sleep -Seconds $keyVaultRoleWaitSeconds
            }
        }
    }

    $vmItems = Get-AzRecoveryServicesBackupItem `
        -VaultId $vault.ID `
        -BackupManagementType AzureVM `
        -WorkloadType AzureVM `
        -ErrorAction SilentlyContinue
    # FriendlyName comes back empty for some protected VMs (#105), which made this check
    # miss an already-protected VM and re-run Enable on every deployment. The container name
    # carries the VM name as its last ';'-separated segment.
    $vmItem = $vmItems | Where-Object {
        $_.FriendlyName -eq $vmName -or ($_.ContainerName -split ';')[-1] -eq $vmName
    }

    if ($vmBackupBlocked) {
        Write-Host "  [SKIP] VM backup not enabled or run: Azure Backup may not be able to read the key vault of $vmName (see the [ERROR] above)." -ForegroundColor Yellow
        $vmItem = $null
    } elseif ($vmItem) {
        Write-Host "  ✓ $vmName is already protected (policy: $($vmItem.ProtectionPolicyName))" -ForegroundColor Green
    } else {
        Write-Host "  Enabling backup protection for $vmName..." -ForegroundColor Gray
        if (-not $vm) {
            Write-Host "  [WARNING] VM '$vmName' not found in '$vmRg'. Skipping VM-backup steps." -ForegroundColor Yellow
            Write-Host "  Complete Lab 3.2 (dev VM) first and re-run this script if VM backup is required." -ForegroundColor Yellow
        } else {
            try {
                $protectionPolicy = Get-AzRecoveryServicesBackupProtectionPolicy -Name 'SkyCraft-Daily-Prod' -VaultId $vault.ID
                Enable-AzRecoveryServicesBackupProtection `
                    -ResourceGroupName $vmRg `
                    -Name $vmName `
                    -Policy $protectionPolicy `
                    -VaultId $vault.ID | Out-Null
                Write-Host "  ✓ VM backup protection enabled for $vmName" -ForegroundColor Green
                $vmItem = Get-AzRecoveryServicesBackupItem `
                    -VaultId $vault.ID `
                    -BackupManagementType AzureVM `
                    -WorkloadType AzureVM `
                    -ErrorAction SilentlyContinue | Where-Object {
                        $_.FriendlyName -eq $vmName -or ($_.ContainerName -split ';')[-1] -eq $vmName
                    }
            } catch {
                $script:deployFailures++
                Write-Host "  [ERROR] Could not enable VM backup: $_" -ForegroundColor Red
                Write-Host "    If this is UserErrorThisVMBackupIsSupportedUsingEnhancedPolicy, the vault still" -ForegroundColor Gray
                Write-Host "    holds a Standard 'SkyCraft-Daily-Prod' from an earlier run - see step [6/7]." -ForegroundColor Gray
                Write-Host "    If this is UserErrorKeyVaultPermissionsNotConfigured, the key vault role above has not" -ForegroundColor Gray
                Write-Host "    taken effect yet: wait a few minutes and re-run (lab-guide-5.2.md, Troubleshooting, Issue 3)." -ForegroundColor Gray
                Write-Host "    Enable manually: Enable-AzRecoveryServicesBackupProtection (Step 5.2.3)" -ForegroundColor Gray
            }
        }
    }

    # ── Initial backup and its outcome ────────────────────────────────────
    # Protection alone proves nothing: after Lab 1.3 every job used to fail in seconds with
    # UserErrorRequestDisallowedByPolicy while this script reported success (#184). So a VM
    # without a recovery point gets an on-demand backup on every run - not only the run that
    # enabled protection, or a failed first job would never be retried - and the job is watched
    # long enough to catch a fast failure. The vault transfer takes far longer than that; a job
    # still running when the watch ends is reported, not waited for.
    $vmItem = $vmItem | Select-Object -First 1
    if ($vmItem) {
        try {
            $recoveryPoints = @(Get-AzRecoveryServicesBackupRecoveryPoint -Item $vmItem -VaultId $vault.ID -ErrorAction SilentlyContinue)
            # -Operation Backup: enabling protection or changing the policy (step [6/7]) starts a
            # ConfigureBackup job, and mistaking that for a running backup would skip the backup.
            $job = Get-AzRecoveryServicesBackupJob `
                -VaultId $vault.ID `
                -BackupManagementType AzureVM `
                -Operation Backup `
                -Status InProgress `
                -ErrorAction SilentlyContinue |
                Where-Object { $_.WorkloadName -eq $vmName } |
                Select-Object -First 1

            if ($recoveryPoints.Count -gt 0) {
                Write-Host "  ✓ $vmName has $($recoveryPoints.Count) recovery point(s) - no on-demand backup needed" -ForegroundColor Green
                $job = $null
            } elseif ($job) {
                Write-Host "  ✓ A backup job for $vmName is already running (started $($job.StartTime) UTC)" -ForegroundColor Green
            } else {
                Write-Host "  Triggering on-demand backup (no recovery point yet)..." -ForegroundColor Gray
                $job = Backup-AzRecoveryServicesBackupItem `
                    -Item $vmItem `
                    -VaultId $vault.ID `
                    -ExpiryDateTimeUTC ((Get-Date).AddDays(30).ToUniversalTime())
            }

            if ($job) {
                $deadline = (Get-Date).AddMinutes(3)
                $jobId = $job.JobId
                while ($job -and $job.Status -eq 'InProgress' -and (Get-Date) -lt $deadline) {
                    Start-Sleep -Seconds 15
                    $job = Get-AzRecoveryServicesBackupJob -JobId $jobId -VaultId $vault.ID -ErrorAction SilentlyContinue
                }

                if (-not $job) {
                    Write-Host "  [WARNING] Lost track of backup job $jobId - check Backup jobs in the vault" -ForegroundColor Yellow
                } elseif ($job.Status -eq 'Failed') {
                    $script:deployFailures++
                    Write-Host "  [ERROR] Backup job for $vmName failed:" -ForegroundColor Red
                    $detail = Get-AzRecoveryServicesBackupJobDetail -JobId $jobId -VaultId $vault.ID -ErrorAction SilentlyContinue
                    foreach ($err in @($detail.ErrorDetails)) {
                        if ($err) { Write-Host "    $($err.ErrorCode): $($err.ErrorMessage)" -ForegroundColor Red }
                    }
                    Write-Host "    400211 (UserErrorRequestDisallowedByPolicy) means an Azure Policy deny refused a" -ForegroundColor Gray
                    Write-Host "    resource Azure Backup creates for the snapshot - see lab-guide-5.2.md, Troubleshooting, Issue 2." -ForegroundColor Gray
                } elseif ($job.Status -eq 'InProgress') {
                    Write-Host "  ✓ Backup job for $vmName is running (the vault transfer takes a while - check Backup jobs)" -ForegroundColor Green
                } else {
                    Write-Host "  ✓ Backup job for ${vmName}: $($job.Status)" -ForegroundColor Green
                }
            }
        } catch {
            $script:deployFailures++
            Write-Host "  [ERROR] Could not run the initial backup of ${vmName}: $_" -ForegroundColor Red
            Write-Host "    Trigger it manually: vault -> Backup items -> Azure Virtual Machine -> Backup now (Step 5.2.3)" -ForegroundColor Gray
        }
    } elseif ($vm -and -not $vmBackupBlocked) {
        # Protection was just enabled, but the vault does not list the item yet.
        Write-Host "  [WARNING] $vmName is protected but not listed as a backup item yet - no initial backup was triggered." -ForegroundColor Yellow
        Write-Host "    Re-run this script in a few minutes, or use Backup now (Step 5.2.3)." -ForegroundColor Gray
    }

    Write-Host "`n  Next Steps:" -ForegroundColor Cyan
    Write-Host "    1. Run .\New-LabBlobBackup.ps1 to configure blob protection on the production storage account of Lab 4.1 (add -ProdSaName if it has another name)" -ForegroundColor Gray
    Write-Host "    2. Configure Azure Site Recovery via Azure Portal (Step 5.2.6)" -ForegroundColor Gray
    Write-Host "    3. Run .\Test-Lab.ps1 to validate deployment" -ForegroundColor Gray
}

Write-Host "`n========================================" -ForegroundColor Cyan
if ($script:deployFailures -gt 0) {
    Write-Host "  Deployment finished with $($script:deployFailures) failure(s)" -ForegroundColor Red
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "  See the [ERROR] lines above - this run exits 1, nothing was masked." -ForegroundColor Gray
    Write-Host "  A missing VM (Lab 3.2 not run) is a skip, not a failure." -ForegroundColor Gray
    Write-Host "========================================`n" -ForegroundColor Cyan
    Exit-Lab -FailureCount 1
}

Write-Host "  Deployment Complete" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan
