# Lab 3.1 Completion Checklist

## ✅ Development Environment VM Verification

### Dev Auth Server (dev-skycraft-swc-auth-01-vm)
- [ ] VM name: `dev-skycraft-swc-auth-01-vm`
- [ ] Resource group: `dev-skycraft-swc-rg`
- [ ] Location: **Sweden Central**
- [ ] Availability zone: **1**
- [ ] Size: **Standard_B2s** (2 vCPU, 4 GiB memory)
- [ ] Image: Ubuntu Server 22.04 LTS - x64 Gen2
- [ ] OS disk type: **Standard SSD** (30 GB)
- [ ] Virtual network: `dev-skycraft-swc-vnet`
- [ ] Subnet: `AuthSubnet (10.1.1.0/24)`
- [ ] Private IP address: [Record IP: ____________]
- [ ] Public IP address: **None**
- [ ] NSG: Subnet-level NSG (dev-skycraft-swc-auth-nsg)
- [ ] SSH key name: `dev-skycraft-swc-auth-01-key`
- [ ] Boot diagnostics: Enabled
- [ ] VM status: **Running**

### Dev World Server 1 (dev-skycraft-swc-world-01-vm)
- [ ] VM name: `dev-skycraft-swc-world-01-vm`
- [ ] Resource group: `dev-skycraft-swc-rg`
- [ ] Availability zone: **1**
- [ ] Size: **Standard_B2ms** (2 vCPU, 8 GiB memory)
- [ ] Image: Ubuntu Server 22.04 LTS
- [ ] OS disk type: **Standard SSD** (30 GB)
- [ ] Subnet: `WorldSubnet (10.1.2.0/24)`
- [ ] Private IP address: [Record IP: ____________]
- [ ] Public IP address: **None**
- [ ] SSH key name: `dev-skycraft-swc-world-01-key`
- [ ] VM status: **Running**

### Dev World Server 2 (dev-skycraft-swc-world-02-vm)
- [ ] VM name: `dev-skycraft-swc-world-02-vm`
- [ ] Resource group: `dev-skycraft-swc-rg`
- [ ] Availability zone: **2** (different from world-01)
- [ ] Size: **Standard_B2ms** (2 vCPU, 8 GiB memory)
- [ ] Image: Ubuntu Server 22.04 LTS
- [ ] OS disk type: **Standard SSD** (30 GB)
- [ ] Subnet: `WorldSubnet (10.1.2.0/24)`
- [ ] Private IP address: [Record IP: ____________]
- [ ] Public IP address: **None**
- [ ] SSH key name: `dev-skycraft-swc-world-02-key`
- [ ] VM status: **Running**

### Dev Database Server (dev-skycraft-swc-db-01-vm)
- [ ] VM name: `dev-skycraft-swc-db-01-vm`
- [ ] Resource group: `dev-skycraft-swc-rg`
- [ ] Availability zone: **1**
- [ ] Size: **Standard_B2ms** (2 vCPU, 8 GiB memory)
- [ ] Image: Ubuntu Server 22.04 LTS
- [ ] OS disk type: **Standard SSD** (30 GB)
- [ ] Subnet: `DatabaseSubnet (10.1.3.0/24)`
- [ ] Private IP address: [Record IP: ____________]
- [ ] Public IP address: **None**
- [ ] SSH key name: `dev-skycraft-swc-db-01-key`
- [ ] **Data disk attached**: `dev-skycraft-swc-db-01-datadisk-01`
  - Size: **128 GiB**
  - Disk type: **Standard SSD**
  - Host caching: Read/Write
- [ ] VM status: **Running**

### Development Environment Tags
Verify all dev VMs have these tags:
- [ ] Tag: `Project` = `SkyCraft`
- [ ] Tag: `Environment` = `Development`
- [ ] Tag: `CostCenter` = `MSDN`
- [ ] Tag: `Role` = [AuthServer | WorldServer | DatabaseServer]

---

## ✅ Production Environment VM Verification

