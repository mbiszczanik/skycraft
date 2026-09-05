<#
.SYNOPSIS
    Deploys Lab 5.2 Business Continuity & Disaster Recovery infrastructure using Bicep.

.DESCRIPTION
    Deploys the Lab 5.2 Bicep templates to Azure, including:
    - Recovery Services Vault (platform-skycraft-swc-rsv) with LRS redundancy
    - VM Backup Policy (SkyCraft-Daily-Prod): Enhanced subtype, daily 02:00 UTC,
      30-day retention, 2-day instant restore. Enhanced is required because Azure
      defaults VM deployments to Trusted Launch, which a Standard policy cannot protect.
    - Backup Vault (platform-skycraft-swc-bv) with LRS and system-assigned identity
    - Blob Backup Policy (SkyCraft-Blob-Policy): 30-day operational retention
    - Diagnostic settings for both vaults -> Log Analytics Workspace
    - VM backup protection enabled on dev-skycraft-swc-auth-vm (when present)

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

.EXAMPLE
    .\Deploy-Bicep.ps1

.EXAMPLE
    .\Deploy-Bicep.ps1 -WhatIf

.EXAMPLE
    .\Deploy-Bicep.ps1 -Force

.NOTES
    Project: SkyCraft
    Lab: 5.2 - Business Continuity & Disaster Recovery
    Version: 1.0.0
    Date: 2026-04-06
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

$scriptPath     = Split-Path -Parent $MyInvocation.MyCommand.Path
$templatePath   = Join-Path $scriptPath '..\bicep\main.bicep'
$location       = 'swedencentral'
$platformRg     = 'platform-skycraft-swc-rg'
$workspaceName  = 'platform-skycraft-swc-law'
$vmName         = 'dev-skycraft-swc-auth-vm'
$vmRg           = 'dev-skycraft-swc-rg'
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
    $Host.SetShouldExit(1)
    exit 1
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
    $Host.SetShouldExit(1)
    exit 1
}
Write-Host "  ✓ Platform RG found: $platformRg" -ForegroundColor Green

$workspace = Get-AzOperationalInsightsWorkspace -ResourceGroupName $platformRg -Name $workspaceName -ErrorAction SilentlyContinue
if (-not $workspace) {
    Write-Host "  [ERROR] Log Analytics Workspace '$workspaceName' not found. Deploy Lab 5.1 first." -ForegroundColor Red
    $Host.SetShouldExit(1)
    exit 1
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
    $Host.SetShouldExit(1)
    exit 1
}

