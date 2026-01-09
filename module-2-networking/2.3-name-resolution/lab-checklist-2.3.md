# Lab 2.3 Completion Checklist

## ✅ Azure Public DNS Zone Verification

### DNS Zone Configuration
- [ ] DNS zone name: `skycraft.example.com`
- [ ] Resource group: `platform-skycraft-swc-rg`
- [ ] Location: **Sweden Central**
- [ ] Status: **Running**
- [ ] Name servers assigned: 4 (ns1-XX.azure-dns.com format)

### DNS Records
- [ ] **A record**: `dev.skycraft.example.com`
  - Type: A
  - TTL: 300 seconds
  - IP address: [Record IP: ____________] (dev-skycraft-swc-lb-pip)

- [ ] **A record**: `play.skycraft.example.com`
  - Type: A
  - TTL: 300 seconds
  - IP address: [Record IP: ____________] (prod-skycraft-swc-lb-pip)

- [ ] **CNAME record**: `game.skycraft.example.com`
  - Type: CNAME
  - TTL: 3600 seconds
  - Alias: `play.skycraft.example.com`

### Tags
- [ ] Tag: `Project` = `SkyCraft`
- [ ] Tag: `Environment` = `Platform`
- [ ] Tag: `CostCenter` = `MSDN`

---

## ✅ Azure Private DNS Zone Verification

### Private DNS Zone Configuration
- [ ] DNS zone name: `skycraft.internal`
- [ ] Resource group: `platform-skycraft-swc-rg`
- [ ] Location: **Sweden Central**
- [ ] Virtual network links: 3 (hub, dev, prod)

### Virtual Network Links
- [ ] **Link 1**: `hub-vnet-link`
  - Virtual network: `platform-skycraft-swc-vnet`
  - Auto-registration: **Disabled**
  - Link state: **Completed**

- [ ] **Link 2**: `dev-vnet-link`
  - Virtual network: `dev-skycraft-swc-vnet`
  - Auto-registration: **Enabled**
  - Link state: **Completed**

- [ ] **Link 3**: `prod-vnet-link`
  - Virtual network: `prod-skycraft-swc-vnet`
  - Auto-registration: **Enabled**
  - Link state: **Completed**

### Private DNS Records
- [ ] **A record**: `dev-db.skycraft.internal`
  - Type: A
  - TTL: 300 seconds
  - IP address: `10.1.3.10`

- [ ] **A record**: `prod-db.skycraft.internal`
  - Type: A
  - TTL: 300 seconds
  - IP address: `10.2.3.10`

### Tags
- [ ] Tag: `Project` = `SkyCraft`
- [ ] Tag: `Environment` = `Platform`
- [ ] Tag: `CostCenter` = `MSDN`

---

## ✅ Development Load Balancer (dev-skycraft-swc-lb)

### Load Balancer Configuration
- [ ] Resource name: `dev-skycraft-swc-lb`
- [ ] Resource group: `dev-skycraft-swc-rg`
- [ ] Location: **Sweden Central**
- [ ] SKU: **Standard**
- [ ] Type: **Public**
- [ ] Tier: **Regional**

### Frontend IP Configuration
- [ ] Name: `dev-skycraft-swc-lb-frontend`
- [ ] IP version: IPv4
- [ ] Public IP address: `dev-skycraft-swc-lb-pip`
- [ ] IP address assigned: [Record IP: ____________]

### Backend Pools
- [ ] **Backend pool 1**: `dev-skycraft-swc-lb-be-world`
  - Virtual network: `dev-skycraft-swc-vnet`
  - Backend pool configuration: NIC
  - IP version: IPv4
  - VMs in pool: 0 (ready for Module 3)

- [ ] **Backend pool 2**: `dev-skycraft-swc-lb-be-auth`
  - Virtual network: `dev-skycraft-swc-vnet`
  - Backend pool configuration: NIC
  - IP version: IPv4
  - VMs in pool: 0 (ready for Module 3)

