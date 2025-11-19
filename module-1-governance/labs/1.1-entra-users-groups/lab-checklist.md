# Lab 1.1 Completion Checklist

## ✅ User Creation Verification

### Internal Users
- [ ] **SkyCraft Admin** user created
  - UPN: skycraft-admin@[yourtenant].onmicrosoft.com
  - Display Name: SkyCraft Admin
  - Status: Active
  
- [ ] **SkyCraft Developer** user created
  - UPN: skycraft-dev@[yourtenant].onmicrosoft.com
  - Display Name: SkyCraft Developer
  - Status: Active
  
- [ ] **SkyCraft Tester** user created
  - UPN: skycraft-tester@[yourtenant].onmicrosoft.com
  - Display Name: SkyCraft Tester
  - Status: Active

### External User
- [ ] **External Partner** invited
  - Email: partner@externalcompany.com
  - Type: Guest
  - Status: Invitation Pending (or Accepted)

---

## ✅ Security Group Verification

- [ ] **SkyCraft-Admins** group created
  - Members: 1 (SkyCraft Admin)
  - Type: Security
  
- [ ] **SkyCraft-Developers** group created
  - Members: 1 (SkyCraft Developer)
  - Type: Security
  
- [ ] **SkyCraft-Testers** group created
  - Members: 1 (SkyCraft Tester)
  - Type: Security

---

## ✅ User Properties Verification

For **SkyCraft Admin**, verify:
- [ ] Job title: Cloud Infrastructure Manager
- [ ] Department: IT Operations
- [ ] Office: Remote
- [ ] Usage location: Set correctly

---

## ✅ License & Feature Verification

- [ ] At least one user has a license assigned
- [ ] SSPR (Self-Service Password Reset) enabled
- [ ] All users appear in "All Users" list
- [ ] All groups appear in "All Groups" list

---

## ✅ Portal Navigation

- [ ] Can access Entra ID from Azure Portal
- [ ] Can navigate Users → All Users
- [ ] Can navigate Groups → All Groups
- [ ] Can access user properties
- [ ] Can manage group memberships

---

## 🔍 Validation Steps

Execute these validation steps to confirm success:

### Step 1: List all users in Azure CLI

```azcli
az ad user list --query "[].{UPN:userPrincipalName,DisplayName:displayName}" -o table
```

**Expected Output**: Shows 4 users (3 internal + 1 guest)

### Step 2: List all groups

```azcli
az ad group list --query "[].{Name:displayName,ID:id}" -o table
```

**Expected Output**: Shows 3 groups

### Step 3: Get group members
```azcli
az ad group member list --group SkyCraft-Admins --query "[].{DisplayName:displayName}" -o
```

**Expected Output**: Shows SkyCraft Admin

---

## ⏱️ Completion Time

- **Estimated Time to Complete**: 3 hours
- **Actual Time Spent**: _________
- **Date Started**: _________
- **Date Completed**: _________

---

## 📝 Notes & Observations

Use this space to note any issues encountered or important learnings:

---

## ✅ Final Approval

- [ ] All checklist items completed
- [ ] All validation steps passed
- [ ] Ready to proceed to Lab 1.2

**Date Completed**: _________________
