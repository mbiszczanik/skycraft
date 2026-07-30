# Lab 2.1 Completion Checklist

## ✅ Resource Groups Verification

### Platform Resource Group

- [ ] Resource group name: `platform-skycraft-swc-rg`
- [ ] Location: **Sweden Central**
- [ ] Tag: `Project` = `SkyCraft`
- [ ] Tag: `Environment` = `Platform`
- [ ] Tag: `CostCenter` = `MSDN`
- [ ] Tag: `Owner` = `admin@skycraft.com`

### Development Resource Group

- [ ] Resource group name: `dev-skycraft-swc-rg`
- [ ] Location: **Sweden Central**
- [ ] Tag: `Project` = `SkyCraft`
- [ ] Tag: `Environment` = `Development`
- [ ] Tag: `CostCenter` = `MSDN`
- [ ] Tag: `Owner` = `admin@skycraft.com`

### Production Resource Group

- [ ] Resource group name: `prod-skycraft-swc-rg`
- [ ] Location: **Sweden Central**
- [ ] Tag: `Project` = `SkyCraft`
- [ ] Tag: `Environment` = `Production`
- [ ] Tag: `CostCenter` = `MSDN`
- [ ] Tag: `Owner` = `admin@skycraft.com`

---

## ✅ Hub Virtual Network (platform-skycraft-swc-vnet)

### Network Configuration

- [ ] Virtual network name: `platform-skycraft-swc-vnet`
- [ ] Location: **Sweden Central**
- [ ] Resource group: `platform-skycraft-swc-rg`
- [ ] Address space: `10.0.0.0/16`
- [ ] DNS servers: Default (Azure-provided)

### Subnets

- [ ] **AzureBastionSubnet**
  - Name: `AzureBastionSubnet` (exact match, case-sensitive)
  - Address range: `10.0.0.0/26`
  - Available IPs: 59 (64 total - 5 reserved)
- [ ] **GatewaySubnet**
  - Name: `GatewaySubnet` (exact match, case-sensitive)
  - Address range: `10.0.1.0/27`
  - Available IPs: 27 (32 total - 5 reserved)

### Peering Connections

- [ ] Peering name: `hub-to-dev`
  - Remote VNet: `dev-skycraft-swc-vnet`
  - Peering status: **Connected**
  - Allow virtual network access: **Enabled**
  - Allow forwarded traffic: **Enabled**
  - Allow gateway transit: **Disabled**
- [ ] Peering name: `hub-to-prod`
  - Remote VNet: `prod-skycraft-swc-vnet`
  - Peering status: **Connected**
  - Allow virtual network access: **Enabled**
  - Allow forwarded traffic: **Enabled**
  - Allow gateway transit: **Disabled**

### Tags

- [ ] Tag: `Project` = `SkyCraft`
- [ ] Tag: `Environment` = `Platform`
- [ ] Tag: `CostCenter` = `MSDN`
- [ ] Tag: `Owner` = `admin@skycraft.com`

---

## ✅ Development Virtual Network (dev-skycraft-swc-vnet)

### Network Configuration

- [ ] Virtual network name: `dev-skycraft-swc-vnet`
- [ ] Location: **Sweden Central**
- [ ] Resource group: `dev-skycraft-swc-rg`
- [ ] Address space: `10.1.0.0/16`
- [ ] DNS servers: Default (Azure-provided)

### Subnets

- [ ] **AuthSubnet**
  - Name: `AuthSubnet`
  - Address range: `10.1.1.0/24`
  - Available IPs: 251 (256 total - 5 reserved)
  - Purpose: Authentication server VMs
- [ ] **WorldSubnet**
  - Name: `WorldSubnet`
  - Address range: `10.1.2.0/24`
  - Available IPs: 251
  - Purpose: World server VMs
- [ ] **DatabaseSubnet**
  - Name: `DatabaseSubnet`
  - Address range: `10.1.3.0/24`
  - Available IPs: 251
  - Purpose: Database server VMs
- [ ] **AppServiceSubnet**
  - Name: `AppServiceSubnet`
  - Address range: `10.1.4.0/24`
  - Available IPs: 251
  - Purpose: App Service instances

### Peering Connections

- [ ] Peering name: `dev-to-hub`
  - Remote VNet: `platform-skycraft-swc-vnet`
  - Peering status: **Connected**
  - Allow virtual network access: **Enabled**
  - Allow forwarded traffic: **Enabled**
  - Use remote virtual network gateway: **Disabled**

### Tags

- [ ] Tag: `Project` = `SkyCraft`
- [ ] Tag: `Environment` = `Development`
- [ ] Tag: `CostCenter` = `MSDN`
- [ ] Tag: `Owner` = `admin@skycraft.com`

