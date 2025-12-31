# Lab 1.3: Manage Azure Subscriptions and Governance (4 hours)

## 🎯 Lab Objectives

By completing this lab, you will:

- Implement Azure Policy to enforce organizational standards
- Configure resource locks to prevent accidental deletion
- Apply and manage tags for resource organization and cost tracking
- Configure Azure budgets and cost alerts
- Use Azure Advisor for optimization recommendations
- Understand management groups and subscription governance

---

## 📋 Real-World Scenario

**Situation**: The SkyCraft infrastructure now has proper identity management (Lab 1.1) and RBAC roles (Lab 1.2). However, there's still risk:

- Developers might accidentally delete production resources
- Resources are created without proper naming conventions
- No visibility into spending patterns
- Resources lack proper tagging for cost allocation

**Your Task**: Implement governance controls to:

1. Enforce naming conventions with Azure Policy
2. Prevent accidental deletion with resource locks
3. Tag all resources for cost tracking
4. Set up budgets and alerts to control spending
5. Use Azure Advisor recommendations

---

## ⏱️ Estimated Time: 4 hours

- **Section 1**: Apply and manage tags (30 min)
- **Section 2**: Implement Azure Policy (60 min)
- **Section 3**: Configure resource locks (30 min)
- **Section 4**: Manage costs with budgets and alerts (45 min)
- **Section 5**: Use Azure Advisor (30 min)
- **Section 6**: Understand management groups (15 min)
- **Hands-on Practice**: Governance framework implementation (30 min)

---

## ✅ Prerequisites

Before starting this lab:

- [ ] Completed Lab 1.1 (users and groups)
- [ ] Completed Lab 1.2 (RBAC and resource groups)
- [ ] Three resource groups exist: dev-skycraft-swc-rg, prod-skycraft-swc-rg, platform-skycraft-swc-rg
- [ ] Owner or Contributor role at subscription level
- [ ] Understanding of compliance and governance concepts

## 📖 Section 1: Apply and Manage Tags (30 minutes)

### What are Azure Tags?

**Tags** are name-value pairs that help you organize and categorize Azure resources. Tags enable:

- **Cost tracking** - Identify spending by project, environment, or department
- **Resource management** - Filter and group resources
- **Automation** - Target resources for automated operations
- **Compliance** - Track resource ownership and purpose

### Tag Limitations

- Maximum 50 tags per resource
- Tag name: 512 characters (storage accounts: 128 characters)
- Tag value: 256 characters
- Tags are not inherited from parent scopes (need Azure Policy for inheritance)

### Step 1.1: Apply Tags to Resource Groups

1. In **Azure Portal**, navigate to **Resource groups**
2. Click on **dev-skycraft-swc-rg**
3. In the left menu, click **Tags**
4. Add the following tags:

| Name        | Value                                     |
| ----------- | ----------------------------------------- |
| Environment | Development                               |
| Project     | SkyCraft                                  |
| CostCenter  | Engineering                               |
| Owner       | skycraft-admin@yourtenant.onmicrosoft.com |
| Purpose     | SkyCraft-Development                      |

5. Click **Apply**

**Expected Result**: Tags are saved and visible in the Tags blade.

### Step 1.2: Tag Production Resource Group

1. Navigate to **prod-skycraft-swc-rg**
2. Click **Tags**
3. Add these tags:

| Name        | Value                                     |
| ----------- | ----------------------------------------- |
| Environment | Production                                |
| Project     | SkyCraft                                  |
| CostCenter  | Operations                                |
| Owner       | skycraft-admin@yourtenant.onmicrosoft.com |
| Purpose     | SkyCraft-Production                       |
| Criticality | High                                      |

4. Click **Apply**

### Step 1.3: Tag Platform Services Resource Group

1. Navigate to **platform-skycraft-swc-rg**
2. Click **Tags**
3. Add tags:

| Name        | Value                                     |
| ----------- | ----------------------------------------- |
| Environment | Platform                                  |
| Project     | SkyCraft                                  |
| CostCenter  | Shared-Services                           |
| Owner       | skycraft-admin@yourtenant.onmicrosoft.com |
| Purpose     | Monitoring-Logging                        |

4. Click **Apply**

### Step 1.4: View Resources by Tag

1. In the Azure Portal search bar, type **Tags**
2. Click **Tags** service
3. You'll see all tags across your subscription
4. Click on **Project** tag
5. Click on **SkyCraft** value
6. **Expected Result**: Shows all three resource groups with the "SkyCraft" project tag

**Best Practice**: Standardize tag names and values across your organization to ensure consistency.

---

