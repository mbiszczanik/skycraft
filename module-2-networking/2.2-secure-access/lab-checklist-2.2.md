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
- [ ] Tag: `Owner` = `mbiszczanik`

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
- [ ] Tag: `Owner` = `mbiszczanik`

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
- [ ] Tag: `Owner` = `mbiszczanik`

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
- [ ] Tag: `Owner` = `mbiszczanik`

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
- [ ] Tag: `Owner` = `mbiszczanik`

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
- [ ] Tag: `Owner` = `mbiszczanik`

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
- [ ] Tag: `Owner` = `mbiszczanik`

---

## ✅ Application Security Groups

### dev-skycraft-swc-asg-auth
- [ ] Resource name: `dev-skycraft-swc-asg-auth`
- [ ] Resource group: `dev-skycraft-swc-rg`
- [ ] Location: **Sweden Central**
- [ ] Purpose: Group authentication server VMs
- [ ] Tags applied: Project, Environment, CostCenter, Owner

### dev-skycraft-swc-asg-world
- [ ] Resource name: `dev-skycraft-swc-asg-world`
- [ ] Resource group: `dev-skycraft-swc-rg`
- [ ] Location: **Sweden Central**
- [ ] Purpose: Group world server VMs
- [ ] Tags applied: Project, Environment, CostCenter, Owner

### dev-skycraft-swc-asg-db
- [ ] Resource name: `dev-skycraft-swc-asg-db`
- [ ] Resource group: `dev-skycraft-swc-rg`
- [ ] Location: **Sweden Central**
- [ ] Purpose: Group database server VMs
- [ ] Tags applied: Project, Environment, CostCenter, Owner

---

## ✅ Service Endpoints Configuration

### Development Database Subnet
- [ ] VNet: `dev-skycraft-swc-vnet`
- [ ] Subnet: `DatabaseSubnet (10.1.3.0/24)`
- [ ] Service endpoint: **Microsoft.Sql** enabled
- [ ] Service endpoint: **Microsoft.Storage** enabled
- [ ] Status: **Succeeded**

### Development World Subnet
- [ ] VNet: `dev-skycraft-swc-vnet`
- [ ] Subnet: `WorldSubnet (10.1.2.0/24)`
- [ ] Service endpoint: **Microsoft.Storage** enabled - required by Lab 4.4
- [ ] Status: **Succeeded**

### Production Database Subnet
- [ ] VNet: `prod-skycraft-swc-vnet`
- [ ] Subnet: `DatabaseSubnet (10.2.3.0/24)`
- [ ] Service endpoint: **Microsoft.Sql** enabled
- [ ] Service endpoint: **Microsoft.Storage** enabled
- [ ] Status: **Succeeded**

### Production World Subnet
- [ ] VNet: `prod-skycraft-swc-vnet`
- [ ] Subnet: `WorldSubnet (10.2.2.0/24)`
- [ ] Service endpoint: **Microsoft.Storage** enabled - required by Lab 4.4
- [ ] Status: **Succeeded**

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

# Verify current subscription
Get-AzContext | Select-Object @{N='Name';E={$_.Subscription.Name}}, @{N='SubscriptionId';E={$_.Subscription.Id}}
```

### Verify Azure Bastion

```powershell
# List Bastion hosts
Get-AzBastion -ResourceGroupName platform-skycraft-swc-rg |
    Select-Object Name, Location, ProvisioningState,
        @{N='VNet';E={($_.IpConfigurations[0].Subnet.Id -split '/subnets/')[0].Split('/')[-1]}} |
    Format-Table -AutoSize

# Expected output:
# Name                      Location      ProvisioningState VNet
# platform-skycraft-swc-bas swedencentral Succeeded         platform-skycraft-swc-vnet

# Show Bastion details
$bastion = Get-AzBastion -ResourceGroupName platform-skycraft-swc-rg -Name platform-skycraft-swc-bas
$bastion | Select-Object Name, @{N='Tier';E={$_.Sku.Name}}, @{N='PublicIP';E={$_.IpConfigurations[0].PublicIpAddress.Id}}
```

### Verify Network Security Groups

```powershell
# List all NSGs
Get-AzNetworkSecurityGroup |
    Select-Object Name, ResourceGroupName, Location, @{N='Subnets';E={$_.Subnets.Count}} |
    Format-Table -AutoSize

# Expected output:
# Name                          ResourceGroupName        Location      Subnets
# dev-skycraft-swc-auth-nsg     dev-skycraft-swc-rg      swedencentral 1
# dev-skycraft-swc-world-nsg    dev-skycraft-swc-rg      swedencentral 1
# dev-skycraft-swc-db-nsg       dev-skycraft-swc-rg      swedencentral 1
# prod-skycraft-swc-auth-nsg    prod-skycraft-swc-rg     swedencentral 1
# prod-skycraft-swc-world-nsg   prod-skycraft-swc-rg     swedencentral 1
# prod-skycraft-swc-db-nsg      prod-skycraft-swc-rg     swedencentral 1
```

### Verify NSG Rules (Dev Auth NSG)

```powershell
# List custom inbound rules for dev auth NSG
Get-AzNetworkSecurityGroup -ResourceGroupName dev-skycraft-swc-rg -Name dev-skycraft-swc-auth-nsg |
    Get-AzNetworkSecurityRuleConfig |
    Where-Object { $_.Priority -lt 1000 } |
    Select-Object Priority, Name,
        @{N='Port';E={$_.DestinationPortRange -join ','}},
        @{N='Source';E={$_.SourceAddressPrefix -join ','}},
        Access |
    Sort-Object Priority |
    Format-Table -AutoSize

