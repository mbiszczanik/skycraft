# Lab 5.3: Network Monitoring & Troubleshooting (1.5 hours)

## 🎯 Learning Objectives

By completing this lab, you will:

- Enable and configure **Azure Network Watcher**
- Use **IP Flow Verify** to identify NSG blocks
- Use **Next Hop** to troubleshoot routing issues
- Run **Connection Troubleshooter** for end-to-end connectivity checks
- Generate a **Network Topology** diagram automatically
- Enable a **VNet flow log** with **Traffic Analytics** on the production VNet
- Create a **Connection Monitor** that probes hub-to-spoke SSH continuously

---

## 🏗️ Architecture Overview

[Description]: Network Watcher is a regional service that provides tools to monitor, diagnose, and view metrics and logs for resources in an Azure virtual network.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="images/lab-5.3-architecture.dark.svg">
  <source media="(prefers-color-scheme: light)" srcset="images/lab-5.3-architecture.svg">
  <img src="images/lab-5.3-architecture.svg" width="100%" alt="Lab 5.3 architecture: Network Watcher tools and flow logs">
</picture>

---

## 📋 Real-World Scenario

**Situation**: Users are reporting that they cannot reach the development world server on port 8080. Khadgar suspects that a recently applied Network Security Group (NSG) rule is blocking the traffic, or perhaps a custom route is sending packets to the wrong gateway. Instead of manually inspecting dozens of rules, he needs to use Network Watcher to pinpoint the exact failure point.

**Your Task**: Use Network Watcher to verify if traffic on port 8080 is allowed to the development VM, confirm correctly routed traffic with Next Hop, and run an end-to-end connection check between the Hub and the Spoke. Then make the visibility permanent: record every flow on the production VNet with a flow log feeding Traffic Analytics, and keep a Connection Monitor probing the hub-to-spoke SSH path every five minutes so the next outage is on a dashboard before a user reports it.

---

## ⏱️ Estimated Time: 1.5 hours

- **Section 1**: Network Watcher Fundamentals (15 min)
- **Section 2**: IP Flow Verify (15 min)
- **Section 3**: Next Hop & Topology (15 min)
- **Section 4**: Connection Troubleshooter (15 min)
- **Section 5**: VNet Flow Log & Traffic Analytics (15 min)
- **Section 6**: Connection Monitor (15 min)

---

## ✅ Prerequisites

Before starting this lab:

- [ ] Completed **Lab 2.1: Virtual Networks** (`prod-skycraft-swc-vnet` is the flow log target; the dev VNet hosts the VMs)
- [ ] Completed **Lab 2.2: Secure Access** (NSGs must exist for IP Flow Verify to have rules to report)
- [ ] Completed **Lab 3.2: Virtual Machines** (`dev-skycraft-swc-auth-vm` and `dev-skycraft-swc-world-vm` must be running - the Connection Monitor needs two distinct VMs; `prod-skycraft-swc-auth-vm` is used as the source when it exists)
- [ ] Completed **Lab 4.1: Storage Accounts** (`platformskycraftswcsa` must exist for flow log storage)
- [ ] Completed **Lab 5.1: Azure Monitor** (`platform-skycraft-swc-law` Log Analytics Workspace must exist for Traffic Analytics and Connection Monitor output)
- [ ] Network Watcher `NetworkWatcher_swedencentral` in `NetworkWatcherRG` (Azure creates it with the first VNet in the region; `Deploy-Bicep.ps1` enables it if missing)

These are the same checks `scripts/Deploy-Bicep.ps1` performs before it deploys anything - the cheapest chain that satisfies them is 1.2 → 2.1 → 2.3 → 3.2 (dev) → 4.1 `-All` → 5.1 → 5.2 → 5.3.

---

## 📖 Section 1: Network Watcher Fundamentals (15 min)

### What is Network Watcher?

**Azure Network Watcher** provides tools to monitor, diagnose, view metrics, and enable or disable logs for resources in an Azure virtual network. It is designed to monitor and repair the network health of IaaS (Infrastructure-as-a-Service) products.

