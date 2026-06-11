# ADR-0001: Use GitHub Flow (drop `develop`)

- **Status:** Accepted
- **Date:** 2026-05-26
- **Deciders:** @mbiszczanik

## Context

SkyCraft started with a Git Flow-style branching model: `main` for stable
content, `develop` as integration branch, `feature/*` for work in progress.
The visible cost of this model in a solo project has been:

- Ongoing `develop` ↔ `main` synchronisation work (see commits
  `ff49c69 fix: sync main into develop ...`, `06cc88a Develop (#33)`,
  `84555eb Develop (#30)`).
- A second protected branch to configure and reason about — branch
  protection rules, sync expectations, merge direction.
- An extra surface area for accidents: during the architecture-layer
  session on 2026-05-26, a commit was inadvertently applied to `develop`
  instead of the feature branch and then auto-synced to `origin/develop`,
  forcing a cherry-pick + reset to recover.

Git Flow was designed for batch releases with multiple developers
integrating concurrently. SkyCraft has neither: it is a single-maintainer
learning project with continuous improvement and no release cadence in the
"v1.2.0" sense.

## Decision

We adopt **GitHub Flow**:

- `main` is the only long-lived branch.
- All work happens on short-lived branches named `feature/*`, `fix/*`,
  `docs/*`, `chore/*`.
- Changes land on `main` exclusively via Pull Request.
- PRs are merged with **squash merge** for a clean linear history.
- The `develop` branch is retired.

## Consequences

**What we gain:**

- One protected branch to configure and reason about.
- No more `develop` ↔ `main` synchronisation commits cluttering history.
- One fewer merge target to mis-aim at — the class of incident that
  triggered this ADR cannot recur in the same form.
- Alignment with how the majority of comparable solo/small OSS projects
  work today (Astro, htmx, Vite, Tailwind, Bun).

**What we give up:**

- No dedicated integration branch where multiple in-flight features can
  bake together before promotion. Acceptable: SkyCraft does not currently
  have multiple concurrent feature branches needing joint testing.
- No "playground" branch separate from `main`. If we later need one
  (e.g. for experimental lab variants), we introduce a long-lived
  `experiment/*` branch with explicit ADR — we do not silently re-add
  `develop`.

**Follow-up tasks:**

- Delete `develop` from the GitHub remote once any open `develop`-targeted
  PRs are closed or re-targeted at `main`.
- Update branch protection on `main` per ADR-0002.
- Update `CONTRIBUTING.md` to describe the GitHub Flow workflow.

## Alternatives considered

- **Keep Git Flow.** Rejected: the ongoing tax of `develop` ↔ `main` sync
  has no upside in a solo project without batch releases.
- **Trunk-based development with no protection on main.** Rejected: even
  solo, branch protection on `main` catches force-push and accidental
  delete mistakes, and the PR workflow is the natural place to attach CI
  later.
