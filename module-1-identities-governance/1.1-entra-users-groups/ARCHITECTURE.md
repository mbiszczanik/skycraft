# Architecture Notes: Lab 1.1 — Entra Users and Groups

> Learning context. These notes explain the reasoning behind the lab's design and how it would change in a real environment. The lab deliberately favors clarity over production hardening.

## 1. Design decisions & trade-offs

| Decision | Choice in this lab | Alternatives considered | Why this choice (in a learning context) |
|---|---|---|---|
| User principal naming | `firstname.lastname@[tenant].onmicrosoft.com` (Warcraft personas: Malfurion, Khadgar, Chromie, Illidan) | UPN formats (smith.john@company.com, jsmith@example.com) | Warcraft personas create memorable teaching personas tied to roles (Owner, Contributor, Reader, Guest per SPECIFICATION.md §3.2). Simplifies storytelling and role mapping. |
| Group membership strategy | Direct member assignment (Assigned type); one-to-one persona→group mapping | Dynamic group rules (e.g., based on department attributes); nested groups | Static assignment is transparent and predictable for a lab. Production would use dynamic membership rules to reduce manual maintenance. |
| Guest user model | B2B invite model (`Invite external user`) sent to `istormrage@illidari.com` | Guest account already in tenant; federated identity | B2B invitation teaches external partner workflows; real scenarios often involve cross-tenant federated access. |
| MFA/Conditional Access scope | Portal shows conditional access options; lab mentions "delegated administration" but does not require MFA setup | Enforce MFA on all users; conditional access policies requiring MFA for risky logins | Lab focuses on user/group structure basics; MFA policies are typically org-wide settings configured separately. |

## 2. Lab simplifications vs production

| Aspect | What the lab does | What production would require | Why it matters |
|---|---|---|---|
| User lifecycle | Manual creation in portal (via wizard) | Automated provisioning via Entra Connect, Okta, or Workday sync; bulk import via PowerShell | Reduces toil; syncs on-premises AD or HR systems. |
| Group membership dynamics | Assigned (manual) membership; one user per group | Dynamic groups (e.g., "all employees in Finance"), nested groups (e.g., Admin group contains Department-Admin subgroups) | Scaling to hundreds/thousands of users requires automation; nested groups model org hierarchy. |
| License assignment | Manual assignment per user (mentioned in objectives) | Group-based licensing; conditional license provisioning | Group-based licensing avoids manual churn when users move roles. |
| Guest access governance | Simple invitation with custom message | Conditional access policies, entitlement reviews, time-limited access, B2B direct connect | Guests represent external risk; production limits their scope and requires periodic access reviews. |
| Auditing & logging | Lab does not explicitly configure audit logging | Enable Entra ID audit logs, configure Azure AD Sign-in logs, export to SIEM | Forensic trace of who accessed what and when; regulatory requirement in most enterprises. |

## 3. Well-Architected lens (light)

- **Dominant pillar**: Security and Operational Excellence. Identity is the real perimeter; users and groups are the foundation every later access decision builds on.
- **Security tension**: The lab favors transparent, manually assigned membership over automation. That clarity helps learning but skips the controls (MFA, Conditional Access, access reviews) that make identity safe at scale.
- **Operational alignment**: Group-based assignment keeps later RBAC and licensing manageable — change the group, not every user. Dynamic membership and HR-driven provisioning are the production evolution.
- **Compliance**: Audit logging and periodic access reviews are out of scope here but are mandatory in regulated tenants; the lab structure is designed so they can be layered on without rework.

## 4. Cost / FinOps note

**Monthly cost of running Lab 1.1 resources**:
- Entra ID users (cloud-only) and security groups: **Free** (directory objects in the Entra ID Free tier carry no per-object charge).
- B2B guest invitation: **Free** under the standard external-identities model (the first 50,000 monthly active external users are free; this lab uses one guest).
- MFA / Conditional Access / PIM (mentioned but not enabled): **Licensed** — require Entra ID P1 (Conditional Access, ~€5.10/user/mo) or P2 (PIM, Identity Protection, ~€7.60/user/mo). Not billed in this lab because they are not configured.
- **Total identity overhead**: EUR 0.00/month.

**Cost control strategy**:
- The lab stays entirely within the Entra ID Free tier; no premium licenses are assigned, so there is no recurring cost.
- Treat P1/P2 as a deliberate, per-user decision: license only the identities that need Conditional Access or PIM rather than blanket-assigning the whole tenant.

**Cleanup reminder** (post-lab):
- Delete the created users (Malfurion, Khadgar, Chromie, Illidan) and the guest invite to keep the tenant tidy; directory objects are free but accumulate.
- Remove the security groups once role-mapping practice is done.
- No resource groups or billable Azure resources are created by this lab, so there is **no cost risk** if cleanup is skipped — only directory clutter.
