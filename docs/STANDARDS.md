# SkyCraft Project Standards

This document serves as the **Source of Truth** for all development, naming conventions, and architectural decisions in the SkyCraft project. All new modules and resources must adhere to these standards.

## 1. Naming Conventions

We strictly follow the Azure Resource Naming recommendations with specific patterns for SkyCraft.

**General Pattern**:  
`{environment}-{project}-{region}-{resource-type-suffix}`

### Definitions

- **Environment**:
  - `dev`: Development
  - `prod`: Production
  - `platform`: Shared Services (Hub)
- **Project**: `skycraft-swc` (includes region shortcut `swc` for Sweden Central if fixed, or just `skycraft` if region varies, but current pattern uses `skycraft-swc`)
- **Region**: Resources should predominantly be in `Sweden Central`.

### Resource Examples

| Resource Type         | Suffix Example | Full Example                 |
| :-------------------- | :------------- | :--------------------------- |
| **Resource Group**    | `-rg`          | `prod-skycraft-swc-rg`       |
| **Virtual Network**   | `-vnet`        | `prod-skycraft-swc-vnet`     |
| **Subnet**            | n/a            | `DatabaseSubnet`             |
| **Network Sec Group** | `-nsg`         | `prod-skycraft-swc-nsg`      |
| **App Sec Group**     | `-asg-{role}`  | `prod-skycraft-swc-asg-auth` |
| **Route Table**       | `-rt`          | `prod-skycraft-swc-rt`       |
| **Load Balancer**     | `-lb`          | `prod-skycraft-swc-lb`       |
| **Public IP**         | `-pip`         | `prod-skycraft-swc-pip`      |
| **Bastion**           | `-bas`         | `platform-skycraft-swc-bas`  |

## 2. Directory Structure

- **Modules**: Root-level folders named `module-X-topic`.
- **Labs**: Sub-folders named `X.Y-lab-name`.
- **Files**:
  - `lab-guide-X.Y.md`: Main instructions.
  - `lab-checklist-X.Y.md`: Verification steps.

## 3. Network Topology

### Hub-Spoke Model

- **Hub**: `platform-skycraft-swc-rg` / `platform-skycraft-swc-vnet` (Shared services)
- **Spokes**:
  - `dev-skycraft-swc-rg` / `dev-skycraft-swc-vnet`
  - `prod-skycraft-swc-rg` / `prod-skycraft-swc-vnet`

## 4. Documentation

- All lab guides must reference the specific resource names defined above.
- Do not use generic names like `myVNet` or `test-rg` in guides.
