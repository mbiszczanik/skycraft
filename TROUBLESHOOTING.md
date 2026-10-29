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

### "RoleAssignmentExists" from Lab 1.2 `Deploy-Bicep.ps1 -IncludeRoleAssignments`

**Symptoms**: The role-assignments deployment fails with `RoleAssignmentExists` although `Test-Lab.ps1` reports every assignment present.
**Cause**: Azure allows one assignment per (scope, role, principal). `New-LabRoleAssignment.ps1` and the portal create assignments under random names; `role-assignments.bicep` names its own with `guid(scope, role, principal)` and cannot adopt one that already exists under another name. The script reads which of the five exist before it deploys, prints `[KEEP]` for each, and the template skips those (`parExistingAssignments`), so this appears only when an assignment was created between that read and the deployment: in the Portal or by `New-LabRoleAssignment.ps1` while the script ran.
**Solution**: Run `Deploy-Bicep.ps1 -IncludeRoleAssignments` again. It now finds the assignment, keeps it, and deploys only the ones still missing.

### "Authentication failed against resource MicrosoftGraphEndpointResourceId"

**Symptoms**: `Get-AzRoleAssignment`, `New-AzRoleAssignment`, `Remove-AzRoleAssignment`, `Get-AzADUser` or `Get-AzADGroup` fails with `Authentication failed against resource MicrosoftGraphEndpointResourceId. User interaction is required`, although other Az commands work and you hold Owner on the subscription.
**Cause**: These cmdlets call Microsoft Graph to resolve users, groups and service principals. Your tenant's Conditional Access (MFA, for example) asks for interaction before it issues a Graph token to Azure PowerShell, and the sign-in you made did not include one. The lab scripts read, create and remove role assignments through the Azure Resource Manager API instead, so their role steps do not need Graph (#397); only the steps that find a user, group or app by name do (Lab 1.2's `Test-Lab.ps1`, `Remove-LabResource.ps1` and `Deploy-Bicep.ps1 -IncludeRoleAssignments`, and Lab 5.2's `Deploy-Bicep.ps1`, `Test-Lab.ps1` and `Remove-LabResource.ps1`, which find the Backup Management Service app when the VM is encrypted with Azure Disk Encryption; they skip that lookup with `-BackupManagementServiceObjectId`).
**Solution**: Sign in again with a Graph token, then rerun the command or the script:

```powershell
Connect-AzAccount -AuthScope MicrosoftGraphEndpointResourceId
```

`New-LabRoleAssignment.ps1` finds the principals through Microsoft Graph PowerShell instead; it asks for its own sign-in (`Connect-MgGraph`).

### "Insufficient Privileges" for Graph

**Symptoms**: Scripts dealing with Entra ID Users/Groups fail with "Insufficient privileges to complete the operation".
**Solution**:

1.  Ensure you have the **User Administrator** or **Global Administrator** role in Entra ID.
2.  Ensure you have granted consent to the Microsoft Graph PowerShell application.

### Lab 1.1: "Microsoft Graph sign-in did not complete"

**Symptoms**: `New-LabUser.ps1`, `Test-Lab.ps1` or `Remove-LabResource.ps1` in Lab 1.1, or `New-LabRoleAssignment.ps1` in Lab 1.2, stop right after "Checking Microsoft Graph connection..." with `[ERROR] Failed to connect to Microsoft Graph: Microsoft Graph sign-in did not complete ...` and exit 1. No sign-in or consent prompt appeared.

