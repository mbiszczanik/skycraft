# Root Cause Analysis: GitHub Issue #112

## Issue Summary

- **GitHub Issue ID**: #112
- **Issue URL**: https://github.com/mbiszczanik/skycraft/issues/112
- **Title**: Tests — a harness that shells out to a lab script can bind the real Az cmdlets and reach the live subscription
- **Reporter**: mbiszczanik
- **Status**: OPEN (label `enhancement`, no comments, no linked PR). Both prerequisites named in the issue have since landed: #77 (lab-local suites in the CI `pester` job) merged as #133, and #139 added the same suites to the local dry-run gate.

## Assessment

| Metric | Value | Reasoning |
|--------|-------|-----------|
| Severity | Medium | No suite is exposed today: the only harness that runs a lab script in a child `pwsh` (Lab 5.2) carries the exit-99 guard and passes locally against a real Az 5.2.0 install with a cached login. The hazard is latent and structural: the guard is a one-off, nothing enforces it for the next suite, and since #139 the default `tools/Invoke-DryRun.ps1` run executes every lab-local suite in-process on a developer box that *is* signed in. The failure mode of the next unguarded suite is a real teardown, not a red test. |
| Complexity | Low | Three additive files plus one doc section: a shared helper module extracted from the 5.2 suite, one repo-wide guard suite, and a §6 subsection in `docs/powershell-standards.md`. The 5.2 suite changes only to import the helper. No lab script changes. |
| Confidence | High | Both PowerShell mechanisms were reproduced on this machine (pwsh 7.6.6, Az.Accounts 5.2.0, Az.DataProtection 2.4.0), the safe ordering was shown to fix both, and the 5.2 suite was run end to end (16/16, guard not triggered). The full inventory of test suites was walked; every `file:line` below is in the current tree. |

## Problem Description

A Pester suite that exercises a `Remove-Lab*.ps1` script by launching it in a child `pwsh` must replace every Az command the script calls with a stub. Two PowerShell behaviours make the two obvious ways of doing that fail silently, so the harness looks isolated while the child process is in fact bound to the real Az modules and, through `Get-AzContext`, to whatever subscription the developer's cached login points at. The scripts under test are destructive by design, so a half-stubbed harness does not fail: it deletes.

The safe pattern exists, but only as ~90 lines embedded in one lab-local suite. There is no shared helper, no repo-wide check that a second child-process suite uses the pattern, and the PowerShell standards do not describe it. Meanwhile the number of environments that run lab-local suites unattended has grown from zero to two (CI via #133, developer boxes via #139).

**Expected Behavior:** Any suite that runs a lab script in a child process either provably shadows every Az command it needs (and refuses to run otherwise), or cannot be merged.

**Actual Behavior:** Only `module-5-monitoring-maintenance/5.2-business-continuity/tests/Remove-LabResource.Tests.ps1` does this. The next suite written by copying a naive `PSModulePath` or `Import-Module stub` approach would run the real script against the live subscription and, as long as the inventory matched nothing, still pass.

**Symptoms:**
- A stub directory placed first on `$env:PSModulePath` is not first in the child: pwsh prepends the user and shared module directories, so a real Az installation wins resolution.
- A stub module imported before the script is partially overridden by `#Requires -Modules`: Az modules that export cmdlets stay shadowed, Az modules that export functions (autorest-generated, e.g. `Az.DataProtection`) win against the stub. The session is half real.
- Neither condition produces an error. In the #105 case the run reached the script's "No Lab 5.2 resources found" early return and looked green.

## Reproduction

**Steps to Reproduce (mechanism 1, `PSModulePath` prepend):**
1. In a parent pwsh: `$env:PSModulePath = 'C:\NOPE'`
2. `pwsh -NoProfile -Command '$env:PSModulePath; (Get-Command Get-AzContext).Source'`
3. Observe: the child path starts with `C:\Users\<user>\Documents\PowerShell\Modules;C:\Program Files\PowerShell\Modules;…;C:\NOPE`, and `Get-AzContext` resolves to `Az.Accounts`.

**Steps to Reproduce (mechanism 2, import order vs `#Requires`):**
1. Write `Stub.psm1` defining functions `Get-AzContext` and `Get-AzDataProtectionBackupVault`.
2. Write `Target.ps1` with `#Requires -Modules Az.Accounts, Az.DataProtection` that prints `(Get-Command <name>).Source` for both.
3. `pwsh -NoProfile -Command "Import-Module .\Stub.psm1; .\Target.ps1"`
4. Observe: `Get-AzContext -> Stub / Function` but `Get-AzDataProtectionBackupVault -> Az.DataProtection / Function`.
5. Re-run as `pwsh -NoProfile -Command "Import-Module Az.Accounts, Az.DataProtection; Import-Module .\Stub.psm1; .\Target.ps1"` and observe both resolve to `Stub`.

**Reproduction Verified:** Yes, both mechanisms, on Windows 11 / pwsh 7.6.6 / Az.Accounts 5.2.0 / Az.DataProtection 2.4.0, with `Get-AzContext` returning a live context in the same session. The 5.2 suite was also run: 16 passed, exit code 99 not observed (the guard was not needed, i.e. the shadowing held).

## Root Cause

### Affected Components

- **Files**:
  - `module-5-monitoring-maintenance/5.2-business-continuity/tests/Remove-LabResource.Tests.ps1` (the only implementation of the safe pattern)
  - `docs/powershell-standards.md` §6 "Pester (Repository Standards Tests)" (does not describe the pattern)
  - `.github/workflows/lint.yml:95` and `tools/Invoke-DryRun.ps1:544` (the two runners that now execute every lab-local suite)
  - `tests/` (no shared harness helper, no guard suite)
- **Functions/Classes**: `Initialize-StubModule` (5.2 suite `:236-254`), `Invoke-CleanupScript` (5.2 suite `:258-328`)
- **Dependencies**: PowerShell 7 module-path bootstrap; `#Requires -Modules` auto-import; command-precedence rules (function > cmdlet, later import wins among same kind); Az modules generated by autorest (`Az.DataProtection`) exporting functions instead of cmdlets.

### Analysis

**Evidence Chain (5 Whys):**
```
WHY can a harness reach the live subscription?
  → because the child pwsh binds the real Az.* commands while the suite believes stubs are in effect
    (evidence: reproduction 1 and 2 above; Remove-LabResource.ps1:86 `Get-AzContext` is the only gate and it passes on a signed-in box)

WHY does a stub directory on PSModulePath not win?
  → because pwsh 7 prepends CurrentUser and AllUsers module directories to any inherited PSModulePath
    (evidence: child printed `…\Documents\PowerShell\Modules;C:\Program Files\PowerShell\Modules;…;C:\NOPE`)

WHY does an explicitly imported stub module not win either?
  → because `#Requires -Modules` imports the real modules after the stub, and among same-kind commands the
    later import wins; Az.DataProtection exports functions, so its functions replace the stub's functions
    (evidence: reproduction 2 — `Get-AzDataProtectionBackupVault -> Az.DataProtection / Function`;
     5.2 script `#Requires -Modules Az.Accounts, Az.RecoveryServices, Az.DataProtection, Az.Resources, Az.Storage` at :52)

WHY is this not caught?
  → because neither condition raises an error, and the script's own early-return paths make a mis-bound run look green
    (evidence: #105 history in the issue; script "No Lab 5.2 resources found" path)

ROOT CAUSE: the safe harness shape (import real Az first, stub last, assert every stubbed name resolves to the
  stub, abort with a distinctive code) lives only inside one lab-local suite and is enforced nowhere:
  - no shared helper in tests/ or tools/ (tests/ holds only *.Tests.ps1; the only .psm1 files are tools/AvmRegistry, Changelog, LabCycle)
  - no repo-wide Pester rule flags a child-process suite lacking the guard
  - docs/powershell-standards.md §6 requires "CI-safe" (no Connect-Az*) but says nothing about stubbing a child process
  (evidence: 5.2 suite :270-287; powershell-standards.md:257-283; Pester-Discovery.Tests.ps1 checks location only)
```

**Why This Occurs:**
The three requirements that make a child-process harness safe are non-obvious and interact: (1) the real modules must already be loaded so `#Requires` does not re-import them on top of the stub, (2) the stub must be imported last and must export *functions* so it outranks both cmdlets and autorest functions, (3) the child must verify `(Get-Command X).Source` for every stubbed name before running anything. The 5.2 suite gets all three right and documents why (`:26-32`, `:270-274`). Nothing carries that knowledge to the next author, and the two runners that execute lab-local suites by default make an unguarded suite an unattended teardown.

**Code Location:**
```
module-5-monitoring-maintenance/5.2-business-continuity/tests/Remove-LabResource.Tests.ps1:278-287
$required = "'" + (@('Az.Accounts', 'Az.RecoveryServices', 'Az.DataProtection', 'Az.Resources', 'Az.Storage') -join "','") + "'"
$shadowed = "'" + ($script:StubCommands -join "','") + "'"
$childCommand = @"
foreach (`$m in @($required)) { Import-Module `$m -ErrorAction SilentlyContinue }   # real Az first
Import-Module '$Manifest' -Force                                                    # stub last
`$notShadowed = @($shadowed) | Where-Object { (Get-Command `$_ -ErrorAction SilentlyContinue).Source -ne '$script:StubModuleName' }
if (`$notShadowed) { Write-Host "[HARNESS] Az stubs are not in effect for: ..."; exit 99 }
```
This block is correct and is the fix's raw material; the defect is that it is not reusable, not required, and not documented.

### Related Issues

- #105 / PR #111 — where the pattern was written; the suite at `module-5-monitoring-maintenance/5.2-business-continuity/tests/`.
- #77 / PR #133 — lab-local suites now run in CI (`lint.yml:83-95`). CI installs only Pester (`:73`), no Az, no `azure/login`; the placeholder `Az.*` manifests in the 5.2 suite (`:246-252`) exist for that runner. CI is the *safe* environment.
- #137 / PR #139 — lab-local suites now run in-process in `tools/Invoke-DryRun.ps1` (`:508-544`), in the default check set (`:83`). A developer box with Az and a cached login is the *dangerous* environment for this class of bug.
- #104 — exit-code propagation through `pwsh -File`; the 5.2 suite launches with `-Command` for that reason (`:15-20`).
- Same hazard class, different mechanism, out of scope here: `tests/LabCycle.Tests.ps1` runs `tools/Remove-LabCycle.ps1` in-process at 15 call sites. Isolation rests on every call splatting probe overrides (`$script:CleanProbes` `:1197-1204`, `$script:SweepBase` incl. `TeardownRunner = { 0 }`). All 15 currently do. The defaults are `Get-AzContext` (`Remove-LabCycle.ps1:204`) and `Remove-AzResourceGroup -Force -AsJob` (`:235`), and no assertion says a real Az command was never reached. Worth a follow-up issue.

## Impact Assessment

**Scope:**
- Today: one suite, guarded. Inventory of all 27 `*.Tests.ps1` files: only the 5.2 suite runs a lab script in a child process; every other child-process launch targets a `tools/` script with no Az surface or a fixture written to `$TestDrive`. No `Deploy-Bicep.ps1` or `Test-Lab.ps1` is executed by any suite.
- Tomorrow: every one of the 17 `Remove-Lab*.ps1` scripts is a candidate for the same kind of regression suite. Sixteen carry `#Requires -Modules Az.*`; the module lists differ per lab, so a copy-paste of the 5.2 block with the wrong `$required` list re-opens mechanism 2.

**Affected Features:**
- Test harnesses for destructive lab scripts; the local dry-run gate; the CI `pester` job (only if Az were ever installed there).

**Severity Justification:**
Medium: no live exposure at this commit, but the class of failure is silent resource deletion on a developer's real subscription, the guard exists in exactly one place, and the repository has just made lab-local suites run by default in two places. The cost of closing it is small.

**Data/Security Concerns:**
Destructive: an unguarded suite can delete real lab resources (resource groups, vaults, storage). No data exfiltration; no credential exposure. The blast radius is whatever subscription `Get-AzContext` returns on the machine running the tests, which per the project's own notes drifts between identities.

## Proposed Fix

### Fix Strategy

Turn the 5.2 block into the repository's one way of running a lab script under test, and make the guard something a reviewer does not have to remember:

1. **Extract** the stub-module writer and the child launcher into a shared test helper module, keeping the exact ordering and the exit-99 assertion.
2. **Enforce** with a repo-wide Pester suite: any `*.Tests.ps1` that launches `pwsh` against a path under `module-*/**/scripts/` must import the helper (or, failing that, contain the shadowing assertion and `exit 99`). Add a positive test that the helper's guard actually fires when the stub is deliberately withheld.
3. **Document** the required shape in `docs/powershell-standards.md` §6, and note in `docs/dry-run-harness.md` that the Pester check runs lab-local suites with the developer's real Az context in reach.

### Files to Modify

1. **`tests/Support/LabScriptStub.psm1`** (new)
   - Changes: `New-LabScriptStubModule -Name -Commands -Body -RequiredModules` (writes `<tmp>/<Name>.psm1|psd1` with `-FunctionsToExport $Commands`, plus manifest-only `RequiredModules` placeholders under `<tmp>/modules`); `Invoke-LabScriptWithStub -ScriptPath -Manifest -RequiredModules -StubCommands -StubModuleName [-ArgumentList] [-Environment @{}]` (real-first import, stub-last import, `.Source` assertion, `exit 99`, `$global:LASTEXITCODE = 0`, run, `exit $LASTEXITCODE`; prepends `<tmp>/modules` to `PSModulePath` only for the placeholders and restores it; returns `ExitCode`/`Output`). Keep the constant `99` and the `[HARNESS]` prefix so existing assertions and log greps hold.
   - Reason: makes the safe shape importable instead of copyable; the per-lab `$RequiredModules` argument removes the mechanism-2 copy-paste trap.

2. **`module-5-monitoring-maintenance/5.2-business-continuity/tests/Remove-LabResource.Tests.ps1`**
   - Changes: `Import-Module (Join-Path $PSScriptRoot '..' '..' '..' 'tests' 'Support' 'LabScriptStub.psm1') -Force` in `BeforeAll`; replace `Initialize-StubModule` and the launch half of `Invoke-CleanupScript` with helper calls, keeping the `SKYCRAFT_STUB_*` env plumbing and `$script:StubBody` local. The `It 'shadows the real Az cmdlets instead of touching Azure'` assertion stays.
   - Reason: proves the helper on the one real consumer; the suite's own 16 tests are the regression net.

3. **`tests/Lab-Script-Harness-Guard.Tests.ps1`** (new, repo-wide)
   - Changes: (a) static rule over every suite in `tests/` and `module-*/**/tests/`: if the text matches a `pwsh` launch (`& pwsh`, `& $Pwsh`, `Start-Process\s+pwsh`) and references `module-*…/scripts/*.ps1`, it must reference `LabScriptStub.psm1` or contain both `exit 99` and `\.Source -ne`. (b) behavioural rule: build a throwaway stub for a two-line generated script with `#Requires -Modules Az.Accounts`, launch via the helper with the stub import removed, assert `ExitCode -eq 99`. Works with or without Az installed because the placeholder manifest satisfies `#Requires` and `Get-Command` then returns nothing.
   - Reason: the "cheap way to enforce" the issue asks for; the behavioural half guards the helper itself against future edits that would weaken the assertion.

4. **`docs/powershell-standards.md`** §6, new subsection "Suites that run a lab script in a child process"
   - Changes: state the four rules (real Az first; stub last, exported as functions; assert `.Source` for every stubbed name and abort with 99; placeholder manifests for `#Requires` on Az-less runners), say `PSModulePath` is not an isolation mechanism and why, point at the helper and the guard suite.
   - Reason: scope item 1 of the issue.

5. **`docs/dry-run-harness.md`** (one paragraph)
   - Changes: the Pester check runs lab-local suites in-process on the developer's box; a suite that reaches Azure would do so with the current `Get-AzContext`. Point at the standards subsection.
   - Reason: #139 made the dev box the environment where this bug bites; the harness doc is where a developer looks first.

### Alternative Approaches

- **Docs + static guard only, no helper.** Smallest diff, but the next suite still copies 90 lines, and the `$required` list is the part most likely to be copied wrong. Rejected.
- **Pester `Mock` in-process instead of a child.** Would avoid the whole problem, but the 5.2 suite deliberately runs the real script in a child to assert the process exit code (#104/#105 contract); `Mock` cannot see into a child process. Not applicable to that suite, so the helper is still needed.
- **Refuse to run when `Get-AzContext` returns a context.** Backwards: a developer's box always has one. The right invariant is "the stub is bound", not "nobody is logged in".
- **Move the guard into `tools/Invoke-LabScript.ps1`.** That shim is production tooling used by the orchestrators against real Azure; putting test stubbing there mixes concerns.

### Risks and Considerations

- Refactoring the 5.2 suite must keep the child launched with `-Command` (not `-File`) and keep `$global:LASTEXITCODE = 0` before the call; both are documented invariants of that suite.
- Helper location `tests/Support/` is outside the `*.Tests.ps1` discovery filter (`Invoke-Pester -Path ./tests` only discovers `*.Tests.ps1`), `tests/Cbh-Coverage.Tests.ps1` and `tests/Script-Standards.Tests.ps1` filter on `*.ps1` so a `.psm1` is out of their scope, and `tests/Pester-Discovery.Tests.ps1` checks suite location only. PSScriptAnalyzer will lint it; keep it clean.
- The lab-local suite reaches the helper through a `..\..\..\tests\Support` relative path built with `Join-Path` from `$PSScriptRoot`, as §6 already requires. Moving a lab directory breaks the import loudly, which is acceptable.
- The static guard's regex is deliberately broad on the launch side and narrow on the target side; a suite that shells `pwsh` at a `tools/` script or a `$TestDrive` fixture (`tests/DryRun-Pester-Gate`, `Avm-Module-Update`, `Exit-Code-Propagation`, `Workflow-Exit-Gating`, `LabCycle`) must not be flagged. Verify with the existing corpus before merging.
- No lab script or Bicep changes; no CHANGELOG-visible behaviour change beyond a new standards section.

### Testing Requirements

**Test Cases Needed:**
1. 5.2 suite still passes end to end after the refactor, on a box with Az installed and a cached login, and exit 99 is not observed (`It 'shadows the real Az cmdlets…'`).
2. Guard suite, behavioural: withholding the stub import yields exit 99 and a `[HARNESS]` line; with the stub imported the generated script's own exit code comes back.
3. Guard suite, static: the 5.2 suite passes the rule; a temp copy of it with the assertion block removed fails the rule; none of the five `tools/`/fixture child-process suites is flagged.
4. Full corpus green in both runners.

**Validation Commands:**
```powershell
Invoke-Pester -Path .\module-5-monitoring-maintenance\5.2-business-continuity\tests\Remove-LabResource.Tests.ps1 -Output Detailed
Invoke-Pester -Path .\tests\Lab-Script-Harness-Guard.Tests.ps1 -Output Detailed
Invoke-Pester -Path (@('.\tests') + (Get-ChildItem -Directory -Filter 'module-*' | Get-ChildItem -Recurse -File -Filter '*.Tests.ps1').FullName)
.\tools\Invoke-DryRun.ps1 -Check Pester
Invoke-ScriptAnalyzer -Path .\tests\Support -Recurse -Settings .\PSScriptAnalyzerSettings.psd1
```

## Implementation Plan

1. Create `tests/Support/LabScriptStub.psm1` by lifting `Initialize-StubModule` and the launch half of `Invoke-CleanupScript` from the 5.2 suite, parameterising module name, command list, body and required modules.
2. Point the 5.2 suite at the helper; run it; confirm 16/16 and no exit 99.
3. Write `tests/Lab-Script-Harness-Guard.Tests.ps1` (static rule + behavioural exit-99 test); run against the corpus and confirm zero false positives.
4. Add the §6 subsection and the dry-run-harness paragraph.
5. Run the full Pester corpus, `tools/Invoke-DryRun.ps1`, and PSScriptAnalyzer; open the PR with `Closes #112` (no live Azure pass is needed: nothing under `scripts/` changes).
6. Open a follow-up issue for the in-process `tests/LabCycle.Tests.ps1` probe-splatting hazard.

This RCA document should be used by the `piv-implement-issue` skill.

## Next Steps

1. Review this RCA document
2. Run the `piv-implement-issue` skill with issue #112 to implement the fix
3. Run the `piv-commit` skill after implementation complete
