# Lab 2.2: Configure Secure Access (NSGs/ASGs)

**Estimated Time**: 2 Hours

## 📝 Lab Overview

Security is paramount. In this lab, you will secure your SkyCraft network using **Network Security Groups (NSGs)** and **Application Security Groups (ASGs)**. You will ensure that only necessary traffic is allowed to reach your game servers and database.

## 🎯 Learning Objectives

- Create and associate Network Security Groups (NSGs)
- Implement Application Security Groups (ASGs) for easier management
- Create Allow/Deny security rules
- Deploy Azure Bastion for secure remote access

## 📋 Lab Tasks

### Task 1: Create Application Security Groups (ASGs)

We will use ASGs to group servers by function, so we don't have to manage IP addresses in our rules.

1. In the Azure Portal, create an **Application Security Group**.
   - **RG**: `prod-skycraft-swc-rg`
   - **Name**: `prod-skycraft-swc-asg-auth`
   - **Region**: **Sweden Central**
2. Create another ASG:
   - **Name**: `prod-skycraft-swc-asg-world`
3. Create a third ASG:
   - **Name**: `prod-skycraft-swc-asg-db`

### Task 2: Create Network Security Groups (NSGs)

We need NSGs to enforce rules at the subnet level.

1. **Create NSG for Spoke**:
   - **RG**: `prod-skycraft-swc-rg`
   - **Name**: `prod-skycraft-swc-nsg`
2. **Create NSG for Hub** (optional for this lab, but good practice):
   - **RG**: `platform-skycraft-swc-rg`
   - **Name**: `platform-skycraft-swc-nsg`

### Task 3: Configure NSG Rules for Game Traffic

We need to open ports for World of Warcraft (AzerothCore).

- **Auth Server Port**: 3724
- **World Server Port**: 8085

1. Open `prod-skycraft-swc-nsg`.
2. Go to **Inbound security rules**.
3. **Allow Auth Traffic**:
   - **Source**: Any
   - **Source port ranges**: \*
   - **Destination**: Application Security Group
   - **Destination ASG**: `prod-skycraft-swc-asg-auth`
   - **Service/Port**: Custom / 3724
   - **Protocol**: TCP
   - **Action**: Allow
   - **Priority**: 100
   - **Name**: `AllowAuthServer`
4. **Allow World Traffic**:
   - **Destination ASG**: `prod-skycraft-swc-asg-world`
   - **Port**: 8085
   - **Priority**: 110
   - **Name**: `AllowWorldServer`

### Task 4: Secure the Database Subnet

We want to ensure ONLY the Auth and World servers can talk to the Database.

1. **Allow App to DB**:
   - **Source**: Application Security Group
   - **Source ASG**: (`prod-skycraft-swc-asg-auth`, `prod-skycraft-swc-asg-world`) - _Note: You might need separate rules per source ASG depending on portal capabilities, or use IP ranges if ASG source limited._
   - **Destination**: Application Security Group
   - **Destination ASG**: `prod-skycraft-swc-asg-db`
   - **Port**: 3306 (MySQL)
   - **Priority**: 200
   - **Name**: `AllowAppToDB`
2. **Deny All Other to DB**:
   - Although there is a default "AllowVNetInBound", for strict control you might add a rule to separate segments if they were in same subnet, but since they are in different subnets, the NSG applied to the subnet works.
   - _Best Practice_: creating a Deny rule with lower priority (higher number) than specific allows but higher than default allow can enforce strictness.

### Task 5: Associate NSGs to Subnets

1. Go to **Virtual Networks** -> `prod-skycraft-swc-vnet`.
2. Select **Subnets**.
3. For each subnet (`AuthSubnet`, `WorldSubnet`, `DatabaseSubnet`):
   - Click the subnet.
   - Set **Security Group** to `prod-skycraft-swc-nsg`.
   - Click **Save**.

### Task 6: Deploy Azure Bastion (Optional/If Credits Allow)

Bastion allows secure RDP/SSH without exposing public IPs on VMs.

1. Navigate to `platform-skycraft-swc-vnet` (Hub).
2. Verify that `AzureBastionSubnet` exists (created in Lab 2.1).
3. Create a **Bastion** resource.
   - **Name**: `platform-skycraft-swc-bas`
   - **Region**: **Sweden Central**
   - **VNet**: `platform-skycraft-swc-vnet`
   - **Subnet**: Select `AzureBastionSubnet`
   - **Public IP**: Create new (`platform-skycraft-swc-bas-pip`)
4. This takes ~15 mins to deploy.

## ✅ Verification

Proceed to the [Lab Checklist](lab-checklist-2.2.md) to verify your deployment.
