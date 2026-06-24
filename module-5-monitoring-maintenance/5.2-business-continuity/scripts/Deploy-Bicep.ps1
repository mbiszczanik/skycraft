<#
.SYNOPSIS
    Deploys Lab 5.2 Business Continuity & Disaster Recovery infrastructure using Bicep.

.DESCRIPTION
    Deploys the Lab 5.2 Bicep templates to Azure, including:
    - Recovery Services Vault (platform-skycraft-swc-rsv) with LRS redundancy
    - VM Backup Policy (SkyCraft-Daily-Prod): daily 02:00 UTC, 30-day retention
    - Backup Vault (platform-skycraft-swc-bv) with LRS and system-assigned identity
    - Blob Backup Policy (SkyCraft-Blob-Policy): 30-day operational retention
    - Diagnostic settings for both vaults -> Log Analytics Workspace
    - VM backup protection enabled on prod-skycraft-swc-auth-vm

    After deployment:
    1. Run .\New-LabBlobBackup.ps1 to assign RBAC roles and configure blob
       protection on prodskycraftswcsa.
    2. Configure Azure Site Recovery (ASR) via the Azure Portal (Step 5.2.8)
       — ASR replication requires portal-based setup.

    Prerequisites: Lab 3.2 (VM) and Lab 5.1 (Log Analytics Workspace) must be deployed.

.PARAMETER WhatIf
    Run deployment in what-if mode (dry run).

.EXAMPLE
    .\Deploy-Bicep.ps1

.EXAMPLE
    .\Deploy-Bicep.ps1 -WhatIf

.NOTES
    Project: SkyCraft
    Lab: 5.2 - Business Continuity & Disaster Recovery
    Version: 1.0.0
    Date: 2026-04-06
#>

#Requires -Version 7.0

[CmdletBinding()]
param(
    [Parameter()]
    [switch]$WhatIf
)

$ErrorActionPreference = 'Stop'

$scriptPath     = Split-Path -Parent $MyInvocation.MyCommand.Path
$templatePath   = Join-Path $scriptPath '..\bicep\main.bicep'
$location       = 'swedencentral'
$platformRg     = 'platform-skycraft-swc-rg'
$workspaceName  = 'platform-skycraft-swc-law'
$deploymentName = "lab52-$(Get-Date -Format 'yyyyMMdd-HHmmss')"

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  Lab 5.2 - BCDR Deployment" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# ── [1/7] Validate prerequisites ──────────────────────────────────────────
Write-Host "[1/7] Validating prerequisites..." -ForegroundColor Yellow

$account = az account show --output json 2>$null | ConvertFrom-Json
if (-not $account) {
    Write-Host "  [ERROR] Not logged into Azure CLI. Run 'az login' first." -ForegroundColor Red
    exit 1
}
Write-Host "  ✓ Logged in as: $($account.user.name)" -ForegroundColor Green

az config set extension.use_dynamic_install=yes_without_prompt --only-show-errors | Out-Null

# Register required resource providers (idempotent)
foreach ($ns in @('Microsoft.RecoveryServices', 'Microsoft.DataProtection')) {
    $state = az provider show --namespace $ns --query registrationState --output tsv 2>$null
    if ($state -ne 'Registered') {
        Write-Host "  Registering provider: $ns..." -ForegroundColor Gray
        az provider register --namespace $ns --output none
        Write-Host "  ✓ Registered: $ns" -ForegroundColor Green
    }
}

# ── [2/7] Resolve resource IDs ────────────────────────────────────────────
Write-Host "`n[2/7] Resolving existing resource IDs..." -ForegroundColor Yellow

$platformRgExists = az group show --name $platformRg --output json 2>$null | ConvertFrom-Json
if (-not $platformRgExists) {
    Write-Host "  [ERROR] Resource group '$platformRg' not found. Complete earlier labs first." -ForegroundColor Red
    exit 1
}
Write-Host "  ✓ Platform RG found: $platformRg" -ForegroundColor Green

