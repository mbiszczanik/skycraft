# Lab 4.4 Completion Checklist

## ✅ Storage Network Security Verification

### Firewall & Virtual Networks

- [ ] Storage Account: `prodskycraftswcsa`
- [ ] Public access: `Enabled from selected virtual networks and IP addresses`
- [ ] VNet Rule: `prod-skycraft-swc-vnet` / `WorldSubnet`
- [ ] Firewall: Your Client IP added to authorized addresses
- [ ] Unauthorized access returns **HTTP 403**

### Service Endpoints

- [ ] VNet: `prod-skycraft-swc-vnet`
- [ ] Subnet: `WorldSubnet`
- [ ] Service Endpoint: `Microsoft.Storage` (Status: **Succeeded**)

### Tags

- [ ] Tag: `Project` = `SkyCraft`
- [ ] Tag: `Environment` = `Production`
- [ ] Tag: `CostCenter` = `MSDN`

---

## ✅ Ad-hoc SAS Token Verification

- [ ] Ad-hoc SAS token generated with read+list permissions, HTTPS only, 1-hour expiry
- [ ] SAS token tested successfully (container list returned via CLI or browser)
- [ ] Understanding of ad-hoc SAS revocation limitation confirmed (cannot revoke without key rotation)

---

## ✅ SAS & Stored Access Policy Verification

- [ ] Container: `dev-assets` created with **Private** access level
- [ ] Stored Access Policy: `DevRevokePolicy` created (Read, List permissions)
- [ ] SAS token generated via policy — access confirmed working
- [ ] Policy deleted — SAS token returns **403 Forbidden** (revocation confirmed)

---

## ✅ Identity-Based Access (RBAC) Verification

- [ ] Role: `Storage Blob Data Contributor` assigned to your account on `prodskycraftswcsa`
- [ ] Authentication method set to **Microsoft Entra user account** (not Access key)
- [ ] Blob upload via OAuth/Entra ID confirmed working
- [ ] Blob list via OAuth/Entra ID confirmed working

---

## 🔍 Validation Commands

### 1. Verify Service Endpoint (Azure CLI)

```azurecli
az network vnet subnet show \
  --resource-group prod-skycraft-swc-rg \
  --vnet-name prod-skycraft-swc-vnet \
  --name WorldSubnet \
  --query "serviceEndpoints[?service=='Microsoft.Storage'].{Service:service, Status:provisioningState}" \
  --output table

# Expected output:
# Service             Status
# ------------------  -----------
# Microsoft.Storage   Succeeded
```

### 1b. Verify Service Endpoint (PowerShell)

```powershell
$vnet = Get-AzVirtualNetwork -Name 'prod-skycraft-swc-vnet' -ResourceGroupName 'prod-skycraft-swc-rg'
($vnet.Subnets | Where-Object Name -eq 'WorldSubnet').ServiceEndpoints |
  Where-Object Service -eq 'Microsoft.Storage' |
  Select-Object Service, ProvisioningState | Format-Table

# Expected output:
# Service             ProvisioningState
# -------             -----------------
# Microsoft.Storage   Succeeded
```

### 2. Verify Storage Firewall Rules (Azure CLI)

```azurecli
az storage account show \
  --name prodskycraftswcsa \
  --resource-group prod-skycraft-swc-rg \
  --query "networkRuleSet.{DefaultAction:defaultAction, VNetRules:virtualNetworkRules[].virtualNetworkResourceId, IPRules:ipRules[].ipAddressOrRange}" \
  --output json

# Expected output (structure):
# {
#   "DefaultAction": "Deny",
#   "VNetRules": ["...WorldSubnet"],
#   "IPRules": ["<YOUR_IP>"]
# }
```

### 2b. Verify Storage Firewall Rules (PowerShell)

```powershell
$sa = Get-AzStorageAccount -ResourceGroupName 'prod-skycraft-swc-rg' -Name 'prodskycraftswcsa'
$sa.NetworkRuleSet | Select-Object DefaultAction,
  @{N='VNetRules';E={$_.VirtualNetworkRules.VirtualNetworkResourceId -join ', '}},
  @{N='IPRules';E={$_.IpRules.IPAddressOrRange -join ', '}}

# Expected output:
# DefaultAction  VNetRules                                 IPRules
# -------------  ---------                                 -------
# Deny           ...WorldSubnet                      <YOUR_IP>
```

### 3. Verify Stored Access Policy (Azure CLI)

```azurecli
az storage container policy list \
  --account-name prodskycraftswcsa \
  --container-name dev-assets \
  --auth-mode login \
  --output table

# Expected output (before deletion):
# Name              Permissions    Expiry
# ----------------  -------------  -------------------------
# DevRevokePolicy   rl             202X-XX-XXTXX:XX:XX+00:00
```

### 3b. Verify Stored Access Policy (PowerShell)

```powershell
$ctx = (Get-AzStorageAccount -ResourceGroupName 'prod-skycraft-swc-rg' -Name 'prodskycraftswcsa').Context
Get-AzStorageContainerStoredAccessPolicy -Container 'dev-assets' -Context $ctx | Format-Table

# Expected output (before deletion):
# Policy            Permission  StartTime  ExpiryTime
# ------            ----------  ---------  ----------
# DevRevokePolicy   rl                     <30 days from creation>
```

