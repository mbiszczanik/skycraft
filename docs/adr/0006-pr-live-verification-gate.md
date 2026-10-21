# ADR-0006: A lab-content PR declares its live verification before it can merge

- **Status:** Accepted
- **Date:** 2026-09-21
- **Deciders:** @mbiszczanik

## Context

The checks that matter most for a lab - `Invoke-LabCycle.ps1`, or a lab's
`Deploy-Bicep.ps1` followed by its `Test-Lab.ps1` against the SkyCraft
subscription - deliberately do not run in CI. A pre-merge gate must not
depend on the state of a subscription, the full cycle takes ~90 minutes
and costs money, and the CI runner has no credentials
(`docs/dry-run-harness.md` §3.2). They are run by hand, on a developer
machine, and until now the only record of that was a checkbox in
`.github/PULL_REQUEST_TEMPLATE.md`.

PR #132 (issue #79) showed the hole. Its body stated, correctly, that the
manual follow-the-guide pass had **not** been run. It was nevertheless
opened ready-for-review with `Closes #79`, every CI check was green, and
the maintainer merged it: the issue closed with its acceptance criterion
unmet, and nothing in the repository recorded that a live pass was still
owed. The template's "`Test-Lab.ps1` passes for affected lab(s)" box was
never ticked - a PR body written with `gh pr create --body-file` does not
contain the template at all - and nothing noticed.

Two things were missing: a **mechanical** reason the merge button would
not work for such a PR, and a **place** where the deferred verification
would be tracked rather than forgotten.

## Decision

