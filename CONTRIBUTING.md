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
- A PR that touches lab content (`module-*/`, `scripts/`, the lab cycle tooling in `tools/`) must declare its live verification in its body - `Live-verified: <what was run>` or `Live-verification: deferred -> #<issue>` - and a deferred PR is opened as a **draft** and links its issue with `Refs #N`, never `Closes #N`. The `Live Verification Declared` check enforces it; see [ADR-0006](docs/adr/0006-pr-live-verification-gate.md).

For multi-commit work — and for any work driven by an automated agent — use a
`git worktree` to isolate the feature from the main checkout (see
[ADR-0003](docs/adr/0003-worktree-branch-discipline.md) for the rationale and
the exact commands).

## 🛠️ How to Contribute

1.  **Fork the Repository**: Create your own copy of the project.
2.  **Create a Branch off `main`**: Use a descriptive name (e.g., `feature/lab-3.1-vm`, `fix/typo-lab-1.2`).
3.  **Make Changes**: Implement your feature or fix.
4.  **Verify**: Run `.\tools\Invoke-DryRun.ps1` (the offline gate that mirrors CI without needing `az login`), plus the relevant `Test-Lab.ps1` scripts to ensure no regressions.
5.  **Submit a Pull Request against `main`**: Title it as a Conventional Commit (see the Releases section below); the title becomes the squash-commit title and a line in the release notes. Describe your changes clearly and link to any relevant issues. PRs are squash-merged. If you changed lab content, fill in the **Live verification** section of the template; if you could not run the live checks, open the PR as a draft, link the issue with `Refs #N`, and name the issue that tracks the live pass.

## 🧪 Testing

All new labs and scripts must include validation steps.

- **Before pushing**: Run `.\tools\Invoke-DryRun.ps1`. It parses every PowerShell file, runs PSScriptAnalyzer, and compiles every Bicep template and parameter file — the whole offline half of CI, no Azure authentication required. See [docs/dry-run-harness.md](docs/dry-run-harness.md).
- **PowerShell**: Use `Test-Lab.ps1` scripts for Pester-like validation.
- **Documentation**: Ensure all links work and screenshots are placed in the correct `images/` directory.

## 🚀 Releases

Releases are automated with [release-please](https://github.com/googleapis/release-please).
The title of your pull request is the squash-commit title on `main`, and the bot reads
those titles to decide the next version and to write the release notes.

- **Title your PR as a Conventional Commit**: `type(scope): subject`, scope optional,
  subject lowercase by convention (e.g. `docs(5.2): say how Deploy-Bicep.ps1 creates
  backup policies`). The `PR Title (Conventional Commits)` check refuses a title that is
  not in that form or whose type is not in the table below; it does not check the
  subject's case, so keep it lowercase yourself. Do not start a paragraph of the PR
  description with `type: ` either: the bot reads it as a second commit. Allowed types
  and what they do while the project is at `0.y.z`:

  | Type | Version bump | In the release notes |
  |---|---|---|
  | `fix`, `perf`, `revert`, `docs` | patch | yes |
  | `feat` | minor | yes |
  | `feat!` / `BREAKING CHANGE:` footer in the PR description | minor | yes |
  | `test`, `chore`, `ci`, `refactor`, `build` | none | no |

- **What happens automatically**: after every merge to `main` the
  [Release Please workflow](.github/workflows/release-please.yml) opens or refreshes a
  pull request titled `chore(main): release X.Y.Z` that bumps `version.txt`,
  `.release-please-manifest.json` and prepends the new section to `CHANGELOG.md`.
  Merging that PR creates the `vX.Y.Z` tag and the GitHub Release with the section as
  the notes. Nothing to type anywhere.
- **To cut a release**: merge the open `chore(main): release X.Y.Z` pull request.
- **To force a version** (for example the jump to 1.0.0): merge a PR whose description
  **ends** with the line `Release-As: 1.0.0`, on its own after the pre-merge checklist;
  the bot only reads footers from the last block of the description, so one placed
  under *Summary* is ignored. Hand edits to the Release PR are overwritten on the bot's
  next run (every push to `main`), so do not bump the version there.
- **If a run failed** (an API error after the Release PR merged, a stale Release PR):
  re-run the workflow from the Actions tab (`workflow_dispatch`); release-please is
  idempotent and finishes what was left. If it aborts with "untagged, merged release PRs
  outstanding", remove the `autorelease: pending` label from the already-released PR
  and re-run.
- **If the run fails on the token step**: the GitHub App `skycraft-release` key or
  Client ID is missing or was rotated. On the App's page generate a new private key,
  then `gh secret set RELEASE_APP_PRIVATE_KEY --repo mbiszczanik/skycraft < key.pem`
  (and `gh secret set RELEASE_APP_ID --repo mbiszczanik/skycraft --body "<Client ID>"`
  if that changed), delete the local `.pem`, re-run the workflow, and once it is green
  delete the old key on the App's page.

Sections up to 0.9.0 in `CHANGELOG.md` were written by hand in Keep a Changelog form and
stay as they are. The reasoning is in [ADR-0007](docs/adr/0007-release-with-release-please.md).

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
