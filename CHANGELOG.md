# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Pester guard `tests/Avm-Module-Pinning.Tests.ps1`: every `br/public:avm/...` reference must pin an exact semver, each AVM module must resolve to a single version repo-wide, and `bicepconfig.json` must not define registry aliases. The suite also asserts that the scan itself matched at least one `.bicep` file and one AVM declaration, so the guard cannot pass vacuously.
- `.bicepparam` parameter files for the Module 1 Bicep entry points (Labs 1.2 and 1.3).

### Changed

- Bicep standards rewritten to an **AVM-first** policy (issue #62 v2): Azure Verified Modules consumed directly from `main.bicep` entry points, exact-version pinning with a repo-wide catalogue, canonical tag set (`Project`/`Environment`/`CostCenter`/`Owner`), an explicit-`dependsOn` rule, lab-friction override principle, and a documented Lab 3.1 hand-written-modules exception.
- Lint workflow now builds every `.bicepparam` file with `az bicep build-params`.
- Lint workflow now parses every `.ps1`/`.psm1`/`.psd1` with the PowerShell parser before running PSScriptAnalyzer, annotating each syntax error with its file and line. PSScriptAnalyzer's gate counts only `Severity -eq 'Error'` and reports none for a file that cannot be parsed, so a syntax error used to reach CI unnoticed unless a Pester container happened to fail on it.
- Module 1 Bicep converted to the AVM-first architecture (issue #62 v2, PR 1/6): resource groups via `avm/res/resources/resource-group`, RG-scope role assignments via `avm/res/authorization/role-assignment/rg-scope`, Lab 1.3 policy assignments called directly from `main.bicep`, and locks via the AVM `lock` parameter. Local modules `rg-role-assignment.bicep`, `locks.bicep`, and `policies.bicep` removed; `tags.bicep` retained as the documented fallback.
- Canonical four-tag set (`Project`/`Environment`/`CostCenter`/`Owner`) applied across Module 1: the non-canonical `Criticality` tag is dropped and the Lab 1.3 scripts take `-Owner` (default `mbiszczanik`) instead of `-AdminEmail`.

## [0.7.1] - 2026-07-27

### Removed

- `AUDIT-modules-2-5.md`: working audit report accidentally committed with the v0.7.0 release. All of its findings were already resolved in 0.7.0, and no file referenced it; recoverable from git history if needed.

### Changed

- `.gitignore` now excludes the private, un-checked-in `CLAUDE.local.md` assistant instructions file so it is no longer listed as untracked.

## [0.7.0] - 2026-07-10

### Added

- Repository hygiene baseline: `.gitattributes` enforcing line-ending normalization (CRLF for `*.ps1`/`*.psm1`/`*.psd1`/`*.cmd`/`*.bat`, LF for `*.sh`, `* text=auto` as the catch-all for other text files, and image/binary types marked binary) and `.editorconfig` for consistent editor settings.
- This `CHANGELOG.md`, following the Keep a Changelog format.
- GitHub issue and pull-request templates to standardize contributions.
- `.vscode/extensions.json` recommending the project's preferred editor extensions.
- Architecture documentation: per-module `ARCHITECTURE.md` notes for Modules 1 through 5.
- Root `DESIGN-DECISIONS.md` index with a README pointer.
- Architecture Decision Records: new ADR folder seeded with the first three records.
- Dependabot configuration and a documented vulnerability-reporting policy.
- Continuous integration via a lint workflow running PSScriptAnalyzer, Pester, and Bicep build.

### Changed

- README updated with a CI status badge and refreshed documentation links.
- Lint workflow extended with markdownlint and gitleaks CI jobs.
- PowerShell standards aligned with the Microsoft gold-path guidance.
- Bicep standards aligned with the Microsoft gold-path guidance.
- Contributing guide documents the GitHub Flow workflow.
- Module 5 Lab 5.2 business-continuity checklist expanded and completed.
- Module 1 README contract enforcement extended to verify the L004 13-section structure.
- ADR-0002 status-checks follow-up marked as implemented.
- Architecture layer gaps from the prior architecture work completed.
- Renamed `SECURITY.MD` to `SECURITY.md` to correct file-name casing.
- Pinned `actions/checkout` to v6 (from v4) in CI.

### Fixed

- Removed dead plaintext-to-`SecureString` conversion from `New-LabUser`.
- Lab 3.3: Added 90-second DNS propagation wait after ACR bootstrap to prevent ACA image-pull failures on freshly created registries.
- Lab 3.2: Removed availability zone pinning from VM and managed disk deployments to prevent `ZonalAllocationFailed` capacity errors in Sweden Central.
- Lab 4.2: Disabled blob public access on the development storage account to comply with subscription-level `PublicAccessNotPermitted` enforcement.
- Lab 4.3: Corrected file share quota property path from `ShareProperties.ShareQuota` (null) to `QuotaGiB` on `PSShare` objects returned by `Get-AzRmStorageShare`.
- Lab 5.2: Increased RBAC propagation wait from 30 seconds to 360 seconds to satisfy Azure Backup's 5–10 minute role-assignment requirement.
- Cleanup 1.3 / Lab 2.3: Added 45-second ARM lock removal propagation wait to prevent downstream cleanup steps from racing the lock-removal window.

## [0.6.0] - 2026-05-26

### Added

- Module 1 README Architecture Overview section with a Mermaid diagram.

### Changed

- Lab 3.1 Bicep modules refactored to align with the Bicep standards.
- Module 5 README rewritten to the L004 13-section contract.
- Comment-Based Help brought to 100% coverage across all PowerShell scripts.
- Unified README file-name casing to lowercase across the repository.
- Cleaned up `.gitignore` typos and added the session scratch directory to ignores.

### Fixed

- Lab 1.1 hard-coded lab password removed and covered with Pester tests.
- Labs 3.3 and 3.4 downgraded from bleeding-edge Bicep API versions to stable releases.

## [0.5.0] - 2026-04-06

### Added

- Module 5 (Monitoring & Maintenance): completed infrastructure-as-code, automation, and lab documentation across all labs.

## [0.4.0] - 2026-02-22

### Added

- Initial SkyCraft AZ-104 learning platform spanning the first four modules.
- Module 1 (Identities & Governance): identity framework, governance lab 1.3, automation, and documentation.
- Module 2 (Networking): virtual network, secure access, and routing labs with Bicep modules, PowerShell scripts, and lab guides.
- Module 3 (Compute): Lab 3.1 infrastructure plus virtual machines (3.2), additional compute labs (3.3), and App Service with VNet integration (3.4).
- Module 4 (Storage): Lab 4.1 storage accounts with conditional encryption and Lab 4.2 Blob Storage.
- Project foundations: specification, naming/standards documents, security files, README, and course navigation.

[Unreleased]: https://github.com/mbiszczanik/skycraft/compare/v0.7.1...HEAD
[0.7.1]: https://github.com/mbiszczanik/skycraft/compare/v0.7.0...v0.7.1
[0.7.0]: https://github.com/mbiszczanik/skycraft/compare/v0.6.0...v0.7.0
[0.6.0]: https://github.com/mbiszczanik/skycraft/compare/v0.5.0...v0.6.0
[0.5.0]: https://github.com/mbiszczanik/skycraft/compare/v0.4.0...v0.5.0
[0.4.0]: https://github.com/mbiszczanik/skycraft/releases/tag/v0.4.0
