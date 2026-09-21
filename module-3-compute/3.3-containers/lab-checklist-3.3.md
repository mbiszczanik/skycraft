# Lab 3.3 Completion Checklist

## ✅ Azure Container Registry (ACR) Verification

### Registry Configuration
- [ ] Registry name: `devskycraftswcacr01` (alphanumeric only)
- [ ] Resource group: `dev-skycraft-swc-rg`
- [ ] Location: **Sweden Central**
- [ ] SKU: **Standard**
- [ ] Admin user: **Enabled**

### Images
- [ ] Repository `skycraft-auth` exists
- [ ] Tag `v1` exists

---

## ✅ Azure Container Instances (ACI) Verification

### Container Configuration
- [ ] Container name: `dev-skycraft-swc-aci-auth`
- [ ] Resource group: `dev-skycraft-swc-rg`
- [ ] OS Type: **Linux**
- [ ] Image: `skycraft-auth:v1` (from your ACR)
- [ ] State: **Running**
- [ ] Public IP address assigned
- [ ] DNS Label: `skycraft-auth-[ID]` configured

---

## ✅ Azure Container Apps (ACA) Verification

### Environment & App
- [ ] Environment name: `dev-skycraft-swc-cae-02`
- [ ] App name: `dev-skycraft-swc-aca-world`
- [ ] Ingress: **Enabled** (Target port 80)
- [ ] Visibility: **External**

### Scaling
- [ ] Min replicas: **1**
- [ ] Max replicas: **3**
- [ ] Scale rule: `http-load` (10 concurrent requests)

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

### Verify ACR and Images

```powershell
# List repositories in your ACR
# Replace [your-acr-name] with your actual registry name (the lab default is devskycraftswcacr01)
Get-AzContainerRegistryRepository -RegistryName [your-acr-name]

# Expected output:
# skycraft-auth
```

### Verify ACI Status

```powershell
# Check ACI state
Get-AzContainerGroup -ResourceGroupName dev-skycraft-swc-rg -Name dev-skycraft-swc-aci-auth |
    Select-Object Name, @{N='State';E={$_.InstanceViewState}}, @{N='IP';E={$_.IPAddressIP}}, @{N='FQDN';E={$_.IPAddressFqdn}} |
    Format-Table -AutoSize
```

### Verify ACA Configuration

```powershell
# Check ACA ingress and provisioning
Get-AzContainerApp -ResourceGroupName dev-skycraft-swc-rg -Name dev-skycraft-swc-aca-world |
    Select-Object Name, ProvisioningState, @{N='FQDN';E={$_.IngressFqdn}} |
    Format-Table -AutoSize
```

---

## 📊 Container Resources Summary

| Component | Name | Type | Image | Status |
|-----------|------|------|-------|--------|
| **Registry** | `devskycraftswcacr01` | ACR | N/A | ✅ |
| **Auth Service** | `dev-skycraft-swc-aci-auth` | ACI | `skycraft-auth:v1` | ✅ |
| **World Service** | `dev-skycraft-swc-aca-world` | ACA | `skycraft-auth:v1` | ✅ |

---

## 📝 Reflection Questions

### Question 1: Docker Build Process
**How does `az acr build` differ from running `docker build` and `docker push` locally? What advantage did it provide in this lab?**

_________________________________________________________________

_________________________________________________________________

### Question 2: ACI vs ACA
**You deployed the same image to both ACI and ACA. Describe a scenario where you would strictly choose ACI over ACA.**

_________________________________________________________________

_________________________________________________________________

### Question 3: Scaling Strategy
**If the WorldServer required high CPU calculations rather than just handling many HTTP requests, how would you change the ACA scaling rule?**

_________________________________________________________________

_________________________________________________________________

**Instructor Review Date**: _________  
**Feedback**: _________________________________________________________________

---

## ⏱️ Completion Tracking

- **Estimated Time**: 2 hours
- **Actual Time Spent**: _________ hours
- **Date Started**: _________
- **Date Completed**: _________

---

## ✅ Final Lab 3.3 Sign-off

**All Verification Items Complete**:
- [ ] All resources created with proper naming conventions
- [ ] ACR contains the built image
- [ ] ACI is accessible via public FQDN
- [ ] ACA is deployed and scaling rules configured
- [ ] All reflection questions answered
- [ ] Ready to proceed to Lab 3.4

**Student Name**: _________________  
**Lab 3.3 Completion Date**: _________________  
**Instructor Signature**: _________________

---

## 🎉 Congratulations!

You've successfully completed **Lab 3.3: Provision and Manage Containers**!

**What You Built**:
- ✅ A private **Azure Container Registry**
- ✅ A standalone container instance in **ACI**
- ✅ A scalable microservice in **Azure Container Apps**

**Next**: [Lab 3.4: Create and Configure Azure App Service →](../3.4-app-service/lab-guide-3.4.md)

---

## 📌 Module Navigation

- [← Back to Module 3 Index](../README.md)
- [Lab 3.4: Next Lab →](../3.4-app-service/lab-guide-3.4.md)
