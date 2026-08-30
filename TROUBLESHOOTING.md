# Troubleshooting Guide

This guide addresses common issues encountered while setting up or running the SkyCraft labs.

## 🔑 Identity & Authorization Issues

### "Tenant Mismatch" Error

**Symptoms**: You receive a `Status: 400 (BadRequest)` when attempting to assign roles (e.g., in Lab 1.2 scripts).
**Cause**: The Azure Subscription you are using is linked to a different Microsoft Entra ID tenant than the one where your User identities reside.
**Solution**:

1.  **Verify Tenants**: Run `Get-AzContext` to see your current TenantId. Run `Get-MgContext` to see your Graph TenantId. They must match.
2.  **Switch Context**: Use `Connect-AzAccount -TenantId <TargetTenantId>` to switch your subscription context if possible.
3.  **Cross-Tenant Setup**: If using a separate subscription (e.g., MSDN) and a separate Entra ID (e.g., Developer Program), you must add the "Service Principal" or "User" as a B2B Guest in the subscription's tenant to verify role assignments.

### "Insufficient Privileges" for Graph

**Symptoms**: Scripts dealing with Entra ID Users/Groups fail with "Insufficient privileges to complete the operation".
**Solution**:

1.  Ensure you have the **User Administrator** or **Global Administrator** role in Entra ID.
2.  Ensure you have granted consent to the Microsoft Graph PowerShell application.

## 💻 Environment Issues

### "The term 'az' is not recognized" or "The term 'bicep' is not recognized"

**Cause**: Azure CLI or Bicep is not installed or not in your system PATH.
**Solution**:

1.  Install the latest **Azure CLI** (v2.40+ recommended).
2.  Install **Bicep CLI**.
3.  Restart your terminal/VS Code reliability.

### "The script ... cannot be run because the following modules ... are missing" (`#Requires`)

**Cause**: Scripts declare their dependencies with `#Requires -Version 7.0` and `#Requires -Modules ...`, so they fail fast on a host that lacks PowerShell 7 or the required Az / Microsoft Graph modules.
**Solution**:

1.  Ensure you are on **PowerShell 7+** (`$PSVersionTable.PSVersion`); install from <https://aka.ms/powershell>.
2.  Install only the narrow submodules the lab needs (faster than the full `Az` / `Microsoft.Graph` meta-modules). Examples:

    ```powershell
    # Az labs (install the submodules named in the script's #Requires line)
    Install-Module Az.Accounts, Az.Resources, Az.Network, Az.Compute, Az.Storage `
        -Scope CurrentUser -Repository PSGallery -Force

    # Module-specific extras as needed
    Install-Module Az.Monitor, Az.OperationalInsights, Az.KeyVault, Az.RecoveryServices `
        -Scope CurrentUser -Force

    # Lab 1.1 / 1.2 identity scripts (Microsoft Graph submodules — NOT the full Microsoft.Graph)
    Install-Module Microsoft.Graph.Authentication, Microsoft.Graph.Users, Microsoft.Graph.Groups `
        -Scope CurrentUser -Force
    ```

3.  Re-run the script. The `#Requires` line at the top of each script lists exactly which modules it needs.

## ☁️ Deployment Errors

### "QuotaExceeded"

**Symptoms**: Deployment fails stating you have exceeded the quota for vCPUs or Public IPs.
**Solution**:

1.  Check your usage in the "Usage + quotas" blade of your Subscription.
2.  Request a quota increase or delete unused resources from other projects.
3.  Note: Free Trial subscriptions have strict limits (often 4 vCPUs) which may limit simultaneous lab deployments.

### "Public IP Address is not available"

**Cause**: Specific regions (like Sweden Central) may have temporary capacity issues for Standard Public IPs.
**Solution**:

1.  Try deploying to a different region (update your local parameter file).
2.  Wait and retry later.

## 🔁 Lab Cycle Teardown (`tools/Remove-LabCycle.ps1`)

### The Recovery Services Vault teardown, and the 14-day residual that is not real

This section exists because the repository believed the wrong thing about this for months. Two
claims are involved; one is true and one is false, and they are easy to confuse.

**True: soft delete is platform-enforced and cannot be turned off.** Azure Backup's "secure by
default" applies `softDeleteState` = `enhancedSecurityState` = `AlwaysON` at 14 days to every new
Recovery Services Vault. There is no way around it:

- creating the vault with soft delete disabled fails with `BMSUserErrorSoftDeleteStateNotSetToAlwaysON`
  ("Soft delete state and enhanced security state must be set to AlwaysON for this API version");
- omitting the setting deploys fine, and Azure applies `AlwaysON` at the 14-day default anyway;
- `Set-AzRecoveryServicesVaultProperty -SoftDeleteFeatureState Disable` afterwards returns
  `BadRequest`.

