# Lab 5.2: Business Continuity & Disaster Recovery (2.5 hours)

## 🎯 Learning Objectives

By completing this lab, you will:

- Deploy an **Azure Recovery Services Vault (RSV)**
- Configure **Backup Policies** for different SLA requirements
- Implement **Azure VM Backup** for production workloads
- Give Azure Backup access to the **key vault** of a VM encrypted with Azure Disk Encryption
- Protect blobs with a policy that combines **operational** and **vaulted** backup
- Perform a **File-Level Recovery (FLR)** from a backup snapshot
- Understand the difference between **LRS** and **GRS** for backup data
- Understand **Soft Delete** for protected items (and why Azure now enforces it)

---

## 🏗️ Architecture Overview

[Description]: Recovery Services Vault stores VM snapshots. Backup Vault stores Blob/Disk backups. Site Recovery replicates the VM to a secondary region (Norway East).

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="images/lab-5.2-architecture.dark.svg">
  <source media="(prefers-color-scheme: light)" srcset="images/lab-5.2-architecture.svg">
  <img src="images/lab-5.2-architecture.svg" width="100%" alt="Lab 5.2 architecture: backup vaults and site recovery">
</picture>

---

## 📋 Real-World Scenario

**Situation**: A catastrophic failure hits the primary region. Not only are VMs down, but data corruption has spread. Malfurion needs a comprehensive strategy: VM restoration for standard failures, Blob backup for game assets, and a "red button" full-region failover for disaster scenarios.

**Your Task**: Implement a multi-layered BCDR strategy:

1. **Azure Backup**: Protect VMs using RSV.
2. **Backup Vault**: Protect Blob Storage with operational and vaulted backups.
3. **Site Recovery**: Enable replication to Norway East for the production server.

---

## ⏱️ Estimated Time: 2.5 hours

- **Section 1**: Backup & Recovery Concepts (15 min)
- **Section 2**: Recovery Services Vault & VM Backup (30 min)
- **Section 3**: Backup Vault & Blob Backup (30 min)
- **Section 4**: Azure Site Recovery & Cross-Region (45 min)
- **Section 5**: Reports & Alerts (15 min)
- **Section 6**: Recovery Simulation (15 min)

---

## ✅ Prerequisites

Before starting this lab:

- [ ] Completed **Lab 5.1: Azure Monitor** (`platform-skycraft-swc-law` must exist - both vaults send their diagnostics to it, and `Deploy-Bicep.ps1` stops if the workspace is missing)
- [ ] Completed **Lab 3.2: Virtual Machines** (`dev-skycraft-swc-auth-vm` in `dev-skycraft-swc-rg` is the VM the lab protects; without it the deployment script skips VM backup with a warning). Lab 3.2 encrypts this VM with Azure Disk Encryption, using the key vault `dev-skycraft-swc-kv` with the RBAC permission model, so Step 5.2.3 first gives Azure Backup access to that vault. `dev-skycraft-swc-world-vm` is not encrypted: Step 5.2.6 and Step 5.2.10 use it
- [ ] Completed **Lab 4.1: Storage Accounts** with the production account (`prodskycraftswcsa` in `prod-skycraft-swc-rg` is the blob backup datasource - run 4.1 with `-All`, the dev-only cycle does not create it)
- [ ] Completed **Lab 4.2: Blob Storage** (the containers in `prodskycraftswcsa`: vaulted blob backup needs at least one container)
- [ ] Resource group `platform-skycraft-swc-rg` exists (Lab 1.2)
- [ ] **Section 4 only** (portal, not automated): quota for 2 vCPUs in **Norway East** for the Site Recovery test failover

The first five are what the scripts check: `scripts/Deploy-Bicep.ps1` stops on a missing resource group or workspace and only warns about the VM at step [7/7], after the deployment; `scripts/New-LabBlobBackup.ps1` stops on a missing storage account and on an account without a container. The shortest chain that also satisfies the gates of the labs it runs is 1.2 → 2.1 → 2.3 → 3.2 (dev, needs `~/.ssh/skycraft-dev.pub`) → 4.1 `-All` → 4.2 → 5.1 → 5.2 (see `tools/lab-cycle-manifest.psd1`).

Both scripts also need PowerShell 7 with Az.Accounts, Az.Resources, Az.RecoveryServices, Az.DataProtection, Az.Compute, Az.OperationalInsights and Az.Storage, a signed-in `Connect-AzAccount` context, permission to register the `Microsoft.RecoveryServices` and `Microsoft.DataProtection` resource providers (`Deploy-Bicep.ps1` registers them if needed), and **Owner** or **User Access Administrator** on `prodskycraftswcsa` (`New-LabBlobBackup.ps1` assigns the Backup Vault identity two roles there) and on `dev-skycraft-swc-kv` (`Deploy-Bicep.ps1` assigns the Backup Management Service app a role there). To find that app, `Deploy-Bicep.ps1`, `Test-Lab.ps1` and `Remove-LabResource.ps1` need a Microsoft Graph token: if they fail with `MicrosoftGraphEndpointResourceId`, see [TROUBLESHOOTING.md](../../TROUBLESHOOTING.md), or pass the app's object id with `-BackupManagementServiceObjectId` (a session that has Microsoft Graph gives it: `(Get-AzADServicePrincipal -ApplicationId 262044b1-e2ce-469f-a196-69ab7ada62d3).Id`). If Lab 4.1 had to use another name than `prodskycraftswcsa` (storage account names are unique across Azure), pass it to `New-LabBlobBackup.ps1`, `Test-Lab.ps1` and `Remove-LabResource.ps1` as `-ProdSaName`.

---

## 📖 Section 1: Backup & Recovery Concepts (15 min)

### What is Azure Backup?

