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

## 4. Architecture Policies

### 4.1 Environment Isolation (L002)

- **Rule**: NEVER mix resources or data between environments.
- **Context**: Constraints in one environment (e.g., policy blocking a feature) should NOT be bypassed by connecting to another environment's resources.
- **Solution**: Resolve the constraint at the architecture level (e.g., change SKU).

### 4.2 Feature Compatibility (L003)

- **Rule**: Before coding, verify the Compatibility Matrix.
- **Example**: NFS Azure Files requires Premium tier; Archive Storage requires LRS/GRS.

## 5. Documentation

- All lab guides must reference the specific resource names defined above.
- Do not use generic names like `myVNet` or `test-rg` in guides.

## 6. Media and Images

- **Storage**: Screenshots and diagrams should be stored in an `images` folder within the same directory as the lab guide.
  - Example: `module-2-networking/2.1-virtual-networks/images/`
- **Naming**: Use descriptive, lowercase names with hyphens.
  - Example: `vnet-peering-connected.png`
- **Referencing**: Use relative paths in Markdown.
  - Example: `![VNet Peering Status](images/vnet-peering-connected.png)`

## 7. Learning Loop & Updates

The `docs/` directory is the **Source of Truth** for all project standards. It is typically updated during Phase 3 (`/validate-lab`).

**When to Update Standards**:

1.  **New Constraint Found**: If a lab fails due to a SKU/Region issue, add a rule to the relevant standard in `docs/`.
2.  **Process Improvement**: If a workflow step is consistently confusing, update the relevant `workflow.md`.
3.  **New Pattern**: If a better way to structure guides is found, update `docs/LAB_GUIDE_STANDARDS.md`.

**Rule**: Do not create separate "lessons learned" files. Update the files in `docs/` directly to prevent the error from happening again.

### 7.1 Writing for AI & Retrieval (RAG)

When updating standards, write for machine readability:

- **Self-Contained**: Avoid "as mentioned above". Repeat the context (e.g., "In Storage Accounts...").
- **Explicit naming**: Use full resource names (e.g., "Azure Key Vault") instead of abbreviations ("KV").
- **Semantic Chunking**: Use clear headers (`###`) for each distinct concept so retrieval systems can index it separately.
