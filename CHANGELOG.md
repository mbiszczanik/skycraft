# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed

- Lab 5.2 `Deploy-Bicep.ps1` creates `SkyCraft-Daily-Prod` as an **Enhanced** backup policy and no longer reports a failed deployment as a success (#113). Azure defaults VM deployments to Trusted Launch, which a Standard policy cannot protect, so enabling VM backup failed with `UserErrorThisVMBackupIsSupportedUsingEnhancedPolicy` for every VM in the lab — and the script printed a `[WARNING]` and exited 0, so an orchestrated cycle recorded a lab whose central resource was never created. Failed policy creation and failed VM protection are now counted and exit 1. Enhanced keeps instant-restore snapshots for 7 days by default, so the script pulls that back to the 2 days the lab documents and `Test-Lab.ps1` asserts. The idempotency check no longer relies on `FriendlyName`, which Azure can return empty.
- Every automation script now sets `$Host.SetShouldExit(<code>)` immediately before a non-zero `exit`, so a failed run is visible to its caller (#104). PowerShell 7 discards `exit <code>` from a script run as `pwsh -File` when that script declares `#Requires -Modules` for a module it has to auto-import - which every `Az.*` script here does. The `exit` still ran, but the process reported **0**, so the lab cycle recorded a failed teardown as a clean one; Lab 2.1 cleanup printed `Cleanup finished with 1 failure(s)` and exited 0. The same script exits correctly when dot-called or run with `-Command`, which is why only the automated cycle was affected. Applied to 144 exit sites across 55 scripts and enforced by the new `tests/Exit-Code-Propagation.Tests.ps1`, which asserts the guard structurally and verifies that the idiom really carries the code through `pwsh -File`.
- Lab 3.2 `Deploy-Bicep.ps1` takes a `-Force` switch and no longer confirms the deployment by reading stdin (#103). Run non-interactively, the old `Read-Host` prompt read EOF, printed `Deployment cancelled.` and exited **0**, so an orchestrating chain recorded the skipped VM deployment as a success and only failed two labs later. The confirmation is now a host prompt defaulting to No instead of a stdin read: `-Force` deploys without asking, and a declined confirmation - or a session with no console to prompt on - exits **2** having deployed nothing.
- Lab 5.3 `Remove-LabResource.ps1` now cleans up everything the deployment creates, not just the connection monitor and the flow log (#106). It also removes the `NetworkWatcherAgent` extension that `Deploy-Bicep.ps1` installs on both connection monitor endpoint VMs — resolved from the monitor's own endpoints before it is deleted, skipped for a missing VM, a missing extension, or an agent not tagged `Project = SkyCraft` — and the `NWTA-*` Traffic Analytics data collection rule and endpoint Azure creates next to the Log Analytics Workspace, once no flow log with Traffic Analytics is left to feed them.

## [0.8.0] - 2026-08-29

### Added

- Pester guard `tests/Avm-Module-Pinning.Tests.ps1`: every `br/public:avm/...` reference must pin an exact semver, each AVM module must resolve to a single version repo-wide, and `bicepconfig.json` must not define registry aliases. The suite also asserts that the scan itself matched at least one `.bicep` file and one AVM declaration, so the guard cannot pass vacuously.
- `.bicepparam` parameter files for the Module 1 Bicep entry points (Labs 1.2 and 1.3).
- `.bicepparam` parameter files for the Module 2 Bicep entry points (Labs 2.1, 2.2 and 2.3).
- Lab 2.3 template outputs `outPublicDnsNameServers` (for nameserver delegation), `outDevLbId` and `outProdLbId`.
- `.bicepparam` parameter files for the Module 3 Bicep entry points (Labs 3.2, 3.3 and 3.4; Lab 3.1 already had dev/prod files).
- Lab 3.3 `bicep/acr.bicep`: a resource-group-scope entry point that deploys only the container registry, used by `Deploy-Bicep.ps1` to bootstrap the image before the orchestrator runs.
- Lab 3.4 `bicep/modules/autoscale.bicep`: the documented local fallback for autoscale settings, because `avm/res/insights/autoscale-setting` is only *Proposed*.
- `.bicepparam` parameter files for the Module 4 Bicep entry points (Labs 4.1, 4.2, 4.3 and 4.4).
- `parOwner` and the canonical `Owner` tag across Module 4, including the portal, CLI and PowerShell paths in the Lab 4.1 guide and the Lab 4.1/4.3 checklists.
- Lab 2.2 `Test-Lab.ps1` asserts the `Microsoft.Storage` service endpoint on `WorldSubnet` (the endpoint Lab 4.4 depends on) and, when Bastion is deployed, its SKU, its public IP SKU and allocation method, and the canonical tags on both (#90).
- Lab 2.3 `Test-Lab.ps1` asserts `DisableOutboundSnat` is false on every load-balancing rule, the canonical tags on both load balancers and both DNS zones, and that the `dev` and `play` A records resolve to the load balancer public IPs reserved in Lab 2.1 (#90).
- `.bicepparam` parameter files for the Module 5 Bicep entry points (Labs 5.1, 5.2 and 5.3). Their required resource-ID parameters default to well-formed placeholders under the zero subscription GUID (an empty default fails `az bicep build-params` with BCP333 against `@minLength(1)`); the deploy scripts resolve the real IDs from Azure.
- `parOwner` and the canonical `Owner` tag across Module 5.
- Lab 5.1 `bicep/modules/storage-blob-diagnostics.bicep` and Lab 5.2 `bicep/modules/backup-vault-diagnostics.bicep`: the documented local fallbacks for diagnostic settings (`avm/res/insights/diagnostic-setting` is subscription-scope only; `avm/res/data-protection/backup-vault` has no `diagnosticSettings` parameter).
- Lab 5.2 `Test-Lab.ps1` asserts that soft delete is off on the Backup Vault.
- Lab 5.1 template output `outStorageDiagnosticSettingId`; Lab 5.3 template output `outNetworkWatcherId`.

### Changed

- Bicep standards rewritten to an **AVM-first** policy (issue #62 v2): Azure Verified Modules consumed directly from `main.bicep` entry points, exact-version pinning with a repo-wide catalogue, canonical tag set (`Project`/`Environment`/`CostCenter`/`Owner`), an explicit-`dependsOn` rule, lab-friction override principle, and a documented Lab 3.1 hand-written-modules exception.
- Lint workflow now builds every `.bicepparam` file with `az bicep build-params`.
- Lint workflow now parses every `.ps1`/`.psm1`/`.psd1` with the PowerShell parser before running PSScriptAnalyzer, annotating each syntax error with its file and line. PSScriptAnalyzer's gate counts only `Severity -eq 'Error'` and reports none for a file that cannot be parsed, so a syntax error used to reach CI unnoticed unless a Pester container happened to fail on it.
- Module 1 Bicep converted to the AVM-first architecture (issue #62 v2, PR 1/6): resource groups via `avm/res/resources/resource-group`, RG-scope role assignments via `avm/res/authorization/role-assignment/rg-scope`, Lab 1.3 policy assignments called directly from `main.bicep`, and locks via the AVM `lock` parameter.
- Canonical four-tag set (`Project`/`Environment`/`CostCenter`/`Owner`) applied across Module 1: the non-canonical `Criticality` tag is dropped and the Lab 1.3 scripts take `-Owner` (default `mbiszczanik`) instead of `-AdminEmail`.
- Module 2 Bicep converted to the AVM-first architecture (issue #62 v2, PR 2/6): virtual networks, subnets and both hub-spoke peering directions via `avm/res/network/virtual-network`, public IPs via `avm/res/network/public-ip-address`, NSGs/ASGs and subnet associations via `avm/res/network/network-security-group`, `avm/res/network/application-security-group` and `avm/res/network/virtual-network/subnet`, Azure Bastion via `avm/res/network/bastion-host`, load balancers via `avm/res/network/load-balancer`, DNS via `avm/res/network/dns-zone` and `avm/res/network/private-dns-zone`.
- Module 2 resource deltas from the AVM conversion: Standard public IPs are zone-redundant (AVM default; public IPs left over from a pre-v2 run must be deleted first, because availability zones cannot be changed in place); the `AppServiceSubnet` delegation is named `Microsoft.Web/serverFarms` instead of `delegation`; outbound SNAT through the load-balancer frontend is preserved by setting `disableOutboundSnat: false` on every rule (the AVM default is `true`, which would leave the Module 3 VMs without outbound internet); spoke-subnet service endpoints are recorded without a region restriction (`locations: ["*"]`) and the AVM subnet module sets `privateEndpointNetworkPolicies: Enabled` on the subnets it re-declares.
- Canonical four-tag set (`Project`/`Environment`/`CostCenter`/`Owner`) applied across Module 2, including the portal-path tables in the lab guides and checklists; Lab 2.3 resources carry their own environment tag (DNS zones `Platform`, dev load balancer `Development`) instead of a blanket `Production`.
- Module 3 Bicep converted to the AVM-first architecture (issue #62 v2, PR 3/6): virtual machines and their NICs via `avm/res/compute/virtual-machine`, the data disk via `avm/res/compute/disk`, Key Vault via `avm/res/key-vault/vault`, Container Registry via `avm/res/container-registry/registry`, Container Instances via `avm/res/container-instance/container-group`, Container Apps via `avm/res/app/managed-environment` and `avm/res/app/container-app`, the App Service plan, web app and staging slot via `avm/res/web/serverfarm` and `avm/res/web/site`, and the Lab 3.3 resource group via `avm/res/resources/resource-group`.
- Lab 3.1 keeps its hand-written modules (that lab's learning objective) and receives the gold-path retrofit: canonical tags, `parOwner`, typed module parameters with validation decorators, and alignment with the Lab 2.1 resources (subnet delegation named `Microsoft.Web/serverFarms`, zone-redundant public IP, hub `GatewaySubnet`, explicit `disableOutboundSnat: false`).
- Lab 3.2 VM sizes moved to B-series v2: the default is `Standard_B2ls_v2` (the v1 `Standard_B1s`/`B2s`/`B2ms` are not available in Sweden Central on the lab subscription) and `Enable-Encryption.ps1` resizes 4 GB sizes to their 8 GB sibling (`B2ls_v2` to `B2s_v2`, `B2als_v2` to `B2as_v2`) for Azure Disk Encryption and back afterwards. The resize runs in place, without deallocation, because both sizes share a hardware family.
- Lab 3.2 VMs are pinned to availability zones again (Auth 1, World 2 with its data disk; `-1` lets Azure choose), and the Key Vault keeps soft delete enabled with the shortest retention (7 days) and no purge protection, because Azure no longer allows soft delete to be disabled on a new vault.
- Canonical four-tag set (`Project`/`Environment`/`CostCenter`/`Owner`) applied across Module 3, including the portal-path tables in the Lab 3.2 guide and checklist (the `Role`, `ManagedBy`, `Service`, `Purpose`, `Port` and `DeploymentDate` tags are gone); Labs 3.3 and 3.4 map `dev`/`prod`/`platform` to the canonical `Environment` values instead of tagging the raw parameter value, and the Lab 3.3 resource group no longer overwrites the Lab 1.2 tags.
- Lab 3.2 resource deltas from the AVM conversion: the data disk is created with `networkAccessPolicy: DenyAll` and `publicNetworkAccess: Disabled` (AVM defaults; the lab never exports a disk) plus `hyperVGeneration: V2` and explicit `burstingEnabled`/`maxShares`/`optimizedForFrequentAttach` values, the OS disk sets `caching: ReadWrite` explicitly, and `adminUsername` became a parameter (`parAdminUsername`, default `azureuser`) because a literal admin name is an error-level linter rule.
- Lab 3.3 resource deltas: the Container Apps environment's infrastructure resource group is named `ME_<environment-name>` by the module (Azure's auto-name was `ME_<env>_<rg>_<region>`), inter-app traffic encryption is enabled, and the container app is sent `maxInactiveRevisions: 0`, `activeRevisionsMode: 'Single'` and `ingressAllowInsecure: false`; and the registry keeps Azure's `azureADAuthenticationAsArmPolicy: enabled` through an explicit override (the module defaults it to `disabled`, which makes `Get-AzContainerRegistryRepository` fail with `Unauthorized`) and is sent a 7-day disabled soft-delete policy and `anonymousPullEnabled: false`.
- Lab 3.4 resource deltas: the staging slot now inherits the app's `siteConfig`, HTTPS-only setting, system-assigned identity, outbound VNet routing **and regional VNet integration** (the hand-written slot had none of the last three); the plan is sent one worker without zone redundancy (the AVM defaults are three workers and zone-redundant for Premium SKUs); the site keeps `ftpsState: 'FtpsOnly'` and uses the `outboundVnetRouting` property of the 2025-03-01 API instead of the legacy `siteConfig` route-all flag, while `alwaysOn` stays at Azure's default for lab cost.
- Module 4 Bicep converted to the AVM-first architecture (issue #62 v2, PR 4/6): all four labs configure the SkyCraft storage accounts through `avm/res/storage/storage-account`, which covers the account, the blob service (soft delete, versioning, containers), lifecycle management rules, the file service (soft delete, shares) and the network ACLs in a single module call.
- Module 4 lab-friction overrides (`docs/bicep-standards.md` §4.5): `networkAcls: { bypass: 'AzureServices', defaultAction: 'Allow' }` in Labs 4.1–4.3, because the module emits `Deny` when the parameter is omitted and Lab 4.4 is the lab that teaches locking the account; and `requireInfrastructureEncryption: false` in all four labs, because the module defaults it to `true` while Azure's own default is `false` and the property is creation-only.
- Module 4 labs are cumulative forward and must be run in order. The AVM module skips a sub-service whose parameter is empty, so a lab that does not own a sub-service passes `{}` and cannot regress an earlier lab; account-level properties are a full replace, so every lab restates the same baseline. Lab 4.4 is the only lab that has to restate another lab's blob configuration, because it creates `dev-assets`.
- Lab 4.1 deploys its three environments through one copy loop instead of three conditional module calls, and no longer switches encryption shape by deployment age: `parIsNewDeployment` and the `-NewDeployment` switch are gone (the module omits the creation-only `keyType` unless it is passed). `Deploy-Bicep.ps1` keeps its existing-account scan, which now only forces `parEnableInfrastructureEncryption` to false when the account already exists.
- Lab 4.2 `Deploy-Bicep.ps1` passes `parLocation`; it accepted `-Location` but only used it as the deployment location, so the template always kept its own default.
- Lab 4.4 `Remove-LabResource.ps1` no longer removes the `Microsoft.Storage` service endpoint from `WorldSubnet`. That endpoint is Lab 2.2 state, and removing it during a Module 4 cleanup silently regressed Module 2.
- Module 4 resource deltas from the AVM conversion: `allowCrossTenantReplication: false` (Azure's default is `true`) and `isLocalUserEnabled: false`.
- Lab 2.3 template parameters renamed to the Module 2 convention: `parPlatformRG`/`parDevRG`/`parProdRG` to `parResourceGroupNamePlatform`/`Dev`/`Prod`, `parHubVnetName`/`parDevVnetName`/`parProdVnetName` to `parVnetNamePlatform`/`Dev`/`Prod`, and `parDevLbPipName`/`parProdLbPipName` to `parPipNameDev`/`parPipNameProd` (#91).
- Lab 3.4 `Deploy-Bicep.ps1 -Environment prod` now targets the prod resource group and VNet; it passed only `parLocation` and `parEnvironment`, so a prod run renamed the resources but deployed them into the dev resource group and VNet.
- Lab 3.3 `Deploy-Bicep.ps1` tags the bootstrap resource group with all four canonical tags derived from `-Environment` (it hardcoded `Environment = 'Development'` and omitted `Owner`) and waits for ACR DNS only when the registry itself was just created, not whenever the image is missing.
- Lab 4.3 `Test-Lab.ps1` enumerates the deployed file shares and compares them against the expected set in both directions; it walked a hardcoded probe list, so a stray share left behind by a hand-made experiment passed silently (#99).
- Lab 4.3 `Remove-LabResource.ps1` takes `-Environment`, matching `Deploy-Bicep.ps1` and `Test-Lab.ps1`; it hardcoded the prod resource group and account, so a `dev` or `platform` run reported success while leaving both shares behind (#95).
- Lab 2.1 `Remove-LabResource.ps1` probes each virtual network and public IP before deleting it, so a resource that is genuinely absent stays an `[INFO]` while a resource that exists but cannot be deleted is reported as `[ERROR]` with the Azure message, and the script exits non-zero (#96).
- Lab 3.4 `Remove-LabResource.ps1` detaches the VNet integration from the web app and every slot and verifies per site that it is gone before deleting the plan (an integrated plan deleted first leaves an orphaned service association link that blocks deleting the subnet, VNet, NSGs and resource group); the resource names are parameters, and the script exits non-zero on failure instead of continuing silently.
- Module 5 Bicep converted to the AVM-first architecture (issue #62 v2, PR 5/6): the Log Analytics workspace via `avm/res/operational-insights/workspace`, the VM Insights data collection rule via `avm/res/insights/data-collection-rule`, the action group via `avm/res/insights/action-group`, the CPU metric alert via `avm/res/insights/metric-alert`, the Recovery Services Vault (with its backup-reports diagnostic setting) via `avm/res/recovery-services/vault`, the Backup Vault via `avm/res/data-protection/backup-vault`, and the VNet flow log and connection monitor via `avm/res/network/network-watcher`.
- Module 5 lab-friction overrides (`docs/bicep-standards.md` §4.5): the Recovery Services Vault keeps `publicNetworkAccess: 'Enabled'` (the module defaults to `Disabled`, which requires private endpoints for VM backup), and the Backup Vault sets soft delete **off** so `Remove-LabResource.ps1` deletes its blob backup instance and the vault in one pass. The Recovery Services Vault sends no `softDeleteSettings` at all: Azure Backup "secure by default" enforces `AlwaysON` soft delete platform-side on every new vault and rejects any other value with `BMSUserErrorSoftDeleteStateNotSetToAlwaysON`. Lab 5.2 `Test-Lab.ps1` asserts `AlwaysON` accordingly, and the teardown path — deleting a vault that holds only soft-deleted items — requires Azure CLI 2.75.0+ or Az PowerShell 7.5.0+.
- Lab 5.2 declares the Recovery Services Vault's LRS redundancy in Bicep (`redundancySettings`); `Deploy-Bicep.ps1` keeps its idempotent redundancy step, which now only confirms the value.
- Lab 5.3 re-declares the auto-provisioned `NetworkWatcher_swedencentral` through the AVM module (an idempotent update that applies the canonical tags); the flow log and the connection monitor are the module's children.
- Module 5 resource deltas from the AVM conversion: the Log Analytics workspace is created with `features.disableLocalAuth: true` and `forceCmkForQuery: true` (Azure's own defaults are `false`; nothing in the course uses the workspace shared keys), the Backup Vault is created with Azure Monitor alerts for all job failures enabled, and the deprecated `retentionPolicy` block is no longer sent with the storage diagnostic setting.
- `docs/bicep-standards.md` §10.5 rewritten: the Recovery Services Vault's storage redundancy is declared in Bicep through the AVM module's `redundancySettings` (the vault API path the error message demands), replacing the previous guidance that it is read-only in the Bicep type system and must be set from the deployment script. Verified against a vault whose `storageTypeState` was already `Locked`.

### Removed

- Module 1 local Bicep modules `rg-role-assignment.bicep`, `locks.bicep`, and `policies.bicep`, superseded by the AVM modules above; `tags.bicep` is retained as the documented fallback for `Microsoft.Resources/tags`.
- Module 2 local Bicep modules `vnet-hub.bicep`, `vnet-spoke.bicep`, `vnet-peering.bicep`, `public-ip.bicep` (Lab 2.1), `security-hub.bicep`, `security-spoke.bicep` (Lab 2.2), `dns-public.bicep`, `dns-private.bicep`, `load-balancer.bicep` (Lab 2.3), superseded by the AVM modules above; `get-public-ip.bicep` is retained as the documented trivial `existing` lookup.
- Module 3 local Bicep modules `keyvault.bicep`, `nic.bicep`, `vm.bicep`, `disk.bicep` (Lab 3.2), `acr.bicep`, `aci.bicep`, `containerapps.bicep` (Lab 3.3) and `app-service.bicep` (Lab 3.4), superseded by the AVM modules above; Lab 3.4 `modules/autoscale.bicep` is the documented fallback.
- Lab 3.3 `Deploy-Containers.ps1`: an older duplicate of `Deploy-Bicep.ps1` that deployed the deleted local modules directly and was referenced by nothing.
- Module 4 local Bicep modules `storageAccount.bicep` (Lab 4.1), `blobContainer.bicep` (Lab 4.2), `storage.bicep` (Lab 4.3) and `security.bicep` (Lab 4.4), superseded by the AVM module above. Module 4 has no local modules left and no `bicep/modules/` directory.
- The cross-lab import that made Lab 4.2 compile Lab 4.1's `modules/storageAccount.bicep`.
- The `blobContainer.bicep` `PublicAccessNotPermitted` race workaround: every container in Module 4 is `publicAccess: 'None'` (the subscription policy blocks anything else), so the race cannot occur.
- Module 5 local Bicep modules `monitoring.bicep` (Lab 5.1), `recoveryServicesVault.bicep`, `backupVault.bicep` (Lab 5.2) and `network-monitoring.bicep` (Lab 5.3), superseded by the AVM modules above; Lab 5.3 has no `bicep/modules/` directory left.

### Fixed

- Lab 1.1 `Test-Lab.ps1` looked for the guest user by the wrong e-mail (`istormrage@...`); it now checks `illidan@externalcompany.com`, the address `New-LabUser.ps1` invites.
- Lab 1.2 `Test-Lab.ps1` could never find the External Partner assignment: guest sign-in names are rewritten to `<alias>_<domain>#EXT#@<tenant>`, so the `illidan@` match is now `illidan[@_]`.
- Lab 2.1 guide: the hub-spoke peering diagram claimed "Allow Gateway Transit"; the lab disables gateway transit and allows forwarded traffic, and the diagram now says so.
- Lab 3.2 `Remove-LabResource.ps1` printed a purge hint that passed the tenant id as `-Location`; the script now deletes and purges the vault itself, so the name is reusable immediately.
- Lab 3.2 `Enable-Encryption.ps1` restores the original VM size on every path: the resize-back used to be skipped when the encryption call failed, and it is now deliberately skipped (with the manual command printed) only while encryption is still in progress.
- Lab 3.3 `Deploy-Bicep.ps1` bootstrapped the registry from `bicep/modules/acr.bicep`, a module that is not deployable on its own; it now deploys `bicep/acr.bicep`.
- Lab 3.3 checklist named the Container Apps environment and app `dev-skycraft-swc-cae`/`dev-skycraft-swc-aca-world`; the template and `Test-Lab.ps1` use the `-02` names.
- Lab 3.1 checklist expected a dev VNet with three subnets; it has four, and its hand-off to Lab 3.2 no longer previews a hand-written VM module or links to a folder that does not exist.
- Lab 1.3 guide and checklist taught non-canonical tag values (`CostCenter` of `Engineering`/`Operations`/`Shared-Services`, an `Owner` e-mail address); the portal path now teaches the same `CostCenter = MSDN` and `Owner = mbiszczanik` the Bicep path deploys (#88).
- Lab 2.1 guide: the "Prod Load Balancer Public IP" block appeared twice with different content, and the dev VNet was described as having three subnets instead of four (#88).
- Lab 2.2 `ARCHITECTURE.md` counted 9 NSGs; the lab deploys 7 (1 hub + 3 dev + 3 prod) (#88).
- Lab 2.1 `Remove-LabResource.ps1` filtered peerings on `-match "peer"`, which matches none of the `hub-to-dev`/`dev-to-hub` names, so cleanup left the spoke side behind as `Disconnected` and the next Lab 2.1 deployment failed with `RemotePeeringIsDisconnected` (#89).
- Lab 2.2 `Remove-LabResource.ps1` printed `~/month` for its three cost estimates: `"~$140/month"` interpolated the undefined variable `$140` (#89).
- Lab 2.2 `Deploy-Security.ps1` recorded service endpoints with `Locations = @("swedencentral")` while the Bicep path records them region-unrestricted, so every subsequent what-if reported a subnet Modify (#89).
- Lab 2.2 `Deploy-Security.ps1` created its NSGs, ASGs and Bastion resources without the canonical `Owner` tag, and tagged the hub Bastion and its public IP `Environment = Production` instead of `Platform`. The script takes `-Owner` (default `mbiszczanik`) and has a separate platform tag set, which removes ten spurious `Modify` entries from every what-if run after the manual path (#100).
- Lab 2.2 `Deploy-Security.ps1` prompted for Azure Bastion with `Read-Host`, so a non-interactive run threw and exited 1 even though Tasks 1-5 had succeeded. It now takes `-DeployBastion`, treats a declined or non-interactive Bastion as success, and exits non-zero only when a task actually failed (#101).
- Lab 2.2 `Deploy-Security.ps1` set service endpoints on `DatabaseSubnet` only, while the Bicep path also puts `Microsoft.Storage` on `WorldSubnet`. A learner following the manual path could not deploy Lab 4.4, whose storage firewall needs a virtual network rule for that subnet, and Lab 2.2's own `Test-Lab.ps1` failed. `Set-SubnetSecurity` now takes a per-subnet endpoint list instead of a single boolean, and the guide and checklist teach the `WorldSubnet` endpoint too (#98).
- Lab 2.1 `Remove-LabResource.ps1` reported every virtual network deletion failure as `[INFO] VNet ... not found or already deleted`, discarding the exception. During the PR #93 live cycle it hid a real `InUseSubnetCannotBeDeleted` on the prod VNet and still exited 0 (#96).
- Lab 2.3 `Remove-LabResource.ps1` deleted the private DNS zone while its VNet links were still draining, failing with `Cannot delete resource while nested resources exist` and needing a manual retry. The zone deletion is retried on exactly that error for up to a minute; any other error still fails immediately. Polling the link list is not enough - ARM keeps counting the links as nested resources for tens of seconds after `Get-AzPrivateDnsVirtualNetworkLink` has stopped returning them (#97).
- Lab 2.3 `Deploy-Bicep.ps1` defaulted `-TemplateFile` to `..\bicep\main.bicep` relative to the current directory, so it was the only script in the repository that had to be run from its own `scripts/` folder; the default is anchored to `$PSScriptRoot` like everywhere else (#75).
- Lab 4.4 accepted `platform` as an environment although the hub VNet has no workload subnet to allow through the storage firewall, so the run failed mid-deployment. `parEnvironment` is now `@allowed(['dev', 'prod'])`, all three scripts validate the same set, and the dead `platform` entries are gone from the template's environment maps (#94).
- Lab 5.2 blob backup: `Deploy-Bicep.ps1` now drops the vaulted `BackupWeekly` rule that current `Az.DataProtection` policy templates ship, so `SkyCraft-Blob-Policy` is the operational-only policy the lab documents, and `New-LabBlobBackup.ps1` no longer passes a container backup configuration. The previous combination stored a policy whose backup rule wrote to `VaultStore` while its only retention lifecycle targeted `OperationalStore`, and Azure rejected every blob backup instance built from it with `UserErrorInvalidRequestParameter: Parameter NO_PARAM in request is invalid`.

## [0.7.1] - 2026-07-27

### Removed

- `AUDIT-modules-2-5.md`: working audit report accidentally committed with the v0.7.0 release. All of its findings were already resolved in 0.7.0, and no file referenced it; recoverable from git history if needed.

### Changed

- `.gitignore` now excludes the private, un-checked-in `CLAUDE.local.md` assistant instructions file so it is no longer listed as untracked.

## [0.7.0] - 2026-07-10

### Added

- Repository hygiene baseline: `.gitattributes` enforcing line-ending normalization (CRLF for `*.ps1`/`*.psm1`/`*.psd1`/`*.cmd`/`*.bat`, LF for `*.sh`, `* text=auto` as the catch-all for other text files, and image/binary types marked binary) and `.editorconfig` for consistent editor settings.
- This `CHANGELOG.md`, following the Keep a Changelog format.
- GitHub issue and pull-request templates to standardize contributions.
- `.vscode/extensions.json` recommending the project's preferred editor extensions.
- Architecture documentation: per-module `ARCHITECTURE.md` notes for Modules 1 through 5.
- Root `DESIGN-DECISIONS.md` index with a README pointer.
- Architecture Decision Records: new ADR folder seeded with the first three records.
- Dependabot configuration and a documented vulnerability-reporting policy.
- Continuous integration via a lint workflow running PSScriptAnalyzer, Pester, and Bicep build.

### Changed

- README updated with a CI status badge and refreshed documentation links.
- Lint workflow extended with markdownlint and gitleaks CI jobs.
- PowerShell standards aligned with the Microsoft gold-path guidance.
- Bicep standards aligned with the Microsoft gold-path guidance.
- Contributing guide documents the GitHub Flow workflow.
- Module 5 Lab 5.2 business-continuity checklist expanded and completed.
- Module 1 README contract enforcement extended to verify the L004 13-section structure.
- ADR-0002 status-checks follow-up marked as implemented.
- Architecture layer gaps from the prior architecture work completed.
- Renamed `SECURITY.MD` to `SECURITY.md` to correct file-name casing.
- Pinned `actions/checkout` to v6 (from v4) in CI.

### Fixed

- Removed dead plaintext-to-`SecureString` conversion from `New-LabUser`.
- Lab 3.3: Added 90-second DNS propagation wait after ACR bootstrap to prevent ACA image-pull failures on freshly created registries.
- Lab 3.2: Removed availability zone pinning from VM and managed disk deployments to prevent `ZonalAllocationFailed` capacity errors in Sweden Central.
- Lab 4.2: Disabled blob public access on the development storage account to comply with subscription-level `PublicAccessNotPermitted` enforcement.
- Lab 4.3: Corrected file share quota property path from `ShareProperties.ShareQuota` (null) to `QuotaGiB` on `PSShare` objects returned by `Get-AzRmStorageShare`.
- Lab 5.2: Increased RBAC propagation wait from 30 seconds to 360 seconds to satisfy Azure Backup's 5–10 minute role-assignment requirement.
- Cleanup 1.3 / Lab 2.3: Added 45-second ARM lock removal propagation wait to prevent downstream cleanup steps from racing the lock-removal window.

## [0.6.0] - 2026-05-26

### Added

- Module 1 README Architecture Overview section with a Mermaid diagram.

### Changed

- Lab 3.1 Bicep modules refactored to align with the Bicep standards.
- Module 5 README rewritten to the L004 13-section contract.
- Comment-Based Help brought to 100% coverage across all PowerShell scripts.
- Unified README file-name casing to lowercase across the repository.
- Cleaned up `.gitignore` typos and added the session scratch directory to ignores.

### Fixed

- Lab 1.1 hard-coded lab password removed and covered with Pester tests.
- Labs 3.3 and 3.4 downgraded from bleeding-edge Bicep API versions to stable releases.

## [0.5.0] - 2026-04-06

### Added

- Module 5 (Monitoring & Maintenance): completed infrastructure-as-code, automation, and lab documentation across all labs.

## [0.4.0] - 2026-02-22

### Added

- Initial SkyCraft AZ-104 learning platform spanning the first four modules.
- Module 1 (Identities & Governance): identity framework, governance lab 1.3, automation, and documentation.
- Module 2 (Networking): virtual network, secure access, and routing labs with Bicep modules, PowerShell scripts, and lab guides.
- Module 3 (Compute): Lab 3.1 infrastructure plus virtual machines (3.2), additional compute labs (3.3), and App Service with VNet integration (3.4).
- Module 4 (Storage): Lab 4.1 storage accounts with conditional encryption and Lab 4.2 Blob Storage.
- Project foundations: specification, naming/standards documents, security files, README, and course navigation.

[Unreleased]: https://github.com/mbiszczanik/skycraft/compare/v0.8.0...HEAD
[0.8.0]: https://github.com/mbiszczanik/skycraft/compare/v0.7.1...v0.8.0
[0.7.1]: https://github.com/mbiszczanik/skycraft/compare/v0.7.0...v0.7.1
[0.7.0]: https://github.com/mbiszczanik/skycraft/compare/v0.6.0...v0.7.0
[0.6.0]: https://github.com/mbiszczanik/skycraft/compare/v0.5.0...v0.6.0
[0.5.0]: https://github.com/mbiszczanik/skycraft/compare/v0.4.0...v0.5.0
[0.4.0]: https://github.com/mbiszczanik/skycraft/releases/tag/v0.4.0
