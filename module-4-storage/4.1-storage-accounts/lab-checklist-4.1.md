# Lab 4.1 Completion Checklist

> **Purpose**: This checklist verifies correct implementation of Lab 4.1: Configure and Manage Storage Accounts. Use it to confirm all resources are properly configured before proceeding to Lab 4.2.

---

## ✅ Platform Storage Account (platformskycraftswcsa)

### Storage Configuration

- [ ] Storage account name: `platformskycraftswcsa`
- [ ] Location: **Sweden Central**
- [ ] Resource group: `platform-skycraft-swc-rg`
- [ ] Performance tier: **Standard**
- [ ] Account kind: **StorageV2 (general-purpose v2)**
- [ ] Redundancy: **Geo-redundant storage (GRS)**, without read access (not RA-GRS)
- [ ] Access tier: **Hot**

### Security Settings

- [ ] Secure transfer required: **Enabled**
- [ ] Allow Blob anonymous access: **Disabled**
- [ ] Minimum TLS version: **TLS 1.2**
- [ ] Storage account key access: **Enabled**
- [ ] Encryption: **Microsoft-managed keys**, infrastructure encryption **Disabled**

### Data Protection

- [ ] Soft delete for blobs: **Enabled** (7 days)
- [ ] Soft delete for containers: **Enabled** (7 days)
- [ ] Soft delete for file shares: **Enabled** (7 days)
- [ ] Versioning for blobs: **Disabled** (Lab 4.2 turns it on for production)

### Tags

- [ ] Tag: `Project` = `SkyCraft`
- [ ] Tag: `Environment` = `Platform`
- [ ] Tag: `CostCenter` = `MSDN`
- [ ] Tag: `Owner` = `mbiszczanik`

---

## ✅ Development Storage Account (devskycraftswcsa)

### Storage Configuration

- [ ] Storage account name: `devskycraftswcsa`
- [ ] Location: **Sweden Central**
- [ ] Resource group: `dev-skycraft-swc-rg`
- [ ] Performance tier: **Standard**
- [ ] Account kind: **StorageV2 (general-purpose v2)**
- [ ] Redundancy: **Locally-redundant storage (LRS)**
- [ ] Access tier: **Hot**

### Security Settings

- [ ] Secure transfer required: **Enabled**
- [ ] Allow Blob anonymous access: **Disabled**
- [ ] Minimum TLS version: **TLS 1.2**
- [ ] Storage account key access: **Enabled**
- [ ] Encryption: **Microsoft-managed keys**, infrastructure encryption **Disabled**

### Data Protection

- [ ] Soft delete for blobs: **Enabled** (7 days)
- [ ] Soft delete for containers: **Enabled** (7 days)
- [ ] Soft delete for file shares: **Enabled** (7 days)
- [ ] Versioning for blobs: **Disabled** (Lab 4.2 turns it on for production)

### Tags

- [ ] Tag: `Project` = `SkyCraft`
- [ ] Tag: `Environment` = `Development`
- [ ] Tag: `CostCenter` = `MSDN`
- [ ] Tag: `Owner` = `mbiszczanik`

---

## ✅ Production Storage Account (prodskycraftswcsa)

### Storage Configuration

- [ ] Storage account name: `prodskycraftswcsa`
- [ ] Location: **Sweden Central**
- [ ] Resource group: `prod-skycraft-swc-rg`
- [ ] Performance tier: **Standard**
- [ ] Account kind: **StorageV2 (general-purpose v2)**
- [ ] Redundancy: **Geo-redundant storage (GRS)**, without read access (not RA-GRS)
- [ ] Access tier: **Hot**

### Security Settings

- [ ] Secure transfer required: **Enabled**
- [ ] Allow Blob anonymous access: **Disabled**
- [ ] Minimum TLS version: **TLS 1.2**
- [ ] Storage account key access: **Enabled**
- [ ] Encryption: **Microsoft-managed keys**, infrastructure encryption **Disabled**

### Data Protection

- [ ] Soft delete for blobs: **Enabled** (7 days)
- [ ] Soft delete for containers: **Enabled** (7 days)
- [ ] Soft delete for file shares: **Enabled** (7 days)
- [ ] Versioning for blobs: **Disabled** (Lab 4.2 turns it on for production)

### Tags

- [ ] Tag: `Project` = `SkyCraft`
- [ ] Tag: `Environment` = `Production`
- [ ] Tag: `CostCenter` = `MSDN`
- [ ] Tag: `Owner` = `mbiszczanik`

### Access Keys

- [ ] key1 rotated in Step 4.1.13: its _Last rotated_ date (Portal, **Security + networking** > **Access keys**) is the day you did the lab

---

## 🔍 Validation Commands

Run these Az PowerShell commands to validate your lab setup:

The lab's validator checks that each account finished provisioning (state **Succeeded**), its redundancy, location, security settings, encryption, soft delete and the `Project`, `Environment` and `CostCenter` tags of the three accounts, whichever path built them, and exits 0 when all pass:

```powershell
.\scripts\Test-Lab.ps1
```

### Verify All Storage Accounts Exist

```powershell
# List all SkyCraft storage accounts with key properties
Get-AzStorageAccount |
    Where-Object { $_.StorageAccountName -like '*skycraft*' } |
    Select-Object StorageAccountName, ResourceGroupName, @{N='SKU';E={$_.Sku.Name}}, Location, MinimumTlsVersion |
    Format-Table -AutoSize

# Expected output:
# StorageAccountName      ResourceGroupName         SKU            Location       MinimumTlsVersion
# ------------------      -----------------         ---            --------       -----------------
# platformskycraftswcsa   platform-skycraft-swc-rg  Standard_GRS   swedencentral  TLS1_2
# devskycraftswcsa        dev-skycraft-swc-rg       Standard_LRS   swedencentral  TLS1_2
# prodskycraftswcsa       prod-skycraft-swc-rg      Standard_GRS   swedencentral  TLS1_2
```

### Verify Security Settings

```powershell
# Check production storage account security settings
Get-AzStorageAccount -ResourceGroupName prod-skycraft-swc-rg -Name prodskycraftswcsa |
    Select-Object StorageAccountName, MinimumTlsVersion, AllowBlobPublicAccess, EnableHttpsTrafficOnly |
    Format-Table -AutoSize

# Expected output:
# StorageAccountName   MinimumTlsVersion  AllowBlobPublicAccess  EnableHttpsTrafficOnly
# ------------------   -----------------  ---------------------  ----------------------
# prodskycraftswcsa    TLS1_2             False                  True
```

### Verify Redundancy Configuration

```powershell
# Check redundancy for each account
Get-AzStorageAccount |
    Where-Object { $_.StorageAccountName -in 'platformskycraftswcsa', 'devskycraftswcsa', 'prodskycraftswcsa' } |
    Select-Object StorageAccountName, @{N='SKU';E={$_.Sku.Name}}, Kind |
    Format-Table -AutoSize

# Expected SKUs:
# platformskycraftswcsa: Standard_GRS
# devskycraftswcsa: Standard_LRS
# prodskycraftswcsa: Standard_GRS
```

### Verify Tags

```powershell
# Check tags on each storage account
(Get-AzStorageAccount -ResourceGroupName prod-skycraft-swc-rg -Name prodskycraftswcsa).Tags

# Expected output:
# Name        Value
# ----        -----
# CostCenter  MSDN
# Owner       mbiszczanik
# Environment Production
# Project     SkyCraft
```

### Verify Soft Delete

```powershell
# Check blob, container and file share soft delete on each account
foreach ($account in @(
        @{ Name = 'platformskycraftswcsa'; ResourceGroup = 'platform-skycraft-swc-rg' }
        @{ Name = 'devskycraftswcsa';      ResourceGroup = 'dev-skycraft-swc-rg' }
        @{ Name = 'prodskycraftswcsa';     ResourceGroup = 'prod-skycraft-swc-rg' })) {
    $blob = Get-AzStorageBlobServiceProperty -ResourceGroupName $account.ResourceGroup -StorageAccountName $account.Name
    $file = Get-AzStorageFileServiceProperty -ResourceGroupName $account.ResourceGroup -StorageAccountName $account.Name
    [pscustomobject]@{
        Account        = $account.Name
        BlobSoftDelete = $blob.DeleteRetentionPolicy.Days
        ContainerSoft  = $blob.ContainerDeleteRetentionPolicy.Days
        ShareSoftDel   = $file.ShareDeleteRetentionPolicy.Days
    }
}

# Expected output: 7 in every column for every account (Lab 4.3 later raises ShareSoftDel to 14 on prod)
```

### Verify Encryption Settings

```powershell
# Check encryption configuration
$encryption = (Get-AzStorageAccount -ResourceGroupName prod-skycraft-swc-rg -Name prodskycraftswcsa).Encryption
[pscustomobject]@{
    KeySource       = $encryption.KeySource
    BlobEncryption  = $encryption.Services.Blob.Enabled
    FileEncryption  = $encryption.Services.File.Enabled
    InfraEncryption = [bool]$encryption.RequireInfrastructureEncryption
}

# Expected output:
# KeySource          BlobEncryption    FileEncryption    InfraEncryption
# ---------          --------------    --------------    ---------------
# Microsoft.Storage  True              True              False
```

---

## 📊 Storage Accounts Summary

| Storage Account       | Resource Group           | Redundancy | TLS | Public Access | Encryption | Status |
| --------------------- | ------------------------ | ---------- | --- | ------------- | ---------- | ------ |
| platformskycraftswcsa | platform-skycraft-swc-rg | GRS        | 1.2 | Disabled      | MMK        | ✅     |
| devskycraftswcsa      | dev-skycraft-swc-rg      | LRS        | 1.2 | Disabled      | MMK        | ✅     |
| prodskycraftswcsa     | prod-skycraft-swc-rg     | GRS        | 1.2 | Disabled      | MMK        | ✅     |

