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

## 🐛 Reporting Issues

If you find a bug or have a suggestion, please open an Issue using the provided templates. Include:

- Description of the issue
- Steps to reproduce
- Expected behavior vs. Actual behavior
- Screenshots (if applicable)

Thank you for helping us build SkyCraft!
