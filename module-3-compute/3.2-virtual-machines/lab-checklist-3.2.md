# Lab 3.2 Completion Checklist

## ✅ Authserver Virtual Machine Verification

### VM Configuration

- [ ] Virtual machine name: `dev-skycraft-swc-auth-vm`
- [ ] Location: **Sweden Central**
- [ ] Resource group: `dev-skycraft-swc-rg`
- [ ] Availability zone: **Zone 1**
- [ ] Size: `Standard_B2s` (2 vCPUs, 4 GiB memory)
- [ ] Image: Ubuntu Server 22.04 LTS - x64 Gen2
- [ ] Status: **Running**

### Authentication

- [ ] Authentication type: SSH public key
- [ ] Username: `azureuser`
- [ ] SSH key configured correctly

### Networking

- [ ] Virtual network: `dev-skycraft-swc-vnet`
- [ ] Subnet: `AuthSubnet` (10.1.1.0/24)
- [ ] Private IP address: 10.1.1.x range
- [ ] Public IP address: **None**
- [ ] NIC network security group: None (NSG on subnet)
- [ ] Load balancer: `dev-skycraft-swc-lb`
- [ ] Backend pool: `dev-skycraft-swc-lb-be-auth`

### Disks

- [ ] OS disk type: Standard SSD (locally-redundant storage)
- [ ] OS disk size: 30 GiB
- [ ] Delete with VM: Enabled
- [ ] Disk encryption: Enabled (Azure Disk Encryption)

### Tags

- [ ] Tag: `Project` = `SkyCraft`
- [ ] Tag: `Environment` = `Development`
- [ ] Tag: `CostCenter` = `MSDN`
- [ ] Tag: `Role` = `Authserver`
- [ ] Tag: `ManagedBy` = `Portal`

---

## ✅ Worldserver Virtual Machine Verification

### VM Configuration

- [ ] Virtual machine name: `dev-skycraft-swc-world-vm`
- [ ] Location: **Sweden Central**
- [ ] Resource group: `dev-skycraft-swc-rg`
- [ ] Availability zone: **Zone 2**
- [ ] Size: `Standard_B2s` (2 vCPUs, 4 GiB memory)
- [ ] Image: Ubuntu Server 22.04 LTS - x64 Gen2
- [ ] Status: **Running**

### Networking

- [ ] Virtual network: `dev-skycraft-swc-vnet`
- [ ] Subnet: `WorldSubnet` (10.1.2.0/24)
- [ ] Private IP address: 10.1.2.x range
- [ ] Public IP address: **None**
- [ ] Load balancer: `dev-skycraft-swc-lb`
- [ ] Backend pool: `dev-skycraft-swc-lb-be-world`

### Disks

- [ ] OS disk type: Standard SSD
- [ ] OS disk size: 30 GiB
- [ ] Data disk attached: `dev-skycraft-swc-world-vm-data`
- [ ] Data disk size: 64 GiB
- [ ] Data disk type: Standard SSD
- [ ] Data disk mounted at: `/data`
- [ ] Disk encryption: Enabled (all disks)

### Tags

- [ ] Tag: `Project` = `SkyCraft`
- [ ] Tag: `Environment` = `Development`
- [ ] Tag: `CostCenter` = `MSDN`
- [ ] Tag: `Role` = `Worldserver`

---

## ✅ Azure Key Vault Verification

### Configuration

- [ ] Key vault name: `dev-skycraft-swc-kv` (or similar unique name)
- [ ] Location: **Sweden Central**
- [ ] Resource group: `dev-skycraft-swc-rg`
- [ ] Pricing tier: Standard
- [ ] Permission model: Azure role-based access control

### Access Configuration

- [ ] Azure Virtual Machines for deployment: Enabled
- [ ] Azure Disk Encryption for volume encryption: Enabled

### Tags

- [ ] Tag: `Project` = `SkyCraft`
- [ ] Tag: `Environment` = `Development`
- [ ] Tag: `CostCenter` = `MSDN`

---

## ✅ Load Balancer Backend Pools Verification

### Auth Backend Pool

- [ ] Pool name: `dev-skycraft-swc-lb-be-auth`
- [ ] VM member: `dev-skycraft-swc-auth-vm`
- [ ] Health probe: Port 3724

### World Backend Pool

- [ ] Pool name: `dev-skycraft-swc-lb-be-world`
- [ ] VM member: `dev-skycraft-swc-world-vm`
- [ ] Health probe: Port 8085

---

## ✅ Availability Zone Distribution Verification

| Component      | Zone           | Status |
| -------------- | -------------- | ------ |
| Authserver VM  | Zone 1         | ✅     |
| Worldserver VM | Zone 2         | ✅     |
| Load Balancer  | Zone-redundant | ✅     |

---

## ✅ Virtual Machine Scale Set (VMSS) Verification

### VMSS Configuration