**Azure Backup** is a cost-effective, secure, one-click backup solution that's scalable based on your backup storage needs. It protects diverse workloads like VMs, SQL databases, SAP HANA, and Azure Files.

### Recovery Services Vault (RSV)

An **RSV** is a storage entity in Azure that houses data. The data is typically copies of data, or configuration information for virtual machines, workloads, servers, or workstations.

### Backup Redundancy

Just like storage accounts, vaults support redundancy:

- **LRS (Locally Redundant)**: Protects against rack and drive failures.
- **GRS (Geo Redundant)**: Protects against regional outages.
- **CRR (Cross Region Restore)**: Allows you to restore data in the secondary region even if the primary region is up.

---

## 📖 Section 2: Recovery Services Vault & VM Backup (30 min)

### Step 5.2.1: Create the Vault

1. Navigate to **Azure Portal** → Search for **Recovery Services vaults**.
2. Click **+ Create**.
3. Fill in the details:

| Field          | Value                       |
| :------------- | :-------------------------- |
| Subscription   | [Your Subscription]         |
| Resource Group | `platform-skycraft-swc-rg`  |
| Vault Name     | `platform-skycraft-swc-rsv` |
| Region         | **Sweden Central**          |

4. Click **Review + Create** → **Create**.

> [!IMPORTANT]
> Change the **Storage Replication Type** immediately after creation if you want to use LRS (to save cost) before any backups are performed: go to **Properties** → **Backup Configuration** → **Update**. The Bicep path (`Deploy-Bicep.ps1`) declares LRS at creation through the AVM vault module's `redundancySettings`. Soft delete is **not** configurable: Azure Backup "secure by default" creates every Recovery Services Vault with `AlwaysON` soft delete and a 14-day retention (see `ARCHITECTURE.md` §1). Cleanup still works in one pass, because Azure allows deleting a vault that holds only soft-deleted items.

**Preview - the AVM module call the Bicep path makes** (`bicep/main.bicep`; versions pinned in `docs/bicep-standards.md` §4.4):

```bicep
module modRecoveryServicesVault 'br/public:avm/res/recovery-services/vault:0.13.0' = {
  name: 'bcdr-rsv-deployment'
  scope: resourceGroup('platform-skycraft-swc-rg')
  params: {
    name: 'platform-skycraft-swc-rsv'
    publicNetworkAccess: 'Enabled'                             // module default: Disabled
    // softDeleteSettings deliberately not set - Azure enforces AlwaysON soft delete
    redundancySettings: { standardTierStorageRedundancy: 'LocallyRedundant' }
    diagnosticSettings: [ { name: 'rsv-backup-reports-diag', workspaceResourceId: parWorkspaceId, ... } ]
    ...
  }
}
```

The Backup Vault uses `avm/res/data-protection/backup-vault:0.13.2` the same way; its diagnostic setting is the one resource without an AVM parameter and lives in `bicep/modules/backup-vault-diagnostics.bicep`. Backup policies stay in `Deploy-Bicep.ps1` (`docs/bicep-standards.md` §10.4).

**Expected Result**: Vault `platform-skycraft-swc-rsv` is deployed.

---

### Step 5.2.2: Create a Production Policy

Azure Backup keeps a VM's instant-restore snapshots in a resource group of their own, outside the VM's group. Left to itself, it creates `AzureBackupRG_swedencentral_1` **without tags**, and Lab 1.3's `Require-Environment-Tag-RG` assignment denies that group, so every backup fails. Create the group yourself, with the SkyCraft tags, and name it in the policy.

1. Search for **Resource groups** → **+ Create**, and create the snapshot group:

   | Field          | Value                                                                                          |
   | :------------- | :--------------------------------------------------------------------------------------------- |
   | Resource group | `platform-skycraft-swc-rpc1-rg`                                                                |
   | Region         | **Sweden Central**                                                                             |
   | Tags           | `Project` = `SkyCraft`, `Environment` = `Platform`, `CostCenter` = `MSDN`, `Owner` = your name |

   Do **not** lock this group. Azure Backup deletes expired snapshots from it, and a lock makes backups fail with `UserErrorRpCollectionLimitReached`. This is also why the snapshots do not go into `platform-skycraft-swc-rg`, which Lab 1.3 locks.

2. Inside the vault, go to **Manage** → **Backup policies**.
3. Click **+ Add** → **Azure Virtual Machine**.
4. Policy Name: `SkyCraft-Daily-Prod`.
5. Policy sub-type: **Enhanced**. Azure defaults VM deployments to Trusted Launch, and a
   Standard policy cannot protect a Trusted Launch VM — it fails with
   `UserErrorThisVMBackupIsSupportedUsingEnhancedPolicy`. The sub-type cannot be changed
   after a VM is protected, so pick it now.
6. Frequency: **Daily** at **02:00 AM**.
7. Timezone: **(UTC) Coordinated Universal Time**.
8. Instant Restore retention: **2 days** (Enhanced defaults to 7 — snapshots are billed).
9. Under **Instant restore**, fill in **Azure Backup Resource Group**: name `platform-skycraft-swc-rpc`, suffix `-rg`. Azure Backup inserts a number between the two, starting at 1, so the snapshots land in `platform-skycraft-swc-rpc1-rg`, the group from step 1.
10. Retention of daily backup point: **30 days**.
11. Click **Create**.

The Bicep path does the same: `bicep/main.bicep` creates the tagged group through `avm/res/resources/resource-group`, and `Deploy-Bicep.ps1` passes `-BackupSnapshotResourceGroup 'platform-skycraft-swc-rpc'` and `-BackupSnapshotResourceGroupSuffix '-rg'` to `New-AzRecoveryServicesBackupProtectionPolicy`. On a policy that already exists, it sets them with `Set-AzRecoveryServicesBackupProtectionPolicy`.

