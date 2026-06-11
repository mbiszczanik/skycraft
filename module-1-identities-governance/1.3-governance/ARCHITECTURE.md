# Architecture Notes: Lab 1.3 — Governance

> Learning context. These notes explain the reasoning behind the lab's design and how it would change in a real environment. The lab deliberately favors clarity over production hardening.

## 1. Design decisions & trade-offs

| Decision | Choice in this lab | Alternatives considered | Why this choice (in a learning context) |
|---|---|---|---|
| Tag taxonomy | Four keys (Environment, Project, CostCenter, Owner) applied at RG scope via `modules/tags.bicep` (lines 57–79 in main.bicep); values defined in varTagsDev, varTagsProd, varTagsPlatform | Minimal tagging (only Environment); extensive taxonomy (20+ keys covering app, team, cost driver, data classification) | Four keys balance clarity and manageability. Lab demonstrates tag inheritance via Bicep; production would enforce via policy. |
| Lock level | `CanNotDelete` on prod and platform RGs (line 17 in `modules/locks.bicep`) | `ReadOnly` (prevents any modification); no locks on dev RG | `CanNotDelete` prevents accidental RG deletion but allows resource updates. Dev RG left unlocked for experimentation. `ReadOnly` is stricter but breaks legitimate updates (e.g., scaling a VM). |
| Policy assignments at subscription scope | Three policy assignments (lines 24–87 in `modules/policies.bicep`): Require Environment tag on RGs, Enforce Project=SkyCraft tag on resources, Restrict to allowed locations (swedencentral, northeurope) | Management group scope (applies across subscriptions); custom policy definitions; audit-only vs deny effect | Subscription scope is appropriate for a single-tenant learning project. Policy definitions (96670d01-0a4d-4649-9c89-2d3abc0a5025, etc.) are built-in Microsoft definitions; custom policies add maintenance burden. Audit-only would allow non-compliant resources (defeats governance goal); Deny blocks creation, teaching hard constraints. |
| Policy effect mode | Deny (implicit, via "Require" and "Enforce" built-in policy definitions) | Audit (log violations but allow creation); DeployIfNotExists (auto-remediate by adding missing tags) | Deny educates users immediately about policy; Audit would allow students to bypass. DeployIfNotExists is safer for auto-remediation but adds complexity. |
| Geographic scope | Two allowed locations: Sweden Central (primary) and North Europe (failover region, line 86–87 in main.bicep) | Single region (swedencentral only); EU-wide (all European regions) | Two regions teach geo-redundancy; single region keeps the lab simple. Restricting to EU demonstrates data residency governance (relevant for GDPR labs in later modules). |
| Module scoping | Tags applied per RG via separate module calls (modTagsDev, modTagsProd, modTagsPlatform); locks applied per RG; policies applied at subscription scope once | Single module applying tags/locks/policies to all RGs; centralized policy assignment in separate stack | Per-RG modularity teaches that tags and locks are RG-scoped, while policies are subscription-scoped. Separate calls make the targeting explicit. |

## 2. Lab simplifications vs production

