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

## 🏗️ Architecture Overview

You will implement the following governance controls:

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="images/lab-1.3-architecture.dark.svg">
  <source media="(prefers-color-scheme: light)" srcset="images/lab-1.3-architecture.svg">
  <img src="images/lab-1.3-architecture.svg" width="100%" alt="Lab 1.3 architecture: policy, locks and budgets">
</picture>

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
- [ ] Owner role at subscription level, or Contributor together with User Access Administrator (Step 1.3.8 gives a managed identity a role on the subscription, which Contributor alone may not do)
- [ ] On a new subscription: the `Microsoft.Insights` resource provider registered (Step 1.3.7 creates an action group and an alert in that namespace, and the Portal does not register it for you; see the note below)
- [ ] Understanding of compliance and governance concepts

**Note**: To register `Microsoft.Insights`, search for **Subscriptions**, click your subscription, and in the left menu, under **Settings**, click **Resource providers**. Search for `Microsoft.Insights`, select the `Microsoft.Insights` row and click **Register**. Its status changes from **NotRegistered** to **Registering** and, after about a minute, to **Registered**. If it does not change to **Registering**, click **Register** again. A subscription you have used before usually has it already; without it, Step 1.3.7 fails (Troubleshooting, Issue 6).

**Note**: With Contributor alone, the paths below end differently at Step 1.3.8. The Portal creates `Inherit-Project-Tag` without the identity's role and says so after **Create**: new resources still get the tag, but the optional remediation task in Step 1.3.10 fails. `scripts/Deploy-Bicep.ps1` fails at the role assignment. `scripts/Invoke-LabGovernance.ps1` creates the assignment, reports `[ERROR]` for the role and exits 1. With Contributor alone, use the Portal and skip the remediation task.

## 🛠️ Portal, PowerShell and Bicep Paths

You can build this lab in the Portal by following this guide, with Az PowerShell, or with Bicep. With the Owner role (see Prerequisites), the three paths end in the same state: the same four policy assignments, of which only `Inherit-Project-Tag` carries a managed identity, holding Contributor on the subscription. `scripts/Test-Lab.ps1` accepts that state whichever path built it:

| Path | What it creates |
| ---- | --------------- |
| Portal (this guide) | Everything in the steps below |
| `scripts/Invoke-LabGovernance.ps1` (Az PowerShell) | The tags of Steps 1.3.1-1.3.3; the four policy assignments of Steps 1.3.5, 1.3.8 and 1.3.9, including the managed identity of `Inherit-Project-Tag` and its role; the locks of Steps 1.3.11 and 1.3.13 |
| `scripts/Deploy-Bicep.ps1` (Bicep, `bicep/main.bicep`) | The same as the PowerShell script |

Step 1.3.8 also shows the Az PowerShell and Azure CLI commands for `Inherit-Project-Tag`, and Step 1.3.10 the Az PowerShell command for its optional remediation task, which neither script runs. These steps have no scripted or Bicep counterpart, because they test, view or explore rather than create, or because the lab keeps them in the Portal: 1.3.4, 1.3.6 (policy test), 1.3.7 (Advisor alert and its action group), 1.3.10 (compliance view; its remediation task has only the command above), 1.3.12 (lock test), 1.3.14, 1.3.15-1.3.17 (budgets), 1.3.18-1.3.22. `Test-Lab.ps1` does not check the budgets or the Advisor alert.

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
- Tags are not inherited from parent scopes (need Azure Policy for inheritance; Step 1.3.8 assigns such a policy)

### Step 1.3.1: Apply Tags to Resource Groups

> [!IMPORTANT] > **Prerequisite**: The resource groups (`platform-skycraft-swc-rg`, `dev-skycraft-swc-rg`, `prod-skycraft-swc-rg`) must already exist. If you haven't created them, complete [Lab 1.2: Manage Access to Azure Resources (RBAC)](../../module-1-identities-governance/1.2-rbac/lab-guide-1.2.md#-section-2-create-resource-groups-15-minutes) first.

1. In Azure Portal, search for **Resource groups**
2. Click on **dev-skycraft-swc-rg**
3. In the left menu, click **Tags**
4. Add the following tags:

| Name        | Value       |
| ----------- | ----------- |
| Environment | Development |
| Project     | SkyCraft    |
| CostCenter  | MSDN        |
| Owner       | mbiszczanik |

5. Click **Apply**

