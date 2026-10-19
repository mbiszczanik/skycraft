# Lab 1.2 Completion Checklist

## ✅ Resource Groups Creation

- [ ] **dev-skycraft-swc-rg** created
  - Region: Sweden Central
  - Tags: Environment = Development, Project = SkyCraft, CostCenter = MSDN, Owner = mbiszczanik
  - Purpose: Development and testing environment
  
- [ ] **prod-skycraft-swc-rg** created
  - Region: Sweden Central
  - Tags: Environment = Production, Project = SkyCraft, CostCenter = MSDN, Owner = mbiszczanik
  - Purpose: Production deployment
  
- [ ] **platform-skycraft-swc-rg** created
  - Region: Sweden Central
  - Tags: Environment = Platform, Project = SkyCraft, CostCenter = MSDN, Owner = mbiszczanik
  - Purpose: Shared services (monitoring, logging)

---

## ✅ Subscription-Level Role Assignments

- [ ] **Malfurion Stormrage** has **Owner** role
  - Scope: Subscription
  - Type: User
  - Condition: none, so the **Condition** column shows the **Add** link, not **View/Edit** (**Allow user to assign all roles (highly privileged)** on the **Conditions** tab, Step 1.2.4)
  - Assignment type: Active, Permanent (where the wizard shows an **Assignment type** tab)
  - Purpose: Full administrative control

---

## ✅ Resource Group: dev-skycraft-swc-rg

- [ ] **SkyCraft-Developers** (group) has **Contributor** role
  - Can create and manage resources
  - Can also delete the resource group itself (Contributor at this scope includes it)
  - Cannot assign roles
  
- [ ] **SkyCraft-Testers** (group) has **Reader** role
  - Can view all resources
  - Cannot modify anything
  - Read-only monitoring access

---

## ✅ Resource Group: prod-skycraft-swc-rg

- [ ] **SkyCraft-Testers** (group) has **Reader** role
  - Production monitoring access
  - View-only permissions

---

## ✅ Resource Group: platform-skycraft-swc-rg

- [ ] **Illidan Stormrage** (guest user) has **Reader** role
  - Limited to shared services only
  - No access to dev or prod
  - Guest user with restricted scope

---

## ✅ Access Verification

- [ ] Verified Khadgar Archmage's access (**Check access** tab → **Check access** button, opened on dev-skycraft-swc-rg)
  - Shows Contributor via SkyCraft-Developers
  - Scope: This resource (dev-skycraft-swc-rg)
  
- [ ] Verified Chromie Timewalker's access, once from each resource group
  - Opened on dev-skycraft-swc-rg: Reader via SkyCraft-Testers, scope This resource
  - Opened on prod-skycraft-swc-rg: Reader via SkyCraft-Testers, scope This resource
  - Check access lists the scope it is opened on and the scopes above it, never a sibling resource group
  
- [ ] Reviewed the role assignments made by this lab (**Role assignments** tab; each scope also lists the ones it inherits, such as your own)
  - Subscription: Malfurion Stormrage, Owner
  - dev-skycraft-swc-rg: 2 assignments at This resource
  - prod-skycraft-swc-rg: 1 assignment at This resource
  - platform-skycraft-swc-rg: 1 assignment at This resource
  
- [ ] Understand inheritance model
  - Subscription → Resource Group → Resource
  - Most permissive role wins

---

## ✅ Concepts Understood

- [ ] Difference between Owner, Contributor, and Reader
- [ ] Why assign roles to groups vs. individual users
- [ ] Understanding of scope (subscription vs. resource group)
- [ ] Role inheritance and permission precedence
- [ ] Principle of least privilege

---

## 🤖 Automation (optional)

The portal steps above have two scripted equivalents in `scripts/`. Pick one per subscription: each skips assignments that already exist, but the Bicep template cannot adopt assignments the imperative script created.

- [ ] Declarative - resource groups and the five role assignments from `bicep/role-assignments.bicep`, with principal IDs resolved from Entra ID:
  ```powershell
  .\scripts\Deploy-Bicep.ps1 -IncludeRoleAssignments -WhatIf   # preview
  .\scripts\Deploy-Bicep.ps1 -IncludeRoleAssignments           # deploy
  ```