### Prod Auth Server (prod-skycraft-swc-auth-01-vm)
- [ ] VM name: `prod-skycraft-swc-auth-01-vm`
- [ ] Resource group: `prod-skycraft-swc-rg`
- [ ] Location: **Sweden Central**
- [ ] Availability zone: **1**
- [ ] Size: **Standard_D2s_v5** (2 vCPU, 8 GiB memory)
- [ ] Image: Ubuntu Server 22.04 LTS - x64 Gen2
- [ ] OS disk type: **Premium SSD** (30 GB)
- [ ] Virtual network: `prod-skycraft-swc-vnet`
- [ ] Subnet: `AuthSubnet (10.2.1.0/24)`
- [ ] Private IP address: [Record IP: ____________]
- [ ] Public IP address: **None**
- [ ] NSG: Subnet-level NSG (prod-skycraft-swc-auth-nsg)
- [ ] SSH key name: `prod-skycraft-swc-auth-01-key`
- [ ] VM status: **Running**

### Prod World Server 1 (prod-skycraft-swc-world-01-vm)
- [ ] VM name: `prod-skycraft-swc-world-01-vm`
- [ ] Resource group: `prod-skycraft-swc-rg`
- [ ] Availability zone: **1**
- [ ] Size: **Standard_D2s_v5** (2 vCPU, 8 GiB memory)
- [ ] Image: Ubuntu Server 22.04 LTS
- [ ] OS disk type: **Premium SSD** (30 GB)
- [ ] Subnet: `WorldSubnet (10.2.2.0/24)`
- [ ] Private IP address: [Record IP: ____________]
- [ ] Public IP address: **None**
- [ ] SSH key name: `prod-skycraft-swc-world-01-key`
- [ ] VM status: **Running**

### Prod World Server 2 (prod-skycraft-swc-world-02-vm)
- [ ] VM name: `prod-skycraft-swc-world-02-vm`
- [ ] Resource group: `prod-skycraft-swc-rg`
- [ ] Availability zone: **2** (different from world-01)
- [ ] Size: **Standard_D2s_v5** (2 vCPU, 8 GiB memory)
- [ ] Image: Ubuntu Server 22.04 LTS
- [ ] OS disk type: **Premium SSD** (30 GB)
- [ ] Subnet: `WorldSubnet (10.2.2.0/24)`
- [ ] Private IP address: [Record IP: ____________]
- [ ] Public IP address: **None**
- [ ] SSH key name: `prod-skycraft-swc-world-02-key`
- [ ] VM status: **Running**

### Prod Database Server (prod-skycraft-swc-db-01-vm)
- [ ] VM name: `prod-skycraft-swc-db-01-vm`
- [ ] Resource group: `prod-skycraft-swc-rg`
- [ ] Availability zone: **1**
- [ ] Size: **Standard_D4s_v5** (4 vCPU, 16 GiB memory)
- [ ] Image: Ubuntu Server 22.04 LTS
- [ ] OS disk type: **Premium SSD** (30 GB)
- [ ] Subnet: `DatabaseSubnet (10.2.3.0/24)`
- [ ] Private IP address: [Record IP: ____________]
- [ ] Public IP address: **None**
- [ ] SSH key name: `prod-skycraft-swc-db-01-key`
- [ ] **Data disk attached**: `prod-skycraft-swc-db-01-datadisk-01`
  - Size: **256 GiB**
  - Disk type: **Premium SSD**
  - Host caching: Read/Write
- [ ] VM status: **Running**

### Production Environment Tags
Verify all prod VMs have these tags:
- [ ] Tag: `Project` = `SkyCraft`
- [ ] Tag: `Environment` = `Production`
- [ ] Tag: `CostCenter` = `MSDN`
- [ ] Tag: `Role` = [AuthServer | WorldServer | DatabaseServer]

---

## ✅ Networking and Security Verification

