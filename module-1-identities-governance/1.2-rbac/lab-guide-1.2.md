# Lab 1.2: Manage Access to Azure Resources (RBAC) (2 hours)

## 🎯 Lab Objectives

By completing this lab, you will:

- Understand Azure RBAC (Role-Based Access Control) fundamentals
- Assign built-in Azure roles at different scopes
- Configure role assignments for users and groups
- Interpret and verify access assignments
- Implement least-privilege access principles for the SkyCraft team

---

## 📋 Real-World Scenario

**Situation**: You've created the SkyCraft team (Lab 1.1), but they currently have no permissions to manage Azure resources. You need to grant appropriate access levels:

- **SkyCraft Admin** → Full control over all SkyCraft resources
- **SkyCraft-Developers group** → Can create and manage VMs and storage, but cannot delete resource groups
- **SkyCraft-Testers group** → Read-only access to monitor resources
- **External Partner** → Read-only access to a specific resource group only

**Your Task**: Assign appropriate RBAC roles at the correct scopes to enable the team to work effectively while maintaining security.

---

## ⏱️ Estimated Time: 2 hours

- **Section 1**: Understand RBAC concepts and scopes (20 min)
- **Section 2**: Create resource groups for SkyCraft (15 min)
- **Section 3**: Assign roles at subscription scope (25 min)
- **Section 4**: Assign roles at resource group scope (30 min)
- **Section 5**: Verify and test access (20 min)
- **Hands-on Practice**: Modify role assignments (10 min)

---

## ✅ Prerequisites

Before starting this lab:

- [ ] Completed Lab 1.1 (users and groups created)
- [ ] Azure subscription with Owner or User Access Administrator role
- [ ] Understanding of resource groups concept
- [ ] Azure Portal access

**Verify Lab 1.1 completion**: Confirm these exist:

- Users: SkyCraft Admin, SkyCraft Developer, SkyCraft Tester
- Groups: SkyCraft-Admins, SkyCraft-Developers, SkyCraft-Testers

---

## 📖 Section 1: Understanding Azure RBAC (20 minutes)

### What is Azure RBAC?

**Azure RBAC** (Role-Based Access Control) is an authorization system that helps you manage **who** has access to Azure resources, **what** they can do with those resources, and **where** they have access.

### The Three Core Components

1. **Security Principal** (WHO)

   - User (e.g., SkyCraft Admin)
   - Group (e.g., SkyCraft-Developers)
   - Service Principal
   - Managed Identity

2. **Role Definition** (WHAT)

   - Collection of permissions
   - Examples: Owner, Contributor, Reader
   - Built-in or Custom roles

3. **Scope** (WHERE)
   - Management Group
   - Subscription
   - Resource Group
   - Individual Resource

### Common Built-in Roles

| Role                            | Description                                      | Use Case                            |
| ------------------------------- | ------------------------------------------------ | ----------------------------------- |
| **Owner**                       | Full access including role assignments           | Admins managing entire environments |
| **Contributor**                 | Can create/manage resources but not grant access | Developers deploying infrastructure |
| **Reader**                      | View-only access                                 | Auditors, monitoring teams, testers |
| **Virtual Machine Contributor** | Manage VMs but not networking/storage            | Specialized VM administrators       |
| **Storage Account Contributor** | Manage storage accounts                          | Storage specialists                 |

### Understanding Scope Hierarchy

```
Management Group (broadest)
└── Subscription
    └── Resource Group
        └── Resource (most specific)
```

**Key Concept**: Permissions are **inherited** down the hierarchy. A role assigned at subscription level applies to all resource groups and resources within that subscription.

### Best Practices

1. **Principle of Least Privilege** → Grant minimum permissions needed
2. **Assign roles to groups, not individual users** → Easier management
3. **Use built-in roles when possible** → Custom roles add complexity
4. **Assign at appropriate scope** → Subscription for broad access, resource group for specific projects

---

## 📖 Section 2: Create Resource Groups (15 minutes)

Before assigning roles, create resource groups for the SkyCraft project.

### Step 2.1: Create Development Resource Group

1. In **Azure Portal**, search for **"Resource groups"**
2. Click **+ Create**
3. Fill in the details:

