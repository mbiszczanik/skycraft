# Architecture Notes: Lab 2.2 — Secure Access

> Learning context. These notes explain the reasoning behind the lab's design and how it would change in a real environment. The lab deliberately favors clarity over production hardening.

## 1. Design decisions & trade-offs

| Decision | Choice in this lab | Alternatives considered | Why this choice (in a learning context) |
|---|---|---|---|
| **NSG placement** | One NSG per subnet (Auth, World, DB) per spoke; Hub NSG is empty at start | One NSG per VNet; NSGs on NICs only; centralized Azure Firewall | Per-subnet NSGs teach the fundamental pattern: firewall rules are *closest* to the protected resource. Empty hub NSG is intentional—it demonstrates that NSGs are allow-lists (default-deny). |
| **ASG usage** | Define ASGs for Auth/World/DB tiers; *reserve* for future NIC membership | Skip ASGs; inline CIDR rules only | ASGs are "security groups" for logical grouping (like AWS Security Groups). Defining them now teaches the pattern: group *roles*, not IPs. In a real network, an Auth server can be added to the Auth ASG without touching rules. |
| **Bastion deployment** | Optional (parDeployBastion = false by default) | Mandatory deployment; separate lab | Bastion adds ~€140/mo, so making it optional teaches cost discipline. Optional deployment is a realistic trade-off: some labs skip it to save budget. Default off avoids surprising learners with a big bill. |
| **Bastion SKU** | Basic SKU (cheaper, no native RDP/SSH file transfer) | Standard SKU (more features, higher cost); no Bastion | Basic SKU is sufficient for lab: students learn the core concept (eliminate public IPs). Real production might upgrade to Standard for auditing. Cost difference: ~€60/mo, worth teaching. |
| **NSG rule specificity** | Bastion subnet hardcoded as 10.0.0.0/26 in spoke rules; explicit port numbers (22, 3724, 8085) | Wildcards (*) for source/dest; dynamic parameter lookups | Hardcoding Bastion subnet teaches best practice: minimize blast radius by being *explicit*. Explicit ports (SSH:22, Auth:3724, World:8085) document the game architecture. Ports 3724 (auth) and 8085 (world) are the default listen ports for World of Warcraft-compatible server cores, which SkyCraft's game tier emulates. |
| **Database security** | MySQLPort 3306 only from Auth + World subnets (not from internet) | Allow from anywhere; firewalls in DB layer only | Layered security: NSG is *first* gate. A DB exposed to internet-inbound is a common breach. This rule teaches: databases are never public-facing. |
| **Service endpoints** | Enabled on DB subnet for Microsoft.Sql and Microsoft.Storage | No service endpoints; rely on private endpoints (Lab 2.2, line 244–256) | Service endpoints allow subnet-level access to PaaS without public IP. Cheaper than private endpoints (~€0 vs. ~€7.50/mo) but less isolated. Lab teaches both: endpoints are a good starting point. |
| **Outbound rules** | Not configured (default: allow all outbound) | Explicit allow-lists for egress | Lab skips egress rules for simplicity. Production uses egress NSGs to prevent data exfiltration. This is a major lab simplification. Explicit egress allow-lists are deliberately deferred to an advanced challenge so the core lab stays focused on inbound segmentation; the base lab keeps default allow-all outbound. |

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
- **Reliability**: NSG rule changes are immediate (no deployment delay); but single Bastion is a bottleneck.
- **Performance Efficiency**: NSGs add negligible latency (~<1 ms). Bastion adds ~100–200 ms round-trip for SSH. Acceptable for admin access, not for data plane.
- **Cost Optimization**: Bastion is the big cost lever; skipping it saves €140/mo but removes secure access (trade-off: students use VPN or accept the bill).

## 4. Cost / FinOps note

**Monthly cost (if Bastion enabled):**
- Azure Bastion (Basic SKU): ~€140/mo (largest cost)
- Bastion Public IP (Standard): €3.40/mo
- NSGs (3 Hub + 6 Spokes = 9 total): €0 (free)
- ASGs (6 total): €0 (free)
- **Total with Bastion: ~€143.40/mo**
- **Total without Bastion (default): ~€0/mo** (inherits Lab 2.1 costs)

**Lab cost controls:**
- **Default: parDeployBastion = false** to avoid surprise costs. Enable only when teaching Bastion.
- If Bastion is enabled, set deployment to 2–3 hours maximum and delete afterward (~€7–10 one-time cost).
- Delete Bastion immediately after learning; it's rarely needed for subsequent labs (VMs get public IPs in Module 3, or use private endpoints).

**Cleanup reminders after lab:**
1. **Delete Bastion and its Public IP** if enabled (€140/mo is expensive for learning).
2. Keep NSGs: Labs 2.3 and Module 3 use them.
3. Check for orphaned network interfaces: if any VMs were deleted (not yet in this lab), NICs may linger (cost ~€1–2/mo each).
4. ASGs can stay (free); they'll be used in Module 3.