## 📖 Section 2: Implement Azure Policy (60 minutes)

### What is Azure Policy?

**Azure Policy** helps enforce organizational standards and assess compliance at scale. Policies can:

- **Audit** resources that don't meet requirements
- **Deny** creation of non-compliant resources
- **Modify** resources to meet requirements (e.g., add tags)
- **Deploy** resources automatically (DeployIfNotExists)

### Built-in vs. Custom Policies

- **Built-in policies** - Pre-defined by Microsoft (500+ available)
- **Custom policies** - Created by your organization for specific needs
- **Policy initiatives** - Groups of policies (also called policy sets)

### Step 2.1: Assign a Built-in Policy (Require Tag on Resource Groups)

1. In Azure Portal, search for **Policy**
2. Click **Policy** service
3. In the left menu, click **Assignments**
4. Click **+ Assign policy**

**Basics tab**:

- **Scope**: Click the "..." button
  - Select your subscription
  - Click **Select**
- **Policy definition**: Click the "..." button
  - Search for: **"Require a tag on resource groups"**
  - Select this policy
  - Click **Select**

5. Fill in additional details:

   - **Assignment name**: `Require-Environment-Tag-RG`
   - **Description**: `All resource groups must have an Environment tag`
   - **Policy enforcement**: Enabled

6. Click **Next**

**Parameters tab**:

- **Tag Name**: `Environment`

7. Click **Next**

**Remediation tab** (skip for now): 8. Click **Next**

**Non-compliance messages tab**:

- **Non-compliance message**: `Resource group must have an Environment tag (Development, Production, or Shared)`

9. Click **Review + create**
10. Click **Create**

**Expected Result**: Policy is assigned and will evaluate new resource groups.

### Step 2.2: Test the Policy

1. Try to create a new resource group **WITHOUT** the "Environment" tag:
   - Click **+ Create a resource group**
   - Name: `rg-test-no-tag`
   - Click **Review + create**

**Expected Result**: Creation is **allowed** (policy is not retroactive, only evaluates new operations).

2. Now try again:
   - Name: `rg-test-with-tag`
   - Go to **Tags** tab
   - Add tag: `Environment` = `Test`
   - Click **Review + create**

**Expected Result**: Creation succeeds because the required tag is present.

3. Delete the test resource group: `rg-test-with-tag`

### Step 2.3: Assign Policy for Resource Naming Convention

1. In **Policy** service, click **Assignments**
2. Click **+ Assign policy**

**Basics tab**:

- **Scope**: Your subscription
- **Policy definition**: Search for **"Require a tag and its value on resources"**
- **Assignment name**: `Enforce-Project-Tag`
- **Description**: `All resources must have Project tag set to SkyCraft`

**Parameters tab**:

- **Tag Name**: `Project`
- **Tag Value**: `SkyCraft`

**Non-compliance message**:

- Message: `All resources must be tagged with Project=SkyCraft`

3. Click **Review + create** → **Create**

### Step 2.4: Assign Policy to Enforce Allowed Locations

Prevent resource creation in unintended regions:

1. **Policy** → **Assignments** → **+ Assign policy**

**Basics tab**:

- **Scope**: Your subscription
- **Policy definition**: Search for **"Allowed locations"**
- **Assignment name**: `Restrict-Azure-Regions`
- **Description**: `Resources can only be created in Sweden Central and North Europe`

**Parameters tab**:

- **Allowed locations**: Select:
  - Sweden Central
  - North Europe

**Non-compliance message**:

- Message: `Resources must be deployed to Sweden Central or North Europe regions only`

2. Click **Review + create** → **Create**

### Step 2.5: View Policy Compliance

1. In **Policy** service, click **Compliance** in left menu
2. Review the compliance dashboard

**Expected View**:

- **Overall compliance percentage** (likely <100% initially)
- List of assigned policies
- Compliance state: Compliant, Non-compliant, Not started

3. Click on **Require-Environment-Tag-RG** policy
4. View which resource groups are compliant

**Note**: Existing resources created before policy assignment may show as non-compliant. This is expected.

---

## 📖 Section 3: Configure Resource Locks (30 minutes)

### What are Resource Locks?

**Resource locks** prevent accidental deletion or modification of critical resources. Two types:

- **CanNotDelete** - Users can read and modify but cannot delete
- **ReadOnly** - Users can read but cannot modify or delete (very restrictive)

### Lock Inheritance

Locks applied at parent scope (subscription/resource group) are inherited by child resources.

### Step 3.1: Apply CanNotDelete Lock to Production Resource Group

1. Navigate to **prod-skycraft-swc-rg**
2. In the left menu, click **Locks**
3. Click **+ Add**
4. Fill in:

| Field     | Value                                                |
| --------- | ---------------------------------------------------- |
| Lock name | lock-no-delete-prod                                  |
| Lock type | Delete                                               |
| Notes     | Prevents accidental deletion of production resources |

5. Click **OK**

**Expected Result**: Lock is created and shows in the Locks list.

### Step 3.2: Test the Lock

1. Still in **prod-skycraft-swc-rg**, click **Overview**
2. Click **Delete resource group** button
3. **Expected Result**: You'll see an error:

   > "Failed to delete resource group 'prod-skycraft-swc-rg'. Error: The scope 'prod-skycraft-swc-rg' cannot perform delete operation because following scope(s) are locked: '/subscriptions/.../resourceGroups/prod-skycraft-swc-rg'. Please remove the lock and try again."

4. Click **Cancel** (do not delete)

**Key Learning**: Even with Owner role, you cannot delete a locked resource until the lock is removed.

### Step 3.3: Apply CanNotDelete Lock to Shared Resource Group

1. Navigate to **platform-skycraft-swc-rg**
2. Click **Locks** → **+ Add**
3. Create lock:

   - Lock name: `lock-no-delete-shared`
   - Lock type: **Delete**
   - Notes: `Protects shared monitoring and logging infrastructure`

4. Click **OK**

### Step 3.4: Understand Lock Hierarchy

**Important Concepts**:

- Locks at **subscription** level protect all resource groups and resources
- Locks at **resource group** level protect all resources within
- Locks at **resource** level protect only that specific resource

**Best Practice**:

- Use **CanNotDelete** on production resource groups
- Use **ReadOnly** very carefully (can break automation)
- Document all locks with clear notes

---

## 📖 Section 4: Manage Costs with Budgets and Alerts (45 minutes)

### What are Azure Budgets?

**Budgets** help you plan for and control costs by:

- Setting spending thresholds
- Triggering alerts when thresholds are reached
- Tracking cost trends over time

### Step 4.1: Create a Subscription Budget

1. In Azure Portal, search for **Cost Management + Billing**
2. Click **Cost Management + Billing**
3. Under **Cost Management**, click **Budgets**
4. Click **+ Add**

**Scope**: Verify your subscription is selected

5. Fill in budget details:

| Field           | Value                             |
| --------------- | --------------------------------- |
| Name            | SkyCraft-Monthly-Budget           |
| Reset period    | Monthly                           |
| Creation date   | [First day of current month]      |
| Expiration date | [One year from now]               |
| Amount          | $200 (adjust based on your needs) |

6. Click **Next**

### Step 4.2: Configure Budget Alerts

**Alert conditions** tab:

1. Click **+ Add condition**

**Alert 1** (Warning at 50%):

- **Alert type**: Actual
- **% of budget**: 50
- **Action group**: (leave blank for now)
- **Alert recipients (email)**: Enter your email address
- **Language**: English

2. Click **+ Add condition** again

**Alert 2** (Critical at 80%):

- **Alert type**: Actual
- **% of budget**: 80
- **Alert recipients (email)**: Enter your email address

3. Click **+ Add condition**

**Alert 3** (Exceeded at 100%):

- **Alert type**: Actual
- **% of budget**: 100
- **Alert recipients (email)**: Enter your email and skycraft-admin email

4. Click **Next**

**Advanced options** (optional):

- Skip for now

5. Click **Create**

**Expected Result**: Budget is created and you'll receive email confirmation

### Step 4.3: Create Resource Group Budget

Create a more specific budget for the production environment:

1. In **Budgets**, click **+ Add**
2. Click **Scope** and select **prod-skycraft-swc-rg**
3. Fill in:

| Field        | Value                 |
| ------------ | --------------------- |
| Name         | SkyCraft-Prod-Monthly |
| Reset period | Monthly               |
| Amount       | $100                  |

4. Configure alerts at 60%, 85%, and 100%
5. Add email recipients
6. Click **Create**

### Step 4.4: View Cost Analysis

1. In **Cost Management + Billing**, click **Cost analysis**
2. Explore different views:

   - **Cost by resource** - See spending per resource
   - **Cost by service** - See spending per Azure service
   - **Cost by location** - Geographic distribution
   - **Daily costs** - Trend over time

3. Apply filters:
   - **Tag**: Project = SkyCraft
   - **Resource group**: prod-skycraft-swc-rg
   - **Time range**: Last 30 days

