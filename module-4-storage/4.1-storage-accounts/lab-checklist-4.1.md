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
- [ ] Redundancy: **Geo-redundant storage (GRS)**
- [ ] Access tier: **Hot**

### Security Settings

- [ ] Secure transfer required: **Enabled**
- [ ] Allow Blob anonymous access: **Disabled**
- [ ] Minimum TLS version: **TLS 1.2**
- [ ] Storage account key access: **Enabled**
- [ ] Encryption: **Microsoft-managed keys**

### Tags

- [ ] Tag: `Project` = `SkyCraft`
- [ ] Tag: `Environment` = `Platform`
- [ ] Tag: `CostCenter` = `MSDN`

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
- [ ] Encryption: **Microsoft-managed keys**

### Tags

- [ ] Tag: `Project` = `SkyCraft`
- [ ] Tag: `Environment` = `Development`
- [ ] Tag: `CostCenter` = `MSDN`

---

## ✅ Production Storage Account (prodskycraftswcsa)

### Storage Configuration

- [ ] Storage account name: `prodskycraftswcsa`
- [ ] Location: **Sweden Central**
- [ ] Resource group: `prod-skycraft-swc-rg`
- [ ] Performance tier: **Standard**
- [ ] Account kind: **StorageV2 (general-purpose v2)**
- [ ] Redundancy: **Geo-redundant storage (GRS)**
- [ ] Access tier: **Hot**

### Security Settings

- [ ] Secure transfer required: **Enabled**
- [ ] Allow Blob anonymous access: **Disabled**
- [ ] Minimum TLS version: **TLS 1.2**
- [ ] Encryption: **Microsoft-managed keys**

### Tags

- [ ] Tag: `Project` = `SkyCraft`
- [ ] Tag: `Environment` = `Production`
- [ ] Tag: `CostCenter` = `MSDN`

---

## 🔍 Validation Commands

### Verify All Storage Accounts Exist

```azurecli
# List all SkyCraft storage accounts with key properties
az storage account list \
  --query "[?contains(name,'skycraft')].{Name:name,ResourceGroup:resourceGroup,SKU:sku.name,Location:location,TLS:minimumTlsVersion}" \
  --output table

# Expected output:
# Name                    ResourceGroup             SKU            Location       TLS
# ----------------------  ------------------------  -------------  -------------  ------
# platformskycraftswcsa   platform-skycraft-swc-rg  Standard_GRS   swedencentral  TLS1_2
# devskycraftswcsa        dev-skycraft-swc-rg       Standard_LRS   swedencentral  TLS1_2
# prodskycraftswcsa       prod-skycraft-swc-rg      Standard_GRS  swedencentral  TLS1_2
```

### Verify Security Settings

```azurecli
# Check production storage account security settings
az storage account show \
  --name prodskycraftswcsa \
  --resource-group prod-skycraft-swc-rg \
  --query "{Name:name,TLS:minimumTlsVersion,PublicAccess:allowBlobPublicAccess,SecureTransfer:enableHttpsTrafficOnly}" \
  --output table

# Expected output:
# Name                 TLS     PublicAccess    SecureTransfer
# -------------------  ------  --------------  ---------------
# prodskycraftswcsa    TLS1_2  false           true
```

### Verify Redundancy Configuration

```azurecli
# Check redundancy for each account
for sa in platformskycraftswcsa devskycraftswcsa prodskycraftswcsa; do
  echo "=== $sa ==="
  az storage account show --name $sa --query "{Name:name,SKU:sku.name,Kind:kind}" --output table
done

# Expected SKUs:
# platformskycraftswcsa: Standard_GRS
# devskycraftswcsa: Standard_LRS
# prodskycraftswcsa: Standard_GRS
```

### Verify Tags

```azurecli
# Check tags on each storage account
az storage account show \
  --name prodskycraftswcsa \
  --resource-group prod-skycraft-swc-rg \
  --query "tags" \
  --output json

# Expected output:
# {
#   "CostCenter": "MSDN",
#   "Environment": "Production",
#   "Project": "SkyCraft"
# }
```

### Verify Encryption Settings

```azurecli
# Check encryption configuration
az storage account show \
  --name prodskycraftswcsa \
  --resource-group prod-skycraft-swc-rg \
  --query "encryption.{KeySource:keySource,BlobEncryption:services.blob.enabled,FileEncryption:services.file.enabled}" \
  --output table

# Expected output:
# KeySource          BlobEncryption    FileEncryption
# -----------------  ----------------  ----------------
# Microsoft.Storage  true              true
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
- [ ] Appropriate redundancy levels configured (LRS, GRS, GZRS)
- [ ] Security settings applied (TLS 1.2, HTTPS only, no public access)
- [ ] All required tags applied (Project, Environment, CostCenter)
- [ ] Encryption verified (Microsoft-managed keys)
- [ ] Access keys reviewed
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

- Creating storage accounts via Portal and CLI/PowerShell
- Selecting appropriate redundancy options
- Configuring security best practices
- Managing access keys

**Next**: [Lab 4.2: Implement Azure Blob Storage →](../4.2-blob-storage/lab-guide-4.2.md)

In Lab 4.2, you'll create blob containers, configure access tiers, implement versioning and soft delete, and create lifecycle management policies.

---

## 📌 Module Navigation

- [← Back to Module 4 Index](../README.md)
- [Lab 4.2: Blob Storage →](../4.2-blob-storage/lab-guide-4.2.md)
