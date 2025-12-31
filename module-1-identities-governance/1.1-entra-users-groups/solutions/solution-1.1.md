# Lab 1.1 - Solution Guide

## Common Issues & Solutions

### Issue 1: "Insufficient privileges to complete the operation"

**Symptom**: Error when trying to create users or groups

**Causes**:
- You don't have User Administrator or Global Administrator role
- Your license doesn't include user management capabilities

**Solutions**:
1. Verify your role in Azure Portal:
   - Go to **Entra ID → My role assignments**
   - Look for "Global Administrator" or "User Administrator"

2. If missing, contact your tenant admin to grant these permissions

3. Alternative: Use Global Administrator account

### Issue 2: Cannot find "Microsoft Entra ID" in search

**Symptom**: Search doesn't return Entra ID in Azure Portal

**Solutions**:
1. Try searching for "Azure Active Directory" instead
2. Use direct URL: https://entra.microsoft.com
3. Ensure you're in the correct tenant (check top-right corner)

### Issue 3: User creation says "This user may already exist"

**Symptom**: Cannot create user with selected UPN

**Solutions**:
1. The UPN already exists (deleted or archived)
2. Try a slightly different UPN: `skycraft-admin-01@yourtenant.onmicrosoft.com`
3. Contact admin to restore deleted user if needed

### Issue 4: "License unavailable" when assigning license

**Symptom**: Cannot assign license to user

**Solutions**:
1. Check available licenses:
   - Entra ID → Licenses → All products
   - Verify you have unused licenses

2. Purchase additional licenses if needed

3. Use Azure AD Free features (no license assignment needed)

### Issue 5: Group doesn't appear after creation

**Symptom**: Created group but can't find it in list

**Solutions**:
1. Refresh the browser (F5)
2. Navigate away and back to Groups list
3. Wait a few seconds (sometimes has a delay)
4. Try searching by group name directly

### Issue 6: Can't find newly created user to add to group

**Symptom**: User appears in "All Users" but not in search when adding to group

**Solutions**:
1. Wait 30 seconds and try again (synchronization delay)
2. Search by full UPN: `skycraft-dev@yourtenant.onmicrosoft.com`
3. Refresh portal and retry
4. Try searching by first/last name instead

---

## Validation Commands

If issues occur, use these Azure CLI commands to diagnose:

List all users:  

`az ad user list --query "[].{DisplayName:displayName,UPN:userPrincipalName,ObjectId:id}" -o table`

Check specific user:  

`az ad user show --id skycraft-admin@yourtenant.onmicrosoft.com`

List all groups:  

`az ad group list --query "[].{DisplayName:displayName,ID:id}" -o table`

Get group members:  

`az ad group member list --group SkyCraft-Admins --query "[].{DisplayName:displayName}" -o table`

Check user's assigned licenses:  

`az ad user show --id skycraft-admin@yourtenant.onmicrosoft.com --query "{LicenseId:licenseAssignmentStates}"`

---

## FAQ

**Q**: Do I need to remember these passwords?  
**A**: No—this is for lab setup only. In production, use temporary passwords or SSO. Encourage users to change passwords at first login.

**Q**: What happens if I delete a group?  
**A**: The group is soft-deleted for 30 days and can be restored. After 30 days, it's permanently deleted.

**Q**: Can external users see internal company resources?  
**A**: Only what you explicitly share. B2B guests are isolated unless given specific permissions.

---

## Getting Additional Help

- **Azure Portal Support**: Click the **?** icon in top-right corner
- **Microsoft Learn**: https://learn.microsoft.com/en-us/entra/
- **Azure Forums**: https://learn.microsoft.com/en-us/answers/topics/azure.html