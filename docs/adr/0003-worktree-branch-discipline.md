# ADR-0003: Use git worktrees for multi-commit work

- **Status:** Accepted
- **Date:** 2026-05-26
- **Deciders:** @mbiszczanik

## Context

During the architecture-layer session on 2026-05-26, mid-session the
active branch in the shared working copy switched unexpectedly: a fresh
`develop → main` merge (`7ee7620`) appeared between commits, and a commit
intended for `feature/architecture-layer` ended up on `develop` (and was
then auto-synced to `origin/develop`). Recovery required `cherry-pick` +
`reset --hard`.

The root cause of the branch switch is still unconfirmed (suspected:
external process operating in the shared checkout, a hook, or an
auto-sync tool). What is clear is that any work that:

- spans multiple commits,
- runs concurrently with other tooling on the same checkout, or
- is performed by an automated agent that does not visually verify the
  branch before every operation,

is exposed to this class of mistake.

`git worktree` makes each branch a physically separate directory with its
own `HEAD`. Operations on one worktree cannot change the branch of
another. This eliminates the shared-checkout failure mode entirely.

## Decision

For any work that meets **any** of the following criteria, use an isolated
`git worktree`:

- The work is expected to span **two or more commits**.
- The work is dispatched to an **automated agent** (Claude Code, IDE
  extensions doing edits, scripted tooling).
- The work runs **concurrently** with other ongoing work on the same
  repository.

The worktree is created as a sibling directory of the main checkout, not
inside it:

```
git worktree add -b feature/<name> ../skycraft-<short-name> origin/main
git -C ../skycraft-<short-name> branch --unset-upstream feature/<name>
```

The `--unset-upstream` step is deliberate: it prevents accidental `git
push` from the feature branch onto the base branch.

When work is done and merged, prune the worktree:

```
git worktree remove ../skycraft-<short-name>
git branch -d feature/<name>   # after PR is merged
```

For trivial single-edit / single-commit work — typo fixes, README tweaks
— a worktree is not required.

## Consequences

**What we gain:**

- The 2026-05-26 class of incident cannot recur: an external `git
  checkout` in the main repo directory does not affect the worktree's
  `HEAD`.
- Multiple features can be worked on in parallel without `git stash`
  juggling.
- Agents have a stable workspace that survives external operations on
  the main checkout.

**What we give up:**

- A small amount of disk space per worktree (one extra working copy of
  the source tree; `.git/` is shared).
- One extra step at the start and end of feature work.
- Shared `.git/` means concurrent ref operations on the *same* branch
  across worktrees can still collide. We avoid this by using a fresh
  branch per worktree, which is already the rule.

**Follow-up tasks:**

- Reference this ADR from `CONTRIBUTING.md`'s branching section.
- If the root cause of the original branch switch is eventually
  identified (hook, tool, etc.), add a postscript or follow-up ADR.

## Alternatives considered

- **Discipline only — check `git symbolic-ref --short HEAD` before every
  commit.** Rejected as the primary mechanism: it relies on the operator
  (or agent) remembering, every single time. Worktrees make the
  guarantee structural rather than behavioural. Verifying the branch is
  still a sensible secondary safeguard inside a worktree.
- **Pre-commit hook that aborts when the branch doesn't match an
  expected value.** Viable as an additional safety net but does not by
  itself prevent the shared-checkout race. Worth adding later as a
  belt-and-braces measure; orthogonal to this ADR.