| Aspect | What the lab does | What production would require | Why it matters |
|---|---|---|---|
| Tag compliance enforcement | Azure Policy enforces two tag presence rules (Environment, Project); other tags (CostCenter, Owner) are applied but not enforced by policy | Comprehensive tag compliance: all four mandatory tags enforced by policy with denial; cost allocation tags mapped to billing export | Lab demonstrates policy basics; production must enforce all compliance tags to prevent billing misallocation and cost center disputes. |
| Lock granularity | Locks at resource group scope (entire RG protected by CanNotDelete) | Locks at individual resource scope (e.g., lock only the production SQL database, allow RG operations); combination of CanNotDelete and ReadOnly per resource type | Lab simplicity: one lock per RG. Production protects critical resources only, allowing other resources to be updated/deleted (reduces accidental blocks). |
| Policy scope and nested governance | Policies assigned at subscription scope; applies uniformly to all RGs | Policy assignments at management group scope for multi-subscription rollout; policy exceptions via exemptions; tiered policies (strict on prod, audit-only on dev) | Single subscription lab has no scope advantage. Enterprise with 50+ subscriptions centralizes governance at management group. Exemptions allow controlled "break glass" for temporary overrides. |
| Custom policies & initiatives | Lab uses three built-in policy definitions; no custom policies | Custom policy definitions (e.g., "VM must be in an availability set"); policy initiatives grouping related policies (e.g., "Security Baseline" = 10 policies bundled) | Built-in policies are discoverable and battle-tested. Custom policies are useful for org-specific rules (e.g., "all databases must have customer-managed keys"). Lab keeps it foundational. |
| Cost controls & budgets | Lab title mentions budgets and Azure Advisor (objectives), but Bicep does not deploy them; lab guide Section 4 covers manual budget creation in portal | Bicep deployment of budget alerts; cost anomaly detection; reserved instances; rightsizing recommendations from Advisor | Lab defers cost controls to manual setup (portal only). Production automates budget thresholds and connects to alerts/webhooks for immediate escalation. |
| Audit logging & reporting | Lab does not explicitly configure Activity Log export or diagnostic settings | Send Activity Log to Log Analytics workspace; query via KQL (e.g., "show all policy violations in the last 7 days"); set up alerts for policy assignment changes | Governance must be auditable; lab focuses on enforcement mechanism, not audit trail. |
| Deny assignment or policy exceptions | No deny assignments; no policy exemption mechanism configured | Deny assignments for explicit "no" (e.g., block delete on sensitive resources even for Owner); policy exemptions for time-limited overrides (e.g., "allow non-compliant VM during incident response") | Lab keeps deny/exemptions out of scope. Real governance uses both to balance security with operational agility. |

## 3. Well-Architected lens (light)

- **Dominant pillar**: Operational Excellence and Governance. Lab establishes naming conventions, tagging for cost tracking, policy enforcement, and resource protection.
- **Security tension**: Locks prevent accidental deletion but also block legitimate updates; balancing is a design trade-off (CanNotDelete vs ReadOnly).
- **Cost alignment**: Tags enable cost allocation by environment and cost center; policies restrict deployment to approved (cheaper) regions.
- **Compliance**: Policy assignments enforce tag presence and geographic boundaries, supporting future audit and regulatory requirements.

## 4. Cost / FinOps note

**Monthly cost of running Lab 1.3 resources**:
- Azure Policy: **Free** (built-in policies incur no compute charge; assignment at subscription scope is no-cost).
- Resource Locks: **Free** (management locks are a metadata feature; no per-lock fee).
- Tags: **Free** (name-value pairs stored as resource metadata).
- **Total governance overhead**: EUR 0.00/month.

**Cost control strategy**:
- This lab enforces **allowed locations** (swedencentral + northeurope). Enforcement prevents accidental deployment to premium regions (e.g., West US 2).
- The **policy restriction** ensures all SkyCraft resources land in cost-optimized European regions.
- No auto-shutdown or time-based scaling is configured; lab resources are expected to be cleaned up after the lab ends.

**Cleanup reminder** (post-lab):
- **Subscription-level artifacts**: Policy assignments (three assignments created by `modules/policies.bicep`) persist at subscription scope and should be deleted via Azure Portal → Policy → Assignments → select each SkyCraft policy → Delete.
- **RG-level artifacts**: Locks and tags are scoped to RGs (dev-skycraft-swc-rg, prod-skycraft-swc-rg, platform-skycraft-swc-rg) and are deleted automatically when RGs are deleted.
- **To fully clean up**: Delete the three resource groups (RGs are NOT automatically deleted); this will cascade-delete all locks, tags, and policy data within those RGs. Then delete the three subscription-scoped policy assignments.
- **Cost risk if not cleaned up**: Zero (governance constructs are free), but policy assignments may interfere with other projects if left assigned.
