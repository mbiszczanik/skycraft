# SkyCraft Lab Parity Reference

> **Reference** for the known gaps between the three paths of a lab.

Every lab is meant to be doable three ways: in the Portal by following the guide, with Az PowerShell (or Azure CLI), and with the lab's Bicep (`Deploy-Bicep.ps1`). All three should leave the same end state, which the lab's `Test-Lab.ps1` accepts whichever way it was built. Issue #362 states that rule and tracks the work; this file keeps the known gaps in one place so they do not live only in issue comments.

The file is a reference, not a plan. It records what is known on the date below. It does not say what to fix next; the tracker does.

---

## 1. The rule

For each lab:

1. Every resource and setting the Bicep creates has a guide step that creates it in the Portal and a PowerShell or CLI equivalent.
2. Every guide step that changes Azure has a Bicep counterpart, unless the step is marked Portal-only (a demo, a test of a deny).
3. Every `Test-Lab.ps1` check tests something a guide step creates and accepts the value each path leaves, including a property the Portal leaves unset where the Bicep writes `false`.
4. Every checklist item maps to a guide step.

Decision of 2026-10-16 (#362): the scripted path lives in the guide as an Az PowerShell block next to each step that changes Azure. The guide blocks are run, not only read; that live replay is still owed (section 5).

---

## 2. Step counts

Computed on 2026-11-16 from the guides on `main` at commit `d540a35`.

A step is a `### Step X.Y.N` heading. "With PowerShell" counts the steps whose section holds a `powershell` block (read-back commands count too). "CLI only" counts the steps whose section holds an `azurecli` or `bash` block and no PowerShell block. The table is a rough measure of how far the guide carries the scripted path, not a proof of parity.

Regenerate the rows with this command from the repository root, and paste the output over the table body:

```powershell
pwsh -NoProfile -File ./tools/Get-LabParityCounts.ps1 -AsMarkdown
```

`tests/Lab-Parity-Doc.Tests.ps1` fails when a row differs from the guides, so a guide change that adds or removes a step needs a refresh of this table and of the date and commit above.

| Lab | Steps | With PowerShell | CLI only |
| --- | --- | --- | --- |
| 1.1 | 14 | 0 | 0 |
| 1.2 | 13 | 0 | 0 |
| 1.3 | 22 | 2 | 0 |
| 2.1 | 15 | 7 | 0 |
| 2.2 | 21 | 12 | 0 |
| 2.3 | 21 | 16 | 1 |
| 3.1 | 24 | 9 | 1 |
| 3.2 | 33 | 14 | 2 |
| 3.3 | 9 | 4 | 1 |
| 3.4 | 13 | 3 | 0 |
| 4.1 | 15 | 3 | 1 |
| 4.2 | 13 | 12 | 0 |
| 4.3 | 8 | 8 | 0 |
| 4.4 | 8 | 8 | 0 |
| 5.1 | 8 | 5 | 0 |
| 5.2 | 9 | 8 | 0 |
| 5.3 | 6 | 2 | 0 |

Labs 1.1 and 1.2 carry the scripted path in separate scripts (`New-LabUser.ps1` and the lab's other scripts), not in the guide.

---

## 3. Known gaps per lab

State is as read from the tracker on 2026-11-16. "Closed" means the issue is closed; the PRs listed are the merged pull requests that reference the issue, not a claim that each one alone closed it. A row marked "not rechecked" comes from a live run of 2026-10-16 and has not been reproduced since.

### Lab 1.1

| Gap | Tracked in | State |
| --- | --- | --- |
| Guide Step 1.1.10 sets Job title, Company name, Department and Office location; the script sets only Job title and Department. The Portal and script paths leave a different profile. | #362 (comment) | Open. The script on `main` still sets no Company name or Office location. Blocks nobody yet: course session 1 sets the four values in the Portal. |

### Lab 1.2

| Gap | Tracked in | State |
| --- | --- | --- |
| No gap recorded. | #362 | n/a |

### Lab 1.3

| Gap | Tracked in | State |
| --- | --- | --- |
| A brand-new subscription fails Step 1.3.7 and leaves Step 1.3.10 unremediated. | #402 | Open. |

### Lab 2.1

| Gap | Tracked in | State |
| --- | --- | --- |
| PowerShell path created public IPs without zones and tags without `Owner`; the validator skipped the subnet delegation. | #274 | Closed 2026-11-04. PRs #420, #422, #507. |
| What-if against the Portal-built estate shows four computed peering response-field differences. | #362 (comment) | Disclosed, no fix planned. Run of 2026-10-24, guide PR #424. |

### Lab 2.2

| Gap | Tracked in | State |
| --- | --- | --- |
| `Test-Lab.ps1` expected prod ASGs and a hub NSG the guide never creates. | #345 | Closed 2026-10-23. PRs #420, #422. |
| What-if shows subnet singular/array CIDR representations and `flushConnection` additions; no creates or deletes. | #362 (comment) | Disclosed, no fix planned. Run of 2026-10-24, guide PR #426. |
| Test-Lab passes a resource left in a Failed state. | #371 | Open. |

### Lab 2.3

| Gap | Tracked in | State |
| --- | --- | --- |
| Outbound SNAT default differs between the Portal and the Bicep. | #344 | Closed. PR #421; guide PR #427. |
| Portal `numberOfProbes` 1 versus scripted 2 (a legacy field the platform documents as not respected). | #362 (comment) | Disclosed, retained. Guide PR #427. |
| The private-link Portal form has no Tags control, so saved links carry only the Project tag; the scripted paths add three more. | #362 (comment) | Disclosed in the guide. PR #427. |
| Test-Lab passes a resource left in a Failed state. | #371 | Open. |

### Lab 3.1

| Gap | Tracked in | State |
| --- | --- | --- |
| No gap recorded. | #362 | n/a |

### Lab 3.2

| Gap | Tracked in | State |
| --- | --- | --- |
| `Test-Lab.ps1` looked resources up by names only the Bicep creates. | #355 | Closed 2026-11-03. PRs #378, #421, #430, #457, #458; lint PR #569. |
| Objectives or checklist items without steps. | #357 | Closed 2026-11-05. PRs #430, #455, #457, #481; lint PR #570. |
| Resource left in a Failed state passes the validator. | #371 | Open. |

### Lab 3.3

| Gap | Tracked in | State |
| --- | --- | --- |
| Guide, checklist and Bicep disagreed on duration, container size, DNS label and regions. | #228 | Closed 2026-10-27. PR #385. |

### Lab 3.4

| Gap | Tracked in | State |
| --- | --- | --- |
| `Test-Lab.ps1` looked resources up by names only the Bicep creates. | #355 | Closed 2026-11-03. See Lab 3.2 for the PRs. |

### Lab 4.1

| Gap | Tracked in | State |
| --- | --- | --- |
| Objectives or checklist items without steps. | #357 | Closed 2026-11-05. See Lab 3.2 for the PRs. |

### Lab 4.2

| Gap | Tracked in | State |
| --- | --- | --- |
| `IsVersioningEnabled -eq $false` failed on a Portal-built account, where the property is `$null`. | #355 (comment) | Closed 2026-11-03 with #355. |
| After Lab 5.2 the what-if of Lab 4.2 exited 0 while its real deployment failed (`InvalidValuesForRequestParameters`), because Lab 5.2 locks blob retention. | #364 | Open. The what-if is not evidence that a deployment succeeds. |

### Lab 4.3

| Gap | Tracked in | State |
| --- | --- | --- |
| The Portal new-share wizard turns Azure Backup on by default and the Bicep does not, so the Portal path left a protected share and a cost. | #360 | Closed 2026-10-26. PR #394. |

### Lab 4.4

| Gap | Tracked in | State |
| --- | --- | --- |
| Container `scripts` (Step 4.4.3) created by no path; checklist required key rotation and a data role that had no steps. | #357, #361 | Closed 2026-11-05 and 2026-11-03. PR #395. |
| The Bicep creates `containers/dev-assets` on the prod account; no guide step does. | #355 | Closed 2026-11-03 with #355. Not rechecked live since 2026-10-16. |
| `Deploy-Bicep.ps1` prints the machine's public IP; learners must not paste its output into a public issue. | #362 (comment) | Not rechecked. |

### Lab 5.1

| Gap | Tracked in | State |
| --- | --- | --- |
| Data collection rule streams differ (`Microsoft-Perf` in the Portal, `Microsoft-InsightsMetrics` in the Bicep); no path installed the Azure Monitor Agent. | #369 | Closed 2026-11-03. PRs #449, #457. |
| Action group receiver name suffix and common alert schema default differ; location `swedencentral` versus `global` (not reported by what-if). | #362 (comment) | Not rechecked since 2026-10-16. No issue of its own. |
| `Test-Lab.ps1` looked resources up by names only the Bicep creates. | #355 | Closed 2026-11-03. See Lab 3.2 for the PRs. |
| Objectives or checklist items without steps. | #357 | Closed 2026-11-05. See Lab 3.2 for the PRs. |
| `tags.Owner` absent in the Portal path, set by the Bicep (also in 5.2 and 5.3). | #362 (comment) | Not rechecked since 2026-10-16. |
| Test-Lab passes a resource left in a Failed state. | #371 | Open. |

### Lab 5.2

| Gap | Tracked in | State |
| --- | --- | --- |
| Backup vault soft delete On (14 days) in the Portal and Off in the Bicep; `alertsForAllJobFailures` unset versus Enabled; `Test-Lab.ps1` failed the Portal path. | #355 | Closed 2026-11-03. PR #458. The end-state difference was not rechecked. |
| Step 5.2.9 (alert processing rule) and Steps 5.2.6 and 5.2.7 (Site Recovery) have no Bicep. | #362 (comment) | Not rechecked since 2026-10-16. |
| `Deploy-Bicep.ps1 -WhatIf` changed Azure before the what-if. | #370 | Closed 2026-11-05. PRs #447, #507. |
| Test-Lab passes a resource left in a Failed state. | #371 | Open. |

### Lab 5.3

| Gap | Tracked in | State |
| --- | --- | --- |
| A flow log in `provisioningState` Failed passed `Test-Lab.ps1` and was invisible to what-if. | #371 | Open. |
| Connection Monitor destination endpoint address unset in the Portal, pinned private IP in the Bicep. | #362 (comment) | Harmless. Not rechecked. |
| `Deploy-Bicep.ps1 -WhatIf` changed Azure before the what-if. | #370 | Closed 2026-11-05. PRs #447, #507. |

---

## 4. What the live check cannot see

The what-if of `Deploy-Bicep.ps1 -WhatIf` against a Portal-built state is the live parity check of #362. It has known blind spots:

- A location change is not reported (Lab 5.1 action group, 2026-10-16).
- A resource in `provisioningState` Failed is not reported (Lab 5.3 flow log, #371).
- A what-if that exits 0 does not show that the deployment succeeds (#364).
- A change that comes from a failed read inside the script (a role lookup without a Microsoft Graph token) is not a parity difference; repeat the read another way first (#397, #406).

---

## 5. Not covered here

The following work stays in its own issues and is not recorded as done by this file:

- The live replay of each guide's PowerShell blocks in step order on a cleared lab (#362).
- The offline parity map, one row per guide step with the Bicep property, the `Test-Lab.ps1` check and the checklist item, and its lint (#363).
- A fresh live parity run of every lab; the rows marked "not rechecked" come from the 2026-10-16 runs.

---

## References

- [Lab guide standards](lab-guide-standards.md)
- [Lab acceptance evidence](lab-acceptance.md)
- [Checklist standards](checklist-standards.md)
