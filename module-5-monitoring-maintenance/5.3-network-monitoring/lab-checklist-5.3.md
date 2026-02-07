# Lab 5.3 Completion Checklist

> **Purpose**: This checklist verifies correct implementation of Lab 5.3: Network Monitoring & Troubleshooting.

---

## ✅ Network Watcher Configuration

### Regional Setup

- [ ] Network Watcher enabled for **Sweden Central**
- [ ] Resource group `NetworkWatcherRG` exists and contains the regional instance

---

## ✅ Diagnostic Tool Usage

### IP Flow Verify

- [ ] Successful check for inbound traffic on port 80 (Allowed or Denied)
- [ ] Identification of the specific NSG rule governing the flow
- [ ] (Optional) Tested outbound traffic to `8.8.8.8` on port 53

### Next Hop

- [ ] Verified **Internet** as next hop for external IPs
- [ ] Verified **VNetPeering** or **VirtualNetwork** for internal cross-vnet traffic

---

## ✅ Connectivity & Topology

### Connection Troubleshooter

- [ ] Relationship between Hub and Spoke verified
- [ ] Hop-by-hop latency and status results obtained

### Topology

- [ ] Visual diagram of `dev-skycraft-swc-rg` generated
- [ ] Diagram accurately reflects subnets and VMs created in Modules 2-3

---

## 🔍 Validation Commands

### Verify Network Watcher Status

```azurecli
# Check if Network Watcher is enabled in the region
az network watcher list \
  --query "[?location=='swedencentral'].{Name:name,Region:location,ProvisioningState:provisioningState}" \
  --output table
```

### Run IP Flow Verify via CLI (Optional)

```azurecli
# Example CLI check
az network watcher test-ip-flow \
  --name dev-skycraft-vm \
  --resource-group dev-skycraft-swc-rg \
  --direction inbound \
  --protocol tcp \
  --local 8080 \
  --remote 8.8.8.8 \
  --remote-port 443
```

---

## 📊 Network Diagnostic Summary

| Tool               | Checked? | Insight Gained                         |
| :----------------- | :------- | :------------------------------------- |
| **IP Flow Verify** | [ ]      | Confirmed NSG rules are working        |
| **Next Hop**       | [ ]      | Confirmed routing tables are correct   |
| **Topology**       | [ ]      | Verified visually the Hub-Spoke layout |

---

## 📝 Reflection Questions

### Question 1: NSG Conflicts

**If a subnet NSG allows traffic but the NIC NSG denies it, what is the final result? How does IP Flow Verify help here?**

---

### Question 2: Hub-Spoke Visibility

**When looking at the Topology of a Spoke resource group, do you see resources in the Hub? Why or why not?**

---

---

## ✅ Final Lab 5.3 Sign-off

**All Verification Items Complete**:

- [ ] Network Watcher initialized
- [ ] Connectivity diagnostics performed
- [ ] Routing and Flow verification successful
- [ ] Network Topology visualized
- [ ] Ready to conclude Module 5

**Student Name**: ******\_\_\_\_******
**Lab 5.3 Completion Date**: ******\_\_\_\_******
