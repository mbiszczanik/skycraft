# Lab 2.2 Completion Checklist

## ✅ Azure Bastion Verification

### Bastion Resource
- [ ] Resource name: `platform-skycraft-swc-bas`
- [ ] Resource group: `platform-skycraft-swc-rg`
- [ ] Location: **Sweden Central**
- [ ] Tier: **Basic**
- [ ] Virtual network: `platform-skycraft-swc-vnet`
- [ ] Subnet: `AzureBastionSubnet (10.0.0.0/26)`
- [ ] Deployment status: **Succeeded**

### Bastion Public IP
- [ ] Public IP name: `platform-skycraft-swc-bas-pip`
- [ ] SKU: **Standard**
- [ ] IP allocation: **Static**
- [ ] IP address assigned: [Record IP: ____________]
- [ ] Associated with: `platform-skycraft-swc-bas`

### Bastion Tags
- [ ] Tag: `Project` = `SkyCraft`
- [ ] Tag: `Environment` = `Platform`
- [ ] Tag: `CostCenter` = `MSDN`

---

## ✅ Development Environment NSGs

### dev-skycraft-swc-auth-nsg

**Configuration**:
- [ ] Resource group: `dev-skycraft-swc-rg`
- [ ] Location: **Sweden Central**
- [ ] Associated subnet: `dev-skycraft-swc-vnet/AuthSubnet`

**Inbound Security Rules**:
- [ ] Priority 100: `Allow-SSH-From-Bastion`
  - Source: `10.0.0.0/26` (Bastion subnet)
  - Destination port: `22`
  - Protocol: TCP
  - Action: Allow

- [ ] Priority 110: `Allow-Auth-GamePort`
  - Source: Any
  - Destination port: `3724`
  - Protocol: TCP
  - Action: Allow

**Tags**:
- [ ] Tag: `Project` = `SkyCraft`
- [ ] Tag: `Environment` = `Development`
- [ ] Tag: `CostCenter` = `MSDN`

### dev-skycraft-swc-world-nsg

**Configuration**:
- [ ] Resource group: `dev-skycraft-swc-rg`
- [ ] Location: **Sweden Central**
- [ ] Associated subnet: `dev-skycraft-swc-vnet/WorldSubnet`

**Inbound Security Rules**:
- [ ] Priority 100: `Allow-SSH-From-Bastion`
  - Source: `10.0.0.0/26`
  - Destination port: `22`
  - Protocol: TCP
  - Action: Allow

- [ ] Priority 110: `Allow-World-GamePort`
  - Source: Any
  - Destination port: `8085`
  - Protocol: TCP
  - Action: Allow

**Tags**:
- [ ] Tag: `Project` = `SkyCraft`
- [ ] Tag: `Environment` = `Development`
- [ ] Tag: `CostCenter` = `MSDN`

### dev-skycraft-swc-db-nsg

**Configuration**:
- [ ] Resource group: `dev-skycraft-swc-rg`
- [ ] Location: **Sweden Central**
- [ ] Associated subnet: `dev-skycraft-swc-vnet/DatabaseSubnet`

**Inbound Security Rules**:
- [ ] Priority 100: `Allow-SSH-From-Bastion`
  - Source: `10.0.0.0/26`
  - Destination port: `22`
  - Protocol: TCP
  - Action: Allow

- [ ] Priority 110: `Allow-MySQL-From-AppTier`
  - Source: `10.1.1.0/24,10.1.2.0/24` (Auth and World subnets)
  - Destination port: `3306`
  - Protocol: TCP
  - Action: Allow

**Tags**:
- [ ] Tag: `Project` = `SkyCraft`
- [ ] Tag: `Environment` = `Development`
- [ ] Tag: `CostCenter` = `MSDN`

---

## ✅ Production Environment NSGs

### prod-skycraft-swc-auth-nsg

**Configuration**:
- [ ] Resource group: `prod-skycraft-swc-rg`
- [ ] Location: **Sweden Central**
- [ ] Associated subnet: `prod-skycraft-swc-vnet/AuthSubnet`

**Inbound Security Rules**:
- [ ] Priority 100: `Allow-SSH-From-Bastion` (Source: 10.0.0.0/26, Port: 22)
- [ ] Priority 110: `Allow-Auth-GamePort` (Source: Any, Port: 3724)

**Tags**:
- [ ] Tag: `Project` = `SkyCraft`
- [ ] Tag: `Environment` = `Production`
- [ ] Tag: `CostCenter` = `MSDN`

