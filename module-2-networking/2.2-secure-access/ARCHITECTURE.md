# Architecture Notes: Lab 2.2 — Secure Access

> Learning context. These notes explain the reasoning behind the lab's design and how it would change in a real environment. The lab deliberately favors clarity over production hardening.

## 1. Design decisions & trade-offs

| Decision | Choice in this lab | Alternatives considered | Why this choice (in a learning context) |
|---|---|---|---|
| **NSG placement** | One NSG per subnet (Auth, World, DB) per spoke; no NSG on the hub subnets | One NSG shared by multiple subnets; NSGs on NICs only; centralized Azure Firewall | Per-subnet NSGs place traffic rules near each workload tier. The hub subnets are reserved for Bastion and a future gateway; this lab attaches no NSG to either (issue #345). |
| **ASG usage** | Define ASGs for Auth/World/DB tiers; *reserve* for future NIC membership | Skip ASGs; inline CIDR rules only | ASGs are "security groups" for logical grouping (like AWS Security Groups). Defining them now teaches the pattern: group *roles*, not IPs. In a real network, an Auth server can be added to the Auth ASG without touching rules. |
| **Bastion deployment** | Optional (parDeployBastion = false by default) | Mandatory deployment; separate lab | Bastion and its public IP incur hourly charges while they exist. The dated estimate is in guide Step 2.2.10. Default off avoids an unexpected deployment, and cleanup after use limits cost. |
| **Bastion SKU** | Basic SKU for Portal SSH/RDP | Standard or Premium for additional features; no Bastion | Basic provides the Portal connections used by the lab without public IPs on the VMs. Bastion itself uses a public IP. Choose additional features against actual requirements rather than an undated price difference. |
| **NSG rule specificity** | Bastion subnet hardcoded as 10.0.0.0/26 in spoke rules; explicit port numbers (22, 3724, 8085) | Wildcards (*) for source/dest; dynamic parameter lookups | Hardcoding Bastion subnet teaches best practice: minimize blast radius by being *explicit*. Explicit ports (SSH:22, Auth:3724, World:8085) document the game architecture. Ports 3724 (auth) and 8085 (world) are the default listen ports for World of Warcraft-compatible server cores, which SkyCraft's game tier emulates. |
| **Database security** | Explicit TCP 3306 allow from Auth + World subnets; default VNet allow retained | Explicit deny rules for isolation between tiers; database firewall controls | The custom rule documents the application path and does not allow internet MySQL. The default `AllowVnetInBound` still permits other internal traffic. Production tier isolation needs additional deny rules. |
| **Service endpoints** | Enabled on the Database subnet for Microsoft.Sql and Microsoft.Storage, and on the World subnet for Microsoft.Storage (Lab 4.4) | Private endpoints and private DNS for the PaaS services | Service endpoints route selected service traffic over the Azure backbone; the services still resolve to public IPs. Restricting a service to approved subnets requires its firewall settings. This lab configures the subnet endpoints and explains private endpoints conceptually. |
| **Outbound rules** | Not configured (default: allow all outbound) | Explicit allow-lists for egress | Lab skips egress rules for simplicity. Production uses egress NSGs to prevent data exfiltration. This is a major lab simplification. Explicit egress allow-lists are deliberately deferred to an advanced challenge so the core lab stays focused on inbound segmentation; the base lab keeps default allow-all outbound. |
| **AVM consumption** | `network-security-group`, `application-security-group`, `virtual-network/subnet` (NSG association + service endpoints) and `bastion-host` (creates its own Standard public IP), called directly from `main.bicep` | Hand-written resources in `security-spoke.bicep` / `security-hub.bicep` (pre-v2) | docs/bicep-standards.md §4. The subnet child module is the AVM way to attach an NSG to an existing subnet; the three subnet loops are chained with an explicit `dependsOn` because concurrent subnet updates on one VNet fail with `AnotherOperationInProgress` (§6.5: genuine sequencing, commented). The module takes service endpoints as plain service names and sets no `locations`, so Azure records them as region-unrestricted (`*`) — equivalent for Lab 4.4's same-region storage account. A subnet PUT replaces the whole subnet, so each module also restates what Lab 2.1 set: the address prefix and `privateEndpointNetworkPolicies: 'Disabled'` (unset, the subnet falls back to `Enabled`). A re-run therefore changes nothing on a spoke that already carries this lab's settings (issue #263). |
| **Loop over spokes** | A `varSpokes` array (dev, prod) drives every spoke-scoped module (`[for spoke in varSpokes: ...]`) | Two copies of every module; a local "spoke" wrapper module around the AVM calls | One declaration per concern keeps `main.bicep` readable and guarantees dev and prod stay identical; a wrapper module would re-introduce the local-module layer that v2 removes. |

## 2. Lab simplifications vs production

| Aspect | What the lab does | What production would require | Why it matters |
|---|---|---|---|
| **Bastion access control** | Single Bastion shared by all users | Conditional Access (Entra ID), Just-in-Time (JIT) access, per-user approval workflows, audit logs shipped to SIEM | Lab Bastion is wide-open once deployed. Real production must enforce *least privilege*: only authorized admins get sessions, and only for short time windows. |
| **Network policy enforcement** | Manual NSG rules per subnet | Azure Policy (built-in: "Deny all inbound, allow explicit") to prevent misconfiguration, automated remediation | Production is *policy-driven*: teams can't create an NSG without explicit inbound rules (or policy fails). Lab is *rule-driven*: humans write rules. |
| **Logging and monitoring** | NSG rules exist but no flow logs | NSG Flow Logs → Storage → Network Watcher for forensics, traffic analytics, anomaly detection, integration with Sentinel (SIEM) | Lab has no observability. In production, every denied packet is logged for auditing and incident response. |
| **Encryption in transit** | Game ports (3724, 8085) assumed encrypted by application | TLS/mTLS for all east-west traffic, Azure Private Link (redundant encryption layer) | Lab assumes app-level encryption. Production enforces transport encryption at the network layer. |
| **High availability** | Single Bastion (single AZ) | Redundant Bastions across zones, or alternative access (Private Endpoints to management services) | Single Bastion is a SPOF. Production spreads VMs across availability zones; Bastion should too. |
| **Blast radius** | NSG misconfiguration blocks a subnet for minutes; manual fix | Automated NSG rollback via Azure Policy or Bicep immutability, canary deployments (roll out rules to 10% of traffic first) | Lab is manual. Production must have fast recovery and validation gates. |
| **ASG utilization** | ASGs defined but not used (NICs not added until Module 3) | NICs added to ASGs immediately; rules reference ASGs not CIDRs; scale-out adds NICs to ASG, rules auto-apply | Lab preps ASGs; real usage is in Module 3. Production assigns every NIC to an ASG, so rules are dynamic and self-service. |

## 3. Well-Architected lens (light)

**Dominant pillar:**
- **Security**: NSGs, ASGs, Bastion form a classic three-layer defense (network perimeter, segmentation, access control).

**Key trade-off:** Ease of deployment vs. zero-trust architecture. Lab uses implicit trust within peered VNets; production adds encryption and identity.

- **Operational Excellence**: Bastion centralizes access; NSG per subnet is standard Azure ops pattern.
- **Reliability**: Verify successful provisioning and allow security-rule changes to propagate before testing connections.
- **Performance Efficiency**: There are no VMs yet, so the lab does not measure application or SSH latency.
- **Cost Optimization**: Create Bastion for the Portal SSH exercises in Lab 3.2 and delete it when those exercises finish. The default automation path leaves it off.

## 4. Cost / FinOps note

**Additional monthly fixed cost from Lab 2.2 (Sweden Central, 730 hours, retail rates checked 2026-10-24):**
- Basic Bastion: EUR 0.1672/hour, about EUR 122.06/month
- Bastion Standard static IPv4 public IP: EUR 0.0044/hour, about EUR 3.21/month
- NSGs (six, three per spoke; no hub NSG): no fixed charge
- ASGs (three, dev tiers): no fixed charge
- Service endpoint settings: no separate endpoint charge
- **Additional fixed cost with Bastion: about EUR 125.27/month**, plus applicable transfer charges
- **Additional fixed cost without Bastion (default): EUR 0/month**; Lab 2.1 IP and transfer charges continue

Rate sources: Azure Retail Prices API for [Basic Bastion](https://prices.azure.com/api/retail/prices?currencyCode=EUR&$filter=armRegionName%20eq%20%27swedencentral%27%20and%20serviceName%20eq%20%27Azure%20Bastion%27) and [Standard IPv4 public IPs](https://prices.azure.com/api/retail/prices?currencyCode=EUR&$filter=armRegionName%20eq%20%27swedencentral%27%20and%20meterName%20eq%20%27Standard%20IPv4%20Static%20Public%20IP%27). The combined Bastion and IP hourly rate is EUR 0.1716; these are optional temporary resources in the lab.

**Lab cost controls:**
- **Default: parDeployBastion = false** to avoid surprise costs. Enable only when teaching Bastion.
- Keep Bastion only for the exercises that use it and delete it afterwards.
- Lab 3.2 uses Bastion for Portal SSH to private VMs. If that lab runs later, delete Bastion now and recreate it when needed.

**Cleanup reminders after lab:**
1. **Delete Bastion and its public IP** when the exercises using it finish.
2. Keep NSGs: Labs 2.3 and Module 3 use them.
3. After the VM labs, inspect leftover disks, IPs and network interfaces, checking later-lab dependencies before deletion.
4. ASGs can stay (free); they'll be used in Module 3.