### Health Probes
- [ ] **Health probe 1**: `dev-skycraft-swc-lb-probe-world`
  - Protocol: TCP
  - Port: `8085`
  - Interval: 15 seconds
  - Unhealthy threshold: 2

- [ ] **Health probe 2**: `dev-skycraft-swc-lb-probe-auth`
  - Protocol: TCP
  - Port: `3724`
  - Interval: 15 seconds
  - Unhealthy threshold: 2

### Load Balancing Rules
- [ ] **Rule 1**: `dev-skycraft-swc-lb-rule-world`
  - Frontend IP: `dev-skycraft-swc-lb-frontend`
  - Protocol: TCP
  - Port: `8085`
  - Backend port: `8085`
  - Backend pool: `dev-skycraft-swc-lb-be-world`
  - Health probe: `dev-skycraft-swc-lb-probe-world`
  - Session persistence: None (5-tuple hash)
  - Idle timeout: 4 minutes
  - TCP reset: Enabled

- [ ] **Rule 2**: `dev-skycraft-swc-lb-rule-auth`
  - Frontend IP: `dev-skycraft-swc-lb-frontend`
  - Protocol: TCP
  - Port: `3724`
  - Backend port: `3724`
  - Backend pool: `dev-skycraft-swc-lb-be-auth`
  - Health probe: `dev-skycraft-swc-lb-probe-auth`
  - Session persistence: None
  - Idle timeout: 4 minutes

### Tags
- [ ] Tag: `Project` = `SkyCraft`
- [ ] Tag: `Environment` = `Development`
- [ ] Tag: `CostCenter` = `MSDN`

---

## ✅ Production Load Balancer (prod-skycraft-swc-lb)

### Load Balancer Configuration
- [ ] Resource name: `prod-skycraft-swc-lb`
- [ ] Resource group: `prod-skycraft-swc-rg`
- [ ] Location: **Sweden Central**
- [ ] SKU: **Standard**
- [ ] Type: **Public**
- [ ] Tier: **Regional**

### Frontend IP Configuration
- [ ] Name: `prod-skycraft-swc-lb-frontend`
- [ ] Public IP address: `prod-skycraft-swc-lb-pip`
- [ ] IP address assigned: [Record IP: ____________]

### Backend Pools
- [ ] **Backend pool 1**: `prod-skycraft-swc-lb-be-world`
  - Virtual network: `prod-skycraft-swc-vnet`
  - Backend pool configuration: NIC
  - VMs in pool: 0 (ready for Module 3)

- [ ] **Backend pool 2**: `prod-skycraft-swc-lb-be-auth`
  - Virtual network: `prod-skycraft-swc-vnet`
  - Backend pool configuration: NIC
  - VMs in pool: 0 (ready for Module 3)

### Health Probes
- [ ] **Health probe 1**: `prod-skycraft-swc-lb-probe-world`
  - Protocol: TCP
  - Port: `8085`
  - Interval: 15 seconds
  - Unhealthy threshold: 2

- [ ] **Health probe 2**: `prod-skycraft-swc-lb-probe-auth`
  - Protocol: TCP
  - Port: `3724`
  - Interval: 15 seconds
  - Unhealthy threshold: 2

### Load Balancing Rules
- [ ] **Rule 1**: `prod-skycraft-swc-lb-rule-world`
  - Port: `8085` → Backend port: `8085`
  - Backend pool: `prod-skycraft-swc-lb-be-world`
  - Health probe: `prod-skycraft-swc-lb-probe-world`

- [ ] **Rule 2**: `prod-skycraft-swc-lb-rule-auth`
  - Port: `3724` → Backend port: `3724`
  - Backend pool: `prod-skycraft-swc-lb-be-auth`
  - Health probe: `prod-skycraft-swc-lb-probe-auth`

### Tags
- [ ] Tag: `Project` = `SkyCraft`
- [ ] Tag: `Environment` = `Production`
- [ ] Tag: `CostCenter` = `MSDN`

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

### Verify Public DNS Zone

