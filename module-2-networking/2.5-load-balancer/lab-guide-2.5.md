# Lab 2.5: Configure Azure Load Balancer

**Estimated Time**: 3 Hours

## 📝 Lab Overview

To support thousands of players, a single Worldserver isn't enough. You need to scale out. In this lab, you will place an **Azure Load Balancer (Standard SKU)** in front of your Worldservers. This ensures that player connections are distributed across multiple servers and that if one server crashes, players are redirected to healthy ones.

## 🎯 Learning Objectives

- Create a Standard Public Load Balancer
- Configure Backend Pools
- creating Health Probes to monitor service availability
- Create Load Balancing Rules for game traffic
- Test high availability

## 📋 Lab Tasks

### Task 1: Create the Load Balancer

1. Search for **Load Balancers**.
2. Click **Create**.
3. **Basics**:
   - **RG**: `prod-skycraft-swc-rg`
   - **Name**: `prod-skycraft-swc-lb`
   - **Region**: **Sweden Central**
   - **SKU**: **Standard** (Required for Availability Zones).
   - **Type**: **Public**.
4. **Frontend IP Configuration**:
   - **Name**: `pip-lb-frontend`
   - **Public IP address**: Create new (`prod-skycraft-swc-pip`).
5. Click **Review + create**, then **Create**.

### Task 2: Configure Backend Pool

1. Open `prod-skycraft-swc-lb`.
2. Go to **Backend pools**.
3. Click **+ Add**.
4. **Name**: `pool-worldservers`
5. **Virtual Network**: `prod-skycraft-swc-vnet`
6. **Backend Pool Configuration**: NIC (Network Interface)
7. **Virtual Machines**: Click **Add** and select your existing Worldserver VMs (e.g., `vm-world-1`, `vm-world-2`).
8. Click **Save**.

### Task 3: Create Health Probe

The LB needs to know if the game server is actually running.

1. Go to **Health probes**.
2. Click **+ Add**.
3. **Name**: `probe-auth-TCP` (Worldserver auth port).
4. **Protocol**: TCP
5. **Port**: 8085 (AzerothCore World Port).
6. **Interval**: 5 seconds.
7. Click **Add**.

### Task 4: Create Load Balancing Rule

1. Go to **Load balancing rules**.
2. Click **+ Add**.
3. **Name**: `rule-worldserver-traffic`
4. **IP Version**: IPv4
5. **Frontend IP**: `pip-lb-frontend`
6. **Protocol**: TCP
7. **Port**: 8085
8. **Backend Port**: 8085
9. **Backend pool**: `pool-worldservers`
10. **Health probe**: `probe-auth-TCP`
11. **Session persistence**: **Client IP** (Important for games so a player doesn't bounce between servers during a session).
12. Click **Add**.

## ✅ Verification

Proceed to the [Lab Checklist](lab-checklist-2.5.md) to verify your deployment.
