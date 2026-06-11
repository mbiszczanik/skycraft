# Architecture Decision Records (ADR)

This folder holds the load-bearing decisions behind SkyCraft — process,
tooling, and architecture. Each ADR is a short, dated note explaining
**what** was decided, **why** at the time, and **what consequences** the
decision has.

ADRs are append-only. We don't edit them after they are accepted — we write
a new ADR that supersedes the old one. That way the *history of the
project's thinking* stays intact, which is more valuable than a tidy
"current state" document that hides the reasoning.

## What goes here vs. elsewhere

| Document type | Lives in | Example |
|---|---|---|
| Why a decision was made | `docs/adr/` (this folder) | "Why GitHub Flow, not Git Flow" |
| How a contributor should work | `CONTRIBUTING.md` | "Branch off main, open PR, squash-merge" |
| Conventions for code style | `docs/bicep-standards.md`, `docs/powershell-standards.md` | "Bicep header block format" |
| The lab architecture itself | `DESIGN-DECISIONS.md` + per-lab `ARCHITECTURE.md` | "Why hub-spoke topology" |
| The Azure baseline & personas | `SPECIFICATION.md` | "Warcraft persona → RBAC mapping" |

If you cannot tell where something belongs: process/meta decisions → ADR;
domain/lab decisions → `DESIGN-DECISIONS.md`.

## How to add a new ADR

1. Copy `template.md` to `NNNN-short-kebab-title.md` (next free number).
2. Fill in Context / Decision / Consequences. Keep it short — one page if
   possible. The point is to capture reasoning, not write a thesis.
3. Open a PR like any other change. The ADR is `Proposed` until merged;
   then it is `Accepted`.
4. If a later ADR overrules this one, do not delete or edit this file —
   change its status to `Superseded by ADR-NNNN` and add a link.

## Status values

- **Proposed** — under discussion in a PR.
- **Accepted** — merged; this is current policy.
- **Superseded by ADR-NNNN** — overruled by a later decision; kept for
  history.
- **Deprecated** — no longer applies but was never explicitly replaced.

## Format

We use a lightweight [MADR](https://adr.github.io/madr/) style. No
ceremony, no required sections beyond Context / Decision / Consequences.
See `template.md`.

## Index

| # | Title | Status |
|---|---|---|
| [0001](0001-use-github-flow.md) | Use GitHub Flow (drop `develop`) | Accepted |
| [0002](0002-branch-protection-rules.md) | Branch protection rules for `main` | Accepted |
| [0003](0003-worktree-branch-discipline.md) | Use git worktrees for multi-commit work | Accepted |
