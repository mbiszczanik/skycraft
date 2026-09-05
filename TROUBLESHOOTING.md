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

### Lab 1.1 hangs at "Checking Microsoft Graph connection..."

**Symptoms**: `New-LabUser.ps1`, `Test-Lab.ps1` or `Remove-LabResource.ps1` in Lab 1.1 print the connection banner and then sit there. Nothing times out, nothing fails; run under `tools/Invoke-LabCycle.ps1` the phase is eventually killed at its limit and reported `Failed(Timeout)`.

**Cause**: `Connect-MgGraph -Scopes ...` binds the **delegated** parameter set, which signs a *person* in. When the cached token needs a refresh that the broker cannot complete silently, the SDK falls back to a prompt — and a run with no console has nobody to answer it. Turning WAM off does not help; the prompt simply moves.

**If you are running the lab by hand** — which is how SkyCraft runs Lab 1.1 today — answer the prompt. It is a real sign-in and the scripts wait for it on purpose. If no prompt appears at all, the browser handoff failed rather than the token: check that a default browser is set, or sign in first with `Connect-MgGraph -UseDeviceCode` and re-run the script, which will reuse that context.

**If the run is unattended** — a scheduler, CI, `tools/Invoke-LabCycle.ps1`, anything with no console — there is nothing to answer the prompt, and the only real fix is to stop asking for one: give the lab a **service principal** so it signs in app-only (client credentials). This is **optional**, and today's cycle does not need it: `tools/lab-cycle-manifest.psd1` runs 1.2 through 5.3 and does not include Lab 1.1. Set it up when you automate 1.1, not before.

The three Lab 1.1 scripts pick a service principal up automatically when these variables are set:

| Variable | Meaning |
| :--- | :--- |
| `SKYCRAFT_GRAPH_TENANT_ID` | Tenant the principal lives in (the Entra tenant, which is **not** necessarily the subscription's) |
| `SKYCRAFT_GRAPH_CLIENT_ID` | The app registration's application (client) ID |
| `SKYCRAFT_GRAPH_CERT_THUMBPRINT` | Thumbprint of a certificate in `Cert:\CurrentUser\My` — preferred |
| `SKYCRAFT_GRAPH_CLIENT_SECRET` | Client secret — used when no thumbprint is set |
| `SKYCRAFT_UNATTENDED` | Set to anything by a caller with no console. Makes a missing or half-configured principal fail in seconds instead of waiting out a step timeout |

With none of them set the scripts sign in interactively exactly as before. Set **by halves** they refuse to start and name the variable that is missing: falling back to a prompt there is the hang this exists to remove, so a half-configured principal is reported rather than degraded into.

`SKYCRAFT_UNATTENDED` is the *only* thing the scripts treat as "nobody is watching". They deliberately do not sniff the console for it — `[Console]::IsInputRedirected` was tried and dropped, because it refuses a sign-in to a learner who is sitting right there the moment anything redirects a stream, and refusing a prompt someone could have answered is a worse failure than the hang it would have caught. An automated caller says so explicitly.

These are deliberately *not* the Azure SDK's `AZURE_TENANT_ID` / `AZURE_CLIENT_ID` / `AZURE_CLIENT_SECRET`. Those are usually already exported for the **subscription** identity, which in this project is a different account from the one that administers Entra ID — consuming them would sign Graph in as the wrong principal, silently. Map them yourself if your CI sets them:

```powershell
$env:SKYCRAFT_GRAPH_TENANT_ID = $env:AZURE_TENANT_ID
$env:SKYCRAFT_GRAPH_CLIENT_ID = $env:AZURE_CLIENT_ID
$env:SKYCRAFT_GRAPH_CLIENT_SECRET = $env:AZURE_CLIENT_SECRET
```

### Creating the Lab 1.1 service principal

Only needed for an unattended run — see above. Requires **Global Administrator** in the Entra tenant (granting application permissions needs admin consent). Run once.

```powershell
# 1. Register the application and give it a service principal in the tenant.
$appId = az ad app create --display-name 'SkyCraft-Lab-Automation' --query appId --output tsv
az ad sp create --id $appId

# 2. Grant the four Microsoft Graph APPLICATION permissions the lab actually uses, then consent.
#    The role IDs are read from the tenant rather than hard-coded, so this cannot drift.
$graphAppId = '00000003-0000-0000-c000-000000000000'
$graph = az ad sp show --id $graphAppId --output json | ConvertFrom-Json

foreach ($role in 'User.ReadWrite.All', 'Group.ReadWrite.All', 'Domain.Read.All', 'User.Invite.All') {
    $roleId = ($graph.appRoles | Where-Object { $_.value -eq $role -and $_.allowedMemberTypes -contains 'Application' }).id
    az ad app permission add --id $appId --api $graphAppId --api-permissions "$roleId=Role"
}
az ad app permission admin-consent --id $appId
```

That is the **minimum** set: `User.ReadWrite.All` creates and deletes the three internal users, `Group.ReadWrite.All` covers the groups and their memberships, `Domain.Read.All` resolves the tenant's default domain, and `User.Invite.All` invites the guest. `Directory.ReadWrite.All` — which the interactive sign-in asks for, and which the lab guide's portal steps rely on — is **not** required app-only; do not grant it to this principal.

Then create a credential. A certificate is preferred: it never sits in an environment variable, and it cannot be leaked by an environment dump or a transcript.

```powershell
# Certificate (preferred)
$cert = New-SelfSignedCertificate -Subject 'CN=SkyCraft-Lab-Automation' `
    -CertStoreLocation Cert:\CurrentUser\My -KeyExportPolicy NonExportable `
    -KeySpec Signature -NotAfter (Get-Date).AddYears(1)
az ad app credential reset --id $appId --cert ([Convert]::ToBase64String($cert.RawData)) --append

$env:SKYCRAFT_GRAPH_TENANT_ID       = '<entra-tenant-id>'
$env:SKYCRAFT_GRAPH_CLIENT_ID       = $appId
$env:SKYCRAFT_GRAPH_CERT_THUMBPRINT = $cert.Thumbprint
```

```powershell
# Client secret (simpler; expires, and is a string you now have to keep somewhere)
$secret = az ad app credential reset --id $appId --years 1 --query password --output tsv
```

### Storing and rotating the credential

**Never commit either credential.** No secret belongs in a `.bicepparam`, a script default, a transcript, or a commit message — `.gitignore` and the `gitleaks` CI job are the backstop, not the plan.

Where the secret should live, in order of preference:

1. **Nowhere** — use the certificate. The private key stays in `Cert:\CurrentUser\My` and only the thumbprint is ever exported.
2. **`Microsoft.PowerShell.SecretManagement`**, materialised into the environment variable for the session that needs it:

    ```powershell
    Install-Module Microsoft.PowerShell.SecretManagement, Microsoft.PowerShell.SecretStore -Scope CurrentUser
    Set-Secret -Name SkyCraft-Graph-ClientSecret -Secret $secret

    # ...then, once per session, before running the lab:
    $env:SKYCRAFT_GRAPH_CLIENT_SECRET = Get-Secret -Name SkyCraft-Graph-ClientSecret -AsPlainText
    ```

    The scripts read the environment variable and never call `Get-Secret` themselves, on purpose: a locked `SecretStore` vault prompts for its password, which would be the same hang in a different place.
3. **The CI secret store** (GitHub Actions secrets, Key Vault), exported into the environment by the job.

Rotation:

- `az ad app credential reset --id $appId --years 1` issues a new secret. Without `--append` it **invalidates every existing credential** on the app — which is what you want for a compromised secret, and what you do not want mid-cycle.
- Certificates expire too. Re-run the `New-SelfSignedCertificate` block with `--append`, update `SKYCRAFT_GRAPH_CERT_THUMBPRINT`, then remove the old credential.
- After rotating, verify without touching the tenant's state: `pwsh -NoProfile -File .\module-1-identities-governance\1.1-entra-users-groups\scripts\Test-Lab.ps1`. It signs in and only reads.

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
    Install-Module Microsoft.Graph.Authentication, Microsoft.Graph.Users, Microsoft.Graph.Groups, `
        Microsoft.Graph.Identity.DirectoryManagement, Microsoft.Graph.Identity.SignIns `
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

### An `AzureBackupRG_<region>_<n>` group is still there

**This is not necessarily wrong.** Azure creates that group itself: while a VM is protected, the
Recovery Services Vault parks a `Microsoft.Compute/restorePointCollections` in it, and both the
collection and the group outlive the vault.

**The group is shared.** It holds restore point collections for *every* protected VM in that
region, including workloads that have nothing to do with SkyCraft. So the question is never "is the
group gone" — it is "is *our* collection gone".

- **Lab 5.2's `Remove-LabResource.ps1` owns the removal** (added by #111 for issue #105). It deletes
  only collections named `AzureBackup_*skycraft*`, and deletes the group itself only if that leaves
  it empty.
- **`Remove-LabCycle.ps1` only asserts.** It fails if a SkyCraft-owned collection is still parked in
  one of those groups, and points you at lab 5.2's transcript. It deliberately does not delete
  them: it cannot filter by ownership as safely as the script that already does.

If the assertion fails, read `tools/lab-cycle-logs/module-5-monitoring-maintenance-5.2-business-continuity.teardown.log`.
If the *group* survives with no SkyCraft collection in it, nothing is wrong — something else in the
subscription is using it.

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

### Lab 3.3's teardown reports `exit 124`

**`124` is the orchestrator's timeout sentinel**, not an error from the lab. It means the delete was
still running when the limit killed it — which sends you somewhere different from a delete that
actually failed. The report says so in words rather than printing the bare number.

**Cause**: deleting a **Container Apps Environment** is slow. Measured on 2026-08-30, lab 3.3's
teardown takes **24.3 minutes** end to end, and almost all of that is the environment. The original
20-minute limit killed it mid-delete; the manifest now allows 45 minutes.

Nothing is lost when this happens — the resource group delete that follows sweeps the environment
up, and the final assertions still pass. It is worth fixing anyway: a teardown that reports a
failure on every otherwise-clean run teaches its operator to discount failures, which is the one
habit this orchestrator exists to prevent.

If you see it again, raise `TimeoutMs` on that lab's entry in `tools/lab-cycle-manifest.psd1`. Do
not lower the others to match your fastest run — a limit is a backstop against a hung phase, not a
performance budget, and a phase retrying through regional capacity legitimately takes several times
its measured duration.

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
