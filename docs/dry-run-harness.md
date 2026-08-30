# SkyCraft Offline Dry-Run Harness

> **Source of Truth** for local pre-push verification.

[`tools/Invoke-DryRun.ps1`](../tools/Invoke-DryRun.ps1) is the single local gate to run before pushing. It mirrors every check in the [Lint workflow](../.github/workflows/lint.yml) that works **without `az login`** and **without any deployed Azure resources**, so a broken push is caught on the dev box instead of in CI.

The harness never authenticates to Azure and never deploys anything. It reads files and shells out to `az bicep`, which is a purely local compiler.

---

## 1. Quick Start

```powershell
# From the repository root
.\tools\Invoke-DryRun.ps1
```

Exit code `0` means every selected check passed. Exit code `1` means at least one check reported problems; every problem is listed under a `=== Failures ===` heading before the summary.

A full run takes roughly **8-10 minutes** on a typical dev box, dominated by PSScriptAnalyzer (~3 min) and the two Bicep compile passes (~3 min each, because every AVM module is restored from the public registry on a cold cache).

---

## 2. What the Harness Checks

| Check | Mirrors CI job | Fails the gate when |
| --- | --- | --- |
| `Parse` | *Verify every PowerShell file parses* | Any `*.ps1` / `*.psm1` / `*.psd1` has a syntax error. Runs first, because PSScriptAnalyzer reports **no** errors for a file it cannot parse. |
| `Analyzer` | *Run PSScriptAnalyzer* | `Invoke-ScriptAnalyzer` with [`PSScriptAnalyzerSettings.psd1`](../PSScriptAnalyzerSettings.psd1) returns a finding of severity `Error`. Warnings are printed and counted but do not fail the gate, exactly as in CI. |
| `Bicep` | *Build all Bicep entry points* | `az bicep build` fails for any `*.bicep` outside a `modules` folder. Templates under `modules` are compiled transitively by their caller. |
| `BicepParams` | *Build all Bicep parameter files* | `az bicep build-params` fails for any `*.bicepparam`. |

Every selected check runs to completion even when an earlier one fails, so a single run reports every problem instead of only the first.

### 2.1 Prerequisites

| Tool | Needed by | Install |
| --- | --- | --- |
| PowerShell 7.0+ | all checks | <https://aka.ms/powershell> |
| PSScriptAnalyzer | `Analyzer` | `Install-Module PSScriptAnalyzer -Scope CurrentUser` |
| Azure CLI + Bicep | `Bicep`, `BicepParams` | <https://aka.ms/installazurecli>, then `az bicep install` |

If PSScriptAnalyzer or the Azure CLI is missing, the affected check **fails** with an install hint rather than passing quietly. A gate that reports green for work it never did is worse than no gate at all. To run a genuine subset, select it explicitly with `-Check` — anything not selected is reported as `SKIP` in the summary and called out again underneath it.

### 2.2 Running a Subset

```powershell
# PowerShell checks only - no Azure CLI on this machine
.\tools\Invoke-DryRun.ps1 -Check Parse,Analyzer

# Bicep only, echoing each file as it is compiled
.\tools\Invoke-DryRun.ps1 -Check Bicep,BicepParams -Verbose

# Point at a different checkout (for example a worktree)
.\tools\Invoke-DryRun.ps1 -RepoRoot C:\src\skycraft-worktree
```

> [!NOTE]
> `pwsh -File` cannot pass an array argument — it hands the whole comma-separated value to the parameter as one string and `ValidateSet` rejects it. Run the script directly (as above) or use `pwsh -Command`. The no-argument form works fine with `-File`, which is what a Git hook or a wrapper script should use.

### 2.3 Sample Output

```text
=== Dry-run summary ===
Check        Status   Items  Problems   Duration  Note
Parse        PASS        77         0       3.0s
Analyzer     PASS        77         0     202.4s  14 warning(s)
Bicep        PASS        18         0     174.2s
BicepParams  PASS        17         0     169.6s
```

---

