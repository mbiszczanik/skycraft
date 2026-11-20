# AGENTS.md

## Purpose

SkyCraft is an AZ-104 learning project: five modules of hands-on Azure labs (`module-*/`), each with a guide, deploy and test scripts, and Bicep. `README.md` has the overview; `CONTRIBUTING.md` is the authority for workflow and release rules, this file only summarises what every contributor needs first.

## Setup

PowerShell 7 (`pwsh`), Bicep CLI, Pester, PSScriptAnalyzer. Install the pre-commit hook once per clone: `git config core.hooksPath tools/git-hooks`. It refuses a commit on `main` and a commit in the main checkout while another worktree exists.

## Commands

- `mise run check:fast`: every PowerShell file parses. Seconds, offline.
- `mise run check`: the offline lane CI runs (`tools/Invoke-DryRun.ps1`: parse, analyzer, Bicep, Pester). No `az login` needed.
- `Test-Lab.ps1` in a lab folder: live validation of that lab; it needs an Azure sign-in and a test subscription.

## Layout

- `module-N-*/N.M-name/`: one lab (`lab-guide-N.M.md`, `lab-checklist-N.M.md`, `ARCHITECTURE.md`, `scripts/`, `tests/`, `images/`).
- `tests/`: repository-wide Pester suites.
- `tools/`: dry-run harness, guide-drift tool, lab cycle tooling, git hooks.
- `docs/`: standards (`project-standards.md`, `powershell-standards.md`, `bicep-standards.md`, `lab-guide-standards.md`, `lab-acceptance.md`) and `adr/`.

## Conventions

- Branch from `main` as `feature/*`, `fix/*`, `docs/*` or `chore/*`; changes land by pull request, squash-merged. Use a git worktree for multi-commit or automated work (ADR-0003). Never pass `--no-verify`.
- The PR title is a Conventional Commit (`type(scope): subject`); it becomes the release note line.
- A PR that touches lab content declares `Live-verified: <what ran, where, date, exit codes>` or `Live-verification: deferred -> #<issue>` (ADR-0006). A deferred PR is a draft and uses `Refs #N`, never `Closes #N`.
- Offline evidence is the full CI test set plus the green CI run id at the PR head, never a subset.
- Never commit secrets, subscription or tenant ids, or personal e-mail addresses.
