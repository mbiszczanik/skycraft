# SkyCraft Deployment Verification

> **Runbook** for verifying `Deploy-Bicep.ps1` changes against a live subscription

Automated checks cover a lot: `az bicep build` proves the templates compile, `az bicep build-params` proves the parameter files compile, Pester enforces the repository standards, and PSScriptAnalyzer enforces the scripting rules. None of them prove that a deploy script actually deploys the right thing.

This runbook covers the gap. Work through it whenever you change:

- the `.bicepparam` hydration block in any `Deploy-Bicep.ps1`
- which parameters a deploy script overlays at runtime
- a template's parameter defaults, `@allowed` values or tag blocks
- the parameter files themselves

The hydration block is shared, in near-identical form, by twelve `Deploy-Bicep.ps1` scripts. A change to one is usually a change to all twelve, and the failure modes below are the ones that offline validation cannot see.

---

## 1. Prerequisites

```powershell
az bicep install        # or: az bicep upgrade
winget install -e --id Microsoft.Bicep    # the standalone CLI - see the warning below
az login
az account set --subscription "<your SkyCraft subscription>"
Connect-AzAccount       # the deploy scripts use Az PowerShell, not the az CLI
```

> [!WARNING]
> **`az bicep install` alone is not enough.** Az PowerShell compiles a `.bicep` template client-side by shelling out to a bare `bicep` on `PATH`, and `az bicep install` deliberately places its binary inside the Azure CLI's private directory instead. Every deploy script passes a `.bicep` template, so without the standalone CLI on `PATH` **no lab deploys** — `New-AzSubscriptionDeployment` fails with `Cannot find Bicep` while binding its dynamic parameters, before it reaches Azure.
>
> Verified by removing the standalone CLI from `PATH`: a `.bicep` template fails, a pre-compiled `.json` template deploys, and `az bicep build` keeps working because it uses the CLI's private binary.