**Cause**: `Connect-MgGraph` returned without an error but also without a signed-in context. A delegated sign-in for scopes the account has never consented to can do exactly that. Before the scripts checked for it, they printed `Connected to Tenant:  as` with empty values and every Graph call after it failed with "Authentication needed" (issue #242). A personal Microsoft account (the kind behind most free Azure accounts) that signs in without naming the lab tenant ended the same way in the pass of 2026-10-20 (#300). The scripts name a tenant when they know one: `-TenantId` (`New-LabUser.ps1` only), else `SKYCRAFT_GRAPH_TENANT_ID`, else the tenant of a Microsoft Graph sign-in already in the session, else the tenant of an Az context in the session, including one Az PowerShell restored from an earlier session. The Graph sign-in's tenant is what keeps a sign-in again for missing scopes in the lab tenant: without it, `Connect-MgGraph -TenantId <lab tenant> -Scopes User.Read.All` followed by `Test-Lab.ps1` signed in again without a tenant and a personal account landed in its own directory (pass of 2026-10-21, #408). A Graph sign-in in that personal-account directory, which such a failed sign-in leaves behind, is not counted as a tenant. If that Graph sign-in and the Az context are in different tenants, they stop with `[ERROR]` before signing in, name both tenants and say how to choose one: set `SKYCRAFT_GRAPH_TENANT_ID` or run `Connect-AzAccount -TenantId` to keep the Graph tenant, or run `Disconnect-MgGraph` to use the Az one. With no tenant from any of these they print a line that says so just before they sign in.

**Solution**:

1.  Interactive sign-in: all four scripts request `User.ReadWrite.All`, `Group.ReadWrite.All` and `Directory.ReadWrite.All` (`New-LabUser.ps1` adds `Domain.Read.All` and `User.Invite.All`), so one consent covers Lab 1.1 and Lab 1.2's role assignment script. Since the scripts showed no prompt, sign in with a device code instead - its sign-in and consent happen in a browser you open yourself - using the full set `New-LabUser.ps1` requests:

    ```powershell
    Connect-MgGraph -TenantId '<your tenant id>' -UseDeviceCode -Scopes 'User.ReadWrite.All', 'Group.ReadWrite.All', 'Directory.ReadWrite.All', 'Domain.Read.All', 'User.Invite.All'
    ```

    A tenant with security defaults on refuses a device code sign-in: the device login page ends with error 530035. Microsoft turns security defaults on in tenants created from 2026-07-01 ([Security defaults: block device code flow](https://learn.microsoft.com/entra/fundamentals/security-defaults#block-device-code-flow)). There, run the script in PowerShell 7 on your own machine, where it opens the sign-in in your browser; do not turn security defaults off for it. In Azure Cloud Shell the scripts need neither, see [Lab 1.1 and Lab 1.2 scripts in Azure Cloud Shell](#lab-11-and-lab-12-scripts-in-azure-cloud-shell).

    The tenant ID is the **Tenant ID** on the **Microsoft Entra ID** > **Overview** page of the lab tenant. Name it: without it, a personal Microsoft account signs in to its own directory instead of the lab tenant. Then open the address the command prints, enter the code, accept the consent, then re-run the script: it reuses that context, because its scopes cover what every Module 1 script requests. A context whose scopes do not cover the script's (for example one left by `Connect-MgGraph -Scopes User.Read.All`) is not reused: the script names the scopes it lacks and signs in again with the ones it needs, in the same tenant (issues #273, #408). Where the tenant requires admin consent, a Global Administrator runs the same command once and ticks **Consent on behalf of your organization**. `New-LabUser.ps1 -DemoMode` requests the same scopes and creates nothing, so it is another way to see whether the consent is in place.
2.  App-only sign-in (`SKYCRAFT_GRAPH_*` set): less likely, since a principal missing an application permission usually still gets a token and fails later with "Insufficient privileges". Still, check that the app registration holds the application permissions listed in [Creating the Lab 1.1 service principal](#creating-the-lab-11-service-principal) and that admin consent was granted for them.

### Lab 1.1 hangs at "Checking Microsoft Graph connection..."

**Symptoms**: `New-LabUser.ps1`, `Test-Lab.ps1` or `Remove-LabResource.ps1` in Lab 1.1 print the connection banner and then sit there. Nothing times out, nothing fails; run under `tools/Invoke-LabCycle.ps1` the phase is eventually killed at its limit and reported `Failed(Timeout)`.

**Cause**: `Connect-MgGraph -Scopes ...` binds the **delegated** parameter set, which signs a *person* in. When the cached token needs a refresh that the broker cannot complete silently, the SDK falls back to a prompt — and a run with no console has nobody to answer it. Turning WAM off does not help; the prompt simply moves.

**If you are running the lab by hand**, which is how SkyCraft runs Lab 1.1 today, answer the prompt. It is a real sign-in and the scripts wait for it on purpose. If no prompt appears at all, the browser handoff failed rather than the token: check that a default browser is set, or sign in first with `Connect-MgGraph -TenantId '<your tenant id>' -UseDeviceCode` (refused with error 530035 in a tenant with security defaults on) and the scopes shown under [Lab 1.1: "Microsoft Graph sign-in did not complete"](#lab-11-microsoft-graph-sign-in-did-not-complete), then re-run the script. It reuses that context only when the context's scopes cover the ones the script requests; otherwise it signs in again.

**If the run is unattended** — a scheduler, CI, `tools/Invoke-LabCycle.ps1`, anything with no console — there is nothing to answer the prompt, and the only real fix is to stop asking for one: give the lab a **service principal** so it signs in app-only (client credentials). This is **optional**, and today's cycle does not need it: `tools/lab-cycle-manifest.psd1` runs 1.2 through 5.3 and does not include Lab 1.1. Set it up when you automate 1.1, not before.

The three Lab 1.1 scripts, and Lab 1.2's `New-LabRoleAssignment.ps1`, which reads Lab 1.1's users, pick a service principal up automatically when these variables are set:

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

That is the **minimum** set: `User.ReadWrite.All` creates and deletes the three internal users, `Group.ReadWrite.All` covers the groups and their memberships, `Domain.Read.All` resolves the tenant's initial `*.onmicrosoft.com` domain, and `User.Invite.All` invites the guest. `Directory.ReadWrite.All` — which the interactive sign-in asks for, and which the lab guide's portal steps rely on — is **not** required app-only; do not grant it to this principal.

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
- After rotating, verify without touching the tenant's state: `pwsh -NoProfile -File .\module-1-identities-governance\1.1-entra-users-groups\scripts\Test-Lab.ps1`. It signs in and only reads. A working credential reaches `Connected to Tenant` with a tenant ID and the tenant's initial domain; a broken one stops with `[ERROR]` before any check runs. Any `[FAIL]` lines after that only mean the lab's users and groups are absent, so in a tenant where Lab 1.1 has not been done, an exit code of 1 is expected and says nothing about the credential.

## 💻 Environment Issues

### "The term 'az' is not recognized" or "The term 'bicep' is not recognized"

**Cause**: Azure CLI or Bicep is not installed or not in your system PATH.
**Solution**:

1.  Install the latest **Azure CLI** (v2.40+ recommended).
2.  Install **Bicep CLI**.
3.  Restart your terminal/VS Code reliability.

### "The script ... cannot be run because the following modules ... are missing" (`#Requires`)

**Cause**: Scripts declare their dependencies with `#Requires -Version 7.0` and `#Requires -Modules ...`, so they fail fast on a host that lacks PowerShell 7 or the required Az modules. The Lab 1.1 scripts and Lab 1.2's `New-LabRoleAssignment.ps1` import their Microsoft Graph modules themselves instead and name the command that installs a missing one (next two entries).
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

3.  Re-run the script. The `#Requires` line at the top of each script lists exactly which modules it needs; in the Lab 1.1 scripts and Lab 1.2's `New-LabRoleAssignment.ps1`, the `$labModule` list below it holds the Microsoft Graph ones.

### "[ERROR] This script needs the PowerShell module Microsoft.Graph.Users, which is not installed"

**Cause**: The Lab 1.1 scripts and Lab 1.2's `New-LabRoleAssignment.ps1` import their Microsoft Graph modules themselves instead of with `#Requires` (issue #375), so a missing module stops them before they sign in, with the module's name and the command that installs it. Azure Cloud Shell ships Azure PowerShell and a basic set of Microsoft Graph modules, but not `Microsoft.Graph.Users` ([Features & tools for Azure Cloud Shell](https://learn.microsoft.com/azure/cloud-shell/features#other-microsoft-services)).
**Solution**:

1.  Run the command the script printed. Where other Microsoft Graph modules are installed, it names their version, for example:

    ```powershell
    Install-Module Microsoft.Graph.Users -RequiredVersion 2.28.0 -Scope CurrentUser
    ```

2.  Re-run the script.
3.  In a Cloud Shell session without a storage account, the module is deleted when the session ends: install it again in each new session. See [Module 1 prerequisites](module-1-identities-governance/README.md#-prerequisites).

### Lab 1.1 and Lab 1.2 scripts in Azure Cloud Shell

**Symptoms**: In Cloud Shell, before the fix for issue #418, `Test-Lab.ps1` and the other Lab 1.1 scripts stayed at "signing in interactively to tenant ..." with no prompt, and the device code sign-in the guide offered as the fallback ended with error 530035.

**Cause**: Cloud Shell has no browser for the interactive sign-in, and a tenant with security defaults on refuses a device code sign-in ([Security defaults: block device code flow](https://learn.microsoft.com/entra/fundamentals/security-defaults#block-device-code-flow)).

**What the scripts do**: With no `SKYCRAFT_GRAPH_*` service principal set, the Lab 1.1 scripts and Lab 1.2's `New-LabRoleAssignment.ps1` sign in with Cloud Shell's own sign-in, the one you made when you opened Cloud Shell, through `Get-AzAccessToken -ResourceTypeName MSGraph`. Nothing prompts. That sign-in's Microsoft Graph token carries the permissions Cloud Shell was given, not the ones the scripts ask for: `Directory.ReadWrite.All`, `Group.ReadWrite.All` and `User.Invite.All`, but not `User.ReadWrite.All`. That is enough to create, invite and read users, create groups and add members (`New-LabUser.ps1`, `Test-Lab.ps1`, `New-LabRoleAssignment.ps1`), but not to delete a user, which takes `User.ReadWrite.All` and nothing else ([Delete a user](https://learn.microsoft.com/graph/api/user-delete)).

**Solution**: Nothing to do for `New-LabUser.ps1`, `Test-Lab.ps1` and `New-LabRoleAssignment.ps1`. `Remove-LabResource.ps1` stops with `[ERROR] ... lacks User.ReadWrite.All` and exit 1 before it deletes anything. Run it in PowerShell 7 on your own machine, or delete the four lab users and three groups in the Portal (**Microsoft Entra ID** > **Users**, then **Groups**: select them and choose **Delete**).

### "[ERROR] This script needs its Microsoft Graph modules at one version"

**Cause**: Every Microsoft Graph module requires `Microsoft.Graph.Authentication` at exactly its own version, and a PowerShell session loads only one version of it. Without `-RequiredVersion`, `Install-Module Microsoft.Graph.Users` installs the newest version from the PowerShell Gallery, which in Cloud Shell can be newer than the preinstalled `Microsoft.Graph.Groups` and `Microsoft.Graph.Identity.DirectoryManagement`. The scripts check this before they import anything (issue #375); without the check, the import stops with `Could not load file or assembly 'Microsoft.Graph.Authentication, Version=...' ... Assembly with same name is already loaded`.
**Solution**:

1.  Run the `Install-Module <module> -RequiredVersion <version> -Scope CurrentUser` lines the script printed. They install the modules it names at the version the other Graph modules share.
2.  If the script says this session has already loaded `Microsoft.Graph.Authentication`, you can instead start a new PowerShell session (in Cloud Shell, type `pwsh`, which keeps your files) and run the script there.
3.  Re-run the script.

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

**SkyCraft no longer creates it.** Since issue #184, lab 5.2's backup policy keeps its snapshots
in its own tagged group, `platform-skycraft-swc-rpc1-rg`, which lab 5.2's teardown deletes whole
and the cycle sweep asserts absent. Only a `SkyCraft-Daily-Prod` policy created before that fix
still writes here, and `Deploy-Bicep.ps1` repoints such a policy on its next run.

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

### `[STOP] leftovers: could not check the N guarded name(s)`

**The preflight could not list what it guards against, so it does not know whether the names are
free.** The leftovers check lists soft-deleted key vaults and the resources holding the names the
run needs. When that listing fails - a 403, throttling, a transient ARM error - the check stops the
run (exit code 3) instead of reporting the names clear: a check that failed is not "clear"
([#290](https://github.com/mbiszczanik/skycraft/issues/290)).

Read the error after the colon, fix its cause (sign in again, check the identity can read the
subscription, or wait out the throttling), and run `Invoke-LabCycle.ps1` again. Nothing was deployed
or deleted. `Remove-LabCycle.ps1` treats its end-of-cycle checks the same way: a `[FAIL] Could not
check whether ...` line is a failed assertion, counted in its exit code, not a pass.

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
[#105](https://github.com/mbiszczanik/skycraft/issues/105) for Lab 5.2's. Every lab script now
ends through `Exit-Lab` from `tools/LabCommon.psm1`
([#257](https://github.com/mbiszczanik/skycraft/issues/257)), and
`tests/Exit-Code-Propagation.Tests.ps1` fails a lab script that does not.

Two things make this visible if it recurs:

- A lab script returns its exit code (`0`, or `1` when anything failed) whichever way it is
  started. PowerShell discards the `exit` of a script that declares `#Requires -Modules` and runs
  as `pwsh -File`, so `Exit-Lab` also calls `$Host.SetShouldExit` when the script is the entry
  point of such a process; at a prompt, under `-Command` and inside `tools/Invoke-LabScript.ps1`
  (the lab cycle's launcher) it is a plain `exit`. A run that reports 0 after printing `[FAIL]`
  means a script that does not end through `Exit-Lab` - the suite above should have failed first.
- The per-step transcripts under `tools/lab-cycle-logs/` hold exactly what each script printed. Read
  the transcript before believing the status.

> [!WARNING]
> **Treat a transcript as a secret.** Nothing in it is redacted: it carries Az error streams and the
> deployment parameter values each script echoes, and a deployment output can contain a connection
> string or an access key. `.gitignore` keeps the whole `tools/lab-cycle-logs/` directory out of
> history. Read a transcript before pasting it into an issue or a chat.

### A phase is `Failed(Test)` and the labs below it were not skipped

**This is intended** ([#259](https://github.com/mbiszczanik/skycraft/issues/259)). The lab deployed,
and then its own `Test-Lab.ps1` failed a check. Everything the dependent labs build on was created,
so the failure does not block them. A validator killed at its limit is `Failed(Test,Timeout)` and
is treated the same way. A failed **Deploy** or **PostDeploy** step is plain `Failed` (or
`Failed(Timeout)`), and that one does skip every lab below it.

Both kinds count towards the exit code. Read `tools/lab-cycle-logs/<phase>.test.log` — the report's
Transcript column points at it — for the check that failed.

**`-Resume` re-runs the failed phase whole, deploy included, and everything below it**, even the
labs that succeeded. Re-deploying a lab can undo what the labs below applied on top of it — Lab 2.1
re-declares its subnets without the NSGs and service endpoints Lab 2.2 attached, and Lab 4.1 resets
the network rules Lab 4.4 set — so a success recorded before the re-deploy no longer describes the
subscription. A resume re-runs every phase with a dependency it processes again, all the way down.
