# Lab 1.2 Completion Checklist

## ✅ Resource Groups Creation

- [ ] **dev-skycraft-swc-rg** created
  - Region: Sweden Central (or selected region)
  - Purpose: Development and testing environment
  
- [ ] **prod-skycraft-swc-rg** created
  - Region: Sweden Central
  - Purpose: Production deployment
  
- [ ] **platform-skycraft-swc-rg** created
  - Region: Sweden Central
  - Purpose: Shared services (monitoring, logging)

---

## ✅ Subscription-Level Role Assignments

- [ ] **SkyCraft Admin** has **Owner** role
  - Scope: Subscription
  - Type: User
  - Purpose: Full administrative control

---

## ✅ Resource Group: dev-skycraft-swc-rg

- [ ] **SkyCraft-Developers** (group) has **Contributor** role
  - Can create and manage resources
  - Cannot delete resource group
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

- [ ] **External Partner Consultant** (user) has **Reader** role
  - Limited to shared services only
  - No access to dev or prod
  - Guest user with restricted scope

---

## ✅ Access Verification

- [ ] Verified SkyCraft Developer access (Check access feature)
  - Shows Contributor via group membership
  - Scope: dev-skycraft-swc-rg
  
- [ ] Verified SkyCraft Tester access
  - Shows Reader via group membership
  - Scope: dev-skycraft-swc-rg and prod-skycraft-swc-rg
  
- [ ] Reviewed all role assignments in IAM blade
  - Subscription: 1 assignment
  - dev-skycraft-swc-rg: 2 assignments
  - prod-skycraft-swc-rg: 1 assignment
  - platform-skycraft-swc-rg: 1 assignment
  
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
- [ ] Imperative - the same five assignments through `New-AzRoleAssignment`:
  ```powershell
  .\scripts\Deploy-Bicep.ps1              # resource groups only
  .\scripts\New-LabRoleAssignment.ps1
  ```
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
    Select-Object DisplayName, RoleDefinitionName, Scope |
    Format-Table -AutoSize
```

### Step 3: Check role assignments for dev-skycraft-swc-rg
```powershell
Get-AzRoleAssignment -ResourceGroupName dev-skycraft-swc-rg |
    Select-Object DisplayName, RoleDefinitionName |
    Format-Table -AutoSize
```

### Step 4: Check specific user's roles
```powershell
Get-AzRoleAssignment -SignInName 'skycraft-dev@[yourtenant].onmicrosoft.com' |
    Select-Object RoleDefinitionName, Scope |
    Format-Table -AutoSize
```

**Expected Output**:
- 3 resource groups listed
- Multiple role assignments across scopes
- Group-based assignments visible

---

## 📊 Assignment Summary

| Principal | Type | Role | Scope | Purpose |
|-----------|------|------|-------|---------|
| SkyCraft Admin | User | Owner | Subscription | Full admin access |
| SkyCraft-Developers | Group | Contributor | dev-skycraft-swc-rg | Dev environment management |
| SkyCraft-Testers | Group | Reader | dev-skycraft-swc-rg | Dev monitoring |
| SkyCraft-Testers | Group | Reader | prod-skycraft-swc-rg | Prod monitoring |
| External Partner | User (Guest) | Reader | platform-skycraft-swc-rg | Limited shared access |

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