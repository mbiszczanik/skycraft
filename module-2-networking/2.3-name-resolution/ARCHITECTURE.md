# Architecture Notes: Lab 2.3 — Name Resolution

> Learning context. These notes explain the reasoning behind the lab's design and how it would change in a real environment. The lab deliberately favors clarity over production hardening.

## 1. Design decisions & trade-offs

| Decision | Choice in this lab | Alternatives considered | Why this choice (in a learning context) |
|---|---|---|---|
| **Public DNS zone name** | skycraft.example.com (placeholder, not registered) | Use a real registered domain; subdomain of student's own domain | Using a placeholder domain teaches DNS concepts without requiring domain registration. In production, use a real registered domain and delegate nameservers to Azure DNS. TODO(author): Should we provide a "bring your own domain" variant for advanced students? |
| **Private DNS zone name** | skycraft.internal (arbitrary RFC 1918 name) | Use environment-specific names (dev.internal, prod.internal); use TLD-style (.local, .corp) | Single shared zone teaches VNet Link concept: one zone can serve multiple VNets with auto-registration per VNet. Realistic for small deployments; large production splits zones per environment. |
| **DNS zone scope** | Private zone links all three VNets (hub + dev + prod); auto-registration only on spokes | Link hub separately with registration disabled, spokes with auto-registration enabled | This design (dns-private.bicep, lines 42–77) reflects reality: shared services (hub) are static; workloads (spokes) are dynamic. Only spokes auto-register VMs so DNS always has current IPs. |
| **DNS A records** | Placeholder A records (dev-db @ 10.1.3.10, prod-db @ 10.2.3.10) with TTL=300s | Automatic records via auto-registration; conditional forwarders to on-premises; round-robin CNAME | Placeholder records teach zone structure. Real databases get auto-registered once VMs exist. TTL=300s (5 min) balances freshness and query load; production tunes per workload SLA. |
| **Load Balancer SKU** | Standard SKU, Regional tier | Basic SKU (retired); Global tier | Standard LB is required for production (Basic deprecated ~2025). Regional tier is correct for single-region hub-spoke. Regional enables zone-redundancy if VMs are deployed across zones. |
| **LB health probe config** | TCP probes on game ports (3724 auth, 8085 world); 15s interval, 2 failed probes = down | HTTPS probes (require app HTTP endpoint); 30s interval; 3 failed probes | TCP probes are simple and don't require application endpoints. 15s interval (aggressive) detects failures quickly in lab. Production might use 30s+ to reduce false positives. Interval = probe sent every N seconds. numberOfProbes = how many failures before marking unhealthy. 15s × 2 = 30s to fail over; acceptable for game servers. |
| **LB rule load distribution** | Default (5-tuple hash: src IP, src port, dest IP, dest port, protocol) | SourceIP affinity (sticky sessions); SourceIPProtocol affinity (more aggressive stickiness) | Default hash distributes traffic fairly across backends. Sticky sessions help with game server state (player connections persist on one server). Lab uses default for simplicity; production would evaluate per-game requirements. |
| **Public DNS records** | Two A records (dev, play) pointing to LB IPs; one CNAME (game → play) | Wildcard entry (*); SRV records for service discovery; geodistribution (Traffic Manager) | Simple two-record setup teaches DNS fundamentals. Wildcard would catch misspellings. SRV records are advanced. Geodistribution requires Azure Traffic Manager (future). |
| **Backend pool strategy** | Empty pools at deployment time (VMs added in Module 3) | Pre-populate with NIC IDs; use VMSS instead of single VMs | Empty pools teach the concept: backend pools are *templates*. Module 3 adds actual VMs. VMSS would auto-scale but adds complexity. |

## 2. Lab simplifications vs production

| Aspect | What the lab does | What production would require | Why it matters |
|---|---|---|---|
| **DNS zone ownership** | Azure-hosted DNS zone in resource group | Nameserver delegation from domain registrar; zone apex delegation (@) | Lab's skycraft.example.com is *not* registered; it's a placeholder. Real production must register the domain and delegate NS records to Azure's nameservers (output from dns-public.bicep, line 77). Without delegation, external DNS queries won't resolve. |
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
- **Cost Optimization**: Standard LB is ~€20/mo + data processing. Private DNS is ~€0.40/mo. Game is free. Public DNS is ~€0.50/mo.

## 4. Cost / FinOps note

**Monthly cost (if left running):**
- 2 Standard Load Balancers (dev + prod): 2 × €20 = €40
- Data processing through LBs (~10 GB outbound): ~€1.50 (rough estimate; scales with traffic)
- 2 Standard Public IPs (LB frontend IPs, already counted in Lab 2.1): already included
- 1 Public DNS Zone (skycraft.example.com): ~€0.50
- 1 Private DNS Zone (skycraft.internal): ~€0.40
- Private DNS zone links (3 VNets × 2 zones): €0 (free)
- **Total: ~€42.40 / month** (additive to Lab 2.1)

**Lab cost controls:**
- LB is the big cost. If not actively learning LB, stop the deployment and delete.
- DNS zones are cheap (~€0.90/mo combined) and can stay.
- Public IPs stay (inherited from Lab 2.1; only bill if not disassociated).

**Cleanup reminders after lab:**
1. Delete Load Balancers if not testing in Module 3 (€20 each).
2. Delete Public DNS zone if not using it (€0.50/mo is negligible, but good practice).
3. Keep Private DNS zone: it's used for service discovery in Module 3+ (VMs will auto-register and query it).
4. Keep Private DNS zone links: they're free and enable resource discovery.
5. Verify no orphaned resources: check for unattached Public IPs (if LB was deleted but PIP remained).
