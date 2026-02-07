# SkyCraft Project Specification

> **Version**: 1.0.0
> **Last Updated**: 2026-01-11
> **Status**: Approved

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

Standardized subnets across all spokes:

- `AuthSubnet` (`10.x.1.0/24`): Authentication Servers
- `WorldSubnet` (`10.x.2.0/24`): Game World Servers
- `DatabaseSubnet` (`10.x.3.0/24`): Persistence Layer (SQL/Storage)

---

## 5. Governance Standards

### 5.1 Tagging Strategy

All resources must have the following tags:

- `Project`: `SkyCraft`
- `Environment`: `Platform`, `Development`, or `Production`
- `CostCenter`: `MSDN` or `Student-Funded`
- `Owner`: `malfurion.stormrage@...`

### 5.2 Naming Convention

Pattern: `{environment}-{project}-{region}-{resource-type-suffix}`
_Example_: `prod-skycraft-swc-vnet`

---

## 6. Module Specifications

### Module 1: Identities & Governance

- **Focus**: Setting up the "People" and "Rules".
- **Key Deliverables**: Entra ID Users/Groups, RBAC Assignments, Policy Definitions, Resource Locks, Budgets.

### Module 2: Networking

- **Focus**: Building the "Roads".
- **Key Deliverables**: VNet Peering, NSGs, ASGs, Azure Bastion, Public/Private DNS, Load Balancers.

### Module 3: Compute

- **Focus**: Building the "Use Case".
- **Key Deliverables**:
  - Virtual Machines (Linux/Windows)
  - Virtual Machine Scale Sets (VMSS)
  - App Services (Web Apps)
  - Container Instances (ACI)

### Module 4: Storage

- **Focus**: Building the "Persistence Layer".
- **Key Deliverables**:
  - Storage Accounts (Standard/Premium)
  - Blob Containers & Access Tiers
  - Azure Files (SMB/NFS)
  - Storage Security (Firewalls, SAS, Private Endpoints)

### Module 5: Monitoring & Maintenance

- **Focus**: Building the "Operations Center".
- **Key Deliverables**:
  - Log Analytics Workspaces (LAW)
  - Azure Monitor Alerts & Metrics
  - VM Insights & Diagnostic Settings
  - Azure Backup & Recovery Services Vault
  - Network Watcher Diagnostics
