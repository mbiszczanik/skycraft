# Architecture Notes: Lab 4.3 — Azure Files

> Learning context. These notes explain the reasoning behind the lab's design and how it would change in a real environment. The lab deliberately favors clarity over production hardening.

## 1. Design decisions & trade-offs

| Decision | Choice in this lab | Alternatives considered | Why this choice (in a learning context) |
|---|---|---|---|
| Protocol | SMB only (implied by StorageV2 + fileServices) | NFS (requires Premium SKU) | SMB is standard for Windows/AD environments; NFS requires Premium tier, which costs 5–10x more and is overkill for a lab. NFS taught in advanced modules. |
| Tier / SKU | Classic file shares in the StorageV2 account (pay-as-you-go), access tier Hot; Standard_GRS (Prod) / Standard_LRS (Dev) | Transaction optimized (the Portal's default), Cool, Premium (provisioned, FileStorage account), `Microsoft.FileShares` file shares (NFS only, provisioned v2) | Hot suits small, often-read config files. Pay-as-you-go bills the data stored and the operations, not the quota, so the lab's shares cost next to nothing. Premium needs a separate provisioned account and bills its provisioned size every hour; `Microsoft.FileShares` does not support SMB. |
| File share quotas | skycraft-config: 100 GB; skycraft-shared: 500 GB | Unlimited, or very small (10 GB) | Quotas teach capacity planning; realistic sizes (100/500 GB) reflect small game-server configs and shared assets. Unlimited would mask over-provisioning. |
| File share snapshots | One manual snapshot (Step 4.3.5), restored from in Step 4.3.6 | Scheduled snapshots through Azure Backup | A manual snapshot teaches point-in-time restore without a vault or a policy. Scheduled backups are Lab 5.2's topic. |
| Azure Backup for the shares | Off on every path: the guide has the learner untick the Portal wizard's **Enable backup** (on by default), the PowerShell blocks and the Bicep configure none, and `Test-Lab.ps1` fails a protected share (issue #360) | The Portal's default: a daily policy in a Recovery Services vault | Backup costs a protected-instance fee from the moment it is on, puts a delete lock on the storage account that blocks this lab's cleanup, and belongs to Lab 5.2. |
| AD integration | Not configured in this lab; mounts use the account key (NTLMv2), so the account's SMB **Security** profile stays at **Maximum compatibility** | On-premises AD DS, Microsoft Entra Kerberos | Identity-based access needs a domain or Entra Kerberos setup that the course does not build; the guide explains it only in the Additional Resources. |

## 2. Lab simplifications vs production

| Aspect | What the lab does | What production would require | Why it matters |
|---|---|---|---|
| Access method | Via Azure Portal / Azure CLI | SMB mount from Windows/Linux VM with AD authentication | Portal is for verification; production mounts via SMB using AD credentials, not account keys. |
| Performance tier | Hot (standard) | Cool for infrequent access, Premium for latency-critical apps | Hot suits active game-server configs; Cool is cheaper for archives. Premium is for dedicated performance (IOPS/throughput guarantees). |
| Snapshots & backup | One manual snapshot; Azure Backup deliberately off | Automated snapshots + Azure Backup integration | Lab creates shares but doesn't automate point-in-time recovery. Production needs scheduled snapshots (Lab 5.2 shows Azure Backup on VMs). |
| Encryption | Default (Microsoft-managed) | Customer-managed keys in Key Vault | Lab doesn't address CMK; encryption at rest is always on. |
| Network isolation | Public network access enabled | Service endpoints or private endpoints + deny public access | Lab 4.4 tightens this; initially open for testing. Production would firewall off public access. |

## 3. Well-Architected lens (light)

- **Dominant pillar:** Reliability & Operational Excellence
- **Reliability:** GRS in Prod enables failover; file share quota limits prevent accidental exhaustion.
- **Operational Excellence:** File shares simplify SMB mount for VMs; snapshots (Steps 4.3.5-4.3.6) reduce RTO for data loss.
- **Cost Optimization:** Standard SKU is cheapest shared storage; Premium reserved for low-latency workloads.
- **Security:** Public network access simplified here; restricted in Lab 4.4 via private endpoints or service endpoints.

## 4. Cost / FinOps note

- **What the lab costs:** pay-as-you-go shares are billed for the data they hold and the operations on them, not for their quota ([Understand Azure Files billing](https://learn.microsoft.com/azure/storage/files/understanding-billing#pay-as-you-go-model)). The lab stores a few bytes (`common/config.txt` and one snapshot), so both shares cost well under 0.01 USD per day. The 100 and 500 GiB quotas are limits, not charges.
- **If the shares were full:** 600 GiB on Hot GRS would cost on the order of 20 EUR a month at list prices (check the [pricing calculator](https://azure.microsoft.com/pricing/calculator/)); a provisioned (Premium) share is billed for its provisioned size whether used or not, which is why the lab does not use one.
- **Defaults that would cost money:** the Portal wizard's **Enable backup** (protected-instance fee plus backup snapshots) and its **Access tier** default of Transaction optimized (the highest price per stored GiB). The guide has the learner change both.
- **Cleanup reminder:**
  - Soft-deleted file shares occupy, and are billed for, their used storage for 14 days before purge.
  - `Remove-LabResource.ps1` deletes the shares together with their snapshots (`-Include Snapshots`).
  - Lab 1.3's `lock-no-delete-prod` on `prod-skycraft-swc-rg` refuses the share deletes (`ScopeLocked`) until it is lifted (issue #372); an Azure Backup delete lock on the account does the same until the backup is stopped.

## 5. Bicep implementation note (AVM)

- **Shares and their retention are parameters**: `avm/res/storage/storage-account` (pinned in docs/bicep-standards.md §4.4) takes the 14-day `fileServices.shareDeleteRetentionPolicy` and the two shares as `fileServices.shares`. The lab's `modules/storage.bicep` is deleted.
- **`blobServices: {}` is deliberate and load-bearing.** The module skips a sub-service when its parameter is empty, so passing an explicit empty object leaves Lab 4.2's containers, versioning and lifecycle rules exactly as they were. `blobServices` is the only sub-service that needs this: unlike `fileServices`, `queueServices`, `tableServices` and `managementPolicyRules`, it has a non-empty default (which would rewrite blob soft delete to 6 days). See the cumulative-lab note in docs/bicep-standards.md §4.5.
- **Lab-friction overrides** (docs/bicep-standards.md §4.5): `networkAcls` default action `Allow` and `requireInfrastructureEncryption: false`, as in Lab 4.1.
- **One end state on every path (issue #362).** The Portal steps, the guide's Az PowerShell blocks and this template leave the same two Hot shares, quotas and 14-day soft delete, with no backup. The template redeploys the whole account, so it also restates Lab 4.1's settings and the AVM defaults Lab 4.1's ARCHITECTURE.md lists; with `-Environment dev` it sends `largeFileSharesState: 'Disabled'`, which Azure may refuse over a dev account built another way (issue #390). The module's file service sends `protocolSettings: {}`; whether that leaves the account's SMB settings (the Portal's **Require Encryption in Transit for SMB**) as they are is to be confirmed with `Deploy-Bicep.ps1 -WhatIf` over a Portal-built lab.
- **`outPrimaryFileEndpoint` reads `serviceEndpoints.file`.** The module's own documentation warns that `Standard_LRS` / `Standard_ZRS` accounts may expose only a blob endpoint; on the lab's `StorageV2` accounts that is not the case - the live cycle returned `https://devskycraftswcsa.file.core.windows.net/` for the `Standard_LRS` dev account. Keep the caveat in mind if the SKU or account kind ever changes.