| Field          | Value                                     |
| -------------- | ----------------------------------------- |
| Subscription   | [Your subscription]                       |
| Resource group | dev-skycraft-swc-rg                       |
| Region         | Sweden Central (or your preferred region) |

4. Click **Review + Create** → **Create**

**Expected Result**: Resource group `dev-skycraft-swc-rg` appears in the list.

### Step 2.2: Create Production Resource Group

1. Click **+ Create** again
2. Fill in:

| Field          | Value                |
| -------------- | -------------------- |
| Subscription   | [Your subscription]  |
| Resource group | prod-skycraft-swc-rg |
| Region         | Sweden Central       |

3. Click **Review + Create** → **Create**

### Step 2.3: Create Shared Services Resource Group

1. Click **+ Create**
2. Fill in:

| Field          | Value                    |
| -------------- | ------------------------ |
| Subscription   | [Your subscription]      |
| Resource group | platform-skycraft-swc-rg |
| Region         | Sweden Central           |

3. Click **Review + Create** → **Create**

**Expected Result**: Three resource groups created:

- `dev-skycraft-swc-rg` (for development/testing)
- `prod-skycraft-swc-rg` (for production deployment)
- `platform-skycraft-swc-rg` (for shared resources like monitoring)

---

## 📖 Section 3: Assign Roles at Subscription Scope (25 minutes)

### Step 3.1: Assign Owner Role to Admin User

1. In Azure Portal, go to **Subscriptions**
2. Click on your subscription name
3. In the left menu, click **Access control (IAM)**
4. Click **+ Add** → **Add role assignment**

**Important**: The role assignment wizard has three tabs: Role, Members, Review

5. **Role tab**:

   - Search for **"Owner"**
   - Select **Owner** role
   - Click **Next**

6. **Members tab**:

   - Select **Assign access to**: User, group, or service principal
   - Click **+ Select members**
   - Search for **"SkyCraft Admin"**
   - Select the user
   - Click **Select**
   - Click **Next**

7. **Review + assign tab**:
   - Review the assignment
   - Click **Review + assign**

**Expected Result**: SkyCraft Admin now has Owner permissions at subscription level.

**Screenshot**: [Would show role assignment completion]

### Step 3.2: Verify Role Assignment

1. Still in **Access control (IAM)**, click **Role assignments** tab
2. Search for **"SkyCraft Admin"**
3. Verify **Owner** role appears with **Subscription** scope

**Expected Result**: You see the assignment listed with these details:

- Name: SkyCraft Admin
- Role: Owner
- Scope: Subscription (your subscription name)
- Type: User

---

## 📖 Section 4: Assign Roles at Resource Group Scope (30 minutes)

Now assign more specific roles at resource group level for the development team.

### Step 4.1: Assign Contributor Role to Developers Group (Dev Environment)

1. Navigate to **Resource groups** → **dev-skycraft-swc-rg**
2. Click **Access control (IAM)**
3. Click **+ Add** → **Add role assignment**

4. **Role tab**:

   - Search for **"Contributor"**
   - Select **Contributor**
   - Click **Next**

5. **Members tab**:

   - Click **+ Select members**
   - Search for **"SkyCraft-Developers"**
   - Select the **group** (not individual users)
   - Click **Select**
   - Click **Next**

6. **Review + assign tab**:
   - Click **Review + assign**

**Expected Result**: SkyCraft-Developers group can now create and manage resources in `dev-skycraft-swc-rg`.

### Step 4.2: Assign Reader Role to Testers Group (Dev Environment)

1. Still in **dev-skycraft-swc-rg**, click **Access control (IAM)**
2. Click **+ Add** → **Add role assignment**

3. **Role tab**:

   - Search for **"Reader"**
   - Select **Reader**
   - Click **Next**

4. **Members tab**:

   - Click **+ Select members**
   - Search for **"SkyCraft-Testers"**
   - Select the group
   - Click **Select**
   - Click **Next**

5. Click **Review + assign**

**Expected Result**: SkyCraft-Testers can view resources but not modify them.

### Step 4.3: Assign Reader Role to Testers (Production Environment)

Repeat the same process for production:

1. Navigate to **Resource groups** → **prod-skycraft-swc-rg**
2. Click **Access control (IAM)**
3. Click **+ Add** → **Add role assignment**
4. Select **Reader** role
5. Add **SkyCraft-Testers** group
6. Click **Review + assign**

