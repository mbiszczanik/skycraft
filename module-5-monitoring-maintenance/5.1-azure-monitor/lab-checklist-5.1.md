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

- [ ] VM Insights enabled for at least one VM (e.g., `dev-skycraft-vm`)
- [ ] Azure Monitor Agent (AMA) installed on the VM
- [ ] Data Collection Rule (DCR) `skycraft-vm-dcr` created and associated
- [ ] Syslog and Performance Counters being collected

---

## ✅ Alerts and Notifications

### Alert Rules

- [ ] Metric Alert: **Percentage CPU > 80%**
- [ ] Log Search Alert: (Optional) Heartbeat missing
- [ ] Action Group: `SkyCraft-Admins-Email` created
- [ ] Target email matches your account for testing

---

## 🔍 Validation Commands

### Verify Log Analytics Workspace Exists

```azurecli
# List LAW in primary resource group
az monitor log-analytics workspace list \
  --resource-group platform-skycraft-swc-rg \
  --query "[?name=='platform-skycraft-swc-law'].{Name:name,Location:location,Retention:retentionInDays}" \
  --output table
```

### Verify Heartbeat in LAW (Run in Portal)

```kusto
// Run this in LAW Logs blade
Heartbeat
| where TimeGenerated > ago(1h)
| summarize LastCall = max(TimeGenerated) by Computer, OSType, Version
```

### Verify Alert Rules

```azurecli
# List all metric alerts in the subscription
az monitor metrics alert list \
  --query "[].{Name:name,Enabled:enabled,Threshold:criteria.threshold}" \
  --output table
```

---

## 📊 Monitoring Summary

| Component        | Status | Verification Method             |
| :--------------- | :----- | :------------------------------ |
| **Central Logs** | [ ]    | LAW exists in Platform RG       |
| **VM Telemetry** | [ ]    | KQL query returns Heartbeat     |
| **CPU Alerts**   | [ ]    | Alert rule listed in Monitor    |
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
- [ ] Central dashboard created
- [ ] All reflection questions answered
- [ ] Ready to proceed to Lab 5.2

**Student Name**: ******\_\_\_\_******
**Lab 5.1 Completion Date**: ******\_\_\_\_******
