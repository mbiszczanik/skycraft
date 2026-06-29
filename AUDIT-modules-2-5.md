# SkyCraft Audit — Modules 2–5: Lab Guide vs Scripts/Bicep

**Scope:** 14 labs (2.1–5.3). Lab guides + checklists + ARCHITECTURE.md vs the actual `*.bicep`, `Deploy-*.ps1`, `Test-Lab.ps1`, `Remove-LabResource.ps1`.
**Method:** 14 per-lab audit agents → 14 adversarial verify agents (every finding re-checked against the repo) → synthesis → completeness critique.
**Result:** **187 verified findings** across 14 labs, plus **9 systemic gaps the audit itself missed** (see §5 — several are hard deploy-breakers).

---

## 1. Executive summary

The single most dangerous theme is **false-pass gating**: five validators (`2.1, 2.2, 3.1, 4.3, 4.4` `Test-Lab.ps1`) print `[FAIL]` but never keep a failure counter and never `exit` non-zero. Because the orchestrator (`master-lab-cycle.ps1:163`) derives PASS/FAIL purely from the child exit code, those steps are reported **PASS even when every resource is missing** — masking every other defect in those labs.

On top of that there is a cluster of **broken-deploy / destructive-cleanup** issues:
- **4.3 cleanup deletes the entire shared `prod-skycraft-swc-rg`**, destroying Lab 4.1's storage account that 4.2/4.4 depend on.
- **4.4 never enables the `Microsoft.Storage` service endpoint** its VNet firewall rule depends on.
- **3.2 default VM size `Standard_B2s`/`B2ms` is `SkuNotAvailable`** in Sweden Central.
- **3.1 `parEnvironment` is ignored** — `prod.bicepparam` deploys zero prod resources.
- **2.2 / 3.1 cleanups leak or orphan** resources every cycle.

The two largest recurring classes are doc-quality but consequential: **az-cli-leftover (27)** carries a real wrong-subscription hazard, **cross-reference-drift (35)** is pure documentation drift.

Worst labs: **4.4** and **5.3** (broken across deploy, naming, validation and prereqs), then **4.3** (false-pass + destructive cleanup + property-read bugs).

---

## 2. Critical findings (6) — all false-pass gating

| Lab | File | Problem | Fix |
|-----|------|---------|-----|
| 2.1 | `2.1-virtual-networks/scripts/Test-Lab.ps1` | 17 `[FAIL]` branches, no counter, no exit; line 41 `return` | Add `$failCount`, `exit $failCount`; gate the `return` |
| 2.2 | `2.2-secure-access/scripts/Test-Lab.ps1` | Prints `[FAIL]`, always PASS; everything swallowed by `-EA SilentlyContinue` | Add `$failCount`/`exit`; stop swallowing `Get-Az*` |
| 3.1 | `3.1-infrastructure-as-code/scripts/Test-Lab.ps1` | No failCount/exit; missing-RG `return` (55) | Add `$failCount`/`exit`; count the missing-RG path |
| 4.3 | `4.3-azure-files/scripts/Test-Lab.ps1` | No counter/exit; storage catch `return` (65) | Mirror 4.1/4.2: `$failCount`/`exit` |
| 4.4 | `4.4-storage-security/scripts/Test-Lab.ps1` | `[WARNING]`/`[ERROR]` paths never fail the step | Add `$failCount`/`exit` |
| 2.1 | `2.1-virtual-networks/scripts/Deploy-Bicep.ps1` | No `exit 1` on non-`Succeeded` provisioning (medium-rated but same gating class) | Add `exit 1` to the non-Succeeded else branch |

> The orchestrator gating bug itself was already fixed earlier (`exit $LASTEXITCODE`). These are the **child scripts** that still never produce a non-zero code, so the fix has nothing to act on.

---

## 3. Findings by class

| Class | Count | One-line | Labs |
|-------|:---:|----------|------|
| **false-pass-gating** | 6 | Validators print `[FAIL]` but exit 0 → orchestrator marks PASS | 2.1, 2.2, 3.1, 4.3, 4.4 |
| **az-cli-leftover** | 27 | Learner/validation/header commands use `az` (wrong subscription on this machine) | all 14 |
| **cross-reference-drift** | 35 | Guides/checklists/diagrams disagree with deployed reality or each other | all 14 |
| **validation-coverage** | 24 | Test-Lab checks existence/counts but skips stated success criteria (tags, SKU, tier, soft delete, RBAC…) | all 14 |
| **other** | 24 | Misleading `.DESCRIPTION`, `Read-Host` in orchestrated scripts, no-op `-WhatIf`, semantic bicep nits | 12 labs |
| **cleanup-gap** | 16 | Cleanup leaks, over-deletes, or cannot complete (soft-delete/purge) | 13 labs |
| **resource-coverage** | 15 | Resources deployed-but-undocumented or documented-but-never-deployed | 10 labs |
| **naming-mismatch** | 13 | Docs/tests reference names that differ from deployed reality | 8 labs |
| **property-read-bug** | 7 | Reads off wrong object level / non-existent property → always-false checks | 2.2, 3.4, 4.3, 4.4, 5.1, 5.2 |
| **environment-mismatch** | 7 | The "prod" path is broken or relabels dev resources | 3.1, 3.2, 3.4, 4.1, 5.2, 5.3 |
| **prerequisite-mismatch** | 7 | Guide Prerequisites under/over-state real deploy dependencies | 2.2, 3.1, 3.2, 3.3, 4.3, 5.2, 5.3 |
| **policy-tag-gap** | 6 | Imperative/bicep creates omit/lowercase the `Project=SkyCraft` tag | 2.3, 3.1, 3.2, 5.1, 5.3 |

---

## 4. Top priorities (do these first)

1. **Fix false-pass gating** in `Test-Lab.ps1` for 2.1, 2.2, 3.1, 4.3, 4.4 (`$failCount` + `exit $failCount`). Everything else is masked until this lands.
2. **Stop 4.3 cleanup deleting the shared prod RG** — scope it to the two 4.3 shares only; never `Remove-AzResourceGroup prod-skycraft-swc-rg`.
3. **Add the `Microsoft.Storage` service endpoint on WorldSubnet** in 4.4 `security.bicep` — the storage firewall rule depends on it.
4. **Change 3.2 default VM size** off `B2s`/`B2ms` to `Standard_D2s_v3` in `Deploy-Bicep.ps1`, `main.bicep`, `Enable-Encryption.ps1`.
5. **Make 3.1 honour `parEnvironment`** (prod path deploys nothing) and fix default cleanup orphaning platform/prod RGs.
6. **Fix 2.2 cleanup no-op** — removal gated on `-RemoveAll` the orchestrator never passes (leaks 6 spoke NSGs + hub NSG + 6 ASGs each cycle).
7. **Add `exit 1`** to 2.1 `Deploy-Bicep.ps1` non-Succeeded branch.
8. **Resolve 3.3 ACA/CAE `-02` naming drift** across bicep, Deploy-Containers, Test-Lab, Remove.
9. **Fix 4.3 property-read bugs** (`.FileService`, keyless `$share.Quota/.AccessTier`) — soft-delete & quota/tier validation are permanently non-functional.
10. **Convert all `az`-CLI validation/deploy blocks to Az PowerShell** (27 findings; wrong-subscription hazard) — start with checklist Validation Commands.
11. **Fix 5.3 prereq/coverage break** — Deploy hard-fails without Storage/LAW/prod-VNet/two VMs the guide never lists; guide describes a different (portal-only) lab than automation builds.
12. **Correct 4.2 game-assets Public/Private contradiction** (docs say "Public: Blob" vs deployed Private) — learner-induced security regression.

---

## 5. Completeness critique — 9 systemic gaps the audit MISSED

These are **not** in the 187 and several are **hard deploy-breakers** under the Lab 1.3 governance policies:

1. **az-cli-leftover undercounted (~27 → ~34).** All 16 `bicep/main.bicep` carry an `EXAMPLE: az deployment sub create` header; the sweep flagged only ~half. Missed: 3.1/3.2/3.3/3.4 `main.bicep:4`, 4.2/4.3 `main.bicep:5`, 4.4 `main.bicep:6`.
2. **policy-tag-gap only checks `Project` — the other two DENY policies are ignored.**
   - **Require-Environment-Tag-RG (deny):** `5.3 Deploy-Bicep.ps1:165` creates `NetworkWatcherRG` with **no tags at all** → denied by Environment-RG *and* Project policies = hard deploy failure. `3.3 Deploy-Bicep.ps1:81` creates its RG with `Project` only (no `Environment`) → also deniable.
   - **Restrict-Azure-Regions (deny) = {swedencentral, northeurope}.** Yet ~14 Deploy scripts `[ValidateSet('swedencentral','westeurope','northeurope')]` — **`westeurope` is offered but DENIED**; any `-Location westeurope` run fails wholesale. 5.2's documented ASR "Norway East" is also outside the allow-list.
3. **Deploy-layer false-pass assessed for only 2.1.** The orchestrator gates on exit code for *every* step. `2.3, 3.2, 3.4, 4.2, 4.3, 4.4` Deploy scripts have **no ProvisioningState verification at all** (rely on the cmdlet throwing). Especially re-check 3.2 (the SkuNotAvailable failure — does it actually exit non-zero?).
4. **False-pass-adjacent bugs scattered into other classes.** `3.3 Test-Lab` (ACI non-Succeeded = WARNING only), `5.1 Test-Lab:170` (`@($null).Count==1`), `3.4 Test-Lab` (`[0]` index, dead else) — all can silently skip assertions. Re-audit all 9 "gated" Test-Labs for unreachable failCount increments.
5. **Region/SKU capacity checked only for the 3.2 VM.** Not re-checked: App Service Plan `P0V4` (3.4), prod VMSS SKU (3.2 docs), auth/world VM redeploys referenced by 5.1/5.2/5.3.
6. **Secrets/credential handling entirely unaudited.** `parSshPublicKey` (3.2), stale "SSH-key generation" claim (3.1). Check bicep params / `*.bicepparam` / Key Vault refs for plaintext secrets, missing `@secure()`, admin passwords in source.
7. **Cross-lab ownership of the shared platform RG / hub VNet is unmapped.** Beyond the two found, re-check whether 3.1 (or others) `Remove-LabResource` can delete a hub VNet that Module 2 created and Module 5 still depends on.
8. **Idempotency across cycles flagged only once (5.2 `.FriendlyName`).** Re-check second-run throws: RBAC role-assignment creates (4.4), ACR image import (3.3 `Deploy-Containers.ps1`), DNS/private-link creates (2.3 `Deploy-DNS.ps1:175`).
9. **Suspiciously thin labs to re-open:** 4.2 (9 — lifecycle policy/versioning/immutability unexplored), 3.3 (11 — ACR admin-user, `publicNetworkAccess`, image provenance got no security review).

> Lower-confidence: the report's claim that the 5.1 DCR association is "exempt" from the tag-deny policy is asserted, not verified — confirm before treating as no-fix.

---

## 6. Per-lab findings (full)

Severity legend: 🔴 critical · 🟠 high · 🟡 medium · ⚪ low. Each line: `[class] title — file → fix`.

### Lab 2.1 — Virtual Networks (17)
- 🔴 [false-pass-gating] Test-Lab never exits non-zero → `Test-Lab.ps1` → add `$failCount` + `exit`, gate line 41 `return`.
- 🟠 [az-cli-leftover] Entire checklist Validation Commands use az → `lab-checklist-2.1.md` (224–382) → rewrite as `Get-Az*`.
- 🟠 [cross-reference-drift] Guide says 3 subnets/spoke; reality is 4 (AppServiceSubnet) → `lab-guide-2.1.md` (246/323/345/368/798) → fix to 4 / 10 total.
- 🟠 [cross-reference-drift] Architecture mermaid + embedded checklist omit AppServiceSubnet → `lab-guide-2.1.md` (30–32/37–39/599–611) → add subnet.
- 🟠 [validation-coverage] Checklist expected outputs claim 3 spoke subnets → `lab-checklist-2.1.md` (264–319/390–402) → include AppServiceSubnet.
- 🟠 [naming-mismatch] Checklist requires gateway transit/use-remote-gateway Enabled; deploy disables both → `lab-checklist-2.1.md` (59/65/115/165, mermaid 42–43) → "Disabled".
- 🟡 [cross-reference-drift] Duplicate "Prod LB Public IP" block in Step 2.1.12 → `lab-guide-2.1.md` (507–519) → delete + renumber.
- 🟡 [resource-coverage] Deploy-Networking `.DESCRIPTION` claims a Bastion PIP it never creates → `Deploy-Networking.ps1:14` → remove or create.
- 🟡 [other] Deploy-Bicep header wrong subnet counts; omits Dev VNet/PIPs/DevResourceGroup → `Deploy-Bicep.ps1` → fix `.DESCRIPTION`.
- 🟡 [false-pass-gating] Deploy-Bicep no `exit 1` on non-Succeeded → `Deploy-Bicep.ps1` (100–121) → add `exit 1`.
- 🟡 [cleanup-gap] Peering-removal filter `-match 'peer'` matches nothing (dead code) → `Remove-LabResource.ps1:67` → remove filter.
- 🟡 [validation-coverage] Test validates no tags despite policy → `Test-Lab.ps1` → add Project/Environment/CostCenter checks.
- ⚪ [az-cli-leftover] Troubleshooting Issue 6 `az network watcher configure` → `lab-guide-2.1.md` (766–769) → Az equivalent.
- ⚪ [az-cli-leftover] main.bicep header EXAMPLE `az deployment sub create` → `bicep/main.bicep:4` → Deploy-Bicep path.
- ⚪ [cross-reference-drift] Step numbering skips 2.1.13 → `lab-guide-2.1.md` → resequence.
- ⚪ [other] AppServiceSubnet created without delegation (diverges from bicep) → `Deploy-Networking.ps1` (108/129) → add `Microsoft.Web/serverFarms` delegation.
- ⚪ [cross-reference-drift] ARCHITECTURE cites wrong lines for allowForwardedTraffic → `ARCHITECTURE.md` → fix ref + "Allow Gateway Transit" label.

### Lab 2.2 — Secure Access (16)
- 🔴 [false-pass-gating] Test-Lab prints `[FAIL]` but never exits → `Test-Lab.ps1` → `$failCount`/`exit`, stop `-EA SilentlyContinue`.
- 🟠 [cleanup-gap] Cleanup no-op: gated on `-RemoveAll` the orchestrator never passes → `Remove-LabResource.ps1` → remove gate / pass switch.
- 🟡 [resource-coverage] Prod ASGs deployed/validated but absent from docs → `Deploy-Security.ps1` → document 3 prod ASGs (sign-off 504).
- 🟡 [resource-coverage] `platform-skycraft-swc-nsg` (hub NSG) undocumented → `security-hub.bicep` → document; fix guide 1028 to 7 NSGs.
- 🟡 [cross-reference-drift] ARCHITECTURE self-contradicts on hub NSG count (1 vs 3) and total (9 vs 7) → `ARCHITECTURE.md:47` → "1 Hub + 6 Spokes = 7".
- 🟡 [cross-reference-drift] Bastion mandatory in docs, optional/off in automation → `lab-guide-2.2.md` (500) → mark optional (`parDeployBastion=false`).
- 🟡 [az-cli-leftover] Checklist Validation Commands all az → `lab-checklist-2.2.md` (208–343) → `Get-Az*`.
- 🟡 [validation-coverage] Test skips SSH-from-Bastion rule, source prefixes, tags → `Test-Lab.ps1` → add checks.
- ⚪ [az-cli-leftover] main.bicep header `az deployment sub create` → `bicep/main.bicep:4` → Deploy-Bicep path.
- ⚪ [resource-coverage] Bicep adds Microsoft.Storage SE to WorldSubnet guide omits & script doesn't create → `security-spoke.bicep` → converge paths.
- ⚪ [naming-mismatch] Bastion + PIP tagged Environment=Production instead of Platform → `Deploy-Security.ps1` (276/295) → Platform tags.
- ⚪ [cleanup-gap] Even with `-RemoveAll`, SEs never removed; "clear NSG rules" step missing → `Remove-LabResource.ps1` (11–12) → fix.
- ⚪ [other] Interactive `Read-Host` prompts in orchestrated scripts → `Deploy-Bicep.ps1:79`, `Deploy-Security.ps1:265` → `-DeployBastion` switch.
- ⚪ [property-read-bug] SEs assigned as raw hashtables; failure swallowed; location hardcoded → `Deploy-Security.ps1` (231–239) → re-throw/count, use `$Location`.
- ⚪ [prerequisite-mismatch] Bastion branch hard-exits if AzureBastionSubnet missing (not in Prereqs) → `Deploy-Security.ps1` → list or soften.
- ⚪ [other] Bastion Basics table lists "Instance count: 2" under Basic SKU → `lab-guide-2.2.md` (446–447) → remove row.

### Lab 2.3 — Name Resolution (14)
- 🟡 [policy-tag-gap] `New-AzPublicIpAddress` fallback creates LB PIP with no Project tag (policy deny) → `Deploy-LoadBalancer.ps1:91` → add `-Tag $Tags`.
- 🟡 [az-cli-leftover] Entire Validation Commands use az → `lab-checklist-2.3.md` (211–369) → `Get-Az*`.
- 🟡 [validation-coverage] Private DNS A records dev-db/prod-db never validated → `Test-Lab.ps1` → add record-set checks.
- 🟡 [validation-coverage] Test doesn't validate 2 backend pools or frontend IP → `Test-Lab.ps1` → assert pools/frontend.
- 🟡 [cross-reference-drift] Guide marks CNAME/auth pool "Optional" but scripts+Test require → `lab-guide-2.3.md` (2.3.4/2.3.12) → remove "(Optional)".
- ⚪ [az-cli-leftover] main.bicep header `az deployment sub create` → `bicep/main.bicep:4` → Deploy-Bicep path.
- ⚪ [validation-coverage] NS count + resource tags not validated → `Test-Lab.ps1` → add (4 NS) + tags.
- ⚪ [cleanup-gap] Cleanup removes LBs but not auto-created LB PIP → `Remove-LabResource.ps1` → add PIP removal.
- ⚪ [other] Bicep tags dev LB + DNS zones Environment=Production → `bicep/main.bicep` → parameterise per resource.
- ⚪ [policy-tag-gap] Bicep VNet links + A records carry no tags → `dns-private.bicep` → add `tags: parTags`.
- ⚪ [cross-reference-drift] Inconsistent placeholder LB IPs; record count off by one → `lab-guide-2.3.md` → unify; checklist NumberOfRecordSets=3.
- ⚪ [other] Dead cleanup of `lb.json` never created → `Deploy-LoadBalancer.ps1:133` → delete line.
- ⚪ [other] VNet "not found" branch unreachable (no `-EA SilentlyContinue`) → `Deploy-DNS.ps1:173` → add flag.
- ⚪ [other] Stream-of-consciousness dev comments in template → `bicep/main.bicep` (77–83) → real docs.

### Lab 3.1 — Infrastructure as Code (13)
- 🔴 [false-pass-gating] Test-Lab prints `[FAIL]` but no failCount/exit → `Test-Lab.ps1` → add; replace missing-RG `return` (55).
- 🟠 [environment-mismatch] `parEnvironment` required but ignored; `prod.bicepparam` deploys no prod resources → `bicep/main.bicep` → parameterise or document dev-only. **(needs-decision)**
- 🟠 [cleanup-gap] Default cleanup (`-Environment dev`) orphans platform (hub VNet) + prod RGs → `Remove-LabResource.ps1` → pass `-Environment all` / remove all three.
- 🟡 [resource-coverage] Dev VNet deploys undocumented 4th subnet (AppServiceSubnet) → `bicep/main.bicep` → document checklist 325 / Test 64.
- 🟡 [validation-coverage] Test never validates platform RG / hub VNet / AzureBastionSubnet → `Test-Lab.ps1` → add.
- 🟡 [validation-coverage] Test checks existence/counts, not ports/pools-probes-rules/PIP SKU/Project tag → `Test-Lab.ps1` → assert.
- 🟡 [az-cli-leftover] `Standards.Tests.ps1` shells out to `az bicep build` → line 110 → use `bicep build`.
- 🟡 [az-cli-leftover] Checklist validation/deploy all az → `lab-checklist-3.1.md` (167–366) → `New-Az*`/`Get-Az*`.
- 🟡 [cross-reference-drift] Guide never references the lab's PS scripts; cleanup teaches `az group delete` → `lab-guide-3.1.md` (1549–1551) → reference scripts.
- ⚪ [policy-tag-gap] Project tag lowercase `skycraft` → `bicep/main.bicep` → literal `SkyCraft`.
- ⚪ [cross-reference-drift] Deploy-Bicep help claims SSH-key gen + non-existent Deploy-Infra.ps1 → `Deploy-Bicep.ps1` (6–7/19/70–72) → fix.
- ⚪ [prerequisite-mismatch] Prereqs list VNets/NSGs/LBs as inputs but the lab creates them → `lab-guide-3.1.md` → reframe as outputs.
- ⚪ [resource-coverage] Architecture diagram shows compute.bicep/dns.bicep + Dev/Prod VMs the lab never creates → `lab-guide-3.1.md` (38–62) → trim.

### Lab 3.2 — Virtual Machines (19)
- 🟠 [environment-mismatch] Default `Standard_B2s` is SkuNotAvailable in Sweden Central → `Deploy-Bicep.ps1:54`, `main.bicep:44` → `Standard_D2s_v3`.
- 🟠 [environment-mismatch] ADE resize target `Standard_B2ms` unavailable + unnecessary → `Enable-Encryption.ps1` → drop resize.
- 🟡 [naming-mismatch] Data disk docs `-world-vm-data` vs deployed `-world-datadisk` → `lab-guide-3.2.md` (586/1847, checklist 73/268/320) → fix.
- 🟡 [naming-mismatch] `ManagedBy` tag three different values → `bicep/main.bicep` → standardise `ManagedBy=Bicep`.
- 🟡 [naming-mismatch] Guide verifies a `Role` tag automation never sets (sets `Purpose`) → guide 404 / checklist 43/84 → `Purpose=...`.
- 🟡 [resource-coverage] VMSS described in docs has no automation; prod bicep deploys individual VMs → `bicep/main.bicep` → add module or fix docs.
- 🟡 [validation-coverage] Test validates none of size/OS-disk/tag/encryption/Key Vault → `Test-Lab.ps1` → add.
- 🟡 [cleanup-gap] KV purge broken: purge protection on + tenant GUID as `-Location` → `Remove-LabResource.ps1:135`, `keyvault.bicep:43` → fix.
- 🟡 [az-cli-leftover] Checklist Validation Commands all az → `lab-checklist-3.2.md` → `Get-Az*`.
- 🟡 [az-cli-leftover] Guide uses az for prereqs/encryption/resize/VMSS → `lab-guide-3.2.md` → Az PowerShell.
- 🟡 [cross-reference-drift] OS/data disks "Premium SSD" in checklist/summary vs Standard SSD in bicep → guide 1456/1847 → Standard SSD.
- ⚪ [policy-tag-gap] Project tag lowercase `skycraft` (cosmetic) → `bicep/main.bicep` → `SkyCraft`. **(needs-decision)**
- ⚪ [cross-reference-drift] Duplicate step numbers (two 3.2.10 / two 3.2.20) → `lab-guide-3.2.md` (478/494, 918/1015) → renumber.
- ⚪ [cross-reference-drift] Section 8 title + duration disagree with time-budget → `lab-guide-3.2.md` (102 vs 1156) → reconcile.
- ⚪ [prerequisite-mismatch] Prereq messages misattribute VNet/LB to "Lab 3.1" (deployed by 2.1/2.3) → `Deploy-Bicep.ps1` (107/114/121) → fix.
- ⚪ [other] Inconsistent allowed VM-size lists; D4s_v3 unreachable → `bicep/main.bicep`, `vm.bicep`, Deploy ValidateSet → align.
- ⚪ [other] Empty data disk sets `osType: 'Linux'` → `disk.bicep:60` → remove.
- ⚪ [other] KV "globally unique" comment but no suffix → `bicep/main.bicep` (80–81) → add `uniqueString` or fix comment.
- ⚪ [other] `Read-Host` confirm + no-op `-WhatIf` → `Deploy-Bicep.ps1` (137/160) → `-Force`/real what-if.

### Lab 3.3 — Containers (11)
- 🟠 [naming-mismatch] ACA/CAE deployed with `-02` suffix but docs use non-suffixed → `bicep/main.bicep` (31/34) → converge. **(needs-decision)**
- 🟡 [naming-mismatch] `Deploy-Containers.ps1` produces non-suffixed names Test/Remove can't match → (145–146) → align or retire script.
- 🟡 [cleanup-gap] Cleanup targets only `-02`; guide-following learners' resources never deleted → `Remove-LabResource.ps1` → delete both. **(needs-decision)**
- 🟡 [az-cli-leftover] Checklist validation entirely az → `lab-checklist-3.3.md` (52–93) → `Get-Az*`.
- 🟡 [validation-coverage] ACI failure only a WARNING; image/OS/running-state never validated → `Test-Lab.ps1` → count + assert.
- 🟡 [cross-reference-drift] ACI sizing guide 0.5/0.5 vs bicep 1 CPU/1 GB → `aci.bicep` / guide 3.3.4 → match 1/1.
- ⚪ [validation-coverage] Unvalidated: ACR tag v1, ACR location, ACA replica min/max, scale-rule name, ingress port → `Test-Lab.ps1` → add.
- ⚪ [cross-reference-drift] Lab duration inconsistent (2h/1h/2h) → `lab-guide-3.3.md` → reconcile.
- ⚪ [resource-coverage] Guide builds via `az acr build` from GitHub; automation imports prebuilt MCR image → reconcile provenance.
- ⚪ [prerequisite-mismatch] Prereqs list only Azure CLI, not Az modules → `lab-guide-3.3.md` → add PS7 + Az.* modules.
- ⚪ [other] Typos (Develomplent Stack, assigments) → `lab-guide-3.3.md` (86/209/226) → fix.

