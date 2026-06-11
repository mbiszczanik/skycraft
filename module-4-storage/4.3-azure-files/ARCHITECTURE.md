# Architecture Notes: Lab 4.3 — Azure Files

> Learning context. These notes explain the reasoning behind the lab's design and how it would change in a real environment. The lab deliberately favors clarity over production hardening.

## 1. Design decisions & trade-offs

| Decision | Choice in this lab | Alternatives considered | Why this choice (in a learning context) |
|---|---|---|---|
| Protocol | SMB only (implied by StorageV2 + fileServices) | NFS (requires Premium SKU) | SMB is standard for Windows/AD environments; NFS requires Premium tier, which costs 5–10x more and is overkill for a lab. NFS taught in advanced modules. |
| Tier / SKU | Standard_GRS (Prod) / Standard_LRS (Dev) | Premium storage, Hot/Cool variants | Standard Hot is the baseline; tiering requires StorageV2 but not a separate Premium account. Premium (~€0.16/GB provisioned) is for low-latency gaming/databases; standard file shares teach the common case. |
| File share quotas | skycraft-config: 100 GB; skycraft-shared: 500 GB | Unlimited, or very small (10 GB) | Quotas teach capacity planning; realistic sizes (100/500 GB) reflect small game-server configs and shared assets. Unlimited would mask over-provisioning. |
| File share snapshots | Not configured in this lab | Always enabled, scheduled | Snapshots provide point-in-time recovery; deferred to a later lab. Lab 4.3 focuses on provisioning and access. |
| AD integration | Not configured in this lab | On-premises AD or Entra ID | AD integration adds complexity; Lab 4.3 focuses on share creation. Lab 4.5+ or module-3 (Identities) would cover this. |

## 2. Lab simplifications vs production

| Aspect | What the lab does | What production would require | Why it matters |
|---|---|---|---|
| Access method | Via Azure Portal / Azure CLI | SMB mount from Windows/Linux VM with AD authentication | Portal is for verification; production mounts via SMB using AD credentials, not account keys. |
| Performance tier | Hot (standard) | Cool for infrequent access, Premium for latency-critical apps | Hot suits active game-server configs; Cool is cheaper for archives. Premium is for dedicated performance (IOPS/throughput guarantees). |
| Snapshots & backup | Manual only | Automated snapshots + Azure Backup integration | Lab creates shares but doesn't automate point-in-time recovery. Production needs scheduled snapshots. |
| Encryption | Default (Microsoft-managed) | Customer-managed keys in Key Vault | Lab doesn't address CMK; encryption at rest is always on. |
| Network isolation | Public network access enabled | Service endpoints or private endpoints + deny public access | Lab 4.4 tightens this; initially open for testing. Production would firewall off public access. |

## 3. Well-Architected lens (light)

- **Dominant pillar:** Reliability & Operational Excellence
- **Reliability:** GRS in Prod enables failover; file share quota limits prevent accidental exhaustion.
- **Operational Excellence:** File shares simplify SMB mount for VMs; snapshots (not yet shown) reduce RTO for data loss.
- **Cost Optimization:** Standard SKU is cheapest shared storage; Premium reserved for low-latency workloads.
- **Security:** Public network access simplified here; restricted in Lab 4.4 via private endpoints or service endpoints.

## 4. Cost / FinOps note

- **Monthly cost (assuming 100 GB config + 500 GB shared shares = 600 GB total in Prod):**
  - Standard GRS, Hot: 600 GB × €0.036/GB = ~€21.60/month
  - Transactions (estimate 10,000/month): ~€0.10
  - **Total: ~€22/month**
- **Dev (Standard LRS, ~100 GB):**
  - 100 GB × €0.018/GB = ~€1.80/month
  - **Combined: ~€24/month**
- **Premium alternative cost (if used):**
  - Premium File Share provisioned at 100 GB: €16/month (fixed) for tier; 500 GB: €80/month.
  - **Premium would cost ~€96/month; Standard saves ~€72/month for this lab.**
- **Lab cost controls:** File shares can be shrunk or deleted after lab; no auto-snapshot cleanup needed in this lab.
- **Cleanup reminder:**
  - Soft-deleted file shares (if any) occupy storage for 14 days before purge.
  - Snapshots (if created manually) must be deleted individually; not auto-cleaned with share deletion.
  - Ensure no locks on shares before RG deletion.
