# Lab 5.2 Completion Checklist

> **Purpose**: This checklist verifies correct implementation of Lab 5.2: Business Continuity & Disaster Recovery. Use it to confirm all backup and recovery resources are properly configured before proceeding to Lab 5.3.

---

## ✅ Recovery Services Vault Verification

### Vault Configuration

- [x] Vault name: `platform-skycraft-swc-rsv`
- [x] Location: **Sweden Central**
- [x] Resource group: `platform-skycraft-swc-rg`
- [x] Storage replication type: **Locally-redundant (LRS)**
- [x] Soft delete: **Enabled** (default)

### Tags

- [x] Tag: `Project` = `SkyCraft`
- [x] Tag: `Environment` = `Platform`
- [x] Tag: `CostCenter` = `MSDN`

---

## ✅ Backup Policy Verification

### VM Backup Policy

- [x] Policy name: `SkyCraft-Daily-Prod`
- [x] Backup frequency: **Daily**
- [x] Backup time: **02:00 AM UTC**
- [x] Instant Restore retention: **2 days**
- [x] Daily backup retention: **30 days**

### Blob Backup Policy

- [x] Policy name: `SkyCraft-Blob-Policy`
- [x] Retention: **30 days**
- [x] Associated vault: `platform-skycraft-swc-bv`

---

## ✅ Protected Items Verification

### VM Backup

- [x] VM `prod-skycraft-swc-auth-vm` listed under **Backup items** → Azure Virtual Machine
- [x] Policy assigned: `SkyCraft-Daily-Prod`
- [x] Initial backup triggered (status: **Completed** or **In progress**)
- [x] Last backup status: **Success** (once completed)

---

## ✅ Backup Vault Verification

### Vault Configuration

- [x] Vault name: `platform-skycraft-swc-bv`
- [x] Location: **Sweden Central**
- [x] Resource group: `platform-skycraft-swc-rg`
- [x] Storage redundancy: **Locally-redundant (LRS)**
- [x] Identity type: **System Assigned**

### Tags

- [x] Tag: `Project` = `SkyCraft`
- [x] Tag: `Environment` = `Platform`
- [x] Tag: `CostCenter` = `MSDN`

---

## ✅ Azure Site Recovery Verification

### Replication Status

- [ ] VM `prod-skycraft-swc-auth-vm` replication status: **Protected**
- [ ] Target region: **Norway East**
- [ ] Cache storage account created in source region
- [ ] Target resource group created in Norway East

### Test Failover

- [ ] Test failover completed successfully
- [ ] Test VM booted in Norway East
- [ ] Cleanup of test resources completed (no orphaned VMs)

---

## ✅ Backup Reports Verification

- [x] Log Analytics Workspace linked to Backup center
- [x] Backup Instances report shows all protected items

---

## 🔍 Validation Commands

Run these commands to validate your lab setup:

### Verify Recovery Services Vault (Azure CLI)

```azurecli
# List Recovery Services Vaults
az backup vault list \
  --resource-group platform-skycraft-swc-rg \
  --query "[?name=='platform-skycraft-swc-rsv'].{Name:name,Location:location,State:properties.provisioningState}" \
  --output table

# Expected output:
# Name                        Location        State
# --------------------------  --------------  ---------
# platform-skycraft-swc-rsv   swedencentral   Succeeded
```

### Verify Recovery Services Vault (PowerShell)

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

### Verify Backup Policy (Azure CLI)

```azurecli
# Get policy details
az backup policy show \
  --name SkyCraft-Daily-Prod \
  --resource-group platform-skycraft-swc-rg \
  --vault-name platform-skycraft-swc-rsv \
  --query "{Name:name,ScheduleFrequency:properties.schedulePolicy.scheduleRunFrequency}" \
  --output table

# Expected output:
# Name                 ScheduleFrequency
# -------------------  -----------------
# SkyCraft-Daily-Prod  Daily
```

### Verify Backup Policy (PowerShell)

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

### Verify Protected Items (Azure CLI)

```azurecli
# List items protected in the vault
az backup item list \
  --vault-name platform-skycraft-swc-rsv \
  --resource-group platform-skycraft-swc-rg \
  --query "[].{Name:properties.friendlyName,Status:properties.protectionStatus,LastBackup:properties.lastBackupTime}" \
  --output table

# Expected output:
# Name                           Status     LastBackup
# -----------------------------  ---------  -------------------
# prod-skycraft-swc-auth-vm      Healthy    2026-02-27T02:00:00
```

### Verify Protected Items (PowerShell)

