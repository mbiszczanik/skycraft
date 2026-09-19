# Lab 4.2 Completion Checklist

## ✅ Blob Containers Verification

### game-assets Container (Private)

- [ ] Container name: `game-assets`
- [ ] Location: **prod-skycraft-swc-rg / prodskycraftswcsa**
- [ ] Public access level: **Private (no anonymous access)**
- [ ] Default access tier: **Hot**

### public-demo Container (Public - Dev Only)

- [ ] Container name: `public-demo`
- [ ] Location: **dev-skycraft-swc-rg / devskycraftswcsa**
- [ ] Public access level: **Blob (anonymous read access for blobs only)**
- [ ] Test blob accessible via public URL

### player-backups Container (Private)

- [ ] Container name: `player-backups`
- [ ] Public access level: **Private (no anonymous access)**
- [ ] Lifecycle rule applied: `archive-backups` (archive after 7 days)

### server-config Container (Private)

- [ ] Container name: `server-config`
- [ ] Public access level: **Private (no anonymous access)**
- [ ] Default access tier: **Hot**

### game-logs Container (Private)

- [ ] Container name: `game-logs`
- [ ] Public access level: **Private (no anonymous access)**
- [ ] Lifecycle rule applied: `tier-game-logs`

---

## ✅ Data Protection Configuration

### Soft Delete for Blobs

- [ ] Feature: **Enabled**
- [ ] Retention period: **7 days**

### Soft Delete for Containers

- [ ] Feature: **Enabled**
- [ ] Retention period: **7 days**

### Blob Versioning

- [ ] Feature: **Enabled**
- [ ] Versions created on overwrite: **Yes**

---

## ✅ Lifecycle Management Policies

### tier-game-logs Rule

- [ ] Rule name: `tier-game-logs`
- [ ] Status: **Enabled**
- [ ] Scope: **All blobs**
- [ ] Blob types: **Block blobs**
- [ ] Actions:
  - [ ] Move to **Cool** after **30 days**
  - [ ] Move to **Cold** after **90 days**
  - [ ] Move to **Archive** after **180 days**
  - [ ] **Delete** after **365 days**

### archive-backups Rule

- [ ] Rule name: `archive-backups`
- [ ] Status: **Enabled**
- [ ] Filter: Blob prefix `player-backups/`
- [ ] Actions:
  - [ ] Move to **Archive** after **7 days**

---

## ✅ Production Blob Verification

- [ ] Private blob uploaded: `prod-skycraft-swc-rg / prodskycraftswcsa / game-assets`
- [ ] Blob name: `textures/test-asset.txt`
- [ ] Version created after overwrite
- [ ] Access tier: **Hot**

---

## 🔍 Validation Commands

Run these Az PowerShell commands to validate your lab setup:

### Verify Containers

```powershell
# List all containers (Production)
$ctx = (Get-AzStorageAccount -ResourceGroupName prod-skycraft-swc-rg -Name prodskycraftswcsa).Context
Get-AzStorageContainer -Context $ctx | Select-Object Name, PublicAccess | Format-Table

# Expected output:
# Name              PublicAccess
# ----              ------------
# game-assets       Off
# player-backups    Off
# server-config     Off
# game-logs         Off

# Verify public-demo (Development) - private, and the account switch is off
$devSa  = Get-AzStorageAccount -ResourceGroupName dev-skycraft-swc-rg -Name devskycraftswcsa
$devSa.AllowBlobPublicAccess           # False
Get-AzStorageContainer -Context $devSa.Context -Name "public-demo" | Select-Object Name, PublicAccess | Format-Table

# Expected output:
# Name              PublicAccess
# ----              ------------
# public-demo       Off
```

### Verify Data Protection

```powershell
# Check blob service properties
$props = Get-AzStorageBlobServiceProperty -ResourceGroupName prod-skycraft-swc-rg -StorageAccountName prodskycraftswcsa
[PSCustomObject]@{
    BlobSoftDeleteEnabled = $props.DeleteRetentionPolicy.Enabled
    BlobSoftDeleteDays = $props.DeleteRetentionPolicy.Days
    ContainerSoftDeleteEnabled = $props.ContainerDeleteRetentionPolicy.Enabled
    ContainerSoftDeleteDays = $props.ContainerDeleteRetentionPolicy.Days
    VersioningEnabled = $props.IsVersioningEnabled
}

# Expected output:
# BlobSoftDeleteEnabled    : True
# BlobSoftDeleteDays       : 7
# ContainerSoftDeleteEnabled: True
# ContainerSoftDeleteDays  : 7
# VersioningEnabled        : True
```

### Verify Lifecycle Policies

```powershell
# List lifecycle policies
$policy = Get-AzStorageAccountManagementPolicy -ResourceGroupName prod-skycraft-swc-rg -StorageAccountName prodskycraftswcsa
$policy.Rules | Select-Object Name, Enabled, Type | Format-Table

# Expected output:
# Name             Enabled Type
# ----             ------- ----
# tier-game-logs   True    Lifecycle
# archive-backups  True    Lifecycle
```

### Verify Test Blob

```powershell
# List blobs in game-assets
$ctx = (Get-AzStorageAccount -ResourceGroupName prod-skycraft-swc-rg -Name prodskycraftswcsa).Context
Get-AzStorageBlob -Container game-assets -Context $ctx |
    Select-Object Name, AccessTier, Length |
    Format-Table -AutoSize

# Expected output:
# Name                          AccessTier  Length
# ----                          ----------  ------
# textures/test-asset.txt       Hot         XX
```

