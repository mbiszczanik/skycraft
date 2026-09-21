# SkyCraft Offline Dry-Run Harness

> **Source of Truth** for local pre-push verification.

[`tools/Invoke-DryRun.ps1`](../tools/Invoke-DryRun.ps1) is the single local gate to run before pushing. It mirrors every check in the [Lint workflow](../.github/workflows/lint.yml) that works **without `az login`** and **without any deployed Azure resources**, so a broken push is caught on the dev box instead of in CI.

The harness never authenticates to Azure and never deploys anything. It reads files, shells out to `az bicep`, which is a purely local compiler, and runs the Pester suites, which need no Azure sign-in either.

---

## 1. Quick Start

```powershell
# From the repository root
.\tools\Invoke-DryRun.ps1
```

Exit code `0` means every selected check passed. Exit code `1` means at least one check reported problems; every problem is listed under a `=== Failures ===` heading before the summary.

A full run takes roughly **10-12 minutes** on a typical dev box, dominated by PSScriptAnalyzer (~3 min) and the two Bicep compile passes (~3 min each, because every AVM module is restored from the public registry on a cold cache). The Pester suites add about 1.5 minutes.

---

## 2. What the Harness Checks

| Check | Mirrors CI job | Fails the gate when |
| --- | --- | --- |
| `Parse` | *Verify every PowerShell file parses* | Any `*.ps1` / `*.psm1` / `*.psd1` has a syntax error. Runs first, because PSScriptAnalyzer reports **no** errors for a file it cannot parse. |
| `Analyzer` | *Run PSScriptAnalyzer* | `Invoke-ScriptAnalyzer` with [`PSScriptAnalyzerSettings.psd1`](../PSScriptAnalyzerSettings.psd1) returns a finding of severity `Error`. Warnings are printed and counted but do not fail the gate, exactly as in CI. |
| `Bicep` | *Build all Bicep entry points* | `az bicep build` fails for any `*.bicep` outside a `modules` folder. Templates under `modules` are compiled transitively by their caller. |
| `BicepParams` | *Build all Bicep parameter files* | `az bicep build-params` fails for any `*.bicepparam`. |
| `Pester` | *Repository Standards (Pester)* | `Invoke-Pester` over `tests/` and every `module-*/**/tests/*.Tests.ps1` reports a failed test, block or container. An empty discovery also fails: a gate that found nothing to run is broken, not green. |

Every selected check runs to completion even when an earlier one fails, so a single run reports every problem instead of only the first.

### 2.1 Prerequisites

| Tool | Needed by | Install |
| --- | --- | --- |
| PowerShell 7.0+ | all checks | <https://aka.ms/powershell> |
| PSScriptAnalyzer | `Analyzer` | `Install-Module PSScriptAnalyzer -Scope CurrentUser` |
| Azure CLI + Bicep | `Bicep`, `BicepParams` | <https://aka.ms/installazurecli>, then `az bicep install` |
| Pester 5.5+ | `Pester` | `Install-Module Pester -MinimumVersion 5.5 -MaximumVersion 5.99 -Scope CurrentUser` |

If PSScriptAnalyzer, the Azure CLI or Pester is missing, the affected check **fails** with an install hint rather than passing quietly. A gate that reports green for work it never did is worse than no gate at all. To run a genuine subset, select it explicitly with `-Check` — anything not selected is reported as `SKIP` in the summary and called out again underneath it.

### 2.2 Running a Subset

```powershell
# PowerShell checks only - no Azure CLI on this machine
.\tools\Invoke-DryRun.ps1 -Check Parse,Analyzer,Pester

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
Pester       PASS        24         0      89.6s  1862 passed, 0 failed
```

---

## 3. What the Harness Does **Not** Check

### 3.1 CI jobs that need extra tooling

These need no Azure authentication but need tooling outside PowerShell, so they stay in CI. Run them locally when you have it:

```powershell
# Markdown lint (Node.js)
npx markdownlint-cli2 --config .markdownlint.jsonc "**/*.md" "!node_modules"

# Secret scan
gitleaks detect --source . --redact
```

### 3.2 Live Azure verification

`az deployment ... what-if`, `Test-Lab.ps1` and `Remove-LabResource.ps1` all need `az login` plus, in most cases, resources that a previous lab created. They are deliberately **not** executed by the harness — a pre-push gate must not depend on the state of a subscription. Section 4 lists the commands to run by hand.