```azurecli
# List DNS zones
az network dns zone list   --query "[].{Name:name,ResourceGroup:resourceGroup,NumberOfRecordSets:numberOfRecordSets}"   --output table

# Expected output:
# Name                    ResourceGroup            NumberOfRecordSets
# ----------------------  ----------------------   ------------------
# skycraft.example.com    platform-skycraft-swc-rg 5

# List DNS records in zone
az network dns record-set list   --resource-group platform-skycraft-swc-rg   --zone-name skycraft.example.com   --query "[].{Name:name,Type:type,TTL:ttl}"   --output table

# Expected output:
# Name  Type   TTL
# ----  -----  ----
# @     NS     172800
# @     SOA    3600
# dev   A      300
# play  A      300
# game  CNAME  3600

# Get specific A record
az network dns record-set a show   --resource-group platform-skycraft-swc-rg   --zone-name skycraft.example.com   --name dev   --query "{Name:name,TTL:ttl,IPs:aRecords[].ipv4Address}"   --output json
```

### Verify Private DNS Zone

```azurecli
# List Private DNS zones
az network private-dns zone list   --query "[].{Name:name,ResourceGroup:resourceGroup,NumberOfRecordSets:numberOfRecordSets,NumberOfVNetLinks:numberOfVirtualNetworkLinks}"   --output table

# Expected output:
# Name               ResourceGroup            NumberOfRecordSets  NumberOfVNetLinks
# -----------------  ----------------------   ------------------  -----------------
# skycraft.internal  platform-skycraft-swc-rg 4                   3

# List virtual network links
az network private-dns link vnet list   --resource-group platform-skycraft-swc-rg   --zone-name skycraft.internal   --query "[].{Name:name,VNet:virtualNetwork.id,RegistrationEnabled:registrationEnabled,ProvisioningState:provisioningState}"   --output table

# Expected output:
# Name            VNet                                           RegistrationEnabled  ProvisioningState
# --------------  ---------------------------------------------  -------------------  -----------------
# hub-vnet-link   /subscriptions/.../platform-skycraft-swc-vnet  False                Succeeded
# dev-vnet-link   /subscriptions/.../dev-skycraft-swc-vnet       True                 Succeeded
# prod-vnet-link  /subscriptions/.../prod-skycraft-swc-vnet      True                 Succeeded

# List records in private zone
az network private-dns record-set list   --resource-group platform-skycraft-swc-rg   --zone-name skycraft.internal   --query "[].{Name:name,Type:type,TTL:ttl}"   --output table

# Expected output:
# Name     Type  TTL
# -------  ----  ---
# @        SOA   3600
# dev-db   A     300
# prod-db  A     300
```

### Verify Load Balancers

```azurecli
# List all load balancers
az network lb list   --query "[].{Name:name,ResourceGroup:resourceGroup,SKU:sku.name,Type:frontendIpConfigurations[0].privateIpAllocationMethod}"   --output table

# Expected output:
# Name                   ResourceGroup            SKU       Type
# ---------------------  ----------------------   --------  ----
# dev-skycraft-swc-lb    dev-skycraft-swc-rg      Standard  N/A
# prod-skycraft-swc-lb   prod-skycraft-swc-rg     Standard  N/A
```

### Verify Dev Load Balancer Details

