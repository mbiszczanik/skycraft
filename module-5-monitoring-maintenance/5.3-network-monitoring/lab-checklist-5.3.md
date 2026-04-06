# Lab 5.3 Completion Checklist

> **Purpose**: This checklist verifies correct implementation of Lab 5.3: Network Monitoring & Diagnostics. Use it to confirm all diagnostic tools have been used and Flow Logs are properly configured.

---

## ✅ Network Watcher Verification

### Regional Setup

- [ ] Network Watcher enabled for **Sweden Central**
- [ ] Resource group: `NetworkWatcherRG`
- [ ] Provisioning state: **Succeeded**

---

## ✅ IP Flow Verify Verification

### Inbound Test

- [ ] Tested inbound TCP traffic on port **8080** to `dev-skycraft-swc-auth-vm`
- [ ] Result recorded: **Allow** / **Deny** (circle one)
- [ ] NSG rule identified: ******\_\_******

### Outbound Test

- [ ] Tested outbound traffic to `8.8.8.8` on port **53** (DNS)
- [ ] Result: **Allow** confirmed

---

## ✅ Next Hop Verification

### External Routing

- [ ] Next hop for destination `1.1.1.1`: **Internet**
- [ ] Route table source: **System Route**

### Internal Routing (Hub ↔ Spoke)

- [ ] Next hop for Hub VNet IP (`10.0.x.x`): **VNetPeering** or **VirtualNetwork**

---

## ✅ Network Topology Verification

- [ ] Topology generated for `dev-skycraft-swc-rg`
- [ ] Diagram shows VNets, subnets, NICs, and NSGs
- [ ] Peering connections visible to Hub VNet

---

## ✅ Connection Troubleshooter Verification

- [ ] Source: `prod-skycraft-swc-auth-vm`
- [ ] Destination: Private IP of `dev-skycraft-swc-auth-vm`
- [ ] Port: **22** (SSH)
- [ ] Result: **Reachable**
- [ ] Hop-by-hop breakdown obtained

---

## ✅ VNet Flow Logs Verification

### Flow Log Configuration

- [ ] Flow Log name: `prod-skycraft-swc-vnet-flowlog`
- [ ] VNet: `prod-skycraft-swc-vnet`
- [ ] Storage account: `platformskycraftswcsa`
- [ ] Version: **2**
- [ ] Retention: **7 days**
- [ ] Flow Log status: **Enabled**

### Traffic Analytics (Optional)

- [ ] Traffic Analytics enabled
- [ ] Workspace: `platform-skycraft-swc-law`
- [ ] Processing interval: **10 minutes**

---

## ✅ Connection Monitor Verification

### Monitor Configuration

- [ ] Connection Monitor name: `skycraft-hub-spoke-cm`
- [ ] Location: **Sweden Central**
- [ ] Resource group: `NetworkWatcherRG`
- [ ] Monitoring status: **Running**

### Test Group

- [ ] Test group name: `hub-spoke-ssh`
- [ ] Protocol: **TCP**, Port: **22**
- [ ] Test frequency: **Every 5 minutes** (300 seconds)
- [ ] Source: `prod-skycraft-swc-auth-vm`
- [ ] Destination: `dev-skycraft-swc-auth-vm` (IP: `10.1.1.4`)

### Output

- [ ] Log Analytics workspace linked: `platform-skycraft-swc-law`

### Tags

- [ ] Tag: `Project` = `SkyCraft`
- [ ] Tag: `Environment` = `Production`
- [ ] Tag: `CostCenter` = `MSDN`

---

## 🔍 Validation Commands

Run these commands to validate your lab setup:

### Verify Network Watcher Status (Azure CLI)

```azurecli
# Check if Network Watcher is enabled
az network watcher list \
  --query "[?location=='swedencentral'].{Name:name,Region:location,State:provisioningState}" \
  --output table

# Expected output:
# Name                             Region          State
# -------------------------------  --------------  ---------
# NetworkWatcher_swedencentral     swedencentral   Succeeded
```