### Network Configuration
- [ ] All 8 VMs have **no public IP addresses**
- [ ] All VMs deployed to correct subnets:
  - Auth servers → AuthSubnet (10.1.1.0/24 or 10.2.1.0/24)
  - World servers → WorldSubnet (10.1.2.0/24 or 10.2.2.0/24)
  - Database servers → DatabaseSubnet (10.1.3.0/24 or 10.2.3.0/24)
- [ ] All VMs have Network Interface Cards (NICs) attached
- [ ] NICs have "Delete with VM" enabled

### NSG and Security
- [ ] All VMs protected by subnet-level NSGs (no NIC-level NSGs)
- [ ] NSG rules allow SSH (port 22) from Bastion subnet (10.0.0.0/26)
- [ ] NSG rules allow application ports (3724, 8085) as configured in Lab 2.2
- [ ] Boot diagnostics enabled on all VMs

### Azure Bastion Connectivity
- [ ] Can connect to dev-skycraft-swc-auth-01-vm via Bastion
- [ ] Can connect to dev-skycraft-swc-world-01-vm via Bastion
- [ ] Can connect to dev-skycraft-swc-world-02-vm via Bastion
- [ ] Can connect to dev-skycraft-swc-db-01-vm via Bastion
- [ ] Can connect to prod-skycraft-swc-auth-01-vm via Bastion
- [ ] Can connect to prod-skycraft-swc-world-01-vm via Bastion
- [ ] Can connect to prod-skycraft-swc-world-02-vm via Bastion
- [ ] Can connect to prod-skycraft-swc-db-01-vm via Bastion

### Private DNS Auto-Registration
- [ ] dev VMs auto-registered in `skycraft.internal` DNS zone
- [ ] prod VMs auto-registered in `skycraft.internal` DNS zone
- [ ] Can resolve VM hostnames from within VNet (nslookup test)

---

## 🔍 Validation Commands

Run these Azure CLI commands to validate your lab setup:

### Login and Set Context

```azurecli
# Login to Azure
az login

# Set subscription context
az account set --subscription "YOUR-SUBSCRIPTION-NAME"

# Verify current subscription
az account show --query "{Name:name, SubscriptionId:id}" --output table
```

### List All Deployed VMs

```azurecli
# List all VMs in dev resource group
az vm list   --resource-group dev-skycraft-swc-rg   --query "[].{Name:name,Size:hardwareProfile.vmSize,Zone:zones[0],Status:provisioningState}"   --output table

# Expected output:
# Name                          Size           Zone  Status
# ----------------------------  -------------  ----  ---------
# dev-skycraft-swc-auth-01-vm   Standard_B2s   1     Succeeded
# dev-skycraft-swc-world-01-vm  Standard_B2ms  1     Succeeded
# dev-skycraft-swc-world-02-vm  Standard_B2ms  2     Succeeded
# dev-skycraft-swc-db-01-vm     Standard_B2ms  1     Succeeded

# List all VMs in prod resource group
az vm list   --resource-group prod-skycraft-swc-rg   --query "[].{Name:name,Size:hardwareProfile.vmSize,Zone:zones[0],Status:provisioningState}"   --output table

# Expected output:
# Name                           Size             Zone  Status
# -----------------------------  ---------------  ----  ---------
# prod-skycraft-swc-auth-01-vm   Standard_D2s_v5  1     Succeeded
# prod-skycraft-swc-world-01-vm  Standard_D2s_v5  1     Succeeded
# prod-skycraft-swc-world-02-vm  Standard_D2s_v5  2     Succeeded
# prod-skycraft-swc-db-01-vm     Standard_D4s_v5  1     Succeeded
```

### Verify VM Details

```azurecli
# Get detailed info for dev auth server
az vm show   --resource-group dev-skycraft-swc-rg   --name dev-skycraft-swc-auth-01-vm   --query "{Name:name,Size:hardwareProfile.vmSize,Zone:zones[0],OS:storageProfile.imageReference.offer,OSType:storageProfile.osDisk.osType,DiskType:storageProfile.osDisk.managedDisk.storageAccountType}"   --output json

# Expected output:
# {
#   "DiskType": "StandardSSD_LRS",
#   "Name": "dev-skycraft-swc-auth-01-vm",
#   "OS": "0001-com-ubuntu-server-jammy",
#   "OSType": "Linux",
#   "Size": "Standard_B2s",
#   "Zone": "1"
# }
```