### prod-skycraft-swc-world-nsg

**Configuration**:
- [ ] Resource group: `prod-skycraft-swc-rg`
- [ ] Location: **Sweden Central**
- [ ] Associated subnet: `prod-skycraft-swc-vnet/WorldSubnet`

**Inbound Security Rules**:
- [ ] Priority 100: `Allow-SSH-From-Bastion` (Source: 10.0.0.0/26, Port: 22)
- [ ] Priority 110: `Allow-World-GamePort` (Source: Any, Port: 8085)

**Tags**:
- [ ] Tag: `Project` = `SkyCraft`
- [ ] Tag: `Environment` = `Production`
- [ ] Tag: `CostCenter` = `MSDN`

### prod-skycraft-swc-db-nsg

**Configuration**:
- [ ] Resource group: `prod-skycraft-swc-rg`
- [ ] Location: **Sweden Central**
- [ ] Associated subnet: `prod-skycraft-swc-vnet/DatabaseSubnet`

**Inbound Security Rules**:
- [ ] Priority 100: `Allow-SSH-From-Bastion` (Source: 10.0.0.0/26, Port: 22)
- [ ] Priority 110: `Allow-MySQL-From-AppTier` (Source: 10.2.1.0/24,10.2.2.0/24, Port: 3306)

**Tags**:
- [ ] Tag: `Project` = `SkyCraft`
- [ ] Tag: `Environment` = `Production`
- [ ] Tag: `CostCenter` = `MSDN`

---

## ✅ Application Security Groups

### dev-skycraft-swc-asg-auth
- [ ] Resource name: `dev-skycraft-swc-asg-auth`
- [ ] Resource group: `dev-skycraft-swc-rg`
- [ ] Location: **Sweden Central**
- [ ] Purpose: Group authentication server VMs
- [ ] Tags applied: Project, Environment, CostCenter

### dev-skycraft-swc-asg-world
- [ ] Resource name: `dev-skycraft-swc-asg-world`
- [ ] Resource group: `dev-skycraft-swc-rg`
- [ ] Location: **Sweden Central**
- [ ] Purpose: Group world server VMs
- [ ] Tags applied: Project, Environment, CostCenter

### dev-skycraft-swc-asg-db
- [ ] Resource name: `dev-skycraft-swc-asg-db`
- [ ] Resource group: `dev-skycraft-swc-rg`
- [ ] Location: **Sweden Central**
- [ ] Purpose: Group database server VMs
- [ ] Tags applied: Project, Environment, CostCenter

---

## ✅ Service Endpoints Configuration

### Development Database Subnet
- [ ] VNet: `dev-skycraft-swc-vnet`
- [ ] Subnet: `DatabaseSubnet (10.1.3.0/24)`
- [ ] Service endpoint: **Microsoft.Sql** enabled
- [ ] Service endpoint: **Microsoft.Storage** enabled
- [ ] Status: **Succeeded**

### Production Database Subnet
- [ ] VNet: `prod-skycraft-swc-vnet`
- [ ] Subnet: `DatabaseSubnet (10.2.3.0/24)`
- [ ] Service endpoint: **Microsoft.Sql** enabled
- [ ] Service endpoint: **Microsoft.Storage** enabled
- [ ] Status: **Succeeded**

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

# Verify current subscription
az account show --query "{Name:name, SubscriptionId:id}" --output table
```

### Verify Azure Bastion

```azurecli
# List Bastion hosts
az network bastion list   --resource-group platform-skycraft-swc-rg   --query "[].{Name:name,Location:location,ProvisioningState:provisioningState,VNet:virtualNetwork.id}"   --output table

# Expected output:
# Name                      Location       ProvisioningState  VNet
# ------------------------  -------------  -----------------  ------------------------------------
# platform-skycraft-swc-bas Sweden Central Succeeded          /subscriptions/.../platform-skycraft-swc-vnet

# Show Bastion details
az network bastion show   --resource-group platform-skycraft-swc-rg   --name platform-skycraft-swc-bas   --query "{Name:name,Tier:sku.name,PublicIP:ipConfigurations[0].publicIpAddress.id}"   --output json
```

### Verify Network Security Groups

```azurecli
# List all NSGs
az network nsg list   --query "[].{Name:name,ResourceGroup:resourceGroup,Location:location,Subnets:length(subnets)}"   --output table

# Expected output:
# Name                          ResourceGroup            Location       Subnets
# ----------------------------  ----------------------   -------------  -------
# dev-skycraft-swc-auth-nsg     dev-skycraft-swc-rg      Sweden Central 1
# dev-skycraft-swc-world-nsg    dev-skycraft-swc-rg      Sweden Central 1
# dev-skycraft-swc-db-nsg       dev-skycraft-swc-rg      Sweden Central 1
# prod-skycraft-swc-auth-nsg    prod-skycraft-swc-rg     Sweden Central 1
# prod-skycraft-swc-world-nsg   prod-skycraft-swc-rg     Sweden Central 1
# prod-skycraft-swc-db-nsg      prod-skycraft-swc-rg     Sweden Central 1
```

### Verify NSG Rules (Dev Auth NSG)

```azurecli
# List custom inbound rules for dev auth NSG
az network nsg rule list   --resource-group dev-skycraft-swc-rg   --nsg-name dev-skycraft-swc-auth-nsg   --query "[?priority<1000].{Priority:priority,Name:name,Port:destinationPortRange,Source:sourceAddressPrefix,Action:access}"   --output table

# Expected output:
# Priority  Name                      Port  Source       Action
# --------  ------------------------  ----  -----------  ------
# 100       Allow-SSH-From-Bastion    22    10.0.0.0/26  Allow
# 110       Allow-Auth-GamePort       3724  *            Allow
```

### Verify NSG Subnet Associations

```azurecli
# Check which subnet is associated with dev auth NSG
az network nsg show   --resource-group dev-skycraft-swc-rg   --name dev-skycraft-swc-auth-nsg   --query "{NSG:name,AssociatedSubnets:subnets[].id}"   --output json

# Verify all dev NSG associations
az network vnet subnet list   --resource-group dev-skycraft-swc-rg   --vnet-name dev-skycraft-swc-vnet   --query "[].{Subnet:name,AddressPrefix:addressPrefix,NSG:networkSecurityGroup.id}"   --output table

# Expected output:
# Subnet         AddressPrefix  NSG
# -------------  -------------  ------------------------------------------------
# AuthSubnet     10.1.1.0/24    /subscriptions/.../dev-skycraft-swc-auth-nsg
# WorldSubnet    10.1.2.0/24    /subscriptions/.../dev-skycraft-swc-world-nsg
# DatabaseSubnet 10.1.3.0/24    /subscriptions/.../dev-skycraft-swc-db-nsg
```

### Verify Application Security Groups

```azurecli
# List all ASGs
az network asg list   --query "[].{Name:name,ResourceGroup:resourceGroup,Location:location}"   --output table

# Expected output:
# Name                         ResourceGroup            Location
# ---------------------------  ----------------------   -------------
# dev-skycraft-swc-asg-auth    dev-skycraft-swc-rg      Sweden Central
# dev-skycraft-swc-asg-world   dev-skycraft-swc-rg      Sweden Central
# dev-skycraft-swc-asg-db      dev-skycraft-swc-rg      Sweden Central
```

### Verify Service Endpoints

```azurecli
# Check service endpoints on dev database subnet
az network vnet subnet show   --resource-group dev-skycraft-swc-rg   --vnet-name dev-skycraft-swc-vnet   --name DatabaseSubnet   --query "{Subnet:name,ServiceEndpoints:serviceEndpoints[].service}"   --output json

# Expected output:
# {
#   "Subnet": "DatabaseSubnet",
#   "ServiceEndpoints": [
#     "Microsoft.Sql",
#     "Microsoft.Storage"
#   ]
# }

# Check service endpoints on prod database subnet
az network vnet subnet show   --resource-group prod-skycraft-swc-rg   --vnet-name prod-skycraft-swc-vnet   --name DatabaseSubnet   --query "{Subnet:name,ServiceEndpoints:serviceEndpoints[].service}"   --output json
```

### Verify Tags on NSGs

```azurecli
# Check tags on dev auth NSG
az network nsg show   --resource-group dev-skycraft-swc-rg   --name dev-skycraft-swc-auth-nsg   --query tags   --output json

# Expected output:
# {
#   "CostCenter": "MSDN",
#   "Environment": "Development",
#   "Project": "SkyCraft"
# }

# Check tags on all NSGs
az network nsg list   --query "[].{Name:name,Environment:tags.Environment,Project:tags.Project,CostCenter:tags.CostCenter}"   --output table
```

### Verify Bastion Public IP

```azurecli
# Check public IP used by Bastion
az network public-ip show   --resource-group platform-skycraft-swc-rg   --name platform-skycraft-swc-bas-pip   --query "{Name:name,IP:ipAddress,SKU:sku.name,Allocation:publicIpAllocationMethod}"   --output table

