# Lab 4.3: Configure Azure Files (1.5 hours)

## 🎯 Learning Objectives

By completing this lab, you will:

- Understand the differences between Azure Files, Blob Storage, and Disks
- Create and configure file shares in Azure Storage using Portal, CLI, and PowerShell
- Configure quotas and access tiers for file shares
- Configure snapshots and soft delete for data protection
- Restore individual files from snapshots
- Mount file shares on Windows and Linux using SMB

---

## 🏗️ Architecture Overview

### Topology

```mermaid
graph TB
    subgraph ProdResources ["prod-skycraft-swc-rg"]
        style ProdResources fill:#ffe1e1,stroke:#e74c3c,stroke-width:2px

        subgraph SA ["prodskycraftswcsa"]
            subgraph Shares ["File Shares"]
                Config["skycraft-config<br/>100 GB quota<br/>Hot tier"]
                Shared["skycraft-shared<br/>500 GB quota<br/>Hot tier"]
            end

            DataProtection["Data Protection<br/>✅ Soft Delete: 14 days<br/>✅ Snapshots: Manual/Daily"]
        end

        subgraph VNet ["prod-skycraft-swc-vnet"]
            VM1["World Server VM<br/>(Windows Server)"]
            VM2["Auth Server VM<br/>(Ubuntu Linux)"]
        end
    end

    VM1 -->|SMB 3.0 / Port 445| Config
    VM2 -->|SMB 3.0 / Port 445| Config
    VM1 -->|SMB 3.0 / Port 445| Shared
    VM2 -->|SMB 3.0 / Port 445| Shared

    DataProtection -.-> Config
    DataProtection -.-> Shared
```

### Logic Flow / Lifecycle

```mermaid
flowchart LR
    Active["Active File<br/>Ver 1.0"]
    Snap["Snapshot 1<br/>(ReadOnly)"]
    Delete["Soft Deleted<br/>(14 Days)"]
    Gone["Permanently<br/>Deleted"]

    Active -->|"Take Snapshot"| Snap
    Active -->|"Delete File"| Delete
    Delete -->|"Undelete"| Active
    Delete -->|"After 14 Days"| Gone
    Snap -->|"Restore"| Active

    style Active fill:#a5d8ff,stroke:#1971c2
    style Snap fill:#ffe8cc,stroke:#e67700
    style Delete fill:#ffc9c9,stroke:#e03131
```

## 📋 Real-World Scenario

**Situation**: SkyCraft game servers need a shared file system to store configuration files (`server.properties`), allowlist/blocklist data, and shared game assets. Unlike Blob Storage (which is object-based), these legacy game server applications require a standard file system interface (SMB) to read and write files.

**Your Task**: You will provision Azure File Shares to meet these needs, ensuring that:

1. **Config data** is protected with snapshots.
2. **Shared data** has enough capacity (quota).
3. **Access** is possible from both Windows (World Servers) and Linux (Auth Servers).

**Business Impact**:

- **Compatibility**: Supports legacy apps without code changes.
- **Resilience**: Snapshots allow quick recovery from "bad config" pushes.
- **Cost Control**: Quotas and Hot tier prevent runaway costs.

## ⏱️ Estimated Time: 1.5 hours

- **Section 1**: Azure Files Fundamentals (15 min)
- **Section 2**: Create File Shares (30 min)
- **Section 3**: Data Protection & Snapshots (25 min)
- **Section 4**: Mount & Test (20 min)

## ✅ Prerequisites

Before starting this lab:

- [ ] Completed Lab 4.1 & Lab 4.2
- [ ] Storage account `prodskycraftswcsa` exists in `prod-skycraft-swc-rg`
- [ ] Azure CLI installed (`az --version` ≥ 2.50)
- [ ] Understanding of SMB protocol basics

---

## 📖 Section 1: Azure Files Fundamentals (15 min)

### Deep Dive: Protocols (SMB vs. NFS)

Azure Files supports two main protocols. We will use SMB for maximum compatibility with both Windows and Linux clients.

