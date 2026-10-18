# Lab 4.4 Completion Checklist

## ✅ Storage Network Security Verification

### Firewall & Virtual Networks (Step 4.4.2)

- [ ] Storage Account: `prodskycraftswcsa`
- [ ] Public network access: **Enable**, scope **Enabled from selected networks** (firewall default action `Deny`)
- [ ] VNet Rule: `prod-skycraft-swc-vnet` / `WorldSubnet`
- [ ] Firewall: Your Client IP added to authorized addresses
- [ ] Exception: **Allow Azure services on the trusted services list to access this storage account** checked (`Bypass` `AzureServices`)

### Service Endpoints (prerequisite from Lab 2.2, checked in Step 4.4.1)

- [ ] VNet: `prod-skycraft-swc-vnet`
- [ ] Subnet: `WorldSubnet`
- [ ] Service Endpoint: `Microsoft.Storage` (Status: Succeeded)

> This endpoint is created and owned by **Lab 2.2**, not by this lab. Verify it is present before
> deploying - the storage firewall rejects a virtual network rule for a subnet without it.

---

## ✅ Access Control Verification

### SAS & Stored Access Policies (Steps 4.4.3 and 4.4.4)

- [ ] Container: `dev-assets` created (**Private**)
- [ ] Policy: `DevRevokePolicy` (Read, List permissions, expiry tomorrow) on `dev-assets`
- [ ] Functional Test: the container SAS URL listed `dev-assets`, and answered `AuthenticationFailed` (403) within 30 seconds of deleting the policy and saving
- [ ] The policy is deleted again (Step 4.4.4); the container stays

### Key Management (Steps 4.4.5 and 4.4.6)

- [ ] **Access Key 1** rotated (*Last rotated* shows today)
- [ ] **Access Key 2** rotated after it (*Last rotated* shows today)
- [ ] Understanding of Key 1 vs Key 2 rotation strategy confirmed (move to key2, rotate key1, move to key1, rotate key2)

### Identity-Based Access (RBAC) (Steps 4.4.7 and 4.4.8)

- [ ] Role: `Storage Blob Data Contributor` assigned to your account on `prodskycraftswcsa` (scope *This resource*)
- [ ] Verification: `hello-skycraft.txt` uploaded to `dev-assets` with **Authentication method** *Microsoft Entra user account* (or `-UseConnectedAccount`)

---

## 🔍 Validation Commands

Run these Az PowerShell commands to validate your lab setup. Run them on the computer whose IP address Step 4.4.2 allowed: commands 2 and 5 read the account's data, which the firewall refuses from any other address.

### 1. Verify Storage Firewall Rules

```powershell
Get-AzStorageAccountNetworkRuleSet -ResourceGroupName prod-skycraft-swc-rg -Name prodskycraftswcsa |
    Format-List DefaultAction, Bypass, @{N='VirtualNetworkRules';E={$_.VirtualNetworkRules.VirtualNetworkResourceId}}, @{N='IpRules';E={$_.IpRules.IPAddressOrRange}}

# Expected Output:
# DefaultAction       : Deny
# Bypass              : AzureServices
# VirtualNetworkRules : /subscriptions/.../virtualNetworks/prod-skycraft-swc-vnet/subnets/WorldSubnet
# IpRules             : <your public IPv4 address>
```

### 2. Verify Stored Access Policy

Between Steps 4.4.3 and 4.4.4 this lists the policy; after Step 4.4.4 it lists nothing, which is the end state.

```powershell
Get-AzRmStorageContainer -ResourceGroupName prod-skycraft-swc-rg -StorageAccountName prodskycraftswcsa -Name dev-assets |
    Select-Object Name, PublicAccess

$context = (Get-AzStorageAccount -ResourceGroupName prod-skycraft-swc-rg -Name prodskycraftswcsa).Context
Get-AzStorageContainerStoredAccessPolicy -Container dev-assets -Context $context |
    Select-Object Policy, Permissions, ExpiryTime |
    Format-Table -AutoSize

# Expected Output (between Steps 4.4.3 and 4.4.4):
# Policy            Permissions   ExpiryTime
# ------            -----------   ----------
# DevRevokePolicy   rl            202X-XX-XX XX:XX:XX +00:00
```

