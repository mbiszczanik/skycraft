# Lab 1.2 - Complete Solutions Guide

## Overview

This document provides complete solutions and expected outcomes for Lab 1.2.

---

## Section 2: Resource Groups - Expected Configuration

### Resource Group: rg-skycraft-dev

**Properties**:

- Name: `rg-skycraft-dev`
- Location: `East US` (or your selected region)
- Resource ID: `/subscriptions/[YOUR-SUB-ID]/resourceGroups/rg-skycraft-dev`

**Tags**:

```json
{
  "Environment": "Development",
  "Project": "SkyCraft"
}
```

### Resource Group: rg-skycraft-prod

**Properties**:

- Name: `rg-skycraft-prod`
- Location: `East US`
- Resource ID: `/subscriptions/[YOUR-SUB-ID]/resourceGroups/rg-skycraft-prod`

**Tags**:

```json
{
  "Environment": "Production",
  "Project": "SkyCraft"
}
```

### Resource Group: rg-skycraft-shared

**Properties**:

- Name: `rg-skycraft-shared`
- Location: `East US`
- Resource ID: `/subscriptions/[YOUR-SUB-ID]/resourceGroups/rg-skycraft-shared`

**Tags**:

```json
{
  "Environment": "Shared",
  "Project": "SkyCraft"
}
```

---

## Section 3 & 4: Role Assignments - Complete Configuration

### Assignment Matrix

| Principal              | Type         | Role        | Scope              | Purpose                                         |
| ---------------------- | ------------ | ----------- | ------------------ | ----------------------------------------------- |
| SkyCraft Admin         | User         | Owner       | Subscription       | Full administrative access across all resources |
| AzerothCore-Developers | Group        | Contributor | rg-skycraft-dev    | Create and manage dev resources                 |
| AzerothCore-Testers    | Group        | Reader      | rg-skycraft-dev    | Monitor dev environment                         |
| AzerothCore-Testers    | Group        | Reader      | rg-skycraft-prod   | Monitor prod environment                        |
| External Partner       | User (Guest) | Reader      | rg-skycraft-shared | Limited access to shared services               |

---

## Azure CLI Commands - Complete Solution

Set variables

```azcli
SUBSCRIPTION_ID="your-subscription-id-here"
LOCATION="eastus"
```

Login to Azure
`az login`

Set subscription context
`az account set --subscription $SUBSCRIPTION_ID`

### Create Resource Groups

Development
az group create

```azcli
az group create
--name rg-skycraft-dev
--location $LOCATION
--tags Environment=Development Project=SkyCraft Purpose="Development and testing"
```

Production

```azcli
az group create
--name rg-skycraft-prod
--location $LOCATION
--tags Environment=Production Project=SkyCraft Purpose="Production deployment"
```

Shared

```azcli
az group create
--name rg-skycraft-shared
--location $LOCATION
--tags Environment=Shared Project=SkyCraft Purpose="Shared services"
```

### Assign Roles - Subscription Level

Get Admin user object ID
`ADMIN_ID=$(az ad user show --id skycraft-admin@yourtenant.onmicrosoft.com --query id -o tsv)`

Assign Owner role at subscription level

```azcli
az role assignment create
--assignee $ADMIN_ID
--role "Owner"
--scope "/subscriptions/$SUBSCRIPTION_ID"
```

### Assign Roles - Resource Group Level

Get group object IDs

```azcli
DEV_GROUP_ID=$(az ad group show --group AzerothCore-Developers --query id -o tsv)
TEST_GROUP_ID=$(az ad group show --group AzerothCore-Testers --query id -o tsv)
PARTNER_ID=$(az ad user show --id partner@externalcompany.com --query id -o tsv)
```

Dev RG: Contributor for Developers

```azcli
az role assignment create
--assignee $DEV_GROUP_ID
--role "Contributor"
--resource-group rg-skycraft-dev
```

Dev RG: Contributor for Developers

```azcli
az role assignment create
--assignee $TEST_GROUP_ID
--role "Reader"
--resource-group rg-skycraft-dev
```

Prod RG: Reader for Testers

```azcli
az role assignment create
--assignee $TEST_GROUP_ID
--role "Reader"
--resource-group rg-skycraft-prod
```

Shared RG: Reader for Partner

```azcli
az role assignment create
--assignee $PARTNER_ID
--role "Reader"
--resource-group rg-skycraft-shared
```

### Verification

List all role assignments for dev RG

```azcli
az role assignment list
--resource-group rg-skycraft-dev
--output table
```

Check specific user's access

```azcli
az role assignment list
--assignee skycraft-dev@yourtenant.onmicrosoft.com
--all
--output table
```

---

## FAQ

### Question 1: Owner vs. Contributor

**Answer**: 
- **Owner** = Full access to all resources + can manage access (assign roles to others)
- **Contributor** = Full access to all resources but CANNOT manage access
- Use case: Admins get Owner, developers get Contributor

### Question 2: Why assign to groups?

**Answer**:
1. **Easier management** - Add/remove users from groups instead of changing role assignments
2. **Reduces role assignment count** - Subscription limit is 4000 assignments
3. **Clearer access model** - Permissions tied to job function, not individuals
4. **Faster propagation** - Group membership changes apply immediately

### Question 3: Creating resource groups

**Answer**: 
No, Contributor at resource group level cannot create new resource groups. Creating RGs requires permissions at subscription level (typically Owner or Contributor at subscription scope).

### Question 4: Conflicting roles

**Answer**: 
The **most permissive role wins**. If a user has Reader at subscription and Contributor at resource group, they get Contributor permissions in that RG (can create/modify resources). Azure RBAC is additive.

### Question 5: Deleted resource group

**Answer**: 
All role assignments scoped to that resource group are automatically deleted. Role assignments at subscription level remain unaffected.

---

## Getting Additional Help

- **Azure Portal Support**: Click the **?** icon in top-right corner
- **Microsoft Learn**: https://learn.microsoft.com/en-us/entra/
- **Azure Forums**: https://learn.microsoft.com/en-us/answers/topics/azure.html
