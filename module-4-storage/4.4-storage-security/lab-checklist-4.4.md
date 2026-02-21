# Lab 4.4 Completion Checklist

## ✅ Storage Network Security Verification

### Firewall & Virtual Networks

- [ ] Storage Account: `prodskycraftswcsa`
- [ ] Public access: `Enabled from selected virtual networks and IP addresses`
- [ ] VNet Rule: `prod-skycraft-swc-vnet` / `ApplicationSubnet`
- [ ] Firewall: Your Client IP added to authorized addresses

### Service Endpoints

- [ ] VNet: `prod-skycraft-swc-vnet`
- [ ] Subnet: `ApplicationSubnet`
- [ ] Service Endpoint: `Microsoft.Storage` (Status: Succeeded)

---

## ✅ Access Control Verification

### Key Management

- [ ] **Access Key 1** rotated (Verify "Last regenerated" timestamp)
- [ ] Understanding of Key 1 vs Key 2 rotation strategy confirmed

### SAS & Stored Access Policies

- [ ] Container: `dev-assets` created
- [ ] Policy: `DevRevokePolicy` (Read, List permissions)
- [ ] Functional Test: SAS token invalidated immediately upon policy deletion

### Identity-Based Access (RBAC)

- [ ] Role: `Storage Blob Data Contributor` assigned to your account
- [ ] Verification: Connection via OAuth/Entra ID allowed file upload/deletion

---

## 🔍 Validation Commands

Run these Azure CLI commands to validate your lab setup:

### 1. Verify Storage Firewall Rules

```azurecli
az storage account show \
  --name prodskycraftswcsa \
  --resource-group prod-skycraft-swc-rg \
  --query "networkRuleSet" \
  --output yaml
```

### 2. Verify Stored Access Policy

```azurecli
az storage container policy list \
  --account-name prodskycraftswcsa \
  --container-name dev-assets \
  --output table

# Expected Output:
# Name              Permissions    Expiry
# ----------------  -------------  -------------------------
# DevRevokePolicy   rl             202X-XX-XXTXX:XX:XX+00:00
```

---

## 📊 Security Architecture Summary

| Component            | Security Feature     | Implementation              | Status |
| :------------------- | :------------------- | :-------------------------- | :----- |
| **Network**          | Service Endpoint     | VNet Integration + Firewall | ✅     |
| **Delegation**       | Stored Access Policy | Revocable SAS tokens        | ✅     |
| **Root Credentials** | Key Rotation         | Managed Key Lifecycle       | ✅     |
| **Identity**         | RBAC                 | Entra ID Data Plane Access  | ✅     |

---

## 📝 Reflection Questions

### Question 1: SAS Security

**Explain how a Stored Access Policy improves security over an ad-hoc SAS token during a leak incident:**

---

### Question 2: RBAC Separation

**Why is it a security best practice to separate Management Plane (Owner) from Data Plane (Storage Blob Data Contributor) access?**

---

### Question 3: Network Lockdown

**What error message did you encounter when attempting to access the storage account from an unauthorized network?**

---

---

## ⏱️ Completion Tracking

- **Estimated Time**: 2.5 hours
- **Actual Time Spent**: ****\_**** hours
- **Date Started**: ****\_****
- **Date Completed**: ****\_****

---

## ✅ Final Lab 4.4 Sign-off

**All Verification Items Complete**:

- [ ] Network rules restrict all unauthorized access
- [ ] Stored Access Policy created and verified revocable
- [ ] Key rotation procedure executed successfully
- [ ] RBAC role assignment confirmed
- [ ] Ready to proceed to Lab 5.1

**Student Name**: ********\_********  
**Instructor Signature**: ********\_********

---

## 🎉 Congratulations!

You've successfully completed **Lab 4.4: Implementing Storage Security**!

**What You Built**:

- ✅ A hardened storage account isolated from public internet
- ✅ A revocable delegation system for developers
- ✅ An identity-led security model using RBAC

**Next**: [Lab 5.1: Monitoring →](../../module-5-monitoring-maintenance/5.1-azure-monitor/lab-guide-5.1.md)

---

## 📌 Module Navigation

- [← Back to Module 4 Index](../README.md)
- [Lab 5.1: Next Lab →](../../module-5-monitoring-maintenance/5.1-azure-monitor/lab-guide-5.1.md)
