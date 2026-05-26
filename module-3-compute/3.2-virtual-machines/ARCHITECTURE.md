# Architecture Notes: Lab 3.2 — Virtual Machines

> Learning context. These notes explain the reasoning behind the lab's design and how it would change in a real environment. The lab deliberately favors clarity over production hardening.

## 1. Design decisions & trade-offs

| Decision | Choice in this lab | Alternatives considered | Why this choice (in a learning context) |
|---|---|---|---|
| VM SKU default | Standard_B2s (2 vCPU, 4 GB RAM, burstable) | Standard_D2s_v3 (fixed performance, costlier), Standard_B1s (smaller, insufficient for game servers) | B2s is the "sweet spot" for a lab: burstable CPU is cheap (~€30/mo), sufficient for light loads, and teaches students the "burst concept" before graduating to fixed-SKU VMs in production. |
| VM SKU options | B1s, B2s, B2ms, D2s_v3, D4s_v3 | Fixed list only | Constrains choices to reasonable options; production leaves SKU open for students to research. |
| OS Image | Ubuntu 22.04 LTS Gen2 (Canonical, jammy, official) | Ubuntu 20.04 LTS, CentOS, RHEL, Windows | 22.04 is AzerothCore's recommended baseline; Gen2 VMs use UEFI and support new features like Encryption at Host. |
| OS Disk | 30 GB Standard SSD (StandardSSD_LRS), delete on VM delete | 128 GB, Premium_LRS, retain for snapshots | 30 GB is enough for OS + minimal services; StandardSSD_LRS (~€3.50/mo) is cost-effective. Production sizes based on application footprint and data growth. |
| VM Count | 2 (Auth in AZ1, World in AZ2) | 1 VM, or 3+ with scale sets | 2 VMs teach availability zone distribution without the complexity of scale sets; students see failover in action if one zone fails. |
| Availability Zones | Auth in Zone 1, World in Zone 2 | Same zone, or mixed | Different zones ensure a zone failure doesn't knock out both services. Lab shows this; production may use scale sets for auto-replacement. |
| Data Disk (World VM only) | 64 GB StandardSSD_LRS, Zone 2 | 128 GB, Premium_LRS, separate VM | 64 GB is enough for a game database in a lab; StandardSSD is cost-effective (~€8/mo). Production sizes based on player count and retention policy. Only World VM gets one because it hosts the game database; Auth is stateless. |
| SSH Authentication | SSH public key only, disable passwords | Allow password auth or certificate | SSH key is more secure and teaches modern practices. Production enforces key rotation and audits key distribution. |
| System-Assigned Managed Identity | Enabled on all VMs | None, or User-Assigned only | Enables VMs to fetch encryption keys or secrets without storing credentials. Lab keeps it simple; production layers with User-Assigned identities for fine-grained RBAC. |
| Encryption Strategy | None (default), EncryptionAtHost, AzureDiskEncryption options | None only | Parameterized to teach the trade-off: no encryption is fast and cheap; EncryptionAtHost adds latency but encrypts at the hypervisor; ADE adds key management complexity. |
| Load Balancer Backend Pools | Both VMs in pools (Auth in auth pool, World in world pool) | Direct public IPs, or all in one pool | Backend pools teach separation of concerns; each service has its own health probe and rule. Direct public IPs would expose both services independently (not using the LB). |

## 2. Lab simplifications vs production

| Aspect | What the lab does | What production would require | Why it matters |
|---|---|---|---|
| SSH Access | Via Bastion in hub VNet | Bastion or private jump server | Lab assumes Bastion is set up (Lab 3.1 or earlier); direct SSH from internet to VM is a security risk. Production ensures no public SSH ingress. |
| Data Disk Encryption | Optional via Azure Disk Encryption (ADE) module | Encryption at Rest mandatory for PII/regulated data | Lab makes encryption optional to show its cost trade-off; production enforces it for compliance (GDPR, HIPAA, etc.). |
| Monitoring | No logs or alerting | Azure Monitor + Log Analytics + Alert Rules | VMs run without observability; production collects diagnostics, application logs, and CPU/disk alerts. |
| Backup | No snapshots or backup policy | Automated daily snapshots or Azure Backup | Lab disks are ephemeral; production requires RTO/RPO guarantees. |
| Public IPs | None on VMs (routed through LB) | Private IPs only, egress via NAT Gateway or Firewall | Lab relies on LB public IP; production avoids public IPs on VMs to reduce attack surface. |
| VM Agent | Enabled | Required for extensions (monitoring, patching) | Lab enables it for future use; production uses it for auto-patching and guest OS configuration. |
| Auto-Shutdown | Not configured | Via auto-shutdown policy or budgets | Lab leaves VMs on 24/7; production uses auto-shutdown for dev/test VMs to avoid idle charges. |

## 3. Well-Architected lens (light)

- **Dominant pillar:** Reliability (availability zones, managed identity for secure credential handling)
- **Cost Management:** B2s burstable SKU teaches cost-optimization; auto-shutdown could save ~70% on dev VM cost. StandardSSD is a good middle ground between speed and cost.
- **Security:** Managed identity enables secure secret retrieval; encryption options teach compliance trade-offs. SSH key-only removes password attack surface.
- **Operational Excellence:** Parameterized encryption strategy and SKU allow experimentation without code changes.
- **Performance:** Burstable CPU is sufficient for light auth/world loads; production upgrades to D-series for consistent performance.

## 4. Cost / FinOps note

**Monthly recurring cost (if left on 24/7)**:
- 2 × Standard_B2s VMs: ~€30 each = €60/mo
- 2 × 30 GB StandardSSD_LRS OS disks: ~€3.50 each = €7/mo
- 1 × 64 GB StandardSSD_LRS data disk: ~€8/mo
- 1 Key Vault (if ADE enabled): ~€0.50/mo
- **Estimated total**: €75–76/mo with no encryption; ~€77/mo with ADE.

**Lab cost controls**:
- Enable auto-shutdown on both VMs: reduces cost to ~€10/mo during lab hours (night/weekend off).
- Delete extra snapshots immediately after backup testing.
- Deallocate VMs when not actively testing (~€7/mo for disk storage alone).

**Cleanup reminder after the lab**:
- **Delete both VMs** (resource intensive; frees ~€60/mo compute cost).
- **Delete orphaned OS disks** if VMs are deleted but disks are retained (still cost ~€7/mo).
- **Delete data disk** (frees ~€8/mo).
- Delete NIC resources (minor cost, but clean).
- Delete or empty Key Vault if ADE was used (reserves the name for 90 days, costing ~€0.50/mo).