```azurecli
# Show dev load balancer frontend IP
az network lb frontend-ip show   --resource-group dev-skycraft-swc-rg   --lb-name dev-skycraft-swc-lb   --name dev-skycraft-swc-lb-frontend   --query "{Name:name,PublicIP:publicIpAddress.id}"   --output json

# List backend pools
az network lb address-pool list   --resource-group dev-skycraft-swc-rg   --lb-name dev-skycraft-swc-lb   --query "[].{Name:name,BackendIPConfigurations:length(backendIpConfigurations)}"   --output table

# Expected output:
# Name                          BackendIPConfigurations
# ----------------------------  -----------------------
# dev-skycraft-swc-lb-be-world  0
# dev-skycraft-swc-lb-be-auth   0

# List health probes
az network lb probe list   --resource-group dev-skycraft-swc-rg   --lb-name dev-skycraft-swc-lb   --query "[].{Name:name,Protocol:protocol,Port:port,Interval:intervalInSeconds,Threshold:numberOfProbes}"   --output table

# Expected output:
# Name                             Protocol  Port  Interval  Threshold
# -------------------------------  --------  ----  --------  ---------
# dev-skycraft-swc-lb-probe-world  Tcp       8085  15        2
# dev-skycraft-swc-lb-probe-auth   Tcp       3724  15        2

# List load balancing rules
az network lb rule list   --resource-group dev-skycraft-swc-rg   --lb-name dev-skycraft-swc-lb   --query "[].{Name:name,Protocol:protocol,FrontendPort:frontendPort,BackendPort:backendPort,Persistence:loadDistribution}"   --output table

# Expected output:
# Name                            Protocol  FrontendPort  BackendPort  Persistence
# ------------------------------  --------  ------------  -----------  -----------
# dev-skycraft-swc-lb-rule-world  Tcp       8085          8085         Default
# dev-skycraft-swc-lb-rule-auth   Tcp       3724          3724         Default
```

### Verify Production Load Balancer

```azurecli
# Show prod load balancer configuration (similar structure to dev)
az network lb show   --resource-group prod-skycraft-swc-rg   --name prod-skycraft-swc-lb   --query "{Name:name,SKU:sku.name,BackendPools:length(backendAddressPools),Probes:length(probes),Rules:length(loadBalancingRules)}"   --output json

# Expected output:
# {
#   "BackendPools": 2,
#   "Name": "prod-skycraft-swc-lb",
#   "Probes": 2,
#   "Rules": 2,
#   "SKU": "Standard"
# }
```

### Verify Tags

```azurecli
# Check tags on DNS zone
az network dns zone show   --resource-group platform-skycraft-swc-rg   --name skycraft.example.com   --query tags   --output json

# Expected output:
# {
#   "CostCenter": "MSDN",
#   "Environment": "Platform",
#   "Project": "SkyCraft"
# }

# Check tags on dev load balancer
az network lb show   --resource-group dev-skycraft-swc-rg   --name dev-skycraft-swc-lb   --query tags   --output json

# Expected output:
# {
#   "CostCenter": "MSDN",
#   "Environment": "Development",
#   "Project": "SkyCraft"
# }
```

---

## 📊 DNS and Load Balancing Architecture Summary

Use this table to document your deployed architecture:

| Component | Name | Type | Configuration | Status |
|-----------|------|------|---------------|--------|
| **Public DNS Zone** | skycraft.example.com | Public | 3 custom records (dev, play, game) | ✅ |
| └─ A Record | dev.skycraft.example.com | A | [Your dev LB IP] | ✅ |
| └─ A Record | play.skycraft.example.com | A | [Your prod LB IP] | ✅ |
| └─ CNAME | game.skycraft.example.com | CNAME | play.skycraft.example.com | ✅ |
| **Private DNS Zone** | skycraft.internal | Private | 2 records, 3 VNet links | ✅ |
| └─ A Record | dev-db.skycraft.internal | A | 10.1.3.10 | ✅ |
| └─ A Record | prod-db.skycraft.internal | A | 10.2.3.10 | ✅ |
| **Dev Load Balancer** | dev-skycraft-swc-lb | Standard Public | 2 pools, 2 probes, 2 rules | ✅ |
| └─ Frontend IP | dev-skycraft-swc-lb-frontend | Public IP | dev-skycraft-swc-lb-pip | ✅ |
| └─ Backend Pool | dev-skycraft-swc-lb-be-world | Empty | Ready for VMs | ✅ |
| └─ Backend Pool | dev-skycraft-swc-lb-be-auth | Empty | Ready for VMs | ✅ |
| └─ Health Probe | dev-skycraft-swc-lb-probe-world | TCP:8085 | 15s interval, threshold 2 | ✅ |
| └─ Health Probe | dev-skycraft-swc-lb-probe-auth | TCP:3724 | 15s interval, threshold 2 | ✅ |
| **Prod Load Balancer** | prod-skycraft-swc-lb | Standard Public | 2 pools, 2 probes, 2 rules | ✅ |
| └─ Frontend IP | prod-skycraft-swc-lb-frontend | Public IP | prod-skycraft-swc-lb-pip | ✅ |
| └─ Backend Pool | prod-skycraft-swc-lb-be-world | Empty | Ready for VMs | ✅ |
| └─ Backend Pool | prod-skycraft-swc-lb-be-auth | Empty | Ready for VMs | ✅ |