- [ ] Resource group: `prod-skycraft-swc-rg`
- [ ] VMSS name: `prod-skycraft-swc-world-vmss`
- [ ] Orchestration mode: Uniform
- [ ] Initial instances: 2
- [ ] Availability zones: 1, 2, 3
- [ ] VM size: Standard_B1s
- [ ] VNet: `prod-skycraft-swc-vnet`
- [ ] Subnet: WorldSubnet

### Autoscale Configuration

- [ ] Minimum instances: 1
- [ ] Maximum instances: 4
- [ ] Scale-out trigger: CPU > 70%
- [ ] Scale-in trigger: CPU < 30%

### VMSS Validation Commands

```azurecli
# List VMSS instances
az vmss list-instances \
  --resource-group prod-skycraft-swc-rg \
  --name prod-skycraft-swc-world-vmss \
  --query "[].{Name:name,Zone:zones[0],State:provisioningState}" \
  --output table
```

### VMSS Cleanup

- [ ] VMSS deleted after completing lab (to avoid costs)

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

### Verify Virtual Machines

```azurecli
# List all VMs in dev resource group
az vm list \
  --resource-group dev-skycraft-swc-rg \
  --query "[].{Name:name,Size:hardwareProfile.vmSize,Zone:zones[0],State:powerState}" \
  --output table

# Expected output:
# Name                        Size          Zone  State
# --------------------------  ------------  ----  ---------
# dev-skycraft-swc-auth-vm    Standard_B2s  1     VM running
# dev-skycraft-swc-world-vm   Standard_B2s  2     VM running
```

### Verify VM Network Configuration

```azurecli
# Show Authserver VM network details
az vm show \
  --name dev-skycraft-swc-auth-vm \
  --resource-group dev-skycraft-swc-rg \
  --query "{Name:name,Zone:zones[0],PrivateIP:privateIps}" \
  --output table

# Show Worldserver VM network details
az vm show \
  --name dev-skycraft-swc-world-vm \
  --resource-group dev-skycraft-swc-rg \
  --query "{Name:name,Zone:zones[0],PrivateIP:privateIps}" \
  --output table
```

### Verify Disk Encryption Status

> **Note**: Azure Disk Encryption for Linux VMs requires **8 GB RAM** and is enabled via Azure CLI (not Portal). VMs must be temporarily resized to `Standard_B2ms` for encryption.

```azurecli
# Check encryption status for both VMs
az vm encryption show \
  --name dev-skycraft-swc-auth-vm \
  --resource-group dev-skycraft-swc-rg

az vm encryption show \
  --name dev-skycraft-swc-world-vm \
  --resource-group dev-skycraft-swc-rg

# Expected output:
# Status                  Message
# ----------------------  ------------------------------------
# Provisioning succeeded  Encryption succeeded for all volumes
```

### (Optional) Verify Encryption at Host

```azurecli
# Check Encryption at Host status
az vm show \
  --name dev-skycraft-swc-auth-vm \
  --resource-group dev-skycraft-swc-rg \
  --query "securityProfile.encryptionAtHost" \
  --output tsv

# Expected output: true (if enabled)
```

### Verify Data Disk Attachment

```azurecli
# List disks attached to Worldserver
az vm show \
  --name dev-skycraft-swc-world-vm \
  --resource-group dev-skycraft-swc-rg \
  --query "storageProfile.dataDisks[].{Name:name,Size:diskSizeGb,Lun:lun}" \
  --output table

# Expected output:
# Name                              Size  Lun
# --------------------------------  ----  ---
# dev-skycraft-swc-world-vm-data    64    0
```

### Verify Load Balancer Backend Pools

```azurecli
# List backend pool members
az network lb address-pool list \
  --lb-name dev-skycraft-swc-lb \
  --resource-group dev-skycraft-swc-rg \
  --query "[].{Name:name,BackendIPConfigs:length(backendIpConfigurations)}" \
  --output table

# Expected output:
# Name                             BackendIPConfigs
# -------------------------------  ----------------
# dev-skycraft-swc-lb-be-auth      1
# dev-skycraft-swc-lb-be-world     1
```

### Verify Key Vault

```azurecli
# Show Key Vault details
az keyvault show \
  --name dev-skycraft-swc-kv \
  --resource-group dev-skycraft-swc-rg \
  --query "{Name:name,Location:location,EnabledForDiskEncryption:properties.enabledForDiskEncryption}" \
  --output table

# Expected output:
# Name                 Location       EnabledForDiskEncryption
# -------------------  -------------  -------------------------
# dev-skycraft-swc-kv  swedencentral  True
```

---

## 📊 VM Infrastructure Summary

