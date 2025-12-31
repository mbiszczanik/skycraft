# Lab 2.1: Configure Virtual Networks

**Estimated Time**: 2.5 Hours

## 📝 Lab Overview

In this lab, you will establish the fundamental network topology for SkyCraft. You will design and deploy a **Hub-and-Spoke** network architecture. This common enterprise pattern allows for central management of shared services (like firewalls or bastion hosts) in the "Hub" while isolating workloads (like our game servers) in "Spokes".

## 🎯 Learning Objectives

- Create Virtual Networks (VNets) and Subnets
- Configure Public IP Addresses
- Implement VNet Peering to connect networks
- Verify connectivity between peered networks

## 📋 Lab Tasks

### Task 1: Design the Network Architecture

We will implement the following address space design:

| Resource  | VNet Name                    | Address Space | Subnet Name   | Subnet Range  | Purpose                             |
| :-------- | :--------------------------- | :------------ | :------------ | :------------ | :---------------------------------- |
| **Hub**   | `platform-skycraft-swc-vnet` | `10.0.0.0/16` | `snet-shared` | `10.0.1.0/24` | Shared services (Bastion, Firewall) |
| **Spoke** | `prod-skycraft-swc-vnet`     | `10.1.0.0/16` | `snet-auth`   | `10.1.1.0/24` | Authentication Servers              |
|           |                              |               | `snet-world`  | `10.1.2.0/24` | World Servers                       |
|           |                              |               | `snet-db`     | `10.1.3.0/24` | Databases                           |

### Task 2: Create the Hub VNet

1. Open the **Azure Portal**.
2. Search for **Virtual Networks** and click **Create**.
3. **Basics**:
   - **Resource Group**: `platform-skycraft-swc-rg` (Created in Lab 1.2)
   - **Name**: `platform-skycraft-swc-vnet`
   - **Region**: **Sweden Central** (as per policy)
4. **IP Addresses**:
   - Delete the default IPv4 address space.
   - Add IPv4 address space: `10.0.0.0/16`
   - Add Subnet:
     - **Name**: `snet-shared`
     - **Address range**: `10.0.1.0/24`
5. **Security**: Leave defaults for now.
6. Click **Review + create**, then **Create**.

### Task 3: Create the Spoke VNet

1. Repeat the process to create the Spoke VNet:
   - **Resource Group**: `prod-skycraft-swc-rg`
   - **Name**: `prod-skycraft-swc-vnet`
   - **Region**: **Sweden Central**
   - **Address Space**: `10.1.0.0/16`
2. Add the following Subnets:
   - `snet-auth` (`10.1.1.0/24`)
   - `snet-world` (`10.1.2.0/24`)
   - `snet-db` (`10.1.3.0/24`)
3. Click **Review + create**, then \*\*Create`.

### Task 4: Configure VNet Peering

Now we connect the two networks so traffic can flow between them.

1. Go to **platform-skycraft-swc-vnet**.
2. Select **Peerings** under Settings.
3. Click **+ Add**.
4. **This Virtual Network** (Hub side):
   - **Peering Link Name**: `peer-hub-to-prod`
   - **Traffic to remote virtual network**: Allow
   - **Traffic forwarded from remote virtual network**: Allow (useful later)
5. **Remote Virtual Network** (Spoke side):
   - **Virtual Network**: Select `prod-skycraft-swc-vnet`
   - **Peering Link Name**: `peer-prod-to-hub`
6. Click **Add**.
7. Wait for the Peering Status to change to **Connected**.

## ✅ Verification

Proceed to the [Lab Checklist](lab-checklist-2.1.md) to verify your deployment.