### Verify Network Configuration

```azurecli
# Get network interface details for dev auth server
az vm show   --resource-group dev-skycraft-swc-rg   --name dev-skycraft-swc-auth-01-vm   --query "networkProfile.networkInterfaces[0].id"   --output tsv | xargs az network nic show --ids | jq '{Name:.name,PrivateIP:.ipConfigurations[0].privateIpAddress,Subnet:.ipConfigurations[0].subnet.id,PublicIP:.ipConfigurations[0].publicIpAddress}'

# Expected output:
# {
#   "Name": "dev-skycraft-swc-auth-01-vmVMNic",
#   "PrivateIP": "10.1.1.X",
#   "Subnet": "/subscriptions/.../subnets/AuthSubnet",
#   "PublicIP": null
# }

# List all NICs in dev resource group
az network nic list   --resource-group dev-skycraft-swc-rg   --query "[].{Name:name,PrivateIP:ipConfigurations[0].privateIpAddress,Subnet:ipConfigurations[0].subnet.id}"   --output table
```

### Verify Availability Zones

```azurecli
# Check zone distribution for world servers (dev)
az vm list   --resource-group dev-skycraft-swc-rg   --query "[?contains(name,'world')].{Name:name,Zone:zones[0]}"   --output table

# Expected output:
# Name                          Zone
# ----------------------------  ----
# dev-skycraft-swc-world-01-vm  1
# dev-skycraft-swc-world-02-vm  2

# Check zone distribution for world servers (prod)
az vm list   --resource-group prod-skycraft-swc-rg   --query "[?contains(name,'world')].{Name:name,Zone:zones[0]}"   --output table

# Expected output:
# Name                           Zone
# -----------------------------  ----
# prod-skycraft-swc-world-01-vm  1
# prod-skycraft-swc-world-02-vm  2
```

### Verify Managed Disks

```azurecli
# List all disks in dev resource group
az disk list   --resource-group dev-skycraft-swc-rg   --query "[].{Name:name,Size:diskSizeGb,SKU:sku.name,State:diskState}"   --output table

# Expected output:
# Name                                    Size  SKU              State
# --------------------------------------  ----  ---------------  --------
# dev-skycraft-swc-auth-01-vm_OsDisk_...  30    StandardSSD_LRS  Attached
# dev-skycraft-swc-world-01-vm_OsDisk...  30    StandardSSD_LRS  Attached
# dev-skycraft-swc-world-02-vm_OsDisk...  30    StandardSSD_LRS  Attached
# dev-skycraft-swc-db-01-vm_OsDisk_...    30    StandardSSD_LRS  Attached
# dev-skycraft-swc-db-01-datadisk-01      128   StandardSSD_LRS  Attached

# Verify data disk attachment
az vm show   --resource-group dev-skycraft-swc-rg   --name dev-skycraft-swc-db-01-vm   --query "storageProfile.dataDisks[].{Name:name,Size:diskSizeGb,Lun:lun,Caching:caching}"   --output table

# Expected output:
# Name                                Size  Lun  Caching
# ----------------------------------  ----  ---  ----------
# dev-skycraft-swc-db-01-datadisk-01  128   0    ReadWrite

# List all disks in prod resource group
az disk list   --resource-group prod-skycraft-swc-rg   --query "[].{Name:name,Size:diskSizeGb,SKU:sku.name,State:diskState}"   --output table

# Expected output includes:
# prod-skycraft-swc-db-01-datadisk-01  256  Premium_LRS  Attached
```

### Verify Tags

