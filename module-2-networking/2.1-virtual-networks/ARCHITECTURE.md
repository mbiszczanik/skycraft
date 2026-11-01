# Architecture Notes: Lab 2.1 — Virtual Networks

> Learning context. These notes explain the reasoning behind the lab's design and how it would change in a real environment. The lab deliberately favors clarity over production hardening.

## 1. Design decisions & trade-offs

| Decision | Choice in this lab | Alternatives considered | Why this choice (in a learning context) |
|---|---|---|---|
| **Hub-Spoke topology** | Three VNets: 1 hub + 2 spokes; spoke-to-spoke *not* directly peered | Flat single VNet; full mesh peering; hub-and-branch (multiple hubs) | Each spoke can reach the hub. Peering is non-transitive, so dev and prod have no route to one another in this lab. Transit would need additional routing and a forwarding appliance. |
| **Address space sizing** | Generous `/16` per VNet (65,536 IPs each) with `/24` subnets (256 IPs) | Tightly-sized `/27` (32 IPs) or `/28` subnets; classless allocation | Generous spacing keeps the lab simple and readable; real production sizing requires careful capacity planning and reserves growth headroom per RFC 1918 strategy. This teaches the principle: always over-allocate in labs to avoid re-addressing. |
| **Subnet granularity** | Hub: 2 subnets (Bastion + Gateway); Spokes: 4 subnets each (Auth, World, DB, AppService) | Single flat subnet per VNet | Subnet segmentation enables NSG rules per workload tier and teaches Azure's fundamental isolation pattern. Demonstrates that subnets are *free*—use them liberally. |
| **Public IP (Standard SKU)** | Static Public IP (Standard) for future Load Balancers | Non-zonal or single-zone Standard IP | Standard SKU matches the Standard load balancers in Lab 2.3. Zone-redundant IPs keep the three deployment paths consistent. The dated cost estimate is in Section 4. |
| **Peering configuration** | Bidirectional peering (hub←→dev, hub←→prod); both directions allow *forwarded traffic* | Unidirectional peering; gateway transit disabled | `allowForwardedTraffic: true` on every peering (`modPeering` over `varPeerings` in main.bicep) prepares for a future central inspection design. That design still needs routes and a forwarding appliance; the flag creates neither. Gateway transit is disabled because no ExpressRoute/VPN gateway is deployed. |
| **Region selection** | Sweden Central (swedencentral) | West Europe, East US, other regions | Sweden Central is arbitrary but consistent across all labs (SPECIFICATION.md). In production, region depends on data residency, latency to users, and feature availability. |
| **AVM consumption** | `avm/res/network/virtual-network` (new VNets with their subnets), its `subnet` and `virtual-network-peering` child modules (subnets missing from an existing VNet, and the four peerings), and `avm/res/network/public-ip-address`, called directly from `main.bicep` | Hand-written `Microsoft.Network/*` resources in local modules (pre-v2); the VNet module's own `peerings` parameter | Consuming Azure Verified Modules is what production teams do (docs/bicep-standards.md §4). The peerings are deployed as child resources, declared once in `varPeerings`, rather than through the VNet module, because that would mean redeploying the VNet - and a VNet deployment removes the peerings it does not list (issue #188). |
| **Public IP zones** | Zone-redundant (AVM default `availabilityZones: [1, 2, 3]`); the Bastion public IP created in Lab 2.2 follows the same default. An existing load balancer public IP is left untouched on a re-run | Non-zonal (pre-v2 raw resource); single zone | Matches the portal default for Standard SKU and the zone-redundancy story of the Standard Load Balancer in Lab 2.3, at the same price. Zones cannot change after creation, so a re-run over a non-zonal IP made in the portal or by `Deploy-Networking.ps1` would fail; `Deploy-Bicep.ps1` looks the IPs up and the template creates only the missing ones. |

## 2. Lab simplifications vs production

