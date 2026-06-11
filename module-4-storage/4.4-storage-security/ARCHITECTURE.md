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
| Diagnostic logging | Not configured in this lab | Always enabled (Monitor logs, Storage Analytics) | Logging is critical for audit/compliance but requires separate module (Lab 4.5 or Monitoring module). |

## 2. Lab simplifications vs production

| Aspect | What the lab does | What production would require | Why it matters |
|---|---|---|---|
| Network access | Service endpoint (VNet rule) + optional IP firewall | Private endpoints for all access; no public endpoint | Service endpoint still routes via public infrastructure; private endpoints use private IP and DNS, zero internet exposure. |
| Access keys | Shared key access still enabled | Disable shared keys, RBAC + Managed Identity only | Lab doesn't disable shared keys; production would eliminate them after confirming all clients use RBAC. |
| Public endpoint | Firewall applied but endpoint exists | No public endpoint registered in DNS/portal | Firewall blocks access but endpoint still resolvable; production would remove public endpoint entirely. |
| SAS token scope | Not addressed | Time-bound, IP-scoped SAS with specific container/blob | Lab creates dev-assets container for token testing; actual token scoping taught in Module 1 (Identities). |
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
