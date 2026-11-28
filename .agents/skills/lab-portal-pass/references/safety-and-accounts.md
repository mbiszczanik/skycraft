# Safety and accounts

## Accounts per lab type

| Labs | Tenant | Account | Why |
|---|---|---|---|
| Entra-only (1.1) | the test tenant (azureflame) | its admin account | the work-tenant account with Entra write is not used in the browser (too much privilege) |
| Role assignments (1.2) | subscription tenant | subscription owner | lab users must live in the subscription's tenant; with test-tenant users, walk the wizard only up to **Select members** (#325 plan) |
| Subscription labs (1.3 onward) | subscription tenant | subscription owner (eit) | owns RBAC, policies, locks, budgets |

- Open `https://portal.azure.com/<tenant-domain-or-id>` to get that tenant's account picker. The user picks the account and completes MFA; never click an account tile or type credentials.
- Confirm the account and directory in the Portal's top-right corner and the **Subscription ID** on a resource group's Overview before the first create of each lab.

## Guards before every write

- `az account show --subscription <id> --query "{sub:id,user:user.name}"` before each batch of creates or deletes; abort on mismatch.
- Before deleting anything, look at it (`az group show`, `az resource list -g`, `az lock list`).
- **Before the agent relaxes a subscription-wide setting for a check (policy enforcement, a lock), it shall walk the check up to its last read-only step and confirm the setting is what blocks it.**
  On 2026-10-27 three Lab 1.3 assignments were set to DoNotEnforce for 6 minutes; the ACI wizard then offered the existing workspace, so none was needed.
