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