---

## ✅ Production Virtual Network (prod-skycraft-swc-vnet)

### Network Configuration

- [ ] Virtual network name: `prod-skycraft-swc-vnet`
- [ ] Location: **Sweden Central**
- [ ] Resource group: `prod-skycraft-swc-rg`
- [ ] Address space: `10.2.0.0/16`
- [ ] DNS servers: Default (Azure-provided)

### Subnets

- [ ] **AuthSubnet**
  - Name: `AuthSubnet`
  - Address range: `10.2.1.0/24`
  - Available IPs: 251 (256 total - 5 reserved)
  - Purpose: Authentication server VMs
- [ ] **WorldSubnet**
  - Name: `WorldSubnet`
  - Address range: `10.2.2.0/24`
  - Available IPs: 251
  - Purpose: World server VMs
- [ ] **DatabaseSubnet**
  - Name: `DatabaseSubnet`
  - Address range: `10.2.3.0/24`
  - Available IPs: 251
  - Purpose: Database server VMs
- [ ] **AppServiceSubnet**
  - Name: `AppServiceSubnet`
  - Address range: `10.2.4.0/24`
  - Available IPs: 251
  - Purpose: App Service instances

### Peering Connections

- [ ] Peering name: `prod-to-hub`
  - Remote VNet: `platform-skycraft-swc-vnet`
  - Peering status: **Connected**
  - Allow virtual network access: **Enabled**
  - Allow forwarded traffic: **Enabled**
  - Use remote virtual network gateway: **Disabled**

### Tags

- [ ] Tag: `Project` = `SkyCraft`
- [ ] Tag: `Environment` = `Production`
- [ ] Tag: `CostCenter` = `MSDN`
- [ ] Tag: `Owner` = `admin@skycraft.com`

---

## ✅ Public IP Addresses

### Dev Load Balancer Public IP

- [ ] Name: `dev-skycraft-swc-lb-pip`
- [ ] Resource group: `dev-skycraft-swc-rg`
- [ ] Location: **Sweden Central**
- [ ] SKU: **Standard**
- [ ] IP assignment: **Static**
- [ ] IP address assigned: [Record IP: ____________]
- [ ] Tags applied: Project, Environment, CostCenter, Owner

### Prod Load Balancer Public IP

- [ ] Name: `prod-skycraft-swc-lb-pip`
- [ ] Resource group: `prod-skycraft-swc-rg`
- [ ] Location: **Sweden Central**
- [ ] SKU: **Standard**
- [ ] IP assignment: **Static**
- [ ] IP address assigned: [Record IP: ____________]
- [ ] Tags applied: Project, Environment, CostCenter, Owner

---

## ✅ Network Topology Verification

### Network Watcher

- [ ] Network Watcher enabled for **Sweden Central** region
- [ ] Can access Network Watcher service
- [ ] Topology view displays hub-spoke architecture

### IP Address Planning Verification

- [ ] No overlapping address spaces between VNets
- [ ] Hub VNet (10.0.0.0/16) does not overlap with Dev (10.1.0.0/16)
- [ ] Hub VNet (10.0.0.0/16) does not overlap with Prod (10.2.0.0/16)
- [ ] Dev VNet (10.1.0.0/16) does not overlap with Prod (10.2.0.0/16)
- [ ] All subnet ranges fall within their parent VNet address space

### Peering Topology

- [ ] Hub has 2 peering connections (to dev and prod)
- [ ] Dev has 1 peering connection (to hub only)
- [ ] Prod has 1 peering connection (to hub only)
- [ ] Dev and Prod do NOT have direct peering (correct isolation)

---

## 🔍 Validation Commands

Run these Az PowerShell commands to validate your lab setup:

### Login and Set Context

```powershell
# Login to Azure
Connect-AzAccount

# List subscriptions
Get-AzSubscription | Select-Object Name, Id, State | Format-Table -AutoSize

# Set subscription context
Set-AzContext -SubscriptionName "YOUR-SUBSCRIPTION-NAME"
```

### Verify Resource Groups

```powershell
# List resource groups in Sweden Central
Get-AzResourceGroup |
    Where-Object { $_.Location -eq 'swedencentral' } |
    Select-Object ResourceGroupName, Location |
    Format-Table -AutoSize

# Expected: 3 resource groups (platform-skycraft-swc-rg, dev-skycraft-swc-rg, prod-skycraft-swc-rg)
```

### Verify Virtual Networks