### Verify Network Watcher Status (PowerShell)

```powershell
Get-AzNetworkWatcher |
  Where-Object { $_.Location -eq 'swedencentral' } |
  Select-Object Name, Location, ProvisioningState |
  Format-Table

# Expected output:
# Name                             Location        ProvisioningState
# ----                             --------        -----------------
# NetworkWatcher_swedencentral     swedencentral   Succeeded
```

### Run IP Flow Verify (Azure CLI)

```azurecli
# Check inbound port 8080
az network watcher test-ip-flow \
  --vm dev-skycraft-swc-auth-vm \
  --resource-group dev-skycraft-swc-rg \
  --direction Inbound \
  --protocol TCP \
  --local "*:8080" \
  --remote "8.8.8.8:443"

# Expected output:
# {
#   "access": "Allow" or "Deny",
#   "ruleName": "<NSG-rule-name>"
# }
```

### Run IP Flow Verify (PowerShell)

```powershell
$vm = Get-AzVM -ResourceGroupName 'dev-skycraft-swc-rg' -Name 'dev-skycraft-swc-auth-vm'
$nw = Get-AzNetworkWatcher | Where-Object { $_.Location -eq 'swedencentral' }

Test-AzNetworkWatcherIPFlow `
    -NetworkWatcher $nw `
    -TargetVirtualMachineId $vm.Id `
    -Direction Inbound `
    -Protocol TCP `
    -LocalPort 8080 `
    -RemoteIPAddress '8.8.8.8' `
    -RemotePort 443

# Expected output:
# Access   : Allow/Deny
# RuleName : <NSG-rule-name>
```

### Verify VNet Flow Logs (Azure CLI)

```azurecli
# List flow logs
az network watcher flow-log list \
  --location swedencentral \
  --query "[?contains(name,'prod')].{Name:name,Enabled:enabled,StorageId:storageId}" \
  --output table

# Expected output:
# Name                            Enabled  StorageId
# ------------------------------  -------  ---------
# prod-skycraft-swc-vnet-flowlog  True     /subscriptions/.../platformskycraftswcsa
```

### Verify VNet Flow Logs (PowerShell)

```powershell
$nw = Get-AzNetworkWatcher | Where-Object { $_.Location -eq 'swedencentral' }

Get-AzNetworkWatcherFlowLog -NetworkWatcher $nw |
  Where-Object { $_.Name -like '*prod*' } |
  Select-Object Name, Enabled, @{N='Version';E={$_.Format.Version}}, RetentionInDays |
  Format-Table

# Expected output:
# Name                            Enabled  Version  RetentionInDays
# ----                            -------  -------  ---------------
# prod-skycraft-swc-vnet-flowlog  True     2        7
```

### Connectivity Test (PowerShell)

```powershell
# Test SSH connectivity from local machine to prod VM (if public IP exists)
Test-NetConnection -ComputerName <prod-vm-public-ip> -Port 22

# Expected: TcpTestSucceeded = True (if Bastion or public IP is configured)
```

### Verify Connection Monitor (Azure CLI)

```azurecli
az network watcher connection-monitor show \
  --name skycraft-hub-spoke-cm \
  --location swedencentral \
  --query "{Name:name,Status:monitoringStatus,AutoStart:autoStart}" \
  --output table

# Expected output:
# Name                   Status   AutoStart
# ---------------------  -------  ---------
# skycraft-hub-spoke-cm  Running  True
```

### Verify Connection Monitor (PowerShell)

```powershell
$nw = Get-AzNetworkWatcher | Where-Object { $_.Location -eq 'swedencentral' }

Get-AzNetworkWatcherConnectionMonitor -NetworkWatcher $nw |
  Where-Object { $_.Name -eq 'skycraft-hub-spoke-cm' } |
  Select-Object Name, MonitoringStatus, AutoStart |
  Format-Table