| Feature            | SMB (Server Message Block)      | NFS (Network File System)      |
| :----------------- | :------------------------------ | :----------------------------- |
| **OS Support**     | Windows, Linux, macOS           | Linux (4.1+) only              |
| **Authentication** | AD DS, Entra ID DS, Storage Key | Network/IP-based only          |
| **Encryption**     | AES-256 (SMB 3.0+)              | None (relies on VNet security) |
| **Use Case**       | Lift-and-shift, Gen-purpose     | HPC, Linux-heavy apps          |

### Performance Tiers

| Tier                      | Workload              | Backend |
| :------------------------ | :-------------------- | :------ |
| **Premium**               | High IOPS (Databases) | SSD     |
| **Transaction Optimized** | High churn            | HDD     |
| **Hot**                   | General purpose       | HDD     |
| **Cool**                  | Archive/Backups       | HDD     |

> **SkyCraft Choice**: We use the **Hot** tier for SkyCraft because game config files are small but accessed frequently when servers start up or reload. The transaction costs of the Cool tier would outweigh the storage savings.

---

## ⚙️ Section 2: Create File Shares (30 min)

### Step 4.3.1: Create Configuration File Share

We need a share named `skycraft-config` with a 100 GB quota.

#### Option 1: Azure Portal

1. Navigate to **Storage accounts** → `prodskycraftswcsa`
2. Select **File shares** (under Data storage)
3. Click **+ File share**
4. Enter Name: `skycraft-config`
5. Select Tier: **Hot**
6. Click **Create**
7. Select the new share, click **Edit quota**, set to **100**, and **Save**.

#### Option 2: Azure CLI

```bash
# Create file share with 100GB quota
az storage share-rm create \
  --name skycraft-config \
  --storage-account prodskycraftswcsa \
  --resource-group prod-skycraft-swc-rg \
  --quota 100 \
  --access-tier Hot \
  --output table
```

#### Option 3: PowerShell

```powershell
# Create file share
New-AzRmStorageShare `
  -ResourceGroupName "prod-skycraft-swc-rg" `
  -StorageAccountName "prodskycraftswcsa" `
  -Name "skycraft-config" `
  -QuotaGiB 100 `
  -AccessTier Hot
```

**Expected Result**: `skycraft-config` exists with 100 GB quota and Hot tier.

### Step 4.3.2: Create Shared Data Share

Create a second share `skycraft-shared` for larger game assets.

#### Option 1: Azure Portal

1. Click **+ File share**
2. Name: `skycraft-shared`
3. Tier: **Hot**
4. Click **Create**
5. Edit quota to **500** GB

#### Option 2: Azure CLI

```bash
az storage share-rm create \
  --name skycraft-shared \
  --storage-account prodskycraftswcsa \
  --resource-group prod-skycraft-swc-rg \
  --quota 500 \
  --access-tier Hot
```

#### Option 3: PowerShell

```powershell
New-AzRmStorageShare `
  -ResourceGroupName "prod-skycraft-swc-rg" `
  -StorageAccountName "prodskycraftswcsa" `
  -Name "skycraft-shared" `
  -QuotaGiB 500 `
  -AccessTier Hot
```

---

## ⚙️ Section 3: Data Protection & Snapshots (25 min)

### Step 4.3.3: Configure Soft Delete

Protect against accidental deletions of the file share or its contents.

#### Option 1: Azure Portal

1. Go to **Data protection** (under Data management)
2. **Enable soft delete for file shares**: Checked
3. **Retention**: 14 days
4. Click **Save**

#### Option 2: Azure CLI

```bash
az storage account file-service-properties update \
  --account-name prodskycraftswcsa \
  --resource-group prod-skycraft-swc-rg \
  --enable-delete-retention true \
  --delete-retention-days 14
```

#### Option 3: PowerShell

```powershell
Update-AzStorageFileServiceProperty `
  -ResourceGroupName "prod-skycraft-swc-rg" `
  -StorageAccountName "prodskycraftswcsa" `
  -EnableShareDeleteRetention $true `
  -ShareDeleteRetentionDays 14
```

### Step 4.3.4: Create Manual Snapshot

Snapshots are read-only point-in-time copies.

#### Option 1: Azure Portal

