# Lab 5.3 Completion Checklist

> **Purpose**: This checklist verifies correct implementation of Lab 5.3: Network Monitoring & Troubleshooting.

---

## ✅ Network Watcher Configuration

### Regional Setup

- [ ] Network Watcher enabled for **Sweden Central**
- [ ] Resource group `NetworkWatcherRG` exists and contains the regional instance `NetworkWatcher_swedencentral` (provisioning state **Succeeded**)

---

## ✅ Diagnostic Tool Usage

### IP Flow Verify

- [ ] Successful check for inbound traffic on port 80 (Allowed or Denied)
- [ ] Identification of the specific NSG rule governing the flow
- [ ] (Optional) Tested outbound traffic to `8.8.8.8` on port 53

### Next Hop

- [ ] Verified **Internet** as next hop for external IPs
- [ ] Verified **VNetPeering** or **VirtualNetwork** for internal cross-vnet traffic

---

## ✅ Connectivity & Topology

### Connection Troubleshooter

- [ ] Relationship between Hub and Spoke verified
- [ ] Hop-by-hop latency and status results obtained

### Topology

- [ ] Visual diagram of `dev-skycraft-swc-rg` generated
- [ ] Diagram accurately reflects subnets and VMs created in Modules 2-3

---

## ✅ VNet Flow Log (prod-skycraft-swc-vnet-flowlog)

- [ ] Flow log name: `prod-skycraft-swc-vnet-flowlog` (under `NetworkWatcher_swedencentral` in `NetworkWatcherRG`)
- [ ] Target resource: `prod-skycraft-swc-vnet`
- [ ] Status: **Enabled**
- [ ] Storage account: `platformskycraftswcsa`
- [ ] Format: JSON, **Version 2**
- [ ] Retention: **7 days**
- [ ] Traffic Analytics: **Enabled**, interval **10 minutes**, workspace `platform-skycraft-swc-law`
- [ ] Tags: `Project = SkyCraft`, `Environment = Production`, `CostCenter = MSDN`

---

## ✅ Connection Monitor (skycraft-hub-spoke-cm)

- [ ] Connection Monitor name: `skycraft-hub-spoke-cm` (under `NetworkWatcher_swedencentral` in `NetworkWatcherRG`)
- [ ] Monitoring status: **Running**
- [ ] Test group `hub-spoke-ssh`: source endpoint `prod-auth-source` (`prod-skycraft-swc-auth-vm`, or `dev-skycraft-swc-world-vm` when no prod VM exists) → destination endpoint `dev-auth-destination` (`dev-skycraft-swc-auth-vm`)
- [ ] Test configuration `tcp-22-every-5m`: **TCP** port **22**, every **300 seconds**, thresholds 10 % failed / 100 ms RTT
- [ ] Output workspace: `platform-skycraft-swc-law`
- [ ] NetworkWatcherAgent extension present on both endpoint VMs
- [ ] Tags: `Project = SkyCraft`, `Environment = Production`, `CostCenter = MSDN`

---

## 🔍 Validation Commands

### Verify Network Watcher Status

```azurecli
# Check if Network Watcher is enabled in the region
az network watcher list \
  --query "[?location=='swedencentral'].{Name:name,Region:location,ProvisioningState:provisioningState}" \
  --output table
```

### Run IP Flow Verify via CLI (Optional)

```azurecli
# Example CLI check
az network watcher test-ip-flow \
  --name dev-skycraft-swc-auth-vm \
  --resource-group dev-skycraft-swc-rg \
  --direction inbound \
  --protocol tcp \
  --local 8080 \
  --remote 8.8.8.8 \
  --remote-port 443
```

### Verify the Flow Log and the Connection Monitor

```azurecli
# Flow log: target, format version, retention, Traffic Analytics
az network watcher flow-log show \
  --name prod-skycraft-swc-vnet-flowlog \
  --location swedencentral \
  --query "{Target:targetResourceId, Enabled:enabled, Version:format.version, RetentionDays:retentionPolicy.days, TA:flowAnalyticsConfiguration.networkWatcherFlowAnalyticsConfiguration.enabled, Interval:flowAnalyticsConfiguration.networkWatcherFlowAnalyticsConfiguration.trafficAnalyticsInterval}" \
  --output table

# Connection monitor: state, test group, test configuration
az network watcher connection-monitor show \
  --name skycraft-hub-spoke-cm \
  --location swedencentral \
  --query "{State:monitoringStatus, Groups:testGroups[].name, Tests:testConfigurations[].{name:name, port:tcpConfiguration.port, freq:testFrequencySec}}" \
  --output json
```

```powershell
$nw = Get-AzNetworkWatcher -Location swedencentral
Get-AzNetworkWatcherFlowLog -NetworkWatcher $nw -Name prod-skycraft-swc-vnet-flowlog |
  Select-Object Name, Enabled, TargetResourceId, @{n='Version';e={$_.Format.Version}}, @{n='RetentionDays';e={$_.RetentionPolicy.Days}}

Get-AzNetworkWatcherConnectionMonitor -NetworkWatcher $nw -Name skycraft-hub-spoke-cm |
  Select-Object Name, MonitoringStatus, @{n='TestGroups';e={$_.TestGroups.Name -join ','}}

# Or run the lab's own validator - it asserts every item in this checklist by name
.\scripts\Test-Lab.ps1
```

---

## 📊 Network Diagnostic Summary

| Tool               | Checked? | Insight Gained                         |
| :----------------- | :------- | :------------------------------------- |
| **IP Flow Verify** | [ ]      | Confirmed NSG rules are working        |
| **Next Hop**       | [ ]      | Confirmed routing tables are correct   |
| **Topology**       | [ ]      | Verified visually the Hub-Spoke layout |
| **VNet flow log**  | [ ]      | Every prod flow recorded; Traffic Analytics maps them |
| **Connection Monitor** | [ ]  | Hub→spoke SSH probed every 5 min into Log Analytics |

---

## 📝 Reflection Questions

### Question 1: NSG Conflicts

**If a subnet NSG allows traffic but the NIC NSG denies it, what is the final result? How does IP Flow Verify help here?**

---

### Question 2: Hub-Spoke Visibility

**When looking at the Topology of a Spoke resource group, do you see resources in the Hub? Why or why not?**

---

---

## ✅ Final Lab 5.3 Sign-off

**All Verification Items Complete**:

- [ ] Network Watcher initialized
- [ ] Connectivity diagnostics performed
- [ ] Routing and Flow verification successful
- [ ] Network Topology visualized
- [ ] `prod-skycraft-swc-vnet-flowlog` enabled with Traffic Analytics
- [ ] `skycraft-hub-spoke-cm` running with test group `hub-spoke-ssh`
- [ ] Ready to conclude Module 5

**Student Name**: ******\_\_\_\_******
**Lab 5.3 Completion Date**: ******\_\_\_\_******