# Expected output:
# Name                   MonitoringStatus  AutoStart
# ----                   ----------------  ---------
# skycraft-hub-spoke-cm  Running           True
```

---

## 📊 Network Diagnostic Summary

| Tool                        | Tested? | Key Finding                         |
| :-------------------------- | :------ | :---------------------------------- |
| **IP Flow Verify**          | [ ]     | NSG rule: ******\_\_******          |
| **Next Hop (External)**     | [ ]     | Next hop type: **Internet**         |
| **Next Hop (Internal)**     | [ ]     | Next hop type: **VNetPeering**      |
| **Topology**                | [ ]     | Hub-Spoke layout visually confirmed |
| **Connection Troubleshoot** | [ ]     | Prod → Dev: **Reachable**           |
| **VNet Flow Logs**           | [ ]     | Enabled on VNet with Version 2  |

---

## 📊 Infrastructure Deployed Summary

| Resource | Name | Configuration | Status |
| :--- | :--- | :--- | :--- |
| Connection Monitor | `skycraft-hub-spoke-cm` | TCP/22, 5-min interval, prod→dev | ☐ |
| VNet Flow Log | `prod-skycraft-swc-vnet-flowlog` | Version 2, 7-day retention, enabled | ☐ |
| Traffic Analytics | Via `platform-skycraft-swc-law` | 10-min processing interval | ☐ |

---

## 📝 Reflection Questions

### Question 1: NSG Rule Documentation

**Document the NSG rule that governs inbound traffic on port 8080:**

| Property    | Value        |
| ----------- | ------------ |
| Rule name   | ****\_\_**** |
| Priority    | ****\_\_**** |
| Action      | ****\_\_**** |
| Source      | ****\_\_**** |
| Destination | ****\_\_**** |

### Question 2: Troubleshooting Experience

**What was the most challenging diagnostic you ran? What unexpected result did you encounter, if any?**

---

---

### Question 3: Flow Log Analysis

**If you enabled Traffic Analytics, what traffic patterns did you observe? If not, describe what insights you would expect from analyzing flow logs for a game server infrastructure.**

---

---

**Instructor Review Date**: **\_\_\_\_**
**Feedback**: ******************\_\_\_\_******************

---

## ⏱️ Completion Tracking

- **Estimated Time**: 2 hours
- **Actual Time Spent**: **\_\_\_\_** hours
- **Date Started**: **\_\_\_\_**
- **Date Completed**: **\_\_\_\_**

**Challenges Encountered** (optional):

---

## ✅ Final Lab 5.3 Sign-off

**All Verification Items Complete**:

- [ ] All diagnostic tools used and results documented
- [ ] VNet Flow Logs enabled on production VNet
- [ ] All validation commands executed successfully
- [ ] All reflection questions answered
- [ ] Module 5 complete — ready for Capstone Project

**Student Name**: ******\_\_\_\_******
**Lab 5.3 Completion Date**: ******\_\_\_\_******
**Instructor Signature**: ******\_\_\_\_******

---

## 🎉 Congratulations!

You've successfully completed **Lab 5.3: Network Monitoring & Diagnostics** and the entire **Module 5: Monitor and Maintain Azure Resources**!

**What You Built**:

- ✅ Comprehensive network diagnostics using IP Flow Verify, Next Hop, and Connection Troubleshooter
- ✅ Visual network topology for infrastructure documentation
- ✅ VNet Flow Logs with Traffic Analytics for ongoing traffic analysis

**Module 5 Complete!** You now have monitoring, backup, disaster recovery, and network diagnostics for the entire SkyCraft infrastructure. Proceed to the **Capstone Project** to deploy everything from scratch.

---

## 📌 Module Navigation

- [← Back to Module 5 Index](../README.md)
- [← Lab 5.2: Business Continuity](../5.2-business-continuity/lab-guide-5.2.md)