## 3. What the Harness Does **Not** Check

### 3.1 CI jobs that need extra tooling

These need no Azure authentication but are outside the harness's scope. Run them locally when you have the tooling:

```powershell
# Repository standards (Pester 5)
Invoke-Pester -Path .\tests

# Markdown lint (Node.js)
npx markdownlint-cli2 --config .markdownlint.jsonc "**/*.md" "!node_modules"

# Secret scan
gitleaks detect --source . --redact
```

### 3.2 Live Azure verification

`az deployment ... what-if`, `Test-Lab.ps1` and `Remove-LabResource.ps1` all need `az login` plus, in most cases, resources that a previous lab created. They are deliberately **not** executed by the harness — a pre-push gate must not depend on the state of a subscription. Section 4 lists the commands to run by hand.

---

## 4. Live Verification Commands, Per Lab

Run these only when you actually want to check a lab against Azure. They all require `az login` (and `Connect-AzAccount` for the `Az` PowerShell paths) against the SkyCraft subscription.

Two things to know before copying anything below:

- **`az deployment sub what-if` is read-only.** It previews the change set and deploys nothing.
- **Labs are cumulative.** A what-if for a later lab reports the resources an earlier lab was supposed to create as missing if that lab was never deployed. Work through a module in order.

Labs 3.1, 3.2, 5.1, 5.2 and 5.3 have a `-WhatIf` switch on their own `Deploy-Bicep.ps1`. Prefer it over the raw `az` command wherever the checked-in parameter file cannot stand on its own:

- **Module 5 (5.1, 5.2, 5.3)**: the `.bicepparam` files carry well-formed **placeholder** resource IDs under the zero subscription GUID, purely so `az bicep build-params` can validate them offline against `@minLength(1)`. The deploy scripts resolve the real IDs from Azure at run time, so a raw what-if for these labs previews against the placeholders and is not meaningful.
- **Lab 3.2**: `parSshPublicKey` is read from the `SKYCRAFT_SSH_PUBLIC_KEY` environment variable and defaults to empty. `Deploy-Bicep.ps1` supplies the key directly.

Labs 3.1, and every lab in Modules 1, 2 and 4, have self-contained parameter files, so the raw `az deployment sub what-if` form below is accurate for them.

All commands are written to be run from the repository root.

### 4.1 Module 1 — Identities and Governance

```powershell
# Lab 1.1 - Entra users and groups (no Bicep; Microsoft Graph only)
.\module-1-identities-governance\1.1-entra-users-groups\scripts\Test-Lab.ps1
.\module-1-identities-governance\1.1-entra-users-groups\scripts\Remove-LabResource.ps1 -WhatIf

# Lab 1.2 - RBAC
az deployment sub what-if --location swedencentral `
    --parameters module-1-identities-governance/1.2-rbac/bicep/parameters/resource-groups.bicepparam
# role-assignments.bicep has no parameter file: its four principal IDs are Entra object IDs
# that only exist once Lab 1.1 has run, so pass them explicitly.
az deployment sub what-if --location swedencentral `
    --template-file module-1-identities-governance/1.2-rbac/bicep/role-assignments.bicep `
    --parameters parAdminPrincipalId=<object-id> parDeveloperGroupPrincipalId=<object-id> `
                 parTesterGroupPrincipalId=<object-id> parPartnerPrincipalId=<object-id>
.\module-1-identities-governance\1.2-rbac\scripts\Test-Lab.ps1
.\module-1-identities-governance\1.2-rbac\scripts\Remove-LabResource.ps1 -WhatIf

# Lab 1.3 - Governance
az deployment sub what-if --location swedencentral `
    --parameters module-1-identities-governance/1.3-governance/bicep/parameters/main.bicepparam
