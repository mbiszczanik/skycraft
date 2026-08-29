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

> [!NOTE]
> API versions apply to **raw resource declarations only**. AVM module references (`br/public:avm/...`) carry no API version — they are pinned by exact module version instead (see [Section 4.4](#44-avm-version-catalogue)) and enforced by `tests/Avm-Module-Pinning.Tests.ps1`.

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

## 4. Architecture Pattern (AVM-First)

We separate **Orchestration** from **Implementation**, and we implement resources by consuming [Azure Verified Modules (AVM)](https://aka.ms/avm) from the public Bicep registry.

### 4.1 Orchestrator (`main.bicep`)

- **Scope**: `targetScope = 'subscription'` (usually).
- **Purpose**: Creates Resource Groups via `br/public:avm/res/resources/resource-group` and calls resource AVM modules **directly**.
- **Content**: `module` blocks (plus trivial `existing` lookups). No raw `resource` definitions.

### 4.2 Consuming AVM Modules

Reference AVM modules directly from the entry point with their **full registry path** and an **exact pinned version**:

```bicep
module modStorage 'br/public:avm/res/storage/storage-account:<pinned-version>' = {
  name: 'storage-deployment'
  scope: resRg
  params: {
    name: varStorageAccountName
    location: parLocation
    tags: varCommonTags
  }
}
```

Rules:

- **No registry aliases** — do not add `moduleAliases` to `bicepconfig.json`. The full `br/public:avm/res/...` path keeps provenance visible in every file (enforced by `tests/Avm-Module-Pinning.Tests.ps1`).
- **AVM parameter names are camelCase** without prefixes — that is the module's contract, not ours. Hungarian notation ([Section 3](#3-naming-conventions-hungarian-notation)) applies only to *our* symbols (`par*`, `var*`, `mod*`, `out*`).
- **Use built-in AVM parameters** instead of separate local modules where they exist: `tags`, `lock`, `diagnosticSettings`, `roleAssignments`.
- **Network access**: building templates with AVM references requires access to `mcr.microsoft.com` (available on GitHub runners; local builds cache modules under `~/.bicep`).

### 4.3 Local Fallback Modules (`modules/*.bicep`)

Hand-written modules are the **exception**, allowed only when no suitable AVM module exists (missing from the AVM index, or not `Available`). Current fallbacks:

- `Microsoft.Resources/tags` (Lab 1.3) — no AVM module exists.
- Autoscale settings (Lab 3.4, `modules/autoscale.bicep`) — `avm/res/insights/autoscale-setting` is only *Proposed*.
- Diagnostic settings on a resource the lab does not deploy itself or whose AVM module has no `diagnosticSettings` parameter (Lab 5.1 `modules/storage-blob-diagnostics.bicep` on the platform storage account's blob service; Lab 5.2 `modules/backup-vault-diagnostics.bicep` on the Backup Vault) — `avm/res/insights/diagnostic-setting` is a *subscription-scope* module (activity log) and cannot target a resource, and `avm/res/data-protection/backup-vault` exposes no `diagnosticSettings` parameter.
- Trivial `existing` lookups (e.g. the public-IP lookup in Lab 2.3) — stay inline or as a tiny local module.
- All of Lab 3.1's modules — see [Section 8.2](#82-hand-written-modules-in-lab-31).

Fallback modules must meet the full gold-path standard: header banner, Hungarian notation, `@description` + validation decorators on every parameter, canonical tags, pinned stable API versions.

### 4.4 AVM Version Catalogue

Every AVM reference pins an **exact version** (`x.y.z`), and a given AVM module uses a **single version across the whole repository**. Both rules are enforced by `tests/Avm-Module-Pinning.Tests.ps1`. To upgrade a module, update every reference and this catalogue in the same PR.

| AVM module | Pinned version | Used in |
| :--- | :--- | :--- |
| `avm/res/app/container-app` | `0.23.0` | Lab 3.3 |
| `avm/res/app/managed-environment` | `0.15.0` | Lab 3.3 |
| `avm/res/authorization/policy-assignment/sub-scope` | `0.1.0` | Lab 1.3 |
| `avm/res/authorization/role-assignment/rg-scope` | `0.1.1` | Lab 1.2 |
| `avm/res/authorization/role-assignment/sub-scope` | `0.1.1` | Lab 1.2 |
| `avm/res/compute/disk` | `0.6.1` | Lab 3.2 |
| `avm/res/compute/virtual-machine` | `0.22.3` | Lab 3.2 |
| `avm/res/container-instance/container-group` | `0.7.0` | Lab 3.3 |
| `avm/res/container-registry/registry` | `0.13.0` | Lab 3.3 |
| `avm/res/data-protection/backup-vault` | `0.13.2` | Lab 5.2 |
| `avm/res/insights/action-group` | `0.8.0` | Lab 5.1 |
| `avm/res/insights/data-collection-rule` | `0.11.0` | Lab 5.1 |
| `avm/res/insights/metric-alert` | `0.4.1` | Lab 5.1 |
| `avm/res/key-vault/vault` | `0.14.0` | Lab 3.2 |
| `avm/res/network/application-security-group` | `0.2.2` | Lab 2.2 |
| `avm/res/network/bastion-host` | `0.8.2` | Lab 2.2 |
| `avm/res/network/dns-zone` | `0.6.2` | Lab 2.3 |
| `avm/res/network/load-balancer` | `0.8.0` | Lab 2.3 |
| `avm/res/network/network-security-group` | `0.5.3` | Lab 2.2 |
| `avm/res/network/network-watcher` | `0.5.1` | Lab 5.3 |
| `avm/res/network/private-dns-zone` | `0.8.1` | Lab 2.3 |
| `avm/res/network/public-ip-address` | `0.13.0` | Lab 2.1 |
| `avm/res/network/virtual-network` | `0.10.2` | Lab 2.1 |
| `avm/res/network/virtual-network/subnet` | `0.2.0` | Lab 2.2 |
| `avm/res/operational-insights/workspace` | `0.16.1` | Lab 5.1 |
| `avm/res/recovery-services/vault` | `0.13.0` | Lab 5.2 |
| `avm/res/resources/resource-group` | `0.4.4` | Labs 1.2, 1.3, 3.3 |
| `avm/res/storage/storage-account` | `0.33.0` | Labs 4.1, 4.2, 4.3, 4.4 |
| `avm/res/web/serverfarm` | `0.7.0` | Lab 3.4 |
| `avm/res/web/site` | `0.24.0` | Lab 3.4 |

> [!NOTE]
> The catalogue is complete for issue #62 v2 (all five modules converted). Upgrading a module means updating every reference and this table in the same PR.

### 4.5 Lab-Friction Overrides

The labs must stay easy to run, test, and tear down for students. Wherever an AVM default conflicts with that, override it explicitly at the call site with a short comment referencing this section. Known overrides:

- **Key Vault** (`key-vault/vault`): Azure no longer allows soft delete to be disabled on new vaults, so the override is the shortest retention (`softDeleteRetentionInDays: 7`) and `enablePurgeProtection: false` (the module defaults to `true`); the lab's `Remove-LabResource.ps1` purges the vault after deleting it so the name is reusable at once (Lab 3.2).
- **Recovery Services Vault** (`recovery-services/vault`): two overrides (Lab 5.2). (1) `softDeleteSettings: { softDeleteState: 'Disabled', enhancedSecurityState: 'Disabled', softDeleteRetentionPeriodInDays: 14 }` — Azure enables soft delete on new vaults, which parks a removed backup item for 14 days and makes `Remove-LabResource.ps1` fail to delete the vault; production keeps soft delete on. (2) `publicNetworkAccess: 'Enabled'` — the module defaults it to `Disabled`, and Azure VM backup into a vault without public access requires private endpoints the lab does not deploy.
- **Backup Vault** (`data-protection/backup-vault`): `softDeleteSettings: { state: 'Off', retentionDurationInDays: 14 }` for the same cleanup reason — `Remove-LabResource.ps1` deletes the blob backup instance and the vault in one pass (Lab 5.2).
- **Load Balancer** (`network/load-balancer`): set `disableOutboundSnat: false` on every load-balancing rule (Lab 2.3). The module defaults it to `true`, which would silently remove the implicit outbound SNAT through the frontend IP that the Module 3 VMs (no public IPs, no NAT gateway) rely on.
- **Container Apps environment** (`app/managed-environment`): `zoneRedundant: false` (the default `true` requires an infrastructure subnet) and `publicNetworkAccess: 'Enabled'` (default `Disabled`), so the consumption environment with external ingress the lab teaches still deploys (Lab 3.3).
- **Container Registry** (`container-registry/registry`): `networkRuleSetDefaultAction: 'Allow'` — with public access enabled the module's default `Deny` makes it emit a `networkRuleSet`, but network rule sets are a Premium-only feature, so on the lab's Standard registry that object is rejected at deploy time (and would have no effect anyway). `Allow` keeps the module from sending one. The module also defaults `azureADAuthenticationAsArmPolicyStatus` to `disabled` while Azure's own default is `enabled`; the lab sets it back to `enabled`, because with it disabled an ARM-audience token cannot reach the registry data plane and `Get-AzContainerRegistryRepository` - the call the lab's `Test-Lab.ps1` makes - fails with `Unauthorized` even though the image is present (Lab 3.3).
- **App Service Plan** (`web/serverfarm`): `zoneRedundant: false` and `skuCapacity: 1` — two independent defaults. The module defaults `zoneRedundant` to `true` for the P and EP SKU tiers (the lab's plan is `P0v4`), and defaults `skuCapacity` to `3` for every SKU; zone redundancy also requires at least two workers, so a one-worker lab plan must opt out of it (Lab 3.4).
- **Storage account** (`storage/storage-account`): two overrides. (1) `networkAcls: { bypass: 'AzureServices', defaultAction: 'Allow' }` in Labs 4.1–4.3 — when the parameter is omitted the module emits `defaultAction: 'Deny'`, which would lock the account down before Lab 4.4, the lab that actually teaches locking it. Lab 4.4 is the one place `Deny` is intentional. (2) `requireInfrastructureEncryption: false` in all four labs — the module defaults it to `true` while Azure's own default is `false`, and the property is creation-only, so left at the module default it would silently enable double encryption on new accounts and produce an unapplicable update on existing ones. Lab 4.1 wires it to its `parEnableInfrastructureEncryption` parameter so the lab's opt-in still works.

Further overrides follow the same principle and are decided per lab.

> [!NOTE]
> Module 4's four labs configure the **same** storage accounts. The AVM storage-account module skips a sub-service entirely when its parameter is empty (`blobServices`, `fileServices`, `queueServices`, `tableServices`, `managementPolicyRules`), so a lab that does not own a sub-service passes `{}` and provably cannot regress an earlier lab. A lab that must write into a sub-service an earlier lab configured restates that earlier configuration — Lab 4.4 is the only such case. Account-level properties are always a full replace, so every lab restates the same baseline. Consequence: run the labs in order; re-running an earlier lab reverts a later lab's settings for the sub-services it owns.

## 5. Resource Tagging (REQUIRED)

All Azure resources **must** be tagged to comply with governance policies (Lab 1.3).

### Required Tags (canonical set)

Every resource carries **exactly** these four tags — no more, no fewer:

| Tag             | Description              | Example                     |
| :-------------- | :----------------------- | :-------------------------- |
| **Project**     | Always set to `SkyCraft` | `Project: 'SkyCraft'`       |
| **Environment** | Deployment environment   | `Environment: 'Production'` |
| **CostCenter**  | Cost tracking identifier | `CostCenter: 'MSDN'`        |
| **Owner**       | Resource owner           | `Owner: 'mbiszczanik'`      |

> [!IMPORTANT]
> `ManagedBy` and `DeploymentDate` are **not** part of the canonical set. In particular, never tag with a deployment timestamp (`parCurrentDate` pattern) — a value that changes on every run breaks `what-if` idempotency and produces noisy diffs.

### Implementation Pattern

Define a `varCommonTags` variable and pass it to every AVM module call via its `tags` parameter (and to any raw resource via `tags:`):

```bicep
@description('Resource owner tag value')
param parOwner string = 'mbiszczanik'

var varCommonTags = {
  Project: 'SkyCraft'
  Environment: parEnvironment
  CostCenter: 'MSDN'
  Owner: parOwner
}

module modVnet 'br/public:avm/res/network/virtual-network:<pinned-version>' = {
  name: 'vnet-deployment'
  scope: resRg
  params: {
    name: varVnetName
    addressPrefixes: [parVnetAddressPrefix]
    location: parLocation
    tags: varCommonTags
  }
}
```

> [!IMPORTANT]
> **Failure to tag resources will cause deployment failures** due to Azure Policy enforcement.

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

### 6.5 Dependencies

- **Never write explicit `dependsOn` when a symbolic reference already exists.** Referencing another resource's or module's property (`modVnet.outputs.outVnetId`) creates the dependency implicitly; a redundant `dependsOn` is dead weight and hides the real data flow.
- Explicit `dependsOn` is allowed **only** for genuine sequencing that no symbolic reference expresses (e.g. VNet peering ordering) — and must carry a comment explaining why.

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

### 8.2 Hand-Written Modules in Lab 3.1

- **Microsoft says**: Prefer consuming [Azure Verified Modules](https://aka.ms/avm) from the public registry instead of hand-writing resource modules — which is exactly what the rest of this repository does ([Section 4](#4-architecture-pattern-avm-first)).
- **We do**: Lab 3.1 (Infrastructure as Code) keeps fully hand-written local modules.
- **Why**: Writing resource definitions by hand **is** that lab's learning objective. Everywhere else the course teaches what production teams actually do — consume AVM; in Lab 3.1 it teaches what is inside such a module. Lab 3.1 receives the gold-path retrofit (decorators, tags, conventions) but no AVM conversion.

### 8.3 Pinned Stable API Versions

- **Microsoft says** (linter default): Use recent API versions (`use-recent-api-versions`).
- **We do**: Pin "Gold Standard" stable versions per resource family ([Section 2](#2-api-versioning-standards)).
- **Why**: Reproducible labs. A bleeding-edge API version can change validation behaviour mid-course and break published lab guides.
- **Scope**: the no-preview / no-future-date rule governs repo-authored `resource` declarations only; AVM modules carry their own upstream pinning and may deploy preview or future-dated API versions internally (e.g. `Microsoft.App/managedEnvironments@2025-10-02-preview`), which `tests/Api-Version-Policy.Tests.ps1` deliberately does not scan.

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
@allowed(['swedencentral', 'northeurope'])
param parLocation string = 'swedencentral'

@description('Environment tag value')
@allowed(['Platform', 'Development', 'Production'])
param parEnvironment string = 'Production'

@description('Resource owner tag value')
param parOwner string = 'mbiszczanik'

@description('Resource Group Name')
@minLength(1)
@maxLength(90)
param parResourceGroupName string

/*******************
*    Variables     *
*******************/
var varCommonTags = {
  Project: 'SkyCraft'
  Environment: parEnvironment
  CostCenter: 'MSDN'
  Owner: parOwner
}

/*******************
*     Modules      *
*******************/

module modResourceGroup 'br/public:avm/res/resources/resource-group:<pinned-version>' = {
  name: 'rg-deployment'
  params: {
    name: parResourceGroupName
    location: parLocation
    tags: varCommonTags
  }
}

resource resRg 'Microsoft.Resources/resourceGroups@2023-07-01' existing = {
  name: parResourceGroupName
}

module modExample 'br/public:avm/res/storage/storage-account:<pinned-version>' = {
  name: 'example-deployment'
  scope: resRg
  params: {
    name: 'examplename'
    location: parLocation
    tags: varCommonTags
  }
  dependsOn: [
    modResourceGroup // RG must exist before RG-scoped modules; no symbolic reference available
  ]
}

/******************
*     Outputs     *
******************/
output outExampleId string = modExample.outputs.resourceId
```

### Local Fallback Module Template (`modules/example.bicep`)

Use only when no suitable AVM module exists — see [Section 4.3](#43-local-fallback-modules-modulesbicep). Remember to extend `varCommonTags` with `Owner` (as in the orchestrator template above).

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

@description('Resource owner tag value')
param parOwner string = 'mbiszczanik'

/*******************
*    Variables     *
*******************/
var varCommonTags = {
  Project: 'SkyCraft'
  Environment: parEnvironment
  CostCenter: 'MSDN'
  Owner: parOwner
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

> [!NOTE]
> **Retired for Module 4 as of PR 4/6 (issue #62 v2).** Labs 4.1-4.4 now call `avm/res/storage/storage-account`, where `networkAcls`, `kind` and `skuName` are ordinary module parameters, so the re-declaration this gotcha describes no longer happens anywhere in the repository. It is kept as a reference for the hand-written pattern (Lab 3.1 and local fallback modules).

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

**Solution**: Always verify subnet names against the `var*Subnets` variables in `module-2-networking/2.1-virtual-networks/bicep/main.bicep` (Lab 2.2 attaches the NSGs to the same names):

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
