# Lab 1.3 Completion Checklist

## ✅ Section 1: Tags Applied

### Resource Group: dev-skycraft-swc-rg
- [ ] Tag: `Environment` = `Development`
- [ ] Tag: `Project` = `SkyCraft`
- [ ] Tag: `CostCenter` = `MSDN`
- [ ] Tag: `Owner` = `mbiszczanik`

### Resource Group: prod-skycraft-swc-rg
- [ ] Tag: `Environment` = `Production`
- [ ] Tag: `Project` = `SkyCraft`
- [ ] Tag: `CostCenter` = `MSDN`
- [ ] Tag: `Owner` = `mbiszczanik`

### Resource Group: platform-skycraft-swc-rg
- [ ] Tag: `Environment` = `Platform`
- [ ] Tag: `Project` = `SkyCraft`
- [ ] Tag: `CostCenter` = `MSDN`
- [ ] Tag: `Owner` = `mbiszczanik`

### Tag Verification
- [ ] Can view resources by "Project" tag in Tags service
- [ ] All three resource groups appear when filtering by Project=SkyCraft
- [ ] Tags are visible in resource group properties

---

## ✅ Section 2: Azure Policy Assignments

### Policy 1: Require Environment Tag
- [ ] Policy assigned: "Require a tag on resource groups"
- [ ] Assignment name: `Require-Environment-Tag-RG` (in the Portal, the assignment's display name; see the note below)
- [ ] Scope: Subscription level
- [ ] Parameter: Tag name = `Environment`
- [ ] Policy enforcement: **Default (enforcement)**
- [ ] Non-compliance message configured
- [ ] Tested policy (creating an RG without the tag was denied after **Create**, with `RequestDisallowedByPolicy`)

### Policy 2: Enforce Project Tag Value
- [ ] Policy assigned: "Require a tag and its value on resources"
- [ ] Assignment name: `Enforce-Project-Tag`
- [ ] Parameter: Tag name = `Project`, Tag value = `SkyCraft`
- [ ] Policy enforcement: **Default (enforcement)**
- [ ] Non-compliance message configured

### Policy 3: Allowed Locations
- [ ] Policy assigned: "Allowed locations"
- [ ] Assignment name: `Restrict-Azure-Regions`
- [ ] Allowed locations: Sweden Central, North Europe
- [ ] Policy enforcement: **Default (enforcement)**
- [ ] Non-compliance message configured

> **Assignment names**: the Portal's **Assignment name** field sets the assignment's display name;
> Azure names the assignment resource itself with a generated id. The Bicep path sets the name
> (`Require-Environment-Tag-RG`, ...) and its own display names (`Require Environment Tag on Resource
> Groups`, `Enforce Project Tag Value`, `Restrict to Allowed Regions`). `Test-Lab.ps1` and
> `Remove-LabResource.ps1` accept an assignment made at the subscription itself, of the built-in
> definition named above, whose name or display name is the dashed name, or whose display name is
> the Bicep one. An assignment left with the definition's own name (the wizard fills it in) is not
> found, and two matching assignments for one policy (for example from the Portal and the Bicep path)
> fail the check.

### Policy Compliance
- [ ] Accessed Policy Compliance dashboard
- [ ] Reviewed overall compliance percentage
- [ ] Viewed compliance details for each policy
- [ ] Understand compliant vs. non-compliant states

---

## ✅ Section 3: Resource Locks

### Lock 1: Production Resource Group
- [ ] Lock applied to: `prod-skycraft-swc-rg`
- [ ] Lock name: `lock-no-delete-prod`
- [ ] Lock type: **Delete** (CanNotDelete)
- [ ] Notes: `Cannot delete resource or child resources.`
- [ ] Tested lock (attempted to delete resource group)
- [ ] Verified the Portal refused: notification **Failed to delete resource group prod-skycraft-swc-rg** ("has locks applied")

### Lock 2: Platform Resource Group
- [ ] Lock applied to: `platform-skycraft-swc-rg`
- [ ] Lock name: `lock-no-delete-platform`
- [ ] Lock type: **Delete** (CanNotDelete)
- [ ] Notes: `Cannot delete resource or child resources.`

### Lock Understanding
- [ ] Understand lock inheritance (parent to child)
- [ ] Know difference between CanNotDelete and ReadOnly
- [ ] Understand how to remove locks when needed
- [ ] Know that locks apply even to Owners

---

## ✅ Section 4: Cost Management

### Budget 1: Subscription Budget
- [ ] Budget created: `SkyCraft-Monthly-Budget`
- [ ] Scope: Subscription level
- [ ] Amount: 100 in your billing currency (or your chosen amount)
- [ ] Reset period: Monthly
- [ ] Expiration date set (the Portal's default, two years from now)
- [ ] Alert at 50% of budget configured
- [ ] Alert at 80% of budget configured
- [ ] Alert at 100% of budget configured
- [ ] Email recipients configured (one list, shared by all alerts)
- [ ] Confirmation email received

### Budget 2: Resource Group Budget
- [ ] Budget created: `SkyCraft-Prod-Monthly`
- [ ] Scope: prod-skycraft-swc-rg (created from the resource group's own **Budgets**, not with a filter)
- [ ] Amount: 50 in your billing currency (or your chosen amount)
- [ ] Alerts configured (60%, 85%, 100%)
- [ ] Email recipients configured

### Cost Analysis
- [ ] Accessed Cost Analysis dashboard
- [ ] Explored "Cost by resource" view
- [ ] Explored "Cost by service" view
- [ ] Applied filter: Tag = Project:SkyCraft
- [ ] Applied filter: Resource group = prod-skycraft-swc-rg
- [ ] Reviewed daily cost trends
- [ ] Understand cost breakdown visualizations

---

## ✅ Section 5: Azure Advisor

### Advisor Dashboard
- [ ] Accessed Azure Advisor
- [ ] Reviewed the **Advisor score** page
- [ ] Viewed recommendations by category:
  - [ ] Cost
  - [ ] Security
  - [ ] Reliability
  - [ ] Operational Excellence
  - [ ] Performance
- [ ] Clicked into at least one recommendation for details

### Advisor Configuration
- [ ] Reviewed Advisor Configuration settings
- [ ] Explored filtering options (include/exclude resources)
- [ ] Created Advisor alert rule (Step 1.3.7, before the tag policy of Step 1.3.8)
- [ ] Alert name: `Advisor-Cost-Recommendations`
- [ ] Alert category: Cost
- [ ] Action group: `skycraft-advisor-ag` in prod-skycraft-swc-rg, Region Sweden Central, tagged `Project` = `SkyCraft`
- [ ] Understand how to act on recommendations

---

## ✅ Section 6: Management Groups

- [ ] Accessed Management Groups service
- [ ] Viewed Tenant Root Group
- [ ] Understand management group hierarchy
- [ ] Know when to use management groups (multi-subscription scenarios)
- [ ] Understand policy and RBAC inheritance in management groups

---

## 🔍 Validation Commands

Run these Az PowerShell commands to validate your governance configuration:

### Login to Azure

```powershell
Connect-AzAccount
```

### Set subscription context

```powershell
Set-AzContext -Subscription "YOUR-SUBSCRIPTION-ID"
```

========================================
### Validate Tags
========================================

### List tags on dev-skycraft-swc-rg

```powershell
(Get-AzResourceGroup -Name dev-skycraft-swc-rg).Tags
```

### List all resources with Project=SkyCraft tag

```powershell
Get-AzResource -TagName Project -TagValue SkyCraft |
    Select-Object Name, ResourceType, ResourceGroupName |
    Format-Table -AutoSize
```

========================================
### Validate Policy Assignments
========================================

### List all policy assignments

```powershell
Get-AzPolicyAssignment |
    Select-Object Name, DisplayName, PolicyDefinitionId, Scope |
    Format-Table -AutoSize
```

### Check policy compliance

```powershell
Get-AzPolicyStateSummary |
    Select-Object -ExpandProperty PolicyAssignments |
    Select-Object PolicyAssignmentId, @{N='NonCompliant';E={$_.Results.NonCompliantResources}} |
    Format-Table -AutoSize
```

========================================
### Validate Resource Locks
========================================

### List locks on prod-skycraft-swc-rg

```powershell
Get-AzResourceLock -ResourceGroupName prod-skycraft-swc-rg |
    Select-Object Name, @{N='Level';E={$_.Properties.level}}, @{N='Notes';E={$_.Properties.notes}} |
    Format-Table -AutoSize
```

### List locks on platform-skycraft-swc-rg

```powershell
Get-AzResourceLock -ResourceGroupName platform-skycraft-swc-rg |
    Select-Object Name, @{N='Level';E={$_.Properties.level}}, @{N='Notes';E={$_.Properties.notes}} |
    Format-Table -AutoSize
```

========================================
### Validate Budgets
========================================

### List the budgets (the cmdlet ships in the Az.Billing module)

The listing is per scope: without `-ResourceGroupName` it shows the subscription's budgets, with it
the budgets on that resource group.

```powershell
# Subscription budget (step 1.3.15)
Get-AzConsumptionBudget |
    Select-Object Name, Amount, Category |
    Format-Table -AutoSize

# Resource group budget (step 1.3.17)
Get-AzConsumptionBudget -ResourceGroupName prod-skycraft-swc-rg |
    Select-Object Name, Amount, Category |
    Format-Table -AutoSize
```

**Expected Results**:
- Tags appear on all three resource groups
- 3 policy assignments visible, each with the dashed name in **Name** (Bicep path) or **DisplayName** (Portal path)
- 2 resource locks confirmed
- SkyCraft-Monthly-Budget listed by the first budget command
- SkyCraft-Prod-Monthly listed by the second budget command

---

## 📊 Governance Summary

| Component | Implemented | Count | Purpose |
|-----------|-------------|-------|---------|
| Tags | ✅ | 12 tags (4 per RG) | Resource organization and cost tracking |
| Azure Policies | ✅ | 3 assignments | Enforce standards and compliance |
| Resource Locks | ✅ | 2 locks | Prevent accidental deletion |
| Budgets | ✅ | 2 budgets | Cost control and alerts |
| Advisor Alerts | ✅ | 1 alert rule | Proactive optimization |

---

## 📝 Reflection Questions

Answer these to verify deep understanding:

1. **Why tag resource groups when tags aren't inherited?**
   
   Answer: ___________________________________________________

2. **What's the difference between Azure Policy "Audit" and "Deny" effects?**
   
   Answer: ___________________________________________________

3. **Can you delete a locked resource if you're the Owner?**
   
   Answer: ___________________________________________________

4. **What happens when a budget threshold is exceeded?**
   
   Answer: ___________________________________________________

5. **When would you use a management group instead of a subscription?**
   
   Answer: ___________________________________________________

---

## ⏱️ Completion Time

- **Estimated Time**: 4 hours
- **Actual Time Spent**: _________
- **Date Started**: _________
- **Date Completed**: _________

---

## ✅ Module 1 Final Sign-off

**All Lab 1.3 Tasks Complete**:
- [ ] All tags applied and verified
- [ ] All policies assigned and tested
- [ ] Resource locks configured and tested
- [ ] Budgets created with alerts
- [ ] Azure Advisor explored and configured
- [ ] Management groups concept understood

**Ready for Module 2**: Implement and Manage Virtual Networking

**Student Name**: _________________
**Module 1 Completion Date**: _________________
**Instructor Signature**: _________________

---

## 🎉 Congratulations!

You've completed **Module 1: Manage Azure Identities and Governance**!

You now have a **production-ready governance framework** with:
- ✅ Identity management (users, groups)
- ✅ Access control (RBAC)
- ✅ Resource organization (tags)
- ✅ Compliance enforcement (policies)
- ✅ Change protection (locks)
- ✅ Cost management (budgets, alerts)

This foundation will support all infrastructure you deploy in Modules 2-5.

**Next**: [Module 2 - Virtual Networking](../../module-2-networking/README.md)