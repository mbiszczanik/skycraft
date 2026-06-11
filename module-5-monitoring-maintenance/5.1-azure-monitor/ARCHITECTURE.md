# Architecture Notes: Lab 5.1 — Azure Monitor

> Learning context. These notes explain the reasoning behind the lab's design and how it would change in a real environment. The lab deliberately favors clarity over production hardening.

## 1. Design decisions & trade-offs

| Decision | Choice in this lab | Alternatives considered | Why this choice (in a learning context) |
|---|---|---|---|
| Log Analytics SKU | PerGB2018 | Pay-as-you-go (Standalone) | PerGB2018 remains available and is cost-effective for small labs; students learn the modern ingestion model that charges per GB of data sent rather than reserved capacity. |
| Data retention | 30 days | 90, 365 days or indefinite | 30 days balances learning (enough data to analyze trends) with cost control; extended retention can quickly become expensive (€0.50+ per GB per month) and is unnecessary for lab exercises. |
| DCR data sources | VM Insights perfcounters + syslog | Application Insights, custom counters, Windows Events | Covers the most common monitoring signals (CPU, memory, disk, system logs); teaches the modern data collection model without overwhelming students with config options. |
| Metric alert threshold | CPU > 80% on prod VM | 50%, 90%, dynamic | 80% is a reasonable middle ground for a lab VM; triggers often enough to demonstrate alerting without noise, but not so sensitive as to spam on normal variance. |
| Storage account diagnostics | StorageRead & StorageWrite logs | All category options | Captures the essential audit trail of blob access for compliance auditing; excludes Delete operations to reduce log volume in a teaching context. |
| Action Group receivers | Email notification only | Teams, Slack, webhooks, logic apps | Email is universally available and demonstrates core alerting; escalation to external systems is deferred to production labs. |

## 2. Lab simplifications vs production

| Aspect | What the lab does | What production would require | Why it matters |
|---|---|---|---|
| Public network access | Log Analytics workspace allows public ingestion & query | Private Endpoints for ingestion/query; on-prem Data Collectors or Azure Arc agents | Removes the need for complex network plumbing (NSGs, firewall rules) so students focus on the monitoring concept; production must restrict data path to private networks to meet compliance and security boundaries. |
| Workspace redundancy | Single region (Sweden Central) | Multi-region replication with read access or secondary workspace | Lab data is non-critical; production requires geo-redundancy so that regional outages do not block queries or ingestion. |
| DCR association scope | One VM for Insights collection | Cohesive agent policy across 100+ VMs via user-assigned MI | Lab uses direct association to one resource ID passed as a parameter; production relies on tag-based rules and managed identities to keep DCR assignment idempotent and scalable. |
| Alert notification delivery | Synchronous email via Action Group (subject to retry) | Email + SMS + voice call + PagerDuty routing with incident response playbook automation | Lab demonstrates the alert dispatch mechanism; production ties alerts into incident lifecycle (ITSM ticketing, on-call escalation). |
| Diagnostic settings retention | None (infinite retention in workspace) | Retention policy on diagnostic settings to auto-delete after 30–90 days in archive tier | Lab keeps all data to maximize learning; production manages retention to balance compliance hold periods with cost. |

## 3. Well-Architected lens (light)

- **Dominant pillar:** Operational Excellence
  - Central monitoring foundation; teaches structured observability (metrics, logs, traces).
- **Security:** Public network access simplifies the lab but violates least-privilege in production.
  - Private endpoints + managed identities required for enterprise.
- **Reliability:** Alert thresholds and single-region setup adequate for teaching; no multi-region or failover.
- **Performance:** 60-second metric evaluation window is a reasonable real-time balance for cost and noise.
- **Cost:** PerGB2018 with 30-day retention is the cheapest path for learning volumes (<10 GB/month = ~€23/month).

## 4. Cost / FinOps note

- **Monthly cost estimate:** Log Analytics Workspace ~€0 base + €2.30 per GB ingested (PerGB2018). A lab with 5 VMs and moderate logging (~3 GB/month) costs ~€7 total.
- **Reduction tactics:**
  - 30-day retention avoids old-data storage cost.
  - Syslog + perf counters only; no verbose application traces.
  - Email action group free (no SMS or voice charges).
- **Cleanup reminder:**
  - **Do not delete the workspace until the lab is complete.** Deleting the RG does not immediately delete the workspace; it may persist and incur ingestion costs if agents are still writing to it.
  - After lab completion: Delete the workspace explicitly to stop ingestion charges. If flow logs from Lab 5.3 are also routing to this workspace, coordinate deletion to avoid query failure in dependent labs.
  - Storage account diagnostic settings remain after RG deletion; verify no data continues to flow to any workspace that you intend to delete.