1. **A PR that touches lab content must declare its live verification in
   its body**, as exactly one of these lines:

   ```text
   Live-verified: <what was run - Invoke-LabCycle run id, or labs + date>
   Live-verification: deferred -> #<issue tracking the live pass>
   ```

   "Lab content" is any path under `module-*/`, `scripts/`, or the lab
   cycle tooling in `tools/` (`Invoke-LabCycle.ps1`, `Remove-LabCycle.ps1`,
   `Invoke-LabScript.ps1`, `LabCycle.psm1`, `lab-cycle-manifest.psd1`),
   except a lab's own `tests/` directory. PRs that touch only tests - the
   repo-wide `tests/` or a lab-local `module-*/**/tests/` suite, which
   stubs Az and runs in CI - docs outside the labs, CI or the gate itself
   are not gated. Docs inside a lab (its guide, README, checklists) stay
   gated: following the guide live is their acceptance criterion (#132).

2. **A deferred PR must not close the issue it addresses.** With
   `Live-verification: deferred -> #N` in the body, a GitHub closing
   keyword (`close`/`fix`/`resolve` + `#N`) fails the gate; the PR links
   its issue with `Refs #N`, and the issue is closed by hand once the
   live pass has run - normally from the follow-up issue the declaration
   names.

3. **The gate is a required status check.** `.github/workflows/pr-gate.yml`
   runs `tools/Test-PrLiveVerification.ps1` on every PR event that can
   change the answer (`opened`, `edited`, `synchronize`, `reopened`,
   `ready_for_review`) and reports as `Live Verification Declared`. That
   check is added to the `Protect Main Branch` ruleset's required checks,
   alongside the three from ADR-0002. The decision logic is pinned by
   `tests/Pr-Live-Verification.Tests.ps1`.

4. **A PR whose verification is still owed is opened as a draft**
   (`gh pr create --draft`). A draft cannot be merged, so this is the
   human-side half of the same rule; the gate is what catches the case
   where the draft is promoted without the declaration being updated.

5. **A deferral needs the maintainer's approval** (amended 2026-10-14,
   #338). A deferred PR passes the gate only while it carries the label
   `live-deferral-approved`, which the maintainer adds when merging
   before the live pass is acceptable for that PR. Without it the check
   fails and says how to get out: run the live pass and declare
   `Live-verified:`, or get the label. The workflow also runs on
   `labeled` and `unlabeled` and reads the labels from the API. Before
   this, a `deferred -> #N` line alone turned the check green, so
   deferring was the default rather than a decision (PR #337 went green
   while a step's success path had never been seen live).

6. **A lab fix is done when it ran live on its branch and again on
   `main`** (amended 2026-10-20, #404). The maintainer's Definition of
   Done for a lab fix is "merged and works after tests", and in the
   2026-10-20 pass fix PRs were deferred while every fix had only offline
   evidence: PR #382's fix could run in the test tenant and passed when
   it was run (Lab 1.1 `Test-Lab.ps1` 10/10, Lab 1.2 8/8, exit 0), and an
   implementer's partial test run reported 0 failures while CI failed on
   a suite it had left out. From now on:

   - **(a) Live run on the branch.** A fix PR re-runs, on its own branch
     and before it asks to merge, the live check that found the defect
     (the failing steps, `Test-Lab.ps1` of the affected labs) and declares
     `Live-verified: <what ran, where, date, exit codes>`.
   - **(b) Deferral only for a blocker.** `Live-verification: deferred`
     with the `live-deferral-approved` label is kept for a live check that
     cannot run in the maintainer's test environment: a brand-new
     subscription, an account that has not consented yet, Cloud Shell. The
     PR says why on exactly one more line,

     ```text
     Live-verification-blocker: <why the live check cannot run in the test environment>
     ```

     and the gate fails a deferred PR without it, with two of them, or
     with a blank or placeholder reason (`<...>`, `TBD`, `TODO`, `n/a`,
     `none`). The blocker is a separate line so the deferred line and the
     PR bodies written before this amendment keep their form; they fail
     only until the line is added or the live check is run.
   - **(c) Repeat on `main`.** After merge the live check runs again on
     `main`, because stacked and overlapping PRs can break each other. Its
     result is recorded on the issue that tracks the live check, and only
     then is that issue closed by hand.
   - **(d) Full offline evidence.** A PR's offline evidence is the full
     test set CI runs (`./tests` and every `module-*/**/tests` suite, as
     `.github/workflows/lint.yml` runs them) plus the green CI run id at
     the PR's head, never a subset.

   The gate enforces (b); (a), (c) and (d) are carried by the PR template
   and `CONTRIBUTING.md`, and the gate cannot check them.

## Consequences

**What we gain:**

- Merging lab content without a live pass becomes an explicit, recorded
  decision (`deferred -> #N`) instead of an omission. The follow-up issue
  is the ledger.
- An issue with a live acceptance criterion can no longer be closed by a
  merge that did not meet it.
- The gate needs no Azure access and runs in seconds; it does not change
  how or when the live checks themselves are run.

**What we give up / accept as cost:**

- The declaration is self-reported. `Live-verified: <run id>` is not
  checked against anything; a wrong or invented value passes. Making the
  orchestrator commit a run ledger that the gate cross-checks is the
  natural next step and is out of scope here.
- Every lab-content PR carries one more line of ceremony, and a body
  edit is needed to unblock a PR that forgot it (the workflow re-runs on
  `edited`).
- The approval label is not removed when new commits arrive: once
  given, it covers later pushes to the same PR. Anyone who can label
  PRs can give it; in this repository that is the maintainer.
- The blocker line is self-reported like the rest: the gate rejects an
  empty or placeholder reason, not a wrong one. Whether the test
  environment really cannot run the check is the maintainer's call when
  giving the label (decision 6).
- Every PR that was deferred before decision 6 fails its gate on the
  next event until it gains a blocker line or a `Live-verified:` line.

**What we must do as a follow-up:**

- Add `Live Verification Declared` to the required status checks of the
  `Protect Main Branch` ruleset once the workflow has reported at least
  once (GitHub only offers a check name it has seen).
- Open the follow-up issue for the live pass #132 still owes, and record
  it against #79.

## Alternatives considered

- **Run the live cycle in GitHub Actions with OIDC to the subscription.**
  Rejected: ~90 minutes and real spend per PR, and it makes the merge gate
  depend on the state of a shared subscription - the exact coupling the
  dry-run harness was built to avoid.
- **A `needs-live-verification` label that a workflow fails on.** Viable,
  and simpler to read on the PR list, but the label carries no
  information about *what* was or was not run and *where* it is tracked.
  The body line does, and it lives in the merge commit's history.
  (Decision 5 uses a label differently: not instead of the body line,
  but as the maintainer's approval on top of it.)
- **Rely on the PR template checkbox.** That is what #132 had. A template
  is advice; it is skipped by `--body-file`, by the API, and by habit.
