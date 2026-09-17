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

- [ ] VM Insights enabled for at least one VM (e.g., `dev-skycraft-swc-auth-vm`)
- [ ] Azure Monitor Agent (AMA) installed on the VM
- [ ] Data Collection Rule (DCR) `skycraft-vm-dcr` created and associated
- [ ] Syslog and Performance Counters being collected

---

## ✅ Alerts and Notifications

### Alert Rules

- [ ] Metric Alert `skycraft-cpu-alert` in `platform-skycraft-swc-rg`: **Percentage CPU > 80%**, enabled, severity **2 (Warning)**, window **5 minutes**, evaluated every **1 minute**
- [ ] Log Search Alert: (Optional) Heartbeat missing
- [ ] Action Group: `skycraft-ops-ag` created (short name `SkyCraftOps`), enabled, at least one email receiver
- [ ] Target email matches your account for testing

### Storage Diagnostics

- [ ] Diagnostic setting `skycraft-storage-diag` on the **blob service** of `platformskycraftswcsa`
- [ ] Categories `StorageRead` and `StorageWrite` enabled, destination `platform-skycraft-swc-law`

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
# The lab's alert rule, by name, in the platform resource group
az monitor metrics alert show \
  --name skycraft-cpu-alert \
  --resource-group platform-skycraft-swc-rg \
  --query "{Name:name,Enabled:enabled,Severity:severity,Window:windowSize,Every:evaluationFrequency,Threshold:criteria.allOf[0].threshold}" \
  --output table
```

### Verify the Storage Diagnostic Setting

```azurecli
SA=$(az storage account show -g platform-skycraft-swc-rg -n platformskycraftswcsa --query id -o tsv)
az monitor diagnostic-settings show \
  --name skycraft-storage-diag \
  --resource "$SA/blobServices/default" \
  --query "{Workspace:workspaceId, Logs:logs[?enabled].category}" \
  --output json
```

---

## 📊 Monitoring Summary

| Component        | Status | Verification Method             |
| :--------------- | :----- | :------------------------------ |
| **Central Logs** | [ ]    | LAW exists in Platform RG       |
| **VM Telemetry** | [ ]    | KQL query returns Heartbeat     |
| **CPU Alerts**   | [ ]    | `skycraft-cpu-alert` listed in Monitor |
| **Storage Logs** | [ ]    | `skycraft-storage-diag` on the blob service |
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
- [ ] CPU Threshold alert `skycraft-cpu-alert` configured
- [ ] Storage diagnostic setting `skycraft-storage-diag` streaming to the workspace
- [ ] Central dashboard created
- [ ] All reflection questions answered
- [ ] Ready to proceed to Lab 5.2

**Student Name**: ******\_\_\_\_******
**Lab 5.1 Completion Date**: ******\_\_\_\_******
