# Architecture Notes: Lab 5.1 — Azure Monitor

> Learning context. These notes explain the reasoning behind the lab's design and how it would change in a real environment. The lab deliberately favors clarity over production hardening.

## 1. Design decisions & trade-offs

| Decision | Choice in this lab | Alternatives considered | Why this choice (in a learning context) |
|---|---|---|---|
| Log Analytics SKU | PerGB2018 | Pay-as-you-go (Standalone) | PerGB2018 remains available and is cost-effective for small labs; students learn the modern ingestion model that charges per GB of data sent rather than reserved capacity. |
| Data retention | 30 days | 90, 365 days or indefinite | 30 days balances learning (enough data to analyze trends) with cost control; extended retention can quickly become expensive (€0.50+ per GB per month) and is unnecessary for lab exercises. |
| DCR data sources | Basic performance counters to `Perf`, VM Insights counters to `InsightsMetrics`, plus Syslog | Application Insights, custom counters, Windows Events | Covers the most common monitoring signals (CPU, memory, disk, system logs); `Perf` is the table the lab's KQL queries, `InsightsMetrics` keeps VM insights' Performance view working. |
| Agent install | `AzureMonitorLinuxAgent` extension: tagged by the Bicep, installed by the DCR wizard in the Portal (only the `Project` tag), or by a Cloud Shell block in the guide (all four tags) | VM insights wizard, Azure Policy that deploys the agent | Lab 1.3's `Enforce-Project-Tag` requires `Project`, and its `Inherit-Project-Tag` adds it to an extension created without one, as the DCR wizard's install is; neither the VM insights wizard nor the extension picker sets tags, and the Bicep and the Cloud Shell block set all four. |
| Metric alert threshold | CPU > 80% on prod VM | 50%, 90%, dynamic | 80% is a reasonable middle ground for a lab VM; triggers often enough to demonstrate alerting without noise, but not so sensitive as to spam on normal variance. |
| Storage account diagnostics | StorageRead & StorageWrite logs | All category options | Captures the essential audit trail of blob access for compliance auditing; excludes Delete operations to reduce log volume in a teaching context. |
| Missing-Heartbeat alert | Log search alert `skycraft-heartbeat-alert` scoped to the monitored VM: `Heartbeat` rows Count < 1 over 5 minutes, evaluated every 5 minutes, severity 1 | Metric alert on VM availability, workspace-scoped query with a `Computer` filter, 1-minute evaluation | It teaches the second alert type the AZ-104 outline names (log search alerts from KQL) on a signal a CPU alert cannot see: a VM, agent or network that stops reporting. Scoping it to the VM keeps the query a bare `Heartbeat`; 5 minutes leaves room for ingestion delay and costs less than 1-minute evaluation. |
| Action group region | Global | Sweden Central (regional processing) | The Portal starts at East US, which Lab 1.3's region policy refuses; Global is what the CLI, PowerShell and Bicep create and the *Allowed locations* policy lets through, so the three paths end in the same state. |
| Dashboard | Private dashboard `SkyCraft-Ops` | Shared (published) dashboard | A private dashboard is stored with the learner's Portal settings, not as a resource, so no region or tag policy applies; a shared one would need Sweden Central and the four tags. The cleanup script does not see it. |
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
  - One log search alert at a 5-minute evaluation; log search alerts are billed per rule by evaluation frequency, so 1-minute evaluation would cost more.
- **Cleanup reminder:**
  - **Do not delete the workspace until the lab is complete.** Deleting the RG does not immediately delete the workspace; it may persist and incur ingestion costs if agents are still writing to it.
  - After lab completion: Delete the workspace explicitly to stop ingestion charges. If flow logs from Lab 5.3 are also routing to this workspace, coordinate deletion to avoid query failure in dependent labs.
  - Storage account diagnostic settings remain after RG deletion; verify no data continues to flow to any workspace that you intend to delete.

## 5. Bicep implementation note (AVM)

- **Modules**: `avm/res/operational-insights/workspace`, `avm/res/insights/data-collection-rule`, `avm/res/compute/virtual-machine/extension` (the Azure Monitor Agent, in the monitored VM's group, with the canonical tags), `avm/res/insights/action-group`, `avm/res/insights/metric-alert` and `avm/res/insights/scheduled-query-rule` (the missing-Heartbeat log search alert, scoped to the VM that gets the agent; all pinned in docs/bicep-standards.md §4.4), called directly from `main.bicep`. The local `modules/monitoring.bicep` is gone.
- **Local fallback**: `modules/storage-blob-diagnostics.bicep` attaches `skycraft-storage-diag` to the platform storage account's blob service. `avm/res/insights/diagnostic-setting` is a subscription-scope module (activity log) and cannot target a resource, and re-declaring the storage account through `avm/res/storage/storage-account` from this lab would replace Lab 4.1's account-level configuration (standards §4.3).
- **Still in `Deploy-Bicep.ps1`**: the DCR association (the monitored VM's resource ID is only known at run time) — unchanged.
- **Behavioural deltas from AVM defaults**, accepted rather than overridden: the workspace is created with `features.disableLocalAuth: true` and `forceCmkForQuery: true` (Azure's own defaults are `false`). Nothing in Module 5 uses the workspace shared keys — VM Insights runs through the Azure Monitor Agent and the DCR, Traffic Analytics and the connection monitor write through service-side integrations, and every query authenticates with Entra ID. Data retention is passed explicitly (`parRetentionInDays`, 30 days) because the module defaults to 365.
- **Log search alert**: `skipQueryValidation` is set because a first deploy creates the rule before the agent has sent a row; the Portal and PowerShell paths of Step 5.1.8 run after Step 5.1.3 shows data, so they validate the query.
- **Metric alert criteria** are expressed through the module's `alertResourceType` (`odata.type` + lowercase `allof`); the deployed rule carries the same `Percentage CPU > 80` criterion, severity 2, 1-minute evaluation over a 5-minute window.
