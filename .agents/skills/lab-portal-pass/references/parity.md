# Parity check: one end state, three paths

Rule (skycraft #362): each lab can be done in the Portal, with PowerShell / CLI, and with its Bicep (`Deploy-Bicep.ps1`), and all three leave the same end state, which `Test-Lab.ps1` accepts. The Portal pass is the only time a Portal-built state exists, so the pass checks it against the other two paths.

## Per lab, right after Test-Lab (step 4)

Run it **before the next lab starts**: later labs change earlier labs' resources (4.4 changes 4.1's network rules), and a what-if after that reports the later lab's changes, not the gap.

- A what-if that exits 0 does not show that the deployment succeeds. **Where** the parity check ran a what-if only, **the report shall** say that no deployment ran. On 2026-10-25 Lab 4.2's what-if after Lab 5.2 exited 0 and the deployment failed (`InvalidValuesForRequestParameters`: 7-day soft delete under an enabled 30-day point-in-time restore, #364).
- **Before** an earlier lab's cleanup or Bicep runs on an estate where later labs ran, **the agent shall** read the settings the later labs turn on (Lab 5.2: point-in-time restore, change feed, 35-day soft delete) and say which of them will block it.

1. **What-if the Bicep against the Portal state** (read-only, nothing is deployed):
   ```bash
   pwsh -NoProfile -NonInteractive -File "<skill-dir>/scripts/run-azps.ps1" \
     -SubscriptionId <sub-id> -Script <scratchpad>/src/<module>/<lab>/scripts/Deploy-Bicep.ps1 -WhatIf \
     > <scratchpad>/whatif-<lab>.txt 2>&1; echo "EXIT=$?"
   ```
   This example uses bash; use PowerShell continuations and `$LASTEXITCODE` in PowerShell.
   Resolve `<skill-dir>` from the loaded skill's actual location.
   The wrapper refuses `Deploy-Bicep.ps1` without `-WhatIf`. If the template needs a secret parameter (a VM admin password), do not invent one: record the what-if as not run and why.
2. **Classify every change the what-if reports** (`+ Create`, `~ Modify` with each property, `- Delete`, `x NoEffect` is fine):
   - **difference** - the Bicep would create a resource the guide never creates, or set a property to a value the Portal path left different. Each one is a parity gap.
   - **noise** - what-if artefacts that are not end-state differences: read-only or server-computed properties, `provisioningState`, etags, default values ARM fills in on read, API-version-only properties. When unsure, read the property back with `az ... show` and compare values; a `$null` vs `false` pair is a **difference** (that is exactly what breaks Test-Lab, #355).
   Record known noise patterns in the "What-if noise seen" list below so later passes classify faster.
3. **Map the reverse direction.** Guide steps that changed Azure but have no Bicep counterpart do not show up in a what-if. Walk the lab's step list and mark each change-step as `bicep: yes/no/portal-only`.
4. **Scripted path coverage.** For each change-step, note whether the guide or the lab's `scripts/` gives a PowerShell / CLI equivalent (`scripted: yes/no`).

## Per module, at the end (optional, by the user's decision)

- **Bicep path:** `tools/Invoke-LabCycle.ps1` deploys the Bicep on a clean state and runs Test-Lab; quote its latest run for the module, or ask before running it (it creates and deletes the whole estate).
- **Scripted path replay:** only where a lab has a scripted path. It needs a clean state (the lab's resources removed), then the guide's commands in order, Test-Lab, and the what-if again. This is live delete/create work: propose it in the report's decisions, do not start it unasked.

## Recording

Add a `parity` object to each lab in `pass.json`; `render_report.py` prints it in the lab's comment:

```json
"parity": {
  "whatif_exit": 0,
  "how": "Deploy-Bicep.ps1 -WhatIf via run-azps.ps1, right after Test-Lab",
  "changes": [
    {"resource": "devskycraftswcsa/blobServices/default", "change": "Modify", "property": "isVersioningEnabled", "portal": "null", "bicep": "false", "verdict": "difference", "issue": "#355"}
  ],
  "steps_without_bicep": ["4.2.11 (upload: data plane, portal-only)"],
  "steps_without_script": ["4.2.3", "4.2.5"],
  "note": "..."
}
```

Each `difference` also goes into `findings` and to its issue: the lab's existing issue when one fits, otherwise a comment on #362 listing the lab, the resource, the property and both values. Never paste what-if output publicly unread: it can show ids and names of the real environment; redact per `redaction.md`.

## What-if noise seen

Storage (first seen on Lab 4.4, 2026-10-16, AVM storage module): all of these are defaults or properties the Portal does not write, with no effect on the end state:
- `storageAccounts`: `+ customDomain.useSubDomainName: false`, `+ isLocalUserEnabled: false`, `+ isSftpEnabled: false`, `x encryption.services` (NoEffect).
- `blobServices/default`: `- deleteRetentionPolicy.allowPermanentDelete: false`, `+ automaticSnapshotPolicyEnabled: false`, `+ containerDeleteRetentionPolicy.allowPermanentDelete: false`, `+ lastAccessTimeTrackingPolicy: "[if(...)]"` (an unresolved AVM expression).
- `containers/*`: `- defaultEncryptionScope: "$account-encryption-key"`, `- denyEncryptionScopeOverride: false`.
- `* Ignore` lines are resources in the scope that the template does not declare; they are not differences.

Monitoring (Lab 5.1, 2026-10-16):
- `metricAlerts`: `criteria.odata.type` Multiple->Single resource, criterion `name` "Metric1" -> the Bicep's name, `- targetResourceRegion`, `- targetResourceType`, `+ description`: the Portal form's shape for the same single-VM rule.
- `workspaces`: `+ forceCmkForQuery`, `x features` (NoEffect).
- `diagnosticSettings`: disabled metric entries (`Transaction`, `Capacity` with `enabled: false`), `retentionPolicy.days: 0`, disabled `StorageDelete` log entry.

**What-if blind spot:** a different `location` on an existing resource (action group `swedencentral` from the Portal vs `global` in the Bicep) is not reported. Read back `location` of every resource the lab creates.

(Add patterns here as passes find them, with the resource type and property.)

## Output hygiene

- Pipe the output through `sed -E 's/\x1b\[[0-9;]*m//g'` - Az what-if colours every token and grep finds nothing in the raw file.
- Lab 4.4's `Deploy-Bicep.ps1` prints the machine's **public IP** ("Auto-detecting client IP"), and every what-if prints full resource ids with the subscription id. Keep the output local; quote only redacted lines.