No API version and no tool turns it off. `docs/bicep-standards.md` §4.5 records it as a platform
constraint. **Do not go looking for a "disarm soft delete" step — there is not one, and the teardown
does not need one.**

**False: that the vault is therefore stuck for 14 days.** It is not. Azure permits deleting a vault
that holds only *soft-deleted* items; the vault then enters a soft-deleted state itself, at no cost,
and immediately stops being an active ARM resource. Verified end to end during PR #102 on the MPN
subscription, with a completed on-demand VM backup on the protected item:

1. stop protection with the recovery points removed;
2. delete the Backup Vault, the blob backup instance, both RBAC role assignments **and** the
   Recovery Services Vault — one pass, no waiting, no support ticket;
3. `Get-AzRecoveryServicesVault`, `Get-AzDataProtectionBackupVault` and `az backup vault list` all
   return empty;
4. redeploying the **same vault name into the same resource group** succeeds immediately.

`Remove-LabCycle.ps1` therefore **asserts the vault is gone** rather than tolerating it. A surviving
vault is a failure, and it leaves through the script's exit code.

### "Vault cannot be deleted because it contains backup items"

**Cause**: your tooling is too old. This is almost certainly where the "permanent RSV residual"
belief came from.

**Minimum versions — Azure CLI 2.75.0 or Az PowerShell 7.5.0.** Older tooling takes a different code
path: it insists on a completely *empty* vault, which soft delete makes impossible, and leaves you
waiting out the 14-day window for no reason. The v0.8.0 cycle ran on az CLI 2.86.0, Az PowerShell
14.0.0 and Az.RecoveryServices 7.7.1.

`Remove-LabCycle.ps1` checks both versions **before it deletes anything** and stops with this
message rather than failing deep in a teardown that has already removed fifteen labs. To fix:

```powershell
az upgrade
Update-Module -Name Az -Force
```

### An empty `AzureBackupRG_<region>_1` is left behind

**Cause**: Azure creates this group itself. While a VM is protected, the Recovery Services Vault
places a `Microsoft.Compute/restorePointCollections` in a resource group named
`AzureBackupRG_<region>_1`, and **both the collection and the group outlive the vault**. No lab
script owns it — the string `AzureBackupRG` appears nowhere else in this repository.

`Remove-LabCycle.ps1` sweeps it, but only when the group holds *nothing but* restore point
collections. A group by that name holding anything else is left standing and reported, because
deleting a resource group on a name match alone is exactly the damage the sweep exists to prevent.
If you see it reported as kept, look inside it by hand.

### `NetworkWatcherRG` is still there after a clean teardown

**This is correct, and deleting it would be a mistake.** `NetworkWatcherRG` is Azure's own resource
group and is shared with every other workload in the subscription. Lab 5.3's `Remove-LabResource.ps1`
removes *this repository's children* from inside it — the flow log, the connection monitor, the
Traffic Analytics DCR/DCE and the NetworkWatcherAgent extensions — and leaves the group itself
standing. The orchestrator never lists it among the groups it deletes.

### The Log Analytics workspace name is still reserved

**This is expected, and it is not a failure.** Lab 5.1's teardown deletes the workspace into a
14-day soft-delete window that keeps `platform-skycraft-swc-law` reserved. Measured on 2026-08-04:
redeploying the same name into the same resource group makes Azure **recover** the workspace,
provisioning state `Succeeded`.

`Invoke-LabCycle.ps1`'s preflight therefore reports this as a **warning and continues**. Treating it
as fatal would mean every successful run blocked the next one from starting.

### The cycle reported success and nothing was deployed

**Cause, historically**: a lab script that printed a failure and exited 0. Both known instances are
fixed — [#104](https://github.com/mbiszczanik/skycraft/issues/104) for Lab 2.1's cleanup and
[#105](https://github.com/mbiszczanik/skycraft/issues/105) for Lab 5.2's — and
`tests/Exit-Code-Propagation.Tests.ps1` now holds the whole repository to the pattern.

Two things make this visible if it recurs:

- `tools/Invoke-LabScript.ps1` is the only process that carries a lab script's real exit code out.
  A script declaring `#Requires -Modules` and launched with `pwsh -File` has its `exit` **discarded**
  and the process reports 0 regardless; the shim declares no module requirement, which is the entire
  reason it works.
- The per-step transcripts under `tools/lab-cycle-logs/` hold exactly what each script printed. Read
  the transcript before believing the status.

> [!WARNING]
> **Treat a transcript as a secret.** Nothing in it is redacted: it carries Az error streams and the
> deployment parameter values each script echoes, and a deployment output can contain a connection
> string or an access key. `.gitignore` keeps the whole `tools/lab-cycle-logs/` directory out of
> history. Read a transcript before pasting it into an issue or a chat.
