# Lab 5.2 Completion Checklist

> **Purpose**: This checklist verifies correct implementation of Lab 5.2: Business Continuity & Disaster Recovery. Use it to confirm all backup and recovery resources are properly configured before proceeding to Lab 5.3.

---

## ✅ Recovery Services Vault Verification

### Vault Configuration

- [ ] Vault name: `platform-skycraft-swc-rsv`
- [ ] Location: **Sweden Central**
- [ ] Resource group: `platform-skycraft-swc-rg`
- [ ] Storage replication type: **Geo-redundant (GRS)**
- [ ] Soft delete: **Enabled** (default)

### Tags

- [ ] Tag: `Project` = `SkyCraft`
- [ ] Tag: `Environment` = `Platform`
- [ ] Tag: `CostCenter` = `MSDN`

---

## ✅ Backup Policy Verification

### VM Backup Policy

- [ ] Policy name: `SkyCraft-Daily-Prod`
- [ ] Backup frequency: **Daily**
- [ ] Backup time: **02:00 AM UTC**
- [ ] Instant Restore retention: **2 days**
- [ ] Daily backup retention: **30 days**

### Blob Backup Policy

- [ ] Policy name: `SkyCraft-Blob-Policy`
- [ ] Retention: **30 days**
- [ ] Associated vault: `platform-skycraft-swc-bv`

---

## ✅ Protected Items Verification

### VM Backup

- [ ] VM `prod-skycraft-swc-auth-vm` listed under **Backup items** → Azure Virtual Machine
- [ ] Policy assigned: `SkyCraft-Daily-Prod`
- [ ] Initial backup triggered (status: **Completed** or **In progress**)
- [ ] Last backup status: **Success** (once completed)

---

## ✅ Backup Vault Verification

### Vault Configuration

- [ ] Vault name: `platform-skycraft-swc-bv`
- [ ] Location: **Sweden Central**
- [ ] Resource group: `platform-skycraft-swc-rg`
- [ ] Storage redundancy: **Locally-redundant (LRS)**
- [ ] Identity type: **System Assigned**

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

- [ ] Log Analytics Workspace linked to Backup center
- [ ] Backup Instances report shows all protected items

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

---

## 📊 BCDR Architecture Summary

| Component                   | Name                        | Type          | Status |
| :-------------------------- | :-------------------------- | :------------ | :----- |
| **Recovery Services Vault** | `platform-skycraft-swc-rsv` | GRS           | [ ]    |
| **VM Backup Policy**        | `SkyCraft-Daily-Prod`       | Daily, 30-day | [ ]    |
| **Protected VM**            | `prod-skycraft-swc-auth-vm` | VM Backup     | [ ]    |
| **Backup Vault**            | `platform-skycraft-swc-bv`  | LRS           | [ ]    |
| **Blob Policy**             | `SkyCraft-Blob-Policy`      | 30-day        | [ ]    |
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

- **Estimated Time**: 2 hours
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
