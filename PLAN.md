# PLAN - issue #184: Lab 5.2 VM backup denied by Lab 1.3's Require-Environment-Tag-RG

Deleted in the PR's last commit. Spec: issue #184.

## Decisions

- Instant-restore snapshots go to a SkyCraft-owned resource group, `platform-skycraft-swc-rpc1-rg`
  (policy prefix `platform-skycraft-swc-rpc`, suffix `-rg`; Azure Backup inserts the number).
  Not `platform-skycraft-swc-rg`: Lab 1.3 puts a CanNotDelete lock on it, and a locked snapshot
  group blocks restore-point garbage collection (UserErrorRpCollectionLimitReached).
- The group is declared in `main.bicep` (AVM resource-group 0.4.4, common tags, no lock), so it
  exists before the policy names it.
- The legacy `AzureBackupRG_*` cleanup stays for estates created before this fix.
- Open risk, settled only by a live run: whether Lab 1.3's `Enforce-Project-Tag` denies the
  untagged restore point collection inside the new group.

## Steps

- [x] 1. `bicep/main.bicep`: snapshot resource group module + outputs (name, prefix, suffix).
- [x] 2. `scripts/Deploy-Bicep.ps1`: policy created with, and an existing policy reconciled to, the
      snapshot group; on-demand backup whenever the VM has no recovery point and no running job;
      poll the job briefly and count a Failed job as a deployment failure.
- [x] 3. `scripts/Test-Lab.ps1`: policy names the group; group exists, tagged, unlocked; latest
      VM backup job is not Failed.
- [x] 4. `scripts/Remove-LabResource.ps1` + `tests/Remove-LabResource.Tests.ps1`: delete the owned
      group; keep the legacy sweep.
- [x] 5. `tests/Script-Standards.Tests.ps1`: guards for steps 2-4.
- [x] 6. `tools/lab-cycle-manifest.psd1`, `tools/Remove-LabCycle.ps1`, `tests/LabCycle.Tests.ps1`:
      the snapshot group joins the residual sweep.
- [ ] 7. Docs: lab guide (5.2.2, 5.2.3, 5.2.9, Troubleshooting), checklist, ARCHITECTURE,
      TROUBLESHOOTING.md.
- [ ] 8. Offline gate: Pester suites, PSScriptAnalyzer, bicep build/build-params, PR gate check.
- [ ] 9. Draft PR, `Refs #184`, live verification deferred; delete this file.