if ($WhatIf) {
    $result
    Write-Host "`n  What-if completed. Review changes above." -ForegroundColor Cyan
} else {
    if ($deployment.ProvisioningState -ne 'Succeeded') {
        Write-Host "`n  [FAILED] Deployment finished with state: $($deployment.ProvisioningState)" -ForegroundColor Red
        $Host.SetShouldExit(1)
        exit 1
    }

    Write-Host "  ✓ Vaults deployed successfully!" -ForegroundColor Green
    $rsvId = $deployment.Outputs['outRsvId'].Value
    $bvPrincipalId = $deployment.Outputs['outBvPrincipalId'].Value

    Write-Host "    RSV ID:          $rsvId"
    Write-Host "    Backup Vault ID: $($deployment.Outputs['outBvId'].Value)"
    Write-Host "    BV Principal ID: $bvPrincipalId"

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

            New-AzRecoveryServicesBackupProtectionPolicy `
                -Name 'SkyCraft-Daily-Prod' `
                -WorkloadType AzureVM `
                -BackupManagementType AzureVM `
                -SchedulePolicy $schedulePolicy `
                -RetentionPolicy $retentionPolicy `
                -VaultId $vault.ID | Out-Null

            # Enhanced keeps instant-restore snapshots for 7 days by default, where Standard kept
            # 2. Snapshots are billed, so pull it back to 2 and keep the cost estimate in
            # ARCHITECTURE.md honest.
            $createdPolicy = Get-AzRecoveryServicesBackupProtectionPolicy -Name 'SkyCraft-Daily-Prod' -VaultId $vault.ID
            $createdPolicy.SnapshotRetentionInDays = 2
            Set-AzRecoveryServicesBackupProtectionPolicy -Policy $createdPolicy -VaultId $vault.ID | Out-Null

            Write-Host "  ✓ Policy 'SkyCraft-Daily-Prod' created (Enhanced, daily 02:00 UTC, 30-day retention)" -ForegroundColor Green
        } catch {
            $script:deployFailures++
            Write-Host "  [ERROR] Failed to create RSV policy: $_" -ForegroundColor Red
        }
    }

    # ── Create Blob Backup Policy (idempotent) ────────────────────────────
    $existingBlobPolicy = Get-AzDataProtectionBackupPolicy `
        -ResourceGroupName $platformRg `
        -VaultName 'platform-skycraft-swc-bv' `
        -Name 'SkyCraft-Blob-Policy' `
        -ErrorAction SilentlyContinue

    if ($existingBlobPolicy) {
        Write-Host "  ✓ Policy 'SkyCraft-Blob-Policy' already exists in Backup Vault" -ForegroundColor Green
    } else {
        Write-Host "  Creating 'SkyCraft-Blob-Policy' blob backup policy (30-day operational retention)..." -ForegroundColor Gray
        try {
            $blobPolicyTemplate = Get-AzDataProtectionPolicyTemplate -DatasourceType AzureBlob
            # Override the template default: set operational (continuous) retention to 30 days
            $blobLifecycle = New-AzDataProtectionRetentionLifeCycleClientObject `
                -SourceDataStore OperationalStore `
                -SourceRetentionDurationType Days `
                -SourceRetentionDurationCount 30
            $blobPolicyTemplate = Edit-AzDataProtectionPolicyRetentionRuleClientObject `
                -Policy $blobPolicyTemplate `
                -Name Default `
                -LifeCycles $blobLifecycle `
                -IsDefault $true
            # Current Az.DataProtection templates ship a vaulted 'BackupWeekly' AzureBackupRule
            # alongside the retention rule. This lab wants operational (continuous) backup only,
            # so the backup rule is dropped - leaving it in stores a policy whose backup rule
            # writes to VaultStore while its only retention lifecycle targets OperationalStore,
            # and Azure then rejects every backup instance built from it with
            # 'UserErrorInvalidRequestParameter: Parameter NO_PARAM in request is invalid'.
            $blobPolicyTemplate.PolicyRule = @(
                $blobPolicyTemplate.PolicyRule | Where-Object { $_.ObjectType -ne 'AzureBackupRule' }
            )
            New-AzDataProtectionBackupPolicy `
                -ResourceGroupName $platformRg `
                -VaultName 'platform-skycraft-swc-bv' `
                -Name 'SkyCraft-Blob-Policy' `
                -Policy $blobPolicyTemplate | Out-Null
            Write-Host "  ✓ Policy 'SkyCraft-Blob-Policy' created (30-day retention)" -ForegroundColor Green
        } catch {
            $script:deployFailures++
            Write-Host "  [ERROR] Failed to create Blob policy: $_" -ForegroundColor Red
        }
    }

    # ── Enable VM Backup Protection (idempotent, dev VM only) ─────────────
    # The automated cycle deploys a standalone dev VM only; no prod VM exists.
    # If the dev VM is absent (Lab 3.2 not run), WARN and skip — do not fail.
    Write-Host "`n[7/7] Ensuring VM backup protection for $vmName..." -ForegroundColor Yellow
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
                $protectionPolicy = Get-AzRecoveryServicesBackupProtectionPolicy -Name 'SkyCraft-Daily-Prod' -VaultId $vault.ID
                Enable-AzRecoveryServicesBackupProtection `
                    -ResourceGroupName $vmRg `
                    -Name $vmName `
                    -Policy $protectionPolicy `
                    -VaultId $vault.ID | Out-Null
                Write-Host "  ✓ VM backup protection enabled for $vmName" -ForegroundColor Green
                Write-Host "  Triggering initial on-demand backup..." -ForegroundColor Gray
                $container = Get-AzRecoveryServicesBackupContainer `
                    -ContainerType AzureVM `
                    -FriendlyName $vmName `
                    -VaultId $vault.ID `
                    -ErrorAction SilentlyContinue
                if ($container) {
                    $backupItem = Get-AzRecoveryServicesBackupItem `
                        -Container $container `
                        -WorkloadType AzureVM `
                        -VaultId $vault.ID
                    Backup-AzRecoveryServicesBackupItem `
                        -Item $backupItem `
                        -VaultId $vault.ID `
                        -ExpiryDateTimeUTC ((Get-Date).AddDays(30).ToUniversalTime()) | Out-Null
                    Write-Host "  ✓ Initial backup triggered (runs in background — check Backup jobs in portal)" -ForegroundColor Green
                }
            } catch {
                $script:deployFailures++
                Write-Host "  [ERROR] Could not enable VM backup: $_" -ForegroundColor Red
                Write-Host "    If this is UserErrorThisVMBackupIsSupportedUsingEnhancedPolicy, the vault still" -ForegroundColor Gray
                Write-Host "    holds a Standard 'SkyCraft-Daily-Prod' from an earlier run - see step [6/7]." -ForegroundColor Gray
                Write-Host "    Enable manually: Enable-AzRecoveryServicesBackupProtection (Step 5.2.3)" -ForegroundColor Gray
            }
        }
    }

    Write-Host "`n  Next Steps:" -ForegroundColor Cyan
    Write-Host "    1. Run .\New-LabBlobBackup.ps1 to configure blob protection on prodskycraftswcsa" -ForegroundColor Gray
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
    $Host.SetShouldExit(1)
    exit 1
}

Write-Host "  Deployment Complete" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan
