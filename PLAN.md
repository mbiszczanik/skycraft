# Bug burndown to 2026-11-14

Deadline: every open `bug` issue is closed with evidence, or carries a recorded decision (parked, not planned), by 2026-11-14.
Source: `gh issue list --label bug --state open` on 2026-11-03 (27 issues). Statuses below come from issue comments, not from the code; re-read each issue before acting (tracker first, per working rules).
Unit of a block: one run that collects every gap, one PR for first-class gaps, one confirming run. A new gap found in a confirming run is filed, not fixed in the same block.
Ownership check before starting: worktree `fix/257-exit-lab-helper` is open and overlaps #398; ask which session owns it.

## Exit criteria per issue

- When a bug is fixed in code and its live check passed on the PR branch, the issue is closed by the PR (`Closes #N`) with command, exit code and date.
- If a live item is still owed, then the PR uses `Refs #N` and the issue stays open until a dated run closes it by hand.
- If a bug cannot be verified before the deadline, then the issue gets a comment with the reason and the class (blocks course, blocks tooling, blocks nobody) and is labelled `parked`.

## Block 0, 2026-11-04: status sweep (no Azure)

- [x] Re-read all 27 issues and merged PRs; status of each issue checked against `origin/main` on 2026-11-03.
- [ ] Close #357 and #197 (code fixed on main, last issue comments stale; #197 still owes a Portal label check by the maintainer).
- [ ] Close #398 only after R8 (count printed `[ERROR]` lines) and R9 (Az and Graph calls outside try/catch end through `Exit-Lab`) are confirmed in code; all 63 scripts already end through `Exit-Lab`.
- [ ] Add label `fixed-awaiting-verification` to issues that need only a live run: #370, #373, #371 (after the 3.2 disk check), #340, #290, #238, #473, #408, #432.
- [ ] Delete stale branch `origin/fix/257-exit-lab-helper` (78 files, 2026-10-21, superseded by #410, #423, #428, #494) only after the maintainer confirms.

Test subscription for live runs: the maintainer's Visual Studio Enterprise MPN subscription, confirmed 2026-11-03 (id kept out of this file). Five subscriptions share that name in the tenant; before every live write, check the id with `az account show`.

## Block 1, 2026-11-05 to 06: offline fixes (CI only)

One PR. Evidence: green CI run id at head, including an `ubuntu-latest` Pester run for #414.

- [ ] #414 `-Force` or `git ls-files` in `tests/` listings; `.patches` filter for both separators
- [ ] #384 `LabScriptStub` exits non-zero on parse error; test with an unparseable script
- [ ] #415 lab-specific preflight only for selected labs (`RequiresOpsEmail` model)
- [ ] #398 R8 (count printed `[ERROR]`) and R9 (calls outside try/catch end through `Exit-Lab`)
- [ ] #393 redaction helper in `tools/LabCommon.psm1`, applied in 32 scripts
- [ ] #346 lint: menu paths name their collapsed group
- [ ] #452 remaining Module 1-3 pinned calls with `-ApiVersion`
- [ ] #372 lock lift and restore (`Invoke-LabWithoutLock`) in the Remove-LabResource scripts of Labs 2.1, 2.2, 2.3, 3.1, 3.2, 3.3; Labs 4.1-5.3 already have it
- [ ] #371 Lab 3.2 Test-Lab also reads disk encryption state
- [ ] Run in parallel: prepare the Module 1 live run (read `param(` blocks and `tools/lab-cycle-manifest.psd1` entries for Labs 1.1-1.3) while these fixes are written
- [ ] #380 Lab 1.2 matches only `malfurion.stormrage@<initial domain>`

## Block 2, 2026-11-07 to 08: Module 1 live run

- [ ] Run 1: Labs 1.1-1.3 collect gaps (#408 second check, #340 failure path, #397, #380, #406 Lab 1.2/1.3 end state)
- [ ] PR for gaps; confirming run
- [ ] #402 R9: needs a never-used subscription; if none exists by 2026-11-08, record the decision and keep `parked`

## Block 3, 2026-11-09 to 10: Module 5 live run (largest)

- [ ] Run 1: Labs 5.1-5.3 collect gaps (#473 Failed-return path, #373 vault diag setting, #371 5.2/5.3 checks, #370 unregistered providers, #238 failing lookup, #452 5.3 connection monitor, #397 5.2, #406 5.1 DCR association, #197 line 248, #357 5.1)
- [ ] PR for gaps; confirming run

## Block 4, 2026-11-11: Module 2 live run

- [ ] Run 1: Labs 2.1-2.3 (#274 public IPs with zone, #275 items 1-2, #352 re-run guard or guide note, #340)
- [ ] PR for gaps; confirming run

## Block 5, 2026-11-12: Modules 3-4 live run

- [ ] Run 1: Labs 3.1-4.4 (#290 failing lookup exit 1, #372 lock lift and restore, #390 largeFileSharesState, #406 Lab 3.4 autoscale, #432 3.2.1 SSH and Issue 3 walk)
- [ ] PR for gaps; confirming run

## Block 6, 2026-11-13 to 14: close-out

- [ ] Close each issue by hand with evidence, or record the parked decision
- [ ] Remaining gaps filed as new issues, not fixed
- [ ] Delete this file in the PR's last commit

## Risks

- Live runs are about 90 minutes each and need the test tenant; a throttled or blocked run costs a day.
- #402 R9 depends on a subscription that does not exist yet.
- Another session may change an issue; re-read before each block.
