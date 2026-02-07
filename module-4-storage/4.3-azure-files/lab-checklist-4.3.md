# Lab 4.3 Completion Checklist

## ✅ Resource Verification

### File Shares

- [ ] **Storage Account**: `prodskycraftswcsa`
- [ ] **Share 1**: `skycraft-config`
  - [ ] Quota: 100 GB
  - [ ] Tier: Hot
- [ ] **Share 2**: `skycraft-shared`
  - [ ] Quota: 500 GB
  - [ ] Tier: Hot

### Content Structure

- [ ] Directory `auth-server` exists
- [ ] Directory `world-server` exists
- [ ] Directory `common` exists
- [ ] File `config.txt` (or similar) uploaded

## ✅ Data Protection Verification

### Settings

- [ ] **Soft Delete**: Enabled for 14 days
- [ ] **Snapshots**: At least one manual snapshot created

### Functional Test

- [ ] **Restore Test**: Successfully restored a deleted file from snapshot
- [ ] **Mount Test**: Generated script and (optional) mounted drive successfully

---

## 🔍 Validation Commands

Run these in Azure Cloud Shell (PowerShell) or local terminal to verify your work.

### 1. Verify Shares and Quotas

```powershell
$ctx = (Get-AzStorageAccount -ResourceGroupName prod-skycraft-swc-rg -Name prodskycraftswcsa).Context
Get-AzStorageShare -Context $ctx | Select-Object Name, Quota, AccessTier

# Expected Output:
# Name             Quota   AccessTier
# ----             -----   ----------
# skycraft-config  100     Hot
# skycraft-shared  500     Hot
```

### 2. Verify Soft Delete Policy

```powershell
$props = Get-AzStorageAccount -ResourceGroupName prod-skycraft-swc-rg -Name prodskycraftswcsa
$props.FileService.ShareDeleteRetentionPolicy

# Expected Output:
# Enabled : True
# Days    : 14
```

### 3. Check for Snapshots

```powershell
# List snapshots for skycraft-config
Get-AzStorageShare -Context $ctx -Name "skycraft-config" -SnapshotTime * | Where-Object { $_.IsSnapshot }
```

---

## 📝 Reflection Questions

### Question 1: Protocol Choice

**Why did we choose SMB over NFS for the SkyCraft game servers? Consider the operating systems involved.**

### Question 2: Access Logic

**If a VM cannot connect to the file share (Error 53), what is the most likely networking cause?**

---

## ✅ Final Sign-off

- [ ] resources verified via CLI/PowerShell
- [ ] manual tests passed
- [ ] reflection questions answered

**Date Completed**: **\*\***\_\_\_\_**\*\***
