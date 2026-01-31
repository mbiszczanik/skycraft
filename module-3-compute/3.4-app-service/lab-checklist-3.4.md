# Lab 3.4 Completion Checklist

## ✅ App Service Plan Verification

### Configuration

- [ ] Name: `dev-skycraft-swc-asp`
- [ ] Resource group: `dev-skycraft-swc-rg`
- [ ] Location: **Sweden Central**
- [ ] Operating System: **Linux**
- [ ] Pricing Tier: **Premium V4 P0V4** (Verification: check "Overview" blade)
- [ ] Status: **Ready**

### Scaling

- [ ] Scale Out Rule: **CPU > 70%** (Increase by 1)
- [ ] Scale In Rule: **CPU < 30%** (Decrease by 1)
- [ ] Instance Limits: **Min: 1**, **Max: 3**

---

## ✅ Web App Verification

### Configuration

- [ ] Name: `dev-skycraft-swc-app01` (globally unique)
- [ ] Runtime Stack: **Node 18 LTS** (or newer)
- [ ] Plan: `dev-skycraft-swc-asp`
- [ ] Health Check: **Enabled** (if configured, otherwise optional)
- [ ] HTTPS Only: **On**

### Deployment Slots

- [ ] Slot `staging` exists
- [ ] **Production** URL displays "Version 2.0" (Post-swap state)
- [ ] **Staging** URL displays "Version 1.0" (Post-swap state)

### Networking

- [ ] VNet Integration Status: **Connected**
- [ ] VNet: `dev-skycraft-swc-vnet`
- [ ] Subnet: `AppServiceSubnet` (10.1.4.0/24)

---

## 🔍 Validation Commands

Run these Azure CLI commands to validate your lab setup:

### Login and Set Context

```azurecli
# Login to Azure
az login

# Set subscription context
az account set --subscription "YOUR-SUBSCRIPTION-NAME"
```

### Verify App Service Plan

```azurecli
# Check Plan Details
az appservice plan show \
  --name dev-skycraft-swc-asp \
  --resource-group dev-skycraft-swc-rg \
  --query "{Name:name, Location:location, SKU:sku.name, Status:status}" \
  --output table

# Expected Output:
# Name                  Location        SKU    Status
# --------------------  --------------  -----  --------
# dev-skycraft-swc-asp  Sweden Central  P0V4   Ready
```

### Verify Web App & Slots

```azurecli
# List Web Apps and Slots
az webapp list \
  --resource-group dev-skycraft-swc-rg \
  --query "[].{Name:name, State:state, Hostnames:defaultHostName}" \
  --output table

# Check Deployment Slots
az webapp deployment slot list \
  --name dev-skycraft-swc-app01 \
  --resource-group dev-skycraft-swc-rg \
  --query "[].{Name:name, State:state}" \
  --output table
```

### Verify Autoscale Settings

```azurecli
# List Autoscale Settings
az monitor autoscale list \
  --resource-group dev-skycraft-swc-rg \
  --query "[].{Name:name, Profiles:profiles[0].name, Rules:length(profiles[0].rules)}" \
  --output table
```

---

## 📊 App Service Architecture Summary

| Component            | Name                   | Details                  | Status |
| -------------------- | ---------------------- | ------------------------ | ------ |
| **App Service Plan** | dev-skycraft-swc-asp   | Linux, Premium V4 P0V4   | ✅     |
| **Web App (Prod)**   | dev-skycraft-swc-app01 | Node.js, VNet Integrated | ✅     |
| **Slot (Staging)**   | .../slots/staging      | Deployment Target        | ✅     |
| **Autoscale**        | Default-Autoscale      | 1-3 Instances            | ✅     |

---

## 📝 Reflection Questions

### Question 1: Deployment Slots

**Describe a scenario where a deployment swap might fail or cause issues in production?**

---

---

### Question 2: Scaling Strategy

**If SkyCraft suddenly had 10,000 users, would the current scaling rules (Max 3 instances) be sufficient? How would you modify the Plan and Rules?**

---

---

### Question 3: VNet Integration

**Why did we need to delegate a specific subnet for VNet Integration? Could we have used the same subnet as the VMs?**

---

**Instructor Review Date**: \***\*\_\*\***  
**Feedback**: **************\*\*\*\***************\_**************\*\*\*\***************

---

## ⏱️ Completion Tracking

- **Estimated Time**: 2 hours
- **Actual Time Spent**: \***\*\_\*\*** hours
- **Date Started**: \***\*\_\*\***
- **Date Completed**: \***\*\_\*\***

**Challenges Encountered** (optional):

---

---

## ✅ Final Lab 3.4 Sign-off

**All Verification Items Complete**:

- [ ] App Service Plan configured correctly
- [ ] Web App deployed and secured
- [ ] Deployment Slots working
- [ ] Auto-scaling rules active
- [ ] VNet Integration verified
- [ ] Validation commands run successfully
- [ ] Reflection questions answered

**Student Name**: **\*\*\*\***\_**\*\*\*\***  
**Lab 3.4 Completion Date**: **\*\*\*\***\_**\*\*\*\***  
**Instructor Signature**: **\*\*\*\***\_**\*\*\*\***

---

## 🎉 Congratulations!

You've successfully completed **Lab 3.4: Create and Configure Azure App Service**!

**What You Built**:

- ✅ A scalable, managed web hosting environment
- ✅ A "Blue-Green" deployment pipeline using Slots
- ✅ A secure connection bridge between Web and Internal Network

**Next**: [Module 4 - Storage](../module-4-storage/README.md) ->

---

## 📌 Module Navigation

- [← Back to Module 3 Index](../README.md)
- [Module 4: Storage Accounts →](../module-4-storage/README.md)