---

## 📊 Load Balancing Rules Summary

Document the load balancing rules deployed:

### Development Environment

| Rule Name | Frontend Port | Backend Port | Backend Pool | Health Probe | Session Persistence |
|-----------|---------------|--------------|--------------|--------------|---------------------|
| dev-skycraft-swc-lb-rule-world | 8085 | 8085 | dev-skycraft-swc-lb-be-world | TCP:8085 (15s) | None (5-tuple) |
| dev-skycraft-swc-lb-rule-auth | 3724 | 3724 | dev-skycraft-swc-lb-be-auth | TCP:3724 (15s) | None (5-tuple) |

### Production Environment

| Rule Name | Frontend Port | Backend Port | Backend Pool | Health Probe | Session Persistence |
|-----------|---------------|--------------|--------------|--------------|---------------------|
| prod-skycraft-swc-lb-rule-world | 8085 | 8085 | prod-skycraft-swc-lb-be-world | TCP:8085 (15s) | None (5-tuple) |
| prod-skycraft-swc-lb-rule-auth | 3724 | 3724 | prod-skycraft-swc-lb-be-auth | TCP:3724 (15s) | None (5-tuple) |

---

## 📝 Reflection Questions

Answer these questions to document your hands-on experience and demonstrate understanding:

### Question 1: DNS Record Documentation
**Document the public IP addresses assigned to your load balancers:**

| DNS Record | IP Address | Load Balancer | Purpose |
|------------|------------|---------------|---------|
| dev.skycraft.example.com | __________ | dev-skycraft-swc-lb | Development game servers |
| play.skycraft.example.com | __________ | prod-skycraft-swc-lb | Production game servers |
| game.skycraft.example.com | [CNAME alias] | prod-skycraft-swc-lb | User-friendly alias |

### Question 2: Private DNS Auto-Registration
**When VMs are deployed in Module 3, describe what will happen with Private DNS auto-registration:**

VMs deployed in dev-skycraft-swc-vnet will automatically:

_________________________________________________________________

_________________________________________________________________

VMs deployed in prod-skycraft-swc-vnet will automatically:

_________________________________________________________________

_________________________________________________________________

### Question 3: Health Probe Configuration Decision
**Why did we choose TCP health probes instead of HTTP probes? In what scenario would you change this?**

Reason for TCP probes:

_________________________________________________________________

_________________________________________________________________

When to use HTTP probes instead:

_________________________________________________________________

_________________________________________________________________

### Question 4: Load Balancer Backend Pool Planning
**In Module 3, you'll deploy VMs to add to backend pools. Plan your VM distribution:**

| Backend Pool | Number of VMs | VM Names | Reasoning |
|--------------|---------------|----------|-----------|
| dev-skycraft-swc-lb-be-world | ______ | __________________ | __________________ |
| dev-skycraft-swc-lb-be-auth | ______ | __________________ | __________________ |
| prod-skycraft-swc-lb-be-world | ______ | __________________ | __________________ |
| prod-skycraft-swc-lb-be-auth | ______ | __________________ | __________________ |

### Question 5: Session Persistence Decision
**We configured load balancing rules with "None" (5-tuple hash) session persistence. Should we change this for AzerothCore game servers? Why or why not?**

Current configuration: None (5-tuple hash)

