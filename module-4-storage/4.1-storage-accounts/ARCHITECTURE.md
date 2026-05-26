# Architecture Notes: Lab 4.1 — Storage Accounts

> Learning context. These notes explain the reasoning behind the lab's design and how it would change in a real environment. The lab deliberately favors clarity over production hardening.

## 1. Design decisions & trade-offs

| Decision | Choice in this lab | Alternatives considered | Why this choice (in a learning context) |
|---|---|---|---|
| Redundancy per environment | Production & Platform: GRS; Development: LRS | All environments GRS or all LRS | GRS costs 2x but teaches high-availability for critical data; LRS in dev reflects cost-consciousness in non-critical environments. AZ-104 objective covers both strategies. |
| Access tier | Hot (all environments) | Cool or Archive | Hot tier is default and most common; archive tier requires longer retrieval latency (not yet relevant in Lab 4.1). Students learn tiering in Lab 4.2. |
| Public network access | Enabled (default) | Disabled with firewall | Lab 4.4 locks this down; starting open simplifies initial deployment and CLI testing. Production would deny by default. |
| Blob/File soft delete | Enabled (7 days) | Disabled or longer retention | 7 days balances accidental deletion recovery with compliance. AZ-104 emphasizes soft delete for data protection. |
| Infrastructure encryption | Optional (disabled by default) | Always enabled | Infrastructure encryption cannot be changed post-creation; disabled here lets students apply it only if explicitly requested. Production would likely enable it. |
| Blob versioning | Optional (disabled by default) | Always enabled | Versioning adds cost and complexity; introduced in Lab 4.2 after containers are deployed. |

## 2. Lab simplifications vs production

| Aspect | What the lab does | What production would require | Why it matters |
|---|---|---|---|
| Network isolation | Public endpoints accessible from internet | Private endpoints + service endpoints only | Lab 4.1 teaches resource creation; Lab 4.4 teaches network security. Production needs zero public exposure for sensitive data. |
| Encryption key management | Microsoft-managed keys (default) | Customer-managed keys (CMK) in Key Vault | CMK provides key rotation control and regulatory compliance (HIPAA, PCI-DSS); added complexity for a lab. |
| Access controls | Shared key access enabled | Disable shared keys, RBAC only | Shared keys are legacy; RBAC is role-based least privilege. Lab doesn't enforce this choice. |
| Monitoring & diagnostics | Not configured in this lab | Storage Analytics + Azure Monitor logs | Lab 4.5 (or later module) would add monitoring. Storage diagnostics help with troubleshooting and capacity planning. |

## 3. Well-Architected lens (light)

- **Dominant pillar:** Security & Cost Optimization
- **Reliability:** GRS in production enables failover to secondary region; reduces data loss RTO/RPO.
- **Cost Optimization:** LRS in dev saves ~50% vs GRS; soft delete retention period (7d) is minimal while protecting against accidents.
- **Security:** Public network access (enabled by default) is simplified here; firewall rules deferred to Lab 4.4.
- **Operational Excellence:** Soft delete and versioning reduce manual recovery effort; no logging/diagnostics in this lab.

## 4. Cost / FinOps note

- **Monthly cost (rough, assuming 1 TB stored):**
  - Platform GRS: ~€36/month (€0.036/GB/month × 1000 GB)
  - Dev LRS: ~€18/month (€0.018/GB/month × 1000 GB)
  - Prod GRS: ~€36/month
  - **Total: ~€90/month for 1 TB across all three environments**
- **Lab cost controls:** Resource groups can be deleted after lab; no auto-shutdown needed (storage is always-on, but can be deleted immediately).
- **Cleanup reminder:**
  - Delete storage accounts to stop billing (data is deleted with the account unless backed up elsewhere).
  - Soft-deleted blobs/containers remain for 7 days after deletion; no additional cleanup needed.
  - Ensure no external locks on storage accounts before RG deletion.
