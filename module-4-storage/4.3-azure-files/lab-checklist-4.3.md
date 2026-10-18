# Lab 4.3 Completion Checklist

## ✅ File Shares Verification

### skycraft-config

- [ ] Share name: `skycraft-config`
- [ ] Storage account: `prodskycraftswcsa`
- [ ] Resource group: `prod-skycraft-swc-rg`
- [ ] Quota: **100 GiB** (Step 4.3.1, **Edit quota**)
- [ ] Access Tier: **Hot** (not the wizard's default, Transaction optimized)
- [ ] Azure Backup: **not configured** (**Enable backup** unticked on the wizard's **Backup** tab)

### skycraft-shared

- [ ] Share name: `skycraft-shared`
- [ ] Storage account: `prodskycraftswcsa`
- [ ] Resource group: `prod-skycraft-swc-rg`
- [ ] Quota: **500 GiB** (Step 4.3.2, **Edit quota**)
- [ ] Access Tier: **Hot**
- [ ] Azure Backup: **not configured**
- [ ] No other file share in `prodskycraftswcsa`

---

## ✅ Content & Structure Verification

- [ ] Directory `common` exists in `skycraft-config`
- [ ] File `common/config.txt` exists with content `server-name=skycraft-prod-01`

---

## ✅ Data Protection Verification

### Soft Delete

- [ ] Soft delete **enabled** for file shares (on since Lab 4.1)
- [ ] Retention period: **14 days** (Step 4.3.3; Lab 4.1 set 7)

### Snapshots

- [ ] At least one manual snapshot exists for `skycraft-config`
- [ ] File restore from snapshot verified (config.txt content matches original)

---

## ✅ Connectivity Verification

- [ ] Mount script generated via Azure Portal (Windows and/or Linux) and run on Windows in a normal, not elevated, PowerShell window
- [ ] Port 445 connectivity tested to `prodskycraftswcsa.file.core.windows.net`
- [ ] Storage account key kept out of screenshots, chats and issues

---

## ✅ Tags (Storage Account Level)

- [ ] Tag: `Project` = `SkyCraft`
- [ ] Tag: `Environment` = `Production`
- [ ] Tag: `CostCenter` = `MSDN`
- [ ] Tag: `Owner` = `mbiszczanik`

---

## 🔍 Validation Commands

Run the lab's validator from the lab folder; it checks the account, soft delete, both shares (quota and tier) and that no Recovery Services vault backs up a share of the account:

```powershell
./scripts/Test-Lab.ps1
# Expected Output (last line):
# Validation Complete. Failures: 0
```

Or run these Az PowerShell commands to validate your lab setup:

### Login and Set Context

```powershell
# Login to Azure
Connect-AzAccount

# Set subscription context
Set-AzContext -SubscriptionName "YOUR-SUBSCRIPTION-NAME"
```

### 1. Verify File Shares and Quotas

```powershell
Get-AzRmStorageShare `
  -ResourceGroupName "prod-skycraft-swc-rg" `
  -StorageAccountName "prodskycraftswcsa" |
  Select-Object Name, QuotaGiB, AccessTier |
  Format-Table

# Expected Output:
# Name             QuotaGiB  AccessTier
# ----             --------  ----------
# skycraft-config  100       Hot
# skycraft-shared  500       Hot
```

### 2. Verify Soft Delete Policy

```powershell
Get-AzStorageFileServiceProperty `
  -ResourceGroupName "prod-skycraft-swc-rg" `
  -StorageAccountName "prodskycraftswcsa" |
  Select-Object -ExpandProperty ShareDeleteRetentionPolicy

# Expected Output:
# Days    Enabled
# ----    -------
# 14      True
```

### 3. Verify That No Azure Backup Protects the Shares

```powershell
$account = Get-AzStorageAccount -ResourceGroupName "prod-skycraft-swc-rg" -Name "prodskycraftswcsa"
foreach ($vault in Get-AzResource -ResourceType "Microsoft.RecoveryServices/vaults") {
    Get-AzRecoveryServicesBackupItem -BackupManagementType AzureStorage -WorkloadType AzureFiles -VaultId $vault.ResourceId |
        Where-Object { $_.SourceResourceId -eq $account.Id -or $_.ContainerName -like "*;prod-skycraft-swc-rg;prodskycraftswcsa" } |
        Select-Object @{ n = 'Vault'; e = { $vault.Name } }, Name, ProtectionState
}

# Expected Output:
# (nothing - no vault protects a share of prodskycraftswcsa)
```

### 4. Verify Existing Snapshots

```powershell
Get-AzRmStorageShare `
  -ResourceGroupName "prod-skycraft-swc-rg" `
  -StorageAccountName "prodskycraftswcsa" `
  -IncludeSnapshot |
  Where-Object { $_.SnapshotTime } |
  Select-Object Name, SnapshotTime |
  Format-Table

# Expected Output:
# Name             SnapshotTime
# ----             ------------
# skycraft-config  2026-02-10 07:15:00 +00:00
```

### 5. Verify Tags

```powershell
(Get-AzStorageAccount -ResourceGroupName prod-skycraft-swc-rg -Name prodskycraftswcsa).Tags

# Expected Output:
# Name        Value
# ----        -----
# CostCenter  MSDN
# Owner       mbiszczanik
# Environment Production
# Project     SkyCraft
```

### 6. Verify Port 445 Connectivity

```powershell
Test-NetConnection `
  -ComputerName prodskycraftswcsa.file.core.windows.net `
  -Port 445

# Expected Output:
# TcpTestSucceeded : True
# (If False, port 445 is blocked — mount from an Azure VM instead)
```

---

## 📊 Azure Files Resource Summary

| Component        | Resource Name     | Quota  | Access Tier | Protection              | Status |
| :--------------- | :---------------- | :----- | :---------- | :---------------------- | :----- |
| **Config Share** | `skycraft-config` | 100 GiB | Hot        | Snapshots + Soft Delete, no backup | ✅     |
| **Asset Share**  | `skycraft-shared` | 500 GiB | Hot        | Soft Delete, no backup             | ✅     |
| **Soft Delete**  | Account-level     | N/A    | N/A         | 14-day retention        | ✅     |

---

## 📝 Reflection Questions

### Question 1: Protocol Selection Documentation

**Document why SMB was chosen instead of NFS for this lab, and identify a scenario where NFS would be the better choice:**

---

---

---

### Question 2: Connectivity Experience

**What happened when you tested port 445 from your local machine? Document the result of `Test-NetConnection` below. If it failed, describe how you worked around it:**

| Test Location | TcpTestSucceeded | Workaround Used  |
| ------------- | ---------------- | ---------------- |
| Local machine | ****\_\_****     | ****\_\_\_\_**** |
| Azure VM      | ****\_\_****     | N/A              |

---

### Question 3: Snapshot Restore Verification

**Describe the exact steps you followed to verify that a restored file was identical to the original. What tool or method did you use to compare the contents?**

---

---

---

**Instructor Review Date**: ****\_****
**Feedback**: ********************************\_********************************

---

## ⏱️ Completion Tracking

- **Estimated Time**: 1.5 hours
- **Actual Time Spent**: **\_\_** hours
- **Date Started**: **\_\_**
- **Date Completed**: **\_\_**

**Challenges Encountered** (optional):

---

---

## ✅ Final Lab 4.3 Sign-off

**All Verification Items Complete**:

- [ ] All file shares created with proper naming conventions
- [ ] Neither share protected by Azure Backup (that is Lab 5.2)
- [ ] `./scripts/Test-Lab.ps1` reports `Failures: 0`
- [ ] All tags applied correctly (Project, Environment, CostCenter, Owner)
- [ ] All validation commands executed successfully
- [ ] All reflection questions answered
- [ ] Snapshot restore workflow verified
- [ ] Ready to proceed to Lab 4.4

**Student Name**: ******\_\_\_\_******
**Lab 4.3 Completion Date**: ******\_\_\_\_******
**Instructor Signature**: ******\_\_\_\_******

---

## 🎉 Congratulations!

You've successfully completed **Lab 4.3: Configure Azure Files**!

**What You Built**:

- ✅ Centralized SMB storage for game server configuration
- ✅ High-capacity shared asset storage (500 GiB)
- ✅ Robust data protection with soft delete (14 days) and snapshots
- ✅ Cross-platform mount capability (Windows + Linux)

**Next**: [Lab 4.4: Storage Security →](../4.4-storage-security/lab-guide-4.4.md)

---

## 📌 Module Navigation

- [← Back to Module 4 Index](../README.md)
- [Lab 4.4: Storage Security →](../4.4-storage-security/lab-guide-4.4.md)