```azurecli
# Check tags on dev auth server
az vm show   --resource-group dev-skycraft-swc-rg   --name dev-skycraft-swc-auth-01-vm   --query tags   --output json

# Expected output:
# {
#   "CostCenter": "MSDN",
#   "Environment": "Development",
#   "Project": "SkyCraft",
#   "Role": "AuthServer"
# }

# List all VMs with tags
az vm list   --query "[].{Name:name,Project:tags.Project,Environment:tags.Environment,Role:tags.Role}"   --output table
```

### Verify Private DNS Records

```azurecli
# List auto-registered DNS records in private zone
az network private-dns record-set a list   --resource-group platform-skycraft-swc-rg   --zone-name skycraft.internal   --query "[].{Name:name,IP:aRecords[0].ipv4Address,AutoRegistered:isAutoRegistered}"   --output table

# Expected output includes:
# Name                          IP          AutoRegistered
# ----------------------------  ----------  ---------------
# dev-skycraft-swc-auth-01-vm   10.1.1.X    True
# dev-skycraft-swc-world-01-vm  10.1.2.X    True
# dev-skycraft-swc-world-02-vm  10.1.2.X    True
# dev-skycraft-swc-db-01-vm     10.1.3.X    True
# prod-skycraft-swc-auth-01-vm  10.2.1.X    True
# ...
```

### Test VM Connectivity from Bastion

Once connected to a VM via Bastion, run these commands:

```bash
# Check OS version
cat /etc/os-release | grep PRETTY_NAME

# Expected output:
# PRETTY_NAME="Ubuntu 22.04.X LTS"

# Check CPU cores
nproc

# Expected output: 2 (for B2s, B2ms, D2s_v5) or 4 (for D4s_v5)

# Check memory
free -h | grep Mem

# Expected output varies by VM size:
# B2s: ~3.8 GiB
# B2ms/D2s_v5: ~7.8 GiB
# D4s_v5: ~15.6 GiB

# Check network interface and IP
ip addr show eth0

# Expected: Private IP in correct subnet range

# Test DNS resolution
nslookup dev-skycraft-swc-db-01-vm.skycraft.internal

# Expected: Returns private IP (10.1.3.X)

# Test connectivity to another VM
nc -zv 10.1.2.10 22

# Expected: Connection succeeded (SSH port open)

# Check disk layout
lsblk

# Expected for auth/world VMs:
# sda   30G  (OS disk only)

# Expected for database VMs:
# sda   30G  (OS disk)
# sdb  128G/256G (data disk - may need to be mounted)
```

---

## 📊 VM Deployment Summary

Use this table to document your deployed infrastructure:

| VM Name | Size | vCPU | Memory | Zone | OS Disk | Data Disk | Private IP | SSH Key Downloaded |
|---------|------|------|--------|------|---------|-----------|------------|-------------------|
| dev-skycraft-swc-auth-01-vm | B2s | 2 | 4 GB | 1 | 30GB SSD | - | __________ | ☐ |
| dev-skycraft-swc-world-01-vm | B2ms | 2 | 8 GB | 1 | 30GB SSD | - | __________ | ☐ |
| dev-skycraft-swc-world-02-vm | B2ms | 2 | 8 GB | 2 | 30GB SSD | - | __________ | ☐ |
| dev-skycraft-swc-db-01-vm | B2ms | 2 | 8 GB | 1 | 30GB SSD | 128GB SSD | __________ | ☐ |
| prod-skycraft-swc-auth-01-vm | D2s_v5 | 2 | 8 GB | 1 | 30GB Premium | - | __________ | ☐ |
| prod-skycraft-swc-world-01-vm | D2s_v5 | 2 | 8 GB | 1 | 30GB Premium | - | __________ | ☐ |
| prod-skycraft-swc-world-02-vm | D2s_v5 | 2 | 8 GB | 2 | 30GB Premium | - | __________ | ☐ |
| prod-skycraft-swc-db-01-vm | D4s_v5 | 4 | 16 GB | 1 | 30GB Premium | 256GB Premium | __________ | ☐ |

---

## 📊 Subnet Placement Verification

Document which VMs are in which subnets:

### Development Environment (dev-skycraft-swc-vnet)

