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
az login
az account set --subscription "<your SkyCraft subscription>"
Connect-AzAccount       # the deploy scripts use Az PowerShell, not the az CLI
```

> [!IMPORTANT]
> Deploy scripts must call `az bicep build-params`, never a bare `bicep`. `az bicep install` places the binary inside the Azure CLI's private directory and **not** on `PATH`, so a bare `bicep` call fails with `CommandNotFoundException` on a machine provisioned from this repository's own prerequisites. See [powershell-standards.md — Best Practices](powershell-standards.md#5-best-practices).

Confirm the Az context points where you think it does — this is the single most common cause of a confusing run:

```powershell
(Get-AzContext).Subscription.Name
```

---

## 2. Backward compatibility: the no-argument run

**What it proves**: a script invoked with no arguments still deploys exactly what it deployed before parameter files existed.

```powershell
cd module-4-storage\4.1-storage-accounts\scripts
.\Deploy-Bicep.ps1 -WhatIf
```

Check that:

- [ ] The `Parameters:` line names the expected `.bicepparam` file
- [ ] `what-if` reports **no changes** against an already-deployed environment. Any unexplained modification is a regression — most often a tag that changed value, or a parameter that silently fell back to a template default
- [ ] The configuration summary reflects the values actually being sent, not a hardcoded string

> [!NOTE]
> A `what-if` that reports changes on every run usually means a non-deterministic value reached a resource property or tag. This is why `utcNow()` and the `DeploymentDate` tag are banned — see [bicep-standards.md §5](bicep-standards.md#5-resource-tagging-required).

---

## 3. The non-default environment

**What it proves**: values that live *only* in the parameter file survive the overlay.

This is the failure mode that offline validation cannot catch. Each script overlays the values it computes, then relies on the parameter file for everything else. If hydration fails, the overlay still succeeds and the deployment proceeds — with template defaults.

Every SkyCraft template defaults to `dev`, so a broken `prod` run silently targets development resources:

```powershell
cd module-3-compute\3.4-app-service\scripts
.\Deploy-Bicep.ps1 -Environment prod -WhatIf
```

- [ ] Targets `prod-skycraft-swc-rg` and `prod-skycraft-swc-vnet` — **not** `dev-*`

```powershell
cd module-3-compute\3.3-containers\scripts
.\Deploy-Bicep.ps1 -Environment prod -WhatIf
```

- [ ] Container resources use the `prod-` prefix — a `dev-skycraft-swc-aci-auth` inside the prod resource group means the parameter file was never read

Repeat for any lab whose parameter file supplies a value the script does not overlay.

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
```

- [ ] Passes against the resources you just deployed

A `Test-Lab.ps1` failure after a successful deployment usually means the validator and the template disagree about what the lab produces. Fix whichever is wrong — but fix the disagreement, do not relax the assertion to make it pass.

---

## 7. Record the outcome

Note in the pull request which labs were verified live, against which subscription, and anything that failed on the way. "Verified offline only" is a legitimate result and far more useful than silence — it tells the reviewer exactly which risk is still open.

---

## Related

- [PowerShell Standards](powershell-standards.md) — the `.bicepparam` + runtime override pattern
- [Bicep Standards](bicep-standards.md) — parameter file conventions (§4.3) and tagging (§5)
- [Troubleshooting](../TROUBLESHOOTING.md) — common Azure deployment errors