### 3. Verify Key Rotation

The output shows when each key was created or last rotated, never the key itself.

```powershell
Get-AzStorageAccountKey -ResourceGroupName prod-skycraft-swc-rg -Name prodskycraftswcsa |
    Select-Object KeyName, CreationTime

# Expected Output: key1 and key2, both with today's date, key2 later than key1.
```

### 4. Verify the Role Assignment

```powershell
$account = Get-AzStorageAccount -ResourceGroupName prod-skycraft-swc-rg -Name prodskycraftswcsa
Get-AzRoleAssignment -Scope $account.Id |
    Where-Object { $_.RoleDefinitionName -eq 'Storage Blob Data Contributor' -and $_.Scope -eq $account.Id } |
    Select-Object DisplayName, ObjectType, RoleDefinitionName

# Expected Output: your account, ObjectType User, Storage Blob Data Contributor.
```

### 5. Verify Data Access with Your Identity

```powershell
$entraContext = New-AzStorageContext -StorageAccountName prodskycraftswcsa -UseConnectedAccount
Get-AzStorageBlob -Container dev-assets -Context $entraContext | Select-Object Name, Length

# Expected Output: hello-skycraft.txt
```

### 6. Run the Lab Validator

```powershell
./scripts/Test-Lab.ps1
```

**Expected Result**: `Validation Complete. Failures: 0` and exit code 0. It prints the stored access policies it finds and when each key was last rotated, without counting them.

---

## 📊 Security Architecture Summary

| Component            | Security Feature     | Implementation              | Status |
| :------------------- | :------------------- | :-------------------------- | :----- |
| **Network**          | Service Endpoint     | VNet Integration + Firewall | ✅     |
| **Delegation**       | Stored Access Policy | Revocable SAS tokens        | ✅     |
| **Root Credentials** | Key Rotation         | Both keys, one at a time    | ✅     |
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

**What error message did you encounter when attempting to access the storage account from an unauthorized network (Step 4.4.4, item 7)?**

---

### Question 4: Key Rotation

**Which clients would have stopped working if you had rotated both keys at the same time, and why does the order key2 → key1 → key2 avoid that?**

---

## ⏱️ Completion Tracking

- **Estimated Time**: 2.5 hours
- **Actual Time Spent**: ****\_**** hours
- **Date Started**: ****\_****
- **Date Completed**: ****\_****

---

## 🧹 Cleanup Verification

`Remove-LabResource.ps1` reverts what this lab created:

- [ ] Storage firewall default action back to `Allow`
- [ ] Container `dev-assets` removed
- [ ] `Storage Blob Data Contributor` role assignments made on the account removed
- [ ] `WorldSubnet` **still** carries the `Microsoft.Storage` service endpoint

> The cleanup deliberately leaves that service endpoint in place: it belongs to Lab 2.2, whose
> `Test-Lab.ps1` asserts it. Remove it with Lab 2.2's own cleanup if you want it gone. A key
> rotation cannot be undone and needs no cleanup.
>
> While Lab 1.3's delete lock `lock-no-delete-prod` is on `prod-skycraft-swc-rg`, Azure refuses to
> delete the container and the role assignment (`ScopeLocked`), and the script exits 1. See
> **What This Lab Leaves Behind** in the guide (issue #372).

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
- ✅ Rotated root credentials
- ✅ An identity-led security model using RBAC

**Next**: [Lab 5.1: Monitoring →](../../module-5-monitoring-maintenance/5.1-azure-monitor/lab-guide-5.1.md)

---

## 📌 Module Navigation

- [← Back to Module 4 Index](../README.md)
- [Lab 5.1: Next Lab →](../../module-5-monitoring-maintenance/5.1-azure-monitor/lab-guide-5.1.md)