| Subnet | IP Range | VMs Deployed | VM Count |
|--------|----------|--------------|----------|
| AuthSubnet | 10.1.1.0/24 | dev-skycraft-swc-auth-01-vm | 1 |
| WorldSubnet | 10.1.2.0/24 | dev-skycraft-swc-world-01-vm<br/>dev-skycraft-swc-world-02-vm | 2 |
| DatabaseSubnet | 10.1.3.0/24 | dev-skycraft-swc-db-01-vm | 1 |

### Production Environment (prod-skycraft-swc-vnet)

| Subnet | IP Range | VMs Deployed | VM Count |
|--------|----------|--------------|----------|
| AuthSubnet | 10.2.1.0/24 | prod-skycraft-swc-auth-01-vm | 1 |
| WorldSubnet | 10.2.2.0/24 | prod-skycraft-swc-world-01-vm<br/>prod-skycraft-swc-world-02-vm | 2 |
| DatabaseSubnet | 10.2.3.0/24 | prod-skycraft-swc-db-01-vm | 1 |

---

## 📝 Reflection Questions

Answer these questions to document your hands-on experience and demonstrate understanding:

### Question 1: VM Sizing Justification
**Explain why you chose different VM sizes for dev and prod environments:**

| Environment | VM Size | Cost Consideration | Performance Consideration |
|-------------|---------|-------------------|--------------------------|
| Development | B-series (B2s, B2ms) | ________________ | ________________ |
| Production | D-series (D2s_v5, D4s_v5) | ________________ | ________________ |

**Monthly cost estimate** (calculate using Azure Pricing Calculator):
- Development environment total: $____________/month
- Production environment total: $____________/month

### Question 2: Availability Zone Strategy
**Document your zone deployment strategy:**

VMs deployed across multiple zones:

_________________________________________________________________

_________________________________________________________________

VMs deployed to single zone (and why):

_________________________________________________________________

_________________________________________________________________

What would happen if Zone 1 experiences an outage?

_________________________________________________________________

_________________________________________________________________

### Question 3: Data Disk Configuration
**Why did you add data disks only to database VMs and not to auth/world servers?**

Database VMs need data disks because:

_________________________________________________________________

_________________________________________________________________

Auth and world server VMs don't need data disks because:

_________________________________________________________________

_________________________________________________________________

### Question 4: Security Configuration
**Explain the security measures implemented in your VM deployment:**

No public IP addresses:

_________________________________________________________________

_________________________________________________________________

Bastion for administrative access:

_________________________________________________________________

_________________________________________________________________

NSG protection:

_________________________________________________________________

_________________________________________________________________

### Question 5: Connectivity Testing Results
**Document your connectivity tests from one VM to others:**

| Source VM | Destination VM | Test Command | Result (Success/Fail) | Notes |
|-----------|----------------|--------------|----------------------|-------|
| dev-skycraft-swc-auth-01-vm | 10.1.2.10 (world-01) | `nc -zv 10.1.2.10 22` | __________ | __________ |
| dev-skycraft-swc-auth-01-vm | 10.1.3.10 (db-01) | `nc -zv 10.1.3.10 22` | __________ | __________ |
| dev-skycraft-swc-world-01-vm | 10.1.3.10 (db-01) | `nc -zv 10.1.3.10 3306` | __________ | __________ |

### Question 6: Private DNS Resolution
**Test and document private DNS auto-registration:**

Command used to test DNS:
```bash
_________________________________________________________________
```

DNS records found for your VMs:

| VM Hostname | FQDN | IP Address | Auto-Registered |
|-------------|------|------------|-----------------|
| dev-skycraft-swc-auth-01-vm | __________.skycraft.internal | __________ | ☐ Yes ☐ No |
| dev-skycraft-swc-world-01-vm | __________.skycraft.internal | __________ | ☐ Yes ☐ No |
| dev-skycraft-swc-db-01-vm | __________.skycraft.internal | __________ | ☐ Yes ☐ No |