```powershell
$vault = Get-AzRecoveryServicesVault -ResourceGroupName 'platform-skycraft-swc-rg' -Name 'platform-skycraft-swc-rsv'
$container = Get-AzRecoveryServicesBackupContainer -VaultId $vault.ID -ContainerType AzureVM
Get-AzRecoveryServicesBackupItem -VaultId $vault.ID -Container $container -WorkloadType AzureVM |
  Select-Object Name, ProtectionStatus, LastBackupTime |
  Format-Table

# Expected output:
# Name                           ProtectionStatus  LastBackupTime
# ----                           ----------------  --------------
# prod-skycraft-swc-auth-vm      Healthy           2026-02-27 02:00:00
```

### Verify Backup Vault (Azure CLI)

```azurecli
az dataprotection backup-vault list \
  --resource-group platform-skycraft-swc-rg \
  --query "[?name=='platform-skycraft-swc-bv'].{Name:name,Region:location,State:properties.provisioningState}" \
  --output table

# Expected output:
# Name                       Region          State
# -------------------------  --------------  ---------
# platform-skycraft-swc-bv   swedencentral   Succeeded
```

### Verify Backup Vault (PowerShell)

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

### Verify Blob Backup Policy (Azure CLI)

```azurecli
az dataprotection backup-policy show \
  --resource-group platform-skycraft-swc-rg \
  --vault-name platform-skycraft-swc-bv \
  --name SkyCraft-Blob-Policy \
  --query "{Name:name,DatasourceTypes:properties.datasourceTypes[0]}" \
  --output table

# Expected output:
# Name                   DatasourceTypes
# ---------------------  -----------------------------------------------
# SkyCraft-Blob-Policy   Microsoft.Storage/storageAccounts/blobServices
```

### Verify Blob Backup Policy (PowerShell)

```powershell
Get-AzDataProtectionBackupPolicy -ResourceGroupName 'platform-skycraft-swc-rg' -VaultName 'platform-skycraft-swc-bv' |
  Where-Object { $_.Name -eq 'SkyCraft-Blob-Policy' } |
  Select-Object Name, @{N='DatasourceType';E={$_.Property.DatasourceTypes[0]}} |
  Format-Table

# Expected output:
# Name                   DatasourceType
# ----                   --------------
# SkyCraft-Blob-Policy   Microsoft.Storage/storageAccounts/blobServices
```

### Verify Blob Backup Instance (Azure CLI)

```azurecli
az dataprotection backup-instance list \
  --resource-group platform-skycraft-swc-rg \
  --vault-name platform-skycraft-swc-bv \
  --query "[].{Name:name,SourceResource:properties.dataSourceInfo.resourceName,Status:properties.currentProtectionState}" \
  --output table

# Expected output:
# Name                           SourceResource       Status
# -----------------------------  -------------------  ---------------------
# prodskycraftswcsa-...          prodskycraftswcsa    ProtectionConfigured
```

### Verify Blob Backup Instance (PowerShell)

```powershell
Get-AzDataProtectionBackupInstance -ResourceGroupName 'platform-skycraft-swc-rg' -VaultName 'platform-skycraft-swc-bv' |
  Select-Object Name, @{N='Source';E={$_.Property.DataSourceInfo.ResourceName}}, @{N='Status';E={$_.Property.CurrentProtectionState}} |
  Format-Table

# Expected output:
# Name                           Source               Status
# ----                           ------               ------
# prodskycraftswcsa-...          prodskycraftswcsa    ProtectionConfigured
```

### Verify ASR Replication Status (Azure CLI)

```azurecli
# ASR replication status is managed within the Recovery Services Vault
az backup replication-protected-item list \
  --resource-group platform-skycraft-swc-rg \
  --vault-name platform-skycraft-swc-rsv \
  --output table

# Expected output (after replication is enabled):
# Name                                  ProtectionState
# ------------------------------------  ---------------
# prod-skycraft-swc-auth-vm             Protected
```

> **Note**: ASR replication is configured via the Azure Portal (Step 5.2.8) and may not yet be enabled in all environments. Verify status in **Azure Portal → Recovery Services Vault → Replicated items**.

---

## 📊 BCDR Architecture Summary

| Component                   | Name                        | Type          | Status |
| :-------------------------- | :-------------------------- | :------------ | :----- |
| **Recovery Services Vault** | `platform-skycraft-swc-rsv` | LRS           | [x]    |
| **VM Backup Policy**        | `SkyCraft-Daily-Prod`       | Daily, 30-day | [x]    |
| **Protected VM**            | `prod-skycraft-swc-auth-vm` | VM Backup     | [x]    |
| **Backup Vault**            | `platform-skycraft-swc-bv`  | LRS           | [x]    |
| **Blob Policy**             | `SkyCraft-Blob-Policy`      | 30-day        | [x]    |
| **Site Recovery**           | ASR → Norway East           | Continuous    | [ ]    |
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
- [ ] All tags applied (Project, Environment, CostCenter)
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