- Delete only what the guide's own steps delete, plus cleanup the user approved per lab. Order for governance objects: locks, then policy assignments, budgets, alerts, action groups. Re-read the state in a separate call afterwards (ARM lists lag).
- Lab cleanup scripts may delete shared resource groups (Lab 1.2's deletes all three). Read a script's targets before proposing it; on a live estate, propose targeted `az` deletes instead.
- Policies at subscription scope (Lab 1.3's deny and allowed-locations) affect other sessions and lab cycles: confirm exclusivity before assigning, and say in the report while they stay active.
- Irreversible clicks on live resources (e.g. confirming a locked resource group's deletion to observe the error) need the user's explicit yes, and the protecting lock re-verified in ARM immediately before the click.
- **If** a Portal delete opens a box that offers to override a lock (*Delete confirmation*: **Attempt override of delete lock**, "the resource will be permanently deleted"), **then the agent shall** leave it unticked, screenshot it and choose **Go back**. Seen on a blob container on 2026-10-25; whether a resource group delete offers it after the typed confirmation is not known, so a locked resource group delete is never confirmed without the user.
- **If** a setting cannot be undone once set (Backup vault soft delete `AlwaysOn`, immutability), **then the agent shall** test the alternative on a temporary resource with its own name before it changes the lab's resource, and delete the temporary one afterwards (Module 5: `New-AzDataProtectionBackupVault -SoftDeleteState Off` was proven on a throwaway vault before the lab's vault was replaced).

## Steps the agent does not do

Known before the walk, so they are planned, not discovered:

| Step kind | Why | What the agent prepares |
|---|---|---|
| Sign-in, MFA, passwords | the user's credentials | the URL or terminal command for the user's shell |
| Rotate or show access keys, generate SAS tokens, connection strings | the agent's permission mode may refuse secret writes and reads | the exact Portal path or Az PowerShell command; the expected result to check |
| Grant a role to the agent's own account (e.g. Storage Blob Data Contributor) | the agent's permission mode may refuse self permission grants | the role, scope and assignee as a Portal path |
| Upload a file through a Portal file picker | the picker is a native OS dialog the agent cannot reach | the file itself in the scratchpad, with its path |
| Mount a share, connect from the user's machine | runs on the user's machine | the command and the expected output |
| An Az PowerShell block that needs Microsoft Graph (`Get-AzADUser -SignedIn`, `Get-AzRoleAssignment -ObjectId`) | the process-scoped context has no Graph token, and `Connect-AzAccount -MicrosoftGraphAccessToken` with an az CLI token still failed on 2026-10-25 | the block and the user's `Connect-AzAccount -AuthScope MicrosoftGraphEndpointResourceId` line |
| A Cloud Shell Bash block that needs no Microsoft Graph (`az` on a VM extension, a resource, a tag) | not a user step: Cloud Shell opens on the existing storage, the agent switches to Bash (a Portal modal), checks the subscription id first and types the block (2026-11-03, #369: exit 0 in about 5 minutes) | the block and the expected result; creating the storage on first use stays a user step |

List these per lab in step 1 of the workflow, mark them `NA (user step)` while walking, and give the user one batch per module. After the user has done them, re-check the Expected Results and update the rows.

## Cost at the end of every working day

Before stopping, list what bills while idle (`az resource list --subscription <id> --query "[?type=='Microsoft.Web/serverFarms' || type=='Microsoft.App/containerApps' || type=='Microsoft.Compute/virtualMachines' || type=='Microsoft.Network/bastionHosts' || type=='Microsoft.Network/applicationGateways' || type=='Microsoft.ContainerInstance/containerGroups'].{n:name,t:type}" -o table`, plus VM power states) and tell the user what stays running overnight, with a stop/delete proposal. An App Service plan left from Module 3 was billed overnight once.

- **The pass shall** report cost from Cost Management at the end of each module, not an estimate. Module reports once said "cents per day" while 8 days cost 18.57 EUR (App Service 11.56). Query (read-only; data lags about a day):
  `az rest --method post --headers "Content-Type=application/json" --url "https://management.azure.com/subscriptions/<id>/providers/Microsoft.CostManagement/query?api-version=2023-11-01" --body '{"type":"ActualCost","timeframe":"Custom","timePeriod":{"from":"<start>T00:00:00Z","to":"<end>T23:59:59Z"},"dataset":{"granularity":"None","aggregation":{"c":{"name":"Cost","function":"Sum"}},"grouping":[{"type":"Dimension","name":"ServiceName"}]}}' --query properties.rows -o tsv`
- **While** no budget alert exists on the subscription (`az consumption budget list --subscription <id>`), **the agent shall** report the last week's cost at the start of each session as well.

## Sending and inviting

- Guest invitations send real email: uncheck **Send invite message** unless the user says otherwise; record it as a deviation.
- Budget alert recipients receive real email: use the subscription owner's address and lab fictional addresses only.

## Test-Lab recipes

- **Entra labs (Graph):** the user runs the command in an interactive terminal and signs in when
  prompted. Use their actual shell, not an assumed chat `!` escape:
  - bash: `SKYCRAFT_GRAPH_TENANT_ID=<tenant-id> pwsh -NoProfile -File '<scratchpad>/<commit>/<lab>/scripts/Test-Lab.ps1'; echo "EXIT=$?"`
  - PowerShell: `$env:SKYCRAFT_GRAPH_TENANT_ID='<tenant-id>'; pwsh -NoProfile -File '<scratchpad>/<commit>/<lab>/scripts/Test-Lab.ps1'; "EXIT=$LASTEXITCODE"`
  If the environment variable was already set, the user shall restore its prior value afterwards;
  otherwise they shall remove it.
- **ARM labs:** run in-session with an az CLI token, scoped to the process so no saved context is touched:
  ```powershell
  $inner = @"
  `$tok = az account get-access-token --subscription <sub-id> --resource https://management.azure.com/ --query accessToken -o tsv
  Connect-AzAccount -AccessToken `$tok -AccountId '<owner-account>' -TenantId <tenant-id> -Subscription <sub-id> -Scope Process | Out-Null
  & '<scratchpad>/<commit>/<lab>/scripts/Test-Lab.ps1'
  "@
  pwsh -NoProfile -NonInteractive -Command $inner 2>&1 | Out-String -Width 200; "PROCESS_EXIT=$LASTEXITCODE"
  ```
- If the az CLI token needs MFA (AADSTS50078), ask the user to sign in again; do not fall back to another identity.