```powershell
# List all VNets with subnet counts
Get-AzVirtualNetwork |
    Select-Object Name, ResourceGroupName,
        @{N='AddressSpace'; E={ $_.AddressSpace.AddressPrefixes -join ', ' }},
        @{N='Subnets'; E={ $_.Subnets.Count }} |
    Format-Table -AutoSize

# Expected output:
# Name                       ResourceGroupName         AddressSpace   Subnets
# -------------------------  ------------------------  -------------  -------
# platform-skycraft-swc-vnet platform-skycraft-swc-rg  10.0.0.0/16    2
# dev-skycraft-swc-vnet      dev-skycraft-swc-rg        10.1.0.0/16    4
# prod-skycraft-swc-vnet     prod-skycraft-swc-rg       10.2.0.0/16    4
```

### Verify Hub VNet Subnets

```powershell
# List hub VNet subnets
(Get-AzVirtualNetwork -ResourceGroupName 'platform-skycraft-swc-rg' -Name 'platform-skycraft-swc-vnet').Subnets |
    Select-Object Name, @{N='AddressPrefix'; E={ $_.AddressPrefix }} |
    Format-Table -AutoSize

# Expected output:
# Name                AddressPrefix
# ------------------  -------------
# AzureBastionSubnet  10.0.0.0/26
# GatewaySubnet       10.0.1.0/27
```

### Verify Dev VNet Subnets

```powershell
# List dev VNet subnets
(Get-AzVirtualNetwork -ResourceGroupName 'dev-skycraft-swc-rg' -Name 'dev-skycraft-swc-vnet').Subnets |
    Select-Object Name, @{N='AddressPrefix'; E={ $_.AddressPrefix }} |
    Format-Table -AutoSize

# Expected output:
# Name              AddressPrefix
# ----------------  -------------
# AuthSubnet        10.1.1.0/24
# WorldSubnet       10.1.2.0/24
# DatabaseSubnet    10.1.3.0/24
# AppServiceSubnet  10.1.4.0/24
```

### Verify Prod VNet Subnets

```powershell
# List prod VNet subnets
(Get-AzVirtualNetwork -ResourceGroupName 'prod-skycraft-swc-rg' -Name 'prod-skycraft-swc-vnet').Subnets |
    Select-Object Name, @{N='AddressPrefix'; E={ $_.AddressPrefix }} |
    Format-Table -AutoSize

# Expected output:
# Name              AddressPrefix
# ----------------  -------------
# AuthSubnet        10.2.1.0/24
# WorldSubnet       10.2.2.0/24
# DatabaseSubnet    10.2.3.0/24
# AppServiceSubnet  10.2.4.0/24
```

### Verify VNet Peering

```powershell
# List all peering connections for hub VNet
Get-AzVirtualNetworkPeering -ResourceGroupName 'platform-skycraft-swc-rg' -VirtualNetworkName 'platform-skycraft-swc-vnet' |
    Select-Object Name, PeeringState, AllowVirtualNetworkAccess, AllowForwardedTraffic |
    Format-Table -AutoSize

# Expected: 2 peerings (hub-to-dev, hub-to-prod) with PeeringState "Connected"

# List peering for dev VNet
Get-AzVirtualNetworkPeering -ResourceGroupName 'dev-skycraft-swc-rg' -VirtualNetworkName 'dev-skycraft-swc-vnet' |
    Select-Object Name, PeeringState |
    Format-Table -AutoSize

# Expected: 1 peering (dev-to-hub) with PeeringState "Connected"

# List peering for prod VNet
Get-AzVirtualNetworkPeering -ResourceGroupName 'prod-skycraft-swc-rg' -VirtualNetworkName 'prod-skycraft-swc-vnet' |
    Select-Object Name, PeeringState |
    Format-Table -AutoSize

# Expected: 1 peering (prod-to-hub) with PeeringState "Connected"
```

### Verify Public IP Addresses

```powershell
# List all public IPs
Get-AzPublicIpAddress |
    Select-Object Name, ResourceGroupName, Sku, IpAddress,
        @{N='Allocation'; E={ $_.PublicIpAllocationMethod }} |
    Format-Table -AutoSize

# Expected output:
# Name                      ResourceGroupName        Sku      IpAddress    Allocation
# ------------------------  -----------------------  -------  -----------  ----------
# dev-skycraft-swc-lb-pip   dev-skycraft-swc-rg       Standard [Public IP]  Static
# prod-skycraft-swc-lb-pip  prod-skycraft-swc-rg      Standard [Public IP]  Static
```

### Verify Tags

