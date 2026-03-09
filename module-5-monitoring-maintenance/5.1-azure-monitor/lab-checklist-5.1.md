# Lab 5.1 Completion Checklist

> **Purpose**: This checklist verifies correct implementation of Lab 5.1: Azure Monitor and Insights. Use it to confirm all resources are properly configured before proceeding to Lab 5.2.

---

## ✅ Log Analytics Workspace Verification

### Workspace Configuration

- [ ] Workspace name: `platform-skycraft-swc-law`
- [ ] Location: **Sweden Central**
- [ ] Resource group: `platform-skycraft-swc-rg`
- [ ] Retention period: **30 days**

### Tags

- [ ] Tag: `Project` = `SkyCraft`
- [ ] Tag: `Environment` = `Platform`
- [ ] Tag: `CostCenter` = `MSDN`

---

## ✅ VM Monitoring Verification

### Azure Monitor Agent (AMA)

- [ ] AMA extension installed on at least one VM (e.g., `dev-skycraft-swc-auth-vm`)
- [ ] Extension provisioning state: **Succeeded**
- [ ] Extension auto-upgrade: **Enabled**

### Data Collection Rule (DCR)

- [ ] DCR name: `skycraft-vm-dcr`
- [ ] Associated with target VM(s)
- [ ] Performance Counters collection: **Enabled**
- [ ] Syslog collection: **Enabled**
- [ ] Destination workspace: `platform-skycraft-swc-law`

### VM Insights

- [ ] VM status in Monitor → Virtual Machines: **Monitored**
- [ ] Heartbeat data visible in Log Analytics (within 15 minutes of enabling)

---

## ✅ Alert Configuration Verification

### Action Group

- [ ] Action Group name: `skycraft-ops-ag`
- [ ] Resource group: `platform-skycraft-swc-rg`
- [ ] Display name: `SkyCraft Ops`
- [ ] Email notification configured with valid email address

### Metric Alert Rule

- [ ] Alert name: `skycraft-cpu-alert`
- [ ] Metric: **Percentage CPU**
- [ ] Operator: **Greater than**
- [ ] Threshold: **80**
- [ ] Check every: **1 minute**
- [ ] Lookback period: **5 minutes**
- [ ] Severity: **Sev 2 - Warning**
- [ ] Action Group: `skycraft-ops-ag` linked
- [ ] Alert rule status: **Enabled**

---

## ✅ Dashboard Verification

- [ ] Dashboard name: `SkyCraft-Ops`
- [ ] Contains CPU performance chart (pinned from KQL)
- [ ] Contains memory performance chart (pinned from KQL)

---

## ✅ Storage Diagnostics Verification

- [ ] Diagnostic setting created for at least one storage account
- [ ] Logs sent to: `platform-skycraft-swc-law`

---

## 🔍 Validation Commands

Run these commands to validate your lab setup:

### Verify Log Analytics Workspace (Azure CLI)

```azurecli
# List LAW in platform resource group
az monitor log-analytics workspace list \
  --resource-group platform-skycraft-swc-rg \
  --query "[?name=='platform-skycraft-swc-law'].{Name:name,Location:location,Retention:retentionInDays,State:provisioningState}" \
  --output table

# Expected output:
# Name                        Location        Retention  State
# --------------------------  --------------  ---------  ---------
# platform-skycraft-swc-law   swedencentral   30         Succeeded
```

### Verify Log Analytics Workspace (PowerShell)

```powershell
Get-AzOperationalInsightsWorkspace -ResourceGroupName 'platform-skycraft-swc-rg' |
  Where-Object { $_.Name -eq 'platform-skycraft-swc-law' } |
  Select-Object Name, Location, @{N='Retention';E={$_.RetentionInDays}}, ProvisioningState |
  Format-Table

# Expected output:
# Name                        Location        Retention  ProvisioningState
# ----                        --------        ---------  -----------------
# platform-skycraft-swc-law   swedencentral   30         Succeeded
```

### Verify AMA Extension on VM (Azure CLI)

```azurecli
# Check AMA extension status
az vm extension list \
  --resource-group dev-skycraft-swc-rg \
  --vm-name dev-skycraft-swc-auth-vm \
  --query "[?contains(name,'AzureMonitor')].{Name:name,Status:provisioningState,AutoUpgrade:enableAutomaticUpgrade}" \
  --output table

# Expected output:
# Name                     Status     AutoUpgrade
# -----------------------  ---------  -----------
# AzureMonitorLinuxAgent   Succeeded  True
```

### Verify AMA Extension on VM (PowerShell)

```powershell
Get-AzVMExtension -ResourceGroupName 'dev-skycraft-swc-rg' -VMName 'dev-skycraft-swc-auth-vm' |
  Where-Object { $_.Name -like '*AzureMonitor*' } |
  Select-Object Name, ProvisioningState, EnableAutomaticUpgrade |
  Format-Table

# Expected output:
# Name                     ProvisioningState  EnableAutomaticUpgrade
# ----                     -----------------  ----------------------
# AzureMonitorLinuxAgent   Succeeded          True
```

