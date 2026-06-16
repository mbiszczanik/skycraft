# ADR-0002: Branch protection rules for `main`

- **Status:** Accepted
- **Date:** 2026-05-26
- **Deciders:** @mbiszczanik

## Context

With ADR-0001 making `main` the only long-lived branch, the protection
rules on `main` are the entire safety net of the project. They have to
work for two distinct cases at once:

1. **Solo maintainer day-to-day** — must not block merges of the
   maintainer's own PRs.
2. **External contributors via fork PRs** — must still go through review
   (= the maintainer's approval) before landing.

The previous configuration used **Require approvals ≥ 1**, which is
self-locking for a single-maintainer project: the maintainer cannot
approve their own PR, and is the only person with write access who could.
Every merge therefore required "bypass rules", which works but leaves a
trail of bypass markers and is not the right mental model.

## Decision

Protection rules for `main` are:

- **Require a pull request before merging** — enabled. No direct pushes
  to `main`.
- **Block force pushes** — enabled. Force pushes to `main` are never
  legitimate.
- **Restrict deletions** — enabled. `main` cannot be deleted.
- **Require linear history** — enabled. Squash-merge only; no merge
  commits on `main`.
- **Require conversation resolution before merging** — enabled. All
  review threads must be closed.
- **Require status checks to pass** — enabled. The required checks are
  `PSScriptAnalyzer`, `Repository Standards (Pester)`, and `Bicep Build
  (Linter)`, defined in `.github/workflows/lint.yml`.
- **Require approvals** — **disabled**, with the explicit understanding
  that external contributors still need maintainer approval because only
  the maintainer has merge permission. If/when a second maintainer joins,
  this is revisited via a new ADR.

Merge method: **squash and merge only**. Other options disabled.

## Consequences

**What we gain:**

- The maintainer's own PRs merge without bypass markers.
- External PRs still cannot reach `main` without the maintainer pressing
  Merge, which is the actual review gate.
- A single, simple set of rules — easy to explain in `CONTRIBUTING.md`.

**What we give up:**

- No formal "two pairs of eyes" gate. Acceptable in a solo project; the
  PR description + diff review by the maintainer is the eyes.
- ~~No automated quality gate yet — `Require status checks` is configured
  but inert until CI exists.~~ **Resolved (2026-06-16):** CI now exists and
  `Require status checks` enforces the `lint.yml` jobs before merge.

**Follow-up tasks:**

- ✅ **Done (2026-06-16):** `.github/workflows/lint.yml` added with
  `Bicep Build (Linter)`, `PSScriptAnalyzer`, and `Repository Standards
  (Pester)`; all three are wired into the `Require status checks` list.
  A Markdown lint job is still not present — add it and wire its name in
  when it lands.
- When a second maintainer is added, write a new ADR re-enabling
  `Require approvals ≥ 1` and adjust this one's status.

## Alternatives considered

- **Keep `Require approvals ≥ 1` and use admin bypass.** Rejected: every
  merge is a bypass; loses the signal value of "bypass means something
  unusual happened".
- **Repository Rulesets with a bypass list (maintainer always bypasses).**
  Considered, viable, but more configuration surface than is justified
  for a single-maintainer project today. Worth re-evaluating if/when a
  second maintainer joins.
