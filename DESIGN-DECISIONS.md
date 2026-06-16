# SkyCraft — Design Decisions & Architecture Layer

> **What this is.** A commentary layer on top of the SkyCraft AZ-104 learning labs.
> Each lab module has an `ARCHITECTURE.md` that explains **why** a design choice
> was made, **what the lab simplifies for clarity**, and **how it would differ in
> a real production environment**. The intent is to help readers signal
> architect-level judgment, not to convert SkyCraft into a hardened reference
> architecture.
>
> **What this is not.** A production reference architecture. SkyCraft labs are
> deliberately simplified for learning: encryption is often optional, networks
> are flat where flat is clearer, costs are minimized over redundancy, and
> several governance/security controls are deferred or made opt-in. The
> `ARCHITECTURE.md` files name those simplifications explicitly so a reader can
> see the gap between a lab and production.

---

## Per-module architecture notes

| Module | Lab | Architecture notes |
|---|---|---|
| 1 — Identities & Governance | 1.1 Entra Users & Groups | [ARCHITECTURE.md](module-1-identities-governance/1.1-entra-users-groups/ARCHITECTURE.md) |
| 1 — Identities & Governance | 1.2 RBAC | [ARCHITECTURE.md](module-1-identities-governance/1.2-rbac/ARCHITECTURE.md) |
| 1 — Identities & Governance | 1.3 Governance | [ARCHITECTURE.md](module-1-identities-governance/1.3-governance/ARCHITECTURE.md) |
| 2 — Networking | 2.1 Virtual Networks | [ARCHITECTURE.md](module-2-networking/2.1-virtual-networks/ARCHITECTURE.md) |
| 2 — Networking | 2.2 Secure Access | [ARCHITECTURE.md](module-2-networking/2.2-secure-access/ARCHITECTURE.md) |
| 2 — Networking | 2.3 Name Resolution | [ARCHITECTURE.md](module-2-networking/2.3-name-resolution/ARCHITECTURE.md) |
| 3 — Compute | 3.1 Infrastructure as Code | [ARCHITECTURE.md](module-3-compute/3.1-infrastructure-as-code/ARCHITECTURE.md) |
| 3 — Compute | 3.2 Virtual Machines | [ARCHITECTURE.md](module-3-compute/3.2-virtual-machines/ARCHITECTURE.md) |
| 3 — Compute | 3.3 Containers | [ARCHITECTURE.md](module-3-compute/3.3-containers/ARCHITECTURE.md) |
| 3 — Compute | 3.4 App Service | [ARCHITECTURE.md](module-3-compute/3.4-app-service/ARCHITECTURE.md) |
| 4 — Storage | 4.1 Storage Accounts | [ARCHITECTURE.md](module-4-storage/4.1-storage-accounts/ARCHITECTURE.md) |
| 4 — Storage | 4.2 Blob Storage | [ARCHITECTURE.md](module-4-storage/4.2-blob-storage/ARCHITECTURE.md) |
| 4 — Storage | 4.3 Azure Files | [ARCHITECTURE.md](module-4-storage/4.3-azure-files/ARCHITECTURE.md) |
| 4 — Storage | 4.4 Storage Security | [ARCHITECTURE.md](module-4-storage/4.4-storage-security/ARCHITECTURE.md) |
| 5 — Monitoring & Maintenance | 5.1 Azure Monitor | [ARCHITECTURE.md](module-5-monitoring-maintenance/5.1-azure-monitor/ARCHITECTURE.md) |
| 5 — Monitoring & Maintenance | 5.2 Business Continuity | [ARCHITECTURE.md](module-5-monitoring-maintenance/5.2-business-continuity/ARCHITECTURE.md) |
| 5 — Monitoring & Maintenance | 5.3 Network Monitoring | [ARCHITECTURE.md](module-5-monitoring-maintenance/5.3-network-monitoring/ARCHITECTURE.md) |

---

## Cross-cutting design themes

These are the load-bearing architectural decisions that show up in more than
one module. The per-module notes explain how each theme materializes in that
lab; this section is the architect's view in one place.

### 1. Hub-Spoke network topology

- **Lab:** One Platform (Hub) VNet `10.0.0.0/16` + two spokes — Development
  `10.1.0.0/16`, Production `10.2.0.0/16`. Hub ↔ spoke peering only; **no
  spoke-to-spoke peering**, so spokes can only reach each other transitively
  through the hub.
- **Production gap:** No central inspection (Azure Firewall / NVA), no NAT
  Gateway for controlled egress, no ExpressRoute or VPN gateway. The
  `GatewaySubnet` is reserved but unused. A real hub holds central DNS
  forwarders, firewall, and shared egress.
- **Why it matters:** The topology is correct for production; what is missing
  is the *machinery inside the hub* that justifies the topology.

### 2. Region lock — Sweden Central