$workspaceJson = az monitor log-analytics workspace show `
    --workspace-name $workspaceName `
    --resource-group $platformRg `
    --output json 2>$null | ConvertFrom-Json
if (-not $workspaceJson) {
    Write-Host "  [ERROR] Log Analytics Workspace '$workspaceName' not found. Deploy Lab 5.1 first." -ForegroundColor Red
    exit 1
}
$workspaceId = $workspaceJson.id
Write-Host "  ✓ Log Analytics Workspace found: $workspaceName" -ForegroundColor Green

# ── [3/7] Display deployment configuration ────────────────────────────────
Write-Host "`n[3/7] Deployment Configuration:" -ForegroundColor Yellow
Write-Host "  Platform RG:     $platformRg"
Write-Host "  Workspace:       $workspaceName"
Write-Host "  Location:        $location"
Write-Host "  Template:        $templatePath"
Write-Host "  Deployment Name: $deploymentName"

if (-not $WhatIf) {
    $confirm = Read-Host "`nProceed with deployment? (y/N)"
    if ($confirm -ne 'y') {
        Write-Host "Deployment cancelled." -ForegroundColor Yellow
        exit 0
    }
}

# ── [4/7] Run Bicep deployment ────────────────────────────────────────────
Write-Host "`n[4/7] Running Bicep deployment..." -ForegroundColor Yellow

$commonParams = @(
    '--name', $deploymentName,
    '--location', $location,
    '--template-file', $templatePath,
    '--parameters', "parWorkspaceId=$workspaceId"
)

if ($WhatIf) {
    Write-Host "  Running in what-if mode (dry run)..." -ForegroundColor Cyan
    $deployArgs = @('deployment', 'sub', 'what-if') + $commonParams
} else {
    $deployArgs = @('deployment', 'sub', 'create') + $commonParams + @('--output', 'json')
}

if ($WhatIf) {
    $result = az @deployArgs 2>&1   # keep stderr visible so what-if diff is complete
} else {
    $result = az @deployArgs 2>$null  # suppress az CLI warnings so ConvertFrom-Json receives clean JSON
}
$exitCode = $LASTEXITCODE

if ($exitCode -ne 0) {
    Write-Host "`n  [ERROR] Deployment failed with exit code $exitCode" -ForegroundColor Red
    Write-Host $result -ForegroundColor Red
    exit $exitCode
}

