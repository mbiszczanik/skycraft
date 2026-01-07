# Lab 2.1 Completion Checklist

## ✅ Resource Groups Verification

### Platform Resource Group
- [ ] Resource group name: `platform-skycraft-swc-rg`
- [ ] Location: **Sweden Central**
- [ ] Tag: `Project` = `SkyCraft`
- [ ] Tag: `Environment` = `Platform`
- [ ] Tag: `CostCenter` = `MSDN`

### Development Resource Group
- [ ] Resource group name: `dev-skycraft-swc-rg`
- [ ] Location: **Sweden Central**
- [ ] Tag: `Project` = `SkyCraft`
- [ ] Tag: `Environment` = `Development`
- [ ] Tag: `CostCenter` = `MSDN`

### Production Resource Group
- [ ] Resource group name: `prod-skycraft-swc-rg`
- [ ] Location: **Sweden Central**
- [ ] Tag: `Project` = `SkyCraft`
- [ ] Tag: `Environment` = `Production`
- [ ] Tag: `CostCenter` = `MSDN`

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
  - Allow gateway transit: **Enabled**
  
- [ ] Peering name: `hub-to-prod`
  - Remote VNet: `prod-skycraft-swc-vnet`
  - Peering status: **Connected**
  - Allow virtual network access: **Enabled**
  - Allow forwarded traffic: **Enabled**
  - Allow gateway transit: **Enabled**

### Tags
- [ ] Tag: `Project` = `SkyCraft`
- [ ] Tag: `Environment` = `Platform`
- [ ] Tag: `CostCenter` = `MSDN`

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

### Peering Connections
- [ ] Peering name: `dev-to-hub`
  - Remote VNet: `platform-skycraft-swc-vnet`
  - Peering status: **Connected**
  - Allow virtual network access: **Enabled**
  - Allow forwarded traffic: **Enabled**
  - Use remote virtual network gateway: **Enabled**

### Tags
- [ ] Tag: `Project` = `SkyCraft`
- [ ] Tag: `Environment` = `Development`
- [ ] Tag: `CostCenter` = `MSDN`

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

### Peering Connections
- [ ] Peering name: `prod-to-hub`
  - Remote VNet: `platform-skycraft-swc-vnet`
  - Peering status: **Connected**
  - Allow virtual network access: **Enabled**
  - Allow forwarded traffic: **Enabled**
  - Use remote virtual network gateway: **Enabled**

### Tags
- [ ] Tag: `Project` = `SkyCraft`
- [ ] Tag: `Environment` = `Production`
- [ ] Tag: `CostCenter` = `MSDN`

---

## ✅ Public IP Addresses

### Bastion Public IP
- [ ] Name: `platform-skycraft-swc-bas-pip`
- [ ] Resource group: `platform-skycraft-swc-rg`
- [ ] Location: **Sweden Central**
- [ ] SKU: **Standard**
- [ ] IP assignment: **Static**
- [ ] IP address assigned: [Record IP: ____________]
- [ ] Tags applied: Project, Environment, CostCenter

### Dev Load Balancer Public IP
- [ ] Name: `dev-skycraft-swc-lb-pip`
- [ ] Resource group: `dev-skycraft-swc-rg`
- [ ] Location: **Sweden Central**
- [ ] SKU: **Standard**
- [ ] IP assignment: **Static**
- [ ] IP address assigned: [Record IP: ____________]
- [ ] Tags applied: Project, Environment, CostCenter

### Prod Load Balancer Public IP
- [ ] Name: `prod-skycraft-swc-lb-pip`
- [ ] Resource group: `prod-skycraft-swc-rg`
- [ ] Location: **Sweden Central**
- [ ] SKU: **Standard**
- [ ] IP assignment: **Static**
- [ ] IP address assigned: [Record IP: ____________]
- [ ] Tags applied: Project, Environment, CostCenter

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

Run these Azure CLI commands to validate your lab setup:

### Login and Set Context

```azurecli
# Login to Azure
az login

# List subscriptions
az account list --output table

# Set subscription context
az account set --subscription "YOUR-SUBSCRIPTION-NAME"
```


### Verify Resource Groups

```azurecli
# List resource groups with Sweden Central location
az group list \
  --query "[?location=='swedencentral'].{Name:name,Location:location,Tags:tags}" \
  --output table

# Expected: 3 resource groups (platform, dev, prod)
```


### Verify Virtual Networks

```azurecli
# List all VNets
az network vnet list \
  --query "[].{Name:name,ResourceGroup:resourceGroup,AddressSpace:addressSpace.addressPrefixes,Subnets:length(subnets)}" \
  --output table

# Expected output:
# Name                       ResourceGroup            AddressSpace    Subnets
# ------------------------   ----------------------   -------------   -------
# platform-skycraft-swc-vnet platform-skycraft-swc-rg 10.0.0.0/16     2
# dev-skycraft-swc-vnet      dev-skycraft-swc-rg      10.1.0.0/16     3
# prod-skycraft-swc-vnet     prod-skycraft-swc-rg     10.2.0.0/16     3
```


### Verify Hub VNet Subnets

```azurecli
# List hub VNet subnets
az network vnet subnet list \
  --resource-group platform-skycraft-swc-rg \
  --vnet-name platform-skycraft-swc-vnet \
  --query "[].{Name:name,AddressPrefix:addressPrefix}" \
  --output table

# Expected output:
# Name                AddressPrefix
# ------------------  -------------
# AzureBastionSubnet  10.0.0.0/26
# GatewaySubnet       10.0.1.0/27
```


### Verify Dev VNet Subnets

```azurecli
# List dev VNet subnets
az network vnet subnet list \
  --resource-group dev-skycraft-swc-rg \
  --vnet-name dev-skycraft-swc-vnet \
  --query "[].{Name:name,AddressPrefix:addressPrefix}" \
  --output table

# Expected output:
# Name             AddressPrefix
# ---------------  -------------
# AuthSubnet       10.1.1.0/24
# WorldSubnet      10.1.2.0/24
# DatabaseSubnet   10.1.3.0/24
```


### Verify Prod VNet Subnets

```azurecli
# List prod VNet subnets
az network vnet subnet list \
  --resource-group prod-skycraft-swc-rg \
  --vnet-name prod-skycraft-swc-vnet \
  --query "[].{Name:name,AddressPrefix:addressPrefix}" \
  --output table

# Expected output:
# Name             AddressPrefix
# ---------------  -------------
# AuthSubnet       10.2.1.0/24
# WorldSubnet      10.2.2.0/24
# DatabaseSubnet   10.2.3.0/24
```


### Verify VNet Peering

```azurecli
# List all peering connections for hub VNet
az network vnet peering list \
  --resource-group platform-skycraft-swc-rg \
  --vnet-name platform-skycraft-swc-vnet \
  --query "[].{Name:name,RemoteVNet:remoteVirtualNetwork.id,Status:peeringState}" \
  --output table

# Expected: 2 peerings (hub-to-dev, hub-to-prod) with status "Connected"

# List peering for dev VNet
az network vnet peering list \
  --resource-group dev-skycraft-swc-rg \
  --vnet-name dev-skycraft-swc-vnet \
  --query "[].{Name:name,Status:peeringState}" \
  --output table

# Expected: 1 peering (dev-to-hub) with status "Connected"

# List peering for prod VNet
az network vnet peering list \
  --resource-group prod-skycraft-swc-rg \
  --vnet-name prod-skycraft-swc-vnet \
  --query "[].{Name:name,Status:peeringState}" \
  --output table

# Expected: 1 peering (prod-to-hub) with status "Connected"
```


### Verify Public IP Addresses

```azurecli
# List all public IPs
az network public-ip list \
  --query "[].{Name:name,ResourceGroup:resourceGroup,SKU:sku.name,IP:ipAddress,Allocation:publicIpAllocationMethod}" \
  --output table

# Expected output:
# Name                           ResourceGroup            SKU       IP              Allocation
# -----------------------------  ----------------------   --------  --------------  ----------
# platform-skycraft-swc-bas-pip  platform-skycraft-swc-rg Standard  [Public IP]     Static
# dev-skycraft-swc-lb-pip        dev-skycraft-swc-rg      Standard  [Public IP]     Static
# prod-skycraft-swc-lb-pip       prod-skycraft-swc-rg     Standard  [Public IP]     Static
```


### Verify Tags

```azurecli
# Check tags on hub VNet
az network vnet show \
  --resource-group platform-skycraft-swc-rg \
  --name platform-skycraft-swc-vnet \
  --query tags

# Expected output:
# {
#   "CostCenter": "MSDN",
#   "Environment": "Platform",
#   "Project": "SkyCraft"
# }
```


---

## 📊 Network Architecture Summary

Use this table to document your deployed architecture:


| Component | Name | Address Space | Subnets | Peerings | Status |
| :-- | :-- | :-- | :-- | :-- | :-- |
| **Hub VNet** | platform-skycraft-swc-vnet | 10.0.0.0/16 | 2 | 2 | ✅ |
| └─ Bastion Subnet | AzureBastionSubnet | 10.0.0.0/26 | N/A | N/A | ✅ |
| └─ Gateway Subnet | GatewaySubnet | 10.0.1.0/27 | N/A | N/A | ✅ |
| **Dev VNet** | dev-skycraft-swc-vnet | 10.1.0.0/16 | 3 | 1 | ✅ |
| └─ Auth Subnet | AuthSubnet | 10.1.1.0/24 | N/A | N/A | ✅ |
| └─ World Subnet | WorldSubnet | 10.1.2.0/24 | N/A | N/A | ✅ |
| └─ Database Subnet | DatabaseSubnet | 10.1.3.0/24 | N/A | N/A | ✅ |
| **Prod VNet** | prod-skycraft-swc-vnet | 10.2.0.0/16 | 3 | 1 | ✅ |
| └─ Auth Subnet | AuthSubnet | 10.2.1.0/24 | N/A | N/A | ✅ |
| └─ World Subnet | WorldSubnet | 10.2.2.0/24 | N/A | N/A | ✅ |
| └─ Database Subnet | DatabaseSubnet | 10.2.3.0/24 | N/A | N/A | ✅ |


---

## 📝 Reflection Questions

Answer these questions to document your hands-on experience and demonstrate understanding:

### Question 1: IP Address Documentation
**Document the public IP addresses you created:**

| Resource | Public IP Address | Purpose |
|----------|-------------------|---------|
| platform-skycraft-swc-bas-pip | __________ | Azure Bastion administrative access |
| dev-skycraft-swc-lb-pip | __________ | Development load balancer |
| prod-skycraft-swc-lb-pip | __________ | Production load balancer |

### Question 2: Architecture Expansion
**If you were asked to add a "staging" environment (between dev and prod), how would you design it?**

- VNet name: __________________
- Address space: __________________
- Number of subnets: __________________
- Peering connections: __________________
- Justification for your design: 

_________________________________________________________________

### Question 3: Troubleshooting Experience
**What was the most challenging part of this lab? How did you resolve it?**

_________________________________________________________________


### Question 4: Network Watcher Verification
**Attach or describe the Network Watcher topology view for your hub VNet:**

- [ ] Screenshot saved to: `images/my-network-topology.png`
- Does it match the expected architecture? ☐ Yes ☐ No
- If no, what differences exist? 

_________________________________________________________________

### Question 5: Real-World Application
**How would you modify this architecture for a production gaming company with 5 environments (dev, test, staging, prod, disaster recovery)?**

_________________________________________________________________

---

## ⏱️ Completion Tracking

- **Estimated Time**: 3 hours
- **Actual Time Spent**: _________ hours
- **Date Started**: _________
- **Date Completed**: _________

---

## ✅ Final Lab 2.1 Sign-off

**All Verification Items Complete**:

- [ ] All resource groups created with proper tags
- [ ] Hub VNet deployed with correct subnets and peerings
- [ ] Dev VNet deployed with correct subnets and peering
- [ ] Prod VNet deployed with correct subnets and peering
- [ ] All VNet peering connections show "Connected" status
- [ ] 3 public IP addresses created (Bastion + 2 LB)
- [ ] All resources follow naming conventions (platform/dev/prod-skycraft-swc-*)
- [ ] All Azure CLI validation commands executed successfully
- [ ] Network Watcher topology verified
- [ ] All reflection questions answered correctly
- [ ] No overlapping IP address ranges
- [ ] Ready to proceed to Lab 2.2

**Student Name**: _________________
**Lab 2.1 Completion Date**: _________________
**Instructor Signature**: _________________