# Lab 3.4 Completion Checklist

## ✅ App Service Plan Verification

### Configuration

- [ ] Name: `dev-skycraft-swc-asp`
- [ ] Resource group: `dev-skycraft-swc-rg`
- [ ] Location: **Sweden Central**
- [ ] Operating System: **Linux**
- [ ] Pricing Tier: **Premium V4 P0V4** (Verification: check "Overview" blade)
- [ ] Zone redundancy: **Disabled** (one instance)
- [ ] Tags: `Environment` = `Development`, `Project` = `SkyCraft`, `CostCenter` = `MSDN`, `Owner` = `mbiszczanik`
- [ ] Status: **Ready**

### Scaling

- [ ] An autoscale setting targets the plan (whatever its name: `Test-Lab.ps1` finds it through the plan)
- [ ] Scale Out Rule: **CPU > 70%** (Increase by 1)
- [ ] Scale In Rule: **CPU < 30%** (Decrease by 1)
- [ ] Instance Limits: **Min: 1**, **Max: 3**

---

## ✅ Web App Verification

### Configuration

- [ ] Name: `dev-skycraft-swc-app01` (or the name you chose in Step 3.4.2)
- [ ] Default domain: `dev-skycraft-swc-app01-<16 characters>.swedencentral-01.azurewebsites.net` (secure unique default hostname)
- [ ] Runtime Stack: **Node 22 LTS**
- [ ] Startup Command: `pm2 serve /home/site/wwwroot --no-daemon`
- [ ] Plan: `dev-skycraft-swc-asp`
- [ ] HTTPS Only: **On**, Minimum Inbound TLS Version: **1.2**
- [ ] Application Insights: **not enabled** (Step 3.4.2)
- [ ] Backups: automatic backups listed, **Every 1 hour** (no custom backup)

### Deployment Slots

- [ ] Slot `staging` exists and is **Running**, with Node 22 LTS and the same startup command
- [ ] **Production** URL displays "Version 2.0" (Post-swap state)
- [ ] **Staging** URL displays "Version 1.0" (Post-swap state)

### Networking

- [ ] VNet Integration Status: **Connected**, on the app and on the `staging` slot
- [ ] VNet: `dev-skycraft-swc-vnet`
- [ ] Subnet: `AppServiceSubnet` (10.1.4.0/24)
- [ ] Outbound internet traffic: routed through the VNet (checked), on the app and on the `staging` slot (Step 3.4.10)

---

## 🔍 Validation Commands

Run these Az PowerShell commands to validate your lab setup:

### Login and Set Context

```powershell
# Login to Azure
Connect-AzAccount

# Set subscription context
Set-AzContext -SubscriptionName "YOUR-SUBSCRIPTION-NAME"
```

### Verify App Service Plan

```powershell
# Check plan details
Get-AzAppServicePlan -ResourceGroupName dev-skycraft-swc-rg -Name dev-skycraft-swc-asp |
    Select-Object Name, Location, @{N='SKU';E={$_.Sku.Name}}, Status |
    Format-Table -AutoSize

# Expected Output:
# Name                  Location        SKU    Status
# ----                  --------        ---    ------
# dev-skycraft-swc-asp  Sweden Central  P0V4   Ready
```

### Verify Web App & Slots

```powershell
# The app: state, address, HTTPS only, runtime and startup command
Get-AzWebApp -ResourceGroupName dev-skycraft-swc-rg -Name dev-skycraft-swc-app01 |
    Select-Object Name, State, DefaultHostName, HttpsOnly,
        @{N='Runtime';E={$_.SiteConfig.LinuxFxVersion}},
        @{N='StartupCommand';E={$_.SiteConfig.AppCommandLine}} |
    Format-List

# Expected: Runtime NODE|22-lts, StartupCommand pm2 serve /home/site/wwwroot --no-daemon

# The staging slot: the same runtime and startup command
Get-AzWebAppSlot -ResourceGroupName dev-skycraft-swc-rg -Name dev-skycraft-swc-app01 -Slot staging |
    Select-Object Name, State, DefaultHostName,
        @{N='Runtime';E={$_.SiteConfig.LinuxFxVersion}},
        @{N='StartupCommand';E={$_.SiteConfig.AppCommandLine}} |
    Format-List
```

### Verify Autoscale Settings

```powershell
# The autoscale setting is found through the plan it scales, whatever its name
$plan = Get-AzAppServicePlan -ResourceGroupName dev-skycraft-swc-rg -Name dev-skycraft-swc-asp
Get-AzAutoscaleSetting -ResourceGroupName dev-skycraft-swc-rg |
    Where-Object { $_.TargetResourceUri -eq $plan.Id } |
    Select-Object Name, TargetResourceUri |
    Format-List
```

### Run the Lab Validator

```powershell
# Checks the plan, the app and the slot (state, runtime, startup command, HTTPS only, VNet
# integration and its outbound routing) and the autoscale setting; exits 0 when everything passes
.\scripts\Test-Lab.ps1
```

---

## 📊 App Service Architecture Summary

| Component            | Name                   | Details                  | Status |
| -------------------- | ---------------------- | ------------------------ | ------ |
| **App Service Plan** | dev-skycraft-swc-asp   | Linux, Premium V4 P0V4   | ✅     |
| **Web App (Prod)**   | dev-skycraft-swc-app01 | Node 22 LTS, VNet Integrated | ✅     |
| **Slot (Staging)**   | .../slots/staging      | Deployment Target, VNet Integrated | ✅     |
| **Autoscale**        | The setting that targets dev-skycraft-swc-asp | 1-3 Instances | ✅     |

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

**Next**: [Module 4 - Storage](../../module-4-storage/README.md) ->

---

## 📌 Module Navigation

- [← Back to Module 3 Index](../README.md)
- [Module 4: Storage Accounts →](../../module-4-storage/README.md)
