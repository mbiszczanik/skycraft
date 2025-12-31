# Lab 2.4: Configure Network Routing

**Estimated Time**: 2 Hours

## 📝 Lab Overview

By default, Azure allows traffic to flow freely between subnets and to the internet. However, in enterprise environments like SkyCraft, you often need to force traffic through a specific path—usually a Firewall or Virtual Appliance—for inspection. This is done using **User Defined Routes (UDRs)**.

## 🎯 Learning Objectives

- Create Custom Route Tables
- Define UDRs (User Defined Routes) to override system routes
- Associate Route Tables with Subnets
- Troubleshoot routing using "Effective Routes"

## 📋 Lab Tasks

### Task 1: Create a Route Table

We want to prepare for a scenario where we force all internet traffic to go through a firewall in the Hub (even if we don't deploy the actual firewall today, we will set up the plumbing).

1. Search for **Route tables**.
2. Click **Create**.
3. **Basics**:
   - **RG**: `prod-skycraft-swc-rg`
   - **Name**: `prod-skycraft-swc-rt`
   - **Region**: **Sweden Central**
   - **Propagate gateway routes**: Yes.
4. Click **Create**.

### Task 2: Define a Route

We will create a route that sends all internet-bound traffic (`0.0.0.0/0`) to the local IP of our (hypothetical) firewall in the Hub.

1. Open `prod-skycraft-swc-rt`.
2. Go to **Routes**.
3. Click **+ Add**.
4. **Route name**: `DefaultRouteToFirewall`
5. **Address prefix destination**: IP Addresses
6. **Destination IP addresses/CIDR ranges**: `0.0.0.0/0`
7. **Next hop type**: Virtual appliance
8. **Next hop address**: `10.0.1.4` (This would be the firewall's private IP in the Hub).
9. Click **Add**.

### Task 3: Associate with Subnets

1. Go to **Subnets** in the Route Table blade.
2. Click **+ Associate**.
3. **Virtual network**: `prod-skycraft-swc-vnet`
4. **Subnet**: `snet-auth`
5. Repeat for `snet-world` and `snet-db`.

> **Warning**: Once you do this, internet access from these subnets will BREAK unless there is actually a Virtual Appliance at 10.0.1.4 forwarding traffic. **This is expected behavior.**

### Task 4: Verify Effective Routes

1. Go to your **Auth VM** (Network Interface).
2. Blade menu -> **Effective routes**.
3. Confirm you see your User Defined Route overriding the default `0.0.0.0/0` Internet route.

> **Recovery**: To restore internet access for the rest of the course, simply disassociate this route table from the subnets or change the next hop to "Internet" for testing.

## ✅ Verification

Proceed to the [Lab Checklist](lab-checklist-2.4.md) to verify your deployment.
