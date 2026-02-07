# Lab 4.3 Completion Checklist

## ✅ Azure Files Deployment Verification

### File Shares

- [ ] Storage Account: `prodskycraftswcsa`
- [ ] **Share 1**: `skycraft-config`
  - [ ] Quota: **100 GB**
  - [ ] Access Tier: **Hot**
- [ ] **Share 2**: `skycraft-shared`
  - [ ] Quota: **500 GB**
  - [ ] Access Tier: **Hot**

### Content & Structure

- [ ] All directories exist: `auth-server`, `world-server`, `common`
- [ ] Sample file `config.txt` uploaded to `common`

### Data Protection

- [ ] **Soft Delete**: Enabled for **14 days**
- [ ] **Snapshots**: At least one manual snapshot exists for `skycraft-config`

### Tags

- [ ] Tag: `Project` = `SkyCraft`
- [ ] Tag: `Environment` = `Production`
- [ ] Tag: `CostCenter` = `MSDN`

---

## 🔍 Validation Commands

Run these Azure CLI commands to validate your lab setup:

### 1. Verify File Shares and Quotas

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

### 2. Verify Soft Delete Policy

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

### 3. Verify Existing Snapshots

```azurecli
az storage share-rm list \
  --storage-account prodskycraftswcsa \
  --resource-group prod-skycraft-swc-rg \
  --include-snapshots \
  --query "[?snapshot != null].{Name:name, Snapshot:snapshot}" \
  --output table
```

---

## 📊 Resource Summary

| Component        | Resource Name     | Quota  | Access Tier | Protection              | Status |
| :--------------- | :---------------- | :----- | :---------- | :---------------------- | :----- |
| **Config Share** | `skycraft-config` | 100 GB | Hot         | Snapshots + Soft Delete | ✅     |
| **Asset Share**  | `skycraft-shared` | 500 GB | Hot         | Soft Delete             | ✅     |

---

## 📝 Reflection Questions

### Question 1: Protocol Selection

**Document why SMB was chosen instead of NFS for this specific lab:**

---

### Question 2: Networking Challenges

**What happened when you tried to mount the drive from your local machine? If it failed, what was the specific error code?**

---

### Question 3: Restore Verification

**Describe the steps you took to verify that a file restored from a snapshot was identical to the original:**

---

---

## ⏱️ Completion Tracking

- **Estimated Time**: 1.5 hours
- **Actual Time Spent**: ****\_**** hours
- **Date Started**: ****\_****
- **Date Completed**: ****\_****

---

## ✅ Final Lab 4.3 Sign-off

**All Verification Items Complete**:

- [ ] All resources created with proper naming conventions
- [ ] All tags applied correctly
- [ ] All validation commands executed successfully
- [ ] All reflection questions answered
- [ ] Ready to proceed to Lab 4.4

**Student Name**: ********\_********  
**Instructor Signature**: ********\_********

---

## 🎉 Congratulations!

You've successfully completed **Lab 4.3: Configure Azure Files**!

**What You Built**:

- ✅ Centralized SMB storage for game configuration
- ✅ High-capacity asset storage share
- ✅ Robust data protection with Soft Delete and Snapshots

**Next**: [Lab 4.4: Storage Security →](../4.4-storage-security/lab-guide-4.4.md)

---

## 📌 Module Navigation

- [← Back to Module 4 Index](../README.md)
- [Lab 4.4: Next Lab →](../4.4-storage-security/lab-guide-4.4.md)