# Expected output:
# Priority Name                   Port Source      Access
#      100 Allow-SSH-From-Bastion 22   10.0.0.0/26 Allow
#      110 Allow-Auth-GamePort    3724 *           Allow
```

### Verify NSG Subnet Associations

```powershell
# Check which subnet is associated with dev auth NSG
$nsg = Get-AzNetworkSecurityGroup -ResourceGroupName dev-skycraft-swc-rg -Name dev-skycraft-swc-auth-nsg
$nsg | Select-Object Name, @{N='AssociatedSubnets';E={$_.Subnets.Id}}

# Verify all dev NSG associations
$vnet = Get-AzVirtualNetwork -ResourceGroupName dev-skycraft-swc-rg -Name dev-skycraft-swc-vnet
$vnet.Subnets |
    Select-Object Name, @{N='AddressPrefix';E={$_.AddressPrefix -join ','}},
        @{N='NSG';E={$_.NetworkSecurityGroup.Id.Split('/')[-1]}} |
    Format-Table -AutoSize

# Expected output:
# Name           AddressPrefix NSG
# AuthSubnet     10.1.1.0/24   dev-skycraft-swc-auth-nsg
# WorldSubnet    10.1.2.0/24   dev-skycraft-swc-world-nsg
# DatabaseSubnet 10.1.3.0/24   dev-skycraft-swc-db-nsg
```

### Verify Application Security Groups

```powershell
# List all ASGs
Get-AzApplicationSecurityGroup |
    Select-Object Name, ResourceGroupName, Location |
    Format-Table -AutoSize

# Expected output:
# Name                         ResourceGroupName        Location
# dev-skycraft-swc-asg-auth    dev-skycraft-swc-rg      swedencentral
# dev-skycraft-swc-asg-world   dev-skycraft-swc-rg      swedencentral
# dev-skycraft-swc-asg-db      dev-skycraft-swc-rg      swedencentral
```

### Verify Service Endpoints

```powershell
# Check service endpoints on dev database subnet
$devVnet = Get-AzVirtualNetwork -ResourceGroupName dev-skycraft-swc-rg -Name dev-skycraft-swc-vnet
Get-AzVirtualNetworkSubnetConfig -VirtualNetwork $devVnet -Name DatabaseSubnet |
    Select-Object Name, @{N='ServiceEndpoints';E={$_.ServiceEndpoints.Service -join ', '}}

# Expected output:
# Name           ServiceEndpoints
# DatabaseSubnet Microsoft.Sql, Microsoft.Storage

# Check service endpoints on prod database subnet
$prodVnet = Get-AzVirtualNetwork -ResourceGroupName prod-skycraft-swc-rg -Name prod-skycraft-swc-vnet
Get-AzVirtualNetworkSubnetConfig -VirtualNetwork $prodVnet -Name DatabaseSubnet |
    Select-Object Name, @{N='ServiceEndpoints';E={$_.ServiceEndpoints.Service -join ', '}}

# Check the Microsoft.Storage endpoint on both world subnets - Lab 4.4 cannot deploy without it
foreach ($vnet in $devVnet, $prodVnet) {
    Get-AzVirtualNetworkSubnetConfig -VirtualNetwork $vnet -Name WorldSubnet |
        Select-Object Name, @{N='ServiceEndpoints';E={$_.ServiceEndpoints.Service -join ', '}}
}

# Expected output for each:
# Name        ServiceEndpoints
# WorldSubnet Microsoft.Storage
```

### Verify Tags on NSGs

```powershell
# Check tags on dev auth NSG
(Get-AzNetworkSecurityGroup -ResourceGroupName dev-skycraft-swc-rg -Name dev-skycraft-swc-auth-nsg).Tag

# Expected output:
# Name        Value
# ----        -----
# CostCenter  MSDN
# Environment Development
# Owner       mbiszczanik
# Project     SkyCraft

# Check tags on all NSGs
Get-AzNetworkSecurityGroup |
    Select-Object Name,
        @{N='Environment';E={$_.Tag['Environment']}},
        @{N='Project';E={$_.Tag['Project']}},
        @{N='CostCenter';E={$_.Tag['CostCenter']}},
        @{N='Owner';E={$_.Tag['Owner']}} |
    Format-Table -AutoSize
```

### Verify Bastion Public IP

```powershell
# Check public IP used by Bastion
Get-AzPublicIpAddress -ResourceGroupName platform-skycraft-swc-rg -Name platform-skycraft-swc-bas-pip |
    Select-Object Name, IpAddress, @{N='SKU';E={$_.Sku.Name}}, PublicIpAllocationMethod |
    Format-Table -AutoSize

# Expected output:
# Name                          IpAddress   SKU      PublicIpAllocationMethod
# platform-skycraft-swc-bas-pip [Public IP] Standard Static
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
| **Service Endpoints** | Microsoft.Storage | Dev & Prod WorldSubnets | Enabled | ✅ |

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
- [ ] `Microsoft.Storage` endpoint enabled on dev and prod world subnets (Lab 4.4 prerequisite)
- [ ] All resources have required tags (Project, Environment, CostCenter, Owner)
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
- [Next Lab: 2.3 DNS & Load Balancing →](../2.3-name-resolution/lab-checklist-2.3.md)
