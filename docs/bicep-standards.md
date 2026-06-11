# SkyCraft Bicep Standards

> **Source of Truth** for Infrastructure-as-Code development.

This document outlines the strict coding conventions for Bicep files in the SkyCraft project. All infrastructure code must adhere to these standards to ensure maintainability, readability, and deployment success.

> [!NOTE]
> These standards follow the official [Microsoft Bicep best practices](https://learn.microsoft.com/azure/azure-resource-manager/bicep/best-practices) with a small number of **conscious divergences** documented in [Section 8](#8-conscious-divergences-from-microsoft-guidance).

---

## 1. File Structure & Header

Every Bicep file must start with a standardized header block. This ensures that any engineer opening the file understands its purpose immediately.

```bicep
/*=====================================================
SUMMARY: [Module Name] - [Short Description]
DESCRIPTION: [Detailed description of what this template deploys]
EXAMPLE: az deployment sub create --location swedencentral --template-file main.bicep
AUTHOR/S: [Name]
VERSION: [X.Y.Z]
DEPLOYMENT: .\scripts\Deploy-Bicep.ps1
======================================================*/
```

## 2. API Versioning Standards

To ensure stability, consistency, and tool compatibility across the SkyCraft project, use well-established and stable API versions.

- **Prefer Stable Versions**: Use "Gold Standard" versions (e.g., `2023-11-01` for Networking) rather than bleeding-edge releases.
- **Consistency**: Maintain identical API versions for similar resources across all modules in a laboratory to simplify maintenance.
- **Tooling Support**: Avoid versions so new they may not be fully supported by all standard Bicep CLI versions or VS Code extensions.
- **Simplicity**: Bleeding-edge versions often include specialized enterprise features (like IPAM Pool integration) that add unnecessary complexity to the core learning objectives.

> [!NOTE]
> This policy is enforced by `tests/Api-Version-Policy.Tests.ps1` and is the reason the `use-recent-api-versions` linter rule is disabled in [`bicepconfig.json`](#7-linter-configuration-bicepconfigjson).

## 3. Naming Conventions (Hungarian Notation)

We use specific prefixes to identify the type of object within Bicep code. This prevents confusion between a parameter, a variable, and the resource itself.

> [!NOTE]
> Microsoft guidance recommends plain `lowerCamelCase` without prefixes. We deliberately diverge for educational clarity — see [Section 8.1](#81-hungarian-notation-prefixes).

| Object Type   | Prefix | Format                | Example                            |
| :------------ | :----- | :-------------------- | :--------------------------------- |
| **Parameter** | `par`  | `par[PascalCaseName]` | `parLocation`, `parVnetName`       |
| **Variable**  | `var`  | `var[PascalCaseName]` | `varNsgName`, `varBastionSubnetId` |
| **Resource**  | `res`  | `res[PascalCaseName]` | `resVnet`, `resKeyVault`, `resNic` |
| **Module**    | `mod`  | `mod[PascalCaseName]` | `modSecurityProd`, `modNetworkHub` |
| **Output**    | `out`  | `out[PascalCaseName]` | `outVnetId`, `outPublicIp`         |

### Azure Resource Names

For the names of the **deployed Azure resources themselves** (`prod-skycraft-swc-vnet`, etc.), see [azure-reference.md — Naming Conventions](azure-reference.md#1-naming-conventions). That document is the single source of truth for resource naming; do not duplicate the pattern here (rule D004).

## 4. Architecture Pattern

We aim for a modular architecture that separates **Orchestration** from **Implementation**.

### 4.1 Orchestrator (`main.bicep`)

- **Scope**: `targetScope = 'subscription'` (usually).
- **Purpose**: Creates Resource Groups (if needed) and calls Modules.
- **Content**: Should **not** contain resource definitions directly (except RGs). It should mostly contain `module` blocks.

### 4.2 Modules (`modules/*.bicep`)

- **Scope**: Default (Resource Group).
- **Purpose**: Deploys specific sets of resources (e.g., "Networking", "Security", "Compute").
- **Best Practice**: Modules should be self-contained and reusable.

## 5. Resource Tagging (REQUIRED)

All Azure resources **must** be tagged to comply with governance policies (Lab 1.3).

### Required Tags

Every resource must include the following tags:

| Tag             | Description              | Example                     |
| :-------------- | :----------------------- | :-------------------------- |
| **Project**     | Always set to `SkyCraft` | `Project: 'SkyCraft'`       |
| **Environment** | Deployment environment   | `Environment: 'Production'` |
| **CostCenter**  | Cost tracking identifier | `CostCenter: 'MSDN'`        |

### Implementation Pattern

Define a `varCommonTags` variable and apply it to all resources:

```bicep
var varCommonTags = {
  Project: 'SkyCraft'
  Environment: parEnvironment  // Pass as parameter
  CostCenter: 'MSDN'
}

resource resExample 'Microsoft.Network/networkSecurityGroups@2023-11-01' = {
  name: 'example-nsg'
  location: parLocation
  tags: varCommonTags  // Apply tags here
  properties: {
    // ...
  }
}
```

> [!IMPORTANT] > **Failure to tag resources will cause deployment failures** due to Azure Policy enforcement.

## 6. Best Practices

### 6.1 Parameters

- **Descriptions**: Every `param` must have a `@description('...')` decorator.
- **Validation decorators**: Constrain every parameter that has a known value range. This catches mistakes at compile/validation time instead of mid-deployment:

  ```bicep
  @description('Deployment environment')
  @allowed(['Platform', 'Development', 'Production'])
  param parEnvironment string

  @description('VNet name')
  @minLength(2)
  @maxLength(64)
  param parVnetName string

  @description('Number of VM instances')
  @minValue(1)
  @maxValue(3)
  param parVmCount int = 1
  ```

- **Secrets**: Any parameter carrying a password, key, or connection string **must** be decorated with `@secure()`. Secure parameters must **never** have a default value and must **never** be echoed in outputs:

  ```bicep
  @description('Local administrator password for the VM')
  @secure()
  param parAdminPassword string
  ```

- **No Hardcoding**: Use parameters for values that typically change (names, locations, SKUs).

### 6.2 Variables & Types

- **User-defined types**: For complex object parameters (e.g., a list of subnets), prefer a `type` definition over an untyped `object`/`array`. This gives IntelliSense and compile-time validation:

  ```bicep
  type subnetConfig = {
    name: string
    addressPrefix: string
    nsgId: string?
  }

  @description('Subnets to create in the VNet')
  param parSubnets subnetConfig[]
  ```

- **External content**: Load static JSON or text (policy definitions, custom script content) with `loadJsonContent()` / `loadTextContent()` instead of inlining long strings:

  ```bicep
  var varPolicyRules = loadJsonContent('policies/require-tags.rules.json')
  ```

### 6.3 Outputs

- **Clean Outputs**: Only output values that are needed by other modules or for debugging (e.g., Resource IDs).
- **No secrets in outputs**: Never output passwords, keys, or connection strings — the `outputs-should-not-contain-secrets` linter rule enforces this.

### 6.4 Deployment Workflow

- **What-if first**: Every deployment must be previewed with `what-if` before the real run. The standard pattern (separate args arrays) is defined in [powershell-standards.md — WhatIf Deployment Pattern](powershell-standards.md#5-best-practices).

## 7. Linter Configuration (`bicepconfig.json`)

The repository root contains a [`bicepconfig.json`](../bicepconfig.json) that the Bicep CLI and VS Code extension pick up automatically for every `.bicep` file in the repo. It promotes the most important linter rules to `error` severity, so violations **fail the build** instead of being silently ignored.

Key decisions encoded there:

| Rule                                  | Level   | Rationale                                                         |
| :------------------------------------ | :------ | :---------------------------------------------------------------- |
| `secure-parameter-default`            | `error` | Secure params must never have defaults                            |
| `outputs-should-not-contain-secrets`  | `error` | Prevents secret leakage via deployment history                    |
| `admin-username-should-not-be-literal`| `error` | Admin usernames must come from parameters                         |
| `no-unused-params` / `no-unused-vars` | `error` | Dead code is removed, not ignored                                 |
| `no-hardcoded-env-urls`               | `error` | Use `environment()` function instead                              |
| `use-recent-api-versions`             | `off`   | Conscious divergence — we pin stable versions (see [Section 2](#2-api-versioning-standards)) |

Do not suppress a linter error with `#disable-next-line` without a comment explaining why.

## 8. Conscious Divergences from Microsoft Guidance

These are deliberate decisions where SkyCraft departs from the official Microsoft gold path. Each one trades a production-grade convention for educational clarity. **Do not "fix" these in code review** — if you want to change one, update this document first.

### 8.1 Hungarian Notation Prefixes

- **Microsoft says**: Use plain `lowerCamelCase` names; avoid prefixes ([best practices](https://learn.microsoft.com/azure/azure-resource-manager/bicep/best-practices#parameters)).
- **We do**: `par*`, `var*`, `res*`, `mod*`, `out*` prefixes ([Section 3](#3-naming-conventions-hungarian-notation)).
- **Why**: AZ-104 learners read templates before they write them. Explicit prefixes make the role of every identifier visible at a glance without IDE hover support (e.g., in lab guides, diffs, and printed material).

### 8.2 No Azure Verified Modules (AVM)

- **Microsoft says**: Prefer consuming [Azure Verified Modules](https://aka.ms/avm) from the public registry (`br/public:avm/res/...`) instead of hand-writing resource modules.
- **We do**: Hand-written modules in `bicep/modules/`.
- **Why**: Writing the resource definitions yourself is the learning objective. AVM hides exactly the properties (subnets, NSG rules, SKUs) that AZ-104 requires you to understand. AVM is introduced as a "what production teams actually use" reference, not as the lab tool.

### 8.3 Pinned Stable API Versions

- **Microsoft says** (linter default): Use recent API versions (`use-recent-api-versions`).
- **We do**: Pin "Gold Standard" stable versions per resource family ([Section 2](#2-api-versioning-standards)).
- **Why**: Reproducible labs. A bleeding-edge API version can change validation behaviour mid-course and break published lab guides.

---

> For Azure Storage architecture decisions (redundancy, tiers, public access), see [azure-reference.md](azure-reference.md).

---

## 9. Boilerplate Templates

Copy and paste these templates to start a new file.

### Orchestrator Template (`main.bicep`)

```bicep
/*=====================================================
SUMMARY: [Lab Name] - Orchestrator
DESCRIPTION: Orchestrates deployment for [Lab Name]
EXAMPLE: az deployment sub create --location swedencentral --template-file main.bicep
AUTHOR/S: [Your Name]
VERSION: 0.1.0
DEPLOYMENT: .\scripts\Deploy-Bicep.ps1
======================================================*/

targetScope = 'subscription'

/*******************
*    Parameters    *
*******************/
@description('Location for all resources')
param parLocation string = 'swedencentral'

@description('Resource Group Name')
@minLength(1)
@maxLength(90)
param parResourceGroupName string

/*******************
*    Resources     *
*******************/

resource resRg 'Microsoft.Resources/resourceGroups@2023-07-01' existing = {
  name: parResourceGroupName
}

module modExample 'modules/example.bicep' = {
  name: 'example-deployment'
  scope: resRg
  params: {
    parLocation: parLocation
  }
}

/******************
*     Outputs     *
******************/
output outExampleId string = modExample.outputs.outExampleId
```

### Module Template (`modules/example.bicep`)

```bicep
/*=====================================================
SUMMARY: [Module Name]
DESCRIPTION: Deploys [Resources]
AUTHOR/S: [Your Name]
VERSION: 0.1.0
DEPLOYMENT: [Internal use via Orchestrator]
======================================================*/

/*******************
*    Parameters    *
*******************/
@description('Location for resources')
param parLocation string

@description('Environment tag value')
@allowed(['Platform', 'Development', 'Production'])
param parEnvironment string = 'Production'

/*******************
*    Variables     *
*******************/
var varCommonTags = {
  Project: 'SkyCraft'
  Environment: parEnvironment
  CostCenter: 'MSDN'
}

var varResourceName = 'example-resource'

/*******************
*    Resources     *
*******************/

resource resExample 'Microsoft.Example/examples@2020-06-01' = {
  name: varResourceName
  location: parLocation
  tags: varCommonTags
  properties: {
    // Properties here
  }
}

/******************
*     Outputs     *
******************/
output outExampleId string = resExample.id
```

---

## 10. Known Issues & Gotchas

### 10.1 BCP120: Cannot Reference `kind`/`sku` from Existing Resources (E001)

**Error**: `BCP120: This expression is being used in an assignment to the "kind" property... which requires a value that can be calculated at the start of the deployment.`

**Root Cause**: When re-declaring a storage account to update its `networkAcls` (firewall), Bicep requires `kind` and `sku` — but these cannot be read from an `existing` resource reference at compile time.

**Solution**: Hardcode the known values (`StorageV2`, `Standard_GRS`) since we control the storage account creation in Lab 4.1.

```bicep
// ❌ WRONG — BCP120 error
resource resUpdate 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: resExisting.name
  kind: resExisting.kind        // BCP120!
  sku: { name: resExisting.sku.name }  // BCP120!
}

// ✅ CORRECT — hardcode known values
resource resUpdate 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: resExisting.name
  kind: 'StorageV2'
  sku: { name: 'Standard_GRS' }
}
```

### 10.2 Subnet Name Consistency (E002)

**Error**: Bicep or scripts reference a non-existent subnet (e.g., `ApplicationSubnet`).

**Root Cause**: Lab guides may use conceptual subnet names that don't match the actual subnets created in Module 2.

**Solution**: Always verify subnet names against `module-2-networking/2.2-secure-access/bicep/` definitions:

| Subnet             | Prod CIDR     | Exists Since |
| ------------------ | ------------- | ------------ |
| `AuthSubnet`       | `10.2.1.0/24` | Lab 2.1      |
| `WorldSubnet`      | `10.2.2.0/24` | Lab 2.1      |
| `DatabaseSubnet`   | `10.2.3.0/24` | Lab 2.1      |
| `AppServiceSubnet` | `10.2.4.0/24` | Lab 2.1      |

### 10.3 Content Deduplication (D004)

**Rule**: A concept should be **taught once** (in its most natural module) and **referenced** elsewhere. If a step exists in two labs, consolidate it to the earlier lab and add a cross-reference.

**Example**: Key rotation was taught in both Lab 4.1 (Step 4.1.13) and Lab 4.4 (old Section 2). Consolidated CLI/PS rotation into Lab 4.1 and replaced Lab 4.4's section with ad-hoc SAS tokens.

### 10.4 Azure Backup Policy Cannot Be Updated via ARM (E003)

**Error**: `UserErrorBMSUpdatePolicyNotSupported: Update of existing policy is not supported. Please create a new policy.`

**Root Cause**: Azure Backup (`Microsoft.RecoveryServices/vaults/backupPolicies` and `Microsoft.DataProtection/backupVaults/backupPolicies`) rejects ARM PUT updates on any existing policy. Bicep's idempotent PUT behaviour triggers this error on every re-deployment after the first.

**Solution**: Do not define backup policies in Bicep. Create them in the deployment PowerShell script using an existence-check pattern:

```powershell
# ✅ CORRECT — create only if not present
$existing = az backup policy show --resource-group $rg --vault-name $vault --name $policyName --output json 2>$null | ConvertFrom-Json
if (-not $existing) {
    az backup policy set --resource-group $rg --vault-name $vault --name $policyName --policy "@policy.json" --output none
}
```

### 10.5 Recovery Services Vault Storage Redundancy Is Locked After First Backup (E004)

**Error**: `BMSUserErrorRedundancySettingsUseVaultApi: Redundancy settings for this vault cannot be modified using this API. Since the Vault API was previously used to update the redundancy settings for this vault, you must again use the Vault API to make any further changes to this property.`

**Root Cause**: The `Microsoft.RecoveryServices/vaults/backupstorageconfig` sub-resource cannot be applied after the vault's `storageTypeState` is `Locked` (which happens after the first backup is stored). Additionally, the `redundancySettings` property in the vault body type is **read-only** in the Bicep type system (BCP073).

**Solution**: Set storage redundancy in the deployment PowerShell script using `az backup vault backup-properties set`, guarded by an idempotency check:

```powershell
# ✅ CORRECT — only set if not already LocallyRedundant and not Locked
$props = az backup vault backup-properties show --resource-group $rg --name $vaultName --output json 2>$null | ConvertFrom-Json
if ($props.properties.storageModelType -ne 'LocallyRedundant') {
    az backup vault backup-properties set --resource-group $rg --name $vaultName --backup-storage-redundancy LocallyRedundant --output none
}
# If already Locked at desired value, no action needed.
```

### 10.6 `az backup item list --workload-type VM` Returns Invalid Input (E005)

**Error**: `BMSUserErrorInvalidInput: Input provided for the call is invalid.`

**Root Cause**: The `--workload-type VM` parameter value is not accepted by this command version of `az backup item list`.

**Solution**: Use `--backup-management-type AzureIaasVM` instead:

```powershell
# ❌ WRONG
az backup item list --vault-name $vault --resource-group $rg --workload-type VM

# ✅ CORRECT
az backup item list --vault-name $vault --resource-group $rg --backup-management-type AzureIaasVM
```