- [ ] Imperative - the same five assignments through the Azure Resource Manager role assignments API:
  ```powershell
  .\scripts\Deploy-Bicep.ps1              # resource groups only
  .\scripts\New-LabRoleAssignment.ps1     # Graph sign-in in the lab tenant (see below)
  ```
  Run both in the PowerShell session where you ran `Connect-AzAccount -TenantId '<your tenant id>'`: `New-LabRoleAssignment.ps1` signs in to Microsoft Graph in the tenant `SKYCRAFT_GRAPH_TENANT_ID` names, else in the tenant of a Microsoft Graph sign-in already in the session, else in the Az context's tenant, which a personal Microsoft account needs to reach the lab tenant. That Az context can also be one Az PowerShell restored from an earlier session, so check it with `Get-AzContext` first. If Microsoft Graph is already signed in to another tenant, the script stops with `[ERROR]` and names both tenants.
- [ ] Validated with `.\scripts\Test-Lab.ps1`

---

## 🔍 Validation Steps

Execute these validation steps to confirm success:

### Step 1: List all resource groups

```powershell
Get-AzResourceGroup |
    Select-Object ResourceGroupName, Location |
    Format-Table -AutoSize
```

### Step 2: Check role assignments at subscription level

```powershell
$subscriptionId = (Get-AzContext).Subscription.Id
Get-AzRoleAssignment -Scope "/subscriptions/$subscriptionId" |
    Where-Object Scope -eq "/subscriptions/$subscriptionId" |
    Select-Object DisplayName, RoleDefinitionName, Scope, Condition |
    Format-Table -AutoSize
```

Malfurion Stormrage's Owner row has an empty `Condition`.

### Step 3: Check role assignments for dev-skycraft-swc-rg
```powershell
Get-AzRoleAssignment -ResourceGroupName dev-skycraft-swc-rg |
    Select-Object DisplayName, RoleDefinitionName |
    Format-Table -AutoSize
```

### Step 4: Check specific user's roles
```powershell
# -ExpandPrincipalGroups adds the roles Khadgar has through his groups, as Check access shows them
Get-AzRoleAssignment -SignInName 'khadgar.archmage@[yourtenant].onmicrosoft.com' -ExpandPrincipalGroups |
    Select-Object DisplayName, RoleDefinitionName, Scope |
    Format-Table -AutoSize
```

Khadgar Archmage has one row: SkyCraft-Developers, Contributor, on `dev-skycraft-swc-rg`.

**Expected Output**:
- 3 resource groups listed
- Multiple role assignments across scopes
- Group-based assignments visible

---

## 📊 Assignment Summary

| Principal | Type | Role | Scope | Purpose |
|-----------|------|------|-------|---------|
| Malfurion Stormrage | User | Owner | Subscription | Full admin access |
| SkyCraft-Developers | Group | Contributor | dev-skycraft-swc-rg | Dev environment management |
| SkyCraft-Testers | Group | Reader | dev-skycraft-swc-rg | Dev monitoring |
| SkyCraft-Testers | Group | Reader | prod-skycraft-swc-rg | Prod monitoring |
| Illidan Stormrage | User (Guest) | Reader | platform-skycraft-swc-rg | Limited shared access |

**Total Assignments**: 5

---

## ⏱️ Completion Time

- **Estimated Time**: 2 hours
- **Actual Time Spent**: _________
- **Date Started**: _________
- **Date Completed**: _________

---

## 📝 Reflection Questions

Answer these to deepen understanding:

1. **Why did we assign Contributor instead of Owner to developers?**
   
   Answer: ___________________________________________________

2. **What would happen if we assigned Reader at subscription level and Contributor at resource group level for the same user?**
   
   Answer: ___________________________________________________

3. **How would you grant a user permission to ONLY manage virtual machines in dev-skycraft-swc-rg?**
   
   Answer: ___________________________________________________

---

## ✅ Final Sign-off

- [ ] All role assignments completed successfully
- [ ] Access verification passed
- [ ] CLI validation commands executed
- [ ] Concepts understood and documented
- [ ] Ready to proceed to Lab 1.3

**Student Name**: _________________  
**Completion Date**: _________________  
**Instructor Signature**: _________________  