if ($WhatIf) {
    Write-Host $result
    Write-Host "`n  What-if completed. Review changes above." -ForegroundColor Cyan
} else {
    $deployment = $result | ConvertFrom-Json
    Write-Host "  ✓ Vaults deployed successfully!" -ForegroundColor Green
    $rsvId = $deployment.properties.outputs.outRsvId.value
    $bvPrincipalId = $deployment.properties.outputs.outBvPrincipalId.value

    Write-Host "    RSV ID:          $rsvId"
    Write-Host "    Backup Vault ID: $($deployment.properties.outputs.outBvId.value)"
    Write-Host "    BV Principal ID: $bvPrincipalId"

    # ── Set RSV storage redundancy to LRS (idempotent) ────────────────────
    Write-Host "`n[5/7] Ensuring RSV storage redundancy is LocallyRedundant..." -ForegroundColor Yellow
    $rsvProps = az backup vault backup-properties show `
        --resource-group $platformRg `
        --name 'platform-skycraft-swc-rsv' `
        --output json 2>$null | ConvertFrom-Json
    $currentRedundancy = $rsvProps.properties.storageModelType
    $isLocked = $rsvProps.properties.storageTypeState -eq 'Locked'

    if ($currentRedundancy -eq 'LocallyRedundant') {
        Write-Host "  ✓ Redundancy already set to LocallyRedundant$(if ($isLocked) { ' (Locked — first backup has run)' })" -ForegroundColor Green
    } else {
        Write-Host "  Setting redundancy to LocallyRedundant..." -ForegroundColor Gray
        try {
            az backup vault backup-properties set `
                --resource-group $platformRg `
                --name 'platform-skycraft-swc-rsv' `
                --backup-storage-redundancy LocallyRedundant `
                --output none
            Write-Host "  ✓ Redundancy set to LocallyRedundant" -ForegroundColor Green
        } catch {
            Write-Host "  [WARNING] Could not set redundancy (vault may already be in use): $_" -ForegroundColor Yellow
        }
    }

    # ── Create VM Backup Policy (idempotent) ──────────────────────────────
    Write-Host "`n[6/7] Ensuring backup policies (SkyCraft-Daily-Prod, SkyCraft-Blob-Policy)..." -ForegroundColor Yellow
    $existingRsvPolicy = az backup policy show `
        --resource-group $platformRg `
        --vault-name 'platform-skycraft-swc-rsv' `
        --name 'SkyCraft-Daily-Prod' `
        --output json 2>$null | ConvertFrom-Json

    if ($existingRsvPolicy) {
        Write-Host "  ✓ Policy 'SkyCraft-Daily-Prod' already exists in RSV" -ForegroundColor Green
    } else {
        Write-Host "  Creating 'SkyCraft-Daily-Prod' backup policy..." -ForegroundColor Gray
        $rsvPolicyJson = @'
{
  "policyType": "V2",
  "instantRpRetentionRangeInDays": 2,
  "schedulePolicy": {
    "schedulePolicyType": "SimpleSchedulePolicyV2",
    "scheduleRunFrequency": "Daily",
    "dailySchedule": {
      "scheduleRunTimes": ["2024-01-01T02:00:00+00:00"]
    }
  },
  "retentionPolicy": {
    "retentionPolicyType": "LongTermRetentionPolicy",
    "dailySchedule": {
      "retentionTimes": ["2024-01-01T02:00:00+00:00"],
      "retentionDuration": { "count": 30, "durationType": "Days" }
    }
  },
  "timeZone": "UTC",
  "backupManagementType": "AzureIaasVM",
  "workLoadType": "VM"
}
'@
        $tempPolicyFile = Join-Path $env:TEMP 'rsv-policy.json'
        $rsvPolicyJson | Set-Content -Path $tempPolicyFile -Encoding utf8
        try {
            az backup policy set `
                --resource-group $platformRg `
                --vault-name 'platform-skycraft-swc-rsv' `
                --name 'SkyCraft-Daily-Prod' `
                --policy "@$tempPolicyFile" `
                --output none
            Write-Host "  ✓ Policy 'SkyCraft-Daily-Prod' created" -ForegroundColor Green
        } catch {
            Write-Host "  [ERROR] Failed to create RSV policy: $_" -ForegroundColor Red
        }
        Remove-Item -Path $tempPolicyFile -ErrorAction SilentlyContinue
    }

    # ── Create Blob Backup Policy (idempotent) ────────────────────────────
    $existingBlobPolicy = az dataprotection backup-policy show `
        --resource-group $platformRg `
        --vault-name 'platform-skycraft-swc-bv' `
        --name 'SkyCraft-Blob-Policy' `
        --output json 2>$null | ConvertFrom-Json

    if ($existingBlobPolicy) {
        Write-Host "  ✓ Policy 'SkyCraft-Blob-Policy' already exists in Backup Vault" -ForegroundColor Green
    } else {
        Write-Host "  Creating 'SkyCraft-Blob-Policy' blob backup policy..." -ForegroundColor Gray
        $blobPolicyJson = @'
{
  "datasourceTypes": ["Microsoft.Storage/storageAccounts/blobServices"],
  "objectType": "BackupPolicy",
  "policyRules": [
    {
      "isDefault": true,
      "lifecycles": [
        {
          "deleteAfter": {
            "duration": "P30D",
            "objectType": "AbsoluteDeleteOption"
          },
          "sourceDataStore": {
            "dataStoreType": "OperationalStore",
            "objectType": "DataStoreInfoBase"
          },
          "targetDataStoreCopySettings": []
        }
      ],
      "name": "Default",
      "objectType": "AzureRetentionRule"
    }
  ]
}
'@
        $tempBlobFile = Join-Path $env:TEMP 'bv-policy.json'
        $blobPolicyJson | Set-Content -Path $tempBlobFile -Encoding utf8
        try {
            az dataprotection backup-policy create `
                --resource-group $platformRg `
                --vault-name 'platform-skycraft-swc-bv' `
                --name 'SkyCraft-Blob-Policy' `
                --policy "@$tempBlobFile" `
                --output none
            Write-Host "  ✓ Policy 'SkyCraft-Blob-Policy' created" -ForegroundColor Green
        } catch {
            Write-Host "  [ERROR] Failed to create Blob policy: $_" -ForegroundColor Red
        }
        Remove-Item -Path $tempBlobFile -ErrorAction SilentlyContinue
    }

    # ── Enable VM Backup Protection (idempotent) ──────────────────────────
    Write-Host "`n[7/7] Ensuring VM backup protection for prod-skycraft-swc-auth-vm..." -ForegroundColor Yellow
    $vmItems = az backup item list `
        --resource-group $platformRg `
        --vault-name 'platform-skycraft-swc-rsv' `
        --backup-management-type AzureIaasVM `
        --output json 2>$null | ConvertFrom-Json
    $vmItem = $vmItems | Where-Object { $_.properties.friendlyName -eq 'prod-skycraft-swc-auth-vm' }

    if ($vmItem) {
        Write-Host "  ✓ prod-skycraft-swc-auth-vm is already protected (policy: $($vmItem.properties.policyName))" -ForegroundColor Green
    } else {
        Write-Host "  Enabling backup protection for prod-skycraft-swc-auth-vm..." -ForegroundColor Gray
        $vmId = az vm show `
            --name 'prod-skycraft-swc-auth-vm' `
            --resource-group 'prod-skycraft-swc-rg' `
            --query id --output tsv 2>$null
        if (-not $vmId) {
            Write-Host "  [WARNING] VM 'prod-skycraft-swc-auth-vm' not found in 'prod-skycraft-swc-rg'. Skipping backup enablement." -ForegroundColor Yellow
            Write-Host "  Complete Lab 3.2 first and re-run this script." -ForegroundColor Yellow
        } else {
            try {
                az backup protection enable-for-vm `
                    --resource-group $platformRg `
                    --vault-name 'platform-skycraft-swc-rsv' `
                    --vm $vmId `
                    --policy-name 'SkyCraft-Daily-Prod' `
                    --output none 2>$null
                Write-Host "  ✓ VM backup protection enabled for prod-skycraft-swc-auth-vm" -ForegroundColor Green
                Write-Host "  Triggering initial on-demand backup..." -ForegroundColor Gray
                $containerName = az backup container show `
                    --resource-group $platformRg `
                    --vault-name 'platform-skycraft-swc-rsv' `
                    --name "IaasVMContainer;iaasvmcontainerv2;prod-skycraft-swc-rg;prod-skycraft-swc-auth-vm" `
                    --backup-management-type AzureIaasVM `
                    --query name --output tsv 2>$null
                if ($containerName) {
                    az backup protection backup-now `
                        --resource-group $platformRg `
                        --vault-name 'platform-skycraft-swc-rsv' `
                        --container-name $containerName `
                        --item-name "VM;iaasvmcontainerv2;prod-skycraft-swc-rg;prod-skycraft-swc-auth-vm" `
                        --retain-until (Get-Date).AddDays(30).ToString('dd-MM-yyyy') `
                        --output none 2>$null
                    Write-Host "  ✓ Initial backup triggered (runs in background — check Backup jobs in portal)" -ForegroundColor Green
                }
            } catch {
                Write-Host "  [WARNING] Could not enable VM backup: $_" -ForegroundColor Yellow
                Write-Host "  Enable manually: az backup protection enable-for-vm (Step 5.2.3)" -ForegroundColor Gray
            }
        }
    }

    Write-Host "`n  Next Steps:" -ForegroundColor Cyan
    Write-Host "    1. Run .\New-LabBlobBackup.ps1 to configure blob protection on prodskycraftswcsa" -ForegroundColor Gray
    Write-Host "    2. Configure Azure Site Recovery via Azure Portal (Step 5.2.8)" -ForegroundColor Gray
    Write-Host "    3. Run .\Test-Lab.ps1 to validate deployment" -ForegroundColor Gray
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  Deployment Complete" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan
