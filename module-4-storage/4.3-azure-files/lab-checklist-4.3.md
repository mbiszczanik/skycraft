# Lab 4.3 Completion Checklist

## ✅ File Shares Verification

### skycraft-config

- [ ] Share name: `skycraft-config`
- [ ] Storage account: `prodskycraftswcsa`
- [ ] Resource group: `prod-skycraft-swc-rg`
- [ ] Quota: **100 GB**
- [ ] Access Tier: **Hot**

### skycraft-shared

- [ ] Share name: `skycraft-shared`
- [ ] Storage account: `prodskycraftswcsa`
- [ ] Resource group: `prod-skycraft-swc-rg`
- [ ] Quota: **500 GB**
- [ ] Access Tier: **Hot**

---

## ✅ Content & Structure Verification

- [ ] Directory `common` exists in `skycraft-config`
- [ ] File `common/config.txt` exists with content `server-name=skycraft-prod-01`

---

## ✅ Data Protection Verification

### Soft Delete

- [ ] Soft delete **enabled** for file shares
- [ ] Retention period: **14 days**

### Snapshots

- [ ] At least one manual snapshot exists for `skycraft-config`
- [ ] File restore from snapshot verified (config.txt content matches original)

---

## ✅ Connectivity Verification

- [ ] Mount script generated via Azure Portal (Windows and/or Linux)
- [ ] Port 445 connectivity tested to `prodskycraftswcsa.file.core.windows.net`

---

## ✅ Tags (Storage Account Level)

- [ ] Tag: `Project` = `SkyCraft`
- [ ] Tag: `Environment` = `Production`
- [ ] Tag: `CostCenter` = `MSDN`

---

## 🔍 Validation Commands

Run these commands to validate your lab setup:

### Login and Set Context

```azurecli
# Login to Azure
az login

# Set subscription context
az account set --subscription "YOUR-SUBSCRIPTION-NAME"
```

### 1. Verify File Shares and Quotas (Azure CLI)

```azurecli
az storage share-rm list \
  --storage-account prodskycraftswcsa \
  --resource-group prod-skycraft-swc-rg \
  --query "[].{Name:name, Quota:quota, Tier:accessTier}" \
  --output table

# Expected Output:
# Name             Quota    Tier
# ---------------  -------  ----
# skycraft-config  100      Hot
# skycraft-shared  500      Hot
```

### 2. Verify File Shares and Quotas (PowerShell)

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

### 3. Verify Soft Delete Policy (Azure CLI)

```azurecli
az storage account file-service-properties show \
  --account-name prodskycraftswcsa \
  --resource-group prod-skycraft-swc-rg \
  --query "shareDeleteRetentionPolicy"

# Expected Output:
# {
#   "days": 14,
#   "enabled": true
# }
```

### 4. Verify Soft Delete Policy (PowerShell)

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

### 5. Verify Existing Snapshots (Azure CLI)

```azurecli
az storage share-rm list \
  --storage-account prodskycraftswcsa \
  --resource-group prod-skycraft-swc-rg \
  --include-snapshots \
  --query "[?snapshot != null].{Name:name, Snapshot:snapshot}" \
  --output table

# Expected Output:
# Name             Snapshot
# ---------------  ----------------------------
# skycraft-config  2026-02-10T07:15:00.0000000Z
```

### 6. Verify Tags (Azure CLI)

```azurecli
az storage account show \
  --name prodskycraftswcsa \
  --resource-group prod-skycraft-swc-rg \
  --query "tags" \
  --output json

# Expected Output:
# {
#   "CostCenter": "MSDN",
#   "Environment": "Production",
#   "Project": "SkyCraft"
# }
```

### 7. Verify Port 445 Connectivity (PowerShell)

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
| **Config Share** | `skycraft-config` | 100 GB | Hot         | Snapshots + Soft Delete | ✅     |
| **Asset Share**  | `skycraft-shared` | 500 GB | Hot         | Soft Delete             | ✅     |
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
- [ ] All tags applied correctly (Project, Environment, CostCenter)
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
- ✅ High-capacity shared asset storage (500 GB)
- ✅ Robust data protection with soft delete (14 days) and snapshots
- ✅ Cross-platform mount capability (Windows + Linux)

**Next**: [Lab 4.4: Storage Security →](../4.4-storage-security/lab-guide-4.4.md)

---

## 📌 Module Navigation

- [← Back to Module 4 Index](../README.md)
- [Lab 4.4: Storage Security →](../4.4-storage-security/lab-guide-4.4.md)