- **Lab:** All deployments default to `swedencentral`. Allowed values in
  parameter validators are typically `swedencentral`, `westeurope`,
  `northeurope`.
- **Production gap:** No multi-region deployment, no paired-region failover,
  no Traffic Manager / Front Door geographic routing. Storage GRS gives passive
  geo-redundancy of bytes only, not of compute.
- **Why it matters:** A single-region project has implicit RPO/RTO
  characteristics that should be made explicit (and accepted) in any real
  design review.

### 3. Resource naming convention

- **Lab:** `{environment}-{project}-{region-code}-{resource-type-suffix}`
  enforced uniformly. Examples: `prod-skycraft-swc-vnet`,
  `dev-skycraft-swc-rg`, `plat-skycraft-swc-nsg-auth`. Codified in
  [docs/bicep-standards.md](docs/bicep-standards.md).
- **Production gap:** No automated linter / policy enforcement of the naming
  scheme; deviations rely on PR review.
- **Why it matters:** Naming is the first FinOps signal. A consistent prefix is
  the difference between a clean cost report and a forensic investigation.

### 4. Mandatory tag taxonomy

- **Lab:** Every resource carries `Project`, `Environment`
  (`Platform` / `Development` / `Production`), `CostCenter`
  (`MSDN` / `Student-Funded`), `Owner`. Defined in
  [SPECIFICATION.md](SPECIFICATION.md) and [docs/bicep-standards.md](docs/bicep-standards.md).
- **Production gap:** Tags are *applied* in Bicep but only a subset
  (`Project`, `Environment`) is *enforced* by Azure Policy in Lab 1.3.
  `CostCenter` and `Owner` can drift silently if a resource is created outside
  IaC.
- **Why it matters:** Tag-driven cost allocation only works if every resource
  is tagged. One untagged storage account becomes the line in the budget
  alert that nobody can explain.

### 5. Personas → RBAC mapping

- **Lab:** Four Warcraft personas — Malfurion (Owner), Khadgar (Contributor),
  Chromie (Reader), Illidan (Guest). Mapped to three security groups
  (Admins, Developers, Testers) and assigned via Lab 1.2.
- **Production gap:** No Privileged Identity Management (PIM) for time-bound
  Owner/Contributor activation; no Conditional Access policies; no
  entitlement reviews for guests; no Deny assignments to protect critical
  resources.
- **Why it matters:** Permanent Owner on a subscription is a pen-test gift.
  The lab teaches the *what*; production needs the *when* (PIM) and the
  *unless* (Deny).

### 6. Environment stratification (Platform / Dev / Prod)

- **Lab:**
  - **Platform / Hub:** shared services, GRS storage, optional Bastion.
  - **Development:** LRS storage, public-blob containers permitted for demos,
    no locks, no enforced policies.
  - **Production:** GRS storage, fully-private blob containers, `CanNotDelete`
    locks (Lab 1.3), lifecycle policies (Lab 4.2), backups (Lab 5.2).
- **Production gap:** No staging / pre-prod between Dev and Prod; no separate
  subscription per environment (a real enterprise pattern); no test data
  isolation.
- **Why it matters:** Two-tier (Dev + Prod) is the floor, not the ceiling. The
  lab makes the trade-off explicit; a real engagement should evaluate it.

### 7. Redundancy by layer

- **Lab:**
  - **Compute:** Two VMs across **different availability zones** (Auth in AZ1,
    World in AZ2). No VM scale sets, no cross-region replication.
  - **Storage:** **GRS** for Platform/Prod, **LRS** for Dev (Lab 4.1).
  - **Networking:** Standard SKU Public IPs and Load Balancers (both
    zone-aware), but a single LB instance per environment.
- **Production gap:** No automated failover, no zone-redundant gateways, no
  active-active multi-region. Backup vault is LRS in Lab 5.2.
- **Why it matters:** AZs protect against a single datacenter; they do not
  protect against a regional outage. The lab teaches the cheap half of the
  picture.

### 8. Public IP & Load Balancer SKU — always Standard

- **Lab:** All Public IPs and Load Balancers are **Standard SKU** (Basic is
  deprecated). Standard PIPs are zone-aware and required by Standard LB.
- **Production gap:** No DDoS Standard plan, no Azure Front Door / Application
  Gateway in front of the LB, no WAF.
- **Why it matters:** Standard SKU is the floor for any modern Azure
  deployment; everything above it (DDoS, WAF, CDN) is layered on top.

### 9. Defense-in-depth — NSGs, ASGs, Bastion

- **Lab:** NSG per subnet (not flat), ASGs defined per workload tier
  (Auth / World / DB), Bastion **optional** (`parDeployBastion=false` default
  to save ~€140/mo). Game ports (3724, 8085) and DB port (3306) restricted to
  caller subnets.