| Aspect | What the lab does | What production would require | Why it matters |
|---|---|---|---|
| **Network segmentation** | Three static VNets (Platform, Dev, Prod) with fixed CIDR ranges | Address management across regions, additional network inspection and private connectivity | The lab uses non-overlapping ranges. Production address plans account for growth and connections to other networks. Forced tunneling alone does not resolve overlapping address spaces. |
| **Peering scope** | Manual peering between named VNets | Automated peering via policies (Azure Policy or Terraform modules), spoke transit via a hub firewall and user-defined routes, automatic route propagation | Manual peering in the lab is transparent for learning. Peering itself is non-transitive. Production automates peering and any additional transit configuration with Infrastructure-as-Code (IaC) to avoid human error. |
| **DNS resolution** | Azure-provided default (168.63.169.254) | Custom Private DNS Zones (Lab 2.3) + VNet links, private resolvers for hybrid DNS, conditional forwarding to on-premises | Azure's default DNS works for internal Azure resources but lacks flexibility. Lab 2.3 introduces Private DNS. Production adds resolvers for hybrid scenarios. |
| **Gateway subnet** | Reserved (10.0.1.0/27) but unused in this lab | ExpressRoute Gateway or VPN Gateway deployed here in future labs | Gateway subnet is *reserved* per Azure design best practice, even if not used immediately. This teaches planning: always leave room for connectivity later. |
| **Subnet ownership** | Lab 2.1 creates every subnet; Lab 2.2 re-declares Auth/World/Database with their NSGs and service endpoints. A re-run of Lab 2.1 does not redeploy a VNet that exists and adds only the subnets it lacks | One template per network, layered through parameters, so a single source of truth owns each subnet | A VNet deployment removes the peerings it does not list, and replaces each subnet it does list with exactly what it declares - that would drop the peerings, detach Lab 2.2's NSGs and service endpoints (Lab 4.4 relies on the latter) and rename an App Service delegation the portal named `delegation`. `Deploy-Bicep.ps1` therefore looks the VNets and subnets up (`parHubVnetExists`, `parDevVnetExists`, `parProdVnetExists`, `parExistingSubnets`); missing VNets and subnets and all four peerings are deployed, so a re-run can add the dev spoke next to an existing hub and prod (issue #188). The price: a re-run does not repair a setting on a VNet or subnet that already exists. Production keeps one template per network so this drift cannot happen. |
| **Monitoring / logging** | Network Watcher and its topology view; no flow logging or packet capture | Virtual network flow logs, metrics, packet capture and diagnostic settings | Step 2.1.14 uses Network Watcher to inspect the topology. Module 5 covers further network monitoring. New [NSG flow logs are no longer supported](https://learn.microsoft.com/azure/network-watcher/nsg-flow-logs-migrate); use virtual network flow logs for new configurations. |
| **Cost optimization** | Keep the networks and IPs for Labs 2.2 and 2.3 | Resource ownership, cost allocation, budget alerts and cleanup of unused resources | Two public IPs add about EUR 6.42/month at the dated rate in Section 4. Peering data transfer adds usage charges. |

## 3. Well-Architected lens (light)

**Dominant pillars:**
- **Operational Excellence**: The hub reserves a shared-services location. Lab 2.2 introduces Bastion; no firewall is deployed by this lab.
- **Security**: Subnet segmentation and peering isolation reduce blast radius of a compromised spoke.

**Key trade-off:** The lab demonstrates network layout and peering. It reserves GatewaySubnet but deploys no gateway, firewall, Bastion host or workload VM.

- **Reliability**: All three networks are in one region. This lab implements no workload failover.
- **Performance Efficiency**: Peering provides direct connectivity between each spoke and the hub. There are no VMs yet, so this lab does not measure application latency.
- **Cost Optimization**: VNets have no fixed charge. Public IPs incur hourly charges, and peering traffic incurs data-transfer charges.

## 4. Cost / FinOps note

**Monthly fixed cost (Sweden Central, 730 hours, retail rates checked 2026-10-24):**
- 3 VNets: EUR 0 fixed charge
- 2 Standard IPv4 public IPs: EUR 0.0044/hour each, about EUR 3.21/month each
- VNet peering (4 links): no fixed charge; traffic is billed per GB
- **Total fixed cost: about EUR 6.42/month**, plus peering and other applicable transfer charges

Public IP rate: [Azure Retail Prices API](https://prices.azure.com/api/retail/prices?currencyCode=EUR&$filter=armRegionName%20eq%20%27swedencentral%27%20and%20meterName%20eq%20%27Standard%20IPv4%20Static%20Public%20IP%27).

**Lab cost controls:**
- Turn off VMs when not in use (Module 3).
- Delete unused Public IPs immediately; they are billed even when disassociated from resources.
- Peering has no inactivity penalty.

**Cleanup reminders after lab:**
1. Delete Public IPs if not using Load Balancer (Lab 2.3).
2. Leave VNets in place because Labs 2.2 and 2.3 depend on them.
3. After the VM labs, inspect leftover disks, IPs and network interfaces before cleanup. Delete only resources no later lab needs.