> [!IMPORTANT]
> Inside a script the rule is the opposite: deploy scripts must call `az bicep build-params`, never a bare `bicep`, so that compiling a parameter file works with either installation. See [powershell-standards.md — Best Practices](powershell-standards.md#5-best-practices).

Confirm the Az context points where you think it does — this is the single most common cause of a confusing run:

```powershell
(Get-AzContext).Subscription.Name
```

---

## 2. Backward compatibility: the no-argument run

**What it proves**: a script invoked with no arguments still deploys exactly what it deployed before parameter files existed.

```powershell
cd module-3-compute\3.1-infrastructure-as-code\scripts
.\Deploy-Bicep.ps1 -WhatIf
```

Check that:

- [ ] The `Parameters:` line names the expected `.bicepparam` file
- [ ] `what-if` reports **no changes** against an already-deployed environment. Any unexplained modification is a regression — most often a tag that changed value, or a parameter that silently fell back to a template default
- [ ] The configuration summary reflects the values actually being sent, not a hardcoded string

> [!IMPORTANT]
> **`-WhatIf` does not mean the same thing in every lab, and most labs do not have it.** Only these produce a real ARM What-If with a resource-level diff, so only these can satisfy the "no changes" check above:
>
> | Lab | `-WhatIf` behaviour |
> | :-- | :------------------ |
> | `3.1`, `5.1`, `5.2`, `5.3` | real ARM What-If |
> | `4.1` | `SupportsShouldProcess` — **skips** the deployment and prints a generic message; no ARM call, so no diff |
> | `3.2` | prints a message and exits 0 — performs no what-if at all |
> | the remaining ten | no `-WhatIf` parameter; passing it is a parameter-binding error |
>
> Unifying this is tracked separately. Until then, choose a lab from the first row when a step below calls for a what-if. Note also that `5.3` mutates Azure *before* its `-WhatIf` guard, so a dry run there is not dry.

> [!NOTE]
> A `what-if` that reports changes on every run usually means a non-deterministic value reached a resource property or tag. This is why `utcNow()` and the `DeploymentDate` tag are banned — see [bicep-standards.md §5](bicep-standards.md#5-resource-tagging-required).

---

## 3. The non-default environment

**What it proves**: values that live *only* in the parameter file survive the overlay.

This is the failure mode that offline validation cannot catch. Each script overlays the values it computes, then relies on the parameter file for everything else. If hydration fails, the overlay still succeeds and the deployment proceeds — with template defaults.

Template defaults vary by lab — some default to `dev`, several to `prod` or a platform value, and a couple require the parameter outright. Whichever it is, a failed hydration falls back to *that* default rather than to what you asked for, so the run silently targets the wrong environment:

```powershell
cd module-3-compute\3.1-infrastructure-as-code\scripts
.\Deploy-Bicep.ps1 -Environment prod -WhatIf
```

- [ ] Every resource in the diff carries the `prod-` prefix — a single `dev-*` name means the parameter file was not read

Repeat for any lab whose parameter file supplies a value the script does not overlay, choosing one that supports a real what-if per the table in §2.

> [!NOTE]
> This section previously prescribed `3.4-app-service` and `3.3-containers`. Neither declares `-WhatIf`, so both commands failed at parameter binding — which is why the defect this section exists to catch shipped in lab 3.3 unnoticed: the check that would have found it could not be run. The lesson generalises past this document. A verification step nobody can execute is worse than none, because the checklist still gets ticked.

---

## 4. Failure paths must fail loudly

**What it proves**: a broken parameter file stops the deployment instead of quietly changing it.

```powershell
.\Deploy-Bicep.ps1 -TemplateParameterFile .\does-not-exist.bicepparam
```

- [ ] Reports `[ERROR] Failed to compile parameter file: ...` and exits non-zero
- [ ] Does **not** reach the deployment call

> [!WARNING]
> `$ErrorActionPreference = 'Stop'` does not catch native-command failures — `$PSNativeCommandUseErrorActionPreference` is `$false` by default. A hydration block that does not check `$LASTEXITCODE` will carry on with an empty parameter set.

---

## 5. Tags on real resources

**What it proves**: both deployment paths agree, and the canonical tag set survives contact with Azure.

```powershell
az resource list --resource-group prod-skycraft-swc-rg `
  --query "[].{Name:name,Env:tags.Environment,Cost:tags.CostCenter,Owner:tags.Owner}" -o table
```

- [ ] `Environment` is the long form — `Development` / `Production` / `Platform`, never `dev` / `prod` / `platform`
- [ ] `CostCenter` and `Owner` are populated on every resource
- [ ] No `ManagedBy` or `DeploymentDate` tag appears

`tests/Tag-Policy.Tests.ps1` enforces these rules against the source. This step confirms the deployed result matches.

---

## 6. Lab validators

```powershell
.\Test-Lab.ps1
$LASTEXITCODE      # 0 = every check passed; anything else is the failure count
```

- [ ] Passes against the resources you just deployed

A `Test-Lab.ps1` failure after a successful deployment usually means the validator and the template disagree about what the lab produces. Fix whichever is wrong — but fix the disagreement, do not relax the assertion to make it pass.

> [!WARNING]
> **Do not read that exit code through `pwsh -File`.** Every validator declares `#Requires -Modules`, which makes `pwsh -NoProfile -File Test-Lab.ps1` exit `0` no matter how many checks failed. Run it in-process as above, or use the `-Command` form that re-exits:
>
> ```powershell
> pwsh -NoProfile -Command "& .\Test-Lab.ps1; exit `$LASTEXITCODE"   # correct
> pwsh -NoProfile -Command "& .\Test-Lab.ps1"                        # 1 on ANY failure - the count is lost
> pwsh -NoProfile -File .\Test-Lab.ps1                               # ALWAYS 0, whatever happened
> ```
>
> The bare `-Command` form is the worst of the three: it looks correct until a validator fails with a count, and then reports 1. See [powershell-standards.md §8](powershell-standards.md#8-script-boilerplate).
>
> This matters most to anything automating a lab cycle: the wrong invocation reports every lab as passing, which is the exact defect these validators were fixed to stop doing.

---

## 7. Record the outcome

Note in the pull request which labs were verified live, against which subscription, and anything that failed on the way. "Verified offline only" is a legitimate result and far more useful than silence — it tells the reviewer exactly which risk is still open.

---

## Related

- [PowerShell Standards](powershell-standards.md) — the `.bicepparam` + runtime override pattern
- [Bicep Standards](bicep-standards.md) — parameter file conventions (§4.3) and tagging (§5)
- [Troubleshooting](../TROUBLESHOOTING.md) — common Azure deployment errors
