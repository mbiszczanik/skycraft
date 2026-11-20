# Script Path Pass of Module 1

> **Procedure** for an agent pass of the Azure CLI and PowerShell paths of Labs 1.1, 1.2 and 1.3 (issue #335).

The Portal path of Module 1 has its own pass (`lab-portal-pass`). This procedure covers the other two paths: the script blocks in each lab guide and the labs' own scripts (`Deploy-Bicep.ps1`, `Test-Lab.ps1`, `Remove-LabResource.ps1` and the lab-specific scripts under `scripts/`). The pass walks them as a learner would and reports what the guide says against what the shell shows.

The procedure is a document, not a plan. Findings and their state live in the tracker (#300 for the per-lab results, one class issue per defect class).

---

## 1. Rules

1. The sign-in for Lab 1.1 (Microsoft Graph) is the maintainer's. The pass never signs in on its own: no `Connect-MgGraph`, `Connect-AzAccount` or `az login` run by the agent. If the session is not signed in, the pass stops and asks.
2. The pass runs only in the rehearsal subscription and the test tenant, with the maintainer's go-ahead for that session.
3. Cleanup runs only with the maintainer's yes, per lab (section 6).
4. A defect is searched across all labs (same script, same guide pattern) and filed as one class issue, not one issue per occurrence.
5. A step that cannot run (a missing permission, a user that does not exist in the subscription's tenant) is reported as `BLOCKED` with the reason, never skipped silently.

---

## 2. Preconditions

Check each one with its command and record the output in the report. If a check fails, stop.

```powershell
# Each of these issues is closed (expected: CLOSED, four lines).
foreach ($n in 257, 350, 273, 237) { gh issue view $n --repo mbiszczanik/skycraft --json state --jq .state }

# The pass starts from the current main (expected: the head the report names).
git fetch origin
git rev-parse origin/main

# The context is the rehearsal subscription of this pass (the maintainer confirms the name).
Get-AzContext | Select-Object Name, @{ n = 'Subscription'; e = { $_.Subscription.Name } }
```

| Precondition | How to check |
| --- | --- |
| #257, #350, #273 and #237 are closed | the `gh issue view` lines above print `CLOSED` four times |
| The rehearsal subscription is not in use | the maintainer says so in this session; `Get-AzResourceGroup` shows no resource group of another run (`Get-AzResourceGroup \| Select-Object ResourceGroupName`) |
| Lab 1.3's policy and lock state is known | `Get-AzPolicyAssignment \| Select-Object Name, DisplayName` and `Get-AzResourceLock \| Select-Object Name, ResourceGroupName` are recorded before Lab 1.3 starts; a deny or allowed-locations assignment left from an earlier run is reported, not removed |

While Lab 1.3's deny and allowed-locations policies are assigned, the pass has the subscription to itself.

---

## 3. The sheet

Generate the step-to-command table once, from the guides on the head the pass runs on:

```bash
python3 -X utf8 tools/guide-drift/script_paths.py module-1-identities-governance
```

The tool prints one row per script block (guide, line, step or section heading, language, first command) and the count per guide. It exits non-zero when the module has no guide or a guide has no script block, so an empty table is never a success.

The table lists only what the guides themselves hold as script blocks. Most of the scripted path of Module 1 is the labs' scripts, so the pass also walks the scripts named in each guide section and in the lab's `scripts/` folder, in the order the guide uses them.

---

## 4. Order of the pass

Run the labs in order 1.1, 1.2, 1.3, because later labs use what the earlier ones create.

For each lab:

1. Read the lab guide and its checklist.
2. Follow every step that has a PowerShell or CLI block, then every lab script the guide names, one command at a time, as a learner would. Run nothing the guide does not say, except the read-back commands needed for evidence.
3. After each command, record its exit code (`$LASTEXITCODE` for native commands such as `az`; `$?` for cmdlets) and what the shell printed.
4. Run the lab's validator after the path, once:

   ```powershell
   pwsh -NoProfile -File ./module-1-identities-governance/<lab folder>/scripts/Test-Lab.ps1
   ```

   Read the exit code of that process. Record it with the pass and fail counts it prints.

5. Post one comment per lab on #300 with the report table (section 5).

Lab specifics:

- Lab 1.1 uses Microsoft Graph and needs the maintainer's sign-in (rule 1).
- Lab 1.2 needs the lab users to exist in the subscription's tenant. If they do not, record each role-assignment step that needs them as `BLOCKED` and name the plan on #325 as the way to resolve it.
- Lab 1.3 creates policy assignments, locks, budgets and the Advisor alert. Check that the names the steps create are the names the lab's lookup accepts, and that the alert step works in the order the guide gives.

---

## 5. Report table

One table per lab, one row per step or script command:

| Step | Result | Guide says | Shell shows | Evidence |
| --- | --- | --- | --- | --- |
| `1.3.8` | `OK`, `DRIFT`, `WRONG` or `BLOCKED` | the command or expected result in the guide | the output, shortened | command, exit code, time (UTC) |

Result classes:

- `OK`: the command ran and the shell shows what the guide says.
- `DRIFT`: it works but the guide's wording, name or output differs from what the shell shows.
- `WRONG`: the command fails or leaves a state the guide does not describe.
- `BLOCKED`: it could not run, with the reason.

Under the table, add the `Test-Lab.ps1` line: command, exit code, pass and fail counts. A result with no exit code recorded is not evidence.

Redact before posting: the comment holds no tenant or subscription name or id, no account address, no real person's name and no local path with a user name. Name them by role (`the rehearsal subscription`, `the test tenant`) or by placeholder.

---

## 6. Cleanup

After a lab's validator has run, ask the maintainer whether to clean up. Only on a yes, run that lab's `Remove-LabResource.ps1` and record its exit code and what it removed. Lab 1.3 is cleaned with its own script, which removes the locks first because a CanNotDelete lock blocks deleting what is inside the group.

Without a yes, leave the resources and say so in the lab's comment. Never delete a resource by hand to obtain a clean state.

---

## 7. Defects

For each `DRIFT` or `WRONG` row, search every other lab for the same pattern (the same script, the same command shape, the same guide wording) before filing. File one class issue per pattern, with the labs and steps it affects, and link it from the lab's comment on #300.
