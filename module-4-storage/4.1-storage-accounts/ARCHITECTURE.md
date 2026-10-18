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
| Monitoring & diagnostics | Not configured in this lab | Storage Analytics + Azure Monitor logs | Lab 5.1 adds a diagnostic setting to the platform account. Storage diagnostics help with troubleshooting and capacity planning. |

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
- **Lab cost controls:** The lab stores a few megabytes, so the three accounts cost cents per month; an account has no fixed fee. Keep them until Module 5 is done: Labs 4.2-4.4 and 5.1-5.3 use them (the guide's "What This Lab Leaves Behind"). The Portal defaults that would add cost - read access to the secondary region (RA-GRS), geo priority replication, Microsoft Defender for Storage, a private endpoint - are named in Step 4.1.2 and left off.
- **Cleanup reminder:**
  - Delete storage accounts to stop billing (data is deleted with the account unless backed up elsewhere).
  - Soft-deleted blobs/containers remain for 7 days after deletion; no additional cleanup needed.
  - Lab 1.3's `CanNotDelete` locks on `platform-skycraft-swc-rg` and `prod-skycraft-swc-rg` block deleting `platformskycraftswcsa` and `prodskycraftswcsa`; `Remove-LabResource.ps1` reports them as failed until the locks are removed (Lab 1.3's cleanup removes them).

## 5. Bicep implementation note (AVM)

- **Accounts**: `avm/res/storage/storage-account` (pinned in docs/bicep-standards.md §4.4). One module call covers the account, its blob service and its file service, so the lab's local `modules/storageAccount.bicep` is gone; there is no `bicep/modules/` directory left in Module 4.
- **One copy loop, three environments**: the three near-identical conditional module calls collapsed into `[for env in varEnvironments: ...]` with `scope: resourceGroup('${env}-skycraft-swc-rg')`. `parDeployAllEnvironments` decides whether the loop runs over `platform, dev, prod` or over the single `parEnvironment`, and the three named outputs are rebuilt with `indexOf`, returning `not-deployed` for an environment this run skipped. The three `existing` resource-group lookups disappeared with the loop.
- **Lab-friction overrides** (docs/bicep-standards.md §4.5): `networkAcls: { bypass: 'AzureServices', defaultAction: 'Allow' }` — the module emits `Deny` when the parameter is omitted, which would lock the account before Lab 4.4 teaches it; and `requireInfrastructureEncryption: false` — the module defaults it to `true` while Azure's own default is `false`, and the property is creation-only. Lab 4.1 wires the second one to `parEnableInfrastructureEncryption`, so `Deploy-Bicep.ps1 -InfraEncryption` still works on a brand-new account.
- **`parIsNewDeployment` is gone**, and with it the `-NewDeployment` switch. The old template switched between two encryption objects so an update would not send the creation-only `keyType`; the AVM module leaves `keyType` unset unless it is passed, and the resulting encryption block is exactly the old update-safe one. The deploy script keeps its existing-account scan, because that scan still has a job: forcing infrastructure encryption off when the account already exists.
- **Behavioural deltas from AVM defaults**, accepted rather than overridden: `isLocalUserEnabled: false`. `allowCrossTenantReplication: false` is also the module's default, and `main.bicep` states it anyway (#358), because the Portal's Advanced tab leaves **Allow cross-tenant replication** unchecked and the guide's PowerShell and CLI blocks pass `$false`, so the three paths visibly agree.
- **Paths that agree** (#358, #362): the Portal steps, the guide's Az PowerShell and CLI blocks and this template set the same account properties and the same 7-day soft delete for blobs, containers and file shares. One Portal default has no counterpart here: **Require Encryption in Transit for SMB** (Advanced tab, checked). With `supportsHttpsTrafficOnly: true`, SMB already requires encryption, so file shares behave the same; `Test-Lab.ps1` does not check it.