### Question 7: Troubleshooting Experience
**Describe any issues encountered during VM deployment and how you resolved them:**

Issue 1:

_________________________________________________________________

Resolution:

_________________________________________________________________

Issue 2:

_________________________________________________________________

Resolution:

_________________________________________________________________

### Question 8: Resource Optimization
**If you had to reduce costs by 30%, which VMs would you downsize and why?**

VMs to downsize: ______________________________________________________

Reasoning:

_________________________________________________________________

_________________________________________________________________

VMs to keep at current size:

_________________________________________________________________

_________________________________________________________________

**Instructor Review Date**: _________  
**Feedback**: 

_________________________________________________________________

_________________________________________________________________

---

## ⏱️ Completion Tracking

- **Estimated Time**: 3 hours
- **Actual Time Spent**: _________ hours
- **Date Started**: _________
- **Date Completed**: _________

**Challenges Encountered**:

_________________________________________________________________

_________________________________________________________________

_________________________________________________________________

**Most Valuable Learning**:

_________________________________________________________________

_________________________________________________________________

**Questions for Instructor**:

_________________________________________________________________

_________________________________________________________________

---

## ✅ Final Lab 3.1 Sign-off

**All Verification Items Complete**:
- [ ] 8 Virtual Machines deployed (4 dev + 4 prod)
- [ ] All VMs using correct sizes (B-series dev, D-series prod)
- [ ] World servers deployed across Zone 1 and Zone 2
- [ ] All VMs using Ubuntu Server 22.04 LTS
- [ ] Standard SSD for dev, Premium SSD for prod
- [ ] Data disks attached to both database VMs (128GB dev, 256GB prod)
- [ ] No public IP addresses on any VM
- [ ] All VMs accessible via Azure Bastion
- [ ] VMs deployed to correct subnets with NSG protection
- [ ] All VMs have proper tags (Project, Environment, CostCenter, Role)
- [ ] SSH private keys downloaded and stored securely
- [ ] Private DNS auto-registration working
- [ ] All validation commands executed successfully
- [ ] VM-to-VM connectivity verified
- [ ] All reflection questions answered

**Student Name**: _________________  
**Lab 3.1 Completion Date**: _________________  
**Instructor Signature**: _________________

---

## 🎉 Congratulations!

You've successfully completed **Lab 3.1: Deploy Virtual Machines for SkyCraft**!

**What You Built**:
- ✅ 8 Azure Virtual Machines across dev and prod environments
- ✅ High-availability configuration with availability zones
- ✅ Appropriate VM sizing for each workload (auth, world, database)
- ✅ Managed disk configuration (OS + data disks)
- ✅ Secure deployment (no public IPs, Bastion access only)
- ✅ Private DNS integration for internal name resolution

**Infrastructure Inventory**:
- **Total VMs**: 8 (4 dev + 4 prod)
- **Total vCPUs**: 20 (8 dev + 12 prod)
- **Total Memory**: 80 GB (32 GB dev + 48 GB prod)
- **Total Storage**: 624 GB (240 GB OS + 384 GB data)
- **Availability Zones**: 2 (Zone 1 and Zone 2)

**Cost Estimate** (approximate monthly):
- Development: ~$150/month (B-series VMs)
- Production: ~$280/month (D-series VMs)
- **Total: ~$430/month** for 8-VM infrastructure

**Next Steps**: In **Lab 3.2: Configure AzerothCore on Azure VMs**, you'll:
- Install AzerothCore dependencies (MySQL, build tools)
- Compile AzerothCore from source
- Configure database servers with MySQL
- Set up authentication and world servers
- Test game server connectivity

**Estimated Lab 3.2 Duration**: 3 hours

---

## 📌 Module Navigation

- [← Back to Module 3 Index](../README.md)
- [Lab Guide: 3.1 Deploy VMs →](lab-guide-3.1.md)
- [Next Lab: 3.2 Configure AzerothCore →](../3.2-configure-azerothcore/lab-checklist-3.2.md)