#### Azure PowerShell

The same group and policy from Azure Cloud Shell (PowerShell). An Enhanced policy keeps instant-restore snapshots for 7 days when it is created, so the last two commands bring that down to 2; they pass the snapshot group again so the update keeps it.

```powershell
New-AzResourceGroup -Name platform-skycraft-swc-rpc1-rg -Location swedencentral `
  -Tag @{ Project = 'SkyCraft'; Environment = 'Platform'; CostCenter = 'MSDN'; Owner = '<your name>' }

$vault   = Get-AzRecoveryServicesVault -ResourceGroupName platform-skycraft-swc-rg -Name platform-skycraft-swc-rsv
$runTime = [datetime]::SpecifyKind([datetime]'02:00:00', [System.DateTimeKind]::Utc)

$schedule = Get-AzRecoveryServicesBackupSchedulePolicyObject -WorkloadType AzureVM -BackupManagementType AzureVM -PolicySubType Enhanced -ScheduleRunFrequency Daily
$schedule.DailySchedule.ScheduleRunTimes.Clear()
$schedule.DailySchedule.ScheduleRunTimes.Add($runTime)

$retention = Get-AzRecoveryServicesBackupRetentionPolicyObject -WorkloadType AzureVM -BackupManagementType AzureVM -ScheduleRunFrequency Daily
$retention.DailySchedule.DurationCountInDays = 30
$retention.DailySchedule.RetentionTimes.Clear()
$retention.DailySchedule.RetentionTimes.Add($runTime)

New-AzRecoveryServicesBackupProtectionPolicy -Name SkyCraft-Daily-Prod -WorkloadType AzureVM -BackupManagementType AzureVM `
  -SchedulePolicy $schedule -RetentionPolicy $retention `
  -BackupSnapshotResourceGroup platform-skycraft-swc-rpc -BackupSnapshotResourceGroupSuffix '-rg' -VaultId $vault.ID

$policy = Get-AzRecoveryServicesBackupProtectionPolicy -Name SkyCraft-Daily-Prod -VaultId $vault.ID
$policy.SnapshotRetentionInDays = 2
Set-AzRecoveryServicesBackupProtectionPolicy -Policy $policy `
  -BackupSnapshotResourceGroup platform-skycraft-swc-rpc -BackupSnapshotResourceGroupSuffix '-rg' -VaultId $vault.ID
```

**Expected Result**: `platform-skycraft-swc-rpc1-rg` exists with the four SkyCraft tags and no lock, and `SkyCraft-Daily-Prod` (Enhanced) shows **Azure Backup Resource Group** `platform-skycraft-swc-rpc` / `-rg` under **Instant restore**.

---

### Step 5.2.3: Protect the Production VM

Lab 3.2 encrypted `dev-skycraft-swc-auth-vm` with **Azure Disk Encryption (ADE)**: its disk encryption key is a secret in `dev-skycraft-swc-kv`. Azure Backup backs up that key along with the disks, and it reads the key vault as the Microsoft Entra app **Backup Management Service**, not as the Recovery Services vault's identity. For a key vault with the RBAC permission model, Microsoft Learn ([Back up and restore encrypted Azure virtual machines](https://learn.microsoft.com/azure/backup/backup-azure-vms-encryption)) has you assign that app the **Key Vault Administrator** role on the vault. Without it, **Enable Backup** fails with `400198 UserErrorKeyVaultPermissionsNotConfigured`, so step 1 comes first.

> [!NOTE]
> ADE retires in September 2028, and AZ-104 lists *Configure encryption at host for Azure virtual machines* instead. The key vault step is still worth knowing: it is what Azure Backup needs for any VM whose keys live in a key vault.

1. Give Azure Backup access to the key vault:
   1. Open `dev-skycraft-swc-kv` (resource group `dev-skycraft-swc-rg`) → **Access control (IAM)** → **+ Add** → **Add role assignment**.
   2. Role: **Key Vault Administrator** → **Next**.
   3. Assign access to: **User, group, or service principal** → **+ Select members** → search for `Backup Management Service` → select it → **Select**.
   4. **Review + assign** → **Review + assign**.
   5. Wait about two minutes for the role to take effect before step 7.
2. In the vault, click **Overview** → **+ Backup**.
3. Where is your workload running? **Azure**.
4. What do you want to back up? **Virtual machine**.
5. Click **Configure Backup**.
6. Select the policy: `SkyCraft-Daily-Prod`. Select Virtual Machines: Find and select `dev-skycraft-swc-auth-vm`.
7. Click **Enable Backup**.
8. Run the first backup now instead of waiting for 02:00: **Protected items** → **Backup items** → **Azure Virtual Machine** → `dev-skycraft-swc-auth-vm` → **Backup now** → **OK**.
9. Open **Monitoring** → **Backup jobs**. The **Take Snapshot** phase finishes within minutes and gives the VM its first recovery point. The job stays **In progress** until the transfer to the vault ends. A job that turns **Failed** within seconds with `UserErrorRequestDisallowedByPolicy` means a policy refused the snapshot group: see Troubleshooting, Issue 2. **Enable Backup** failing with `UserErrorKeyVaultPermissionsNotConfigured` is Troubleshooting, Issue 3.

#### Azure CLI

```azurecli
KV=$(az keyvault show -g dev-skycraft-swc-rg -n dev-skycraft-swc-kv --query id -o tsv)
# 262044b1-e2ce-469f-a196-69ab7ada62d3 is the app id of Backup Management Service in every tenant.
az role assignment create --assignee 262044b1-e2ce-469f-a196-69ab7ada62d3 --role "Key Vault Administrator" --scope "$KV"

az backup protection enable-for-vm -g platform-skycraft-swc-rg -v platform-skycraft-swc-rsv \
  --vm $(az vm show -g dev-skycraft-swc-rg -n dev-skycraft-swc-auth-vm --query id -o tsv) --policy-name SkyCraft-Daily-Prod
```

