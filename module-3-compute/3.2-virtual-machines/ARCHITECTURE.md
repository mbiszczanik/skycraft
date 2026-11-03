# Architecture Notes: Lab 3.2 — Virtual Machines

> Learning context. These notes explain the reasoning behind the lab's design and how it would change in a real environment. The lab deliberately favors clarity over production hardening.

## 1. Design decisions & trade-offs

| Decision | Choice in this lab | Alternatives considered | Why this choice (in a learning context) |
|---|---|---|---|
| VM SKU default | Standard_B2ls_v2 (2 vCPU, 4 GB RAM, burstable v2) | Standard_D2s_v3 (fixed performance, costlier), Standard_B2s_v2 (same 2 vCPU but 8 GB RAM, dearer — the size Azure Disk Encryption needs); the B-series v1 sizes the lab originally used (B1s, B2s, B2ms) cannot deploy in Sweden Central on this subscription | B2ls_v2 is the "sweet spot" for a lab: burstable CPU is cheap (~€30/mo), sufficient for light loads, and teaches students the "burst concept" before graduating to fixed-SKU VMs in production. |
| VM SKU options | B2ls_v2, B2als_v2, B2s_v2, B2as_v2, D2s_v3, D4s_v3 | Fixed list only | Constrains choices to reasonable options; B-series v1 is not available in Sweden Central on the lab subscription, so the list is the v2 burstable family plus D-series. Production leaves the SKU open for students to research. |
| OS Image | Ubuntu 22.04 LTS Gen2 (Canonical, jammy, official), image version pinned to `22.04.202506200` (kernel `6.8.0-1030-azure`) in the Bicep | `latest`; Ubuntu 20.04 LTS, CentOS, RHEL, Windows | 22.04 is AzerothCore's recommended baseline; Gen2 VMs use UEFI and support new features like Encryption at Host. `latest` booted kernel `6.8.0-1065-azure`, which Azure Site Recovery (Lab 5.2) rejected with `ASRMobilityServiceKernelNotSupportedV2`; Microsoft Learn's Site Recovery support matrix lists `6.8.0-1030-azure` for Mobility service 9.66 and later. The Portal cannot pick an image version, so a Portal-made VM gets the newest image and Lab 5.2 Troubleshooting boots a supported kernel. |
| OS Disk | 30 GB Standard SSD (StandardSSD_LRS), delete on VM delete | 128 GB, Premium_LRS, retain for snapshots | 30 GB is enough for OS + minimal services; StandardSSD_LRS (~€3.50/mo) is cost-effective. Production sizes based on application footprint and data growth. |
| VM Count | 2 (Auth in AZ1, World in AZ2) | 1 VM, or 3+ with scale sets | 2 VMs teach availability zone distribution without the complexity of scale sets; students see failover in action if one zone fails. |
| Availability Zones | Auth in Zone 1, World in Zone 2 | Same zone, or mixed | Different zones ensure a zone failure doesn't knock out both services. Lab shows this; production may use scale sets for auto-replacement. |
| Data Disk (World VM only) | 64 GB StandardSSD_LRS, Zone 2, LUN 0, named `<prefix>-world-vm-data` as the guide names it; mounted at `/data` through `/dev/disk/azure/scsi1/lun0-part1` | 128 GB, Premium_LRS, separate VM; a mount by `/dev/sdX` | 64 GB is enough for a game database in a lab; StandardSSD is cost-effective (~€8/mo). Production sizes based on player count and retention policy. Only World VM gets one because it hosts the game database; Auth is stateless. B2ls_v2 has no temporary disk, so the device letter of the data disk differs from sizes that have one; the LUN path does not. |
| SSH Authentication | SSH public key only, disable passwords | Allow password auth or certificate | SSH key is more secure and teaches modern practices. Production enforces key rotation and audits key distribution. |
| System-Assigned Managed Identity | Enabled on all VMs | None, or User-Assigned only | Enables VMs to fetch encryption keys or secrets without storing credentials. Lab keeps it simple; production layers with User-Assigned identities for fine-grained RBAC. |
| Encryption Strategy | AzureDiskEncryption (default) on the **Auth VM only**: the template creates the Key Vault and `Deploy-Bicep.ps1` runs `Enable-Encryption.ps1`, which resizes the Auth VM to 8 GB, encrypts it and resizes it back. EncryptionAtHost and None stay as parameters | ADE on both VMs (the lab's state before #368); encryption at host instead of ADE; ADE as an opt-in | Lab 5.2 restores files from and replicates the World VM, and file-level recovery is not available for an ADE VM; it backs up the Auth VM to teach the Key Vault role Azure Backup needs (maintainer decision 2026-10-16, #368). ADE retires in September 2028 and AZ-104 lists encryption at host, which Step 3.2.21 shows on the World VM (a VM that ever had ADE cannot get it). All three paths leave the same VM encrypted (#362); `Test-Lab.ps1` checks the Auth VM encrypted and the World VM not. The OS encryption takes about 2 hours, so the default deployment does too; `-SkipEncryption` defers it. |
| Load Balancer Backend Pools | Each VM in its role pool (Auth in auth pool, World in world pool) and both in the egress pool `<lb>-be-outbound` | Direct public IPs, or all in one pool | Backend pools teach separation of concerns; each service has its own health probe and rule. Direct public IPs would expose both services independently (not using the LB). |
| Application security groups | In dev, the Auth NIC in `dev-skycraft-swc-asg-auth` and the World NIC in `dev-skycraft-swc-asg-world` (Lab 2.2's ASGs); none in prod | Leave the ASGs empty; create prod ASGs too | Lab 2.2 creates the ASGs, and an ASG is only practised once NICs are in it and a rule names it (#345, #353). Lab 2.2 creates them in dev only, so the template adds the NICs only when `parEnvironment` is dev and `Deploy-Bicep.ps1` gates on them there. |
| Scale set | A Portal exercise (Steps 3.2.29-3.2.33): `dev-skycraft-swc-world-vmss`, Uniform, in the **dev** group, scaled by hand and by autoscale rules, then deleted. Not in the template | The prod group (the guide's place before 2026-10-16); a Bicep scale set | Lab 1.3 locks `prod-skycraft-swc-rg` with `CanNotDelete`, so the delete of Step 3.2.33 failed there with `ScopeLocked` (maintainer decision 2026-10-16). The guide's end state has no scale set, so the template creates none; `Remove-LabResource.ps1` removes a leftover one with its autoscale setting and the `basicNsg<nic>` NSG the wizard creates, and `Test-Lab.ps1` warns about it. Its instances join `be-world` only, so they have no internet access. |
| Outbound connectivity | Both VM NICs in `<lb>-be-outbound`, the pool of the load balancer's one outbound rule (Lab 2.3) | A NAT gateway on the subnets; a public IP per VM; one outbound rule per role pool | The subnets are private, so a VM outside `be-outbound` has no internet access (package updates, VM extensions). A frontend IP takes only one outbound rule with an overlapping protocol, so the roles share one egress pool. The portal's VM wizard joins a single pool, so the guide adds both VMs to `be-outbound` afterwards; `main.bicep` puts each NIC in both pools and `Test-Lab.ps1` checks it. |

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
- **Cost Management:** B2ls_v2 burstable SKU teaches cost-optimization; auto-shutdown could save ~70% on dev VM cost. StandardSSD is a good middle ground between speed and cost.
- **Security:** Managed identity enables secure secret retrieval; encryption options teach compliance trade-offs. SSH key-only removes password attack surface.
- **Operational Excellence:** Parameterized encryption strategy and SKU allow experimentation without code changes.
- **Performance:** Burstable CPU is sufficient for light auth/world loads; production upgrades to D-series for consistent performance.

## 4. Cost / FinOps note

**Monthly recurring cost (if left on 24/7)**:
- 2 × Standard_B2ls_v2 VMs: ~€30 each = €60/mo
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
- Delete the Key Vault if ADE was used — `Remove-LabResource.ps1 -IncludeKeyVault` deletes **and** purges it, so the name is reusable at once (soft-delete retention is 7 days, purge protection off).

## 5. Bicep implementation note (AVM)

- **VMs**: `avm/res/compute/virtual-machine`. The NICs are created by the module from `nicConfigurations` (there is no separate NIC module any more), including the load-balancer backend pools on the IP configuration (the role pool and `<lb>-be-outbound`) and `enableAcceleratedNetworking: false`.
- **Data disk**: `avm/res/compute/disk`, attached to the World VM by resource ID (`dataDisks[].managedDisk.resourceId`), so the disk keeps its own lifecycle and zone.
- **Key Vault** (ADE only, the default): `avm/res/key-vault/vault` with the lab-friction override from docs/bicep-standards.md §4.5: soft delete forced on with 7-day retention, purge protection off, and `Remove-LabResource.ps1 -IncludeKeyVault` purges the vault after deleting it so the name is free immediately. Enabled for VM deployment and disk encryption, as Step 3.2.17 ticks them; not for template deployment.
- **ASGs**: the existing Lab 2.2 ASGs are referenced by ID in `ipConfigurations[].applicationSecurityGroups`, in dev only.
- **Deltas vs the hand-written templates**: the data disk now carries `networkAccessPolicy: DenyAll` / `publicNetworkAccess: Disabled` (AVM defaults; the lab never exports the disk), the OS disk sets `caching: 'ReadWrite'` explicitly (the AVM default is `ReadOnly`), and the NICs carry the canonical four tags only.
- **Zones**: `parAvailabilityZoneAuth` and `parAvailabilityZoneWorld` pin the Auth VM to zone 1 and the World VM plus its data disk to zone 2; `-1` is the documented escape hatch when Azure answers `ZonalAllocationFailed`.