- **Production gap:** No Azure Firewall, no egress restrictions (only ingress
  is constrained), NSG flow logs not enabled until Lab 5.3, no Defender for
  Cloud, no Just-in-Time VM access.
- **Why it matters:** NSGs are stateless and L3/L4 only. They are the
  perimeter, not the strategy.

### 10. Encryption — optional and lab-friendly

- **Lab:** VM disk encryption is *opt-in* (`None` / `EncryptionAtHost` /
  `AzureDiskEncryption`, Lab 3.2). Storage infrastructure encryption is a
  creation-only flag, default off. Customer-managed keys never used.
- **Production gap:** No CMK in Key Vault, no key rotation policies, no Double
  Encryption mandated for regulated workloads.
- **Why it matters:** Encryption-at-rest is on by default with
  Microsoft-managed keys; the lab teaches that the *interesting* decisions
  (CMK, infrastructure encryption, host encryption) sit above that baseline.

### 11. Cost controls — burstable, optional, deletable

- **Lab:** B-series burstable VMs by default. Bastion default-off. LRS for Dev
  storage. App Service P0V4 used in Lab 3.4 *deliberately* to teach Premium
  features, but its cost is called out explicitly.
- **Production gap:** No Azure Reservations, no Savings Plans, no Spot VMs, no
  budget alerts deployed by Bicep (Lab 1.3 mentions them but defers to portal).
- **Why it matters:** Lab-grade cost discipline is "delete when done."
  Production-grade cost discipline is reservations + budgets + anomaly
  detection. The lab does the first half well.

### 12. Data protection — soft delete & lifecycle

- **Lab:** Blob soft delete = 7 days everywhere (Lab 4.1). Production
  containers carry a lifecycle policy that ages logs through Cool (30d) → Cold
  (90d) → Archive (180d) → Delete (365d). Backups are archived after 7 days
  (Lab 4.2).
- **Production gap:** No immutable / WORM containers, no legal hold, no
  cross-region snapshot copies for critical data, soft-delete window is short
  for serious compliance.
- **Why it matters:** Lifecycle is a cost lever **and** a retention lever.
  The lab shows both correctly; what's missing is the *immutability* lever for
  audit/regulatory data.

### 13. Centralized monitoring

- **Lab:** A single Log Analytics Workspace lives in the Platform RG (Lab
  5.1). VM Insights via DCR. Metric alerts route through one Action Group
  (email only). VNet Flow Logs v2 with Traffic Analytics (Lab 5.3) send to the
  same workspace. Diagnostic settings on storage forward audit logs there too.
- **Production gap:** No Defender for Cloud, no Microsoft Sentinel, no SMS /
  PagerDuty / Teams escalation paths, retention is 30 days only, workspace is
  in a single region with no replication.
- **Why it matters:** Centralization is the right architecture decision; the
  lab gets that part right. What it omits is the *escalation* and
  *retention* posture that an SRE / SecOps team needs in practice.

### 14. Infrastructure-as-Code maturity

- **Lab:** Bicep throughout (no ARM JSON). `main.bicep` orchestrator pattern
  with reusable modules in `bicep/modules/`. Standardized header block
  (SUMMARY / DESCRIPTION / EXAMPLE / AUTHOR / VERSION). API versions pinned
  (`2023-11-01` for Networking, `2022-04-01` for Authorization). PowerShell
  conventions and Bicep conventions enforced via
  [docs/bicep-standards.md](docs/bicep-standards.md) and
  [docs/powershell-standards.md](docs/powershell-standards.md).
- **Production gap:** No CI/CD pipeline that lints / validates / `what-if`s
  the Bicep before deployment. No drift detection. No `Microsoft.Resources/deploymentStacks`
  for managed deletion.
- **Why it matters:** Templates without a pipeline are still
  click-through-with-extra-steps. The lab demonstrates the artifact;
  production needs the workflow.

---

## Author decisions (resolved)

Earlier drafts of several `ARCHITECTURE.md` files carried `TODO(author):` markers
where rationale could not be inferred from code alone. These have been resolved:

- **Game-port choices (3724, 8085)** — documented as the default auth/world
  listen ports for World of Warcraft-compatible server cores, which the game
  tier emulates (Lab 2.2).
- **Egress NSG strategy** — kept at default allow-all in the base lab; explicit
  egress allow-lists are deferred to an advanced challenge (Lab 2.2).
- **ACR credential handling (Lab 3.3)** — the lab's `listCredentials()` approach
  leaks the registry password through Bicep outputs; the production alternative
  is Managed Identity (AcrPull) with Key Vault references.
- **Public DNS zone** — `skycraft.example.com` remains a placeholder; a
  "bring-your-own-domain" path is offered as an optional advanced variant
  (Lab 2.3).

A consolidated list is in the PR description that introduces this layer.