> [!NOTE]
> Network Watcher is enabled automatically for your subscription when you create a virtual network, but it must be enabled for the specific region (Sweden Central).

---

## 📖 Section 2: IP Flow Verify (15 min)

### Step 5.3.1: Check for NSG Blocks

1. Navigate to **Network Watcher** → **Diagnostic tools** → **IP flow verify**.
2. Select your VM: `dev-skycraft-swc-auth-vm`.
3. Configure the check:
   - Protocol: **TCP**
   - Direction: **Inbound**
   - Local port: **8080**
   - Remote IP: **8.8.8.8** (Example external IP)
   - Remote port: **443**
4. Click **Check**.

**Expected Result**: The tool returns **Access denied** or **Access allowed** and specifies the **NSG Rule** name that caused the result.

---

## 📖 Section 3: Next Hop & Topology (15 min)

### Step 5.3.2: Verify Routing

1. In Network Watcher, go to **Next hop**.
2. Select your VM: `prod-skycraft-swc-auth-vm`.
3. Source IP address: (Auto-filled).
4. Destination IP address: `1.1.1.1` (External DNS).
5. Click **Next hop**.

**Expected Result**: The tool returns **Internet** as the next hop type. If you were checking traffic between Hub and Spoke vNets, it should say **VNetPeering** or **VirtualNetwork**.

### Step 5.3.3: Visualize Topology

1. In Network Watcher, go to **Monitoring** → **Topology**.
2. Select the resource group: `dev-skycraft-swc-rg`.
3. Click **View topology**.

**Expected Result**: A visual map of your VNets, subnets, and connected VMs appears.

---

## 📖 Section 4: Connection Troubleshooter (15 min)

### Step 5.3.4: End-to-End Check

1. In Network Watcher, go to **Connection troubleshoot**.
2. **Source**:
   - Type: **Virtual Machine**
   - Resource: `prod-skycraft-swc-auth-vm` *(if Lab 3.2 prod environment was deployed)*
   - **Fallback** — if only dev environment exists: use `dev-skycraft-swc-world-vm` as source
3. **Destination**:
   - Type: **Virtual Machine**
   - Resource: `dev-skycraft-swc-auth-vm`
   - Port: **22** (SSH)
4. Click **Check**.

**Expected Result**: After a minute, the tool shows a hop-by-hop breakdown of the connection status. Source and destination must be two distinct VMs — both must have the **NetworkWatcherAgent** extension installed (the deployment script installs it automatically).

---

## 📖 Section 5: VNet Flow Log & Traffic Analytics (15 min)

### What is a VNet flow log?

The tools above answer a question you already have. A **flow log** records every flow through a virtual network - source, destination, port, protocol, allowed or denied, bytes - as JSON in a storage account, so you can answer the questions you have not asked yet. **Traffic Analytics** reads those logs into a Log Analytics workspace every 10 minutes and turns them into top talkers, blocked flows and cross-VNet traffic maps.

> [!NOTE]
> **SkyCraft Choice**: VNet flow logs, not NSG flow logs. NSG flow logs were retired for new deployments in 2025 and only see traffic that passes an NSG; a VNet flow log sees every flow in `prod-skycraft-swc-vnet`, including subnets with no NSG attached. Retention is 7 days: long enough to investigate an incident, short enough that the storage cost stays negligible.

### Step 5.3.5: Create the flow log

The flow log is a child of the regional Network Watcher `NetworkWatcher_swedencentral` in `NetworkWatcherRG`, not of the VNet, which is why it lives in that resource group.

#### Azure Portal

1. In **Network Watcher**, go to **Logs** → **Flow logs** → **+ Create**.
2. **Basics**:
   - Flow log type: **Virtual network** → **+ Select target resource** → **Virtual network** → `prod-skycraft-swc-vnet` → **Confirm selection**
   - Flow log name: `prod-skycraft-swc-vnet-flowlog`
   - Storage account: `platformskycraftswcsa`
   - Retention (days): **7**
