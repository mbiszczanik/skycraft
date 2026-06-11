# Architecture Notes: Lab 5.2 — Business Continuity & Disaster Recovery

> Learning context. These notes explain the reasoning behind the lab's design and how it would change in a real environment. The lab deliberately favors clarity over production hardening.

## 1. Design decisions & trade-offs

| Decision | Choice in this lab | Alternatives considered | Why this choice (in a learning context) |
|---|---|---|---|
| Recovery Services Vault redundancy | Locally Redundant Storage (LRS) | Geo-Redundant Storage (GRS) | LRS keeps lab costs minimal (~€2–4/month per protected VM) and is sufficient for a learning exercise; production requires GRS or GZRS to survive region-wide outages and meet RTO/RPO SLAs. |
| Backup frequency | Daily (via Deploy-Bicep.ps1 policy creation) | Hourly or multiple times per day | Daily balances RPO (up to 24 hours of loss acceptable) with cost and simplicity; production may require 4-hourly or 1-hourly recovery points depending on mission-critical data. |
| Retention period | 30 days for daily backups | 365 days or tiered (daily 30d, weekly 1y, monthly 5y) | 30 days is enough to recover from a recent corruption or accidental deletion in a lab; production uses longer retention for compliance (HIPAA 7-year, SOX 10-year) and archival cost tiers. |
| Vault storage access | Public network enabled | Private Endpoints, no public access | Lab simplicity; production isolates backup vault traffic to private networks to satisfy compliance and reduce ransomware blast radius. |
| Soft delete | Enabled (default) | Disabled | Soft delete prevents accidental vault deletion and is enabled by default in Bicep; production always uses soft delete (14-day grace period) to prevent catastrophic data loss. |
| Blob operational backup (Backup Vault) | Continuous, 30-day retention | Snapshot-based (cheaper but lower granularity) | Continuous backup captures every block change; useful for learning destructive workloads; production chooses based on RTO/RPO (snapshots faster to restore, continuous granular point-in-time). |
| Backup Vault identity | System-assigned managed identity | User-assigned MI (recommended) | System-assigned is simpler for a single vault in a lab; production uses user-assigned MI to support role inheritance across multiple vaults and cleaner identity hygiene. |

## 2. Lab simplifications vs production

| Aspect | What the lab does | What production would require | Why it matters |
|---|---|---|---|
| Vault geo-redundancy | LRS (single region) | GRS or GZRS (cross-region replication) | Lab data loss is acceptable; production must survive regional failures and meet RTO/RPO guarantees in SLAs. |
| Backup targets | 1–2 VMs in the lab | 50–1000+ VMs with tiered priority (critical, standard, non-critical) | Lab uses hardcoded VM resource ID in metric alert; production automates target discovery via tags or policy to avoid manual registration and support scaling. |
| Retention policy complexity | Single 30-day policy for all backups | Tiered: daily 30d, weekly 1y, monthly 5y, archive after 1 year | Lab keeps data simple; production archives to cold storage (€0.01/GB/month) after hot retention window to meet compliance while controlling cost. |
| Backup verification & restore testing | Manual verification in lab guide | Automated restore test every 30 days via runbook | Lab trusts backups are valid; production performs periodic restore drills to catch silent backup failures before they are needed in an outage. |
| Monitoring | Diagnostic logs route to Log Analytics (Lab 5.1 workspace) | Backup reports in dedicated dashboard, alert on backup job failure | Lab collects logs; production activates alerts so failed backups are detected and remediated within SLA (typically 4 hours). |
| Cross-tenant recovery | Not applicable | Backup Vault may support cross-subscription/tenant restore scenarios | Out of scope for this lab; relevant for enterprise multi-cloud disaster recovery. |

## 3. Well-Architected lens (light)

- **Dominant pillar:** Reliability & Resilience
  - Backup is the foundational tool for recovery from data loss and ransomware; teaches backup design and testing discipline.
- **Security:** Soft delete and RBAC on vault access prevent unauthorized deletion or tampering.
  - Private Endpoints and deny-public-access policies required in production.
- **Cost:** LRS + 30-day retention keeps lab cost ~€4.50/month per VM (<50 GB).
  - Tiered retention (archive after 1 year) essential in production for long-term compliance retention.
- **Operational Excellence:** Diagnostic logs to workspace enable backup health monitoring and trend analysis.

## 4. Cost / FinOps note

- **Monthly cost estimate:**
  - Recovery Services Vault: Free (no base cost).
  - Instance Protection (per VM per month): ~€4.50 for a Standard_B2s VM with <50 GB incremental backups.
  - Backup Vault: Free (no base cost).
  - Blob operational backup: ~€0 for <100 GB stored (continuous, 30-day retention).
  - **Total for 2 VMs:** ~€9/month.
- **Reduction tactics:**
  - LRS storage is cheaper than GRS (GRS adds ~2x cost).
  - 30-day retention avoids long-term storage fees; archive tiers reduce per-GB cost to €0.01/month after hot period.
  - Deploy-Bicep.ps1 uses Azure Backup REST API to create policies (idempotent), avoiding repeated creation attempts.
- **Cleanup reminder:**
  - **Do not delete the vault immediately after lab completion.** Soft delete is enabled; the vault will be in a "soft-deleted" state for 14 days. Deletion will fail if any protected instance still references it.
  - Stop all backup jobs first: Disable backup on the 2 protected VMs, allow the next backup cycle to complete, then delete the vault.
  - After soft-delete grace period (14 days), the vault is permanently deleted and recovery is no longer possible.
  - Backup Vault also supports soft delete; follow the same 14-day grace period process.
  - Diagnostic settings on the vault itself will be deleted with the vault, but logs already sent to the Log Analytics workspace (Lab 5.1) remain and continue to incur ingestion charges unless the workspace is also deleted.
