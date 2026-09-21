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
   `Invoke-LabScript.ps1`, `LabCycle.psm1`, `lab-cycle-manifest.psd1`).
   PRs that touch only tests, docs outside the labs, CI or the gate itself
   are not gated.

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
- **Rely on the PR template checkbox.** That is what #132 had. A template
  is advice; it is skipped by `--body-file`, by the API, and by habit.
