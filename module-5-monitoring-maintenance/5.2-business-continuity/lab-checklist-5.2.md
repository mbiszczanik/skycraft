# Lab 5.2 Completion Checklist

> **Purpose**: This checklist verifies correct implementation of Lab 5.2: Business Continuity & Disaster Recovery. Use it to confirm all backup and recovery resources are properly configured before proceeding to Lab 5.3.

---

## ✅ Recovery Services Vault Verification

### Vault Configuration

- [x] Vault name: `platform-skycraft-swc-rsv`
- [x] Location: **Sweden Central**
- [x] Resource group: `platform-skycraft-swc-rg`
- [x] Storage replication type: **Locally-redundant (LRS)**, set at creation on the **Redundancy** tab
- [x] Soft delete: **AlwaysON** (platform-enforced by Azure Backup "secure by default"; only the retention, 14 days, is chosen at creation)

### Tags

- [x] Tag: `Project` = `SkyCraft`
- [x] Tag: `Environment` = `Platform`
- [x] Tag: `CostCenter` = `MSDN`
- [x] Tag: `Owner` = `mbiszczanik`

---

## ✅ Backup Policy Verification

### VM Backup Policy

- [x] Policy name: `SkyCraft-Daily-Prod`
- [x] Policy sub-type: **Enhanced** (required for Trusted Launch VMs; cannot be changed later)
- [x] Backup frequency: **Daily**
- [x] Backup time: **02:00 AM UTC**
- [x] Instant Restore retention: **2 days**
- [x] Azure Backup Resource Group: name `platform-skycraft-swc-rpc`, suffix `-rg`
- [x] Daily backup retention: **30 days** (the form's default is 180)

### Instant-Restore Snapshot Resource Group

- [x] Resource group `platform-skycraft-swc-rpc1-rg` in **Sweden Central**
- [x] Tags: `Project` = `SkyCraft`, `Environment` = `Platform`, `CostCenter` = `MSDN`, `Owner` set
- [x] No resource lock on the group (Azure Backup deletes expired snapshots from it)
- [x] Restore point collections `AzureBackup_<vm>_<n>` in the group carry `Project` = `SkyCraft` (inherited through Lab 1.3's `Inherit-Project-Tag`)

### Blob Backup Policy

- [x] Policy name: `SkyCraft-Blob-Policy`, created by `New-LabBlobBackup.ps1` (not in the Portal)
- [x] Operational backup only: one retention rule, **30 days** in the OperationalStore
- [x] No vaulted backup rule (no Azure Backup charge)
- [x] Associated vault: `platform-skycraft-swc-bv`

---

## ✅ Protected Items Verification

### Key Vault Access for Encrypted VM Backup

- [x] Microsoft Entra app **Backup Management Service** holds **Key Vault Administrator** on `dev-skycraft-swc-kv`
- [x] Granted before *Enable backup* of the ADE-encrypted `dev-skycraft-swc-auth-vm`

### VM Backup

- [x] VMs `dev-skycraft-swc-auth-vm` and `dev-skycraft-swc-world-vm` listed under **Backup items** → Azure Virtual Machine
- [x] Policy assigned to both: `SkyCraft-Daily-Prod`
- [x] Initial backup of each: **Take Snapshot** sub-task **Completed**; job **Completed** or **In progress**, never **Failed** (a failure here is Troubleshooting, Issues 2 and 4 in the lab guide)
- [x] Last backup status: **Success** (once completed)

### File-Level Recovery

- [ ] File recovery script run on `dev-skycraft-swc-world-vm` from `/root/flr`: `Connection succeeded!`
- [ ] `/root/flr/<vm>-<time>/Volume1/opt/skycraft/flr-marker.txt` read back
- [ ] **Unmount Disks** done on the File Recovery pane

---

## ✅ Backup Vault Verification

### Vault Configuration

- [x] Vault name: `platform-skycraft-swc-bv`
- [x] Location: **Sweden Central**
- [x] Resource group: `platform-skycraft-swc-rg`
- [x] Storage redundancy: **Locally-redundant (LRS)**
- [x] Identity type: **System Assigned**
- [x] Soft delete: **Off** (lab-friction override for cleanup), so created with Az PowerShell or the Bicep: the Portal creates it AlwaysOn, which cannot be undone

### Tags

- [x] Tag: `Project` = `SkyCraft`
- [x] Tag: `Environment` = `Platform`
- [x] Tag: `CostCenter` = `MSDN`
- [x] Tag: `Owner` = `mbiszczanik`

---

## ✅ Azure Site Recovery Verification

### Replication Status

- [ ] VM `dev-skycraft-swc-world-vm` (the unencrypted one) replication status: **Protected**, health **Normal**
- [ ] Running kernel on the VM is on Site Recovery's supported list (`6.8.0-1030-azure` from Lab 3.2's Bicep)
- [ ] Target region: **North Europe**
- [ ] Target resource group `platform-skycraft-neu-asr-rg` created in North Europe with `Project`, `Environment`, `CostCenter` and `Owner`
- [ ] The group holds the Recovery Services vault, the cache storage account (Sweden Central), the target virtual network and the replica disks
- [ ] No `Site-recovery-vault-RG` or `<source group>-asr` group exists

### Test Failover

- [ ] Failover VM size set to the size of the source VM before the test
- [ ] Test failover completed successfully
- [ ] Test VM `dev-skycraft-swc-world-vm-test` booted in North Europe
- [ ] Cleanup of test resources completed (no orphaned VMs)

---

## ✅ Backup Reports Verification

- [ ] Diagnostic setting `rsv-backup-reports-diag` on `platform-skycraft-swc-rsv` → workspace `platform-skycraft-swc-law` (resource-specific categories `CoreAzureBackup`, `AddonAzureBackupJobs`, `AddonAzureBackupPolicy`, `AddonAzureBackupStorage`, `AddonAzureBackupProtectedInstance`, `AzureBackupOperations`; not the legacy `AzureBackupReport`)
- [ ] Diagnostic setting `bv-backup-reports-diag` on `platform-skycraft-swc-bv` → workspace `platform-skycraft-swc-law` (the four `CoreAzureBackup`/`Addon*` categories)
- [ ] Backup Instances report in **Resiliency** → **Reports** shows all protected items (up to 24 h after the settings exist)

---

## ✅ Alert Processing Rule Verification

- [ ] Rule `skycraft-backup-critical-apr` in `platform-skycraft-swc-rg`, enabled
- [ ] Scope: `platform-skycraft-swc-rsv`
- [ ] Filter: **Severity** **Equals** **Sev0** (Critical)
- [ ] Rule type: **Apply action group** with `skycraft-ops-ag` (not **Suppress notifications**)
- [ ] Tags: `Project` = `SkyCraft`, `Environment` = `Platform`, `CostCenter` = `MSDN`, `Owner` set

---

## 🔍 Validation Commands

Run these Az PowerShell commands to validate your lab setup:

### Verify Recovery Services Vault

```powershell
Get-AzRecoveryServicesVault -ResourceGroupName 'platform-skycraft-swc-rg' |
  Where-Object { $_.Name -eq 'platform-skycraft-swc-rsv' } |
  Select-Object Name, Location, @{N='State';E={$_.Properties.ProvisioningState}} |
  Format-Table

# Expected output:
# Name                        Location        State
# ----                        --------        -----
# platform-skycraft-swc-rsv   swedencentral   Succeeded
```

### Verify Backup Policy

```powershell
$vault = Get-AzRecoveryServicesVault -ResourceGroupName 'platform-skycraft-swc-rg' -Name 'platform-skycraft-swc-rsv'
Get-AzRecoveryServicesBackupProtectionPolicy -VaultId $vault.ID -Name 'SkyCraft-Daily-Prod' |
  Select-Object Name, WorkloadType, @{N='Frequency';E={$_.SchedulePolicy.ScheduleRunFrequency}} |
  Format-Table

# Expected output:
# Name                 WorkloadType    Frequency
# ----                 ------------    ---------
# SkyCraft-Daily-Prod  AzureVM         Daily
```

### Verify Protected Items

```powershell
$vault = Get-AzRecoveryServicesVault -ResourceGroupName 'platform-skycraft-swc-rg' -Name 'platform-skycraft-swc-rsv'
$container = Get-AzRecoveryServicesBackupContainer -VaultId $vault.ID -ContainerType AzureVM
Get-AzRecoveryServicesBackupItem -VaultId $vault.ID -Container $container -WorkloadType AzureVM |
  Select-Object Name, ProtectionStatus, LastBackupTime |
  Format-Table

# Expected output:
# Name                           ProtectionStatus  LastBackupTime
# ----                           ----------------  --------------
# dev-skycraft-swc-auth-vm      Healthy           2026-02-27 02:00:00
```

### Verify Backup Vault

```powershell
Get-AzDataProtectionBackupVault -ResourceGroupName 'platform-skycraft-swc-rg' |
  Where-Object { $_.Name -eq 'platform-skycraft-swc-bv' } |
  Select-Object Name, Location, @{N='State';E={$_.Property.ProvisioningState}} |
  Format-Table

# Expected output:
# Name                       Location        State
# ----                       --------        -----
# platform-skycraft-swc-bv   swedencentral   Succeeded
```

### Verify Blob Backup Policy

```powershell
Get-AzDataProtectionBackupPolicy -ResourceGroupName 'platform-skycraft-swc-rg' -VaultName 'platform-skycraft-swc-bv' |
  Where-Object { $_.Name -eq 'SkyCraft-Blob-Policy' } |
  Select-Object Name, @{N='DatasourceType';E={$_.Property.DatasourceTypes[0]}} |
  Format-Table

# Expected output:
# Name                   DatasourceType
# ----                   --------------
# SkyCraft-Blob-Policy   Microsoft.Storage/storageAccounts/blobServices

# The rules: one AzureRetentionRule, OperationalStore, P30D; no AzureBackupRule (vaulted)
$bv = Get-AzDataProtectionBackupVault -ResourceGroupName 'platform-skycraft-swc-rg' -VaultName 'platform-skycraft-swc-bv'
(Get-AzResource -ResourceId "$($bv.Id)/backupPolicies/SkyCraft-Blob-Policy" -ApiVersion '2023-01-01' -ExpandProperties).Properties.policyRules |
  Select-Object name, objectType, @{N='Store';E={$_.lifecycles.sourceDataStore.dataStoreType}}, @{N='Keep';E={$_.lifecycles.deleteAfter.duration}} |
  Format-Table

# Expected output:
# name    objectType          Store            Keep
# ----    ----------          -----            ----
# Default AzureRetentionRule  OperationalStore P30D
```

### Verify Key Vault Role for Azure Backup

```powershell
$kv = Get-AzKeyVault -ResourceGroupName 'dev-skycraft-swc-rg' -VaultName 'dev-skycraft-swc-kv'
Get-AzRoleAssignment -Scope $kv.ResourceId -RoleDefinitionName 'Key Vault Administrator' |
  Where-Object { $_.DisplayName -eq 'Backup Management Service' } |
  Select-Object DisplayName, RoleDefinitionName, ObjectType |
  Format-Table

# Expected output:
# DisplayName                RoleDefinitionName       ObjectType
# -----------                ------------------       ----------
# Backup Management Service  Key Vault Administrator  ServicePrincipal
```

`Get-AzRoleAssignment` resolves the principals through Microsoft Graph. If it fails with `MicrosoftGraphEndpointResourceId`, see [TROUBLESHOOTING.md](../../TROUBLESHOOTING.md); `Test-Lab.ps1` reads the role through the Azure Resource Manager API instead.

### Verify Alert Processing Rule

```powershell
$aprId = "/subscriptions/$((Get-AzContext).Subscription.Id)/resourceGroups/platform-skycraft-swc-rg/providers/Microsoft.AlertsManagement/actionRules/skycraft-backup-critical-apr"
$apr = (Get-AzResource -ResourceId $aprId -ApiVersion '2021-08-08' -ExpandProperties).Properties
[pscustomobject]@{
  Enabled  = $apr.enabled
  Action   = $apr.actions.actionType
  Group    = ($apr.actions.actionGroupIds -split '/')[-1]
  Severity = ($apr.conditions | Where-Object field -eq 'Severity').values -join ','
} | Format-Table

# Expected output:
# Enabled Action          Group           Severity
# ------- ------          -----           --------
#    True AddActionGroups skycraft-ops-ag Sev0
```

### Verify Blob Backup Instance

```powershell
Get-AzDataProtectionBackupInstance -ResourceGroupName 'platform-skycraft-swc-rg' -VaultName 'platform-skycraft-swc-bv' |
  Select-Object Name, @{N='Source';E={$_.Property.DataSourceInfo.ResourceName}}, @{N='Status';E={$_.Property.CurrentProtectionState}} |
  Format-Table

# Expected output:
# Name                           Source               Status
# ----                           ------               ------
# prodskycraftswcsa-...          prodskycraftswcsa    ProtectionConfigured
```

### Verify ASR Replication Status

```powershell
# ASR replication lives in the vault of the North Europe target group
$vault = Get-AzRecoveryServicesVault -ResourceGroupName platform-skycraft-neu-asr-rg -Name platform-skycraft-neu-asr-rsv
Set-AzRecoveryServicesAsrVaultContext -Vault $vault | Out-Null
$items = foreach ($fabric in Get-AzRecoveryServicesAsrFabric) {
    foreach ($container in Get-AzRecoveryServicesAsrProtectionContainer -Fabric $fabric) {
        Get-AzRecoveryServicesAsrReplicationProtectedItem -ProtectionContainer $container |
            Select-Object FriendlyName, ProtectionState, ReplicationHealth
    }
}
$items | Format-Table -AutoSize

# Expected output (after the initial replication, about 45 minutes):
# FriendlyName                ProtectionState ReplicationHealth
# ------------                --------------- -----------------
# dev-skycraft-swc-world-vm   Protected       Normal
```

> **Note**: `Test-Lab.ps1` runs the same read and fails while the item is still replicating. In the Portal: **Recovery Services Vault** → **Protected items** → **Replicated items**.

---

## 📊 BCDR Architecture Summary

| Component                   | Name                        | Type          | Status |
| :-------------------------- | :-------------------------- | :------------ | :----- |
| **Recovery Services Vault** | `platform-skycraft-swc-rsv` | LRS           | [x]    |
| **VM Backup Policy**        | `SkyCraft-Daily-Prod`       | Daily, 30-day | [x]    |
| **Protected VMs**           | `dev-skycraft-swc-auth-vm`, `dev-skycraft-swc-world-vm` | VM Backup | [x] |
| **Key Vault role**          | Backup Management Service on `dev-skycraft-swc-kv` | Key Vault Administrator | [x] |
| **Backup Vault**            | `platform-skycraft-swc-bv`  | LRS, soft delete Off | [x] |
| **Blob Policy**             | `SkyCraft-Blob-Policy`      | Operational, 30-day | [x] |
| **Alert processing rule**   | `skycraft-backup-critical-apr` | Sev0 → `skycraft-ops-ag` | [ ] |
| **Site Recovery**           | `dev-skycraft-swc-world-vm` → North Europe, `platform-skycraft-neu-asr-rg` | Continuous    | [ ]    |
| **Test Failover**           | Completed + cleaned up      | Validated     | [ ]    |

---

## 📝 Reflection Questions

### Question 1: RPO/RTO Documentation

**Document the RPO and RTO for your backup configuration:**

| Scenario          | RPO          | RTO          |
| ----------------- | ------------ | ------------ |
| VM Backup (daily) | ****\_\_**** | ****\_\_**** |
| Blob Backup       | ****\_\_**** | ****\_\_**** |
| Site Recovery     | ****\_\_**** | ****\_\_**** |

### Question 2: Troubleshooting Experience

**What was the most challenging part of this lab? How did you resolve it?**

---

---

### Question 3: Cost Considerations

**Estimate the monthly cost of your BCDR setup. What would you change to reduce costs while maintaining acceptable protection?**

---

---

**Instructor Review Date**: **\_\_\_\_**
**Feedback**: ******************\_\_\_\_******************

---

## ⏱️ Completion Tracking

- **Estimated Time**: 2.5 hours
- **Actual Time Spent**: **\_\_\_\_** hours
- **Date Started**: **\_\_\_\_**
- **Date Completed**: **\_\_\_\_**

**Challenges Encountered** (optional):

---

## ✅ Final Lab 5.2 Sign-off

**All Verification Items Complete**:

- [ ] All resources created with proper naming conventions
- [ ] All tags applied (Project, Environment, CostCenter, Owner)
- [ ] All validation commands executed successfully
- [ ] All reflection questions answered
- [ ] Ready to proceed to Lab 5.3

**Student Name**: ******\_\_\_\_******
**Lab 5.2 Completion Date**: ******\_\_\_\_******
**Instructor Signature**: ******\_\_\_\_******

---

## 🎉 Congratulations!

You've successfully completed **Lab 5.2: Business Continuity & Disaster Recovery**!

**What You Built**:

- ✅ Multi-layered BCDR strategy with Recovery Services and Backup Vaults
- ✅ Automated daily VM backups with 30-day retention
- ✅ Cross-region disaster recovery with Azure Site Recovery
- ✅ Validated DR strategy with successful test failover

**Next**: [Lab 5.3: Network Monitoring & Diagnostics →](../5.3-network-monitoring/lab-guide-5.3.md)

---

## 📌 Module Navigation

- [← Back to Module 5 Index](../README.md)
- [← Lab 5.1: Azure Monitor](../5.1-azure-monitor/lab-guide-5.1.md)
- [Lab 5.3: Network Monitoring →](../5.3-network-monitoring/lab-guide-5.3.md)
