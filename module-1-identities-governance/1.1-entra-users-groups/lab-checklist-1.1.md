# Lab 1.1 Completion Checklist

## ✅ User Creation Verification

### Internal Users

- [ ] **Malfurion Stormrage** user created
  - UPN: malfurion.stormrage@[yourtenant].onmicrosoft.com
  - Display Name: Malfurion Stormrage
  - Status: Active
- [ ] **Khadgar Archmage** user created
  - UPN: khadgar.archmage@[yourtenant].onmicrosoft.com
  - Display Name: Khadgar Archmage
  - Status: Active
- [ ] **Chromie Timewalker** user created
  - UPN: chromie.timewalker@[yourtenant].onmicrosoft.com
  - Display Name: Chromie Timewalker
  - Status: Active

### External User

- [ ] **Illidan Stormrage** invited
  - Email: illidan@externalcompany.com
  - Type: Guest
  - Status: Invitation Pending (or Accepted)

---

## ✅ Security Group Verification

- [ ] **SkyCraft-Admins** group created
  - Members: 1 (Malfurion Stormrage)
  - Type: Security
- [ ] **SkyCraft-Developers** group created
  - Members: 1 (Khadgar Archmage)
  - Type: Security
- [ ] **SkyCraft-Testers** group created
  - Members: 1 (Chromie Timewalker)
  - Type: Security

---

## ✅ User Properties Verification

For **Malfurion Stormrage**, verify:

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

**Expected Output**: Shows Malfurion Stormrage

---

## 📊 Entity Summary

| Entity Name         | Type  | Key Attribute       | Purpose               |
| ------------------- | ----- | ------------------- | --------------------- |
| Malfurion Stormrage | User  | Cloud Infra Manager | Main Admin            |
| Khadgar Archmage    | User  | Developer           | Application Dev       |
| Chromie Timewalker  | User  | Tester              | QA & Testing          |
| Illidan Stormrage   | Guest | External Invitee    | External Consultant   |
| SkyCraft-Admins     | Group | Assigned: Malfurion | Administrative access |
| SkyCraft-Developers | Group | Assigned: Khadgar   | Dev resource access   |
| SkyCraft-Testers    | Group | Assigned: Chromie   | Test resource access  |

---

## ⏱️ Completion Time

- **Estimated Time**: 3 hours
- **Actual Time Spent**: ****\_****
- **Date Started**: ****\_****
- **Date Completed**: ****\_****

---

## 📝 Reflection Questions

Answer these to deepen understanding:

1.  **Why do we create a separate "SkyCraft-Admins" group instead of just using the Global Admin role?**

    Answer: ************************\_\_\_************************

2.  **What is the difference between an internal Member user and an invited Guest user in Entra ID?**

    Answer: ************************\_\_\_************************

3.  **Why is the "Usage location" property important for user creation?**

    Answer: ************************\_\_\_************************

---

## ✅ Final Sign-off

- [ ] All checklist items completed
- [ ] All validation steps passed
- [ ] Users and Groups verified in portal or CLI
- [ ] Ready to proceed to Lab 1.2

**Student Name**: ********\_********  
**Completion Date**: ********\_********  
**Instructor Signature**: ********\_********
