# Architecture Notes: Lab 3.1 — Infrastructure as Code

> Learning context. These notes explain the reasoning behind the lab's design and how it would change in a real environment. The lab deliberately favors clarity over production hardening.

## 1. Design decisions & trade-offs

| Decision | Choice in this lab | Alternatives considered | Why this choice (in a learning context) |
|---|---|---|---|
| Region allowance | swedencentral, westeurope, northeurope | Single region only | Multiple regions teach multi-region awareness; students can experiment with failover regions without redeploying. |
| VNet sizing | /16 per environment (Hub 10.0.0.0/16, Dev 10.1.0.0/16, Prod 10.2.0.0/16) | Tightly sized /24 or /25 | Generous spacing keeps the lab uncluttered; students can add subnets without re-addressing. In production, you size based on actual VM forecasts and leave headroom for growth. |
| Subnet segmentation | Three /24 subnets per spoke (AuthSubnet, WorldSubnet, DatabaseSubnet) | Single flat subnet per VNet | Segmentation teaches network layering early; each subnet gets its own NSG, preventing uncontrolled lateral movement. |
| Hub VNet purpose | Bastion host only (AzureBastionSubnet /26) | Hub for shared services (DNS, routing, egress) | Simplified for a lab; production hubs hold firewall, DNS forwarders, and central egress inspection. |
| Load Balancer SKU | Standard, Regional tier | Basic LB (deprecated) | Standard is now the only supported option; teaches modern best practices. Regional tier prevents cross-region asymmetry. |
| NSG rules | Bastion SSH (from 10.0.0.0/26), service ports (3724 Auth, 8085 World from any source) | Restrict service ports to VNet only | Public inbound on game ports teaches port mapping; production closes these to VNet+known client ranges only. |

## 2. Lab simplifications vs production

| Aspect | What the lab does | What production would require | Why it matters |
|---|---|---|---|
| Network isolation | NSGs only, no firewall | Azure Firewall or NVA in hub | Stateless NSG rules cannot inspect encrypted traffic or enforce application-layer policies. Enterprise deployments centralize inspection. |
| DNS | Azure-provided default (internal only) | Private DNS Zones + conditional forwarder | Required for custom domain names (e.g., auth.skycraft.local) and cross-VNet name resolution. |
| VNet Peering | None shown; assumes manual setup | Hub-spoke with auto-peering via automation | The lab assumes Lab 3.1 creates RGs and networks; peering is typically automated or done in a separate orchestration step. |
| Public IP allocation | Static on Load Balancer | Static with auto-release / reserved addresses | Lab uses Static to keep the public IP stable during the lab. Production reserves public IPs to avoid IP exhaustion in shared subscriptions. |
| Tagging discipline | Common tags on all resources (Project, Service, CostCenter, ManagedBy, DeploymentDate) | Team/Owner, ApplicationId, DataClassification, Automation owner | Lab tags enable cost tracking and resource management; production adds fields for automation handoff and compliance auditing. |

## 3. Well-Architected lens (light)

- **Dominant pillar:** Operational Excellence (IaC-first, templated, repeatable)
- **Cost Management:** Generous sizing and static allocation teach students to resize later; production uses reserved instances or spot VMs.
- **Reliability:** Availability zones are prepared (zone selection in parameters) but NSGs/LB rules can block traffic if misconfigured; production adds health probes and network policies.
- **Security:** NSG-only defense is simple but flat; no encryption in transit on NSGs.
- **Performance:** Standard LB with TCP health checks covers basic needs; production adds HTTP path-based routing and connection draining.

## 4. Cost / FinOps note

**Monthly recurring cost (if left on, all resources 24/7)**:
- 1 Standard Load Balancer: ~€15/mo
- 1 Static Public IP: ~€3/mo
- 3 Resource Groups: free
- 3 Virtual Networks: free
- NSGs: free
- **Total**: ~€18/mo for networking foundation alone.

**Lab cost controls**:
- No VMs or compute in this lab, so minimal active costs.
- Public IP can be deallocated when not in use (frees the IP charge but reserves the name).

**Cleanup reminder after the lab**:
- Delete the Public IP (if deallocated, still incurs ~€3/mo reservation cost).
- Delete Load Balancer (frees ~€15/mo).
- Delete VNets (no storage cost but keeps the address space reserved).
- Leave Resource Groups empty or delete entirely.
