# Lab 2.3: Configure Name Resolution

**Estimated Time**: 2.5 Hours

## 📝 Lab Overview

In a distributed system like SkyCraft, servers shouldn't rely on fragile IP addresses. Instead, they should communicate using friendly names. In this lab, you will implement **Azure Private DNS** to allow your Spoke and Hub resources to resolve each other by name (e.g., `db.skycraft.internal`).

## 🎯 Learning Objectives

- Create an Azure Private DNS Zone
- specific custom DNS settings (if applicable)
- Link DNS Zones to Virtual Networks
- Configure auto-registration for simpler management
- Verify name resolution between VMs

## 📋 Lab Tasks

### Task 1: Create a Private DNS Zone

1. In the Azure Portal, search for **Private DNS zones**.
2. Click **Create**.
3. **Basics**:
   - **Resource Group**: `platform-skycraft-swc-rg` (or `prod-skycraft-swc-rg` - DNS is often shared or prod)
   - **Name**: `skycraft.internal`
   - **Region**: (Global resource, but metadata location matters)
4. Click **Review + create**, then **Create**.

### Task 2: Link Virtual Networks

We need to tell our VNets to use this specific DNS zone.

1. Open the `skycraft.internal` zone.
2. Go to **Virtual network links**.
3. **Link to Hub**:
   - Click **+ Add**.
   - **Link name**: `link-to-hub`
   - **Virtual network**: `platform-skycraft-swc-vnet`
   - **Enable auto registration**: **Yes** (This is crucial: VM names automatically become DNS records).
4. **Link to Spoke**:
   - Click **+ Add**.
   - **Link name**: `link-to-prod`
   - **Virtual network**: `prod-skycraft-swc-vnet`
   - **Enable auto registration**: **Yes**.

### Task 3: Verify Auto-Registration

1. If you successfully deployed VMs in previous optional steps (or if you deploy one now), check the **Overview** page of the Private DNS Zone.
2. You should see "A" records automatically appearing for your VMs (e.g., `vm-auth`, `vm-world`).

### Task 4: Test Name Resolution

1. Connect to one VM (e.g., via Bastion).
2. Use `nslookup` or `ping` to resolve another VM's name.
   ```bash
   ping vm-db.skycraft.internal
   ```
3. Ensure it resolves to the private IP address (`10.1.3.x`).

## ✅ Verification

Proceed to the [Lab Checklist](lab-checklist-2.3.md) to verify your deployment.
