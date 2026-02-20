# SkyCraft Bicep Standards

> **Source of Truth** for Infrastructure-as-Code development.

This document outlines the strict coding conventions for Bicep files in the SkyCraft project. All infrastructure code must adhere to these standards to ensure maintainability, readability, and deployment success.

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

## 3. Naming Conventions (Hungarian Notation)

We use specific prefixes to identify the type of object within Bicep code. This prevents confusion between a parameter, a variable, and the resource itself.

| Object Type   | Prefix | Format                | Example                            |
| :------------ | :----- | :-------------------- | :--------------------------------- |
| **Parameter** | `par`  | `par[PascalCaseName]` | `parLocation`, `parVnetName`       |
| **Variable**  | `var`  | `var[PascalCaseName]` | `varNsgName`, `varBastionSubnetId` |
| **Resource**  | `res`  | `res[PascalCaseName]` | `resVnet`, `resKeyVault`, `resNic` |
| **Module**    | `mod`  | `mod[PascalCaseName]` | `modSecurityProd`, `modNetworkHub` |
| **Output**    | `out`  | `out[PascalCaseName]` | `outVnetId`, `outPublicIp`         |

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

- **Descriptions**: Every `param` must have a `@description('...')` decorator.
- **No Hardcoding**: Use parameters for values that typically change (names, locations, SKUs).
- **Clean Outputs**: Only output values that are needed by other modules or for debugging (e.g., Resource IDs).

---

## 7. Storage & Data Standards

### 7.1 Redundancy Decisions (D001)

| Environment     | Redundancy                  | Rationale                                        |
| :-------------- | :-------------------------- | :----------------------------------------------- |
| **Development** | **LRS** (Locally Redundant) | Lowest cost, acceptable risk for ephemeral data. |
| **Production**  | **GRS** (Geo-Redundant)     | Balances disaster recovery with cost.            |

> [!NOTE]
> **SkyCraft Choice**: We chose **GRS** over GZRS for Production because GRS supports Archive Tier (GZRS does not) and is ~17% cheaper.

### 7.2 Constraints & Compatibility (L001)

> [!CAUTION]
> **Archive tier is NOT supported for ZRS, GZRS, or RA-GZRS.**
> If you need lifecycle management with archive tier, you **MUST** use LRS or GRS.

### 7.3 Public Access (D003)

- **Development**: Public Blob Access **Allowed** (for exam prep skills).
- **Production**: Public Blob Access **Disabled** (enterprise security best practice).

---

## 8. Boilerplate Templates

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
