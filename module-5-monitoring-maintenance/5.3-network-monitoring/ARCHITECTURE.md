# Architecture Notes: Lab 5.3 — Network Monitoring & Diagnostics

> Learning context. These notes explain the reasoning behind the lab's design and how it would change in a real environment. The lab deliberately favors clarity over production hardening.

## 1. Design decisions & trade-offs

| Decision | Choice in this lab | Alternatives considered | Why this choice (in a learning context) |
|---|---|---|---|
| Flow Log type | Virtual Network Flow Log (v2, JSON) | NSG Flow Logs (v1), deprecated after June 2025 | VNet Flow Logs capture all IP traffic at the network interface layer and are the modern standard; NSG Flow Logs are deprecated and will be unsupported after June 2025, so the lab teaches the future-proof approach. |
| Flow Log version | Version 2 (v2) | Version 1 (v1, legacy) | v2 includes additional fields (TCP flags, flow state: OK/Denied) that enable deeper troubleshooting; v1 is simpler but loses diagnostic value. Teaching v2 aligns with current Azure best practices. |
| Flow Log retention | 7 days | 30, 90, 365 days or indefinite | 7 days is enough for a typical troubleshooting window (DNS issues, intermittent connectivity); longer retention multiplies storage cost (€0.10/GB for Hot, €0.03/GB for Warm) without benefit in a learning lab. |
| Traffic Analytics interval | 10 minutes | 1, 60 minutes | 10 minutes provides a reasonable refresh rate for analyzing traffic patterns without excessive aggregation; 1-minute is too noisy, 60-minute loses temporal resolution. |
| Traffic Analytics destination | Log Analytics Workspace (centralized) | Storage account only (cheaper, logs-only) | Routing to a workspace enables rich KQL queries and integration with other telemetry (metrics, diagnostic logs); storage-only is cheaper but requires separate parsing tools. Lab emphasizes integrated monitoring. |
| Connection Monitor protocol | TCP/22 (SSH) | ICMP ping, HTTP, custom TCP | SSH is relevant to the lab topology (Auth Server connectivity between hub and spoke) and demonstrates TCP layer health checks; ICMP may be blocked by NSGs in production so TCP is more realistic. |
| Connection Monitor frequency | Every 5 minutes | Every 1, 30 seconds | 5 minutes balances prompt detection of outages (~5 min alert latency) with cost of test traffic; every 30 seconds would double the test load. |
| Flow Log storage format | JSON in blob storage | CSV (legacy), Parquet (newer) | JSON is human-readable and widely supported by analytics tools; Parquet is more efficient for large-scale batch analytics but adds tooling complexity. |

## 2. Lab simplifications vs production

| Aspect | What the lab does | What production would require | Why it matters |
|---|---|---|---|
| Flow log scope | Single VNet (production) | Multiple VNets + NSGs + subnets with variable retention per scope | Lab captures one VNet's traffic; production segments by security boundary (e.g., high-sensitivity subnets retain 90 days, general retain 30 days) and enforces retention policies per NSG to meet compliance. |
| Traffic Analytics cost | ~€2/GB analyzed (combined flow log + analytics cost) | Aggregated across 100s of VNets; per-VNet cost can exceed €500/month | Lab cost is modest (~€5–10/month for 5–10 GB of logs); production carefully budgets TA and sometimes disables it for non-critical VNets or uses sampling. |
| Connection Monitor endpoints | 1 source (prod VM), 1 destination (dev VM) | Mesh of 20+ endpoints across regions & datacenters with custom thresholds per path | Lab tests a single critical path (hub-spoke SSH); production creates multi-endpoint meshes to catch cross-region latency, asymmetric routing, and datacenter availability issues. |
| Connection Monitor actions | Output to Log Analytics (queryable) | Output to Action Group, ITSM ticketing, auto-remediation runbooks | Lab logs results; production integrates failed probes into incident response (PagerDuty, ServiceNow, Auto-Scale). |
| Flow log storage redundancy | LRS in a single storage account | RA-GRS or immutable blob snapshots for compliance archives | Lab trades redundancy for cost; production requires cross-region replication so that storage region failure does not block access to forensic logs. |
| Flow log ingestion latency | ~10 minutes to Log Analytics | Real-time ingestion for incident response, or batch for compliance analytics | Traffic Analytics aggregates at 10-minute intervals; production may stream to event hubs for real-time threat detection (ransomware, DDoS) or batch to cold storage for compliance audits. |

## 3. Well-Architected lens (light)

- **Dominant pillar:** Operational Excellence & Reliability
  - Network monitoring is critical to diagnosing connectivity failures, latency, and packet loss; teaches structured network troubleshooting.
- **Security:** Flow logs provide forensic audit trail for intrusion detection, policy violations, and compliance audits.
  - Immutable storage and longer retention (30–90 days) required in production for compliance (PCI-DSS, HIPAA).
- **Cost:** VNet Flow Logs are free; Traffic Analytics cost ~€2/GB analyzed (significant at scale). Lab limits scope to one VNet.
- **Performance:** Connection Monitor probes every 5 minutes; tight thresholds (10% failure rate, 100 ms RTT) ensure quick detection of user-impacting issues.

## 4. Cost / FinOps note

- **Monthly cost estimate:**
  - VNet Flow Logs (captured, stored): Free for the log capture; storage in blob account ~€0.08/GB (Hot tier, 7-day retention). A single VNet with 2 VMs generating 10 GB/week = ~€3/month storage.
  - Traffic Analytics: ~€2/GB analyzed. Same 10 GB/week = ~€8/month.
  - Connection Monitor: Free (first 100 test endpoints), then €0.10 per endpoint per day. Lab uses 2 endpoints = free tier.
  - **Total for lab:** ~€11/month.
- **Reduction tactics:**
  - Reduce retention from 30 to 7 days (saves 75% storage cost).
  - Use sampling or target only critical VNets for Traffic Analytics (if monitoring many VNets, disable TA on non-critical ones).
  - Connection Monitor: Increase probe frequency from 5 minutes to 30 minutes to reduce test traffic and alert noise.
  - Delete or disable Flow Logs on VNets after lab (free to disable, but logs continue to accumulate in storage until manually purged).
- **Cleanup reminder:**
  - **Flow Logs persist in the storage account even after the lab RG is deleted.** The NetworkWatcherRG is automatically provisioned by Azure and may outlive manual RG cleanup.
  - Delete the VNet Flow Log resource explicitly to stop new logs from being written.
  - Flow logs already in the storage account blob container must be manually deleted or moved to archive tier to avoid ongoing Hot tier charges.
  - Traffic Analytics data in Log Analytics Workspace (Lab 5.1) will continue to accumulate; delete the Flow Log source to stop analytics ingestion, then purge old data from the workspace.
  - If Connection Monitor is left running, it will continue to probe the network indefinitely, potentially triggering alerts in production-like systems; disable or delete the Connection Monitor resource immediately after troubleshooting.