**Expected Result**: Visual charts showing cost breakdown (likely very low since we haven't deployed resources yet).

---

## 📖 Section 5: Use Azure Advisor (30 minutes)

### What is Azure Advisor?

**Azure Advisor** provides personalized recommendations to:

- Improve reliability (High Availability)
- Enhance security
- Optimize performance
- Reduce costs
- Achieve operational excellence

### Step 5.1: Access Azure Advisor

1. In Azure Portal, search for **Advisor**
2. Click **Advisor** service
3. Review the **Overview** page

**Dashboard shows**:

- Overall score (0-100%)
- Recommendations by category
- Number of affected resources

### Step 5.2: Review Cost Recommendations

1. Click **Cost** tab in left menu
2. Review recommendations (may be none if newly created)

**Common recommendations**:

- Right-size underutilized virtual machines
- Delete unused resources
- Consider reserved instances for predictable workloads
- Use Azure Hybrid Benefit if you have Windows Server licenses

3. If recommendations exist, click one to view details

### Step 5.3: Review Security Recommendations

1. Click **Security** tab
2. Review recommendations

**Common recommendations**:

- Enable Microsoft Defender for Cloud
- Configure diagnostic logs
- Enable encryption
- Configure backup

### Step 5.4: Configure Advisor Alerts

1. Click **Configuration** in left menu
2. Review filtering options:

   - Include/exclude subscriptions
   - Include/exclude resource groups
   - Set low utilization thresholds

3. Click **Alerts** in left menu
4. Click **+ New Advisor alert**

**Create alert rule**:

- **Scope**: Your subscription
- **Condition**: Category = Cost
- **Action group**: (skip for now)
- **Alert details**:
  - Name: `Advisor-Cost-Recommendations`
  - Description: `Alert when new cost recommendations are available`

5. Click **Create alert rule**

**Expected Result**: You'll receive alerts when Advisor identifies new cost-saving opportunities.

---

# 📖 Section 6: Understand Management Groups (15 minutes)

### What are Management Groups?

**Management groups** provide:

- Hierarchical organization above subscriptions
- Policy and access control inheritance
- Enterprise-scale governance

### Structure Example

```
Tenant Root Group
├── Production Management Group
│   └── SkyCraft-Prod Subscription
├── Development Management Group
│   └── SkyCraft-Dev Subscription
└── Shared Services Management Group
    └── SkyCraft-Shared Subscription
```

(This is ideal structure as creation Subscription does not incur any cost)

### Step 6.1: View Management Groups

1. In Azure Portal, search for **Management groups**
2. Click **Management groups** service
3. You'll see the **Tenant Root Group**

**Note**: Creating management groups requires specific permissions. For this lab, understanding the concept is sufficient.

### When to Use Management Groups

- **Multiple subscriptions** - Organize and govern at scale
- **Inherited policies** - Apply governance across many subscriptions
- **Delegated administration** - Grant RBAC at management group level
- **Enterprise structure** - Mirror your organizational hierarchy

---

# ✅ Lab Checklist

### Tags Applied

- [ ] dev-skycraft-swc-rg has 5 tags (Environment, Project, CostCenter, Owner, Purpose)
- [ ] prod-skycraft-swc-rg has 6 tags (+ Criticality)
- [ ] platform-skycraft-swc-rg has 5 tags
- [ ] Can view resources grouped by "Project" tag

### Azure Policies Assigned

- [ ] Policy: Require Environment tag on resource groups
- [ ] Policy: Require Project=SkyCraft on all resources
- [ ] Policy: Restrict resources to East US and West US
- [ ] Policy compliance dashboard shows all three policies
- [ ] Tested policy enforcement (tried creating resource without tag)

### Resource Locks Configured

- [ ] CanNotDelete lock on prod-skycraft-swc-rg
- [ ] CanNotDelete lock on platform-skycraft-swc-rg
- [ ] Tested lock (attempted to delete locked resource group)
- [ ] Lock notes documented

### Cost Management

- [ ] Created subscription-level budget ($200/month)
- [ ] Configured 3 alert thresholds (50%, 80%, 100%)
- [ ] Created resource group-specific budget (prod-skycraft-swc-rg)
- [ ] Explored Cost Analysis with filters
- [ ] Understand daily cost trends

### Azure Advisor

- [ ] Accessed Advisor dashboard
- [ ] Reviewed recommendations by category
- [ ] Configured Advisor alert for cost recommendations
- [ ] Understand how to act on recommendations

### Management Groups

- [ ] Viewed Management Groups in portal
- [ ] Understand hierarchy and inheritance
- [ ] Know when to use management groups

---

## 🔧 Troubleshooting

### Issue 1: Cannot assign policy - insufficient permissions

**Symptom**: Error when creating policy assignment

**Solution**:

- Need Owner, Contributor, or Resource Policy Contributor role
- Check permissions: **Subscription** → **Access control (IAM)** → **Check access**

### Issue 2: Policy doesn't show as enforced

**Symptom**: Created resource without required tag but no error

**Solutions**:

- Policies take 5-10 minutes to propagate
- Policy may be in "Audit" mode instead of "Deny" mode
- Check **Policy enforcement** is set to "Enabled"
- Review policy effect (should be "Deny" for enforcement)

### Issue 3: Cannot delete resource despite Owner role

**Symptom**: "Cannot delete" error even with Owner permissions

**Solution**:

- Check for resource locks: **Resource** → **Locks**
- Remove lock temporarily (document why)
- Delete resource
- Re-apply lock if needed

### Issue 4: Budget alert not received

**Symptom**: Budget threshold reached but no email

**Solutions**:

- Check email spam/junk folder
- Verify email address in budget alert configuration
- Alerts can take 6-8 hours to trigger
- Actual costs must exceed threshold (forecasted costs don't trigger alerts)

### Issue 5: Tag not showing in Cost Analysis

**Symptom**: Applied tags but don't appear in cost breakdown

**Solutions**:

- Cost data can take 24 hours to populate
- Tags must be applied before resources are created
- Use "Cost by tag" view in Cost Analysis
- Ensure tag is applied to actual resources, not just resource group

---

## 🎓 Knowledge Check

1. **Q**: What's the difference between Azure Policy and RBAC?  
   **A**: RBAC controls **who** can do **what** (identity and permissions). Policy controls **what** can be done **regardless of who** does it (compliance and standards).

2. **Q**: When should you use CanNotDelete vs. ReadOnly lock?  
   **A**: Use **CanNotDelete** for production resources (allows operations but prevents deletion). Use **ReadOnly** sparingly (prevents all modifications, can break automation).

3. **Q**: Are tags inherited from resource groups to resources?  
   **A**: No, tags are NOT automatically inherited. You must use Azure Policy with "Modify" effect to inherit tags, or apply tags directly to resources.

4. **Q**: What happens when a budget threshold is reached?  
   **A**: An **alert email** is sent. Budgets do NOT automatically stop resource creation or shut down resources—they only notify.

5. **Q**: Can you remove a lock if you have Owner role?  
   **A**: Yes, Owner can remove locks. However, the lock prevents deletion even for Owners until it's removed.

---

## 📚 Additional Resources

- [Azure Policy overview](https://learn.microsoft.com/en-us/azure/governance/policy/overview)
- [Azure Policy built-in definitions](https://learn.microsoft.com/en-us/azure/governance/policy/samples/built-in-policies)
- [Lock resources to prevent changes](https://learn.microsoft.com/en-us/azure/azure-resource-manager/management/lock-resources)
- [Create and manage budgets](https://learn.microsoft.com/en-us/azure/cost-management-billing/costs/tutorial-acm-create-budgets)
- [Azure Advisor documentation](https://learn.microsoft.com/en-us/azure/advisor/)
- [Organize resources with management groups](https://learn.microsoft.com/en-us/azure/governance/management-groups/overview)

---

## 🔗 What's Next

Congratulations! You've completed **Module 1: Manage Azure Identities and Governance**!

**What You've Accomplished**:

- ✅ Created identity structure (users, groups)
- ✅ Implemented RBAC (role assignments at appropriate scopes)
- ✅ Applied tags for organization and cost tracking
- ✅ Enforced standards with Azure Policy
- ✅ Protected resources with locks
- ✅ Configured cost management and budgets
- ✅ Used Azure Advisor for recommendations

**Your SkyCraft infrastructure now has**:

- Secure identity and access management
- Proper governance and compliance controls
- Cost visibility and control
- Protection against accidental changes

**Next Module**: Module 2 - Implement and Manage Virtual Networking

- Design and deploy virtual networks
- Configure network security groups
- Implement Azure Bastion for secure access
- Configure load balancing and DNS

---

## 📝 Lab Summary

**Time Spent**: ~4 hours

**Governance Components Implemented**:

- 3 Azure Policy assignments
- 2 resource locks
- 15+ tags across resource groups
- 2 budgets with multiple alert thresholds
- Azure Advisor recommendations configured

**Compliance Level**: Production-ready governance framework ✅

---

---

## 📌 Module Navigation

- [← Lab 1.2: Manage Access & RBAC](../1.2-rbac/lab-guide-1.2.md)
- [← Back to Module 1 Index](../README.MD)
- [Module 2: Virtual Networking →](../../module-2-networking/README.md)