.\module-1-identities-governance\1.3-governance\scripts\Test-Lab.ps1
.\module-1-identities-governance\1.3-governance\scripts\Remove-LabResource.ps1 -WhatIf
```

### 4.2 Module 2 — Networking

```powershell
# Lab 2.1 - Virtual networks
az deployment sub what-if --location swedencentral `
    --parameters module-2-networking/2.1-virtual-networks/bicep/parameters/main.bicepparam
.\module-2-networking\2.1-virtual-networks\scripts\Test-Lab.ps1
.\module-2-networking\2.1-virtual-networks\scripts\Remove-LabResource.ps1 -WhatIf

# Lab 2.2 - Secure access
az deployment sub what-if --location swedencentral `
    --parameters module-2-networking/2.2-secure-access/bicep/parameters/main.bicepparam
.\module-2-networking\2.2-secure-access\scripts\Test-Lab.ps1
.\module-2-networking\2.2-secure-access\scripts\Remove-LabResource.ps1 -WhatIf

# Lab 2.3 - Name resolution
az deployment sub what-if --location swedencentral `
    --parameters module-2-networking/2.3-name-resolution/bicep/parameters/main.bicepparam
.\module-2-networking\2.3-name-resolution\scripts\Test-Lab.ps1
.\module-2-networking\2.3-name-resolution\scripts\Remove-LabResource.ps1 -WhatIf
```

### 4.3 Module 3 — Compute

```powershell
# Lab 3.1 - Infrastructure as code (dev and prod parameter sets)
az deployment sub what-if --location swedencentral `
    --parameters module-3-compute/3.1-infrastructure-as-code/bicep/parameters/dev.bicepparam
az deployment sub what-if --location swedencentral `
    --parameters module-3-compute/3.1-infrastructure-as-code/bicep/parameters/prod.bicepparam
.\module-3-compute\3.1-infrastructure-as-code\scripts\Test-Lab.ps1
.\module-3-compute\3.1-infrastructure-as-code\scripts\Remove-LabResource.ps1 -WhatIf

# Lab 3.2 - Virtual machines
.\module-3-compute\3.2-virtual-machines\scripts\Deploy-Bicep.ps1 -WhatIf
.\module-3-compute\3.2-virtual-machines\scripts\Test-Lab.ps1
.\module-3-compute\3.2-virtual-machines\scripts\Remove-LabResource.ps1 -WhatIf

# Lab 3.3 - Containers
az deployment sub what-if --location swedencentral `
    --parameters module-3-compute/3.3-containers/bicep/parameters/main.bicepparam
# acr.bicep is the resource-group-scope bootstrap that Deploy-Bicep.ps1 runs first:
az deployment group what-if --resource-group dev-skycraft-swc-rg `
    --template-file module-3-compute/3.3-containers/bicep/acr.bicep
.\module-3-compute\3.3-containers\scripts\Test-Lab.ps1
.\module-3-compute\3.3-containers\scripts\Remove-LabResource.ps1 -WhatIf

# Lab 3.4 - App Service
az deployment sub what-if --location swedencentral `
    --parameters module-3-compute/3.4-app-service/bicep/parameters/main.bicepparam
.\module-3-compute\3.4-app-service\scripts\Test-Lab.ps1
.\module-3-compute\3.4-app-service\scripts\Remove-LabResource.ps1 -WhatIf
```

### 4.4 Module 4 — Storage

Module 4 labs are cumulative forward and must be previewed in order — every lab restates the account-level baseline, so a what-if for Lab 4.3 against a subscription that never ran Lab 4.1 is meaningless.

```powershell
# Lab 4.1 - Storage accounts
az deployment sub what-if --location swedencentral `
    --parameters module-4-storage/4.1-storage-accounts/bicep/parameters/main.bicepparam
.\module-4-storage\4.1-storage-accounts\scripts\Test-Lab.ps1
.\module-4-storage\4.1-storage-accounts\scripts\Remove-LabResource.ps1 -WhatIf

# Lab 4.2 - Blob storage
az deployment sub what-if --location swedencentral `
    --parameters module-4-storage/4.2-blob-storage/bicep/parameters/main.bicepparam
.\module-4-storage\4.2-blob-storage\scripts\Test-Lab.ps1
.\module-4-storage\4.2-blob-storage\scripts\Remove-LabResource.ps1 -WhatIf

