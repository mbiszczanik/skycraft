# Contributing to SkyCraft

Thank you for your interest in contributing to SkyCraft! We welcome contributions from the community to help make this the best Azure learning project available.

## 📋 Standards and Guidelines

Before submitting a Pull Request (PR), please review our project standards to ensure your contribution aligns with the project's structure and style:

- **[General Standards](docs/project-standards.md)**: Naming conventions, directory structure, and tagging strategy.
- **[PowerShell Standards](docs/powershell-standards.md)**: Scripting style, error handling, and formatting.
- **[Bicep Standards](docs/bicep-standards.md)**: Infrastructure as Code modules and parameters.
- **[Dry-Run Harness](docs/dry-run-harness.md)**: The offline pre-push gate and the live checks it deliberately leaves to you.

## 🌿 Branching & PR workflow

SkyCraft follows **GitHub Flow** (see [ADR-0001](docs/adr/0001-use-github-flow.md)):

- `main` is the only long-lived branch.
- All work happens on short-lived branches: `feature/*`, `fix/*`, `docs/*`, `chore/*`.
- Changes land on `main` exclusively via Pull Request, **squash-merged** for linear history.
- Branch protection rules on `main` are documented in [ADR-0002](docs/adr/0002-branch-protection-rules.md).

For multi-commit work — and for any work driven by an automated agent — use a
`git worktree` to isolate the feature from the main checkout (see
[ADR-0003](docs/adr/0003-worktree-branch-discipline.md) for the rationale and
the exact commands).

## 🛠️ How to Contribute

1.  **Fork the Repository**: Create your own copy of the project.
2.  **Create a Branch off `main`**: Use a descriptive name (e.g., `feature/lab-3.1-vm`, `fix/typo-lab-1.2`).
3.  **Make Changes**: Implement your feature or fix.
4.  **Verify**: Run `.\tools\Invoke-DryRun.ps1` (the offline gate that mirrors CI without needing `az login`), plus the relevant `Test-Lab.ps1` scripts to ensure no regressions.
5.  **Submit a Pull Request against `main`**: Describe your changes clearly and link to any relevant issues. PRs are squash-merged.

## 🧪 Testing

All new labs and scripts must include validation steps.

- **Before pushing**: Run `.\tools\Invoke-DryRun.ps1`. It parses every PowerShell file, runs PSScriptAnalyzer, and compiles every Bicep template and parameter file — the whole offline half of CI, no Azure authentication required. See [docs/dry-run-harness.md](docs/dry-run-harness.md).
- **PowerShell**: Use `Test-Lab.ps1` scripts for Pester-like validation.
- **Documentation**: Ensure all links work and screenshots are placed in the correct `images/` directory.

## 🚀 Releases

`CHANGELOG.md` is the single source of truth for versions. A release is the merge to
`main` that moves the `## [Unreleased]` items under a new `## [X.Y.Z] - YYYY-MM-DD`
heading; nothing else is typed anywhere.

- **What happens automatically**: the [Release workflow](.github/workflows/release.yml)
  runs on every push to `main` that changes `CHANGELOG.md`. It reads the topmost
  released section, and if the matching `vX.Y.Z` release does not exist yet it creates
  the tag on the merge commit and the GitHub Release with that section as the notes.
  A CHANGELOG edit that adds no new version finds the release already published and
  does nothing.
- **To cut a release**: in the PR, rename `## [Unreleased]` to `## [X.Y.Z] - YYYY-MM-DD`
  (adding a fresh empty `## [Unreleased]` above it), bump nothing else, and merge.
- **To check before merging**: `.\tools\Publish-Release.ps1 -WhatIf` prints the version,
  the target commit and the exact notes the workflow would publish.
- **To backfill or run by hand** (a missed release, a workflow outage):
  `.\tools\Publish-Release.ps1 -Target <merge-commit-sha>` with `gh auth login` done.
  The script is idempotent - it never edits or deletes an existing release or tag.

The reasoning is in [ADR-0005](docs/adr/0005-release-from-changelog.md).

## 📦 AVM module versions

The Bicep templates consume [Azure Verified Modules](https://aka.ms/avm) pinned to exact
versions, and Dependabot does not read Bicep registry references, so the pins have no
update signal of their own. Two things stand in for it:

- `.\tools\Get-AvmModuleUpdate.ps1` lists every pin next to the newest version
  `br/public` publishes. The [AVM Module Update Check workflow](.github/workflows/avm-module-update.yml)
  runs it on the first day of each quarter and fails - which notifies the maintainer -
  when any module has a newer version. Run it by hand any time; it needs no Azure login.
- Upgrading a module is a normal PR: update every reference **and** the catalogue in
  [docs/bicep-standards.md §4.4](docs/bicep-standards.md#44-avm-version-catalogue) together.
  `tests/Avm-Module-Pinning.Tests.ps1` and `tests/Avm-Module-Update.Tests.ps1` fail the
  PR if either side is left behind or a pin is not published.

## 🐛 Reporting Issues

If you find a bug or have a suggestion, please open an Issue using the provided templates. Include:

- Description of the issue
- Steps to reproduce
- Expected behavior vs. Actual behavior
- Screenshots (if applicable)

Thank you for helping us build SkyCraft!
