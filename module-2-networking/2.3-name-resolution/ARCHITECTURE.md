# Architecture Notes: Lab 2.3 : Name Resolution

> Learning context. These notes explain the reasoning behind the lab's design and how it would change in a real environment. The lab deliberately favors clarity over production hardening.

## 1. Design decisions & trade-offs

| Decision | Choice in this lab | Alternatives considered | Why this choice (in a learning context) |
|---|---|---|---|
| **Public DNS zone name** | skycraft.example.com (placeholder, not registered) | Use a real registered domain; subdomain of student's own domain | Using a placeholder domain teaches DNS concepts without requiring domain registration. In production, use a real registered domain and delegate nameservers to Azure DNS. A "bring your own domain" path is offered as an optional advanced variant: students who own a domain can delegate the Azure DNS nameservers and validate real external resolution end to end. |
| **Private DNS zone name** | skycraft.internal (private DNS namespace) | Use environment-specific names (dev.internal, prod.internal); use TLD-style (.local, .corp) | Single shared zone teaches VNet Link concept: one zone can serve multiple VNets with auto-registration per VNet. Realistic for small deployments; large production splits zones per environment. |
| **DNS zone scope** | Private zone links all three VNets (hub + dev + prod); auto-registration only on spokes | Link hub separately with registration disabled, spokes with auto-registration enabled | This design (the private-dns-zone module's `virtualNetworkLinks` in main.bicep) reflects reality: shared services (hub) are static; workloads (spokes) are dynamic. Only spokes auto-register VMs so DNS always has current IPs. |
| **DNS A records** | Placeholder A records (dev-db @ 10.1.3.10, prod-db @ 10.2.3.10) with TTL=300s | Automatic records via auto-registration; conditional forwarders to on-premises; round-robin CNAME | Placeholder records teach zone structure. Real databases get auto-registered once VMs exist. TTL=300s (5 min) balances freshness and query load; production tunes per workload SLA. |
| **Load Balancer SKU** | Standard SKU, Regional tier | Basic SKU (retired); Global tier | Basic Load Balancer retired on September 30, 2025. Regional tier is correct for single-region hub-spoke. Regional enables zone-redundancy if VMs are deployed across zones. |
| **LB health probe config** | TCP probes on game ports (3724 auth, 8085 world); 15s interval, probeThreshold 1 | HTTPS probes (require app HTTP endpoint); longer intervals or higher thresholds | The threshold matches the Portal and AVM 0.8.0 defaults. One consecutive failure or success changes backend health. The legacy numberOfProbes field stays 2, as in AVM; it is separate from probeThreshold. |
| **LB rule load distribution** | Default (5-tuple hash: src IP, src port, dest IP, dest port, protocol) | SourceIP affinity (sticky sessions); SourceIPProtocol affinity (more aggressive stickiness) | Default hash distributes traffic fairly across backends. Sticky sessions help with game server state (player connections persist on one server). Lab uses default for simplicity; production would evaluate per-game requirements. |
| **Public DNS records** | Two A records (dev, play) pointing to LB IPs; one CNAME (game → play) | Wildcard entry (*); SRV records for service discovery; geodistribution (Traffic Manager) | Simple two-record setup teaches DNS fundamentals. Wildcard would catch misspellings. SRV records are advanced. Geodistribution requires Azure Traffic Manager (future). |
| **Backend pool strategy** | Empty pools at deployment time (VMs added in Module 3) | Pre-populate with NIC IDs; use VMSS instead of single VMs | Empty pools teach the concept: backend pools are *templates*. Module 3 adds actual VMs. VMSS would auto-scale but adds complexity. |
| **AVM consumption** | `load-balancer`, `dns-zone` (records via `a` / `cname`) and `private-dns-zone` (`virtualNetworkLinks`, `a`), called directly from `main.bicep`; the public-IP address lookup stays a local `existing` module, the LB frontends reference the PIPs through `existing` lookups scoped to the spoke resource groups | Hand-written resources in `load-balancer.bicep`, `dns-public.bicep`, `dns-private.bicep` (pre-v2) | docs/bicep-standards.md §4; `modules/get-public-ip.bicep` is kept as the documented trivial-lookup fallback example (§4.3); the IPs themselves are owned by Lab 2.1. |
| **Outbound connectivity** | One outbound rule per load balancer, `<lb>-outbound` (frontend `<lb>-frontend`, protocol All, idle timeout 4 min, TCP reset on, manual allocation of 8000 ports per instance), for a dedicated egress pool `<lb>-be-outbound` that Lab 3.2 puts every VM NIC into; the load-balancing rules keep `disableOutboundSnat: true` | One outbound rule per role pool (refused by Azure: a frontend IP takes one outbound rule with an overlapping protocol); default port allocation on the load-balancing rules (`disableOutboundSnat: false`, which Azure refuses once an outbound rule uses the frontend); a NAT gateway on the subnets; a public IP per VM | The Lab 2.1 subnets are private (no default outbound access), so the outbound rule is the Module 3 VMs' only egress. Outbound rules are part of configuring a public Standard load balancer in AZ-104; Microsoft Learn does not recommend default port allocation, and a NAT gateway is outside the AZ-104 outline. 8000 ports per instance: the frontend offers 63,984, so the egress pool admits 7 instances; Module 3 puts 2 VMs there (the Lab 3.2 scale set, up to 4, in dev, would also fit). Production with more instances would add frontend IPs or use a NAT gateway (docs/bicep-standards.md §4.5). |
| **Environment tags** | DNS zones `Platform`, dev load balancer `Development`, prod load balancer `Production` | One blanket `Production` tag for every Lab 2.3 resource (pre-v2) | The lab checklist always expected per-environment tags; the blanket value was drift and would have made cost-by-environment reports wrong. |

## 2. Lab simplifications vs production

| Aspect | What the lab does | What production would require | Why it matters |
|---|---|---|---|
| **DNS zone ownership** | Azure-hosted DNS zone in resource group | Nameserver delegation from domain registrar; zone apex delegation (@) | Lab's skycraft.example.com is *not* registered; it's a placeholder. Real production must register the domain and delegate NS records to Azure's nameservers (the `outPublicDnsNameServers` output of main.bicep). Without delegation, external DNS queries won't resolve. |
| **Private DNS auto-registration** | VNet links configured, but no VMs exist yet to auto-register | VMs auto-register via DHCP; DNS is immediately available to other resources | Lab configures the *capability* (auto-registration enabled on dev/prod links). Real usage appears in Module 3. Shows how DNS scales: add a VM, it self-registers, no manual DNS entry needed. |
| **LB backend capacity** | No backends deployed (empty pools, ready for VMs) | Load Balancer deployed with Autoscale (VMSS) or pre-warmed VMs; health probes actively monitor | Lab leaves backends empty. Production deploys at least 2 backends per pool for HA; health probes detect and skip unhealthy backends in real-time. |
| **Health probe verification** | Probes are configured but VMs don't exist to respond | Probes fail immediately (all backends marked unhealthy); LB marks pools as "down"; monitoring alerts fire | Lab's health probes exist but have nothing to probe. In Module 3, when VMs are added, probes will fail until game servers listen on ports 3724/8085. This teaches: if health probes fail, traffic doesn't route. |
| **Geographic distribution** | Single region (Sweden Central) | Multi-region with Traffic Manager (failover to another Azure region or on-premises) | Lab is single-region. Global SkyCraft would use Traffic Manager to distribute game traffic across regions (e.g., EU vs. NA). |
| **SSL/TLS termination** | No HTTPS configured on LB | Application Gateway (Layer 7) with SSL certificates, end-to-end encryption, WAF rules | Lab uses TCP Layer 4 load balancing. Production game servers would use HTTPS for account pages and TLS for game data. LB can't terminate HTTPS at Layer 4; would need Application Gateway. |
| **DNS query logging** | No observability on DNS queries | Azure Diagnostics → Log Analytics, DNS query analytics, anomaly detection | Lab has no DNS observability. Production logs every query to detect suspicious patterns (e.g., DNS exfiltration) and validate auto-registration is working. |
| **TTL strategy** | Fixed TTL=300s for A records | Dynamic TTL based on backend health (fast fail-over) or query source (internal vs. external) | Lab's fixed TTL is simple. Production might use lower TTL (60s) on internal DNS for faster updates, higher TTL (3600s) on public DNS to reduce query load. |
| **LB persistence** | No session affinity (default hash) | Stateful backends with session replication or distributed cache (Redis) | Game servers are stateful (player session). Default hash tries to keep same player on same server, but *imperfect* (can hash to different server on port change). Real game servers would replicate state or use shared DB (covered in Module 4). |

## 3. Well-Architected lens (light)

**Dominant pillar:**
- **Reliability**: Load Balancer distributes traffic and detects failures; Public DNS and Private DNS provide redundant name resolution across regions (potential).
- **Performance Efficiency**: Standard LB tier enforces zone-redundancy awareness; health probes route traffic only to healthy backends.

**Key trade-off:** Simplicity vs. resilience. Lab uses single LB per region (no active-active failover), and placeholder DNS records (not real domain).

- **Operational Excellence**: LB centralizes traffic ingestion; Private DNS simplifies internal service discovery.
- **Security**: Private DNS hides internal topology from external queries; health probes validate only responding backends get traffic.
- **Cost Optimization**: both DNS zones and both load balancers continue to accrue charges. The estimate below separates fixed references from usage.

## 4. Cost / FinOps note

**Retail lookup: 2026-10-23, EUR, 730 hours/month.**

| Resource | Monthly fixed cost or reference | Usage |
| --- | --- | --- |
| Public DNS zone | EUR 0.44, Global first-25-zone tier | EUR 0.352/million queries at the base tier |
| Private DNS zone | EUR 0.44, Global first-25-zone tier | EUR 0.352/million queries at the base tier |
| Three private-zone VNet links | No separate fixed meter found | Zone/query meters above |
| Two Standard Load Balancers | Sweden Central price unknown; Global reference EUR 16.06 each | Global reference EUR 0.0044/GB processed; extra rules can add rule-hours |
| Two inherited Standard IPv4 public IPs | EUR 6.424 combined, already counted in Lab 2.1 | Charged while attached or unattached |

The two zones add EUR 0.88/month. Both LBs add a Global fixed-cost reference of EUR 32.12/month for their first five rules each (the lab uses three each). Lab 2.3's fixed-cost reference increment is EUR 33.00/month. Including the inherited IPs gives EUR 39.424/month for Module 2 excluding optional Bastion, plus usage. The confirmed regional total remains unknown because no Sweden Central-specific LB meter was returned. The links are three links to one zone, not links to both zones.

Sources: [DNS pricing](https://azure.microsoft.com/pricing/details/dns/), [Load Balancer pricing](https://azure.microsoft.com/pricing/details/load-balancer/), and the Azure Retail Prices API. The LB Global meter is a reference, not a confirmed Sweden Central quote. Record-set overages do not apply at lab volume.

**Lab cost controls:**

- Keep the load balancers and private DNS zone when continuing to Module 3.
- Remove the Lab 2.3 resources through its cleanup script when finished; nested pools, probes and rules are removed with each LB.
- Removing an LB retains its public IP and its hourly charge. Lab 2.1's cleanup removes those IPs.
- Remove private-zone links before deleting the private zone.
