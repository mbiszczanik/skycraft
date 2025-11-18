# Lab 1.3 Completion Checklist

## ✅ Section 1: Tags Applied

### Resource Group: dev-skycraft-swc-rg
- [ ] Tag: `Environment` = `Development`
- [ ] Tag: `Project` = `SkyCraft`
- [ ] Tag: `CostCenter` = `Engineering`
- [ ] Tag: `Owner` = `skycraft-admin@yourtenant.onmicrosoft.com`
- [ ] Tag: `Purpose` = `SkyCraft-Development`

### Resource Group: prod-skycraft-swc-rg
- [ ] Tag: `Environment` = `Production`
- [ ] Tag: `Project` = `SkyCraft`
- [ ] Tag: `CostCenter` = `Operations`
- [ ] Tag: `Owner` = `skycraft-admin@yourtenant.onmicrosoft.com`
- [ ] Tag: `Purpose` = `SkyCraft-Production`
- [ ] Tag: `Criticality` = `High`

### Resource Group: platform-skycraft-swc-rg
- [ ] Tag: `Environment` = `Shared`
- [ ] Tag: `Project` = `SkyCraft`
- [ ] Tag: `CostCenter` = `Shared-Services`
- [ ] Tag: `Owner` = `skycraft-admin@yourtenant.onmicrosoft.com`
- [ ] Tag: `Purpose` = `Monitoring-Logging`

### Tag Verification
- [ ] Can view resources by "Project" tag in Tags service
- [ ] All three resource groups appear when filtering by Project=SkyCraft
- [ ] Tags are visible in resource group properties

---

## ✅ Section 2: Azure Policy Assignments

### Policy 1: Require Environment Tag
- [ ] Policy assigned: "Require a tag on resource groups"
- [ ] Assignment name: `Require-Environment-Tag-RG`
- [ ] Scope: Subscription level
- [ ] Parameter: Tag name = `Environment`
- [ ] Policy enforcement: **Enabled**
- [ ] Non-compliance message configured
- [ ] Tested policy (attempted to create RG without tag)

### Policy 2: Enforce Project Tag Value
- [ ] Policy assigned: "Require a tag and its value on resources"
- [ ] Assignment name: `Enforce-Project-Tag`
- [ ] Parameter: Tag name = `Project`, Tag value = `SkyCraft`
- [ ] Policy enforcement: **Enabled**
- [ ] Non-compliance message configured

### Policy 3: Allowed Locations
- [ ] Policy assigned: "Allowed locations"
- [ ] Assignment name: `Restrict-Azure-Regions`
- [ ] Allowed locations: Sweden Central, North Europe
- [ ] Policy enforcement: **Enabled**
- [ ] Non-compliance message configured

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
- [ ] Notes: `Prevents accidental deletion of production resources`
- [ ] Tested lock (attempted to delete resource group)
- [ ] Verified error message received

### Lock 2: Shared Resource Group
- [ ] Lock applied to: `platform-skycraft-swc-rg`
- [ ] Lock name: `lock-no-delete-shared`
- [ ] Lock type: **Delete** (CanNotDelete)
- [ ] Notes: `Protects shared monitoring and logging infrastructure`

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
- [ ] Amount: $200 (or your chosen amount)
- [ ] Reset period: Monthly
- [ ] Expiration date set (1 year from now)
- [ ] Alert at 50% of budget configured
- [ ] Alert at 80% of budget configured
- [ ] Alert at 100% of budget configured
- [ ] Email recipients configured for all alerts
- [ ] Confirmation email received

### Budget 2: Resource Group Budget
- [ ] Budget created: `SkyCraft-Prod-Monthly`
- [ ] Scope: prod-skycraft-swc-rg
- [ ] Amount: $100 (or your chosen amount)
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
- [ ] Reviewed Overall Score
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
- [ ] Created Advisor alert rule
- [ ] Alert name: `Advisor-Cost-Recommendations`
- [ ] Alert category: Cost
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

Run these commands to validate your governance configuration:

### Login to Azure

```azcli
az login
```

### Set subscription context

```azcli
az account set --subscription "YOUR-SUBSCRIPTION-ID"
```

========================================
### Validate Tags
========================================

### List tags on dev-skycraft-swc-rg

```azcli
az tag list --resource-id /subscriptions/YOUR-SUB-ID/resourceGroups/dev-skycraft-swc-rg
```

### List all resources with Project=SkyCraft tag

```azcli
az resource list --tag Project=SkyCraft --query "[].{Name:name,Type:type,RG:resourceGroup}" -o table
```

========================================
### Validate Policy Assignments
========================================

### List all policy assignments

```azcli
az policy assignment list --query "[].{Name:name,DisplayName:displayName,Scope:scope}" -o table
```

### Check policy compliance

```azcli
az policy state summarize --query "results[].{PolicyName:policyAssignments.policyDefinitionName,Compliant:resourceDetails.complianceState}"
```

========================================
### Validate Resource Locks
========================================

### List locks on prod-skycraft-swc-rg

```azcli
az lock list --resource-group prod-skycraft-swc-rg --query "[].{Name:name,Level:level,Notes:notes}" -o table
```

### List locks on platform-skycraft-swc-rg

```azcli
az lock list --resource-group platform-skycraft-swc-rg --query "[].{Name:name,Level:level,Notes:notes}" -o table
```

========================================
### Validate Budgets
========================================

### List all budgets (requires Cost Management extension)

```azcli
az consumption budget list --query "[].{Name:name,Amount:amount,Category:category}" -o table
```

**Expected Results**:
- Tags appear on all three resource groups
- 3 policy assignments visible
- 2 resource locks confirmed
- 2 budgets listed

---

## 📊 Governance Summary

| Component | Implemented | Count | Purpose |
|-----------|-------------|-------|---------|
| Tags | ✅ | 15+ tags | Resource organization and cost tracking |
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