1. Open `skycraft-config` share
2. Click **Snapshots** (under Operations)
3. Click **+ Add snapshot**
4. Comment: `Pre-update backup`
5. Click **OK**

#### Option 2: Azure CLI

```bash
az storage share-rm snapshot \
  --storage-account prodskycraftswcsa \
  --resource-group prod-skycraft-swc-rg \
  --name skycraft-config \
  --output table
```

#### Option 3: PowerShell

```powershell
New-AzRmStorageShareSnapshot `
  -ResourceGroupName "prod-skycraft-swc-rg" `
  -StorageAccountName "prodskycraftswcsa" `
  -ShareName "skycraft-config"
```

**Expected Result**: A new snapshot appears in the list with the current timestamp.

---

## ⚙️ Section 4: Mount & Test (20 min)

### Step 4.3.5: Mount on Windows

#### Option 1: Azure Portal (Generate Script)

1. Open `skycraft-config`
2. Click **Connect**
3. Select **Windows** tab
4. Drive: **Z**
5. Click **Show script** -> Copy and run in local PowerShell.

### Step 4.3.6: Mount on Linux

#### Option 1: Azure Portal (Generate Script)

1. Select **Linux** tab
2. Copy the script. It uses `cifs-utils` to mount via `/etc/fstab`.

---

## ✅ Lab Checklist

- [ ] `skycraft-config` (100GB, Hot) created
- [ ] `skycraft-shared` (500GB, Hot) created
- [ ] Soft delete set to 14 days
- [ ] Snapshot created and restore capability verified
- [ ] Mount script generated successfully

**Detailed verification**: [lab-checklist-4.3.md](lab-checklist-4.3.md)

## 🔧 Troubleshooting

### Issue 1: "The network path was not found" (Error 53)

**Symptom**: Connection fails even with correct credentials.
**Cause**: Port 445 (SMB) is blocked by your firewall or ISP.
**Solution**: Use an Azure VM or VPN. Test with: `Test-NetConnection -ComputerName prodskycraftswcsa.file.core.windows.net -Port 445`

### Issue 2: "Access Denied" (Error 5)

**Symptom**: Credentials rejected during mount.
**Cause**: Invalid Storage Key or local time drift issues.
**Solution**: Regenerate keys in Portal or ensure your client clock is synced (standard Kerberos/SMB requirement).

### Issue 3: Share cannot be deleted

**Symptom**: Deletion fails even for empty share.
**Cause**: Exist snapshots or Lease on the share.
**Solution**: Delete all snapshots before deleting the share, or check for active handles.

## 🎓 Knowledge Check

1. **Which protocol should you use for a Linux-only High Performance Computing (HPC) cluster?**
   <details>
     <summary>**Click to see the answer**</summary>
   **Answer**: NFS (Network File System) on Premium tier is preferred for Linux HPC due to POSIX compliance and performance.
   </details>

2. **If I delete a file share, can I restore it?**
   <details>
     <summary>**Click to see the answer**</summary>
   **Answer**: Yes, if **Soft Delete** was enabled for file shares. You can undelete the whole share within the retention period.
   </details>

3. **What is the primary factor affecting Azure Files snapshot costs?**
   <details>
     <summary>**Click to see the answer**</summary>
   **Answer**: You are billed on the **differential** data changes between snapshots, not the full volume size.
   </details>

## 📚 Additional Resources

- [Troubleshoot Azure Files mounting on Windows](https://learn.microsoft.com/azure/storage/files/storage-troubleshoot-windows-file-connection-problems)
- [Overview of Azure Files identity-based authentication](https://learn.microsoft.com/azure/storage/files/storage-files-active-directory-overview)

## 📌 Module Navigation

[← Lab 4.2: Blob Storage](../4.2-blob-storage/lab-guide-4.2.md) | [Next Lab: 4.4 - Storage Security →](../4.4-storage-security/lab-guide-4.4.md)

---

## 📝 Lab Summary

**What You Accomplished**:
✅ Provisioned SMB file shares for cross-platform access
✅ Configured quotas to prevent storage exhaustion
✅ Implemented a snapshot strategy for disaster recovery
✅ Verified data protection processes

**Time Spent**: ~1.5 hours
