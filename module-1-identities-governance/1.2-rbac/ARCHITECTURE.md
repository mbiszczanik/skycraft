# Architecture Notes: Lab 1.2 — RBAC

> Learning context. These notes explain the reasoning behind the lab's design and how it would change in a real environment. The lab deliberately favors clarity over production hardening.

## 1. Design decisions & trade-offs

| Decision | Choice in this lab | Alternatives considered | Why this choice (in a learning context) |
|---|---|---|---|
| Role assignment scope | Mixed: subscription scope (Owner on admin user), resource group scope (Contributor on DevRG, Reader on TestRG) | All at subscription scope; all at RG scope | Mixed scopes teach the principle of least privilege: admin gets subscription-wide Owner; developers get only RG-level Contributor. Reflects real-world job boundaries. |
| Built-in vs. custom roles | Owner, Contributor, Reader (built-in, lines 41–43 in `role-assignments.bicep`) | Custom role (e.g., "VM Operator" with only VM mgmt permissions) | Built-in roles are discoverable and well-documented. Custom roles are needed later when granularity exceeds built-in coverage; keeping to built-in simplifies the lab. |
| Group-based vs. principal-based assignment | Groups assigned to RGs (SkyCraft-Developers → Contributor on dev RG; SkyCraft-Testers → Reader on both dev and prod RGs) | Individual user assignments; service principal assignments | Group-based simplifies role management: adding/removing users from a group updates all associated role assignments without modifying RBAC directly. |
| Idempotency via `guid()` | Role assignment name computed with `guid(resourceGroup().id, parPrincipalId, parRoleDefinitionId)` (line 23 in `rg-role-assignment.bicep`) | Sequential naming (role-assignment-1, role-assignment-2); random GUIDs | `guid()` ensures the same assignment request re-applies idempotently (Bicep upserts the same resource). Prevents accidental duplicates on re-deployment. |
| API version for role assignments | `Microsoft.Authorization/roleAssignments@2022-04-01` (line 22 in `rg-role-assignment.bicep`) | @2021-10-01 or earlier | 2022-04-01 is stable and widely used; includes principalType parameter (User/Group/ServicePrincipal) for validation. |

## 2. Lab simplifications vs production

| Aspect | What the lab does | What production would require | Why it matters |
|---|---|---|---|
| Principal IDs as parameters | Bicep expects pre-computed principal IDs (parAdminPrincipalId, parDeveloperGroupPrincipalId, etc.) passed from a script | Lookup of users/groups by name within Bicep; integration with Entra ID API; service principals registered in the tenant | Manual principal ID collection is error-prone; production tools (Terraform, AzureRM PowerShell) resolve principal names automatically. |
| Scope hierarchy | Three RGs (dev, prod, platform); admin at subscription, developers at dev RG, testers at dev + prod RGs | Management groups layered above subscription (e.g., tenant-wide policies); cross-subscription delegated access; conditional access policies | Management groups allow policy inheritance across multiple subscriptions; realistic for large enterprises. |
| Role audit trail | Portal shows role assignments; lab does not configure continuous audit logging | Enable Azure AD audit logs; stream to Log Analytics; query via KQL for compliance reporting | Tracks who made access changes and when; critical for SOC 2 / ISO 27001. |
| Time-bound access | All assignments are permanent | Privileged Identity Management (PIM) for time-limited role activation; conditional access for time-based access gates | Lab user has permanent Contributor; production elevates to Contributor only during maintenance windows. |
| Deny assignments | Not used in this lab | Deny assignments to explicitly block an action (e.g., deny subscription-wide deletion) even if a role grants it | Deny supplements Allow; lab keeps it simple with Allow-only. Real-world risk mitigation often uses Deny (e.g., prevent production resource deletion even from Owner role). |

## 3. Well-Architected lens (light)

- **Dominant pillar**: Security. The lab is a direct application of least privilege — admin at subscription Owner, developers scoped to a single resource group, testers limited to Reader.
- **Separation of duties**: Group-based assignment (Developers → Contributor, Testers → Reader) keeps "who can change what" auditable and decoupled from individual identities.
- **Operational tension**: Permanent assignments are simple but stand against the production norm of just-in-time access; PIM is the intended evolution for any standing privileged role.
- **Compliance**: Role-assignment history and deny assignments (out of scope here) are what auditors look for; the lab's explicit scoping makes that trail easy to add later.

## 4. Cost / FinOps note

**Monthly cost of running Lab 1.2 resources**:
- Azure RBAC and role assignments: **Free** (role assignments are control-plane metadata; there is no per-assignment charge at any scope).
- Built-in roles (Owner, Contributor, Reader): **Free** (no cost to use or assign).
- Privileged Identity Management (referenced for time-bound access, not configured): **Licensed** — requires Entra ID P2 (~€7.60/user/mo). Not billed in this lab.
- **Total access-control overhead**: EUR 0.00/month.

**Cost control strategy**:
- RBAC itself is a zero-cost governance layer; the FinOps value is indirect — correct scoping prevents costly mistakes (e.g., a developer accidentally deleting production resources).
- If PIM is later adopted, license only the few principals that hold standing Owner/Contributor rather than the whole directory.

**Cleanup reminder** (post-lab):
- Remove the role assignments created by `role-assignments.bicep` (subscription- and RG-scoped) if the practice subscription is shared.
- Deleting the three resource groups cascades their RG-scoped assignments automatically; the subscription-scoped Owner assignment must be removed manually.
- **Cost risk if not cleaned up**: Zero (RBAC is free), but stale assignments are a security and audit liability.
