# Architecture Notes: Lab 2.1 — Virtual Networks

> Learning context. These notes explain the reasoning behind the lab's design and how it would change in a real environment. The lab deliberately favors clarity over production hardening.

## 1. Design decisions & trade-offs

| Decision | Choice in this lab | Alternatives considered | Why this choice (in a learning context) |
|---|---|---|---|
| **Hub-Spoke topology** | Three VNets: 1 hub + 2 spokes; spoke-to-spoke *not* directly peered | Flat single VNet; full mesh peering; hub-and-branch (multiple hubs) | Hub-spoke scales well, teaches centralized routing model, and prevents accidental spoke-to-spoke shortcuts. No spoke-to-spoke peering forces traffic through hub, demonstrating how real enterprises control north-south traffic flows. |
| **Address space sizing** | Generous `/16` per VNet (65,536 IPs each) with `/24` subnets (256 IPs) | Tightly-sized `/27` (32 IPs) or `/28` subnets; classless allocation | Generous spacing keeps the lab simple and readable; real production sizing requires careful capacity planning and reserves growth headroom per RFC 1918 strategy. This teaches the principle: always over-allocate in labs to avoid re-addressing. |
| **Subnet granularity** | Hub: 2 subnets (Bastion + Gateway); Spokes: 4 subnets each (Auth, World, DB, AppService) | Single flat subnet per VNet | Subnet segmentation enables NSG rules per workload tier and teaches Azure's fundamental isolation pattern. Demonstrates that subnets are *free*—use them liberally. |
| **Public IP (Standard SKU)** | Static Public IP (Standard) for future Load Balancers | Basic SKU (deprecated); Elastic IP analogue | Standard SKU is required for Standard LB (Lab 2.3) and enforces availability zone redundancy awareness. Also teaches that Standard PIP billing (~€3.40/mo) is negligible vs. security benefit. |
| **Peering configuration** | Bidirectional peering (hub←→dev, hub←→prod); both directions allow *forwarded traffic* | Unidirectional peering; gateway transit disabled | Bidirectional peering with forwarded traffic allows hub to become future firewall/routing hub. `allowForwardedTraffic: true` (lab-guide-2.1.md, lines 42–43) shows the intent: central inspection is the *future state*. Gateway transit disabled because no ExpressRoute/VPN is deployed yet. |
| **Region selection** | Sweden Central (swedencentral) | West Europe, East US, other regions | Sweden Central is arbitrary but consistent across all labs (CLAUDE.local.md, SPECIFICATION.md). In production, region depends on data residency, latency to users, and feature availability. |

## 2. Lab simplifications vs production

| Aspect | What the lab does | What production would require | Why it matters |
|---|---|---|---|
| **Network segmentation** | Three static VNets (Platform, Dev, Prod) with fixed CIDR ranges | Dynamic VNet creation, overlapping CIDR ranges via NAT, multi-region replication, private endpoints for all PaaS, Azure Firewall in hub | Production must handle growth: new regions, new business units, overlapping CIDR (via forced tunneling). The lab's fixed sizing teaches the principle: IP space is a precious, finite resource. |
| **Peering scope** | Manual peering between named VNets | Automated peering via policies (Azure Policy or Terraform modules), transitive peering via hub firewall rules, automatic route propagation | Manual peering in the lab is transparent for learning. Production automates this with Infrastructure-as-Code (IaC) to avoid human error and enable GitOps compliance. |
| **DNS resolution** | Azure-provided default (168.63.169.254) | Custom Private DNS Zones (Lab 2.3) + VNet links, private resolvers for hybrid DNS, conditional forwarding to on-premises | Azure's default DNS works for internal Azure resources but lacks flexibility. Lab 2.3 introduces Private DNS. Production adds resolvers for hybrid scenarios. |
| **Gateway subnet** | Reserved (10.0.1.0/27) but unused in this lab | ExpressRoute Gateway or VPN Gateway deployed here in future labs | Gateway subnet is *reserved* per Azure design best practice, even if not used immediately. This teaches planning: always leave room for connectivity later. |
| **Monitoring / logging** | Not included in this lab | Network Watcher, NSG flow logs, VNet peering metrics, Packet Capture, Diagnostics | The lab is observability-free. Production requires observability to detect link flaps, asymmetric routes, and DDoS attacks. Covered in Module 5. |
| **Cost optimization** | Resources left running continuously | Auto-shutdown, dev/test subscriptions for spare environments, resource groups for cost allocation, budget alerts | Lab resources incur ~€2–4/mo (3 VNets + 2 PIPs, peering is free). Production maps cost to business units and enforces cleanup. |

## 3. Well-Architected lens (light)

**Dominant pillars:**
- **Operational Excellence**: The hub-spoke topology centralizes administration (single Bastion, single firewall location).
- **Security**: Subnet segmentation and peering isolation reduce blast radius of a compromised spoke.

**Key trade-off:** Clarity vs. complexity. The lab sacrifices auto-failover and redundancy (single gateway per region) for simplicity.

- **Reliability**: Hub-spoke is resilient *within* a region (no SPOF if Bastion/gateway are HA-deployed); no multi-region failover.
- **Performance Efficiency**: Three `/16` VNets incur peering latency (~1–5 ms within region); acceptable for learning but monitored in production (Network Watcher).
- **Cost Optimization**: Peering is free. VNets themselves are free. The only cost: Public IPs (~€3.40/mo each, only 2 in Lab 2.1) and data transferred out of Azure.

## 4. Cost / FinOps note

**Monthly cost (if left running):**
- 3 VNets: €0 (free resource)
- 2 Standard Public IPs: 2 × €3.40 = €6.80
- VNet peering (4 links): €0 (free)
- **Total: ~€6.80 / month**

**Lab cost controls:**
- Turn off VMs when not in use (Module 3).
- Delete unused Public IPs immediately; they are billed even when disassociated from resources.
- Peering has no inactivity penalty.

**Cleanup reminders after lab:**
1. Delete Public IPs if not using Load Balancer (Lab 2.3).
2. Leave VNets in place—Labs 2.2 and 2.3 depend on them.
3. Monitor for orphaned resources: check for unattached NICs (created during VM teardown, cost ~€1–2 if left dangling).
