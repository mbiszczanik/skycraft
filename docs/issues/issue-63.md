# Root Cause Analysis: GitHub Issue #63

## Issue Summary

- **GitHub Issue ID**: #63
- **Issue URL**: https://github.com/mbiszczanik/skycraft/issues/63
- **Title**: Phase 4 — Bicep & Markdown standards-enforcement tests
- **Reporter**: mbiszczanik
- **Status**: OPEN (no linked PR, no comments)

## Assessment

| Metric | Value | Reasoning |
|--------|-------|-----------|
| Severity | Low | This is an enhancement (test coverage), not a defect — nothing is broken in production labs today. |
| Complexity | Low | Two new, self-contained Pester files that follow an existing, well-established house pattern (`tests/Script-Standards.Tests.ps1`); no CI wiring change needed (`lint.yml` already runs `Invoke-Pester -Path ./tests -CI`). |
| Confidence | High | The house pattern (discovery → `$Cases` → `It -ForEach`, separator-agnostic matching) is fully evidenced in-repo, and both target invariants (canonical tags, README/link casing) already hold repo-wide, so the tests can be written and validated against real files without guessing. |

## Problem Description

This is not a bug report — it is Phase 4 of a multi-phase standards-enforcement retrofit. Phase 3 (canonical Bicep tags: `Project`/`Environment`/`CostCenter`/`Owner`, forbidding `ManagedBy`/`DeploymentDate`) already shipped and is recorded in `CHANGELOG.md:51` and `docs/bicep-standards.md:164-194`. Phase 4 (this issue) asks to **lock the retrofit in with tests** so a future change can't silently reintroduce a forbidden tag key or a broken/mis-cased relative link, mirroring how `tests/Script-Standards.Tests.ps1` already locks in the PowerShell-standards retrofit (issue #61).

**Expected Behavior:** `tests/Bicep-Tags.Tests.ps1` and `tests/Markdown-Links.Tests.ps1` exist, run as part of the existing `pester` CI job, and fail if a Bicep file drops a canonical tag / adds a forbidden one, or a Markdown file links to a path that doesn't exist on disk with matching case.

**Actual Behavior:** Neither test file exists yet (confirmed via `Glob` — no `**/*Bicep-Tag*` or `**/*Markdown-Link*` matches anywhere in the repo). The invariants themselves already hold, but nothing enforces them against regression.

**Symptoms:**
- No automated guard against a future Bicep file reintroducing `ManagedBy`/`DeploymentDate` or omitting one of the four canonical tags.
- No automated guard against a future Markdown edit introducing a relative link that's broken, or only resolves because Windows `Test-Path` is case-insensitive (would break on the Linux CI runner / on a case-sensitive checkout).

## Reproduction

Not applicable (enhancement, not a reproducible defect). Verified instead by absence: `Invoke-Pester -Path ./tests` today has no test asserting either invariant, and both target files are missing from the repo.

**Reproduction Verified:** N/A

## Root Cause

### Affected Components

- **Files to create**: `tests/Bicep-Tags.Tests.ps1`, `tests/Markdown-Links.Tests.ps1`
- **Files to update**: `CHANGELOG.md` ([Unreleased] → Added)
- **Reference pattern**: `tests/Script-Standards.Tests.ps1`, `tests/Readme-Casing.Tests.ps1`
- **Dependencies**: none — no `lint.yml` change needed; the `pester` job (`.github/workflows/lint.yml:46-56`) already runs `Invoke-Pester -Path ./tests -CI` over the whole directory.

### Analysis

**Why does no test enforce the canonical-tag/link-casing invariants?** → because Phase 3 (issue #62 v2) retrofitted the Bicep tags and the earlier casing work, but shipped without a locking Pester test for either — only the PowerShell-standards retrofit got one (`tests/Script-Standards.Tests.ps1`, issue #61) (evidence: `CHANGELOG.md:16-52` lists tag/AVM work but no `Bicep-Tags`/`Markdown-Links` test addition).
**Why wasn't it caught as a gap earlier?** → because the retrofit was tracked as an explicit multi-phase plan and issue #63 *is* the tracked follow-up for phase 4 (evidence: issue body — "Depends on: Phase 3 (Bicep tags must be canonical first)").
→ **ROOT CAUSE**: not a bug — a planned, not-yet-implemented test-coverage gap. The fix is additive: write the two test files per the established house pattern.

### Related findings (informational, not blocking)

- `module-3-compute/3.1-infrastructure-as-code/tests/Standards.Tests.ps1:100-105` has a lab-scoped test that *tolerates* `ManagedBy` as "OK as extra metadata." This predates the Phase 3 "forbidden" decision (`docs/bicep-standards.md:180`) and is now stale, but it is narrowly scoped to Lab 3.1's `main.bicep`, never triggers today (repo-wide `ManagedBy`/`DeploymentDate` grep is empty), and does not conflict with the new repo-wide `Bicep-Tags.Tests.ps1`. Out of scope for this issue; flagged for a separate cleanup.
- Several Bicep files compose tags via `union(varCommonTags, { Environment: '<env>' })` rather than declaring all four keys in one literal block (e.g. `module-3-compute/3.1-infrastructure-as-code/bicep/main.bicep:49-56`, `module-4-storage/4.1-storage-accounts/bicep/main.bicep:69-88` nests per-environment). A naive "does this one `var ...Tags... = {...}` block contain all four keys" scan would false-fail these files. The new test resolves this at the **file level** (union of all `*Tags*` var blocks and `union(...)` second arguments in that file must cover the canonical four), consistent with the issue's own text-scan caveat ("note in CBH a future upgrade to compiled-ARM inspection").

## Impact Assessment

**Scope:** Repo-wide — 23 `.bicep` files declare or reference tags; 41 `.md` files (169 relative-link occurrences by rough regex count, refined to 281 individual link matches after excluding external/anchor links) are in scope for link checking.

**Affected Features:** None at runtime — this only adds CI test coverage.

**Severity Justification:** Low — no user-facing or lab-deployment behavior changes; risk is confined to CI (a false-positive could block a legitimate PR, mitigated by validating the tests pass clean against the current tree before merging).

**Data/Security Concerns:** None.

## Proposed Fix

### Fix Strategy

Add two Pester 5 test files under `tests/`, following the exact house pattern used by `tests/Script-Standards.Tests.ps1` and `tests/Readme-Casing.Tests.ps1`: discovery-phase `Get-ChildItem`/`git ls-files` → `$Cases` array of hashtables → `Describe`/`It -ForEach`, with separator-agnostic (`-replace '\\','/'`) path matching so the suite runs identically on Windows and the `ubuntu-latest` CI runner.

### Files to Modify

1. **`tests/Bicep-Tags.Tests.ps1`** (new)
   - Changes: `Describe 'SkyCraft Bicep - canonical tag set'` with two `It -ForEach` blocks:
     - Canonical-four coverage, scoped to files that own a literal `var ...Tags... = {...}` block (skips pure pass-through modules like `module-1-identities-governance/1.3-governance/bicep/modules/tags.bicep`, which only has `param parTags object`). Resolves the canonical set at file level to tolerate the `union(varCommonTags, {...})` composition pattern.
     - Forbidden-key check (`ManagedBy`, `DeploymentDate`), scoped to every `.bicep` file repo-wide.
   - Reason: locks in the Phase 3 tag retrofit (`docs/bicep-standards.md` §5).

2. **`tests/Markdown-Links.Tests.ps1`** (new)
   - Changes: `Describe 'Markdown relative links resolve on disk (case-sensitive)'` — for every `.md` file tracked by `git ls-files`, extract every `](...)` link, skip URI-scheme links (`https?:`, `mailto:`, etc.) and pure anchors (`#...`), resolve the remainder relative to the referencing file's directory (or repo root for a leading `/`), and assert the resolved path is a member of the `git ls-files` set (files) or a tracked-directory prefix set (directory-style links), using ordinal (case-sensitive) `HashSet<string>` membership — not `Test-Path`, which is case-insensitive on Windows.
   - Reason: locks in link integrity and case-correctness so links that "work" on a Windows checkout don't silently break on Linux/macOS or the CI runner.

3. **`CHANGELOG.md`**
   - Changes: add both new guards under `[Unreleased]` → `### Added`.
   - Reason: repo convention — every prior `tests/*.Tests.ps1` addition is logged there (e.g. `CHANGELOG.md:20` for `Avm-Module-Pinning.Tests.ps1`).

### Alternative Approaches

- **Compiled-ARM inspection for tags** (build every `.bicep` to ARM JSON via `az bicep build` and inspect the resolved `tags` property per resource) would be more precise — it would correctly resolve `union()`/lookup-map composition without the file-level heuristic above — but it's significantly slower (27 `az bicep build` invocations) and heavier to write correctly for a first pass. The issue explicitly asks for a text scan and to note the future upgrade in the file's comment-based help; that's what's implemented, with the upgrade path documented in the `.SYNOPSIS`/`.DESCRIPTION` block.
- **Case-insensitive Markdown link check** (plain `Test-Path`) was rejected — it's exactly the bug class this test exists to catch (works on Windows, breaks on Linux/macOS/case-sensitive filesystems), per the issue and the precedent set by `tests/Readme-Casing.Tests.ps1`.

### Risks and Considerations

- A regex-based tag-key scan can't perfectly model arbitrary Bicep expressions; scoping the canonical-four check to files with a literal `var ...Tags...` block, and unioning keys across `union()` calls, was validated against every current pattern in the repo (flat blocks, `union()` composition, per-environment nested objects) before finalizing.
- The Markdown-link scan must resolve relative to the *referencing file's directory*, not the repo root — verified against real link samples (`./images/...`, `../tests/`, `/README.md`).
- No breaking changes; purely additive test files plus a changelog entry.

### Testing Requirements

**Test Cases Needed:**
1. Full suite green against the current tree (`Invoke-Pester -Path ./tests`) — both new files pass with zero violations, since Phase 3's retrofit is already complete.
2. Deliberately break one canonical tag (remove `Owner` from one `var varCommonTags` block) → `Bicep-Tags.Tests.ps1` fails on that file → revert.
3. Deliberately introduce a forbidden tag (`ManagedBy: 'test'`) in one file → test fails → revert.
4. Deliberately break one Markdown link (wrong case, e.g. `Readme.md` instead of `README.md`, or a nonexistent path) → `Markdown-Links.Tests.ps1` fails on that file/link → revert.

**Validation Commands:**
```powershell
Invoke-Pester -Path ./tests/Bicep-Tags.Tests.ps1 -Output Detailed
Invoke-Pester -Path ./tests/Markdown-Links.Tests.ps1 -Output Detailed
Invoke-Pester -Path ./tests -CI
```

## Implementation Plan

1. Write `tests/Bicep-Tags.Tests.ps1`, validate green against the current tree.
2. Write `tests/Markdown-Links.Tests.ps1`, validate green against the current tree.
3. Run the deliberate-break verification steps above and revert.
4. Update `CHANGELOG.md` under `[Unreleased]` → `Added`.
5. Run the full `tests/` suite once more (`Invoke-Pester -Path ./tests -CI`) to confirm no regression in the other 8 existing test files.

This RCA document should be used by the `piv-implement-issue` skill.

## Next Steps

1. Review this RCA document
2. Run the `piv-implement-issue` skill with issue #63 to implement the fix
3. Run the `piv-commit` skill after implementation complete
