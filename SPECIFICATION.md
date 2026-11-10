# SkyCraft Project Specification

> **Status**: Living document. It tracks the repository, not a release; the released version is in `version.txt` and `CHANGELOG.md`.

This document defines the technical specification for the SkyCraft Azure learning project. It serves as the authoritative source for architectural decisions, identity frameworks, and infrastructure standards.

---

## 1. Project Vision

**SkyCraft** is a scenario-based learning project that simulates the deployment of infrastructure for a massive multiplayer online game ("AzerothCore").

- **Philosophy**: "Production-Grade First". Students build infrastructure as if it were for a real enterprise client, not a sandbox.
- **Pedagogy**: Learn by doing. Every lab builds upon the previous one to create a cohesive platform.
- **Automation**: Emphasis on Infrastructure as Code (Bicep) and Automation (PowerShell) as primary tools.

---

## 2. Architecture Specification

### 2.1 Topology

We utilize a **Hub-Spoke Network Topology** deployed in the **Sweden Central** region.

- **Hub (`platform`)**: Centralized management, connectivity, and visibility.
- **Spoke 1 (`dev`)**: Development environment for rapid iteration.
- **Spoke 2 (`prod`)**: Stable production environment for live workloads.

### 2.2 Technology Stack

- **Cloud Provider**: Microsoft Azure
- **Infrastructure as Code**: Azure Bicep
- **Automation**: PowerShell 7.x (Core)
- **Version Control**: Git
- **Documentation**: Markdown (GFM)

---

## 3. Identity & Access Management (IAM)

### 3.1 Tenant Strategy

- **Standard Tenant**: `skycraft-swc` (or student's own tenant)
- **Domain**: `*.onmicrosoft.com`

### 3.2 The Warcraft Persona Framework

To ensure consistency across labs, we use specific personas mapped to standard RBAC roles.

| Persona                 | Role                     | Description                                                                         |
| :---------------------- | :----------------------- | :---------------------------------------------------------------------------------- |
| **Malfurion Stormrage** | `Owner` / `Global Admin` | **IT Operations Manager**. Has full access to all resources.                        |
| **Khadgar Archmage**    | `Contributor`            | **Lead Developer**. Can create/manage resources in Dev, but cannot assign roles.    |
| **Chromie Timewalker**  | `Reader`                 | **QA / Auditor**. Can view resources in Dev and Prod but cannot modify them.        |
| **Illidan Stormrage**   | `Guest`                  | **External Consultant**. Has limited access to specific resource groups (Platform). |

### 3.3 Groups

- `SkyCraft-Admins`: Malfurion
- `SkyCraft-Developers`: Khadgar
- `SkyCraft-Testers`: Chromie

---

## 4. Network Specification

### 4.1 IP Addressing Strategy

We use a scalable `/16` addressing scheme to prevent overlap.

| Environment        | VNet Name                    | Address Space |
| :----------------- | :--------------------------- | :------------ |
| **Platform (Hub)** | `platform-skycraft-swc-vnet` | `10.0.0.0/16` |
| **Development**    | `dev-skycraft-swc-vnet`      | `10.1.0.0/16` |
| **Production**     | `prod-skycraft-swc-vnet`     | `10.2.0.0/16` |

### 4.2 Subnet Standards

Standardized subnets across both spokes (`10.1.x.0/24` in dev, `10.2.x.0/24` in prod), as deployed by `module-2-networking/2.1-virtual-networks/bicep/main.bicep`:

- `AuthSubnet` (`10.x.1.0/24`): Authentication Servers
- `WorldSubnet` (`10.x.2.0/24`): Game World Servers
- `DatabaseSubnet` (`10.x.3.0/24`): Persistence Layer (SQL/Storage)
- `AppServiceSubnet` (`10.x.4.0/24`): App Service

The hub has two subnets of its own:

- `AzureBastionSubnet` (`10.0.0.0/26`): Azure Bastion
- `GatewaySubnet` (`10.0.1.0/27`): reserved for a future gateway

---

## 5. Governance Standards

### 5.1 Tagging Strategy

All resources must have the following tags:

- `Project`: `SkyCraft`
- `Environment`: `Platform`, `Development`, or `Production`
- `CostCenter`: `MSDN`
- `Owner`: the owner handle (Bicep parameter `parOwner`; default `mbiszczanik`)

### 5.2 Naming Convention

Pattern: `{environment}-{project}-{region}-{resource-type-suffix}`
_Example_: `prod-skycraft-swc-vnet`

---

## 6. Module Specifications

### Module 1: Identities & Governance

- **Focus**: Setting up the "People" and "Rules".
- **Key Deliverables**: Entra ID Users/Groups, RBAC Assignments, Policy Assignments, optional Resource Locks (applied only with `-ApplyLocks` or `parApplyLocks`, removed in Lab 1.3 Step 1.3.14), Budgets.

### Module 2: Networking

- **Focus**: Building the "Roads".
- **Key Deliverables**: VNet Peering, NSGs, ASGs, Azure Bastion (optional), Public/Private DNS, Load Balancers.

### Module 3: Compute

- **Focus**: Building the "Use Case".
- **Key Deliverables**:
  - Infrastructure as Code with Bicep
  - Virtual Machines (Linux), with optional Azure Disk Encryption on the Authserver VM (`-SkipEncryption` skips it)
  - Virtual Machine Scale Sets (VMSS)
  - Container Registry and Container Instances (ACI)
  - App Service (Web Apps) with deployment slots

### Module 4: Storage

- **Focus**: Building the "Vault" for game data.
- **Key Deliverables**: Storage accounts (GRS for Platform and Prod, LRS for Dev), Blob storage with versioning, soft delete and lifecycle rules, Azure Files shares and snapshots, storage security (SAS tokens, stored access policies, firewalls, encryption).

### Module 5: Monitoring & Maintenance

- **Focus**: Keeping the platform observable and recoverable.
- **Key Deliverables**: Azure Monitor with a Log Analytics workspace, diagnostic settings, KQL queries and alerts; Recovery Services Vault and Backup Vault with backup, restore and cross-region failover drills; Network Watcher with a VNet flow log and Connection Monitor.
