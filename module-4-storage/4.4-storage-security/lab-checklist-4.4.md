# Lab 4.4 Completion Checklist

## ✅ Storage Security Verification

### Network Configuration (Firewall)

- [ ] Storage Account: `prodskycraftswcst` (or your specific account)
- [ ] Public network access: `Enabled from selected virtual networks and IP addresses`
- [ ] Virtual Network Rule: `prod-skycraft-swc-vnet` / `ApplicationSubnet`
- [ ] Client IP Exception: Your current IP address is added

### Service Endpoint (VNet side)

- [ ] Virtual Network: `prod-skycraft-swc-vnet`
- [ ] Subnet: `ApplicationSubnet`
- [ ] Service Endpoint: `Microsoft.Storage` configured
- [ ] Status: **Succeeded**

---

## ✅ Access Control Verification

### Key Management

- [ ] **Key 1** was successfully rotated (regeneration date is today)
- [ ] Understanding of Active-Passive rotation confirmed

### Stored Access Policy (SAS)

- [ ] Container: `dev-assets` created
- [ ] Policy Name: `DevTeamPolicy`
- [ ] Policy Permissions: **Read**, **List** (initially)
- [ ] SAS Token generated linking to `DevTeamPolicy`
- [ ] **Revocation Test Passed**: Changing policy permissions immediately blocked SAS access

### Identity-Based Access (RBAC)

- [ ] Role Assignment: **Storage Blob Data Contributor** assigned to user
- [ ] Scope: Storage Account or Container level
- [ ] Verification: User successfully uploaded/deleted file via Portal/Explorer (Data Plane)

---

## 🔍 Validation Commands

Run these Azure CLI commands to validate your lab setup:

### Verify Network Rules

```azurecli
az storage account show \
  --resource-group prod-skycraft-swc-rg \
  --name prodskycraftswcst \
  --query "networkRuleSet" \
  --output yaml
```

### Verify Stored Access Policy

```azurecli
# Check if the policy exists on the container
az storage container policy list \
  --account-name prodskycraftswcst \
  --container-name dev-assets \
  --output table

# Expected Output:
# Name           Permissions    Expiry
# -------------  -------------  -------------------------
# DevTeamPolicy  rl             202X-XX-XXTXX:XX:XX+00:00
```

---

## 📊 Security Configuration Summary

| Feature            | Configuration                    | Status |
| ------------------ | -------------------------------- | ------ |
| **Public Access**  | Restricted to VNet + Client IP   | ✅     |
| **SAS Management** | Stored Access Policy (Revocable) | ✅     |
| **Authentication** | Hybrid (Policy + Azure AD)       | ✅     |
| **Key Health**     | Rotated                          | ✅     |

---

## 📝 Reflection Questions

### Question 1: Revocation Strategy

**Why is using a Stored Access Policy safer than generating a SAS token directly from the Account Key?**

---

---

### Question 2: RBAC vs Keys

**You assigned yourself "Storage Blob Data Contributor". Why couldn't you upload a file when you were just an "Owner" of the subscription (assuming keys were disabled)?**

---

---

### Question 3: Service Endpoint Security

**If an attacker gains access to a VM in the `ApplicationSubnet`, can they access the storage account? How would you further restrict this?**

---

---

**Instructor Review Date**: ****\_****  
**Feedback**: ********************************\_********************************

---

## ⏱️ Completion Tracking

- **Estimated Time**: 2.5 hours
- **Actual Time Spent**: ****\_**** hours
- **Date Started**: ****\_****
- **Date Completed**: ****\_****

**Challenges Encountered** (optional):

---

---

## ✅ Final Lab 4.4 Sign-off

**All Verification Items Complete**:

- [ ] Network rules restrict all unauthorized access
- [ ] Stored Access Policy created and verified revocable
- [ ] Key rotation procedure executed
- [ ] RBAC role assignment confirmed
- [ ] Ready to proceed to Lab 5.1

**Student Name**: ********\_********  
**Lab 4.4 Completion Date**: ********\_********  
**Instructor Signature**: ********\_********

---

## 🎉 Congratulations!

You've successfully completed **Lab 4.4: Implementing Storage Security**!

**What You Built**:

- ✅ A hardened storage account resistant to public internet attacks
- ✅ A revocable delegation system using Stored Access Policies
- ✅ A rotated and managed cryptographic identity foundation

**Next**: [Lab 5.1: Monitor Resources →](../../module-5-monitor/5.1-monitor-resources/lab-guide-5.1.md)

---

## 📌 Module Navigation

- [← Back to Module 4 Index](../README.md)
- [Lab 5.1: Monitor Resources →](../../module-5-monitor/5.1-monitor-resources/lab-guide-5.1.md)