# Lab 4.3 - Azure Files
az deployment sub what-if --location swedencentral `
    --parameters module-4-storage/4.3-azure-files/bicep/parameters/main.bicepparam
.\module-4-storage\4.3-azure-files\scripts\Test-Lab.ps1
.\module-4-storage\4.3-azure-files\scripts\Remove-LabResource.ps1 -WhatIf

# Lab 4.4 - Storage security
az deployment sub what-if --location swedencentral `
    --parameters module-4-storage/4.4-storage-security/bicep/parameters/main.bicepparam
.\module-4-storage\4.4-storage-security\scripts\Test-Lab.ps1
.\module-4-storage\4.4-storage-security\scripts\Remove-LabResource.ps1 -WhatIf
```

### 4.5 Module 5 — Monitoring and Maintenance

Every Module 5 lab resolves resource IDs from Azure at run time, so use the deploy script's own `-WhatIf` rather than a raw `az` command.

```powershell
# Lab 5.1 - Azure Monitor (-OpsEmail is mandatory)
.\module-5-monitoring-maintenance\5.1-azure-monitor\scripts\Deploy-Bicep.ps1 -OpsEmail 'ops@example.com' -WhatIf
.\module-5-monitoring-maintenance\5.1-azure-monitor\scripts\Test-Lab.ps1
.\module-5-monitoring-maintenance\5.1-azure-monitor\scripts\Remove-LabResource.ps1 -WhatIf

# Lab 5.2 - Business continuity
.\module-5-monitoring-maintenance\5.2-business-continuity\scripts\Deploy-Bicep.ps1 -WhatIf
.\module-5-monitoring-maintenance\5.2-business-continuity\scripts\Test-Lab.ps1
.\module-5-monitoring-maintenance\5.2-business-continuity\scripts\Remove-LabResource.ps1 -WhatIf

# Lab 5.3 - Network monitoring
.\module-5-monitoring-maintenance\5.3-network-monitoring\scripts\Deploy-Bicep.ps1 -WhatIf
.\module-5-monitoring-maintenance\5.3-network-monitoring\scripts\Test-Lab.ps1
.\module-5-monitoring-maintenance\5.3-network-monitoring\scripts\Remove-LabResource.ps1 -WhatIf
```

---

## 5. Implementation Notes

### 5.1 Why `--outfile` and not `--stdout`

The harness compiles to a throwaway file (`az bicep build --file <f> --outfile <tmp>`) rather than piping to `--stdout`, which is what the Lint workflow does.

On a Windows console that is not UTF-8, `az bicep build --stdout` dies with `UnicodeEncodeError: 'charmap' codec can't encode character` as soon as a template pulls in an AVM module whose metadata contains a non-ANSI character. `PYTHONIOENCODING=utf-8` does not help, because the Azure CLI's bundled Python ignores it. Writing to a file bypasses the console encoding entirely. CI runs on Ubuntu with a UTF-8 locale and is unaffected, which is why the workflow can keep using `--stdout`.

Do not "simplify" the harness back to `--stdout`.

### 5.2 Excluded directories

File discovery skips `.git`, `.worktrees`, `lab-outputs`, `node_modules`, `scratch`, `temp` and `test-results` at any depth, so generated ARM output and session scratch files cannot fail the gate. Override the list with `-ExcludeDirectory` if a checkout needs something different.

### 5.3 Exit-code propagation

The harness ends with `$Host.SetShouldExit(1)` immediately before `exit 1`, per [`docs/powershell-standards.md`](powershell-standards.md) Section 4. Without that guard PowerShell 7 can discard the exit code of a script run as `pwsh -File`, and a failing gate would report success to its caller.

---

## 6. Related Documents

- [PowerShell Standards](powershell-standards.md) — the conventions the `Analyzer` check enforces.
- [Bicep Standards](bicep-standards.md) — the conventions the `Bicep` checks enforce.
- [Contributing](../CONTRIBUTING.md) — branching and PR workflow.