Should we change to Source IP affinity? 

☐ Yes ☐ No

Reasoning:

_________________________________________________________________

_________________________________________________________________

_________________________________________________________________

### Question 6: DNS TTL Considerations
**You set TTL to 300 seconds (5 minutes) for DNS A records. Describe a scenario where you'd want to change this:**

Scenario requiring lower TTL (e.g., 60 seconds):

_________________________________________________________________

_________________________________________________________________

Scenario requiring higher TTL (e.g., 3600 seconds):

_________________________________________________________________

_________________________________________________________________

### Question 7: Troubleshooting Exercise
**If a player reports they cannot connect to play.skycraft.example.com, describe your troubleshooting steps in order:**

1. _________________________________________________________________
2. _________________________________________________________________
3. _________________________________________________________________
4. _________________________________________________________________
5. _________________________________________________________________

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

_________________________________________________________________

**Most Valuable Learning**:

_________________________________________________________________

_________________________________________________________________

**Questions for Instructor**:

_________________________________________________________________

_________________________________________________________________

---

## ✅ Final Lab 2.3 Sign-off

**All Verification Items Complete**:
- [ ] Public DNS zone created with 3 custom records (dev, play, game)
- [ ] Private DNS zone created with 3 VNet links and 2 A records
- [ ] Dev load balancer deployed with Standard SKU
- [ ] Prod load balancer deployed with Standard SKU
- [ ] 4 backend pools created (2 per load balancer)
- [ ] 4 health probes configured (TCP ports 3724, 8085)
- [ ] 4 load balancing rules configured
- [ ] All resources have required tags (Project, Environment, CostCenter)
- [ ] All validation commands executed successfully
- [ ] All reflection questions answered
- [ ] DNS name servers documented for future domain delegation
- [ ] Load balancer public IPs documented for DNS records
- [ ] Ready to proceed to Module 3 (Compute)

**Student Name**: _________________  
**Lab 2.3 Completion Date**: _________________  
**Instructor Signature**: _________________

---

## 🎉 Congratulations!

You've successfully completed **Lab 2.3** and **Module 2: Virtual Networking**!

**What You Built in Lab 2.3**:
- ✅ Azure Public DNS zone with friendly domain names for game servers
- ✅ Azure Private DNS zone for internal service discovery
- ✅ 2 Azure Standard Load Balancers for high availability
- ✅ 4 backend pools ready to receive VM traffic
- ✅ 4 health probes for automatic failure detection
- ✅ 4 load balancing rules for traffic distribution

**Module 2 Complete - Full Achievement**:
- ✅ **Lab 2.1**: Hub-spoke network topology with VNet peering
- ✅ **Lab 2.2**: Network security with Bastion, NSGs, and ASGs
- ✅ **Lab 2.3**: DNS and load balancing infrastructure

**Network Infrastructure Ready**:
- 🌐 3 VNets (platform, dev, prod) with 8 subnets
- 🔒 6 Network Security Groups protecting all subnets
- 🔑 Azure Bastion for secure administrative access
- 🌍 DNS infrastructure (public and private zones)
- ⚖️ Load balancers for high-availability traffic distribution
- 🏥 Health probes for automatic failure detection

**Next Steps**: In **Module 3: Compute**, you'll:
- Deploy Azure Virtual Machines (Linux Ubuntu Server)
- Install and configure AzerothCore game server software
- Add VMs to load balancer backend pools
- Configure VM extensions and custom script extensions
- Implement VM availability sets and zones
- Test end-to-end connectivity and load balancing

**Estimated Module 3 Duration**: 8 hours (3 labs)

---

## 📌 Module Navigation

- [← Back to Module 2 Index](../README.md)
- [← Previous Lab: 2.2 Secure Access](../2.2-secure-access/lab-checklist-2.2.md)
- [Lab Guide: 2.3 DNS & Load Balancing →](lab-guide-2.3.md)
- [Next Module: Module 3 Compute →](../../module-3-compute/README.md)