---

## 📝 Reflection Questions

### Question 1: Redundancy Rationale

**Document your rationale for the redundancy level chosen for each environment:**

| Environment | Redundancy | Your Rationale                                     |
| ----------- | ---------- | -------------------------------------------------- |
| Platform    | GRS        | **\*\***\*\*\*\***\*\***\_**\*\***\*\*\*\***\*\*** |
| Development | LRS        | **\*\***\*\*\*\***\*\***\_**\*\***\*\*\*\***\*\*** |
| Production  | GRS        | **************\_**************                     |

### Question 2: Cost Analysis

**Research and document the approximate monthly cost per GB for each redundancy option in Sweden Central:**

| Redundancy | Cost per GB/month | 100 GB Monthly Cost |
| ---------- | ----------------- | ------------------- |
| LRS        | $\***\*\_\*\***   | $\***\*\_\*\***     |
| GRS        | $\***\*\_\*\***   | $\***\*\_\*\***     |
| GZRS       | $\***\*\_\*\***   | $\***\*\_\*\***     |

**Cost savings using LRS for dev instead of GZRS**: $\***\*\_\*\***

### Question 3: Disaster Recovery Scenario

**If Sweden Central experiences a complete regional outage:**

- Which storage accounts would survive? **\*\***\*\*\*\***\*\***\_**\*\***\*\*\*\***\*\***
- How would you access the production data? **\*\***\*\*\*\***\*\***\_**\*\***\*\*\*\***\*\***
- What is the expected RPO (Recovery Point Objective)? **\*\***\*\*\*\***\*\***\_**\*\***\*\*\*\***\*\***

### Question 4: Key Rotation Policy

**Document your organization's key rotation requirements:**

- Rotation frequency: **\*\***\*\*\*\***\*\***\_**\*\***\*\*\*\***\*\***
- Who is responsible for rotation? **\*\***\*\*\*\***\*\***\_**\*\***\*\*\*\***\*\***
- How would you automate this? **\*\***\*\*\*\***\*\***\_**\*\***\*\*\*\***\*\***

### Question 5: Troubleshooting Experience

**What challenges did you encounter during storage account creation? How did you resolve them?**

---

**Instructor Review Date**: \***\*\_\*\***
**Feedback**: ******\*\*******\*\*\*\*******\*\*******\_******\*\*******\*\*\*\*******\*\*******

---

## ⏱️ Completion Tracking

- **Estimated Time**: 2 hours
- **Actual Time Spent**: \***\*\_\*\*** hours
- **Date Started**: \***\*\_\*\***
- **Date Completed**: \***\*\_\*\***

---

## ✅ Final Lab 4.1 Sign-off

**All Verification Items Complete**:

- [ ] All three storage accounts created with correct names
- [ ] Appropriate redundancy levels configured (LRS for development, GRS for platform and production)
- [ ] Security settings applied (TLS 1.2, HTTPS only, no anonymous blob access)
- [ ] Soft delete on for blobs, containers and file shares (7 days)
- [ ] All required tags applied (Project, Environment, CostCenter, Owner)
- [ ] Encryption verified (Microsoft-managed keys)
- [ ] Access keys reviewed, and key1 of `prodskycraftswcsa` rotated
- [ ] All validation commands executed successfully
- [ ] All reflection questions answered
- [ ] Ready to proceed to Lab 4.2

**Student Name**: **\*\*\*\***\_**\*\*\*\***
**Lab 4.1 Completion Date**: **\*\*\*\***\_**\*\*\*\***
**Instructor Signature**: **\*\*\*\***\_**\*\*\*\***

---

## 🎉 Congratulations!

You've completed **Lab 4.1: Configure and Manage Storage Accounts**!

**What You Built**:

- ✅ Three storage accounts with environment-appropriate redundancy
- ✅ Platform (GRS), Development (LRS), Production (GRS)
- ✅ Secure configuration with TLS 1.2 and disabled public access
- ✅ Proper governance tags applied
- ✅ Encryption at rest verified

**Key Skills Demonstrated**:

- Creating storage accounts on one path (Portal, Az PowerShell, Azure CLI or Bicep) and mapping each Portal setting to its parameter
- Selecting appropriate redundancy options
- Configuring security best practices
- Managing and rotating access keys

**Next**: [Lab 4.2: Implement Azure Blob Storage →](../4.2-blob-storage/lab-guide-4.2.md)

In Lab 4.2, you'll create blob containers, configure access tiers, implement versioning and soft delete, and create lifecycle management policies.

---

## 📌 Module Navigation

- [← Back to Module 4 Index](../README.md)
- [Lab 4.2: Blob Storage →](../4.2-blob-storage/lab-guide-4.2.md)