What CI *does* enforce is that a PR touching lab content **says** whether they were run: the `Live Verification Declared` check ([`.github/workflows/pr-gate.yml`](../.github/workflows/pr-gate.yml), [ADR-0006](adr/0006-pr-live-verification-gate.md)) requires a `Live-verified: <what was run>` or `Live-verification: deferred -> #<issue>` line in the PR body. Run the same check locally on an open PR with `.\tools\Test-PrLiveVerification.ps1 -Body (gh pr view <n> --json body -q .body) -ChangedFile (gh pr diff <n> --name-only)`.

One qualification. The `Pester` check runs the lab-local suites in-process on your box, and a suite that exercises a lab script in a child `pwsh` (Lab 5.2's `Remove-LabResource.Tests.ps1`) does so with your installed Az and your current `Get-AzContext` in reach. Those suites must go through `tests/Support/LabScriptStub.psm1`, which refuses to run the script unless every Az command it calls resolves to the stub — see [PowerShell standards §6](powershell-standards.md#suites-that-run-a-lab-script-in-a-child-process) and issue #112. A refusal shows up as a failed test with exit code 99 in its message, never as a live teardown.

---

## 4. Live Verification Commands, Per Lab

Run these only when you actually want to check a lab against Azure. They all require `az login` (and `Connect-AzAccount` for the `Az` PowerShell paths) against the SkyCraft subscription.

Two things to know before copying anything below:

- **`az deployment sub what-if` is read-only.** It previews the change set and deploys nothing.
- **Labs are cumulative.** A what-if for a later lab reports the resources an earlier lab was supposed to create as missing if that lab was never deployed. Work through a module in order.

Every lab's `Deploy-Bicep.ps1` now takes a `-WhatIf` switch (issue #74) that runs
`Get-AzSubscriptionDeploymentWhatIfResult` with the same arguments the real deployment would use,
prints the ARM change set and exits 0 without deploying. **Prefer it over a raw `az` command**: it
previews exactly what the script would send, including the values the script resolves at run time,
which a raw command against the checked-in parameter file cannot always reproduce:

- **Module 5 (5.1, 5.2, 5.3)**: the `.bicepparam` files carry well-formed **placeholder** resource IDs under the zero subscription GUID, purely so `az bicep build-params` can validate them offline against `@minLength(1)`. The deploy scripts resolve the real IDs from Azure at run time, so a raw what-if for these labs previews against the placeholders and is not meaningful.
- **Lab 3.2**: `parSshPublicKey` is read from the `SKYCRAFT_SSH_PUBLIC_KEY` environment variable and defaults to empty. `Deploy-Bicep.ps1` supplies the key directly.
- **Lab 4.4**: `parClientIp` is auto-detected by the script; a raw what-if previews an empty firewall rule instead.

The raw `az deployment sub what-if` form is still listed where the script does not cover a template:
Lab 3.3's resource-group-scope `acr.bicep` bootstrap.

All commands are written to be run from the repository root.

### 4.1 Module 1 — Identities and Governance

```powershell
# Lab 1.1 - Entra users and groups (no Bicep; Microsoft Graph only)
.\module-1-identities-governance\1.1-entra-users-groups\scripts\Test-Lab.ps1
.\module-1-identities-governance\1.1-entra-users-groups\scripts\Remove-LabResource.ps1 -WhatIf

# Lab 1.2 - RBAC
.\module-1-identities-governance\1.2-rbac\scripts\Deploy-Bicep.ps1 -WhatIf
# role-assignments.bicep has no parameter file: its four principal IDs are Entra object IDs
# that only exist once Lab 1.1 has run. -IncludeRoleAssignments resolves them from the
# directory and previews that template too (the three resource groups must already exist).
.\module-1-identities-governance\1.2-rbac\scripts\Deploy-Bicep.ps1 -IncludeRoleAssignments -WhatIf
.\module-1-identities-governance\1.2-rbac\scripts\Test-Lab.ps1
.\module-1-identities-governance\1.2-rbac\scripts\Remove-LabResource.ps1 -WhatIf

# Lab 1.3 - Governance
.\module-1-identities-governance\1.3-governance\scripts\Deploy-Bicep.ps1 -WhatIf
.\module-1-identities-governance\1.3-governance\scripts\Test-Lab.ps1
.\module-1-identities-governance\1.3-governance\scripts\Remove-LabResource.ps1 -WhatIf
```

### 4.2 Module 2 — Networking

```powershell
# Lab 2.1 - Virtual networks
.\module-2-networking\2.1-virtual-networks\scripts\Deploy-Bicep.ps1 -WhatIf
.\module-2-networking\2.1-virtual-networks\scripts\Test-Lab.ps1
.\module-2-networking\2.1-virtual-networks\scripts\Remove-LabResource.ps1 -WhatIf

# Lab 2.2 - Secure access (-WhatIf skips the Bastion prompt and previews with Bastion off)
.\module-2-networking\2.2-secure-access\scripts\Deploy-Bicep.ps1 -WhatIf
.\module-2-networking\2.2-secure-access\scripts\Test-Lab.ps1
.\module-2-networking\2.2-secure-access\scripts\Remove-LabResource.ps1 -WhatIf

# Lab 2.3 - Name resolution
.\module-2-networking\2.3-name-resolution\scripts\Deploy-Bicep.ps1 -WhatIf
.\module-2-networking\2.3-name-resolution\scripts\Test-Lab.ps1
.\module-2-networking\2.3-name-resolution\scripts\Remove-LabResource.ps1 -WhatIf
```

### 4.3 Module 3 — Compute

```powershell
# Lab 3.1 - Infrastructure as code (dev and prod parameter sets)
.\module-3-compute\3.1-infrastructure-as-code\scripts\Deploy-Bicep.ps1 -Environment dev -WhatIf
.\module-3-compute\3.1-infrastructure-as-code\scripts\Deploy-Bicep.ps1 -Environment prod -WhatIf
.\module-3-compute\3.1-infrastructure-as-code\scripts\Test-Lab.ps1
.\module-3-compute\3.1-infrastructure-as-code\scripts\Remove-LabResource.ps1 -WhatIf

# Lab 3.2 - Virtual machines
.\module-3-compute\3.2-virtual-machines\scripts\Deploy-Bicep.ps1 -WhatIf
.\module-3-compute\3.2-virtual-machines\scripts\Test-Lab.ps1
.\module-3-compute\3.2-virtual-machines\scripts\Remove-LabResource.ps1 -WhatIf

# Lab 3.3 - Containers (-WhatIf previews main.bicep only; the ACR bootstrap is skipped, not simulated)
.\module-3-compute\3.3-containers\scripts\Deploy-Bicep.ps1 -WhatIf
# acr.bicep is the resource-group-scope bootstrap that Deploy-Bicep.ps1 runs first:
az deployment group what-if --resource-group dev-skycraft-swc-rg `
    --template-file module-3-compute/3.3-containers/bicep/acr.bicep
.\module-3-compute\3.3-containers\scripts\Test-Lab.ps1
.\module-3-compute\3.3-containers\scripts\Remove-LabResource.ps1 -WhatIf

# Lab 3.4 - App Service
.\module-3-compute\3.4-app-service\scripts\Deploy-Bicep.ps1 -WhatIf
.\module-3-compute\3.4-app-service\scripts\Test-Lab.ps1
.\module-3-compute\3.4-app-service\scripts\Remove-LabResource.ps1 -WhatIf
```

### 4.4 Module 4 — Storage

Module 4 labs are cumulative forward and must be previewed in order — every lab restates the account-level baseline, so a what-if for Lab 4.3 against a subscription that never ran Lab 4.1 is meaningless.

```powershell
# Lab 4.1 - Storage accounts
.\module-4-storage\4.1-storage-accounts\scripts\Deploy-Bicep.ps1 -All -WhatIf
.\module-4-storage\4.1-storage-accounts\scripts\Test-Lab.ps1
.\module-4-storage\4.1-storage-accounts\scripts\Remove-LabResource.ps1 -WhatIf

# Lab 4.2 - Blob storage
.\module-4-storage\4.2-blob-storage\scripts\Deploy-Bicep.ps1 -WhatIf
.\module-4-storage\4.2-blob-storage\scripts\Test-Lab.ps1
.\module-4-storage\4.2-blob-storage\scripts\Remove-LabResource.ps1 -WhatIf

# Lab 4.3 - Azure Files
.\module-4-storage\4.3-azure-files\scripts\Deploy-Bicep.ps1 -Environment prod -WhatIf
.\module-4-storage\4.3-azure-files\scripts\Test-Lab.ps1
.\module-4-storage\4.3-azure-files\scripts\Remove-LabResource.ps1 -WhatIf

# Lab 4.4 - Storage security
.\module-4-storage\4.4-storage-security\scripts\Deploy-Bicep.ps1 -Environment prod -WhatIf
.\module-4-storage\4.4-storage-security\scripts\Test-Lab.ps1
.\module-4-storage\4.4-storage-security\scripts\Remove-LabResource.ps1 -WhatIf
```

### 4.5 Module 5 — Monitoring and Maintenance

Every Module 5 lab resolves resource IDs from Azure at run time, so the deploy script's own `-WhatIf` is the only meaningful preview here - a raw `az` command would preview the placeholder IDs.

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
