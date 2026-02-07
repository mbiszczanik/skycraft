# Lab 5.2 Completion Checklist

> **Purpose**: This checklist verifies correct implementation of Lab 5.2: Business Continuity & Disaster Recovery.

---

## ✅ Recovery Services Vault (platform-skycraft-swc-rsv)

### Vault Configuration

- [ ] Vault name: `platform-skycraft-swc-rsv`
- [ ] Location: **Sweden Central**
- [ ] Resource group: `platform-skycraft-swc-rg`
- [ ] Storage replication type: (Circle one) **LRS** / **GRS**
- [ ] Soft delete: **Enabled** (Default)

---

## ✅ Backup Policy

### Policy Details

- [ ] Policy name: `SkyCraft-Daily-Prod`
- [ ] Backup frequency: **Daily**
- [ ] Retention (Daily): **30 days**
- [ ] Snapshot retention: **2 days**

---

## ✅ Protected Items

### VM Protection

- [ ] Production VM (e.g., `prod-skycraft-vm`) listed under **Backup items**
- [ ] Initial backup status: **Completed** or **Warning** (if still pending)
- [ ] Last backup status: **Success**

---

## ✅ Backup Vault (platform-skycraft-swc-bv)

### Blob Protection

- [ ] Vault `platform-skycraft-swc-bv` deployed (LRS)
- [ ] Policy `SkyCraft-Blob-Policy` created
- [ ] Storage account linked to backup policy

---

## ✅ Azure Site Recovery (ASR)

### Replication Status

- [ ] `prod-skycraft-vm` replication status: **Protected**
- [ ] Target region: **Norway East**
- [ ] Test Failover performed successfully
- [ ] Cleanup of test resources completed

---

## 🔍 Validation Commands

### Verify Vault Exists via CLI

```azurecli
# List vaults in the platform resource group
az backup vault list \
  --resource-group platform-skycraft-swc-rg \
  --query "[?name=='platform-skycraft-swc-rsv'].{Name:name,Location:location,SKU:sku.name}" \
  --output table
```

### Verify Backup Policy

```azurecli
# Get policy details
az backup policy show \
  --name SkyCraft-Daily-Prod \
  --resource-group platform-skycraft-swc-rg \
  --vault-name platform-skycraft-swc-rsv \
  --output json
```

### Verify Backup Status of VM

```azurecli
# List items protected in the vault
az backup item list \
  --vault-name platform-skycraft-swc-rsv \
  --resource-group platform-skycraft-swc-rg \
  --output table
```

### Verify Backup Vault

```azurecli
az dataprotection backup-vault list \
  --resource-group platform-skycraft-swc-rg \
  --query "[].{Name:name,Region:location,State:properties.provisioningState}" \
  --output table
```

### Verify Site Recovery Replication

```azurecli
az network vnet list \
  --resource-group platform-skycraft-swc-rg \
  --query "[?contains(location, 'norway')].{Name:name,Location:location}" \
  --output table
```

---

## 📊 Backup Summary

| Resource           | Protected? | Policy                | Last Backup |
| :----------------- | :--------- | :-------------------- | :---------- |
| `prod-skycraft-vm` | [ ]        | `SkyCraft-Daily-Prod` | [ ]         |
| `dev-skycraft-vm`  | [ ]        | (None)                | N/A         |

---

## 📝 Reflection Questions

### Question 1: RPO and RTO

**Define RPO (Recovery Point Objective) and RTO (Recovery Time Objective) for this lab's backup policy.**

---

### Question 2: Soft Delete Security

**How does Soft Delete prevent a "hostile admin" from permanently deleting backups?**

---

### Question 3: File-Level Recovery

**Under what circumstances would you choose File-Level Recovery over reclaiming a whole VM?**

---

---

## ✅ Final Lab 5.2 Sign-off

**All Verification Items Complete**:

- [ ] Recovery Services Vault deployed
- [ ] Backup policy created correctly
- [ ] VM registered and initial backup triggered
- [ ] Recovery options (File Recovery) understood and tested
- [ ] Ready to proceed to Lab 5.3

**Student Name**: **\*\***\_\_\_\_**\*\***
**Lab 5.2 Completion Date**: **\*\***\_\_\_\_**\*\***