3. **Analytics** (VNet flow logs are always format version 2; there is no version field):
   - **Enable traffic analytics**: checked
   - Traffic analytics processing interval: **Every 10 mins**
   - Log Analytics workspace: `platform-skycraft-swc-law`
4. **Tags**: `Project = SkyCraft`, `Environment = Production`, `CostCenter = MSDN`, `Owner = <your name>`.
5. Click **Review + create** → **Create**.

#### Azure CLI

`--storage-account` and `--workspace` take full resource IDs here: given a bare name, the CLI looks for it in `--resource-group` (the VNet's group), but both live in `platform-skycraft-swc-rg`.

```azurecli
SA=$(az storage account show -g platform-skycraft-swc-rg -n platformskycraftswcsa --query id -o tsv)
LAW=$(az monitor log-analytics workspace show -g platform-skycraft-swc-rg -n platform-skycraft-swc-law --query id -o tsv)

az network watcher flow-log create \
  --name prod-skycraft-swc-vnet-flowlog \
  --location swedencentral \
  --vnet prod-skycraft-swc-vnet \
  --resource-group prod-skycraft-swc-rg \
  --storage-account "$SA" \
  --enabled true \
  --format JSON --log-version 2 \
  --retention 7 \
  --traffic-analytics true \
  --workspace "$LAW" \
  --interval 10 \
  --tags Project=SkyCraft Environment=Production CostCenter=MSDN Owner="<your name>"
```

#### Azure PowerShell

```powershell
$nw   = Get-AzNetworkWatcher -Location swedencentral
$vnet = Get-AzVirtualNetwork -Name prod-skycraft-swc-vnet -ResourceGroupName prod-skycraft-swc-rg
$sa   = Get-AzStorageAccount -Name platformskycraftswcsa -ResourceGroupName platform-skycraft-swc-rg
$law  = Get-AzOperationalInsightsWorkspace -Name platform-skycraft-swc-law -ResourceGroupName platform-skycraft-swc-rg

New-AzNetworkWatcherFlowLog -NetworkWatcher $nw -Name prod-skycraft-swc-vnet-flowlog `
  -TargetResourceId $vnet.Id -StorageId $sa.Id -Enabled $true `
  -FormatType Json -FormatVersion 2 -EnableRetention $true -RetentionPolicyDays 7 `
  -EnableTrafficAnalytics -TrafficAnalyticsWorkspaceId $law.ResourceId -TrafficAnalyticsInterval 10 `
  -Tag @{ Project = 'SkyCraft'; Environment = 'Production'; CostCenter = 'MSDN'; Owner = '<your name>' }
```

**Expected Result**: `prod-skycraft-swc-vnet-flowlog` shows **Enabled** under Flow logs with `prod-skycraft-swc-vnet` as its target. After 10-20 minutes, **Traffic Analytics** in Network Watcher shows the first flows between the hub and the spokes.

---

## 📖 Section 6: Connection Monitor (15 min)

### What is Connection Monitor?

**Connection Troubleshoot** (Section 4) is a one-off probe. **Connection Monitor** runs the same probe on a schedule from an agent on the source VM, records reachability, latency and the hop-by-hop path to a Log Analytics workspace, and can alert when checks fail. The lab creates one monitor, `skycraft-hub-spoke-cm`, that probes SSH from the production spoke VM (or, in a dev-only environment, the dev world VM) to the development auth server every five minutes.

### Step 5.3.6: Create the Connection Monitor

Both endpoint VMs need the **NetworkWatcherAgent** extension, and no earlier lab installs it. The portal offers to install it when you pick a VM endpoint, and `Deploy-Bicep.ps1` installs it before creating the monitor; the CLI and PowerShell paths below install it explicitly first, because creating a monitor with an agent-less VM endpoint fails with `NetworkWatcherVmExtensionNotInstalled`. The extension is tagged `Project = SkyCraft` so that `Remove-LabResource.ps1` removes it again - a portal-installed agent is untagged and survives cleanup.

#### Azure Portal

1. In **Network Watcher**, go to **Monitoring** → **Connection monitor** → **+ Create**.
2. **Basics**:
   - Connection Monitor Name: `skycraft-hub-spoke-cm`
   - Subscription: yours
   - Region: **Sweden Central** (the wizard defaults to East US; the region picks the Network Watcher, and `Test-Lab.ps1` looks under `NetworkWatcher_swedencentral`)
3. **Test groups** → **+ Add test group**
   - Test group name: `hub-spoke-ssh`
   - **+ Add sources** → **Azure endpoints** → select `prod-skycraft-swc-auth-vm` → **Add endpoints**
     - **Fallback** — if only the dev environment exists: pick `dev-skycraft-swc-world-vm` instead (the deployment script makes the same substitution)
   - The source endpoint is named after its VM: select it in the test group view and rename it `prod-auth-source`
   - **+ Add destinations** → **Azure endpoints** → select `dev-skycraft-swc-auth-vm` → **Add endpoints**
   - Select the destination endpoint in the test group view and rename it `dev-auth-destination` (`Test-Lab.ps1` looks the destination up by this name)
   - **Add Test configuration** → **New configuration**
     - Test configuration name: `tcp-22-every-5m`
     - Protocol: **TCP**
     - **Disable traceroute**: leave unchecked
     - Destination port: `22`
     - Test Frequency: **Every 5 minutes**
     - **Checks failed (%)**: `10`
     - **Round trip time (ms)**: `100`
   - **Add Test configuration** → **Add Test Group**
4. **Workspace**:
   - **Use workspace created by connection monitor**: unchecked
   - Workspace: `platform-skycraft-swc-law`
5. **Create alert**: leave unchecked.
6. Click **Review + create** → **Create**.
7. The wizard has no Tags tab, and `Test-Lab.ps1` checks the monitor's `Project` and `CostCenter` tags, so tag it from Cloud Shell (PowerShell):

   ```powershell
   Update-AzTag -ResourceId (Get-AzNetworkWatcherConnectionMonitor -Location swedencentral -Name skycraft-hub-spoke-cm).Id `
     -Tag @{ Project = 'SkyCraft'; Environment = 'Production'; CostCenter = 'MSDN'; Owner = '<your name>' } -Operation Merge
   ```

#### Azure CLI

```azurecli
# Dev-only environment: use -g dev-skycraft-swc-rg -n dev-skycraft-swc-world-vm for the source
SRC=$(az vm show -g prod-skycraft-swc-rg -n prod-skycraft-swc-auth-vm --query id -o tsv)
DST=$(az vm show -g dev-skycraft-swc-rg -n dev-skycraft-swc-auth-vm --query id -o tsv)

# Install the agent on both endpoints and tag it so the lab cleanup removes it
for VM in "$SRC" "$DST"; do
  az vm extension set --ids "$VM" --publisher Microsoft.Azure.NetworkWatcher --name NetworkWatcherAgentLinux --version 1.4
  az resource tag --is-incremental --tags Project=SkyCraft --ids "$VM/extensions/NetworkWatcherAgentLinux"
done

az network watcher connection-monitor create \
  --name skycraft-hub-spoke-cm \
  --location swedencentral \
  --endpoint-source-name prod-auth-source --endpoint-source-type AzureVM \
  --endpoint-source-resource-id "$SRC" \
  --endpoint-dest-name dev-auth-destination --endpoint-dest-type AzureVM \
  --endpoint-dest-resource-id "$DST" \
  --test-config-name tcp-22-every-5m \
  --protocol Tcp --tcp-port 22 --frequency 300 \
  --threshold-failed-percent 10 --threshold-round-trip-time 100 \
  --test-group-name hub-spoke-ssh \
  --workspace-ids $(az monitor log-analytics workspace show -g platform-skycraft-swc-rg -n platform-skycraft-swc-law --query id -o tsv) \
  --tags Project=SkyCraft Environment=Production CostCenter=MSDN Owner="<your name>"
```

#### Azure PowerShell

```powershell
$nw  = Get-AzNetworkWatcher -Location swedencentral
# Falls back to the dev world VM when the prod environment does not exist
$src = (Get-AzVM -Name prod-skycraft-swc-auth-vm -ResourceGroupName prod-skycraft-swc-rg -ErrorAction SilentlyContinue) ??
       (Get-AzVM -Name dev-skycraft-swc-world-vm -ResourceGroupName dev-skycraft-swc-rg)
$dst = Get-AzVM -Name dev-skycraft-swc-auth-vm  -ResourceGroupName dev-skycraft-swc-rg
$law = Get-AzOperationalInsightsWorkspace -Name platform-skycraft-swc-law -ResourceGroupName platform-skycraft-swc-rg

# Install the agent on both endpoints; New-AzResource (not Set-AzVMExtension, which has no -Tag)
# so the extension carries the tag the lab cleanup selects on
foreach ($vm in $src, $dst) {
  New-AzResource -ResourceId "$($vm.Id)/extensions/NetworkWatcherAgentLinux" -Location $vm.Location `
    -Properties @{ publisher = 'Microsoft.Azure.NetworkWatcher'; type = 'NetworkWatcherAgentLinux'; typeHandlerVersion = '1.4'; autoUpgradeMinorVersion = $true } `
    -Tag @{ Project = 'SkyCraft' } -Force
}

$srcEp = New-AzNetworkWatcherConnectionMonitorEndpointObject -Name prod-auth-source     -AzureVM -ResourceId $src.Id
$dstEp = New-AzNetworkWatcherConnectionMonitorEndpointObject -Name dev-auth-destination -AzureVM -ResourceId $dst.Id
$tcp   = New-AzNetworkWatcherConnectionMonitorProtocolConfigurationObject -TcpProtocol -Port 22
$cfg   = New-AzNetworkWatcherConnectionMonitorTestConfigurationObject -Name tcp-22-every-5m -TestFrequencySec 300 `
           -ProtocolConfiguration $tcp -SuccessThresholdChecksFailedPercent 10 -SuccessThresholdRoundTripTimeMs 100
$grp   = New-AzNetworkWatcherConnectionMonitorTestGroupObject -Name hub-spoke-ssh -TestConfiguration $cfg -Source $srcEp -Destination $dstEp
$out   = New-AzNetworkWatcherConnectionMonitorOutputObject -WorkspaceResourceId $law.ResourceId

New-AzNetworkWatcherConnectionMonitor -NetworkWatcher $nw -Name skycraft-hub-spoke-cm -TestGroup $grp -Output $out `
  -Tag @{ Project = 'SkyCraft'; Environment = 'Production'; CostCenter = 'MSDN'; Owner = '<your name>' }
```

**Expected Result**: `skycraft-hub-spoke-cm` appears under Connection monitor with monitoring status **Running**, and `NWConnectionMonitorTestResult` in `platform-skycraft-swc-law` starts receiving rows within about 10 minutes. What `hub-spoke-ssh` reports depends on the source:

- **Dev fallback source** (`dev-skycraft-swc-world-vm`): **Pass** - source and destination share `dev-skycraft-swc-vnet`.
- **Production source** (`prod-skycraft-swc-auth-vm`): **Fail**. The prod and dev spokes are each peered only to the hub, and VNet peering is not transitive, so traffic to the dev `AuthSubnet` (`10.1.1.0/24`) matches the system route `10.0.0.0/8 → None` and is dropped. Confirm it with **Next hop** (Step 5.3.2) from `prod-skycraft-swc-auth-vm` to the private IP of `dev-skycraft-swc-auth-vm`: this is the monitor doing its job, not a broken lab. Issue #178 tracks the route the lab should provide.

**Preview - the AVM module call the Bicep path makes** (`bicep/main.bicep`; version pinned in `docs/bicep-standards.md` §4.4). Both resources of this lab are children of the Network Watcher module:

```bicep
module modNetworkWatcher 'br/public:avm/res/network/network-watcher:0.5.1' = {
  name: 'network-monitoring-deployment'
  scope: resourceGroup('NetworkWatcherRG')
  params: {
    name: 'NetworkWatcher_swedencentral'        // re-declares the auto-provisioned watcher (idempotent)
    flowLogs: [ { name: 'prod-skycraft-swc-vnet-flowlog', targetResourceId: parProdVnetResourceId, formatVersion: 2, retentionInDays: 7, workspaceResourceId: parWorkspaceResourceId, trafficAnalyticsInterval: 10, ... } ]
    connectionMonitors: [ { name: 'skycraft-hub-spoke-cm', endpoints: [...], testConfigurations: [...], testGroups: [...], workspaceResourceId: parWorkspaceResourceId } ]
  }
}
```

---

## ✅ Lab Checklist

- [ ] Network Watcher verified as active in Sweden Central
- [ ] IP Flow Verify used to check port 8080 access
- [ ] Next Hop checked for external connectivity
- [ ] VNet Topology generated and inspected
- [ ] Connection Troubleshooter used between two VMs
- [ ] Flow log `prod-skycraft-swc-vnet-flowlog` enabled on `prod-skycraft-swc-vnet` with Traffic Analytics every 10 minutes
- [ ] Connection Monitor `skycraft-hub-spoke-cm` running the `hub-spoke-ssh` test group

**For detailed verification**, see [lab-checklist-5.3.md](lab-checklist-5.3.md)

---

## 🔧 Troubleshooting

### Issue 1: "Network Watcher not enabled for region"

**Symptom**: Common error when first opening the tool.

**Solution**:

- Go to **Network Watcher** → **Regions**.
- Ensure **Sweden Central** is set to **Enabled**.

### Issue 2: Test-Lab.ps1 fails on the flow log or the Connection Monitor although the portal steps succeeded

**Symptom**: `Flow log 'prod-skycraft-swc-vnet-flowlog' exists` or `Connection Monitor 'skycraft-hub-spoke-cm' exists` reports FAIL.

**Root Cause**: The validation script looks the resources up **by name** under `NetworkWatcher_swedencentral` in `NetworkWatcherRG`, and the destination endpoint by the name `dev-auth-destination`. A flow log, monitor or endpoint created under a different name, or a monitor without the `Project = SkyCraft` and `CostCenter = MSDN` tags (the portal wizard cannot set them - see Step 5.3.6, item 7), fails the check.

**Solution**: Use the exact names from Steps 5.3.5 and 5.3.6, or run `scripts/Deploy-Bicep.ps1`, which is idempotent and produces the same resources.

### Issue 3: Connection Monitor shows "Agent not installed" on an endpoint

**Symptom**: The test group stays **Indeterminate** and the endpoint carries a warning.

**Root Cause**: Connection Monitor probes from the **NetworkWatcherAgent** VM extension, and no earlier lab installs it - Lab 3.2's VMs come without it.

**Solution**: Install the extension on both endpoint VMs with the loop at the top of the Step 5.3.6 CLI or PowerShell block, or re-run `Deploy-Bicep.ps1`, which installs it before creating the monitor.

### Issue 4: Enabling Traffic Analytics fails with `TARequestDisallowedByPolicy`

**Symptom**: Creating the flow log (Step 5.3.5, any path) fails with *The enablement of Traffic Analytics is blocked due to the user's policy restrictions: "RequestDisallowedByPolicy ... policyAssignments/Enforce-Project-Tag"*, and the flow log is left in the **Failed** state.

**Root Cause**: When Traffic Analytics is enabled it creates its own data collection endpoint and rule, `NWTA-<workspace-guid>...`, in the workspace's resource group (`platform-skycraft-swc-rg`) - without tags. Lab 1.3's `Enforce-Project-Tag` assignment denies every untagged resource, so the pair is refused.

**Solution**: Tracked in issue #182. Until it lands, the lab has no supported workaround that keeps Lab 1.3's policy intact. Do not delete the assignment: it is what Lab 1.3's `Test-Lab.ps1` checks.

---

## 🎓 Knowledge Check

1. **When would you use IP Flow Verify instead of just looking at NSG rules?**
   <details>
     <summary>**Click to see the answer**</summary>

   **Answer**: When there are multiple NSGs applied (at both subnet and NIC levels) or complex rule sets. IP Flow Verify simulates the traffic and identifies exactly which rule is winning.
   </details>

2. **Does Network Watcher cost anything?**
   <details>
     <summary>**Click to see the answer**</summary>

   **Answer**: Most diagnostic tools (IP Flow, Next Hop) are free. Only logs (VNet flow logs, Traffic Analytics) and Packet Captures incur costs based on data volume.
   </details>

3. **Connection Troubleshoot and Connection Monitor both test `prod-skycraft-swc-auth-vm` → `dev-skycraft-swc-auth-vm` on port 22. When do you need the monitor?**
   <details>
     <summary>**Click to see the answer**</summary>

   **Answer**: Connection Troubleshoot is a single probe you run when you already suspect a problem. Connection Monitor repeats the probe every five minutes from an agent on the source VM, stores the results in Log Analytics, and can raise an alert - it catches the outage that happens at 03:00 and tells you when it started.
   </details>

4. **Why is the flow log created under `NetworkWatcherRG` rather than next to `prod-skycraft-swc-vnet` in `prod-skycraft-swc-rg`?**
   <details>
     <summary>**Click to see the answer**</summary>

   **Answer**: A flow log is a child resource of the regional Network Watcher, not of its target. Network Watcher is one Azure-provisioned instance per region, so every flow log and connection monitor in Sweden Central lives under `NetworkWatcher_swedencentral`, whichever VNet it records.
   </details>

---

## 📚 Additional Resources

- [Network Watcher Overview](https://learn.microsoft.com/en-us/azure/network-watcher/network-watcher-monitoring-overview)
- [IP Flow Verify Documentation](https://learn.microsoft.com/en-us/azure/network-watcher/network-watcher-ip-flow-verify-overview)
- [VNet Flow Logs](https://learn.microsoft.com/en-us/azure/network-watcher/vnet-flow-logs-overview)
- [Traffic Analytics](https://learn.microsoft.com/en-us/azure/network-watcher/traffic-analytics)
- [Connection Troubleshoot](https://learn.microsoft.com/en-us/azure/network-watcher/network-watcher-connectivity-overview)
- [Connection Monitor](https://learn.microsoft.com/en-us/azure/network-watcher/connection-monitor-overview)

---

## 📌 Module Navigation

[Lab 5.2 Business Continuity ←](../5.2-business-continuity/lab-guide-5.2.md) | [Back to Module 5 Index](../README.md)

---

## 📝 Lab Summary

**What You Accomplished:**

✅ Verified Network Watcher is enabled for Sweden Central
✅ Used IP Flow Verify to identify NSG rule behavior
✅ Checked routing with Next Hop diagnostic tool
✅ Generated network topology visualization
✅ Ran end-to-end Connection Troubleshooter between VMs
✅ Enabled a VNet flow log with Traffic Analytics on the production VNet
✅ Created a Connection Monitor probing hub-to-spoke SSH every 5 minutes

**Infrastructure Deployed:**

| Resource                         | Type                              | Resource Group    | Notes                                                                     |
| -------------------------------- | --------------------------------- | ----------------- | ------------------------------------------------------------------------- |
| `NetworkWatcher_swedencentral`   | Network Watcher                   | `NetworkWatcherRG` | Azure-provisioned per region; re-declared with the SkyCraft tags          |
| `prod-skycraft-swc-vnet-flowlog` | Flow log (VNet)                   | `NetworkWatcherRG` | Target `prod-skycraft-swc-vnet`, v2, 7-day retention, Traffic Analytics 10 min |
| `skycraft-hub-spoke-cm`          | Connection Monitor                | `NetworkWatcherRG` | `hub-spoke-ssh` → `tcp-22-every-5m`, output to `platform-skycraft-swc-law` |
| NetworkWatcherAgent              | VM extension on both endpoint VMs | `dev-skycraft-swc-rg` / `prod-skycraft-swc-rg` | Installed by `Deploy-Bicep.ps1`; removed by `Remove-LabResource.ps1` |

**Time Spent**: ~1.5 hours

**Congratulations!** You have completed Module 5: Monitor and Maintain Azure Resources.
