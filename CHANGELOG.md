# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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

[Unreleased]: https://github.com/mbiszczanik/skycraft/compare/v0.6.0...HEAD
[0.6.0]: https://github.com/mbiszczanik/skycraft/compare/v0.5.0...v0.6.0
[0.5.0]: https://github.com/mbiszczanik/skycraft/compare/v0.4.0...v0.5.0
[0.4.0]: https://github.com/mbiszczanik/skycraft/releases/tag/v0.4.0
