# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.8.0] - 2026-07-30

### Added

- Bicep parameter files (`bicep/parameters/*.bicepparam`) for every entry point — per-environment (`dev`/`prod`/`platform`) for environment-aware labs, a single `main.bicepparam` otherwise; kept minimal (only differentiating or required values) to avoid drift.
- Validation decorators (`@allowed`, `@minLength`/`@maxLength`, `@minValue`/`@maxValue`) across all Bicep parameters, consistent with the PowerShell `[ValidateSet]` values.
- Lint workflow now validates every `*.bicepparam` with `az bicep build-params` (parameter files are not covered by `az bicep build`).
- `docs/deployment-verification.md`: runbook for smoke-testing `Deploy-Bicep.ps1` changes against a live subscription, linked from `CONTRIBUTING.md`. CI proves the templates compile; it cannot prove they deploy the right thing, and the failure modes that only appear live (a `prod` run silently targeting `dev` resources, a hydration failure swallowed by `$ErrorActionPreference`) had no documented check.
- `tests/Tag-Policy.Tests.ps1`: enforces the canonical tag set. Fails on a `ManagedBy`/`DeploymentDate` assignment (Bicep or PowerShell), on any `utcNow()` in a template, on a Bicep tag block that sets `Project` without `CostCenter` and `Owner`, and on a PowerShell tag hashtable that omits `Owner`.

### Changed

- Canonical resource tags standardized to exactly `Project` / `Environment` / `CostCenter` / `Owner`, with `Owner` sourced from a new `parOwnerEmail` parameter (deliberate per-resource extras such as `Purpose`/`Criticality` retained).
- `Deploy-Bicep.ps1` made backward-compatible with `-Environment` / `-TemplateParameterFile`, merging the parameter file with runtime-computed overrides; a no-argument run deploys identically to before.
- Audited explicit `dependsOn` across all labs: documented every genuine non-symbolic ordering and removed a transitively-redundant hub-VNet dependency.
- Bicep standards documented the canonical tag set, the `bicep/parameters/{env}.bicepparam` convention, and the "never write an explicit `dependsOn` when a symbolic reference already exists" rule.
- Swept the canonical `Owner` tag into the imperative companion deploy scripts and the storage/BCDR lab tag-enumeration docs so both deployment paths agree, and into the remaining lab materials (checklists for 2.1, 2.2, 2.3, 3.1, 3.2 and `lab-guide-4.1.md`).
- Canonicalized the `Environment` tag *value* in labs 3.3 and 3.4, which tagged resources `dev`/`prod` instead of `Development`/`Production`. The module parameters now declare the canonical form; the orchestrators keep the short value for naming and map it once, as labs 4.3 and 4.4 already did.
- Lab 4.1: the soft-delete settings are no longer re-hardcoded in the deploy overlay, so the parameter files actually govern them; the configuration summary now reports the effective value instead of a fixed string.
- Module 5 labs ship only the environment they support (5.1/5.2 platform, 5.3 prod) and dropped the `-Environment` parameter accordingly — every resource in those labs is name-pinned, so the other parameter files could only mis-tag platform infrastructure.
- Lab 3.2 is now consistently regional: the guide's architecture diagram, portal walkthroughs, verification tables and summaries no longer teach zone pinning, and Section 6 explains the `ZonalAllocationFailed` trade-off that drives the choice.

### Removed

- Banned the `ManagedBy` and `DeploymentDate` tags (and the now-unused `parCurrentDate`/`parService` parameters); the `utcNow()`-fed `DeploymentDate` broke `what-if` idempotency by changing on every run. Also removed them from the lab materials that still taught them (`lab-guide-3.1.md`, `3.1/ARCHITECTURE.md`, `lab-guide-3.2.md`, `lab-checklist-3.2.md`).

### Fixed

- `Deploy-Bicep.ps1` (12 labs): parameter files are compiled with `az bicep build-params` instead of a bare `bicep`. The only Bicep install this project documents is `az bicep install`, which does not put `bicep` on `PATH`, so every one of those scripts failed with `CommandNotFoundException` on a correctly-provisioned machine.
- `Deploy-Bicep.ps1` (12 labs): the hydration step checks `$LASTEXITCODE`. `$ErrorActionPreference = 'Stop'` does not catch native-command failures, so a failed compile previously skipped hydration silently and deployed with only the runtime overrides — e.g. `3.4 -Environment prod` targeting the dev resource group and VNet, or `3.3 -Environment prod` creating `dev-skycraft-swc-aci-auth` in the prod resource group.
- Parameter files that carry empty placeholders for runtime values no longer advertise a direct `az deployment sub create` in their `EXAMPLE:` header; following it submitted the empty placeholders.
- Corrected the `Skycraft` → `SkyCraft` project-tag casing in the Lab 1.2 resource-group script.
- Lab 3.2: pass the SSH public key to `New-AzSubscriptionDeployment` as a plain string. Az cannot serialize a `SecureString` inside a merged `-TemplateParameterObject` (`Unable to serialize secure string value`); the key is public, so no secret is exposed. Surfaced by the live deployment cycle.
- Lab 3.2 `Test-Lab.ps1`: validate that the VMs are regional (no availability zone) instead of asserting fixed zones — the VMs are deliberately deployed without zone pinning to avoid `ZonalAllocationFailed` capacity errors in Sweden Central, and the stale assertion crashed on `Zones[0]`.

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

[Unreleased]: https://github.com/mbiszczanik/skycraft/compare/v0.7.0...HEAD
[0.7.0]: https://github.com/mbiszczanik/skycraft/compare/v0.6.0...v0.7.0
[0.6.0]: https://github.com/mbiszczanik/skycraft/compare/v0.5.0...v0.6.0
[0.5.0]: https://github.com/mbiszczanik/skycraft/compare/v0.4.0...v0.5.0
[0.4.0]: https://github.com/mbiszczanik/skycraft/releases/tag/v0.4.0
