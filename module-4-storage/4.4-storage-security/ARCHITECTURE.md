# Architecture Notes: Lab 4.4 — Storage Security

> Learning context. These notes explain the reasoning behind the lab's design and how it would change in a real environment. The lab deliberately favors clarity over production hardening.

## 1. Design decisions & trade-offs

| Decision | Choice in this lab | Alternatives considered | Why this choice (in a learning context) |
|---|---|---|---|
| Firewall default action | Deny (Production environment) | Allow (default for Lab 4.1–4.3) | Deny-by-default is the "zero trust" principle; students graduate from open (Lab 4.1) to locked-down (Lab 4.4). Production always starts with Deny. |
| Network rules | VNet service endpoint on WorldSubnet only | Multiple subnets, IP ranges, or private endpoints | VNet rule via service endpoint is simpler than private endpoint (no NIC, no DNS zone); teaches the common case. Private endpoints are advanced (Lab 4.5 or separate security module). |
| IP rules | Optional client IP parameter | Hardcoded list, or CIDR ranges | Optional client IP is flexible for different labs/environments; hardcoding would break labs in different networks. |
| Private endpoints | Not configured in this lab | Always deployed for Prod | Private endpoints hide storage from public DNS and internet entirely; deferred to advanced module. Service endpoints still route traffic via public IP internally. |
| Customer-managed keys | Not configured in this lab | Always for Prod | CMK complexity (Key Vault + RBAC + key rotation) exceeds AZ-104 scope; encryption at rest is always on (Microsoft-managed by default). |
| SAS exercise container | `dev-assets`, created on every path (guide Step 4.4.3) | Any existing container (Lab 4.2's), which the guide used before issue #361 | The lab manifest makes 4.4 depend on 4.1 and 2.2, not on 4.2, so the lab creates its own container; the Bicep already declared it, so the three paths now meet in one state `Test-Lab.ps1` can check. |
| Data-plane role | Storage Blob Data Contributor on the account itself, for the learner (Portal) or for whoever runs `Deploy-Bicep.ps1` | A role on the resource group or the subscription; a condition limiting it to `dev-assets` | Account scope is the least privilege that still lets the learner see the switch from key to Entra ID in the Portal; a condition is shown in the wizard but not set, to keep the role easy to check. |
| Key rotation | Both keys, one after the other (guide Section 3), by maintainer decision on issue #357 | Rotation only in Lab 4.1; a key expiration policy | Lab 4.1 shows one rotation; this lab ties the two-key order to what a rotation revokes (SAS tokens, Lab 4.3's mounts). A rotation is an operation, so it has PowerShell commands but no Bicep counterpart. |
| Diagnostic logging | Not configured in this lab | Always enabled (Monitor logs, Storage Analytics) | Logging is critical for audit/compliance but requires separate module (Lab 4.5 or Monitoring module). |

## 2. Lab simplifications vs production

| Aspect | What the lab does | What production would require | Why it matters |
|---|---|---|---|
| Network access | Service endpoint (VNet rule) + optional IP firewall | Private endpoints for all access; no public endpoint | Service endpoint still routes via public infrastructure; private endpoints use private IP and DNS, zero internet exposure. |
| Access keys | Shared key access still enabled; both keys rotated by hand | Disable shared keys, RBAC + Managed Identity only; keys in Key Vault with automatic rotation | Lab doesn't disable shared keys: the SAS exercise, Lab 4.3's mounts and the Portal's default view still use them. Production would eliminate them after confirming all clients use RBAC. |
| Public endpoint | Firewall applied but endpoint exists | No public endpoint registered in DNS/portal | Firewall blocks access but endpoint still resolvable; production would remove public endpoint entirely. |
| SAS token scope | A container SAS on `dev-assets` bound to a stored access policy (Read, List, one day), then revoked | User delegation SAS, short-lived, IP-scoped | A stored access policy needs an account-key (service) SAS; a user delegation SAS is safer but cannot be revoked through a policy, which is what the lab demonstrates. |
| Monitoring | Not configured | Alerts on anomalous access, failed auth, egress anomalies | Lab doesn't enable Storage Analytics or Monitor integration; production tracks all access. |

## 3. Well-Architected lens (light)

- **Dominant pillar:** Security
- **Security:** Firewall default-deny + VNet rules enforce least-privilege network access. Disabling public access and requiring service endpoints (or private endpoints) eliminates internet-facing risk.
- **Reliability:** Service endpoints ensure Azure services can bypass the firewall (bypass: AzureServices); production critical path is protected.
- **Operational Excellence:** Firewall rules are transparent to legitimate clients in the allowed subnet; reduces operational surprises.
- **Cost Optimization:** Service endpoints cost nothing; private endpoints cost ~€7/month each + egress. Lab chooses service endpoints for cost.

## 4. Cost / FinOps note

- **Monthly cost (no new storage, just security configuration):**
  - Service endpoints: €0 (built into VNet)
  - Storage account with Deny firewall: no premium cost (regular GRS/LRS rate applies)
  - **Total incremental cost: €0**
- **If private endpoints were used instead:**
  - 1 private endpoint × ~€7/month = €7
  - Egress data (cross-region or external): €0.02–€0.05/GB depending on destination
  - **Total: €7 + egress**
- **Lab cost controls:** Firewall rules don't auto-create resources; student manually specifies subnet / client IP during deployment.
- **Cleanup reminder:**
  - Network rules (service endpoint, IP firewall) are deleted with storage account or can be manually cleared before RG deletion.
  - Private endpoint NICs (if later used) are orphaned if storage account is deleted; must be cleaned separately.
  - Diagnostic settings (if added) may send logs to Log Analytics; ensure log retention policies are set before cleanup to avoid unexpected egress charges.

## 5. Bicep implementation note (AVM)

- **The firewall is one parameter**: `avm/res/storage/storage-account` (pinned in docs/bicep-standards.md §4.4) takes `networkAcls` with `defaultAction: 'Deny'`, one `virtualNetworkRules` entry for the lab subnet and an optional `ipRules` entry for the student's client IP (omitted when `parClientIp` is empty). The lab's `modules/security.bicep` is deleted. This is the one lab where `Deny` is intentional — Labs 4.1-4.3 override it to `Allow` (docs/bicep-standards.md §4.5).
- **The subnet is resolved through a nested `existing` reference**, so the virtual network rule carries a real subnet resource ID rather than a composed string.
- **This lab restates Labs 4.1 and 4.2 blob settings.** `dev-assets` has to be created through `blobServices.containers`, and a non-empty `blobServices` replaces the whole blob service configuration — so the template restates soft delete, versioning and the earlier containers for the target environment. Lab 4.4 is the only lab in Module 4 that has to do this; see the cumulative-lab note in docs/bicep-standards.md §4.5.
- **The data-plane role is the module's `roleAssignments` parameter.** `parDataContributorPrincipalId` carries the object id `Deploy-Bicep.ps1` reads from the `oid` claim of its Azure Resource Manager token (no Microsoft Graph call), or nothing when that identity holds the role on the account already: the module names its assignment `guid(account, principal, role)`, and ARM refuses a second assignment of the same role to the same principal at the same scope under another name, such as the one a Portal-made assignment has (`RoleAssignmentExists`). Empty, the template assigns nothing.
- **Prerequisite: `WorldSubnet` must carry the `Microsoft.Storage` service endpoint**, which Lab 2.2 sets. Without it the virtual network rule is rejected.
- **Cleanup no longer removes that service endpoint.** It is Lab 2.2 state — Lab 2.2 sets it and its `Test-Lab.ps1` asserts it — so removing it here silently regressed Module 2 on every Module 4 cleanup. `Remove-LabResource.ps1` now prints an informational line instead. The firewall revert, the `dev-assets` removal and the role-assignment cleanup are unchanged.
- **`platform` is rejected, not merely unusable.** The hub VNet has only `AzureBastionSubnet` and `GatewaySubnet`, so there is no workload subnet to allow through the storage firewall. `parEnvironment` is `@allowed(['dev', 'prod'])` and all three scripts validate the same set, so the run fails at parameter binding with a clear message instead of at deployment time (#94).