| Component       | Name                      | Zone | Size         | Disk Encryption | Backend Pool |
| --------------- | ------------------------- | ---- | ------------ | --------------- | ------------ |
| **Authserver**  | dev-skycraft-swc-auth-vm  | 1    | Standard_B2s | ✅              | be-auth      |
| **Worldserver** | dev-skycraft-swc-world-vm | 2    | Standard_B2s | ✅              | be-world     |
| **Key Vault**   | dev-skycraft-swc-kv       | N/A  | Standard     | N/A             | N/A          |

### Disk Summary

| VM          | Disk Name                      | Type         | Size  | Mount Point |
| ----------- | ------------------------------ | ------------ | ----- | ----------- |
| Authserver  | OS Disk                        | Standard SSD | 30 GB | /           |
| Worldserver | OS Disk                        | Standard SSD | 30 GB | /           |
| Worldserver | dev-skycraft-swc-world-vm-data | Standard SSD | 64 GB | /data       |

---

## 📝 Reflection Questions

### Question 1: Deployed Resource Documentation

**Document the VMs you created:**

| VM Name                   | Private IP       | Zone     | Subnet           |
| ------------------------- | ---------------- | -------- | ---------------- |
| dev-skycraft-swc-auth-vm  | \***\*\_\_\*\*** | **\_\_** | \***\*\_\_\*\*** |
| dev-skycraft-swc-world-vm | \***\*\_\_\*\*** | **\_\_** | \***\*\_\_\*\*** |

### Question 2: SSH Key Management

**Where did you store your SSH private key? How would you back it up securely?**

---

---

---

### Question 3: High Availability Design

**If Zone 1 experiences an outage, which services are affected? How would you design for true HA?**

---

---

---

### Question 4: Cost Analysis

**What is the estimated monthly cost for these VMs? How could you reduce costs for a development environment?**

| Resource          | Monthly Cost (Est.) |
| ----------------- | ------------------- |
| Authserver VM     | $\***\*\_\_\*\***   |
| Worldserver VM    | $\***\*\_\_\*\***   |
| Data Disk (64 GB) | $\***\*\_\_\*\***   |
| Total             | $\***\*\_\_\*\***   |

**Cost Reduction Strategies:**

---

---

### Question 5: Production Scaling

**For a production environment with 500 concurrent players, how would you modify this architecture?**

- VM Size recommendation: **\*\*\*\***\_\_**\*\*\*\***
- Number of Worldserver instances: **\*\*\*\***\_\_**\*\*\*\***
- Use VMSS? Yes / No - Why: **\*\*\*\***\_\_**\*\*\*\***

---

**Instructor Review Date**: \***\*\_\*\***  
**Feedback**: **\*\***\*\***\*\***\*\*\*\***\*\***\*\***\*\***\_**\*\***\*\***\*\***\*\*\*\***\*\***\*\***\*\***

---

## ⏱️ Completion Tracking

- **Estimated Time**: 4 hours
- **Actual Time Spent**: \***\*\_\*\*** hours
- **Date Started**: \***\*\_\*\***
- **Date Completed**: \***\*\_\*\***

**Challenges Encountered** (optional):

---

---

---

## ✅ Final Lab 3.2 Sign-off

**All Verification Items Complete**:

- [ ] Both VMs created and running
- [ ] VMs deployed in different availability zones
- [ ] All disks encrypted with Azure Disk Encryption
- [ ] Data disk attached and mounted on Worldserver
- [ ] VMs added to load balancer backend pools
- [ ] Key vault created for encryption keys
- [ ] All tags applied correctly
- [ ] All validation commands executed successfully
- [ ] All reflection questions answered
- [ ] Ready to proceed to Lab 3.3

**Student Name**: **\*\*\*\***\_**\*\*\*\***  
**Lab 3.2 Completion Date**: **\*\*\*\***\_**\*\*\*\***  
**Instructor Signature**: **\*\*\*\***\_**\*\*\*\***

---

## 🎉 Congratulations!

You've successfully completed **Lab 3.2: Create and Configure Virtual Machines**!

**What You Built**:

- ✅ 2 Ubuntu Linux VMs for SkyCraft game servers
- ✅ High-availability deployment across 2 availability zones
- ✅ Encrypted OS and data disks for security compliance
- ✅ 64 GB dedicated data disk for database storage
- ✅ Secure access configuration via Azure Bastion
- ✅ Load balancer integration for public access

**Infrastructure Cost (Estimated)**:

- VMs (2x B2s): ~$60/month
- Standard SSD Disks: ~$10/month
- Key Vault: ~$0.03/operation
- **Total**: ~$70/month for development environment

**Next**: [Lab 3.3: Provision and Manage Containers →](../3.3-containers/lab-guide-3.3.md)

---

## 📌 Module Navigation

- [← Back to Module 3 Index](../README.md)
- [← Lab 3.1: Infrastructure as Code](../3.1-infrastructure-as-code/lab-guide-3.1.md)
- [Lab 3.3: Containers →](../3.3-containers/lab-guide-3.3.md)
