# Lab 1.3 - Complete Solutions Guide

## Overview

This document provides complete solutions, expected configurations, and Azure CLI commands for Lab 1.3.

---

## Section 1: Tags - Complete Configuration

### Expected Tag Structure

#### dev-skycraft-swc-rg

```json
{
  "Environment": "Development",
  "Project": "SkyCraft",
  "CostCenter": "MSDN",
  "Owner": "skycraft-admin@yourtenant.onmicrosoft.com"
}
```

#### prod-skycraft-swc-rg

```json
{
  "Environment": "Production",
  "Project": "SkyCraft",
  "CostCenter": "MSDN",
  "Owner": "skycraft-admin@yourtenant.onmicrosoft.com",
  "Criticality": "High"
}
```

#### platform-skycraft-swc-rg

```json
{
  "Environment": "Shared",
  "Project": "SkyCraft",
  "CostCenter": "MSDN",
  "Owner": "skycraft-admin@yourtenant.onmicrosoft.com"
}
```

### Azure CLI Commands - Apply Tags

Set variables

```azcli
SUBSCRIPTION_ID="your-subscription-id"
ADMIN_EMAIL="skycraft-admin@yourtenant.onmicrosoft.com"
```

Apply tags to dev RG

```azcli
az tag update
--resource-id "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/dev-skycraft-swc-rg"
--operation Merge
--tags Environment=Development Project=SkyCraft CostCenter=Engineering Owner=$ADMIN_EMAIL Purpose=AzerothCore-Development
```

Apply tags to prod RG

```azcli
az tag update
--resource-id "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/prod-skycraft-swc-rg"
--operation Merge
--tags Environment=Production Project=SkyCraft CostCenter=Operations Owner=$ADMIN_EMAIL Purpose=AzerothCore-Production Criticality=High
```

Apply tags to prod RG

```azcli
az tag update
--resource-id "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/platform-skycraft-swc-rg"
--operation Merge
--tags Environment=Shared Project=SkyCraft CostCenter=Shared-Services Owner=$ADMIN_EMAIL Purpose=Monitoring-Logging
```

List all resources with Project=SkyCraft tag

`az resource list --tag Project=SkyCraft --query "[].{Name:name,Type:type,RG:resourceGroup}" -o table`

---

## Section 2: Azure Policy - Complete Configuration

### Policy Assignment 1: Require Environment Tag

**Built-in Policy ID**: `96670d01-0a4d-4649-9c89-2d3abc0a5025`

Assign policy

```azcli
az policy assignment create
--name "Require-Environment-Tag-RG"
--display-name "Require Environment Tag on Resource Groups"
--scope "/subscriptions/$SUBSCRIPTION_ID"
--policy "96670d01-0a4d-4649-9c89-2d3abc0a5025"
--params '{"tagName":{"value":"Environment"}}'
--description "All resource groups must have an Environment tag"
```

### Policy Assignment 2: Enforce Project Tag Value

**Built-in Policy ID**: `1e30110a-5ceb-460c-a204-c1c3969c6d62`

Assign policy

```azcli
az policy assignment create
--name "Enforce-Project-Tag"
--display-name "Enforce Project Tag Value"
--scope "/subscriptions/$SUBSCRIPTION_ID"
--policy "1e30110a-5ceb-460c-a204-c1c3969c6d62"
--params '{"tagName":{"value":"Project"},"tagValue":{"value":"SkyCraft"}}'
--description "All resources must have Project tag set to SkyCraft"
```

### Policy Assignment 3: Allowed Locations

**Built-in Policy ID**: `e56962a6-4747-49cd-b67b-bf8b01975c4c`

Assign policy

```azcli
az policy assignment create
--name "Restrict-Azure-Regions"
--display-name "Restrict to Allowed Regions"
--scope "/subscriptions/$SUBSCRIPTION_ID"
--policy "e56962a6-4747-49cd-b67b-bf8b01975c4c"
--params '{"listOfAllowedLocations":{"value":["swedencentral","northeurope"]}}'
--description "Resources can only be created in Sweden Central and North Europe"
```

### View Policy Compliance

List all policy assignments

`az policy assignment list --query "[].{Name:name,DisplayName:displayName,Scope:scope}" -o table`

Check compliance state

`az policy state summarize --subscription $SUBSCRIPTION_ID`

List non-compliant resources

`az policy state list --filter "complianceState eq 'NonCompliant'" --query "[].{Resource:resourceId,Policy:policyDefinitionName}" -o table`

---

## Section 3: Resource Locks - Complete Configuration

### Lock Configuration

| Resource Group | Lock Name | Lock Level | Purpose |
|----------------|-----------|------------|---------|
| prod-skycraft-swc-rg | lock-no-delete-prod | CanNotDelete | Protect production resources |
| platform-skycraft-swc-rg | lock-no-delete-platform | CanNotDelete | Protect shared infrastructure |