### Verify Blob Versioning

```powershell
# List blob versions
Get-AzStorageBlob -Container game-assets -Prefix 'textures/test-asset.txt' -IncludeVersion -Context $ctx |
    Select-Object Name, VersionId, IsLatestVersion |
    Format-Table -AutoSize

# Expected output (if overwritten):
# Name                          VersionId                              IsLatestVersion
# ----                          ---------                              ---------------
# textures/test-asset.txt       2026-02-06T15:30:00.0000000Z
# textures/test-asset.txt       2026-02-06T15:35:00.0000000Z           True
```

---

## 📊 Blob Storage Summary

| Container      | Access Level  | Expected Tier | Lifecycle Rule  | Status |
| -------------- | ------------- | ------------- | --------------- | ------ |
| game-assets    | Private       | Hot           | None            | ✅     |
| player-backups | Private       | Archive (7d)  | archive-backups | ✅     |
| server-config  | Private       | Hot           | None            | ✅     |
| game-logs      | Private       | Cool→Archive  | tier-game-logs  | ✅     |
| public-demo    | Blob (public) | Hot           | None            | ✅     |

### Data Protection Summary

| Feature               | Status     | Retention/Setting |
| --------------------- | ---------- | ----------------- |
| Blob Soft Delete      | ✅ Enabled | 7 days            |
| Container Soft Delete | ✅ Enabled | 7 days            |
| Blob Versioning       | ✅ Enabled | All versions      |

### Lifecycle Rules Summary

| Rule Name       | Scope           | Actions                                        |
| --------------- | --------------- | ---------------------------------------------- |
| tier-game-logs  | All blobs       | Cool(30d)→Cold(90d)→Archive(180d)→Delete(365d) |
| archive-backups | player-backups/ | Archive(7d)                                    |

---

## 📝 Reflection Questions

### Question 1: Cost Optimization Analysis

**Calculate the monthly storage cost difference for 100GB in each tier:**

| Tier                | Cost per GB/month | Total (100GB) |
| ------------------- | ----------------- | ------------- |
| Hot                 | $**\_\_\_\_**     | $**\_\_\_\_** |
| Cool                | $**\_\_\_\_**     | $**\_\_\_\_** |
| Cold                | $**\_\_\_\_**     | $**\_\_\_\_** |
| Archive             | $**\_\_\_\_**     | $**\_\_\_\_** |
| **Maximum Savings** |                   | $**\_\_\_\_** |

---

### Question 2: Data Recovery Scenario

**Describe the steps to recover a soft-deleted container named `game-logs`:**

1. ***
2. ***
3. ***

---

### Question 3: Lifecycle Policy Design

**If game logs grew to 10TB per month and needed 3-year retention for compliance, how would you modify the lifecycle policy? Document your changes:**

| Current Action | Modified Action | Reason |
| -------------- | --------------- | ------ |
|                |                 |        |
|                |                 |        |
|                |                 |        |

---

### Question 4: Rehydration Priority Selection

**For a disaster recovery scenario where player backups need to be restored within 2 hours, which rehydration priority would you choose and why?**

---

---

---

### Question 5: Access Level Decision

**A marketing team wants to share game screenshots publicly. What access level configuration would you recommend and what security considerations apply?**

---

---

---

**Instructor Review Date**: \***\*\_\*\***
**Feedback**: **\*\***\*\***\*\***\*\***\*\***\*\***\*\***\_\_**\*\***\*\***\*\***\*\***\*\***\*\***\*\***

---

## ⏱️ Completion Tracking

- **Estimated Time**: 2 hours
- **Actual Time Spent**: **\_\_\_** hours
- **Date Started**: \***\*\_\*\***
- **Date Completed**: \***\*\_\*\***

---

## ✅ Final Lab 4.2 Sign-off

**All Verification Items Complete**:

- [ ] All four containers created with correct naming
- [ ] `game-assets` is **Private** (Production)
- [ ] `public-demo` has blob-level public access (Development)
- [ ] Soft delete enabled for blobs (7 days)
- [ ] Soft delete enabled for containers (7 days)
- [ ] Blob versioning enabled
- [ ] `tier-game-logs` lifecycle rule created and enabled
- [ ] `archive-backups` lifecycle rule created and enabled
- [ ] Test blob uploaded and verified
- [ ] All validation commands executed successfully
- [ ] All reflection questions answered
- [ ] Ready to proceed to Lab 4.3

**Student Name**: **\*\***\_\_\_\_**\*\***
**Lab 4.2 Completion Date**: **\*\***\_\_\_\_**\*\***
**Instructor Signature**: **\*\***\_\_\_\_**\*\***

---

## 🎉 Congratulations!

You've completed **Lab 4.2: Implement Azure Blob Storage**!

**What You Built**:

- ✅ Four blob containers with appropriate access levels and security
- ✅ Comprehensive data protection with soft delete and versioning
- ✅ Lifecycle management policies for automatic cost optimization
- ✅ Working test blob with version history

**Cost Optimization Achieved**:

- Game logs: ~95% savings after 180 days (Archive tier)
- Player backups: ~95% savings after 7 days (Archive tier)

**Next**: [Lab 4.3: Configure Azure Files →](../4.3-azure-files/lab-guide-4.3.md)

---

## 📌 Module Navigation

- [← Lab 4.1: Storage Accounts](../4.1-storage-accounts/lab-guide-4.1.md)
- [Lab 4.3: Azure Files →](../4.3-azure-files/lab-guide-4.3.md)