**Note**: If the group already carries these four tags with these values (Lab 1.2's Bicep path creates the groups with them), **Apply** stays greyed out: there is nothing to change. Check the values against the table and go on.

**Expected Result**: Tags are saved and visible in the Tags blade.

![Apply Tags to Resource Groups](./images/step-1.3.1.png)

### Step 1.3.2: Tag Production Resource Group

1. Navigate to **prod-skycraft-swc-rg**
2. Click **Tags**
3. Add these tags:

| Name        | Value       |
| ----------- | ----------- |
| Environment | Production  |
| Project     | SkyCraft    |
| CostCenter  | MSDN        |
| Owner       | mbiszczanik |

4. Click **Apply**

**Note**: If the tags are already there with these values, **Apply** stays greyed out and there is nothing to do (as in Step 1.3.1).

### Step 1.3.3: Tag Platform Services Resource Group

1. Navigate to **platform-skycraft-swc-rg**
2. Click **Tags**
3. Add tags:

| Name        | Value       |
| ----------- | ----------- |
| Environment | Platform    |
| Project     | SkyCraft    |
| CostCenter  | MSDN        |
| Owner       | mbiszczanik |

4. Click **Apply**

**Note**: If the tags are already there with these values, **Apply** stays greyed out and there is nothing to do (as in Step 1.3.1).

### Step 1.3.4: View Resources by Tag

1. In Azure Portal, search for **Tags**
2. In the list of tags, click **Project : SkyCraft**

The **Tags** service lists every tag in your subscription as one name : value pair per line (`CostCenter : MSDN`, `Environment : Development`, `Project : SkyCraft`, ...).

**Expected Result**: **Resources with tag Project : SkyCraft** lists the three resource groups, and any resource that already carries the tag (for example from Lab 1.2's deployment).

**Best Practice**: Standardize tag names and values across your organization to ensure consistency.

![View Resources by Tag](./images/step-1.3.4.png)

---

## 📖 Section 2: Implement Azure Policy (60 minutes)

### What is Azure Policy?

**Azure Policy** helps enforce organizational standards and assess compliance at scale. Policies can:

- **Audit** resources that don't meet requirements
- **Deny** creation of non-compliant resources
- **Modify** resources to meet requirements (e.g., add tags, as `Inherit-Project-Tag` does in Step 1.3.8)
- **Deploy** resources automatically (DeployIfNotExists)

### Built-in vs. Custom Policies

- **Built-in policies** - Pre-defined by Microsoft (500+ available)
- **Custom policies** - Created by your organization for specific needs
- **Policy initiatives** - Groups of policies (also called policy sets)

### Step 1.3.5: Assign a Built-in Policy (Require Tag on Resource Groups)

1. In Azure Portal, search for **Policy**
2. In the left menu, under **Authoring**, click **Assignments**
3. Click **Assign policy**

![Assign a Built-in Policy](./images/step-1.3.5a.png)

4. On the **Basics** tab, fill in:

- Scope: leave it as it is. The wizard fills in your subscription already (its "..." button opens a pane with Subscription showing All selected, which is your subscription)
- Click the "..." button at the end of **Policy definition**
  - Search for **Require a tag on resource groups**
  - Select **Require a tag on resource groups**, then click **Add**
- **Assignment name**: `Require-Environment-Tag-RG`
- **Description**: `All resource groups must have an Environment tag`
- **Policy enforcement**: Default (enforcement)

**Note**: Once you add the definition, the wizard fills **Assignment name** with the definition's own name (`Require a tag on resource groups`). Replace it with `Require-Environment-Tag-RG`: the lab's scripts (`Test-Lab.ps1`, `Remove-LabResource.ps1`) look for an assignment of this definition with that name. In the Portal, **Assignment name** sets the assignment's display name; Azure names the assignment resource itself with a generated id. The wizard also shows a **Version** field (`1.*.*`): leave it as it is.

![Assign a Built-in Policy](./images/step-1.3.5b.png)

5. Click the **Parameters** tab and set:

- **Tag Name**: `Environment`

6. Click the **Non-compliance messages** tab and set:

- **Non-compliance message**: `Resource group must have an Environment tag (Development, Production, or Platform)`

The **Remediation** and **Managed identity** tabs stay as they are: this policy denies, it does not change resources.

7. Click **Review + create**, then **Create**

**Expected Result**: Policy is assigned and will evaluate new resource groups. **Assignments** lists `Require-Environment-Tag-RG`.

![Assign a Built-in Policy](./images/step-1.3.5c.png)

### Step 1.3.6: Test the Policy

First, try to create a resource group **WITHOUT** the "Environment" tag:

1. In Azure Portal, search for **Resource groups**
2. Click **+ Create**
3. On the **Basics** tab, fill in (leave the Tags tab empty):

| Field               | Value          |
| ------------------- | -------------- |
| Resource group name | rg-test-no-tag |
| Region              | Sweden Central |

4. Click **Review + create**
5. If the review page opens without an error, click **Create**, then click the notification **Failed to create the resource group** to open the error details

**Expected Result**: Creation is **denied** by `Require-Environment-Tag-RG`, so `rg-test-no-tag` is not created. The Portal shows the denial in one of two places (both were seen on the same day): either **Review + create** fails with "Validation failed. Required information is missing or not valid.", the **Tags** tab is marked with an error showing the non-compliance message from Step 1.3.5 and a **Policy details** link, and **Create** stays greyed out; or the review page opens without an error and the denial comes after **Create**, where the error details show the error code `RequestDisallowedByPolicy`, the policy `Require-Environment-Tag-RG` with a **Policy link**, and the same message. A policy evaluates every new create or update request. What it does not do is change resources that already exist: a resource group created before the assignment stays without the tag and is reported as non-compliant instead (Step 1.3.10). From the CLI or a template, the same denial comes back with the same error code.

![Assign a Built-in Policy](./images/step-1.3.6a.png)

Now create one with the tag:

6. Close the error details, or the form if the Tags tab showed the error, and click **+ Create** again
7. On the **Basics** tab, fill in:

| Field               | Value            |
| ------------------- | ---------------- |
| Resource group name | rg-test-with-tag |
| Region              | Sweden Central   |

8. Click the **Tags** tab and add:

| Name        | Value |
| ----------- | ----- |
| Environment | Test  |

9. Click **Review + create**, then **Create**

**Expected Result**: Creation succeeds because the required tag is present.

**Note**: If `rg-test-no-tag` was created as well, the assignment was not in effect yet: see Troubleshooting, Issue 2.

![Assign a Built-in Policy](./images/step-1.3.6b.png)

Finally, delete the test resource group `rg-test-with-tag` (the policy denied `rg-test-no-tag`, so it does not exist):

10. Click **Refresh**, then click **rg-test-with-tag**
11. Click **Delete resource group**
12. Fill in the confirmation field:

- **Enter resource group name to confirm deletion**: `rg-test-with-tag`

13. Click outside the field, then click **Delete**
14. In the **Delete confirmation** dialog, click **Delete**

**Note**: The **Delete** button stays greyed out until the name is typed and the field loses focus. That is why you click outside the field first.

After a refresh, `rg-test-with-tag` is no longer listed in **Resource groups**.

### Step 1.3.7: Configure Advisor Alerts

> [!IMPORTANT]
> This step belongs to Section 5 (Azure Advisor), but you do it here, before the next policy step. Step 1.3.8 assigns `Enforce-Project-Tag`, which refuses every new resource without the tag `Project` = `SkyCraft`, and `Inherit-Project-Tag`, which adds that tag from the resource group. The **Create Advisor Alerts** form has no tags, so after Step 1.3.8 the alert is created only while `Inherit-Project-Tag` is in effect and `prod-skycraft-swc-rg` carries `Project` = `SkyCraft`. Created here, it does not depend on either. It stays without tags, and Step 1.3.10 shows it as the resource a remediation task tags.

1. In Azure Portal, search for **Advisor**
2. In the left menu, under **Monitoring** (expand it if it is collapsed), click **Alerts (Preview)**
3. Click **New Advisor Alert**
4. Fill in the top of the form:

- **Subscription**: Your subscription
- **Category**: Cost

5. Under **Action groups**, click **Create new**
6. On the **Basics** tab of the new action group, fill in:

| Field             | Value                |
| ----------------- | -------------------- |
| Resource group    | prod-skycraft-swc-rg |
| Region            | Sweden Central       |
| Action group name | skycraft-advisor-ag  |
| Display name      | SkyAdvisor           |

**Note**: **Region** starts at **(US) East US**. Change it to Sweden Central: Step 1.3.9 will allow only Sweden Central and North Europe, and once that policy is in place an action group in East US is refused (the Portal then shows the refusal only under the notification bell and leaves the form as it was). **Display name** takes at most 12 characters.

![Configure Advisor Alerts](./images/step-1.3.7a.png)

7. Click the **Tags** tab and add:

| Name        | Value       |
| ----------- | ----------- |
| Environment | Production  |
| Project     | SkyCraft    |
| CostCenter  | MSDN        |
| Owner       | mbiszczanik |

8. Click **Review + create**, then **Create**

Back in **Create Advisor Alerts**, the new action group `skycraft-advisor-ag` is listed under **Action groups**.

9. Under **Alert details**, fill in:

- **Alert rule name**: `Advisor-Cost-Recommendations`
- **Description**: `Alert when new cost recommendations are available`
- **Select existing resource group**: `prod-skycraft-swc-rg`

10. Click **Create alert**

**Expected Result**: The Portal confirms with the notification **Successfully created alert** ("Successfully created alert for Azure Advisor"), and **Alerts (Preview)** lists `Advisor-Cost-Recommendations`. The action group has no notification or action, so the alert sends you no email or other message when Advisor finds a new cost-saving opportunity; to be notified, add an email notification to `skycraft-advisor-ag`.

![Configure Advisor Alerts](./images/step-1.3.7b.png)

**Note**: **Alerts (Preview)** lists the rule even when its creation failed. If the Portal says **Failed to create alert** ("An error occurred while trying to create alert"), the alert does not exist: see Troubleshooting, Issue 6.

### Step 1.3.8: Assign Policy for Resource Naming Convention

1. In Azure Portal, search for **Policy**
2. In the left menu, under **Authoring**, click **Assignments**
3. Click **Assign policy**
4. On the **Basics** tab, fill in:

- **Scope**: Your subscription
- Click the "..." button at the end of **Policy definition**
  - Search for **Require a tag and its value on resources**
  - Select **Require a tag and its value on resources**, then click **Add**
- **Assignment name**: `Enforce-Project-Tag`
- **Description**: `All resources must have Project tag set to SkyCraft`

**Note**: As in Step 1.3.5, replace the definition's name that the wizard fills into **Assignment name**.

5. Click the **Parameters** tab and set:

- **Tag Name**: `Project`
- **Tag Value**: `SkyCraft`

6. Click the **Non-compliance messages** tab and set:

- **Non-compliance message**: `All resources must be tagged with Project=SkyCraft`

7. Click **Review + create**, then **Create**

**Note**: From now on, the Portal refuses every new resource in this subscription that does not carry the tag `Project` = `SkyCraft`, unless the assignment below adds the tag for it. Resource groups are not resources in this sense: the definition checks resources only.

Now assign the second tag policy of this step, `Inherit-Project-Tag`. It copies the `Project` tag of a resource group to every new resource created in it without the tag:

8. In the left menu, under **Authoring**, click **Assignments**
9. Click **Assign policy**
10. On the **Basics** tab, fill in:

- **Scope**: Your subscription
- Click the "..." button at the end of **Policy definition**
  - Search for **Inherit a tag from the resource group if missing**
  - Select **Inherit a tag from the resource group if missing**, then click **Add**
- **Assignment name**: `Inherit-Project-Tag`
- **Description**: `Resources get the Project tag of their resource group when they are created without it`

**Note**: The search also lists **Inherit a tag from the resource group**, without "if missing": that one overwrites a tag the resource already has. Take the one that ends in "if missing". As in Step 1.3.5, replace the definition's name that the wizard fills into **Assignment name**.

11. Click the **Parameters** tab and set:

- **Tag Name**: `Project`

12. Click the **Remediation** tab and leave **Create a remediation task** unchecked
13. Click the **Managed identity** tab and set:

- **Create a Managed Identity**: checked
- **Type of Managed Identity**: System assigned managed identity

> [!WARNING]
> Check the next field before you click **Create**: an assignment's identity location cannot be changed after the assignment is created ([Azure Policy assignment structure, Identity](https://learn.microsoft.com/azure/governance/policy/concepts/assignment-structure#identity)). To fix a wrong region, you would have to delete `Inherit-Project-Tag` and assign it again.

- **System assigned identity location**: Sweden Central

**Note**: A Modify policy changes resources, so its assignment needs a managed identity. When you click **Create**, the Portal also gives this identity, by default and without asking, the role that the policy definition lists: **Contributor** on your whole subscription. This opens access: the identity can change any resource in the subscription. Leave it as the Portal sets it, because the optional remediation task in Step 1.3.10 needs it; adding the tag to a new resource needs no role. `scripts/Remove-LabResource.ps1` removes the role together with the assignment. If your account cannot assign roles (Contributor alone, see Prerequisites), the Portal says so after **Create**; the assignment is still created and still tags new resources.

14. Click **Review + create**, then **Create**

**Expected Result**: **Assignments** lists `Enforce-Project-Tag` and `Inherit-Project-Tag`.

**Why two tag policies**: Azure Policy evaluates a create or update request in a fixed order: Modify policies change the request first, and Deny policies check the changed request afterwards. When you create a resource without the `Project` tag in a resource group that carries `Project` = `SkyCraft`, `Inherit-Project-Tag` adds the tag, and `Enforce-Project-Tag` then lets the resource pass. In later labs this covers resources you cannot tag yourself: VM extensions, autoscale settings, deployment slots, and resources a service creates for you in a tagged group (a backup's restore point collection, for example). Two cases stay refused, because there is nothing to inherit: a resource in a group without the `Project` tag (such as `NetworkWatcherRG`, which Azure creates on its own without tags), and a resource group that a service creates itself, such as Site Recovery's target group or `DefaultResourceGroup-*` (refused by `Require-Environment-Tag-RG`). Before you reach such a step in a later lab, create the group yourself, in the region where the service would create it, with the four SkyCraft tags (as in Step 1.3.1, with the **Environment** value of the lab's environment), and pick it where the wizard asks for a group; see Troubleshooting, Issue 7.

**With Az PowerShell** (instead of items 8-14; the other assignments, the tags and the locks of this lab are created by `scripts/Invoke-LabGovernance.ps1`):

```powershell
$subscriptionScope = "/subscriptions/$((Get-AzContext).Subscription.Id)"
$definition = Get-AzPolicyDefinition -Id '/providers/Microsoft.Authorization/policyDefinitions/ea3f2387-9b95-492a-a190-fcdc54f7b070'
$assignment = New-AzPolicyAssignment -Name 'Inherit-Project-Tag' `
    -DisplayName 'Inherit Project Tag from Resource Group' `
    -Scope $subscriptionScope `
    -PolicyDefinition $definition `
    -PolicyParameterObject @{ tagName = 'Project' } `
    -IdentityType 'SystemAssigned' `
    -Location 'swedencentral'

# The Portal grants this role itself; from PowerShell you grant it. If Azure answers that the
# principal does not exist, the new identity is not replicated yet: wait a minute and run it again.
New-AzRoleAssignment -ObjectId $assignment.IdentityPrincipalId -ObjectType 'ServicePrincipal' `
    -RoleDefinitionId 'b24988ac-6180-42a0-ab88-20f7382dd24c' -Scope $subscriptionScope
```

**With the Azure CLI**:

```bash
subscriptionScope="/subscriptions/$(az account show --query id --output tsv)"
az policy assignment create \
  --name Inherit-Project-Tag \
  --display-name "Inherit Project Tag from Resource Group" \
  --scope "$subscriptionScope" \
  --policy "/providers/Microsoft.Authorization/policyDefinitions/ea3f2387-9b95-492a-a190-fcdc54f7b070" \
  --params '{"tagName": {"value": "Project"}}' \
  --mi-system-assigned \
  --location swedencentral \
  --identity-scope "$subscriptionScope" \
  --role Contributor
```

**Note**: Pass `--policy` the full definition path, as above. With the bare id (`ea3f2387-...`), the current Azure CLI fails with `PolicyDefinitionNotFound`, although `az policy definition show` finds the same definition.

### Step 1.3.9: Assign Policy to Enforce Allowed Locations

Prevent resource creation in unintended regions:

1. In the left menu, under **Authoring**, click **Assignments**
2. Click **Assign policy**
3. On the **Basics** tab, fill in:

- **Scope**: Your subscription
- Click the "..." button at the end of **Policy definition**
  - Search for **Allowed locations**
  - Select **Allowed locations**, then click **Add**
- **Assignment name**: `Restrict-Azure-Regions`
- **Description**: `Resources can only be created in Sweden Central and North Europe`

**Note**: The search returns three definitions: Azure Cosmos DB allowed locations, Allowed locations, and Allowed locations for resource groups. Take the one named exactly Allowed locations. As in Step 1.3.5, replace the definition's name that the wizard fills into **Assignment name**.

4. Click the **Parameters** tab and set:

- Open the **Allowed locations** list and tick **Sweden Central** and **North Europe**

The list is a multi-select with a filter box; with both regions ticked, the field shows "2 selected".

5. Click the **Non-compliance messages** tab and set:

- **Non-compliance message**: `Resources must be deployed to Sweden Central or North Europe regions only`

6. Click **Review + create**, then **Create**

### Step 1.3.10: View Policy Compliance

1. In **Policy** service, click **Compliance** in left menu
2. Review the compliance dashboard

**Expected View**:

- **Overall compliance percentage** (likely <100% initially)
- List of assigned policies
- Compliance state: Compliant, Non-compliant, Not started

3. Click on **Require-Environment-Tag-RG** policy
4. View which resource groups are compliant

**Note**: Existing resources created before policy assignment may show as non-compliant. This is expected.

**Note**: A new assignment appears in Compliance only after its first evaluation, which can take up to 30 minutes after you assign it. If `Require-Environment-Tag-RG` is not listed yet, come back to this step after Section 3.

![Assign a Built-in Policy](./images/step-1.3.10.png)

**Optional: tag the resources that existed before Step 1.3.8.** `Inherit-Project-Tag` adds the tag when a resource is created or updated; a resource that already existed without the `Project` tag stays as it is and is listed as non-compliant under `Inherit-Project-Tag` here in **Compliance**. In this lab that is the Advisor alert `Advisor-Cost-Recommendations` from Step 1.3.7, whose form has no tags. A **remediation task** tags such resources. It runs as the assignment's managed identity, with the Contributor role the identity got in Step 1.3.8. Skip these items if your account could not grant that role (see Prerequisites): the task would fail.

**Note**: A role takes about five minutes to take effect after it is granted. Do not start the remediation task sooner than five minutes after Step 1.3.8 (in the Portal, or with the PowerShell or CLI commands there). If the task fails with an authorization error, wait a few minutes and create it again.

5. In the left menu, click **Compliance**
6. Click **Inherit-Project-Tag**

**Note**: **Compliance** lists an assignment by its display name. If you created the assignment with the Bicep path, `scripts/Invoke-LabGovernance.ps1` or the PowerShell or CLI commands of Step 1.3.8, its display name is `Inherit Project Tag from Resource Group`: click that one instead.

7. Click **Create remediation task**
8. Click **Remediate**

The **New remediation task** page opens with that assignment already selected, so **Remediate** is the only thing to click there.

A task can finish as succeeded without remediating anything, so check its result a few minutes later:

9. In the left menu, click **Remediation**
10. Click the **Remediation tasks** tab
11. Click your task, the newest in the list. Its details page shows its status and lists the resources it remediated: there should be one, `Advisor-Cost-Recommendations`. A task whose list is empty remediated nothing, even when its status says it succeeded
12. In Azure Portal, search for **Resource groups**
13. Click on **prod-skycraft-swc-rg**
14. Click on **Advisor-Cost-Recommendations**
15. In the left menu, click **Tags**

**Expected Result**: The Portal confirms with **Remediation task creation succeeded**. Once the task has finished (a few minutes), it lists one remediated resource, the **Tags** page of `Advisor-Cost-Recommendations` shows `Project` = `SkyCraft`, and after the next compliance evaluation `Inherit-Project-Tag` shows the alert as compliant.

**Note**: If the task remediated 0 resources and the alert has no `Project` tag, start a new task with the Az PowerShell command below (in Cloud Shell, for example), then check it with items 9-15. That is what worked on a new subscription: a Portal task created about four minutes after **Compliance** first listed the alert as non-compliant under `Inherit-Project-Tag`, with **Locations** left empty, ended **Succeeded** with 0 deployments; a task with the command's settings (no location filter), created seven minutes later, tagged the alert. Why the first task remediated nothing is not known. If you have run the command before, give the new task another `-Name` (for example `remediate-project-tag-2`) instead of reusing the earlier task's name. Two Portal routes may work too but have not been confirmed: create the task again (items 5-15) after the alert has been listed as non-compliant for a few more minutes, or tick **Re-evaluate resource compliance before remediating** on the **New remediation task** page before you click **Remediate**.

The same with Az PowerShell (the `Start-AzPolicyRemediation` cmdlet ships in the Az.PolicyInsights module):

```powershell
$subscriptionScope = "/subscriptions/$((Get-AzContext).Subscription.Id)"
# The Portal names the assignment with a generated id, so find it by its definition and by the
# name the guide gives it (the Bicep path and Invoke-LabGovernance.ps1 set the display name below).
$assignment = @(Get-AzPolicyAssignment -Scope $subscriptionScope | Where-Object {
        $_.PolicyDefinitionId -like '*/ea3f2387-9b95-492a-a190-fcdc54f7b070' -and $_.Scope -eq $subscriptionScope -and
        ($_.Name -eq 'Inherit-Project-Tag' -or $_.DisplayName -in 'Inherit-Project-Tag', 'Inherit Project Tag from Resource Group')
    })
if ($assignment.Count -ne 1) {
    throw "Found $($assignment.Count) Inherit-Project-Tag assignments on the subscription, expected one. Check Policy > Assignments."
}
Start-AzPolicyRemediation -Name 'remediate-project-tag' -PolicyAssignmentId $assignment[0].Id
```

---

## 📖 Section 3: Configure Resource Locks (30 minutes)

### What are Resource Locks?

**Resource locks** prevent accidental deletion or modification of critical resources. Two types:

- **CanNotDelete** - Users can read and modify but cannot delete
- **ReadOnly** - Users can read but cannot modify or delete (very restrictive)

### Lock Inheritance

Locks applied at parent scope (subscription/resource group) are inherited by child resources.

### Step 1.3.11: Apply CanNotDelete Lock to Production Resource Group

1. In Azure Portal, search for **Resource groups**
2. Click **prod-skycraft-swc-rg**
3. In the left menu, under **Settings** (expand it if it is collapsed), click **Locks**
4. Click **+ Add**
5. Fill in:

| Field     | Value                                                |
| --------- | ---------------------------------------------------- |
| Lock name | lock-no-delete-prod                                  |
| Lock type | Delete                                               |
| Notes     | Cannot delete resource or child resources.           |

> The Bicep path applies both locks through the AVM resource-group module, which sets this notes text itself; the notes are not configurable through the module. If you create the locks in the portal, use the same text so your locks match the checklist. `Test-Lab.ps1` does not read the notes: it checks that each group carries, on the group itself, a lock with the name given in step 1.3.11 or 1.3.13 and the **Delete** (`CanNotDelete`) type.

**Note**: **Lock type** starts at **Read-only**. Change it to **Delete**: a read-only lock on the group would block every change to it and its resources, not only deletion.

6. Click **OK**

**Expected Result**: Lock is created and shows in the Locks list.

![Assign a Built-in Policy](./images/step-1.3.11.png)

### Step 1.3.12: Test the Lock

> [!WARNING]
> This step really asks the Portal to delete the production resource group. The lock from Step 1.3.11 is what stops it. Do not start the step unless **Locks** lists `lock-no-delete-prod` with the lock type Delete: without the lock, the group and everything in it are deleted.

1. Still in `prod-skycraft-swc-rg`, in the left menu, under **Settings** (expand it if it is collapsed), click **Locks** and verify:
   - `lock-no-delete-prod` is listed, with the lock type Delete
2. In the left menu, click **Overview**
3. Click **Delete resource group**
4. Fill in the confirmation field:

- **Enter resource group name to confirm deletion**: `prod-skycraft-swc-rg`

5. Click outside the field, then click **Delete**
6. In the **Delete confirmation** dialog, click **Delete**

**Expected Result**: The Portal refuses before it deletes anything. A notification **Failed to delete resource group prod-skycraft-swc-rg** (open the notification bell if it is not on screen) says: "Resource group prod-skycraft-swc-rg has locks applied. Remove the locks before deleting." The resource group and everything in it stay.

![Test the Lock](./images/step-1.3.12.png)

**Note**: The pane opened by **Delete resource group** shows no lock warning, and the **Delete** button stays greyed out until the name is typed and the field loses focus. The refusal comes only after you confirm. From the CLI or a template, Azure Resource Manager refuses the same delete with the error code `ScopeLocked`.

**Key Learning**: Even with Owner role, you cannot delete a locked resource until the lock is removed.

### Step 1.3.13: Apply CanNotDelete Lock to Platform Resource Group

1. Navigate to **platform-skycraft-swc-rg**
2. In the left menu, under **Settings** (expand it if it is collapsed), click **Locks** → **+ Add**
3. Create lock:
   - Lock name: `lock-no-delete-platform`
   - Lock type: **Delete**
   - Notes: `Cannot delete resource or child resources.`

**Note**: As in Step 1.3.11, **Lock type** starts at **Read-only**: change it to **Delete**.

4. Click **OK**

### Step 1.3.14: Understand Lock Hierarchy

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

![Manage Costs with Budgets and Alerts](./images/step-1.3.15a.png)

### Step 1.3.15: Create a Subscription Budget

1. In Azure Portal, search for **Cost Management + Billing**
2. In the left menu, click **Cost Management**
3. In the left menu, under **Monitoring**, click **Budgets**
4. Click **+ Add**

**Note**: Cost Management + Billing opens on **Billing scopes**. **Cost Management** then opens at a scope the Portal picks for you (sometimes a **Scope automatically selected** popover says so) and names it at the top of the page, after **Scope**. It should be your subscription; if it is another scope, click **Change scope** in the left menu and pick your subscription before you continue.

5. On the **Create a budget** step, fill in:

| Field           | Value                                               |
| --------------- | --------------------------------------------------- |
| Name            | SkyCraft-Monthly-Budget                             |
| Reset period    | Monthly                                             |
| Creation date   | [The current month; the day is fixed to the 1st]    |
| Expiration date | [Leave the default, two years from now]             |
| Amount          | 100 (in your billing currency; adjust to your needs) |

**Note**: **Reset period** starts at **Billing month**. Pick **Monthly**, which the list shows under **Calendar months**. The **Amount** field is labelled with your billing currency (for example **Amount (€)**).

**Note**: On a subscription created the same day, the cost chart of **Create a budget** can show **Cannot load data**. That is expected: cost data can take up to 48 hours to appear (note in Step 1.3.18), and the budget is still created.

6. Click **Next >**

![Manage Costs with Budgets and Alerts](./images/step-1.3.15b.png)

### Step 1.3.16: Configure Budget Alerts

On the **Set alerts** step, every alert is one row under **Alert conditions**. A new empty row appears below each row you fill in.

1. Fill in three rows under **Alert conditions** (leave the Action group column at None):

| Type        | % of budget |
| ----------- | ----------- |
| Actual cost | 50          |
| Actual cost | 80          |
| Actual cost | 100         |

2. Fill in the recipients:

- **Alert recipients (email)**: [your email address]

**Note**: **Alert recipients (email)** is one list for all the rows: every recipient gets every alert of this budget. To add a second address, type it in the empty row that appears below the first. **Languages** can stay at Default.

3. Click **Create**

**Expected Result**: Budget is created and **Budgets** lists `SkyCraft-Monthly-Budget`. The recipients may also receive a confirmation email.

![Manage Costs with Budgets and Alerts](./images/step-1.3.16.png)

### Step 1.3.17: Create Resource Group Budget

Create a more specific budget for the production environment. A budget belongs to the scope it is created at, so you create this one from the resource group itself:

1. In Azure Portal, search for **Resource groups**
2. Click **prod-skycraft-swc-rg**
3. In the left menu, under **Cost Management** (expand it if it is collapsed), click **Budgets**
4. Click **+ Add**

**Note**: In **Create budget**, **Scope** is plain text and shows `prod-skycraft-swc-rg`: it cannot be changed there. Do not use **Add filter** to pick the group: that creates a subscription budget with a filter, not a budget of the resource group.

5. On the **Create a budget** step, fill in:

| Field        | Value                         |
| ------------ | ----------------------------- |
| Name         | SkyCraft-Prod-Monthly         |
| Reset period | Monthly                       |
| Amount       | 50 (in your billing currency) |

6. Click **Next >**
7. On the **Set alerts** step, fill in three rows under **Alert conditions**:

| Type        | % of budget |
| ----------- | ----------- |
| Actual cost | 60          |
| Actual cost | 85          |
| Actual cost | 100         |

8. Fill in the recipients:

- **Alert recipients (email)**: [your email address]

9. Click **Create**

**Expected Result**: The resource group's **Budgets** lists `SkyCraft-Prod-Monthly`.

![Manage Costs with Budgets and Alerts](./images/step-1.3.17.png)

### Step 1.3.18: View Cost Analysis

1. In Azure Portal, search for **Subscriptions**
2. Click your subscription
3. Under **Cost Management** click **Cost analysis**
4. Open the **VIEW** menu and, under **Built-in views**, explore:
   - **Cost by resource** - See spending per resource
   - **Cost by service** - See spending per Azure service
   - **Daily costs** - Trend over time

**Note**: Open Cost analysis from the subscription, as here. **Cost Management + Billing** has no **Cost analysis** of its own, and its **Go to subscription** link opens the scope you used last (after Step 1.3.17, the production resource group).

![Manage Costs with Budgets and Alerts](./images/step-1.3.18a.png)

5. Click the date range button (it shows the current period) and, under **Relative dates**, click **Last 30 days**
6. Click **Add filter**, choose **Tag**, then pick the tag `project` with the value `skycraft` (Cost analysis shows tag names and values in lower case), and click the green check mark next to the filter to apply it
7. Click **Add filter** again, choose **Resource group name**, pick `prod-skycraft-swc-rg` and click the green check mark

**Expected Result**: Visual charts showing cost breakdown (likely very low since we haven't deployed resources yet).

![Manage Costs with Budgets and Alerts](./images/step-1.3.18b.png)

**Note**: On a subscription created the same day, Cost analysis can show **Unable to load** instead of the charts, and no **Add filter**, for up to 48 hours: Microsoft says a new subscription may wait that long for all Cost Management features. The **VIEW** menu and **Last 30 days** still work, but items 6-7 cannot be done yet. The budget chart of Step 1.3.15 shows **Cannot load data** for the same reason. Nothing is wrong with the lab: come back to this step later. `Test-Lab.ps1` does not check it.

---

## 📖 Section 5: Use Azure Advisor (30 minutes)

### What is Azure Advisor?

**Azure Advisor** provides personalized recommendations to:

- Improve reliability (High Availability)
- Enhance security
- Optimize performance
- Reduce costs
- Achieve operational excellence

### Step 1.3.19: Access Azure Advisor

1. In Azure Portal, search for **Advisor**
2. Review the **Overview** page
3. In the left menu, click **Advisor score**

**Overview shows** one card per category (Cost, Security, Reliability, Operational excellence, Performance), each with:

- Its own score ("Score --%" until Advisor has assessed the category)
- The number of active recommendations
- The number of impacted resources

The overall score (0-100%) is on the separate **Advisor score** page.

![Manage Costs with Budgets and Alerts](./images/step-1.3.19.png)

### Step 1.3.20: Review Cost Recommendations

1. In the left menu, under **Recommendations**, click **Cost**
2. Review recommendations (may be none if newly created)

**Common recommendations**:

- Right-size underutilized virtual machines
- Delete unused resources
- Consider reserved instances for predictable workloads
- Use Azure Hybrid Benefit if you have Windows Server licenses

3. If recommendations exist, click one to view details

### Step 1.3.21: Review Security Recommendations

1. In the left menu, under **Recommendations**, click **Security**
2. Review recommendations

**Common recommendations**:

- Enable Microsoft Defender for Cloud
- Configure diagnostic logs
- Enable encryption
- Configure backup

![Review Security Recommendations](./images/step-1.3.21.png)

**Advisor alerts**: you created the Advisor alert for cost recommendations in [Step 1.3.7](#step-137-configure-advisor-alerts), in Section 2, before the tag policy of Step 1.3.8 could refuse it. To see it, open **Alerts (Preview)** under **Monitoring** in Advisor's left menu.

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

### Step 1.3.22: View Management Groups

1. In Azure Portal, search for **Management groups**
2. Click **Management groups** service
3. You'll see the **Tenant Root Group**

![View Management Groups](./images/step-1.3.22.png)

**Note**: Creating management groups requires specific permissions. For this lab, understanding the concept is sufficient.

### When to Use Management Groups

- **Multiple subscriptions** - Organize and govern at scale
- **Inherited policies** - Apply governance across many subscriptions
- **Delegated administration** - Grant RBAC at management group level
- **Enterprise structure** - Mirror your organizational hierarchy

---

# ✅ Lab Checklist

### Tags Applied

- [ ] dev-skycraft-swc-rg has 4 tags (Environment, Project, CostCenter, Owner)
- [ ] prod-skycraft-swc-rg has 4 tags
- [ ] platform-skycraft-swc-rg has 4 tags
- [ ] Can view resources grouped by "Project" tag

### Azure Policies Assigned

- [ ] Policy: Require Environment tag on resource groups
- [ ] Policy: Require Project=SkyCraft on all resources
- [ ] Policy: Inherit the Project tag from the resource group (Modify, with a system-assigned managed identity)
- [ ] Policy: Restrict resources to Sweden Central and North Europe
- [ ] Policy compliance dashboard shows all four policies
- [ ] Tested policy enforcement (tried creating resource without tag)

### Resource Locks Configured

- [ ] CanNotDelete lock on prod-skycraft-swc-rg
- [ ] CanNotDelete lock on platform-skycraft-swc-rg
- [ ] Tested lock (attempted to delete locked resource group)
- [ ] Lock notes documented

### Cost Management

- [ ] Created subscription-level budget (100 per month, in your billing currency)
- [ ] Configured 3 alert thresholds (50%, 80%, 100%)
- [ ] Created resource group-specific budget (prod-skycraft-swc-rg, 50 per month)
- [ ] Explored Cost Analysis with filters (on a new subscription, once Cost analysis loads, which can take up to 48 hours; Step 1.3.18)
- [ ] Understand daily cost trends

### Azure Advisor

- [ ] Accessed Advisor dashboard
- [ ] Reviewed recommendations by category
- [ ] On a new subscription, registered the `Microsoft.Insights` resource provider before Step 1.3.7 (Prerequisites)
- [ ] Configured Advisor alert for cost recommendations (Step 1.3.7, before Step 1.3.8)
- [ ] Understand how to act on recommendations

### Management Groups

- [ ] Viewed Management Groups in portal
- [ ] Understand hierarchy and inheritance
- [ ] Know when to use management groups

**For detailed verification**, see [lab-checklist-1.3.md](lab-checklist-1.3.md)

---

## 📦 What This Lab Leaves Behind

No later lab needs an object this lab creates: `tools/lab-cycle-manifest.psd1` lists no lab that depends on Lab 1.3. Every later lab in this subscription runs under its policies and locks, though, and they change what you can create and delete there. Everything below costs nothing per day.

| Left behind | Where | Daily cost | What it does in later labs |
| --- | --- | --- | --- |
| `Require-Environment-Tag-RG` | Subscription | 0 | Refuses a new resource group without an `Environment` tag, including a group a service would create itself (Troubleshooting, Issue 7) |
| `Enforce-Project-Tag` | Subscription | 0 | Refuses a new resource without `Project` = `SkyCraft`, unless `Inherit-Project-Tag` adds it |
| `Inherit-Project-Tag` | Subscription | 0 | Adds the resource group's `Project` tag to a new resource created without it, so resources you cannot tag (VM extensions, autoscale settings, deployment slots) pass `Enforce-Project-Tag` in a tagged group |
| Managed identity of `Inherit-Project-Tag`, with Contributor | Subscription | 0 | Can change any resource in the subscription; only a remediation task uses it |
| `Restrict-Azure-Regions` | Subscription | 0 | Refuses a resource outside Sweden Central and North Europe |
| `lock-no-delete-prod`, `lock-no-delete-platform` | prod and platform resource groups | 0 | Block every delete in those groups, including a later lab's cleanup, until the locks are removed |
| Tags on the three resource groups | dev, prod and platform resource groups | 0 | The `Project` tag that `Inherit-Project-Tag` copies to new resources |
| `SkyCraft-Monthly-Budget`, `SkyCraft-Prod-Monthly` | Subscription, prod resource group | 0 | Send emails at their thresholds; they never stop a deployment |
| `Advisor-Cost-Recommendations` and its action group `skycraft-advisor-ag` | prod resource group | 0 | Nothing reaches you: Step 1.3.7 creates the action group without any notification or action, so a new Advisor cost recommendation sends no email or other message |
| `Microsoft.Insights` resource provider registered (on a new subscription, Prerequisites) | Subscription | 0 | Lets later labs create action groups, alert rules and diagnostic settings |

`scripts/Remove-LabResource.ps1` removes all of these except the tags and the resource provider registration, whichever path created them. It removes the locks first, and the identity's role before its assignment. Run it before Lab 1.2's cleanup deletes the resource groups, because the locks block that delete.

---

## 🔧 Troubleshooting

### Issue 1: Cannot assign policy - insufficient permissions

**Symptom**: Error when creating policy assignment

**Solution**:

- Need Owner, Contributor, or Resource Policy Contributor role to assign a policy
- `Inherit-Project-Tag` (Step 1.3.8) also gives its managed identity a role, which needs Owner or User Access Administrator. Without it, the Portal creates the assignment without the role, the Bicep path fails and `Invoke-LabGovernance.ps1` exits 1 (see Prerequisites)
- Check permissions: **Subscription** → **Access control (IAM)** → **Check access**

### Issue 2: Policy doesn't show as enforced

**Symptom**: Created resource without required tag but no error

**Solutions**:

- A new assignment takes about five minutes to take effect, sometimes longer. If Step 1.3.6 created `rg-test-no-tag`, delete it the way the step deletes `rg-test-with-tag`, wait a few minutes and try again
- Policy may be in "Audit" mode instead of "Deny" mode
- Check **Policy enforcement** is set to "Default (enforcement)", not "Do not enforce"
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

### Issue 6: Advisor alert or its action group is refused

**Symptom**: In Step 1.3.7, the Portal says "Failed to create alert - An error occurred while trying to create alert", or the action group's **Create** does nothing and the notification bell shows "Failed to create action group"

**Solutions**:

- Action group, on a new subscription: the bell shows "Create action group: Failed to create action group. Error: The subscription is not registered to use namespace 'microsoft.insights'. See https://aka.ms/rps-not-found for how to register subscriptions." Register the `Microsoft.Insights` resource provider as the note under Prerequisites shows, wait until its status is **Registered**, then click **Create** again on the same form: it keeps what you filled in
- Action group: set **Region** to Sweden Central. `Restrict-Azure-Regions` (Step 1.3.9) refuses the default East US
- Alert: `Enforce-Project-Tag` (Step 1.3.8) is in effect in your subscription, for example from an earlier run of this lab or its Bicep path, and `Inherit-Project-Tag` does not add the tag for the alert. The **Create Advisor Alerts** form has no tags, so the alert passes `Enforce-Project-Tag` only through `Inherit-Project-Tag`. **Alerts (Preview)** may still list the refused alert, but it does not exist. Check that **Policy** → **Assignments** lists `Inherit-Project-Tag` (assigned more than about ten minutes ago, with **Tag Name** `Project`) and that `prod-skycraft-swc-rg` carries `Project` = `SkyCraft` on its **Tags** page, then create the alert again. `Test-Lab.ps1` does not check the alert

### Issue 7: A resource without tags is refused although `Inherit-Project-Tag` is assigned

**Symptom**: In this lab or a later one, creating a resource fails with `RequestDisallowedByPolicy` and "All resources must be tagged with Project=SkyCraft", or a resource group fails with the Environment tag message, although Step 1.3.8 assigned `Inherit-Project-Tag`

**Root Cause**: `Inherit-Project-Tag` copies the tag from the resource's own resource group. It has nothing to copy when that group has no `Project` tag, and it does not apply to resource groups at all. It also takes effect only some minutes after you assign it, like every assignment.

**Solutions**:

- Check that the resource group carries `Project` = `SkyCraft` (**Resource groups** → the group → **Tags**). A group Azure creates on its own, such as `NetworkWatcherRG`, has no tags until you add them
- A resource group that a service would create itself (Site Recovery's target group, `DefaultResourceGroup-*`) is refused by `Require-Environment-Tag-RG`: create the group yourself, in the region where the service would create it, with the four SkyCraft tags, then pick it in the wizard. `NetworkWatcherRG`, which Azure creates without tags, gets them the same way: add the four tags on its **Tags** page before you create anything in it
- Check that `Inherit-Project-Tag` is the definition that ends in "if missing", with **Tag Name** `Project`, and that **Assignments** lists it; `Test-Lab.ps1` checks both
- Right after Step 1.3.8, wait about ten minutes and try again

### Issue 8: The Bicep deployment fails with `RoleAssignmentUpdateNotPermitted`

**Symptom**: `scripts/Deploy-Bicep.ps1` fails on the role assignment of `Inherit-Project-Tag` with `RoleAssignmentUpdateNotPermitted` ("Tenant ID, application ID, principal ID, and scope are not allowed to be updated")

**Root Cause**: The Bicep path names the identity's role assignment from the subscription, the role, the region and the assignment's name, so every run uses the same name. When `Inherit-Project-Tag` was deleted in the Portal, its role assignment stayed behind, held by an identity that no longer exists. The next deployment creates a new identity and tries to give the old role assignment to it, which Azure does not allow.

**Solutions**:

- Remove the stale role assignment yourself: **Subscriptions** → your subscription → **Access control (IAM)** → **Role assignments**, find the **Contributor** row whose name is **Identity not found**, check it, click **Delete**, then deploy again. `scripts/Remove-LabResource.ps1` does not find it: it removes the role assignments of the policy assignments that still exist
- Next time, remove the lab with `scripts/Remove-LabResource.ps1` rather than in the Portal: it removes the identity's role assignment before the policy assignment, so none is left behind

---

## 🎓 Knowledge Check

Test your understanding with these questions:

1. **What's the difference between Azure Policy and RBAC?**

   <details>
     <summary>**Click to see the answer**</summary>

   **Answer**: RBAC controls **who** can do **what** (identity and permissions). Policy controls **what** can be done **regardless of who** does it (compliance and standards).
   </details>

2. **When should you use CanNotDelete vs. ReadOnly lock?**

   <details>
     <summary>**Click to see the answer**</summary>

   **Answer**: Use **CanNotDelete** for production resources (allows operations but prevents deletion). Use **ReadOnly** sparingly (prevents all modifications, can break automation).
   </details>

3. **Are tags inherited from resource groups to resources?**

   <details>
     <summary>**Click to see the answer**</summary>

   **Answer**: No, tags are NOT automatically inherited. You must use Azure Policy with "Modify" effect to inherit tags (as `Inherit-Project-Tag` does from Step 1.3.8 on), or apply tags directly to resources.
   </details>

4. **What happens when a budget threshold is reached?**

   <details>
     <summary>**Click to see the answer**</summary>

   **Answer**: An **alert email** is sent. Budgets do NOT automatically stop resource creation or shut down resources—they only notify.
   </details>

5. **Can you remove a lock if you have Owner role?**

   <details>
     <summary>**Click to see the answer**</summary>

   **Answer**: Yes, Owner can remove locks. However, the lock prevents deletion even for Owners until it's removed.
   </details>

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

- 4 Azure Policy assignments (three Deny, one Modify with a managed identity)
- 2 resource locks
- 12 tags across resource groups (4 canonical tags per resource group)
- 2 budgets with multiple alert thresholds
- Azure Advisor recommendations configured

**Compliance Level**: Production-ready governance framework ✅

---

---

## 📌 Module Navigation

- [← Lab 1.2: Manage Access & RBAC](../1.2-rbac/lab-guide-1.2.md)
- [← Back to Module 1 Index](../README.md)
- [Module 2: Virtual Networking →](../../module-2-networking/README.md)