### Azure CLI Commands - Apply Locks

Apply lock to production RG

```azcli
az lock create
--name lock-no-delete-prod
--resource-group prod-skycraft-swc-rg
--lock-type CanNotDelete
--notes "Prevents accidental deletion of production resources"
```

Apply lock to platform RG

```azcli
az lock create
--name lock-no-delete-platform
--resource-group platform-skycraft-swc-rg
--lock-type CanNotDelete
--notes "Protects shared monitoring and logging infrastructure"
```

List all locks

`az lock list --resource-group rg-skycraft-prod --query "[].{Name:name,Level:level,Notes:notes}" -o table`
`az lock list --resource-group rg-skycraft-shared --query "[].{Name:name,Level:level,Notes:notes}" -o table`

Test lock (should fail)
`az group delete --name rg-skycraft-prod --yes --no-wait`

Expected: Error message about locked resource

### Remove Lock (if needed)

Get lock ID
`LOCK_ID=$(az lock show --name lock-no-delete-prod --resource-group rg-skycraft-prod --query id -o tsv)`

Delete lock
`az lock delete --ids $LOCK_ID`

---

## Section 4: Budgets - Expected Configuration

### Budget 1: Subscription Level

**Configuration**:
- Name: `SkyCraft-Monthly-Budget`
- Scope: Subscription
- Amount: $200 USD
- Reset period: Monthly
- Time grain: Monthly
- Start date: First day of current month
- Expiration: One year from creation

**Alert Thresholds**:
1. **50% threshold**: Warning alert
   - Type: Actual
   - Recipients: Your email
   
2. **80% threshold**: Critical alert
   - Type: Actual
   - Recipients: Your email
   
3. **100% threshold**: Exceeded alert
   - Type: Actual
   - Recipients: Your email + admin email

### Budget 2: Resource Group Level

**Configuration**:
- Name: `SkyCraft-Prod-Monthly`
- Scope: rg-skycraft-prod
- Amount: $100 USD
- Reset period: Monthly
- Thresholds: 60%, 85%, 100%

**Note**: Budget creation via CLI requires additional setup. Manual creation via portal is recommended for this lab.

---

## Section 5: Azure Advisor - Expected Configuration

### Advisor Alert Rule

**Configuration**:
- Alert name: `Advisor-Cost-Recommendations`
- Category: Cost
- Scope: Subscription
- Action group: (Optional) Create action group for notifications
- Email notifications: Enabled

### Expected Recommendations (Examples)

- **Cost**: Right-size underutilized VMs (will appear after deploying VMs in Module 3)
- **Security**: Enable Microsoft Defender for Cloud
- **Reliability**: Configure backup for VMs
- **Performance**: Optimize database performance
- **Operational Excellence**: Update outdated resources

---

## Knowledge Check Answers

### Question 1: Azure Policy vs. RBAC

**Answer**: 
- **RBAC** (Role-Based Access Control) controls **WHO** can perform actions (identity-based permissions)
- **Azure Policy** controls **WHAT** actions can be performed regardless of who does them (compliance and governance)
- **Example**: RBAC says "John can create VMs", Policy says "VMs must be in East US region"

### Question 2: CanNotDelete vs. ReadOnly

**Answer**:
- **CanNotDelete**: Users can read and modify resources, but cannot delete them (recommended for production)
- **ReadOnly**: Users can ONLY read resources, cannot modify OR delete (very restrictive, can break automation)
- **Use case**: CanNotDelete for production RGs, ReadOnly rarely used except for archived/historical data

### Question 3: Tag Inheritance

**Answer**: 
No, tags are NOT automatically inherited from resource groups to resources. To achieve inheritance, you must:
1. Use Azure Policy with "Modify" effect to enforce tag inheritance
2. Apply tags directly to resources
3. Use automation scripts to copy tags from parent to child

### Question 4: Budget Thresholds

**Answer**: 
When a budget threshold is reached, Azure sends an **alert email** to configured recipients. Budgets do NOT:
- Stop resource deployment
- Shut down resources
- Block spending

They are **informational only**—proactive monitoring, not enforcement.

### Question 5: Removing Locks

**Answer**: 
Yes, users with Owner role CAN remove locks. However, the lock prevents the delete operation itself until removed. Process:
1. Owner removes the lock
2. Owner performs the delete operation
3. (Optional) Owner re-applies the lock

Locks add a **"speed bump"** to prevent accidental deletion, not permanent protection.

---

## Getting Additional Help

- **Azure Portal Support**: Click the **?** icon in top-right corner
- **Microsoft Learn**: https://learn.microsoft.com/en-us/entra/
- **Azure Forums**: https://learn.microsoft.com/en-us/answers/topics/azure.html