**Expected Result**: Testers can view production resources but cannot make changes.

### Step 4.4: Assign Limited Access to External Partner

For the external partner, grant access only to the shared services resource group:

1. Navigate to **Resource groups** → **platform-skycraft-swc-rg**
2. Click **Access control (IAM)**
3. Click **+ Add** → **Add role assignment**
4. Select **Reader** role
5. Add **External Partner Consultant** user (the guest user from Lab 1.1)
6. Click **Review + assign**

**Expected Result**: External partner has read-only access to shared services only, not dev or prod.

---

## 📖 Section 5: Verify and Test Access (20 minutes)

### Step 5.1: Check Access for Developer

1. Navigate to **dev-skycraft-swc-rg**
2. Click **Access control (IAM)**
3. Click **Check access** tab
4. Search for **"SkyCraft Developer"** (individual user)
5. Click the user name

**Expected Result**: Shows the user has:

- **Contributor** (inherited from SkyCraft-Developers group)
- Scope: dev-skycraft-swc-rg

**Analysis**: The user doesn't have the role directly—they inherit it through group membership. This confirms best practice (assign to groups, not users).

### Step 5.2: Check Access for Tester

1. Still in **Access control (IAM)**, click **Check access**
2. Search for **"SkyCraft Tester"**
3. Click the user name

**Expected Result**: Shows:

- **Reader** role (inherited from SkyCraft-Testers group)
- Scope: dev-skycraft-swc-rg and prod-skycraft-swc-rg

### Step 5.3: View All Role Assignments

1. Click **Role assignments** tab
2. Review all assignments for this resource group

**Expected assignments**:
| Name | Type | Role | Scope |
|------|------|------|-------|
| SkyCraft-Developers | Group | Contributor | This resource |
| SkyCraft-Testers | Group | Reader | This resource |

### Step 5.4: Test Effective Permissions (Optional but Recommended)

To truly verify permissions, you would:

1. Sign in as **SkyCraft Developer** (in a private browser window)
2. Try to create a resource in `dev-skycraft-swc-rg` → Should succeed
3. Try to delete `dev-skycraft-swc-rg` → Should fail (Contributor can't delete RGs)
4. Try to create resource in `prod-skycraft-swc-rg` → Should fail (no access)

**Note**: For lab purposes, checking access in IAM is sufficient verification.

---

## 📖 Section 6: Understanding Role Assignment Properties (10 minutes)

### View Assignment Details

1. In any resource group, go to **Access control (IAM)** → **Role assignments**
2. Click on any assignment to view details

**Key Properties**:

- **Principal ID**: Unique identifier for user/group
- **Role Definition ID**: Unique identifier for the role
- **Scope**: Exact resource path where role applies
- **Condition**: Advanced - conditional access (not used in this lab)

### Understand Inheritance

```
Subscription (SkyCraft Admin = Owner)
└── dev-skycraft-swc-rg (Developers = Contributor, Testers = Reader)
    └── [Future VM] (inherits all above permissions)
```

**Key Concept**: When you create a VM in `dev-skycraft-swc-rg`:

- SkyCraft Admin can manage it (Owner at subscription)
- Developers can manage it (Contributor at RG)
- Testers can view it (Reader at RG)

---

## ✅ Lab Checklist

Complete this checklist to verify successful lab completion:

### Resource Groups Created

- [ ] `dev-skycraft-swc-rg` exists
- [ ] `prod-skycraft-swc-rg` exists
- [ ] `platform-skycraft-swc-rg` exists

### Subscription-Level Role Assignments

- [ ] SkyCraft Admin has **Owner** role at subscription scope

### Resource Group-Level Assignments (dev-skycraft-swc-rg)

- [ ] SkyCraft-Developers group has **Contributor** role
- [ ] SkyCraft-Testers group has **Reader** role

### Resource Group-Level Assignments (prod-skycraft-swc-rg)

- [ ] SkyCraft-Testers group has **Reader** role

### Resource Group-Level Assignments (rg-skycraft-shared)

- [ ] External Partner has **Reader** role

### Verification Completed

- [ ] Checked access for SkyCraft Developer (shows Contributor via group)
- [ ] Checked access for SkyCraft Tester (shows Reader via group)
- [ ] Reviewed role assignments in all three resource groups
- [ ] Understand the difference between subscription and resource group scope

---

## 🔧 Troubleshooting

### Issue 1: "You do not have permission to add role assignment"

**Symptom**: Error when trying to assign roles

**Causes**:

- You don't have Owner or User Access Administrator role
- You're trying to assign a role you don't have yourself

**Solutions**:

1. Verify your own role: **Subscriptions** → **Access control (IAM)** → **Check access**
2. You need Owner or User Access Administrator to assign roles
3. Contact your subscription administrator

### Issue 2: Cannot find user/group when adding members

**Symptom**: User or group doesn't appear in search

**Solutions**:

1. Wait 5 minutes after creating users/groups (synchronization delay)
2. Search by exact name: "SkyCraft-Developers"
3. Refresh the browser (F5)
4. Verify the user/group exists: **Entra ID** → **Users** or **Groups**

### Issue 3: Role assignment doesn't show in "Check access"

**Symptom**: Just assigned a role but it doesn't appear

**Solutions**:

1. Wait 2-3 minutes (propagation delay)
2. Refresh the page
3. Check the correct scope (subscription vs. resource group)
4. Verify assignment in **Role assignments** tab

### Issue 4: User can't perform actions despite having Contributor role

**Symptom**: Developer reports "Access Denied" errors

**Solutions**:

1. Verify role assignment scope matches where they're working
2. Confirm they're members of the correct group
3. Ask them to sign out and sign back in (token refresh)
4. Wait up to 5 minutes for permissions to propagate

---

## 🎓 Knowledge Check

Test your understanding:

1. **Q**: What's the difference between Owner and Contributor roles?  
   **A**: Owner can do everything Contributor can do, PLUS assign roles to others. Contributor cannot grant access to anyone else.

2. **Q**: Why assign roles to groups instead of individual users?  
   **A**: Groups are easier to manage—add/remove users from groups without changing role assignments. Also helps minimize role assignment count (4000 limit per subscription).

3. **Q**: If SkyCraft Developer has Contributor at resource group level, can they create a new resource group?  
   **A**: No. Creating resource groups requires permissions at subscription level.

4. **Q**: A user has Reader at subscription level and Contributor at resource group level. What can they do in that resource group?  
   **A**: Contributor permissions apply (most permissive wins). They can create and manage resources in that RG.

5. **Q**: What happens to role assignments when you delete a resource group?  
   **A**: Role assignments scoped to that resource group are automatically deleted.

---

## 📚 Additional Resources

- [Azure built-in roles documentation](https://learn.microsoft.com/en-us/azure/role-based-access-control/built-in-roles)
- [Steps to assign an Azure role](https://learn.microsoft.com/en-us/azure/role-based-access-control/role-assignments-steps)
- [Best practices for Azure RBAC](https://learn.microsoft.com/en-us/azure/role-based-access-control/best-practices)
- [Understand scope for Azure RBAC](https://learn.microsoft.com/en-us/azure/role-based-access-control/scope-overview)

---

## 🔗 What's Next

You've successfully implemented RBAC for the SkyCraft team! Key accomplishments:

- ✅ Created organized resource group structure
- ✅ Assigned appropriate roles at correct scopes
- ✅ Implemented least-privilege access
- ✅ Used groups for better management

**Next Lab**: Lab 1.3 - Azure Governance and Policies

- You'll add policies to enforce naming conventions
- Configure resource locks to prevent accidental deletion
- Set up cost management and budgets

---

## 📝 Lab Summary

**What You Accomplished**:

- ✅ Created 3 resource groups (dev, prod, shared)
- ✅ Assigned Owner role at subscription level
- ✅ Assigned Contributor and Reader roles at resource group level
- ✅ Followed best practices (groups, least privilege, appropriate scope)
- ✅ Verified access assignments

**Time Spent**: ~2 hours

**Roles Assigned**:

- 1 subscription-level assignment (Owner)
- 5 resource group-level assignments (Contributor × 1, Reader × 4)

---

---

## 📌 Module Navigation

- [← Lab 1.1: Manage Entra Users & Groups](../1.1-entra-users-groups/lab-guide-1.1.md)
- [← Back to Module 1 Index](../README.MD)
- [Lab 1.3: Governance & Policies →](../1.3-governance/lab-guide-1.3.md)
