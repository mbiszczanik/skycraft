# SkyCraft Azure Reference

> **Source of Truth** for all Azure-specific naming conventions, network topology, architecture policies, and storage decisions.

This document covers **what we build in Azure and why**. For how we organize the project itself, see [project-standards.md](project-standards.md).

---

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
| **Storage Account**   | `sa`           | `prodskycraftswcsa`          |
| **File Share**        | n/a            | `skycraft-config`            |
| **Blob Container**    | n/a            | `skycraft-backups`           |

> **Note**: Storage account names cannot contain hyphens (Azure constraint, 3-24 lowercase alphanumeric). Pattern: `{env}skycraftswcsa`.

---

## 2. Network Topology

### Hub-Spoke Model

- **Hub**: `platform-skycraft-swc-rg` / `platform-skycraft-swc-vnet` (Shared services)
- **Spokes**:
  - `dev-skycraft-swc-rg` / `dev-skycraft-swc-vnet`
  - `prod-skycraft-swc-rg` / `prod-skycraft-swc-vnet`

---

## 3. Architecture Policies

### 3.1 Environment Isolation (L002)

- **Rule**: NEVER mix resources or data between environments.
- **Context**: Constraints in one environment (e.g., policy blocking a feature) should NOT be bypassed by connecting to another environment's resources.
- **Solution**: Resolve the constraint at the architecture level (e.g., change SKU).

### 3.2 Feature Compatibility (L003)

- **Rule**: Before coding, verify the Compatibility Matrix.
- **Example**: NFS Azure Files requires Premium tier; Archive Storage requires LRS/GRS.

---

## 4. Storage & Data Decisions

### 4.1 Redundancy Decisions (D001)

| Environment     | Redundancy                  | Rationale                                        |
| :-------------- | :-------------------------- | :----------------------------------------------- |
| **Development** | **LRS** (Locally Redundant) | Lowest cost, acceptable risk for ephemeral data. |
| **Production**  | **GRS** (Geo-Redundant)     | Balances disaster recovery with cost.            |

> [!NOTE]
> **SkyCraft Choice**: We chose **GRS** over GZRS for Production because GRS supports Archive Tier (GZRS does not) and is ~17% cheaper.

### 4.2 Constraints & Compatibility (L001)

> [!CAUTION]
> **Archive tier is NOT supported for ZRS, GZRS, or RA-GZRS.**
> If you need lifecycle management with archive tier, you **MUST** use LRS or GRS.

### 4.3 Public Access (D003)

- **Development**: Public Blob Access **Allowed** (for exam prep skills).
- **Production**: Public Blob Access **Disabled** (enterprise security best practice).

---

## 5. Subnet Reference

Always verify subnet names against `module-2-networking/2.2-secure-access/bicep/` definitions:

| Subnet             | Prod CIDR     | Exists Since |
| ------------------ | ------------- | ------------ |
| `AuthSubnet`       | `10.2.1.0/24` | Lab 2.1      |
| `WorldSubnet`      | `10.2.2.0/24` | Lab 2.1      |
| `DatabaseSubnet`   | `10.2.3.0/24` | Lab 2.1      |
| `AppServiceSubnet` | `10.2.4.0/24` | Lab 2.1      |