### Verify Alert Rules (Azure CLI)

```azurecli
# List metric alerts
az monitor metrics alert list \
  --resource-group platform-skycraft-swc-rg \
  --query "[?name=='skycraft-cpu-alert'].{Name:name,Enabled:enabled,Severity:severity}" \
  --output table

# Expected output:
# Name                Enabled  Severity
# ------------------  -------  --------
# skycraft-cpu-alert  True     2
```

### Verify Alert Rules (PowerShell)

```powershell
Get-AzMetricAlertRuleV2 -ResourceGroupName 'platform-skycraft-swc-rg' |
  Where-Object { $_.Name -eq 'skycraft-cpu-alert' } |
  Select-Object Name, Enabled, Severity |
  Format-Table

# Expected output:
# Name                Enabled  Severity
# ----                -------  --------
# skycraft-cpu-alert  True     2
```

### Verify Heartbeat in LAW (KQL — Run in Portal)

```kusto
// Run this in LAW Logs blade
Heartbeat
| where TimeGenerated > ago(1h)
| summarize LastCall = max(TimeGenerated) by Computer, OSType, Version
| order by LastCall desc

// Expected: At least one row per connected VM
```

### Verify Action Group (Azure CLI)

```azurecli
az monitor action-group list \
  --resource-group platform-skycraft-swc-rg \
  --query "[?name=='skycraft-ops-ag'].{Name:name,ShortName:groupShortName,Enabled:enabled}" \
  --output table

# Expected output:
# Name              ShortName    Enabled
# ----------------  -----------  -------
# skycraft-ops-ag   SkyCraftOps  True
```

### Verify Action Group (PowerShell)

```powershell
Get-AzActionGroup -ResourceGroupName 'platform-skycraft-swc-rg' |
  Where-Object { $_.Name -eq 'skycraft-ops-ag' } |
  Select-Object Name, GroupShortName, Enabled |
  Format-Table

# Expected output:
# Name              GroupShortName  Enabled
# ----              --------------  -------
# skycraft-ops-ag   SkyCraftOps     True
```

---

## 📊 Monitoring Architecture Summary

| Component                | Name                        | Status | Verification Method              |
| :----------------------- | :-------------------------- | :----- | :------------------------------- |
| **Log Analytics WS**     | `platform-skycraft-swc-law` | [ ]    | CLI/PS workspace list            |
| **Data Collection Rule** | `skycraft-vm-dcr`           | [ ]    | Monitor → Data Collection Rules  |
| **VM Telemetry**         | AMA on dev/prod VMs         | [ ]    | KQL Heartbeat query returns data |
| **Action Group**         | `skycraft-ops-ag`           | [ ]    | CLI/PS action-group list         |
| **CPU Alert**            | `skycraft-cpu-alert`        | [ ]    | CLI/PS metric alert list         |
| **Dashboard**            | `SkyCraft-Ops`              | [ ]    | Visible in Portal → Dashboards   |
| **Storage Diagnostics**  | Diagnostic setting          | [ ]    | Storage → Diagnostic settings    |

---

## 📝 Reflection Questions

### Question 1: Workspace Topology

**Document the Log Analytics Workspace you created:**

| Property         | Value        |
| ---------------- | ------------ |
| Workspace name   | ****\_\_**** |
| Resource group   | ****\_\_**** |
| Location         | ****\_\_**** |
| Retention (days) | ****\_\_**** |
| Connected VMs    | ****\_\_**** |

### Question 2: Troubleshooting Experience

**What was the most challenging part of this lab? How did you resolve it?**

---

---

### Question 3: Alert Design

**If you needed to alert on "VM unreachable for more than 5 minutes", would you use a Metric Alert or a Log Search Alert? Describe how you would configure it.**

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

## ✅ Final Lab 5.1 Sign-off

**All Verification Items Complete**:

- [ ] All resources created with proper naming conventions
- [ ] All tags applied (Project, Environment, CostCenter)
- [ ] All validation commands executed successfully
- [ ] All reflection questions answered
- [ ] Ready to proceed to Lab 5.2

**Student Name**: ******\_\_\_\_******
**Lab 5.1 Completion Date**: ******\_\_\_\_******
**Instructor Signature**: ******\_\_\_\_******

---

## 🎉 Congratulations!

You've successfully completed **Lab 5.1: Azure Monitor and Insights**!

**What You Built**:

- ✅ Centralized Log Analytics Workspace for all SkyCraft telemetry
- ✅ VM monitoring with Azure Monitor Agent and Data Collection Rules
- ✅ Proactive alerting with CPU threshold monitoring and email notifications
- ✅ Operational dashboard for multi-resource visibility

**Next**: [Lab 5.2: Business Continuity & Disaster Recovery →](../5.2-business-continuity/lab-guide-5.2.md)

---

## 📌 Module Navigation

- [← Back to Module 5 Index](../README.md)
- [Lab 5.2: Business Continuity →](../5.2-business-continuity/lab-guide-5.2.md)