### Lab 3.4 — App Service (12)
- 🟠 [cross-reference-drift] Node runtime inconsistent 4 ways (guide 24, checklist 18, arch 20, bicep 20) → set all to Node 20 LTS (guide 156, checklist 27, arch 10).
- 🟡 [az-cli-leftover] Checklist Validation Commands all az → `lab-checklist-3.4.md` (52–101) → `Get-Az*`.
- 🟡 [az-cli-leftover] Guide az prereqs + malformed zip-deploy command → `lab-guide-3.4.md` → fix to `az webapp deploy --src-path … --type zip` or `Publish-AzWebApp`.
- 🟡 [resource-coverage] Guide presents automated Backups step automation never configures → `lab-guide-3.4.md` (13, 3.4.13) → implement or drop. **(needs-decision)**
- 🟡 [environment-mismatch] Deploy `-Environment prod` creates prod-named resources in dev RG/VNet → `Deploy-Bicep.ps1` → derive RG/VNet or restrict ValidateSet.
- ⚪ [property-read-bug] Autoscale check indexes `[0]` on possibly-null array → `Test-Lab.ps1` → guard/try-catch.
- ⚪ [naming-mismatch] In-guide checklist "Standard S1" but lab uses Premium V4 P0V4 → guide 414 → fix.
- ⚪ [resource-coverage] Bicep enables System-Assigned identity guide/test never mention → `app-service.bicep` → document or remove.
- ⚪ [validation-coverage] Test doesn't validate Node runtime/linuxFxVersion → `Test-Lab.ps1` → assert `NODE|20-lts`.
- ⚪ [naming-mismatch] Checklist autoscale "Default-Autoscale"; real `dev-skycraft-swc-asp-autoscale` → checklist 112 → fix.
- ⚪ [cleanup-gap] Remove swallows errors, never exits non-zero → `Remove-LabResource.ps1` (63–66) → `exit 1`.
- ⚪ [cross-reference-drift] Orphan `step-3.4.13.png` / root `image.png` never referenced → reference or delete.

### Lab 4.1 — Storage Accounts (11)
- 🟡 [az-cli-leftover] Entire Validation Commands use az → `lab-checklist-4.1.md` (89–170) → `Get-AzStorageAccount`.
- 🟡 [validation-coverage] Test never validates Access tier = Hot → `Test-Lab.ps1` → add `$sa.AccessTier -eq 'Hot'`.
- ⚪ [az-cli-leftover] Guide az create/verify/key-rotation; verify az-only → `lab-guide-4.1.md` → add PS verification.
- ⚪ [az-cli-leftover] Bicep header EXAMPLE `az deployment sub create` → `bicep/main.bicep` (6–8) → Deploy-Bicep path.
- ⚪ [validation-coverage] Test doesn't validate kind StorageV2 nor file-share soft delete → `Test-Lab.ps1` → add.
- ⚪ [cross-reference-drift] Sign-off lists "(LRS, GRS, GZRS)" but GZRS never deployed → checklist 249 → LRS/GRS only.
- ⚪ [environment-mismatch] Standalone Deploy dev-only while Test validates all three → `Deploy-Bicep.ps1` → default `-All` or default Test to dev.
- ⚪ [cross-reference-drift] Malformed encryption-options markdown table → `lab-guide-4.1.md` (540–544) → fix.
- ⚪ [cross-reference-drift] LRS-vs-GRS savings disagree (60% vs ~50%) → `ARCHITECTURE.md` → reconcile.
- ⚪ [other] Duplicated comment in storage account block → `storageAccount.bicep` (143–144) → delete.
- ⚪ [other] Guide over-states a Module 3 (VMs) dependency → `lab-guide-4.1.md:96` → remove.

### Lab 4.2 — Blob Storage (9)
- 🟠 [cross-reference-drift] Diagram + embedded checklist say game-assets "Public: Blob" but deployed Private → `lab-guide-4.2.md` (27/796) → Private (keep public demo on dev public-demo container).
- 🟡 [validation-coverage] Test never validates soft delete (blobs + containers, 7 days) → `Test-Lab.ps1` → assert retention policies.
- 🟡 [validation-coverage] Test verifies only 1 of 4 required prod containers → `Test-Lab.ps1` → add player-backups/server-config/game-logs.
- 🟡 [az-cli-leftover] Guide primary path az; several steps az-only → `lab-guide-4.2.md` → add PS for soft delete/lifecycle/versioning; fix role-assign (669–674).
- ⚪ [az-cli-leftover] Checklist Validation Commands still include az → `lab-checklist-4.2.md` → add Az twins.
- ⚪ [cross-reference-drift] Inconsistent duration (2h/2.5h/~2h10m) → `lab-guide-4.2.md` → reconcile.
- ⚪ [validation-coverage] Test blob upload + version-on-overwrite required but neither deployed nor validated → `lab-checklist-4.2.md` → deploy+validate or mark manual.
- ⚪ [cleanup-gap] Containers soft-deleted not purged; guide role assignment never removed → `Remove-LabResource.ps1` → purge or document.
- ⚪ [other] Section 3 presents soft delete as newly enabled but on from 4.1 defaults → `lab-guide-4.2.md` → reframe as "verify".

### Lab 4.3 — Azure Files (11)
- 🔴 [false-pass-gating] Test never counts/exits → `Test-Lab.ps1` → `$failCount`/`exit`; replace catch `return` (65).
- 🟠 [property-read-bug] Soft-delete read from non-existent `.FileService` (always-false) → `Test-Lab.ps1` → `Get-AzStorageFileServiceProperty`.
- 🟠 [validation-coverage] Test doesn't validate most Success Criteria → `Test-Lab.ps1` → add quota 100/500, Hot, config.txt, snapshot, tags.
- 🟡 [property-read-bug] Share quota/tier read from wrong level via keyless context → `Test-Lab.ps1` → `Get-AzRmStorageShare` `.ShareProperties`.
- 🟡 [resource-coverage] Directory/file + snapshot from guide never created/validated → `storage.bicep` → create or mark manual.
- 🟡 [az-cli-leftover] Checklist validation az; snapshot/tag az-only → `lab-checklist-4.3.md` → `Get-Az*`.
- 🟡 [cleanup-gap] **Cleanup deletes the entire shared prod RG, destroying 4.1 storage** → `Remove-LabResource.ps1` → scope to the two shares only.
- 🟡 [cross-reference-drift] ARCHITECTURE contradicts guide on snapshots/scope → `ARCHITECTURE.md` → fix.
- ⚪ [other] Architecture diagram shows prod VMs that don't exist → `lab-guide-4.3.md` (36–45) → remove.
- ⚪ [prerequisite-mismatch] Prereqs require Azure CLI although automation is pure Az → `lab-guide-4.3.md:115` → drop.
- ⚪ [cross-reference-drift] Cost note assumes Dev+Prod but lab deploys only prod → `ARCHITECTURE.md` (35–44) → remove Dev line.

