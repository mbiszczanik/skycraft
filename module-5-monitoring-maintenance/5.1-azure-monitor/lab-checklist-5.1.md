# Lab 5.1 Completion Checklist

> **Purpose**: This checklist verifies correct implementation of Lab 5.1: Azure Monitor and Insights. Use it to confirm all resources are properly configured before proceeding to Lab 5.2.

---

## ✅ Log Analytics Workspace (platform-skycraft-swc-law)

### Workspace Configuration

- [ ] Workspace name: `platform-skycraft-swc-law`
- [ ] Location: **Sweden Central**
- [ ] Resource group: `platform-skycraft-swc-rg`
- [ ] Retention period: **30 days** (minimum)

---

## ✅ VM Monitoring (AMA Agent)

### Data Collection

- [ ] Data Collection Rule (DCR) `skycraft-vm-dcr` created and associated with at least one VM (e.g., `dev-skycraft-swc-auth-vm`)
- [ ] Azure Monitor Agent `AzureMonitorLinuxAgent` on that VM: **Provisioning succeeded**, tagged `Project = SkyCraft`
- [ ] Performance counters (`Perf` table) and Syslog being collected
- [ ] `Heartbeat` rows from the VM in the last 15 minutes

---

## ✅ Alerts and Notifications

### Alert Rules

- [ ] Metric Alert: **Percentage CPU > 80%**
- [ ] Log Search Alert `skycraft-heartbeat-alert`: query `Heartbeat` on the monitored VM, **Count Less than 1** over 5 minutes, enabled, notifies `skycraft-ops-ag`
- [ ] Action Group: `skycraft-ops-ag` created (short name `SkyCraftOps`), region **Global**, tagged `Project = SkyCraft`
- [ ] Target email matches your account for testing, and its verification e-mail is confirmed
- [ ] Dashboard `SkyCraft-Ops` (Private) shows the CPU chart from Step 5.1.6

---

## 🔍 Validation Commands

### Verify Log Analytics Workspace Exists

```powershell
# Show the LAW in the platform resource group
Get-AzOperationalInsightsWorkspace -ResourceGroupName platform-skycraft-swc-rg -Name platform-skycraft-swc-law |
    Select-Object Name, Location, @{N='Retention';E={$_.RetentionInDays}} |
    Format-Table -AutoSize
```

### Verify the Azure Monitor Agent

```powershell
# Provisioning state and Project tag of the agent on the monitored VM
$vm = Get-AzVM -ResourceGroupName dev-skycraft-swc-rg -Name dev-skycraft-swc-auth-vm
Get-AzResource -ResourceId "$($vm.Id)/extensions/AzureMonitorLinuxAgent" |
    Select-Object Name, @{N='State';E={$_.Properties.provisioningState}}, @{N='Project';E={$_.Tags.Project}}
```

### Verify Heartbeat and Perf in LAW (Run in Portal)

```kusto
// Run this in LAW Logs blade
Heartbeat
| where TimeGenerated > ago(1h)
| summarize LastCall = max(TimeGenerated) by Computer, OSType, Version
```

```kusto
// Rows only when the rule sends Performance Counters to Azure Monitor Logs
Perf
| where TimeGenerated > ago(1h) and CounterName == "% Processor Time"
| summarize Samples = count() by Computer
```

### Verify Alert Rules

```powershell
# The lab's alert rule, by name, in the platform resource group
Get-AzMetricAlertRuleV2 -ResourceGroupName platform-skycraft-swc-rg -Name skycraft-cpu-alert |
    Select-Object Name, Enabled, Severity, @{N='Window';E={$_.WindowSize}}, @{N='Every';E={$_.EvaluationFrequency}},
        @{N='Threshold';E={$_.Criteria[0].Threshold}} |
    Format-Table -AutoSize
```

### Verify the Log Search Alert

```powershell
# The Heartbeat rule, its scope, condition and action group
$rule = Get-AzResource -ResourceGroupName platform-skycraft-swc-rg -ResourceType Microsoft.Insights/scheduledQueryRules `
    -Name skycraft-heartbeat-alert -ExpandProperties
$rule.Properties.criteria.allOf | Select-Object query, timeAggregation, operator, threshold
$rule.Properties | Select-Object enabled, severity, windowSize, @{N='Scope';E={$_.scopes -join ', '}},
    @{N='ActionGroups';E={($_.actions.actionGroups | ForEach-Object { ($_ -split '/')[-1] }) -join ', '}}
```

### Verify the Storage Diagnostic Setting

```powershell
$sa = Get-AzStorageAccount -ResourceGroupName platform-skycraft-swc-rg -Name platformskycraftswcsa
Get-AzDiagnosticSetting -ResourceId "$($sa.Id)/blobServices/default" -Name skycraft-storage-diag |
    Select-Object @{N='Workspace';E={$_.WorkspaceId}}, @{N='Logs';E={($_.Log | Where-Object Enabled).Category -join ', '}}
```

---

## 📊 Monitoring Summary

| Component        | Status | Verification Method             |
| :--------------- | :----- | :------------------------------ |
| **Central Logs** | [ ]    | LAW exists in Platform RG       |
| **VM Telemetry** | [ ]    | KQL returns Heartbeat and Perf  |
| **CPU Alerts**   | [ ]    | Alert rule listed in Monitor    |
| **Heartbeat Alert** | [ ] | Log search rule listed in Monitor |
| **Dashboard**    | [ ]    | Ops Dashboard visible in Portal |

---

## 📝 Reflection Questions

### Question 1: Metrics vs. Logs

**In which scenario would you prefer Metrics over Logs for alerting?**

---

### Question 2: Cost Management

**How does the amount of data ingested affect the cost of Log Analytics?**

---

### Question 3: Real-Time vs. Latency

**What is the typical ingestion latency for Azure Monitor Logs, and why does this matter for critical alerts?**

---

---

## ✅ Final Lab 5.1 Sign-off

**All Verification Items Complete**:

- [ ] Log Analytics Workspace correctly deployed
- [ ] AMA Agent active and reporting to LAW
- [ ] CPU Threshold alert configured
- [ ] Missing-Heartbeat log search alert configured
- [ ] Central dashboard created
- [ ] All reflection questions answered
- [ ] Ready to proceed to Lab 5.2

**Student Name**: ******\_\_\_\_******
**Lab 5.1 Completion Date**: ******\_\_\_\_******