#### Azure PowerShell

```powershell
$kv = Get-AzKeyVault -ResourceGroupName dev-skycraft-swc-rg -VaultName dev-skycraft-swc-kv
New-AzRoleAssignment -ApplicationId 262044b1-e2ce-469f-a196-69ab7ada62d3 -RoleDefinitionName 'Key Vault Administrator' -Scope $kv.ResourceId

$vault  = Get-AzRecoveryServicesVault -ResourceGroupName platform-skycraft-swc-rg -Name platform-skycraft-swc-rsv
$policy = Get-AzRecoveryServicesBackupProtectionPolicy -Name SkyCraft-Daily-Prod -VaultId $vault.ID
Enable-AzRecoveryServicesBackupProtection -ResourceGroupName dev-skycraft-swc-rg -Name dev-skycraft-swc-auth-vm -Policy $policy -VaultId $vault.ID
```

`New-AzRoleAssignment` looks the app up in Microsoft Graph. If it fails with `MicrosoftGraphEndpointResourceId`, see [TROUBLESHOOTING.md](../../TROUBLESHOOTING.md); Azure Cloud Shell has the Graph token it needs.

`Deploy-Bicep.ps1` assigns the role itself when the VM is ADE-encrypted (it finds the vault from the VM's encryption settings), then enables protection, and triggers this backup whenever the VM has no recovery point yet; it fails if the job fails. `Test-Lab.ps1` checks the role assignment and fails if the latest backup job of the VM failed.

**Expected Result**: `dev-skycraft-swc-kv` → **Access control (IAM)** → **Role assignments** lists **Backup Management Service** with **Key Vault Administrator**, and `dev-skycraft-swc-auth-vm` is listed under **Backup items** with a backup job **In progress** or **Completed**.

> [!TIP]
> The first backup is an **Initial Replica** (full backup). Subsequent backups are **Incrementals** (only changed blocks), making them faster and cheaper.

---

## 📖 Section 3: Backup Vault & Blob Backup (30 min)

### Step 5.2.4: Deploy Backup Vault

**Backup Vaults** are newer entities used for Azure Blobs, Azure Disks, and PostgreSQL. They are distinct from Recovery Services Vaults.

1. Search for **Backup vaults**.
2. Click **+ Create**.
3. Resource Group: `platform-skycraft-swc-rg`
4. Name: `platform-skycraft-swc-bv`
5. Region: **Sweden Central**
6. Backup Storage Redundancy: **Locally-redundant (LRS)**
7. Click **Review + create** → **Create**.

### Step 5.2.5: Configure Blob Backup

Create the blob backup **policy**, then grant the vault identity access and protect the storage account.

Blob backup has two tiers, and one policy can carry both ([Overview of Azure Blob backup](https://learn.microsoft.com/azure/backup/blob-backup-overview)):

| Tier | Where the backup is | Schedule | Restores to |
| :--- | :--- | :--- | :--- |
| **Operational** | In the source account itself (point-in-time restore, blob soft delete, versioning, change feed), nothing is copied to the vault | Continuous, none to set | The same account |
| **Vaulted** | Copied to the Backup vault: an offsite copy that survives the account | Daily or weekly | A different account |

A new policy cannot be operational only: Microsoft Learn says vaulted backup is selected by default in a new policy and cannot be turned off. SkyCraft keeps the vaulted part small: one backup a day, kept 7 days. Vaulted backup is billed, per protected instance and per GB stored in the vault (see [Azure Backup pricing](https://azure.microsoft.com/pricing/details/backup/)); the lab's containers hold little data.

**a. Create the blob backup policy**

1. Open `platform-skycraft-swc-bv` (your new Backup vault) → **Manage** → **Backup policies** → **+ Add**.
2. Datasource type: **Azure Blobs (Azure Storage)** → **Continue**.
3. **Basics**: Policy name `SkyCraft-Blob-Policy`; vault `platform-skycraft-swc-bv` → **Next**.
4. **Schedule + retention**:
   - **Operational backups**: checked. Edit its **Default** retention rule to **30 days**.
   - **Vaulted backups**: checked, and greyed out: it cannot be cleared. Backup frequency **Daily**, time **3:30 AM**, timezone **(UTC) Coordinated Universal Time**. Edit its **Default** retention rule (90 days when the policy is new) to **7 days**.
5. **Review + create** → **Create**.

`Deploy-Bicep.ps1` creates the same policy through the Data Protection REST API, with the request body Microsoft Learn shows for an operational plus vaulted policy ([Create Azure Data Protection backup policies for blobs using REST API](https://learn.microsoft.com/azure/backup/backup-azure-dataprotection-use-rest-api-create-update-blob-policy)): two **Default** retention rules (`OperationalStore` 30 days, `VaultStore` 7 days) and a daily `VaultStore` backup rule. Azure does not change a blob policy in place, so a `SkyCraft-Blob-Policy` left by an earlier run of this lab, operational only, is reported as an error: see Troubleshooting, Issue 4.

**b. Grant the Backup Vault identity access to the storage account**

The Backup Vault uses its **system-assigned managed identity** to read and protect blob data. Assign these two roles to that identity, scoped to `prodskycraftswcsa`:

| Role                                   | Why                                                                       |
| :------------------------------------- | :------------------------------------------------------------------------ |
| **Storage Account Backup Contributor** | Lets the vault configure and manage operational backup on the account.    |
| **Storage Blob Data Owner**            | Lets the vault access blob data for protection.                           |

Assign one role at a time. The wizard's **Review + assign** button first opens its review tab; select it there again to assign the role.

1. Navigate to `prodskycraftswcsa` (resource group `prod-skycraft-swc-rg`) → **Access control (IAM)** → **+ Add** → **Add role assignment**.
2. **Storage Account Backup Contributor** → **Next** → Assign access to: **Managed identity** → **+ Select members** → choose the Backup vault type in the pane's managed identity list → `platform-skycraft-swc-bv` → **Select** → **Review + assign** → **Review + assign**.
3. **+ Add** → **Add role assignment** → **Storage Blob Data Owner** → **Next** → Assign access to: **Managed identity** → **+ Select members** → choose the Backup vault type in the pane's managed identity list → `platform-skycraft-swc-bv` → **Select** → **Review + assign** → **Review + assign**.

> [!NOTE]
> Allow ~5 minutes for the role assignments to propagate before the next step, or it may fail with `UserErrorMissingRequiredPermissions`.

**c. Configure backup (create the backup instance)**

1. Open `platform-skycraft-swc-bv` → **+ Backup**.
2. Datasource type: **Azure Blobs (Azure Storage)**.
3. Backup policy: `SkyCraft-Blob-Policy`.
4. **Datasources**: select the storage account `prodskycraftswcsa`. Because the policy is vaulted too, choose which containers the vault copies: under **Selected containers**, click **Change** → **Backup all present containers** → **Select**. Do not pick **Backup all present and future containers**: Microsoft Learn says that choice is permanent. A storage account without a container cannot be configured for vaulted backup, which is why Lab 4.2 is a prerequisite.
5. Wait until the **Backup readiness** column shows success, then open **Review + configure** and start the configuration to create the **backup instance** that protects the account.

Configuring vaulted backup turns on blob versioning and the change feed in the account and adds an object replication rule there (**Data management** → **Object replication**). Operational backup adds point-in-time restore, blob soft delete and a delete lock owned by Azure Backup. Removing the backup instance removes the object replication rule again.

> [!TIP]
> The automation script `New-LabBlobBackup.ps1` performs steps **b** and **c** for you (role assignments + backup instance). It lists the account's containers and passes all of them to `New-AzDataProtectionBackupConfigurationClientObject -VaultedBackupContainer`; the portal flow above is the manual equivalent.

**Expected Result**: `SkyCraft-Blob-Policy` lists an operational retention of 30 days and a daily vaulted backup kept 7 days, and `platform-skycraft-swc-bv` → **Backup instances** lists `prodskycraftswcsa` as **Protection configured**.

---

## 📖 Section 4: Azure Site Recovery & Cross-Region (45 min)

### Step 5.2.6: Enable Replication

Replicate `dev-skycraft-swc-world-vm`, the VM Lab 3.2 leaves unencrypted.

> [!NOTE]
> For a VM encrypted with Azure Disk Encryption, such as `dev-skycraft-swc-auth-vm`, the replication wizard asks for more ([Replicate Azure Disk Encryption-enabled virtual machines to another Azure region](https://learn.microsoft.com/azure/site-recovery/azure-to-azure-how-to-enable-replication-ade-vms)): under **Encryption settings** the wizard creates a disk encryption key vault in the target region (its name ends in `asr`) and copies the VM's keys and secrets into it, and with an RBAC key vault you, the user enabling replication, need **Key Vault Administrator** on the source vault and on the target vault. The lab skips that by replicating the unencrypted VM.

1. Navigate to your VM: `dev-skycraft-swc-world-vm`.
2. Access **Disaster recovery** in the left menu.
3. Target region: **Norway East** (or another available European region).
4. Click **Advanced settings** to review resources (ASR creates a cache storage account and target resources).
5. Click **Refiew + Start replication**.

> [!NOTE]
> Initial synchronization can take 15-30 minutes depending on disk size.

### Step 5.2.7: Perform Test Failover

1. Once status is **Protected**, click **Test Failover**.
2. Recovery Point: **Latest processed**.
3. Azure Virtual Network: Select the created ASR VNet in the target region.
4. Click **Test Failover**.
5. Once complete, verify the new VM exists in the target region.
6. Click **Cleanup test failover** to remove temporary resources.

---

## 📖 Section 5: Reports & Alerts (15 min)

### Step 5.2.8: Configure Backup Reports

Backup reports are built from **diagnostic settings** on the vaults: each vault streams its backup logs to a Log Analytics workspace, and Backup center renders the workbooks from that data. Create one diagnostic setting per vault, with the names below - `scripts/Test-Lab.ps1` looks them up by name.

> [!NOTE]
> If `Deploy-Bicep.ps1` has already run, both settings exist: open them with **Edit setting** instead of adding new ones. Azure refuses a second setting that sends an overlapping category to the same workspace. A `rsv-backup-reports-diag` left by an older version of this lab still carries the legacy `AzureBackupReport` category - uncheck it and check the two missing ones; re-running `Deploy-Bicep.ps1` replaces the category list the same way.

**a. Recovery Services Vault → `rsv-backup-reports-diag`**

1. Open `platform-skycraft-swc-rsv` → **Monitoring** → **Diagnostic settings** → **+ Add diagnostic setting**.
2. Diagnostic setting name: `rsv-backup-reports-diag`
3. Under **Logs**:
   - Check **Core Azure Backup Data** (`CoreAzureBackup`)
   - Check **Addon Azure Backup Job Data** (`AddonAzureBackupJobs`)
   - Check **Addon Azure Backup Policy Data** (`AddonAzureBackupPolicy`)
   - Check **Addon Azure Backup Storage Data** (`AddonAzureBackupStorage`)
   - Check **Addon Azure Backup Protected Instance Data** (`AddonAzureBackupProtectedInstance`)
   - Check **Azure Backup Operations** (`AzureBackupOperations`)
   - Leave **Azure Backup Reporting Data** (`AzureBackupReport`) unchecked

   Backup reports needs the six checked categories. Azure Backup Reporting Data is the legacy event: it flows only in **Azure diagnostics** mode, and with **Resource specific** selected it sends no data.
4. Check **Send to Log Analytics workspace**.
5. Log Analytics workspace: `platform-skycraft-swc-law`.
6. Destination table: select **Resource specific**.
7. Click **Save**.

**b. Backup Vault → `bv-backup-reports-diag`**

1. Open `platform-skycraft-swc-bv` → **Monitoring** → **Diagnostic settings** → **+ Add diagnostic setting**.
2. Diagnostic setting name: `bv-backup-reports-diag`
3. Under **Logs**, check **Core Azure Backup Data**, **Addon Azure Backup Job Data**, **Addon Azure Backup Policy Data** and **Addon Azure Backup Protected Instance Data** - a Backup Vault has no legacy `AzureBackupReport` event, and no `AddonAzureBackupStorage` because its storage data is already in Core and Protected Instance. Leave the **Health** metric (under **Metrics**) unchecked - Backup reports does not use it, and the Bicep path does not enable it.
4. Check **Send to Log Analytics workspace**.
5. Log Analytics workspace: `platform-skycraft-swc-law`.

   There is no **Destination table** option here: Backup Vault logs always land in resource-specific tables.
6. Click **Save**.

#### Azure CLI

```azurecli
LAW=$(az monitor log-analytics workspace show -g platform-skycraft-swc-rg -n platform-skycraft-swc-law --query id -o tsv)
RSV=$(az backup vault show -g platform-skycraft-swc-rg -n platform-skycraft-swc-rsv --query id -o tsv)
BV=$(az dataprotection backup-vault show -g platform-skycraft-swc-rg -v platform-skycraft-swc-bv --query id -o tsv)

az monitor diagnostic-settings create --name rsv-backup-reports-diag --resource "$RSV" \
  --workspace "$LAW" --export-to-resource-specific true \
  --logs '[{"category":"CoreAzureBackup","enabled":true},{"category":"AddonAzureBackupJobs","enabled":true},{"category":"AddonAzureBackupPolicy","enabled":true},{"category":"AddonAzureBackupStorage","enabled":true},{"category":"AddonAzureBackupProtectedInstance","enabled":true},{"category":"AzureBackupOperations","enabled":true}]'

az monitor diagnostic-settings create --name bv-backup-reports-diag --resource "$BV" \
  --workspace "$LAW" --export-to-resource-specific true \
  --logs '[{"category":"CoreAzureBackup","enabled":true},{"category":"AddonAzureBackupJobs","enabled":true},{"category":"AddonAzureBackupPolicy","enabled":true},{"category":"AddonAzureBackupProtectedInstance","enabled":true}]'
```

#### Azure PowerShell

```powershell
$law = Get-AzOperationalInsightsWorkspace -ResourceGroupName platform-skycraft-swc-rg -Name platform-skycraft-swc-law
$rsv = Get-AzRecoveryServicesVault -ResourceGroupName platform-skycraft-swc-rg -Name platform-skycraft-swc-rsv
$bv  = Get-AzDataProtectionBackupVault -ResourceGroupName platform-skycraft-swc-rg -VaultName platform-skycraft-swc-bv

$core = 'CoreAzureBackup', 'AddonAzureBackupJobs', 'AddonAzureBackupPolicy', 'AddonAzureBackupProtectedInstance'
$rsvLogs = ($core + 'AddonAzureBackupStorage', 'AzureBackupOperations') | ForEach-Object { New-AzDiagnosticSettingLogSettingsObject -Category $_ -Enabled $true }
$bvLogs  = $core | ForEach-Object { New-AzDiagnosticSettingLogSettingsObject -Category $_ -Enabled $true }

New-AzDiagnosticSetting -Name rsv-backup-reports-diag -ResourceId $rsv.ID -WorkspaceId $law.ResourceId -LogAnalyticsDestinationType Dedicated -Log $rsvLogs
New-AzDiagnosticSetting -Name bv-backup-reports-diag  -ResourceId $bv.Id  -WorkspaceId $law.ResourceId -LogAnalyticsDestinationType Dedicated -Log $bvLogs
```

**c. Read the reports**

1. Navigate to **Backup center** → **Backup reports**.
2. Select `platform-skycraft-swc-law` as the workspace.
3. View the **Backup Instances** report to see protection status across both vaults. Data appears up to 24 hours after the settings are created.

**Expected Result**: Each vault lists one diagnostic setting targeting `platform-skycraft-swc-law`; `Test-Lab.ps1` reports both `[Diagnostic Settings]` checks as PASS.

### Step 5.2.9: Review Alerts

1. In **Backup center**, click **Alerts**.
2. Verify if any Critical or Warning alerts exist. After a fresh deployment expect one built-in alert on `platform-skycraft-swc-rsv`:
   - **Modify policy with shorter retention** (0 - Critical) - raised because `Deploy-Bicep.ps1` shortens instant-restore retention to 2 days after creating the Enhanced policy. Expected; it is a security alert about the change, not a failure.

   A **Backup Failure** (1 - Error) alert is **not** expected. It means the VM has no recovery point; open the failed job under **Backup jobs** and see Troubleshooting, Issue 2.
3. Configure a notification rule to email `admins@skycraft.com` for Critical alerts.

---

## 📖 Section 6: Recovery Simulation (15 min)

### Step 5.2.10: File-Level Recovery

Instead of restoring the whole VM, you can mount a recovery point's disks and copy single files out of them ([Recover files from Azure virtual machine backup](https://learn.microsoft.com/azure/backup/backup-azure-restore-files-from-vm)). On a Linux VM, Azure Backup generates a Python script that connects the recovery point's disks over iSCSI and mounts their volumes under the folder you run it in; there are no drive letters.

File recovery from an encrypted VM backup is not supported: for an ADE-encrypted VM, Microsoft Learn says you restore its disks and create a VM from them to get at files and folders. So this step uses `dev-skycraft-swc-world-vm`, which Lab 3.2 leaves unencrypted, and gives it a backup of its own first.

**a. Back up the World VM with a file to find**

1. Open `dev-skycraft-swc-world-vm` → **Operations** → **Run command** → **RunShellScript**, paste the line below and click **Run**:

   ```bash
   echo "SkyCraft file recovery test, written $(date -u)" | sudo tee /home/azureuser/skycraft-flr-marker.txt
   ```

2. Protect the VM as in Step 5.2.3, steps 2-8: policy `SkyCraft-Daily-Prod`, virtual machine `dev-skycraft-swc-world-vm`, then **Backup now**. It is not encrypted, so it needs no key vault role.
3. Open **Monitoring** → **Backup jobs** and the job's details, and wait until its Take Snapshot phase has completed. The snapshot recovery point is enough for file recovery.

`Deploy-Bicep.ps1` protects only `dev-skycraft-swc-auth-vm`; this backup is a Portal step, and `Remove-LabResource.ps1` removes it with the vault's other backup items.

**b. Download the script**

1. Open `dev-skycraft-swc-world-vm` → **Backup** → **File Recovery**. The VM's entry under the vault's Backup items leads to the same pane.
2. Under **Select restore point**, select the recovery point from part a.
3. Click **Download Script**. The file name starts with the VM name and the region code, and ends in `.py`.
4. Copy the password the pane shows: the script asks for it.

**c. Run the script on the VM**

The script needs root, Python 3 and bash, and it asks to install `open-iscsi` and `lshw` if they are missing. It reaches `download.microsoft.com` on port 443 and the Recovery Services endpoint of the vault's region (`pod01-rec2.<region code>.backup.windowsazure.com`, or the `AzureBackup` service tag) on port **3260**, outbound.

1. Open an SSH session to `dev-skycraft-swc-world-vm` through Lab 2.2's Bastion (as in Step 3.2.15).
2. Put the script on the VM under its downloaded name: create the file in the SSH session and paste the script's content into it (`nano <script name>.py`), or, with a Bastion SKU that supports the native client, copy it with `scp` through `az network bastion tunnel`.
3. Run it as root, and enter the password when it asks:

   ```bash
   mkdir -p ~/flr && cd ~/flr
   sudo python3 ./<script name>.py
   ```

4. The script prints `Connection succeeded!` and then the recovery point's volumes with their mount paths, for example `.../<vm name>-<time>/Volume1` (the OS disk, ext4). Volumes it cannot mount, such as the BIOS boot partition, are listed as not mountable.
5. Browse the OS disk's volume and read the file from part a:

   ```bash
   sudo ls <Volume1 mount path>/home/azureuser/
   sudo cat <Volume1 mount path>/home/azureuser/skycraft-flr-marker.txt
   ```

**d. Close the connection**

1. In the Portal, on the **File Recovery** pane, click **Unmount Disks**.
2. On the VM, remove the mount paths the script leaves behind: `sudo python3 ./<script name>.py clean`.

An open connection makes the VM's next backup fail with `UserErrorUnableToOpenMount`, and the script's access ends by itself after 12 hours.

**Expected Result**: The script lists the recovery point's volumes as mount paths under the folder it ran in, and `skycraft-flr-marker.txt` with the text from part a is in that volume's `home/azureuser` folder. After **Unmount Disks** and `clean`, the mount paths are gone.

---

## ✅ Lab Checklist

- [ ] Vault `platform-skycraft-swc-rsv` deployed and configured (LRS/GRS)
- [ ] Backup policy `SkyCraft-Daily-Prod` created with 30-day retention, instant-restore snapshots in the tagged `platform-skycraft-swc-rpc1-rg`
- [ ] Backup Management Service holds **Key Vault Administrator** on `dev-skycraft-swc-kv`
- [ ] `dev-skycraft-swc-auth-vm` registered for backup
- [ ] Initial backup job **In progress** or **Completed**, not **Failed**
- [ ] Backup Vault `platform-skycraft-swc-bv` with `SkyCraft-Blob-Policy` (operational 30 days, vaulted daily kept 7 days) protecting `prodskycraftswcsa`
- [ ] A file restored from a recovery point of `dev-skycraft-swc-world-vm`, and the disks unmounted
- [ ] Diagnostic settings `rsv-backup-reports-diag` and `bv-backup-reports-diag` send backup logs to `platform-skycraft-swc-law`
- [ ] Detailed verification performed (see checklist)

**For detailed verification**, see [lab-checklist-5.2.md](lab-checklist-5.2.md)

---

## 🔧 Troubleshooting

### Issue 1: Deployment of Vault Fails

**Symptom**: "Resource provider not registered" error.

**Solution**:

- Ensure `Microsoft.RecoveryServices` provider is registered in your subscription.
- Navigate to **Subscription** → **Resource Providers** → Register `Microsoft.RecoveryServices`.

### Issue 2: The VM backup job fails with `UserErrorRequestDisallowedByPolicy`

**Symptom**: The backup of `dev-skycraft-swc-auth-vm` ends **Failed** within seconds with error 400211, *An invalid policy is configured on the VM which is preventing Snapshot operation*, and Backup center raises a **Backup Failure** alert. `Deploy-Bicep.ps1` and `Test-Lab.ps1` report the failed job.

**Root Cause**: The backup policy names no snapshot resource group, so Azure Backup creates `AzureBackupRG_swedencentral_1` for the restore point collection, without tags. Lab 1.3's `Require-Environment-Tag-RG` assignment denies untagged resource groups, so the snapshot never starts. The Activity Log shows the refusal as `Microsoft.Authorization/policies/deny/action` on that group. A policy created before this lab named the group (issue #184) behaves this way.

**Solution**: Give the policy a tagged snapshot group, as in Step 5.2.2:

1. Create `platform-skycraft-swc-rpc1-rg` with the SkyCraft tags (Step 5.2.2, step 1), or re-run `Deploy-Bicep.ps1`, which creates the group and updates the existing policy for you.
2. In the portal: **Backup policies** → `SkyCraft-Daily-Prod` → **Modify** → **Instant restore** → **Azure Backup Resource Group**: name `platform-skycraft-swc-rpc`, suffix `-rg` → **Update**.
3. Run **Backup now** again (Step 5.2.3, step 8).

If the job still fails with the same code, the Activity Log entry names the resource that was refused and the policy assignment that refused it. Do not delete Lab 1.3's assignments: Lab 1.3's `Test-Lab.ps1` checks them.

### Issue 3: Enable Backup fails with `UserErrorKeyVaultPermissionsNotConfigured`

**Symptom**: **Enable Backup** for `dev-skycraft-swc-auth-vm` ends with a **ConfigureBackup** job **Failed**, error `400198 UserErrorKeyVaultPermissionsNotConfigured`: *Azure Backup Service does not have sufficient permissions to Key Vault for Backup of Encrypted Virtual Machines*. `Deploy-Bicep.ps1` prints the same message at step [7/7].

**Root Cause**: Lab 3.2 encrypted the VM with Azure Disk Encryption, and its key vault `dev-skycraft-swc-kv` uses the RBAC permission model. Azure Backup reads the vault as the Backup Management Service app, which holds no role there. A role on the Recovery Services vault's own identity does not help: Microsoft Learn says VM backup uses the Backup Management Service app, not the vault's managed identity.

**Solution**:

1. Assign **Backup Management Service** the **Key Vault Administrator** role on `dev-skycraft-swc-kv` (Step 5.2.3, step 1), or re-run `Deploy-Bicep.ps1`, which assigns it.
2. Wait about two minutes, then **Enable Backup** again. A role assigned seconds before can still fail the same way: wait a few more minutes and retry.
3. If `Deploy-Bicep.ps1` cannot find the app (`MicrosoftGraphEndpointResourceId`), see [TROUBLESHOOTING.md](../../TROUBLESHOOTING.md), or pass `-BackupManagementServiceObjectId` (Prerequisites).

### Issue 4: `Deploy-Bicep.ps1` reports `SkyCraft-Blob-Policy` as operational only

**Symptom**: Step [6/7] prints `[ERROR] Policy 'SkyCraft-Blob-Policy' exists but is operational only`, and `Test-Lab.ps1` fails **Blob policy takes a daily vaulted backup, kept 7 days in the vault**.

**Root Cause**: An earlier version of this lab created an operational-only blob policy. Azure keeps existing policies working, but a new policy is always operational plus vaulted (Step 5.2.5), and Azure does not update a blob policy in place.

**Solution**: Run `Remove-LabResource.ps1` and deploy again, or delete the blob backup instance of `prodskycraftswcsa` and then the policy (**Backup policies** → `SkyCraft-Blob-Policy` → **Delete**), re-run `Deploy-Bicep.ps1` and then `New-LabBlobBackup.ps1`.

---

## 🎓 Knowledge Check

1. **What is "Soft Delete" in Recovery Services Vault?**
   <details>
     <summary>**Click to see the answer**</summary>

   **Answer**: It retains deleted backup data for 14 additional days at no cost, protecting against accidental deletion or ransomware attacks. Azure Backup now enforces it on every new Recovery Services Vault (`AlwaysON`, not disableable); the lab's cleanup script still works because Azure allows deleting a vault that holds only soft-deleted items.
   </details>

2. **Can you change the vault redundancy (LRS to GRS) after backups are taken?**
   <details>
     <summary>**Click to see the answer**</summary>

   **Answer**: No. Redundancy must be configured before the first backup is stored. To change it later, you must delete all items and start over.
   </details>

---

## 📚 Additional Resources

- [Azure Backup Overview](https://learn.microsoft.com/en-us/azure/backup/backup-overview)
- [Recovery Services Vault Documentation](https://learn.microsoft.com/en-us/azure/backup/backup-azure-recovery-services-vault-overview)
- [Azure VM Backup Tutorial](https://learn.microsoft.com/en-us/azure/backup/quick-backup-vm-portal)
- [File Recovery from Azure VM Backup](https://learn.microsoft.com/en-us/azure/backup/backup-azure-restore-files-from-vm)

---

## 📌 Module Navigation

[Lab 5.1 Azure Monitor ←](../5.1-azure-monitor/lab-guide-5.1.md) | [Next Lab: 5.3 Network Monitoring →](../5.3-network-monitoring/lab-guide-5.3.md)

---

## 📝 Lab Summary

**What You Accomplished:**

✅ Deployed a **Recovery Services Vault** for VM snapshots
✅ Deployed a **Backup Vault** for Blob Storage protection
✅ Configured backup policies for both Compute and Storage
✅ Enabled **Azure Site Recovery** to replicate Production to Norway East
✅ Successfully performed a **Test Failover** to validate BCDR strategy
✅ Configured **Backup Reports** through the `rsv-backup-reports-diag` and `bv-backup-reports-diag` diagnostic settings
✅ Explored File-Level Recovery vs Full VM Restore

**Time Spent**: ~2.5 hours

**Ready for Lab 5.3?** Next, you'll use Network Watcher to diagnose and troubleshoot connectivity issues.
