# Architecture Notes: Lab 4.2 — Blob Storage

> Learning context. These notes explain the reasoning behind the lab's design and how it would change in a real environment. The lab deliberately favors clarity over production hardening.

## 1. Design decisions & trade-offs

| Decision | Choice in this lab | Alternatives considered | Why this choice (in a learning context) |
|---|---|---|---|
| Container isolation | Production: 4 private containers; Dev: 1 public container | All private with lifecycle, all public with RBAC | Mirrors real scenarios: prod stores game-assets, backups, configs, logs (all private); dev has public demo asset for student learning. Public access in dev teaches the risk. |
| Public access model | Account-level public access (Dev only) | Container-level public access | Account-level is the least-secure option; Lab 4.4 teaches disabling it. Container-level is more granular (not shown here). |
| Lifecycle tiers | Prod logs: Hot→Cool (30d)→Cold (90d)→Archive (180d)→Delete (365d); backups: Archive (7d) | All tiers kept Hot, or delete after X days | Tiering teaches cost optimization: Cool/Cold/Archive are cheaper per-GB but have retrieval latency. Backups → Archive quickly (7d) reflects backup storage model. Logs aging to deletion (365d) teaches retention policies. |
| Blob versioning | Enabled (Prod only) | Disabled, or versioning with immutable snapshots | Versioning enables rollback of accidental overwrites; disabled in Dev (less critical). Production would enable for game-assets and configs. |
| Lifecycle filters | Prefix matching on `player-backups/` | No prefix filtering, or wildcard patterns | Prefix filtering teaches selective rules; backups in a dedicated prefix is a real pattern. |

## 2. Lab simplifications vs production

| Aspect | What the lab does | What production would require | Why it matters |
|---|---|---|---|
| Retention compliance | Lifecycle auto-deletes after 365 days | Multi-year retention with legal hold / immutable storage | Game logs may have regulatory or audit requirements (GDPR, SOC2). Immutable blobs prevent deletion once set. |
| Rehydration cost | Not addressed | Explicitly budget rehydration cost when retrieving from Archive | Rehydration can take hours and cost 10–100x more than initial storage. Production must track access patterns. |
| Backup strategy | Backups archived after 7 days (still deletable) | Immutable snapshots or cross-region replication | Lab doesn't teach active/passive backup failover; snapshots are point-in-time but mutable. |
| Change tracking | Versioning enabled (no change feed) | Change feed + event-driven pipelines | Versioning tracks overwrites; change feed integrates with Event Grid for real-time processing. Lab is simpler. |
| Access logging | Not configured | Storage Analytics logs all read/write; sent to Monitor | Logging provides audit trail for security/compliance; deferred to monitoring module. |

## 3. Well-Architected lens (light)

- **Dominant pillar:** Cost Optimization & Compliance
- **Cost Optimization:** Lifecycle policies tiering logs down automatically reduce storage costs by 60–80%; Archive tier at €0.004/GB/month vs Hot at €0.018/GB/month.
- **Reliability:** Versioning (Prod) enables rollback; multi-region replication would be next step.
- **Security:** Public access in Dev is intentional teaching tool; Prod is fully private. RBAC/SAS token controls not shown here (Lab 4.4).
- **Compliance:** 365-day retention before deletion reflects audit requirements; immutable storage not yet needed.

## 4. Cost / FinOps note

- **Monthly cost (assuming 1 TB in Prod, 100 GB in Dev):**
  - Prod Hot (50% of 1 TB): €18
  - Prod Cool (30% of 1 TB, assume 40 days): ~€3
  - Prod Cold (15% of 1 TB, assume 120 days): ~€0.30
  - Prod Archive (5% of 1 TB, assume 270 days): ~€0.05
  - Dev Hot (100 GB public demo): ~€1.80
  - **Total: ~€23/month** (vs ~€36 without tiering)
  - **Savings: ~€13/month (~35% reduction) from Hot-only**
- **Rehydration costs:** If retrieving 1 GB from Archive: ~€0.02 retrieval + Standard re-hydration latency (hours). Communicate this in lab guide.
- **Cleanup reminder:**
  - Lifecycle policies don't delete immediately; archived blobs in 365+ day retention remain until deletion task runs.
  - Snapshots (if any) must be manually deleted; not covered by container deletion.
  - Soft-deleted containers/blobs still occupy storage for 7 days; plan cleanup accordingly.

## 5. Bicep implementation note (AVM)

- **Containers and lifecycle rules are parameters, not resources**: both prod and dev go through `avm/res/storage/storage-account` (pinned in docs/bicep-standards.md §4.4), with the containers as `blobServices.containers` and the two tiering rules as `managementPolicyRules`. The lab's `modules/blobContainer.bicep` is deleted.
- **The cross-lab import is gone.** This template used to import `../../4.1-storage-accounts/bicep/modules/storageAccount.bicep`, coupling two labs at compile time; each lab now calls the AVM module directly.
- **The `PublicAccessNotPermitted` race no longer exists.** `blobContainer.bicep` was a workaround for creating a `Blob`-level container before `allowBlobPublicAccess` had settled. Every container in this lab is `publicAccess: 'None'` — the subscription policy blocks anything else — so the race cannot occur and the container declaration moved inside the module call.
- **`fileServices` is omitted on purpose.** The module skips a sub-service entirely when its parameter is empty, so Lab 4.1's file-share soft delete (and later Lab 4.3's shares) survive this deployment untouched. See the cumulative-lab note in docs/bicep-standards.md §4.5.
- **Lab-friction overrides** (docs/bicep-standards.md §4.5): `networkAcls` default action `Allow` and `requireInfrastructureEncryption: false`, as in Lab 4.1.
- **`Deploy-Bicep.ps1` now passes `parLocation`.** It accepted `-Location` but only used it as the deployment location, so the template always kept its own default.