# Expected output:
# Name                           IP              SKU       Allocation
# -----------------------------  --------------  --------  ----------
# platform-skycraft-swc-bas-pip  [Public IP]     Standard  Static
```

---

## 📊 Security Architecture Summary

Use this table to document your deployed security architecture:

| Component | Name | Associated Resource | Rules/Config | Status |
|-----------|------|---------------------|--------------|--------|
| **Azure Bastion** | platform-skycraft-swc-bas | AzureBastionSubnet | Tier: Basic | ✅ |
| **Dev Auth NSG** | dev-skycraft-swc-auth-nsg | dev-skycraft-swc-vnet/AuthSubnet | 2 custom rules | ✅ |
| **Dev World NSG** | dev-skycraft-swc-world-nsg | dev-skycraft-swc-vnet/WorldSubnet | 2 custom rules | ✅ |
| **Dev DB NSG** | dev-skycraft-swc-db-nsg | dev-skycraft-swc-vnet/DatabaseSubnet | 2 custom rules | ✅ |
| **Prod Auth NSG** | prod-skycraft-swc-auth-nsg | prod-skycraft-swc-vnet/AuthSubnet | 2 custom rules | ✅ |
| **Prod World NSG** | prod-skycraft-swc-world-nsg | prod-skycraft-swc-vnet/WorldSubnet | 2 custom rules | ✅ |
| **Prod DB NSG** | prod-skycraft-swc-db-nsg | prod-skycraft-swc-vnet/DatabaseSubnet | 2 custom rules | ✅ |
| **Auth ASG** | dev-skycraft-swc-asg-auth | N/A | Ready for VM assignment | ✅ |
| **World ASG** | dev-skycraft-swc-asg-world | N/A | Ready for VM assignment | ✅ |
| **DB ASG** | dev-skycraft-swc-asg-db | N/A | Ready for VM assignment | ✅ |
| **Service Endpoints** | Microsoft.Sql, Microsoft.Storage | Dev & Prod DatabaseSubnets | Enabled | ✅ |

---

## 📊 NSG Rules Summary

Document the security rules deployed:

### Development Environment

| NSG | Priority | Rule Name | Source | Dest Port | Protocol | Action |
|-----|----------|-----------|--------|-----------|----------|--------|
| auth-nsg | 100 | Allow-SSH-From-Bastion | 10.0.0.0/26 | 22 | TCP | Allow |
| auth-nsg | 110 | Allow-Auth-GamePort | Any | 3724 | TCP | Allow |
| world-nsg | 100 | Allow-SSH-From-Bastion | 10.0.0.0/26 | 22 | TCP | Allow |
| world-nsg | 110 | Allow-World-GamePort | Any | 8085 | TCP | Allow |
| db-nsg | 100 | Allow-SSH-From-Bastion | 10.0.0.0/26 | 22 | TCP | Allow |
| db-nsg | 110 | Allow-MySQL-From-AppTier | 10.1.1.0/24,10.1.2.0/24 | 3306 | TCP | Allow |

### Production Environment

| NSG | Priority | Rule Name | Source | Dest Port | Protocol | Action |
|-----|----------|-----------|--------|-----------|----------|--------|
| auth-nsg | 100 | Allow-SSH-From-Bastion | 10.0.0.0/26 | 22 | TCP | Allow |
| auth-nsg | 110 | Allow-Auth-GamePort | Any | 3724 | TCP | Allow |
| world-nsg | 100 | Allow-SSH-From-Bastion | 10.0.0.0/26 | 22 | TCP | Allow |
| world-nsg | 110 | Allow-World-GamePort | Any | 8085 | TCP | Allow |
| db-nsg | 100 | Allow-SSH-From-Bastion | 10.0.0.0/26 | 22 | TCP | Allow |
| db-nsg | 110 | Allow-MySQL-From-AppTier | 10.2.1.0/24,10.2.2.0/24 | 3306 | TCP | Allow |

---

## 📝 Reflection Questions

Answer these questions to document your hands-on experience and demonstrate understanding:

### Question 1: Bastion Public IP Documentation
**Document the public IP address assigned to Azure Bastion:**

- Public IP resource name: `platform-skycraft-swc-bas-pip`
- Assigned IP address: __________
- How would you access this in a production environment? 

_________________________________________________________________

_________________________________________________________________

### Question 2: NSG Rule Priority Planning
**You need to add a new rule to allow HTTPS (443) from a specific management IP (203.0.113.0/24) to the Auth servers. What priority would you assign and why?**

- Priority chosen: __________
- Reasoning:

_________________________________________________________________

_________________________________________________________________

### Question 3: Troubleshooting Experience
**What was the most challenging part of configuring NSGs or Bastion? How did you resolve it?**

_________________________________________________________________

_________________________________________________________________

_________________________________________________________________

### Question 4: Security Rule Testing
**When VMs are deployed in Module 3, how will you test that the NSG rules are working correctly?**

Testing plan:
1. _________________________________________________________________
2. _________________________________________________________________
3. _________________________________________________________________

### Question 5: Service Endpoints vs Private Endpoints
**Based on the SkyCraft requirements, when would you recommend using Private Endpoints instead of Service Endpoints for the database connectivity?**

_________________________________________________________________

_________________________________________________________________

_________________________________________________________________

### Question 6: ASG Implementation Strategy
**In Module 3 when you deploy VMs, describe your plan for assigning VMs to Application Security Groups:**

| VM Type | ASG Assignment | Reason |
|---------|----------------|--------|
| Auth Server VM 1 | __________________ | __________________ |
| World Server VM 1 | __________________ | __________________ |
| Database VM 1 | __________________ | __________________ |

### Question 7: Defense-in-Depth Evaluation
**Review your implemented security layers. If you had to add one more security control, what would it be and why?**

Additional security control: __________

Justification:

_________________________________________________________________

_________________________________________________________________

**Instructor Review Date**: _________  
**Feedback**: 

_________________________________________________________________

_________________________________________________________________

---

## ⏱️ Completion Tracking

- **Estimated Time**: 2.5 hours
- **Actual Time Spent**: _________ hours
- **Date Started**: _________
- **Date Completed**: _________

**Challenges Encountered**:

_________________________________________________________________

_________________________________________________________________

**Most Valuable Learning**:

_________________________________________________________________

_________________________________________________________________

---

## ✅ Final Lab 2.2 Sign-off

**All Verification Items Complete**:
- [ ] Azure Bastion deployed and operational in hub VNet
- [ ] 6 Network Security Groups created (3 dev, 3 prod)
- [ ] All NSGs have proper inbound security rules configured
- [ ] All NSGs associated with correct subnets
- [ ] 3 Application Security Groups created for dev environment
- [ ] Service endpoints enabled on dev and prod database subnets
- [ ] All resources have required tags (Project, Environment, CostCenter)
- [ ] All validation commands executed successfully
- [ ] All reflection questions answered
- [ ] No NSG associated with AzureBastionSubnet (Bastion manages own security)
- [ ] Ready to proceed to Lab 2.3

**Student Name**: _________________  
**Lab 2.2 Completion Date**: _________________  
**Instructor Signature**: _________________

---

## 🎉 Congratulations!

You've successfully implemented **comprehensive network security** for the SkyCraft infrastructure!

**What You Built**:
- ✅ Azure Bastion for secure administrative access (no public IPs on VMs needed)
- ✅ 6 Network Security Groups with least-privilege access rules
- ✅ 3 Application Security Groups for role-based management
- ✅ Service endpoints for secure Azure PaaS connectivity
- ✅ Defense-in-depth security architecture

**Security Achievements**:
- 🔒 **Layer 1**: Azure Bastion blocks direct SSH/RDP from internet
- 🔒 **Layer 2**: NSGs control traffic at subnet level
- 🔒 **Layer 3**: ASGs simplify VM role-based security
- 🔒 **Layer 4**: Service endpoints secure PaaS traffic
- 🔒 **Layer 5**: Private endpoints ready for maximum security

**Network Security Posture**:
- All administrative access goes through Bastion
- Game servers only expose required ports (3724 for auth, 8085 for world)
- Databases only accept connections from application tiers
- Azure SQL and Storage accessed over Microsoft backbone (not public internet)

**Next Steps**: In **Lab 2.3**, you'll configure Azure DNS for custom domain resolution and deploy Azure Load Balancer to distribute traffic across multiple game servers for high availability.

---

## 📌 Module Navigation

- [← Back to Module 2 Index](../README.md)
- [← Previous Lab: 2.1 Virtual Networks](../2.1-virtual-networks/lab-checklist-2.1.md)
- [Lab Guide: 2.2 Secure Access →](lab-guide-2.2.md)
- [Next Lab: 2.3 DNS & Load Balancing →](../2.3-dns-load-balancing/lab-checklist-2.3.md)