### 4. Verify RBAC Assignment (Azure CLI)

```azurecli
az role assignment list \
  --scope "/subscriptions/<SUB_ID>/resourceGroups/prod-skycraft-swc-rg/providers/Microsoft.Storage/storageAccounts/prodskycraftswcsa" \
  --query "[?roleDefinitionName=='Storage Blob Data Contributor'].{Principal:principalName, Role:roleDefinitionName}" \
  --output table

# Expected output:
# Principal           Role
# ------------------  --------------------------------
# your@email.com      Storage Blob Data Contributor
```

### 4b. Verify RBAC Assignment (PowerShell)

```powershell
$storageId = (Get-AzStorageAccount -ResourceGroupName 'prod-skycraft-swc-rg' -Name 'prodskycraftswcsa').Id
Get-AzRoleAssignment -Scope $storageId |
  Where-Object RoleDefinitionName -eq 'Storage Blob Data Contributor' |
  Select-Object DisplayName, RoleDefinitionName | Format-Table

# Expected output:
# DisplayName         RoleDefinitionName
# -----------         ------------------
# Your Name           Storage Blob Data Contributor
```

### 5. Verify Tags (Azure CLI)

```azurecli
az storage account show \
  --name prodskycraftswcsa \
  --resource-group prod-skycraft-swc-rg \
  --query "tags" \
  --output json

# Expected output:
# {
#   "Project": "SkyCraft",
#   "Environment": "Production",
#   "CostCenter": "MSDN"
# }
```

### 5b. Verify Tags (PowerShell)

```powershell
(Get-AzStorageAccount -ResourceGroupName 'prod-skycraft-swc-rg' -Name 'prodskycraftswcsa').Tags

# Expected output:
# Key           Value
# ---           -----
# Project       SkyCraft
# Environment   Production
# CostCenter    MSDN
```

---

## 📊 Security Architecture Summary

| Component           | Security Feature     | Implementation              | Status |
| :------------------ | :------------------- | :-------------------------- | :----- |
| **Network**         | Service Endpoint     | VNet Integration + Firewall | ✅     |
| **Delegation**      | Ad-hoc SAS           | Time-limited shared access  | ✅     |
| **Rev. Delegation** | Stored Access Policy | Revocable SAS tokens        | ✅     |
| **Identity**        | RBAC                 | Entra ID Data Plane Access  | ✅     |

---

## 📝 Reflection Questions

### Question 1: Incident Response

**A developer's laptop was stolen and it had a SAS token. Document the steps you would take to revoke access, and how those steps differ based on whether the SAS was ad-hoc or policy-based.**

---

---

---

---

### Question 2: Defense-in-Depth

**Document which of the four security layers you configured (Network, Keys, SAS, RBAC) would stop each of the following attack scenarios:**

| Attack Scenario                                              | Which Layer Blocks It? |
| ------------------------------------------------------------ | ---------------------- |
| Attacker on public internet tries to access blobs            | \***\*\_\_\*\***       |
| Stolen SAS token used from an authorized VNet                | \***\*\_\_\*\***       |
| Disgruntled employee with Owner role tries to download blobs | \***\*\_\_\*\***       |

---

### Question 3: Operational Experience

**What was the most challenging part of this lab? How did you resolve it?**

---

---

**Instructor Review Date**: **\_\_\_\_**
**Feedback**: **\*\***\*\***\*\***\*\*\*\***\*\***\*\***\*\***\_**\*\***\*\***\*\***\*\*\*\***\*\***\*\***\*\***

---

## ⏱️ Completion Tracking

- **Estimated Time**: 2.5 hours
- **Actual Time Spent**: \***\*\_\*\*** hours
- **Date Started**: \***\*\_\*\***
- **Date Completed**: \***\*\_\*\***

---

## ✅ Final Lab 4.4 Sign-off

**All Verification Items Complete**:

- [ ] Network rules restrict all unauthorized access
- [ ] Ad-hoc SAS token generated and tested
- [ ] Stored Access Policy created and revocation verified
- [ ] RBAC role assignment confirmed with data plane upload
- [ ] All tags applied (Project, Environment, CostCenter)
- [ ] All validation commands executed successfully
- [ ] All reflection questions answered
- [ ] Ready to proceed to Lab 5.1

**Student Name**: \***\*\_\*\***
**Lab 4.4 Completion Date**: \***\*\_\*\***
**Instructor Signature**: \***\*\_\*\***

---

## 🎉 Congratulations!

You've successfully completed **Lab 4.4: Implementing Storage Security**!

**What You Built**:

- ✅ A hardened storage account isolated from public internet via Service Endpoints
- ✅ Ad-hoc SAS tokens generated and their non-revocable limitation experienced
- ✅ A revocable delegation system for developers via Stored Access Policies
- ✅ An identity-led security model using Entra ID RBAC on the data plane

**Next**: [Lab 5.1: Monitor Resources →](../../module-5-monitor/5.1-monitor-resources/lab-guide-5.1.md)

---

## 📌 Module Navigation

- [← Back to Module 4 Index](../README.md)
- [← Previous Lab: 4.3 - Azure Files](../4.3-azure-files/lab-guide-4.3.md)
- [Lab 5.1: Monitor Resources →](../../module-5-monitor/5.1-monitor-resources/lab-guide-5.1.md)
