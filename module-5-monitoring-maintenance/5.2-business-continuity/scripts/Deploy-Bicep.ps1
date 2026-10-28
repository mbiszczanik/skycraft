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
    - Backup Vault (platform-skycraft-swc-bv) with LRS, system-assigned identity and soft
      delete Off (a Portal-built vault is AlwaysOn, which cannot be undone, issue #366)
    - Diagnostic settings for both vaults -> Log Analytics Workspace
    - Alert processing rule (skycraft-backup-critical-apr): the vault's Critical alerts go to
      Lab 5.1's action group skycraft-ops-ag
    - Key Vault Administrator for the Backup Management Service app on dev-skycraft-swc-kv,
      unless it holds the role already. Lab 3.2 encrypts dev-skycraft-swc-auth-vm with Azure
      Disk Encryption, and without the role Enable backup fails with 400198 (issue #368).
      Finding the app's service principal needs Microsoft Graph; the role read and the
      grant go through Azure Resource Manager.
    - VM backup protection enabled on dev-skycraft-swc-auth-vm and dev-skycraft-swc-world-vm
      (each when present), plus an on-demand backup whenever a VM has no recovery point yet.
      The world VM is the unencrypted one Step 5.2.10 restores files from. The script watches the
      job's Take Snapshot phase until it completes or fails (up to 20 minutes) and counts a
      failure, or a phase it did not see finish, as a deployment failure.

    The blob backup policy (SkyCraft-Blob-Policy) is created by New-LabBlobBackup.ps1, the
    script the guide has the learner run (issue #306).

    After deployment:
    1. Run .\New-LabBlobBackup.ps1 to create the blob backup policy, assign RBAC roles and
       configure blob protection on prodskycraftswcsa.
    2. Configure Azure Site Recovery (ASR) via the Azure Portal (Step 5.2.6)
       — ASR replication requires portal-based setup.

    Prerequisites: Lab 3.2 (VM and key vault) and Lab 5.1 (Log Analytics Workspace and action
    group skycraft-ops-ag) must be deployed.

.PARAMETER WhatIf
    Run deployment in what-if mode (dry run).

.PARAMETER Force
    Skip the confirmation prompt for non-interactive execution (master-lab-cycle.ps1 passes this).

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
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
# Exit-Lab ends the script with exit code 0 or 1 and leaves an interactive session open (#257).
Import-Module (Join-Path $PSScriptRoot '../../../tools/LabCommon.psm1') -Force -Verbose:$false

$scriptPath     = Split-Path -Parent $MyInvocation.MyCommand.Path
$templatePath   = Join-Path $scriptPath '..\bicep\main.bicep'
$location       = 'swedencentral'
$platformRg     = 'platform-skycraft-swc-rg'
$workspaceName  = 'platform-skycraft-swc-law'
# The auth VM is ADE-encrypted (Lab 3.2); the world VM is not, so Step 5.2.10 restores files from it.
$vmNames        = @('dev-skycraft-swc-auth-vm', 'dev-skycraft-swc-world-vm')
$vmRg           = 'dev-skycraft-swc-rg'
$actionGroupName = 'skycraft-ops-ag'
$keyVaultName   = 'dev-skycraft-swc-kv'
# Built-in ids, the same in every tenant: the Backup Management Service app and Key Vault Administrator.
$backupManagementServiceAppId = '262044b1-e2ce-469f-a196-69ab7ada62d3'
$keyVaultAdministratorRoleId  = '00482a5a-887f-4fb3-b363-3b7fe8e74483'
# Take Snapshot took about 8.5 minutes live on 2026-10-16.
$snapshotWatchMinutes = 20
$deploymentName = "lab52-$(Get-Date -Format 'yyyyMMdd-HHmmss')"

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

# The alert processing rule adds Lab 5.1's action group.
$actionGroup = Get-AzResource -ResourceGroupName $platformRg -ResourceType 'Microsoft.Insights/actionGroups' -Name $actionGroupName -ErrorAction SilentlyContinue
if (-not $actionGroup) {
    Write-Host "  [ERROR] Action group '$actionGroupName' not found in '$platformRg'. Deploy Lab 5.1 first." -ForegroundColor Red
    Exit-Lab -FailureCount 1
}
Write-Host "  ✓ Action group found: $actionGroupName" -ForegroundColor Green

# Key Vault Administrator for the Backup Management Service app on Lab 3.2's key vault (#368).
# The template grants it only when the app lacks it: a second grant under another name (one made
# in the Portal) fails with RoleAssignmentExists.
$backupServicePrincipalId = ''
$keyVaultRoleGranted = $false
$keyVault = Get-AzResource -ResourceGroupName $vmRg -ResourceType 'Microsoft.KeyVault/vaults' -Name $keyVaultName -ErrorAction SilentlyContinue
if (-not $keyVault) {
    Write-Host "  [WARNING] Key vault '$keyVaultName' not found in '$vmRg' - no Key Vault role for Azure Backup." -ForegroundColor Yellow
    Write-Host "    Lab 3.2 creates it; an ADE-encrypted VM cannot be backed up without the role." -ForegroundColor Gray
} else {
    $servicePrincipal = $null
    $lookupFailed = $false
    try {
        # Microsoft Graph: the app's object ID differs per tenant.
        $servicePrincipal = Get-AzADServicePrincipal -ApplicationId $backupManagementServiceAppId -ErrorAction Stop | Select-Object -First 1
    } catch {
        $lookupFailed = $true
        $script:deployFailures++
        Write-Host "  [ERROR] Could not find the Backup Management Service app in Microsoft Entra ID: $_ $(Get-LabGraphSignInHint -Client Az)" -ForegroundColor Red
    }
    if ($servicePrincipal) {
        try {
            $held = @(Get-LabArmRoleAssignment -Scope $keyVault.ResourceId -PrincipalId $servicePrincipal.Id |
                Where-Object {
                    $_.RoleDefinitionId -eq $keyVaultAdministratorRoleId -and
                    ($_.Scope -eq $keyVault.ResourceId -or $keyVault.ResourceId -like "$($_.Scope)/*")
                })
            if ($held.Count -gt 0) {
                Write-Host "  [KEEP]   Backup Management Service holds Key Vault Administrator on $keyVaultName; the template grants none." -ForegroundColor Gray
            } else {
                $backupServicePrincipalId = $servicePrincipal.Id
                $keyVaultRoleGranted = $true
                Write-Host "  ✓ The template grants Backup Management Service Key Vault Administrator on $keyVaultName" -ForegroundColor Green
            }
        } catch {
            $script:deployFailures++
            Write-Host "  [ERROR] Could not read the role assignments on '$keyVaultName': $_" -ForegroundColor Red
        }
    } elseif (-not $lookupFailed) {
        $script:deployFailures++
        Write-Host "  [ERROR] The Backup Management Service app ($backupManagementServiceAppId) has no service principal in this tenant." -ForegroundColor Red
    }
}

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
    parBackupManagementServicePrincipalId = $backupServicePrincipalId
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
    Write-Host "    Alert rule:      $($deployment.Outputs['outAlertProcessingRuleId'].Value)"

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
    Write-Host "`n[6/7] Ensuring VM backup policy (SkyCraft-Daily-Prod)..." -ForegroundColor Yellow
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

    # SkyCraft-Blob-Policy is created by New-LabBlobBackup.ps1, the script the guide has the learner
    # run (issue #306), so the policy has one definition.
    Write-Host "  SkyCraft-Blob-Policy: created by New-LabBlobBackup.ps1 (next step)" -ForegroundColor Gray

    # ── Enable VM Backup Protection (idempotent, dev VMs only) ────────────
    # The automated cycle deploys the dev VMs only; no prod VM exists.
    # A dev VM that is absent (Lab 3.2 not run) is a WARN and a skip, not a failure.
    Write-Host "`n[7/7] Ensuring VM backup protection for $($vmNames -join ', ')..." -ForegroundColor Yellow
    foreach ($vmName in $vmNames) {
        $vm = $null
        $vmItem = $null
        $job = $null
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

        if ($vmItem) {
            Write-Host "  ✓ $vmName is already protected (policy: $($vmItem.ProtectionPolicyName))" -ForegroundColor Green
        } else {
            Write-Host "  Enabling backup protection for $vmName..." -ForegroundColor Gray
            $vm = Get-AzVM -Name $vmName -ResourceGroupName $vmRg -ErrorAction SilentlyContinue
            if (-not $vm) {
                Write-Host "  [WARNING] VM '$vmName' not found in '$vmRg'. Skipping VM-backup steps." -ForegroundColor Yellow
                Write-Host "  Complete Lab 3.2 (dev VM) first and re-run this script if VM backup is required." -ForegroundColor Yellow
            } else {
                try {
                    if ($keyVaultRoleGranted) {
                        # The role took effect within two minutes live (#368); before that Enable fails with 400198.
                        Write-Host "  Waiting 120 seconds for the Key Vault role to take effect..." -ForegroundColor Gray
                        Start-Sleep -Seconds 120
                        $keyVaultRoleGranted = $false
                    }
                    $protectionPolicy = Get-AzRecoveryServicesBackupProtectionPolicy -Name 'SkyCraft-Daily-Prod' -VaultId $vault.ID
                    $enableJob = Enable-AzRecoveryServicesBackupProtection `
                        -ResourceGroupName $vmRg `
                        -Name $vmName `
                        -Policy $protectionPolicy `
                        -VaultId $vault.ID
                    if ($enableJob -and $enableJob.Status -eq 'Failed') {
                        $enableDetail = Get-AzRecoveryServicesBackupJobDetail -JobId $enableJob.JobId -VaultId $vault.ID -ErrorAction SilentlyContinue
                        $reason = @($enableDetail.ErrorDetails | ForEach-Object { "$($_.ErrorCode): $($_.ErrorMessage)" }) -join '; '
                        throw "ConfigureBackup job failed: $reason (400198 UserErrorKeyVaultPermissionsNotConfigured: the Key Vault role is missing or not active yet)"
                    }
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
                    Write-Host "  [ERROR] Could not enable VM backup for ${vmName}: $_" -ForegroundColor Red
                    Write-Host "    If this is UserErrorThisVMBackupIsSupportedUsingEnhancedPolicy, the vault still" -ForegroundColor Gray
                    Write-Host "    holds a Standard 'SkyCraft-Daily-Prod' from an earlier run - see step [6/7]." -ForegroundColor Gray
                    Write-Host "    Enable manually: Enable-AzRecoveryServicesBackupProtection (Step 5.2.3)" -ForegroundColor Gray
                }
            }
        }

        # ── Initial backup and its outcome ────────────────────────────────────
        # Protection alone proves nothing: after Lab 1.3 every job used to fail in seconds with
        # UserErrorRequestDisallowedByPolicy while this script reported success (#184). So a VM
        # without a recovery point gets an on-demand backup on every run - not only the run that
        # enabled protection, or a failed first job would never be retried - and the job is watched
        # until its Take Snapshot phase completes or fails. The vault transfer after it is not waited for.
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
                    # Watch Take Snapshot, not the whole job: the snapshot is the recovery point Step 5.2.10
                    # needs, and the vault transfer after it takes far longer (#366).
                    $deadline = (Get-Date).AddMinutes($snapshotWatchMinutes)
                    $jobId = $job.JobId
                    $snapshotStatus = ''
                    $detail = $null
                    Write-Host "  Watching the Take Snapshot phase of job $jobId (up to $snapshotWatchMinutes minutes)..." -ForegroundColor Gray
                    while ($true) {
                        $job = Get-AzRecoveryServicesBackupJob -JobId $jobId -VaultId $vault.ID -ErrorAction SilentlyContinue
                        $detail = Get-AzRecoveryServicesBackupJobDetail -JobId $jobId -VaultId $vault.ID -ErrorAction SilentlyContinue
                        $snapshotStatus = "$((@($detail.SubTasks) | Where-Object { $_.Name -eq 'Take Snapshot' } | Select-Object -First 1).Status)"
                        if (-not $job -or $job.Status -ne 'InProgress' -or $snapshotStatus -in @('Completed', 'Failed')) { break }
                        if ((Get-Date) -ge $deadline) { break }
                        Start-Sleep -Seconds 30
                    }
                    $snapshotLabel = if ($snapshotStatus) { $snapshotStatus } else { 'not reported' }

                    if (-not $job) {
                        $script:deployFailures++
                        Write-Host "  [ERROR] Lost track of backup job $jobId - check Backup jobs in the vault" -ForegroundColor Red
                    } elseif ($job.Status -eq 'Failed' -or $snapshotStatus -eq 'Failed') {
                        $script:deployFailures++
                        Write-Host "  [ERROR] Backup job for $vmName failed (Take Snapshot: $snapshotLabel):" -ForegroundColor Red
                        foreach ($err in @($detail.ErrorDetails)) {
                            if ($err) { Write-Host "    $($err.ErrorCode): $($err.ErrorMessage)" -ForegroundColor Red }
                        }
                        Write-Host "    400211 (UserErrorRequestDisallowedByPolicy) means an Azure Policy deny refused a" -ForegroundColor Gray
                        Write-Host "    resource Azure Backup creates for the snapshot - see lab-guide-5.2.md, Troubleshooting, Issue 2." -ForegroundColor Gray
                    } elseif ($snapshotStatus -eq 'Completed' -or $job.Status -in @('Completed', 'CompletedWithWarnings')) {
                        Write-Host "  ✓ Take Snapshot completed for $vmName - it has a recovery point; job status: $($job.Status)" -ForegroundColor Green
                    } else {
                        $script:deployFailures++
                        Write-Host "  [ERROR] Take Snapshot for $vmName did not finish within $snapshotWatchMinutes minutes (Take Snapshot: $snapshotLabel, job: $($job.Status))." -ForegroundColor Red
                        Write-Host "    The job may still succeed: check Backup jobs in the vault, then run Test-Lab.ps1." -ForegroundColor Gray
                    }
                }
            } catch {
                $script:deployFailures++
                Write-Host "  [ERROR] Could not run the initial backup of ${vmName}: $_" -ForegroundColor Red
                Write-Host "    Trigger it manually: vault -> Backup items -> Azure Virtual Machine -> Backup now (Step 5.2.3)" -ForegroundColor Gray
            }
        } elseif ($vm) {
            # Protection was just enabled, but the vault does not list the item yet.
            Write-Host "  [WARNING] $vmName is protected but not listed as a backup item yet - no initial backup was triggered." -ForegroundColor Yellow
            Write-Host "    Re-run this script in a few minutes, or use Backup now (Step 5.2.3)." -ForegroundColor Gray
        }
    }

    Write-Host "`n  Next Steps:" -ForegroundColor Cyan
    Write-Host "    1. Run .\New-LabBlobBackup.ps1 to create SkyCraft-Blob-Policy and protect prodskycraftswcsa" -ForegroundColor Gray
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