### Lab 4.4 — Storage Security (14)
- 🔴 [false-pass-gating] Test never exits non-zero → `Test-Lab.ps1` → `$failCount`/`exit`.
- 🟠 [naming-mismatch] Docs/Test use "ApplicationSubnet" but deployed is "WorldSubnet" → guide 30/108/118/129/178, checklist 9/16 → WorldSubnet.
- 🟠 [property-read-bug] SE check filters non-existent "ApplicationSubnet" (always null) → `Test-Lab.ps1:66` → "WorldSubnet".
- 🟠 [resource-coverage] **Automation never enables the Microsoft.Storage service endpoint the firewall rule depends on** → `security.bicep` → add `serviceEndpoints` to WorldSubnet.
- 🟠 [validation-coverage] Test omits key-rotation/RBAC/dev-assets/IP-rule; synopsis claims an RBAC check that doesn't exist → `Test-Lab.ps1` → add + fix `.DESCRIPTION`.
- 🟠 [cross-reference-drift] Estimated-Time outline ≠ body; Key-Rotation/RBAC sections have no steps → `lab-guide-4.4.md` → add missing steps.
- 🟡 [az-cli-leftover] Checklist + Step 4.4.1 use az (also wrong subnet) → `lab-checklist-4.4.md`, guide 114–119 → Az + WorldSubnet.
- 🟡 [cross-reference-drift] Troubleshooting refs "step 4.4.3" for key rotation but 4.4.3 is Stored Access Policy → `lab-guide-4.4.md` → fix ref.
- 🟡 [cross-reference-drift] "Next Lab" link points to nonexistent `module-5-monitor/...` → `lab-guide-4.4.md:233` → fix to `module-5-monitoring-maintenance/5.1-azure-monitor/`.
- 🟡 [naming-mismatch] Step 4.4.3 says container "scripts" but automation/checklist use "dev-assets" → guide 155 → dev-assets.
- 🟡 [other] Module re-declares FULL storage account with minimal props (risks resetting 4.1 hardening + SKU change) → `security.bicep` (59–85) → networkAcls-only child.
- ⚪ [cleanup-gap] Cleanup removes RBAC + SE never created; never deletes stored access policy → `Remove-LabResource.ps1` → mirror Deploy.
- ⚪ [cross-reference-drift] Cleanup comment numbering skips "# 2" → `Remove-LabResource.ps1` → renumber.
- ⚪ [resource-coverage] Orphan step images imply removed Key-Rotation/RBAC steps → `lab-guide-4.4.md` → add steps + wire or delete.

### Lab 5.1 — Azure Monitor (13)
- 🟡 [az-cli-leftover] Checklist validation commands use az → `lab-checklist-5.1.md` (46/65) → `Get-AzOperationalInsightsWorkspace`/`Get-AzMetricAlertRuleV2`.
- 🟡 [validation-coverage] Objective "Create Log Search Alerts" never delivered → `lab-guide-5.1.md:9` → add step or drop objective.
- ⚪ [az-cli-leftover] main.bicep header EXAMPLE az + contradicts DEPLOYMENT line → `bicep/main.bicep:8` → Deploy-Bicep path.
- ⚪ [cross-reference-drift] Dashboard name SkyCraft-Operations-Dash vs SkyCraft-Ops → `ARCHITECTURE.md:25` → SkyCraft-Ops.
- ⚪ [policy-tag-gap] `New-AzDataCollectionRuleAssociation` sets no Project tag → non-taggable sub-resource; likely no-fix. **(needs-decision — verify exemption)**
- ⚪ [naming-mismatch] Param/comment "prod VM" but alert targets dev VM → `monitoring.bicep` (157/163) → rename `parTargetVmResourceId`.
- ⚪ [cross-reference-drift] ARCHITECTURE claims alert on prod VM; reality dev VM → `ARCHITECTURE.md:12` → `dev-skycraft-swc-auth-vm`.
- ⚪ [cleanup-gap] Cleanup only removes DCR association from DEV VM, not fallback VM → `Remove-LabResource.ps1` → mirror Deploy fallback.
- ⚪ [cleanup-gap] Workspace only soft-deleted (14-day), not purged → `Remove-LabResource.ps1` → optional `-ForceDelete`.
- ⚪ [validation-coverage] Heartbeat data + pinned dashboard unverified; AMA install never automated → `Test-Lab.ps1` → automate or document manual.
- ⚪ [property-read-bug] Email-receiver count not null-safe (`@($null).Count==1` false-PASS) → `Test-Lab.ps1:170` → `@(... | Where {$_}).Count`.
- ⚪ [cross-reference-drift] Orphaned screenshots up to 5.1.11 but guide has 5.1.1–5.1.6 → delete or wire.
- ⚪ [other] DCR `kind:'Linux'` Syslog-only; guide NOTE over-promises Windows "Event logs" → `monitoring.bicep` / guide 128 → fix NOTE.

