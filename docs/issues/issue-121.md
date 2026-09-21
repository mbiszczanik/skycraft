# Root Cause Analysis: GitHub Issue #121

## Issue Summary

- **GitHub Issue ID**: #121
- **Issue URL**: https://github.com/mbiszczanik/skycraft/issues/121
- **Title**: Lab 3.3 names every container resource for dev only, so prod and platform runs are unnameable
- **Reporter**: mbiszczanik
- **Status**: OPEN (no linked PR, no comments; found by the audit that #120 merged)

## Assessment

| Metric | Value | Reasoning |
|--------|-------|-----------|
| Severity | Medium | `-Environment prod` silently deploys dev-named containers into the prod resource group, and eight real, billing container resources already stand in the subscription that no source can name or tear down. No data loss and no security exposure; the workaround (override every name by hand) is what produced the orphans. |
| Complexity | Medium | Six files in one lab plus one guard in `tests/Resource-Audit.Tests.ps1`. The pattern to mirror (Lab 3.4) already exists, but one name does not fit: `platform-skycraft-swc-aca-world-02` is 34 characters against Azure's 32-character Container App limit, so the ACA name scheme has to change, which touches the guide, checklist and the live dev estate. |
| Confidence | High | Every claim is a literal in the current tree (`file:line` below). The composed-name fix was dry-run against the real `Get-KnownResourceName` from `scripts/Invoke-ResourceAudit.ps1` and every prod/platform name resolved as known. The one unknown is a naming decision, not a diagnosis. |

## Problem Description

Lab 3.3 is the only Module 3 lab whose resource names are spelled as `dev` literals and never composed from the environment. Every other lab in the repository derives names from `parEnvironment` / `$Environment` (Lab 3.4: `'${parEnvironment}-skycraft-swc-asp'`, `"$Environment-skycraft-swc-rg"`), so `-Environment prod` produces prod resources. Lab 3.3 accepts `-Environment prod` and `parEnvironment = 'prod'` (the `@allowed` set includes `prod` and `platform`) but only uses the value for the `Environment` tag.

**Expected Behavior:** `.\Deploy-Bicep.ps1 -Environment prod` deploys `prodskycraftswcacr01`, `prod-skycraft-swc-aci-auth`, `prod-skycraft-swc-cae-02` and a prod container app into `prod-skycraft-swc-rg`; `Test-Lab.ps1` and `Remove-LabResource.ps1` accept the same switch and act on the same names; `scripts/Invoke-ResourceAudit.ps1` recognises them.

**Actual Behavior:** `-Environment prod` deploys `devskycraftswcacr01` and the other three dev names, tagged `Environment=Production`, into whichever resource group `-ResourceGroupName` names (default `dev-skycraft-swc-rg`, independent of `-Environment`). `Test-Lab.ps1` and `Remove-LabResource.ps1` have no `-Environment` at all and hardcode the four dev names.

**Symptoms:**
- `scripts/Invoke-ResourceAudit.ps1` reports 8 container resources under `prod`/`platform` as drift, all genuine.
- `Remove-LabResource.ps1` cannot remove them (it can only delete the four dev literals at lines 54-57).
- `Deploy-Bicep.ps1 -Environment prod -ResourceGroupName prod-skycraft-swc-rg` would create a *second* `devskycraftswcacr01`-named registry request in prod, which Azure rejects because ACR names are globally unique and the dev one already exists — so the lab is not deployable to prod at all from this repository.

## Reproduction

**Steps to Reproduce:**
1. `cd module-3-compute/3.3-containers/scripts`
2. `.\Deploy-Bicep.ps1 -Environment prod -ResourceGroupName prod-skycraft-swc-rg -WhatIf`
3. Observe the what-if lists `devskycraftswcacr01`, `dev-skycraft-swc-aci-auth`, `dev-skycraft-swc-cae-02`, `dev-skycraft-swc-aca-world-02` under `prod-skycraft-swc-rg`.
4. `Get-Command .\Test-Lab.ps1, .\Remove-LabResource.ps1 | Select-Object -ExpandProperty Parameters` — neither has `-Environment`.

**Reproduction Verified:** Yes, statically (the what-if needs a live prod registry; the parameter object in `Deploy-Bicep.ps1:96-101` is deterministic). The name-resolution side was verified by running the real `Get-KnownResourceName` against a scratch copy of the proposed sources (see Testing).

## Root Cause

### Affected Components

- **Files**:
  - `module-3-compute/3.3-containers/bicep/main.bicep` (param defaults, lines 28-52)
  - `module-3-compute/3.3-containers/bicep/acr.bicep` (`parAcrName` default, line 27)
  - `module-3-compute/3.3-containers/bicep/parameters/main.bicepparam` (dev literals, lines 12-13)
  - `module-3-compute/3.3-containers/scripts/Deploy-Bicep.ps1` (`$acrName`, line 84; `-ResourceGroupName` default independent of `-Environment`, line 56)
  - `module-3-compute/3.3-containers/scripts/Test-Lab.ps1` (lines 51, 88, 116, 117)
  - `module-3-compute/3.3-containers/scripts/Remove-LabResource.ps1` (lines 54-57, 69-109)
  - `tests/Resource-Audit.Tests.ps1` (guard at lines 310-323, to be deleted)
  - `module-3-compute/3.3-containers/lab-guide-3.3.md`, `lab-checklist-3.3.md` (name tables; only if the ACA name changes, see below)
- **Functions/Classes**: none — the scripts are linear; the templates use param defaults.
- **Dependencies**: `scripts/Invoke-ResourceAudit.ps1` `Get-KnownResourceName` (learns names by expanding `${...}`/`$...` placeholders over the `@allowed` environment domain — it *cannot* learn a name that exists only on an unmerged branch).

### Analysis

**Evidence Chain (5 Whys):**
```
WHY does the audit flag prodskycraftswcacr01 & co. as drift?
  → because no source on main can produce those names
    (evidence: scripts/Invoke-ResourceAudit.ps1:86-293 builds the known set from literals and
     placeholder templates in *.bicep/*.bicepparam/*.ps1; nothing under 3.3-containers
     contains a prod/platform literal or a '${parEnvironment}…' name template)

WHY can no source produce them?
  → because Lab 3.3 spells its four names as dev literals in param defaults
    (evidence: bicep/main.bicep:38 parAcrName = 'devskycraftswcacr01', :43 parAciName,
     :48 parCaeName, :53 parAcaName; bicep/acr.bicep:27; parameters/main.bicepparam:12-13)
    and again as literals in the scripts
    (evidence: scripts/Deploy-Bicep.ps1:84 $acrName = "devskycraftswcacr01";
     Test-Lab.ps1:51,88,116,117; Remove-LabResource.ps1:54-57)

WHY are those resources live under prod/platform at all?
  → because the unmerged branch feature/bicep-gold-path carries
    3.3-containers/bicep/parameters/prod.bicepparam and platform.bicepparam with hand-spelled
    names, and a live cycle from that branch deployed them
    (evidence: `git show feature/bicep-gold-path:module-3-compute/3.3-containers/bicep/parameters/platform.bicepparam`;
     CHANGELOG.md:27 says the audit reports zero drift when pointed at that branch)

WHY did that branch shorten the platform app to platform-skycraft-swc-aca-02?
  → because 'platform-skycraft-swc-aca-world-02' is 34 characters and Container Apps
    (and main.bicep:51 @maxLength(32)) allow 32
    (evidence: platform.bicepparam comment "shortened to satisfy parAcaName maxLength(32)")

ROOT CAUSE: Lab 3.3 never adopted the environment-composed naming the rest of Module 3 uses
  (Lab 3.4 bicep/main.bicep:47-48 '${parEnvironment}-skycraft-swc-asp';
   Lab 3.4 scripts/Deploy-Bicep.ps1:67 "$Environment-skycraft-swc-rg"), so parEnvironment
   only reaches the tag map (main.bicep:60-70) and never the names. Original behaviour since
   d9bac39 (2026-01-31); not a regression.
```

**Why This Occurs:**
`parEnvironment` was added for the canonical tag set (CHANGELOG 0.8.0, "Labs 3.3 and 3.4 map dev/prod/platform to the canonical Environment values") but the names were left as the portal-era dev literals. `Deploy-Bicep.ps1` then had to restate the registry name to run Phase 1 (existence check and image import happen before `main.bicep` runs), and the comment on line 84 records the duplication without resolving it.

**Code Location:**
```
module-3-compute/3.3-containers/bicep/main.bicep:36-53
param parAcrName string = 'devskycraftswcacr01'
param parAciName string = 'dev-skycraft-swc-aci-auth'
param parCaeName string = 'dev-skycraft-swc-cae-02'
param parAcaName string = 'dev-skycraft-swc-aca-world-02'

module-3-compute/3.3-containers/scripts/Deploy-Bicep.ps1:84
$acrName = "devskycraftswcacr01" # Should match main.bicep default or param
```

### Related Issues

- #116 / #120 — the resource audit that found this; its guard at `tests/Resource-Audit.Tests.ps1:310-323` is a characterisation test that must be deleted with this fix.
- #79 / #132 — reconciled the Lab 3.3 guide with the `-02` names; the guide's name tables (lab-guide-3.3.md:66,138,191,196,265-267; lab-checklist-3.3.md:6,21,34-35,95-97) will need the same treatment if the ACA name changes.
- `feature/bicep-gold-path` (unmerged, pre-AVM) — carries the per-environment `.bicepparam` files and a `bicep build-params`-based `Deploy-Bicep.ps1`. Reference only; do not rebase (it deploys the deleted `bicep/modules/*.bicep`).

## Impact Assessment

**Scope:** One lab (3.3). The lab cycle (`tools/lab-cycle-manifest.psd1:211-223`) runs Lab 3.3 dev-only and is unaffected by the bug; it is affected by the fix only if the dev ACA name changes.

**Affected Features:**
- Lab 3.3 prod/platform deployment (impossible from `main` today).
- Lab 3.3 teardown and validation for anything but dev.
- Resource audit accuracy (8 true positives that should become known names once the fix lands).

**Severity Justification:** Medium — real running cost and an undeletable-by-tooling state, but confined to one lab and no correctness risk for dev.

**Data/Security Concerns:** None. The registry admin credential flow is unchanged.

## Proposed Fix

### Fix Strategy

Compose every Lab 3.3 name from the environment, the way Lab 3.4 does, while keeping the names as overridable parameters (ACR names are globally unique, so a collision override must stay possible):

1. **`main.bicep` / `acr.bicep`** — param defaults become `'${parEnvironment}skycraftswcacr01'`, `'${parEnvironment}-skycraft-swc-aci-auth'`, `'${parEnvironment}-skycraft-swc-cae-02'`, and `'${parEnvironment}-skycraft-swc-rg'`. Bicep allows a param default to reference an earlier param. The audit's placeholder expansion learns all three environments from this form (verified, see Testing).
2. **ACA name** — `'${parEnvironment}-skycraft-swc-aca-world'` (drop the `-02` from the app only). Fits 32 for all three environments (dev 26, prod 27, platform 31). The `-02` exists because a Container Apps *environment* pins an immutable `ME_<name>` resource group (lab-guide-3.3.md:200); the app has no such constraint and carried `-02` only for symmetry. Keep `world` because the guide calls it the World Service.
3. **`Deploy-Bicep.ps1`** — derive `-ResourceGroupName` from `-Environment` (`"$Environment-skycraft-swc-rg"`, as Lab 3.4 line 67 does) and add `-AcrName` with default `"${Environment}skycraftswcacr01"`, passed as `parAcrName` to both `acr.bicep` and `main.bicep`. Phase 1 needs the registry name before any template runs, so the script composition is the single source for the script path; the Bicep default serves direct-template callers. Delete the line-84 literal and its comment.
4. **`Test-Lab.ps1` / `Remove-LabResource.ps1`** — add `-Environment` (`ValidateSet dev/prod/platform`, default `dev`) and `-AcrName`/`-AciName`/`-CaeName`/`-AcaName` parameters whose defaults compose from it; default `-ResourceGroupName` from it too. Replace every literal. The `-*Name` overrides are what let the eight live orphans be removed (`-Environment prod -AcaName prod-skycraft-swc-aca-world-02`, `-Environment platform -AcaName platform-skycraft-swc-aca-02`).
5. **`parameters/main.bicepparam`** — drop the `parResourceGroupName` and `parAcrName` lines (keep `parLocation`, `parEnvironment` for the CI `build-params` check). Optionally add `prod.bicepparam`/`platform.bicepparam` containing only `parEnvironment`; not required once names compose.
6. **`tests/Resource-Audit.Tests.ps1:310-323`** — delete the "spelled only for dev" guard and add its inverse: `recognises <_>` for `prodskycraftswcacr01`, `platform-skycraft-swc-cae-02`, `platform-skycraft-swc-aca-world`.
7. **Docs** — `lab-guide-3.3.md`, `lab-checklist-3.3.md`, `ARCHITECTURE.md`: replace `dev-skycraft-swc-aca-world-02` with `dev-skycraft-swc-aca-world`; add a one-line note that names take the environment prefix. `tests/Guide-Automation-Names.Tests.ps1` skips interpolated names, so the guide is not forced to spell prod/platform.
8. **CHANGELOG** — Unreleased: Changed (names compose from the environment; ACA renamed) and Removed (audit guard).

### Files to Modify

1. **module-3-compute/3.3-containers/bicep/main.bicep** — compose the five defaults from `parEnvironment`; rename the ACA default. Reason: the template is the source of every literal the audit and the scripts restate.
2. **module-3-compute/3.3-containers/bicep/acr.bicep** — same `parAcrName` default. Reason: "Keep in sync with modAcr in main.bicep" (line 51) applies to the name too.
3. **module-3-compute/3.3-containers/bicep/parameters/main.bicepparam** — remove the two dev literals. Reason: they would override the composed defaults back to dev for any bicepparam caller.
4. **module-3-compute/3.3-containers/scripts/Deploy-Bicep.ps1** — `-ResourceGroupName` default and `-AcrName` derived from `-Environment`; pass `parAcrName = $AcrName`. Reason: removes the second hardcoded registry and stops `-Environment prod` landing in the dev RG.
5. **module-3-compute/3.3-containers/scripts/Test-Lab.ps1** — `-Environment` + name params. Reason: validation must target the environment that was deployed.
6. **module-3-compute/3.3-containers/scripts/Remove-LabResource.ps1** — `-Environment` + name params; replace the eight literals in the `ShouldProcess` and `Remove-*` calls. Reason: teardown must be able to name every environment, including the live orphans.
7. **tests/Resource-Audit.Tests.ps1** — swap the guard. Reason: the issue says so; the guard is intentionally a tripwire.
8. **module-3-compute/3.3-containers/{lab-guide-3.3.md,lab-checklist-3.3.md,ARCHITECTURE.md}, CHANGELOG.md** — ACA rename and note. Reason: `Guide-Automation-Names.Tests.ps1` and #79 keep the guide and automation in step.

### Alternative Approaches

- **Per-environment `.bicepparam` files with literal names** (the issue's first option, and what `feature/bicep-gold-path` did). Pro: matches all eight live names exactly, including the shortened platform app; the audit learns literals directly. Con: the scripts still need the same names for Phase 1, validation and teardown, so either they restate a per-environment table (three copies of the literal problem) or they parse the bicepparam with `bicep build-params` at run time (the gold-path approach), which adds a Bicep CLI dependency to every script run and the `az bicep --stdout` code-page crash this repo has already hit on Windows. Rejected.
- **Keep `-aca-world-02` for dev/prod and special-case platform** via a Bicep conditional. Pro: no rename, all live names match. Con: the audit's expansion cannot see through a ternary, so the platform app stays unknown; and Lab 3.3 becomes the only lab whose name scheme depends on the environment. Rejected.
- **Drop `platform` from Lab 3.3's `@allowed` set** and keep `-aca-world-02`. Pro: zero rename. Con: the issue and the live estate both include platform; Lab 1.2 creates the platform RG; the platform orphans would remain unnameable. Rejected, but cheap if the owner decides platform is out of scope for containers.

### Risks and Considerations

- **Live dev estate**: after the ACA rename, a subscription still holding `dev-skycraft-swc-aca-world-02` from the last cycle is not cleaned by the new teardown default. Run the *current* `Remove-LabResource.ps1` (or the new one with `-AcaName dev-skycraft-swc-aca-world-02`) once before or right after merging.
- **Live prod/platform orphans**: remove with the new script's overrides (`-Environment prod -AcaName prod-skycraft-swc-aca-world-02`; `-Environment platform -AcaName platform-skycraft-swc-aca-02`). Lab 3.3 teardown takes ~24 minutes per environment (all of it the CAE, `tools/lab-cycle-manifest.psd1:427-431`).
- **ACR global uniqueness**: `prodskycraftswcacr01` / `platformskycraftswcacr01` already belong to this subscription (the audit found them), so no collision; the `-AcrName` override exists for anyone else.
- **Lab cycle manifest**: the comment at `tools/lab-cycle-manifest.psd1:221-222` ("-ResourceGroupName and -Environment both default to dev …") stays true; no manifest change.
- **Idempotence of the dev cycle**: unchanged apart from the app name; the CAE keeps `-02`, so the `ME_` resource-group constraint is untouched.
- **Guide-Automation-Names test**: literal names in `Test-Lab.ps1` disappear (they become interpolated), so the test constrains this lab less than before. The guide should still spell the dev names for learners.

### Testing Requirements

**Test Cases Needed:**
1. `tests/Resource-Audit.Tests.ps1`: `recognises <_>` for `prodskycraftswcacr01`, `platformskycraftswcacr01`, `platform-skycraft-swc-cae-02`, `prod-skycraft-swc-aci-auth`, `platform-skycraft-swc-aca-world` (replaces the deleted guard).
2. `tests/Resource-Audit.Tests.ps1`: the two old-scheme live names `prod-skycraft-swc-aca-world-02` and `platform-skycraft-swc-aca-02` are **not** recognised (they are orphans of the old scheme and should stay flagged until removed).
3. Existing suites unchanged: `Script-Standards`, `Cbh-Coverage` (new parameters need `.PARAMETER` entries), `Guide-Automation-Names`, `Bicep-Tags`, `Markdown-Links`.
4. `bicep build` / `bicep build-params` succeed for `main.bicep`, `acr.bicep`, `main.bicepparam` (CI job).
5. Dry run: `tools/Invoke-DryRun.ps1` for Lab 3.3 (the gate runs the offline Pester suites, #139).
6. Live (PR stays draft until done, per the repo's live-verification gate): `Deploy-Bicep.ps1 -Environment prod -WhatIf` lists prod names in `prod-skycraft-swc-rg`; a dev cycle deploys, validates and tears down `dev-skycraft-swc-aca-world`; `Invoke-ResourceAudit.ps1` then reports zero container drift after the old-scheme orphans are removed.

**Pre-verified (this RCA):** `Get-KnownResourceName` lifted from `scripts/Invoke-ResourceAudit.ps1` and run against a scratch tree containing only the proposed composed defaults returned `True` for `prodskycraftswcacr01`, `platformskycraftswcacr01`, `platform-skycraft-swc-cae-02`, `prod-skycraft-swc-aci-auth`, `platform-skycraft-swc-aca-world` and `False` for `prod-skycraft-swc-aca-world-02`, `platform-skycraft-swc-aca-02`.

**Validation Commands:**
```powershell
Invoke-Pester -Path .\tests -CI
bicep build .\module-3-compute\3.3-containers\bicep\main.bicep --outfile $env:TEMP\main.json
bicep build .\module-3-compute\3.3-containers\bicep\acr.bicep --outfile $env:TEMP\acr.json
bicep build-params .\module-3-compute\3.3-containers\bicep\parameters\main.bicepparam --outfile $env:TEMP\main.parameters.json
.\module-3-compute\3.3-containers\scripts\Deploy-Bicep.ps1 -Environment prod -WhatIf   # live, read-only
.\scripts\Invoke-ResourceAudit.ps1                                                    # live, read-only
```

## Implementation Plan

1. Branch `fix/lab-3.3-environment-names` from `main`.
2. Swap the audit guard for its inverse first (red), then change `main.bicep`/`acr.bicep`/`main.bicepparam` (green for the name cases).
3. Rework the three scripts (`-Environment`, composed name params, CBH `.PARAMETER` entries); run `Invoke-Pester -Path .\tests -CI`.
4. Update guide, checklist, ARCHITECTURE.md, CHANGELOG (Unreleased).
5. Open the PR as **draft** with `Refs #121`; run the live what-if and one dev cycle; remove the eight old-scheme orphans with the new script's overrides; re-run the audit; then mark ready and switch to `Closes #121`.

This RCA document should be used by the `piv-implement-issue` skill.

## Next Steps

1. Decide the ACA name scheme (recommended: `${env}-skycraft-swc-aca-world`; alternatives above).
2. Run `piv-implement-issue` for #121.
3. Run `piv-commit` after implementation.
