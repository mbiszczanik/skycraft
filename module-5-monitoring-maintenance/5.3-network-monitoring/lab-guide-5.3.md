# Lab 5.3: Network Monitoring & Troubleshooting (1 hour)

## 🎯 Learning Objectives

By completing this lab, you will:

- Enable and configure **Azure Network Watcher**
- Use **IP Flow Verify** to identify NSG blocks
- Use **Next Hop** to troubleshoot routing issues
- Run **Connection Troubleshooter** for end-to-end connectivity checks
- Generate a **Network Topology** diagram automatically
- Understand **NSG Flow Logs** for traffic analysis

---

## 🏗️ Architecture Overview

[Description]: Network Watcher is a regional service that provides tools to monitor, diagnose, and view metrics and logs for resources in an Azure virtual network.

```mermaid
graph TB
    NW["Network Watcher<br/>(Sweden Central)"]

    subgraph "Diagnostic Tools"
        IPF["IP Flow Verify<br/>(NSG Blocks?)"]
        NH["Next Hop<br/>(Routing?)"]
        CT["Connection Troubleshooter<br/>(Can A talk to B?)"]
    end

    VM_Dev["dev-skycraft-vm"]
    VM_Prod["prod-skycraft-vm"]

    NW --- Diagnostic Tools
    Diagnostic Tools -.-> VM_Dev
    Diagnostic Tools -.-> VM_Prod
```

---

## 📋 Real-World Scenario

**Situation**: Users are reporting that they cannot reach the development world server on port 8080. Khadgar suspects that a recently applied Network Security Group (NSG) rule is blocking the traffic, or perhaps a custom route is sending packets to the wrong gateway. Instead of manually inspecting dozens of rules, he needs to use Network Watcher to pinpoint the exact failure point.

**Your Task**: Use Network Watcher to verify if traffic on port 8080 is allowed to the development VM, confirm correctly routed traffic with Next Hop, and run an end-to-end connection check between the Hub and the Spoke.

---

## ⏱️ Estimated Time: 1 hour

- **Section 1**: Network Watcher Fundamentals (15 min)
- **Section 2**: IP Flow Verify (15 min)
- **Section 3**: Next Hop & Topology (15 min)
- **Section 4**: Connection Troubleshooter (15 min)

---

## ✅ Prerequisites

Before starting this lab:

- [ ] Completed **Module 2: Networking** (VNets and NSGs must exist)
- [ ] At least one VM must be running

---

## 📖 Section 1: Network Watcher Fundamentals (15 min)

### What is Network Watcher?

**Azure Network Watcher** provides tools to monitor, diagnose, view metrics, and enable or disable logs for resources in an Azure virtual network. It is designed to monitor and repair the network health of IaaS (Infrastructure-as-a-Service) products.

> [!NOTE]
> Network Watcher is enabled automatically for your subscription when you create a virtual network, but it must be enabled for the specific region (Sweden Central).

---

## 📖 Section 2: IP Flow Verify (15 min)

### Step 5.3.1: Check for NSG Blocks

1. Navigate to **Network Watcher** → **Diagnostic tools** → **IP flow verify**.
2. Select your VM: `dev-skycraft-vm`.
3. Configure the check:
   - Protocol: **TCP**
   - Direction: **Inbound**
   - Local port: **8080**
   - Remote IP: **8.8.8.8** (Example external IP)
   - Remote port: **443**
4. Click **Check**.

**Expected Result**: The tool returns **Access denied** or **Access allowed** and specifies the **NSG Rule** name that caused the result.

---

## 📖 Section 3: Next Hop & Topology (15 min)

### Step 5.3.2: Verify Routing

1. In Network Watcher, go to **Next hop**.
2. Select your VM: `prod-skycraft-vm`.
3. Source IP address: (Auto-filled).
4. Destination IP address: `1.1.1.1` (External DNS).
5. Click **Next hop**.

**Expected Result**: The tool returns **Internet** as the next hop type. If you were checking traffic between Hub and Spoke vNets, it should say **VNetPeering** or **VirtualNetwork**.

### Step 5.3.3: Visualize Topology

1. In Network Watcher, go to **Monitoring** → **Topology**.
2. Select the resource group: `dev-skycraft-swc-rg`.
3. Click **View topology**.

**Expected Result**: A visual map of your VNets, subnets, and connected VMs appears.

---

## 📖 Section 4: Connection Troubleshooter (15 min)

### Step 5.3.4: End-to-End Check

1. In Network Watcher, go to **Connection troubleshoot**.
2. **Source**:
   - Type: **Virtual Machine**
   - Resource: `prod-skycraft-vm`
3. **Destination**:
   - Type: **Specify manually**
   - IP Address: (Select the private IP of your `dev-skycraft-vm`)
   - Port: **22** (SSH)
4. Click **Check**.

**Expected Result**: After a minute, the tool shows a hop-by-hop breakdown of the connection status.

---

## ✅ Lab Checklist

- [ ] Network Watcher verified as active in Sweden Central
- [ ] IP Flow Verify used to check port 8080 access
- [ ] Next Hop checked for external connectivity
- [ ] VNet Topology generated and inspected
- [ ] Connection Troubleshooter used between two VMs

**For detailed verification**, see [lab-checklist-5.3.md](lab-checklist-5.3.md)

---

## 🔧 Troubleshooting

### Issue 1: "Network Watcher not enabled for region"

**Symptom**: Common error when first opening the tool.

**Solution**:

- Go to **Network Watcher** → **Regions**.
- Ensure **Sweden Central** is set to **Enabled**.

---

## 🎓 Knowledge Check

1. **When would you use IP Flow Verify instead of just looking at NSG rules?**
   <details>
     <summary>**Click to see the answer**</summary>

   **Answer**: When there are multiple NSGs applied (at both subnet and NIC levels) or complex rule sets. IP Flow Verify simulates the traffic and identifies exactly which rule is winning.
   </details>

2. **Does Network Watcher cost anything?**
   <details>
     <summary>**Click to see the answer**</summary>

   **Answer**: Most diagnostic tools (IP Flow, Next Hop) are free. Only logs (NSG Flow Logs, Traffic Analytics) and Packet Captures incur costs based on data volume.
   </details>

---

## 📚 Additional Resources

- [Network Watcher Overview](https://learn.microsoft.com/en-us/azure/network-watcher/network-watcher-monitoring-overview)
- [IP Flow Verify Documentation](https://learn.microsoft.com/en-us/azure/network-watcher/network-watcher-ip-flow-verify-overview)
- [NSG Flow Logs](https://learn.microsoft.com/en-us/azure/network-watcher/network-watcher-nsg-flow-logging-overview)
- [Connection Troubleshoot](https://learn.microsoft.com/en-us/azure/network-watcher/network-watcher-connectivity-overview)

---

## 📌 Module Navigation

[Lab 5.2 Business Continuity ←](../5.2-business-continuity/lab-guide-5.2.md) | [Back to Module 5 Index](../README.MD)

---

## 📝 Lab Summary

**What You Accomplished:**

✅ Verified Network Watcher is enabled for Sweden Central
✅ Used IP Flow Verify to identify NSG rule behavior
✅ Checked routing with Next Hop diagnostic tool
✅ Generated network topology visualization
✅ Ran end-to-end Connection Troubleshooter between VMs

**Time Spent**: ~1 hour

**Congratulations!** You have completed Module 5: Monitor and Maintain Azure Resources.