```powershell
# Check tags on hub VNet
(Get-AzVirtualNetwork -ResourceGroupName 'platform-skycraft-swc-rg' -Name 'platform-skycraft-swc-vnet').Tag

# Expected output:
# Key         Value
# ---         -----
# CostCenter  MSDN
# Environment Platform
# Owner       admin@skycraft.com
# Project     SkyCraft
```

---

## 📊 Network Architecture Summary

Use this table to document your deployed architecture:

| Component          | Name                       | Address Space | Subnets | Peerings | Status |
| :----------------- | :------------------------- | :------------ | :------ | :------- | :----- |
| **Hub VNet**       | platform-skycraft-swc-vnet | 10.0.0.0/16   | 2       | 2        | ✅     |
| └─ Bastion Subnet  | AzureBastionSubnet         | 10.0.0.0/26   | N/A     | N/A      | ✅     |
| └─ Gateway Subnet  | GatewaySubnet              | 10.0.1.0/27   | N/A     | N/A      | ✅     |
| **Dev VNet**       | dev-skycraft-swc-vnet      | 10.1.0.0/16   | 3       | 1        | ✅     |
| └─ Auth Subnet     | AuthSubnet                 | 10.1.1.0/24   | N/A     | N/A      | ✅     |
| └─ World Subnet    | WorldSubnet                | 10.1.2.0/24   | N/A     | N/A      | ✅     |
| └─ Database Subnet | DatabaseSubnet             | 10.1.3.0/24   | N/A     | N/A      | ✅     |
| **Prod VNet**      | prod-skycraft-swc-vnet     | 10.2.0.0/16   | 3       | 1        | ✅     |
| └─ Auth Subnet     | AuthSubnet                 | 10.2.1.0/24   | N/A     | N/A      | ✅     |
| └─ World Subnet    | WorldSubnet                | 10.2.2.0/24   | N/A     | N/A      | ✅     |
| └─ Database Subnet | DatabaseSubnet             | 10.2.3.0/24   | N/A     | N/A      | ✅     |

---

## 📝 Reflection Questions

Answer these questions to document your hands-on experience and demonstrate understanding:

### Question 1: IP Address Documentation

**Document the public IP addresses you created:**

| Resource                 | Public IP Address | Purpose                   |
| ------------------------ | ----------------- | ------------------------- |
| dev-skycraft-swc-lb-pip  | \***\*\_\_\*\***  | Development load balancer |
| prod-skycraft-swc-lb-pip | \***\*\_\_\*\***  | Production load balancer  |

### Question 2: Architecture Expansion

**If you were asked to add a "staging" environment (between dev and prod), how would you design it?**

- VNet name: **\*\*\*\***\_\_**\*\*\*\***
- Address space: **\*\*\*\***\_\_**\*\*\*\***
- Number of subnets: **\*\*\*\***\_\_**\*\*\*\***
- Peering connections: **\*\*\*\***\_\_**\*\*\*\***
- Justification for your design:

---

### Question 3: Troubleshooting Experience

**What was the most challenging part of this lab? How did you resolve it?**

---

### Question 4: Network Watcher Verification

**Attach or describe the Network Watcher topology view for your hub VNet:**

- [ ] Screenshot saved to: `images/my-network-topology.png`
- Does it match the expected architecture? ☐ Yes ☐ No
- If no, what differences exist?

---

### Question 5: Real-World Application

**How would you modify this architecture for a production gaming company with 5 environments (dev, test, staging, prod, disaster recovery)?**

---

---

## ⏱️ Completion Tracking

- **Estimated Time**: 3 hours
- **Actual Time Spent**: \***\*\_\*\*** hours
- **Date Started**: \***\*\_\*\***
- **Date Completed**: \***\*\_\*\***

---

## ✅ Final Lab 2.1 Sign-off

**All Verification Items Complete**:

- [ ] All resource groups created with proper tags
- [ ] Hub VNet deployed with correct subnets and peerings
- [ ] Dev VNet deployed with correct subnets and peering
- [ ] Prod VNet deployed with correct subnets and peering
- [ ] All VNet peering connections show "Connected" status
- [ ] 2 public IP addresses created (2 LB IPs)
- [ ] All resources follow naming conventions (platform/dev/prod-skycraft-swc-\*)
- [ ] All Azure CLI validation commands executed successfully
- [ ] Network Watcher topology verified
- [ ] All reflection questions answered correctly
- [ ] No overlapping IP address ranges
- [ ] Ready to proceed to Lab 2.2

**Student Name**: **\*\*\*\***\_**\*\*\*\***
**Lab 2.1 Completion Date**: **\*\*\*\***\_**\*\*\*\***
**Instructor Signature**: **\*\*\*\***\_**\*\*\*\***