### Lab 5.2 — Business Continuity (13)
- 🟡 [prerequisite-mismatch] Deploy hard-fails on missing LAW but Prereqs omit Lab 5.1/the LAW → `lab-guide-5.2.md` (70–73) → add.
- 🟡 [az-cli-leftover] Checklist validation blocks use az → `lab-checklist-5.2.md` (104/133/164/194/222/252/281) → remove (PS twins exist).
- 🟡 [validation-coverage] ASR command `az backup replication-protected-item list` is not real → `lab-checklist-5.2.md:281` → remove (ASR is portal-only).
- 🟡 [property-read-bug] VM-protection idempotency uses `.FriendlyName` (documented empty) → `Deploy-Bicep.ps1:272` → match `$_.Name -like "*$vmName"`.
- 🟡 [cleanup-gap] Cleanup never handles RSV soft delete → vault left behind → `Remove-LabResource.ps1` → disable soft delete / `Undo-AzRecoveryServicesBackupItemDeletion`.
- ⚪ [environment-mismatch] Guide calls protected machine "Production VM" but it's the dev VM → `lab-guide-5.2.md` (5.2.3) → relabel.
- ⚪ [cross-reference-drift] Typo "Refiew + Start replication" → `lab-guide-5.2.md:216` → "Review".
- ⚪ [other] ARCHITECTURE says "2 protected VMs" but automation protects one → `ARCHITECTURE.md` (22/45/52) → fix + recompute cost.
- ⚪ [az-cli-leftover] Bicep comment claims `az backup vault backup-properties set` → `recoveryServicesVault.bicep:45`, `main.bicep:7` → PS.
- ⚪ [resource-coverage] ASR (asr vault, replica VM, Norway East) described but never created → mark portal-only or add coverage.
- ⚪ [other] Blob backup-instance comment says "vaulted" but Deploy creates operational (continuous) policy → reconcile. **(needs-decision)**
- ⚪ [other] Step screenshots exist but guide never references them → wire or delete.
- ⚪ [validation-coverage] Test validates instance existence only, not policy link/protection state; VM initial-backup status unchecked → `Test-Lab.ps1` → assert.

### Lab 5.3 — Network Monitoring (14)
- 🟠 [naming-mismatch] Guide uses fictitious "dev-skycraft-vm"/"prod-skycraft-vm" → `lab-guide-5.3.md` (30–31/82/100/124/127) → real names (prod is a VMSS).
- 🟠 [prerequisite-mismatch] Prereqs omit Storage (4.1) + LAW (5.1) + understate VM count, all hard-required → `lab-guide-5.3.md` (57–63) → add.
- 🟠 [resource-coverage] Guide steps are portal-only diagnostics; automation deploys Flow Log + Connection Monitor + extensions never mentioned → reconcile scope. **(needs-decision)**
- 🟠 [validation-coverage] Test validates Flow Log + Connection Monitor (guide never builds); guide hands-on items untested → align. **(needs-decision)**
- 🟠 [az-cli-leftover] Checklist Validation Commands use az + nonexistent VM → `lab-checklist-5.3.md` (51–67) → Az + real VM name.
- 🟡 [policy-tag-gap] `New-AzResourceGroup` + `New-AzNetworkWatcher` omit Project tag → `Deploy-Bicep.ps1` (165–167) → add `-Tag`.
- 🟡 [environment-mismatch] Connection Monitor documented hub→spoke (prod→dev) but deploys dev-world→dev-auth → `network-monitoring.bicep` → rename endpoint + fix wording.
- ⚪ [cleanup-gap] Remove never removes NetworkWatcherAgent VM extensions → `Remove-LabResource.ps1` → optional removal.
- ⚪ [cleanup-gap] Flow-log blobs left in storage after cleanup → `Remove-LabResource.ps1` → purge/archive.
- ⚪ [cross-reference-drift] Checklist port/protocol disagree with guide (80 vs 8080; outbound:53 vs inbound:443) → checklist 20/22/66 → align.
- ⚪ [cross-reference-drift] Orphaned step images 5.3.5/5.3.7/5.3.8 but guide defines 5.3.1–5.3.4 → delete or wire.
- ⚪ [other] Objective says "NSG Flow Logs" but deployed is a VNet Flow Log → `lab-guide-5.3.md:12` → VNet Flow Logs v2.
- ⚪ [az-cli-leftover] Bicep header EXAMPLE `az deployment sub create` → `bicep/main.bicep:7` → Deploy-Bicep path.
- ⚪ [other] Tag tests labeled "(Project, Environment, CostCenter)" but assert only Project+CostCenter → `Test-Lab.ps1` (158/209) → add Environment.

---

## 7. Per-lab verified counts

| Lab | Count | Lab | Count |
|-----|:---:|-----|:---:|
| 2.1 | 17 | 4.1 | 11 |
| 2.2 | 16 | 4.2 | 9 |
| 2.3 | 14 | 4.3 | 11 |
| 3.1 | 13 | 4.4 | 14 |
| 3.2 | 19 | 5.1 | 13 |
| 3.3 | 11 | 5.2 | 13 |
| 3.4 | 12 | 5.3 | 14 |
| | | **Total** | **187** |

---

*Generated by a 30-agent audit/verify/synthesis workflow (run `wf_257635db-3f5`). Items tagged **(needs-decision)** require a product call (in-scope vs out-of-scope) before a mechanical fix.*
