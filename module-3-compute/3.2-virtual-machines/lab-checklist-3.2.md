# Lab 3.2 Completion Checklist

## ✅ Authserver Virtual Machine Verification

### VM Configuration

- [ ] Virtual machine name: `dev-skycraft-swc-auth-vm`
- [ ] Location: **Sweden Central**
- [ ] Resource group: `dev-skycraft-swc-rg`
- [ ] Availability zone: **Zone 1**
- [ ] Size: `Standard_B2ls_v2` (2 vCPUs, 4 GiB memory)
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
- [ ] Tag: `Owner` = `mbiszczanik`

---

## ✅ Worldserver Virtual Machine Verification

### VM Configuration

- [ ] Virtual machine name: `dev-skycraft-swc-world-vm`
- [ ] Location: **Sweden Central**
- [ ] Resource group: `dev-skycraft-swc-rg`
- [ ] Availability zone: **Zone 2**
- [ ] Size: `Standard_B2ls_v2` (2 vCPUs, 4 GiB memory)
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
- [ ] Tag: `Owner` = `mbiszczanik`

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
- [ ] Tag: `Owner` = `mbiszczanik`

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
- [ ] VM size: Standard_B2ls_v2
- [ ] VNet: `prod-skycraft-swc-vnet`
- [ ] Subnet: WorldSubnet

### Autoscale Configuration

- [ ] Minimum instances: 1
- [ ] Maximum instances: 4
- [ ] Scale-out trigger: CPU > 70%
- [ ] Scale-in trigger: CPU < 30%

### VMSS Validation Commands

```powershell
# List VMSS instances
Get-AzVmssVM -ResourceGroupName prod-skycraft-swc-rg -VMScaleSetName prod-skycraft-swc-world-vmss |
    Select-Object Name, @{N='Zone';E={$_.Zones -join ','}}, ProvisioningState |
    Format-Table -AutoSize
```

### VMSS Cleanup

- [ ] VMSS deleted after completing lab (to avoid costs)

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

### Verify Virtual Machines

```powershell
# List all VMs in dev resource group
Get-AzVM -ResourceGroupName dev-skycraft-swc-rg -Status |
    Select-Object Name, @{N='Size';E={$_.HardwareProfile.VmSize}}, @{N='Zone';E={$_.Zones -join ','}}, PowerState |
    Format-Table -AutoSize

# Expected output:
# Name                        Size              Zone  PowerState
# ----                        ----              ----  ----------
# dev-skycraft-swc-auth-vm    Standard_B2ls_v2  1     VM running
# dev-skycraft-swc-world-vm   Standard_B2ls_v2  2     VM running
```

### Verify VM Network Configuration

```powershell
# Show private IPs of both VMs
foreach ($vmName in 'dev-skycraft-swc-auth-vm', 'dev-skycraft-swc-world-vm') {
    $vm = Get-AzVM -ResourceGroupName dev-skycraft-swc-rg -Name $vmName
    $nic = Get-AzNetworkInterface -ResourceId $vm.NetworkProfile.NetworkInterfaces[0].Id
    [pscustomobject]@{
        Name      = $vm.Name
        Zone      = $vm.Zones -join ','
        PrivateIP = $nic.IpConfigurations[0].PrivateIpAddress
    }
}
```

### Verify Disk Encryption Status

> **Note**: Azure Disk Encryption for Linux VMs requires **8 GB RAM** and is enabled from PowerShell or the CLI (not the Portal). VMs must be temporarily resized to `Standard_B2s_v2` for encryption - `Enable-Encryption.ps1` does the resize, encryption and resize back for you.

```powershell
# Check encryption status for both VMs
Get-AzVMDiskEncryptionStatus -ResourceGroupName dev-skycraft-swc-rg -VMName dev-skycraft-swc-auth-vm
Get-AzVMDiskEncryptionStatus -ResourceGroupName dev-skycraft-swc-rg -VMName dev-skycraft-swc-world-vm

# Expected output (per VM):
# OsVolumeEncrypted   : Encrypted
# DataVolumesEncrypted: Encrypted
# ProgressMessage     : Encryption succeeded for all volumes
```

### (Optional) Verify Encryption at Host

```powershell
# Check Encryption at Host status
(Get-AzVM -ResourceGroupName dev-skycraft-swc-rg -Name dev-skycraft-swc-auth-vm).SecurityProfile.EncryptionAtHost

# Expected output: True (if enabled)
```

### Verify Data Disk Attachment

```powershell
# List disks attached to Worldserver
(Get-AzVM -ResourceGroupName dev-skycraft-swc-rg -Name dev-skycraft-swc-world-vm).StorageProfile.DataDisks |
    Select-Object Name, DiskSizeGB, Lun |
    Format-Table -AutoSize

# Expected output:
# Name                              DiskSizeGB  Lun
# ----                              ----------  ---
# dev-skycraft-swc-world-vm-data    64          0
```

### Verify Load Balancer Backend Pools

```powershell
# List backend pool members
(Get-AzLoadBalancer -ResourceGroupName dev-skycraft-swc-rg -Name dev-skycraft-swc-lb).BackendAddressPools |
    Select-Object Name, @{N='BackendIPConfigs';E={$_.BackendIpConfigurations.Count}} |
    Format-Table -AutoSize

# Expected output:
# Name                             BackendIPConfigs
# ----                             ----------------
# dev-skycraft-swc-lb-be-auth      1
# dev-skycraft-swc-lb-be-world     1
```

### Verify Key Vault

```powershell
# Show Key Vault details
Get-AzKeyVault -ResourceGroupName dev-skycraft-swc-rg -VaultName dev-skycraft-swc-kv |
    Select-Object VaultName, Location, EnabledForDiskEncryption |
    Format-Table -AutoSize

# Expected output:
# VaultName            Location       EnabledForDiskEncryption
# ---------            --------       ------------------------
# dev-skycraft-swc-kv  swedencentral  True
```

---

## 📊 VM Infrastructure Summary

| Component       | Name                      | Zone | Size             | Disk Encryption | Backend Pool |
| --------------- | ------------------------- | ---- | ---------------- | --------------- | ------------ |
| **Authserver**  | dev-skycraft-swc-auth-vm  | 1    | Standard_B2ls_v2 | ✅              | be-auth      |
| **Worldserver** | dev-skycraft-swc-world-vm | 2    | Standard_B2ls_v2 | ✅              | be-world     |
| **Key Vault**   | dev-skycraft-swc-kv       | N/A  | Standard         | N/A             | N/A          |

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

- VMs (2x B2ls_v2): ~$60/month
- Standard SSD Disks: ~$10/month
- Key Vault: ~$0.03/operation
- **Total**: ~$70/month for development environment

**Next**: [Lab 3.3: Provision and Manage Containers →](../3.3-containers/lab-guide-3.3.md)

---

## 📌 Module Navigation

- [← Back to Module 3 Index](../README.md)
- [← Lab 3.1: Infrastructure as Code](../3.1-infrastructure-as-code/lab-guide-3.1.md)
- [Lab 3.3: Containers →](../3.3-containers/lab-guide-3.3.md)
