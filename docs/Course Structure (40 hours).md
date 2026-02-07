## **Module 1: Manage Azure Identities and Governance (9 hours)**

**Exam Weight**: 20-25%[](https://learn.microsoft.com/en-us/credentials/certifications/resources/study-guides/az-104)​

## **Section 1.1: Manage Microsoft Entra Users and Groups (3 hours)**

**Hours 1-3**: Identity Foundation for SkyCraft Team

- Create users and groups for your SkyCraft deployment team (admins, developers, testers)
- Manage user and group properties (assign team roles and department tags)
- Manage licenses in Microsoft Entra ID (assign appropriate Azure licenses)
- Manage external users (add guest contributors for collaborative deployment)
- Configure self-service password reset (SSPR) for the team
  **Practical Task**: Create an organizational structure with 3 groups: SkyCraft-Admins, SkyCraft-Developers, SkyCraft-Viewers

---

## **Section 1.2: Manage Access to Azure Resources (2 hours)**

**Hours 4-5**: Role-Based Access Control (RBAC)

- Manage built-in Azure roles (Owner, Contributor, Reader)
- Assign roles at different scopes (subscription, resource group, resource-level)
- Interpret access assignments using Azure Portal and PowerShell
  **Practical Task**: Assign Virtual Machine Contributor role to developers for SkyCraft VMs, Reader role to monitoring team

---

## **Section 1.3: Manage Azure Subscriptions and Governance (4 hours)**

**Hours 6-9**: Governance Framework for Game Server Infrastructure

- Implement and manage Azure Policy (enforce VM SKU restrictions, required tags)
- Configure resource locks (prevent accidental deletion of production resources)
- Apply and manage tags on resources (Environment: Production/Dev, Project: SkyCraft, CostCenter)
- Manage resource groups (create logical groupings for networking, compute, storage)
- Manage subscriptions (understand subscription hierarchy)
- Manage costs by using alerts, budgets, and Azure Advisor recommendations
- Configure management groups (organize multiple subscriptions if applicable)
  **Practical Task**: Create governance structure with policies enforcing naming conventions and cost budgets for SkyCraft deployment
  **Milestone**: Complete identity and governance foundation ready for infrastructure deployment

---

## **Module 2: Implement and Manage Virtual Networking (7 hours)**

**Exam Weight**: 15-20%[](https://learn.microsoft.com/en-us/credentials/certifications/resources/study-guides/az-104)​

## **Section 2.1: Configure and Manage Virtual Networks (3 hours)**

**Hours 10-12**: Network Foundation

- Create and configure virtual networks and subnets (separate subnets for database, auth, world tiers)
- Create and configure virtual network peering (connect dev and production VNets)
- Configure public IP addresses (assign static IPs for game servers)
- Configure user-defined network routes (custom routing for traffic inspection)
- Troubleshoot network connectivity (diagnose connection issues between tiers)
  **Practical Task**: Design and deploy 3-tier VNet architecture for SkyCraft (frontend, application, database subnets)

---

## **Section 2.2: Configure Secure Access to Virtual Networks (2.5 hours)**

**Hours 13-14**: Network Security

- Create and configure network security groups (NSGs) and application security groups
- Evaluate effective security rules in NSGs (troubleshoot access issues)
- Implement Azure Bastion (secure administrative access without public IPs)
- Configure service endpoints for Azure platform as a service (PaaS) (secure Storage and SQL access)
- Configure private endpoints for Azure PaaS (fully private connectivity to Azure SQL)
  **Practical Task**: Configure NSG rules allowing game client connections (ports 8085, 3724), implement Azure Bastion for VM management, configure private endpoint for Azure SQL Database

---

## **Section 2.3: Configure Name Resolution and Load Balancing (1.5 hours)**

**Hours 15-16**: DNS and Load Distribution

- Configure Azure DNS (create DNS zone for yourgameserver.com)
- Configure an internal or public load balancer (distribute player connections across multiple Worldservers)
- Troubleshoot load balancing (verify health probes and backend pool connectivity)
  **Practical Task**: Deploy Azure Load Balancer with health probes for SkyCraft Worldserver instances, configure DNS records
  **Milestone**: Complete secure, high-availability network infrastructure with proper segmentation and load distribution

---

## **Module 3: Deploy and Manage Azure Compute Resources (10 hours)**

**Exam Weight**: 20-25%[](https://learn.microsoft.com/en-us/credentials/certifications/resources/study-guides/az-104)​

## **Section 3.1: Automate Deployment Using ARM/Bicep (3 hours)**

**Hours 17-19**: Infrastructure as Code

- Interpret an Azure Resource Manager template or a Bicep file
- Modify an existing Azure Resource Manager template (customize for SkyCraft)
- Modify an existing Bicep file (parameterize VM sizes, regions)
- Deploy resources by using an Azure Resource Manager template or a Bicep file
- Export a deployment as an Azure Resource Manager template or convert an ARM template to a Bicep file

**Practical Task**: Create and deploy Bicep template that provisions complete SkyCraft infrastructure (VNet, VMs, Storage)

---

## **Section 3.2: Create and Configure Virtual Machines (4 hours)**

**Hours 20-23**: VM Infrastructure for SkyCraft Servers

- Create a virtual machine (Ubuntu Linux for Authserver and Worldserver)
- Configure Azure Disk Encryption (encrypt OS and data disks)
- Move a virtual machine to another resource group, subscription, or region
- Manage virtual machine sizes (resize VMs based on player load)
- Manage virtual machine disks (add data disks for database storage)
- Deploy virtual machines to availability zones and availability sets (high availability for game servers)
- Deploy and configure Azure Virtual Machine Scale Sets (auto-scale Worldserver instances)

**Practical Task**: Deploy 2 Linux VMs (one for Authserver, one for Worldserver) across availability zones into your VNet, configure managed disks.

---

## **Section 3.3: Provision and Manage Containers (2 hours)**

**Hours 24-25**: Containerization Options

- Create and manage an Azure container registry (store custom SkyCraft container images)
- Provision a container by using Azure Container Instances (deploy isolated game services)
- Provision a container by using Azure Container Apps (modern microservices approach)
- Manage sizing and scaling for containers, including Azure Container Instances and Azure Container Apps
  **Practical Task**: (Optional/Advanced) Create container registry, build SkyCraft Docker image, deploy using Azure Container Instances

---

## **Section 3.4: Create and Configure Azure App Service (1 hour)**

**Hour 26**: App Service for Web Management Tools

- Provision an App Service plan
- Configure scaling for an App Service plan
- Create an App Service (deploy web-based admin panel for SkyCraft)
- Configure certificates and Transport Layer Security (TLS) for an App Service
- Map an existing custom DNS name to an App Service
- Configure backup for an App Service
- Configure networking settings for an App Service
- Configure deployment slots for an App Service (blue-green deployment for admin tools)

**Practical Task**: Deploy a simple web dashboard for monitoring SkyCraft server status using App Service
**Milestone**: Complete compute infrastructure with VMs running in your VNet, containerization knowledge, and automation templates

---

## **Module 4: Implement and Manage Storage (7 hours)**

**Exam Weight**: 15-20%[](https://learn.microsoft.com/en-us/credentials/certifications/resources/study-guides/az-104)​

## **Section 4.1: Configure Access to Storage (2 hours)**

**Hours 27-28**: Secure Storage Access

- Configure Azure Storage firewalls and virtual networks (restrict access to VNet only)
- Create and use shared access signature (SAS) tokens (time-limited access for game data)
- Configure stored access policies (manage SAS token lifecycle)
- Manage access keys (rotate keys securely)
- Configure identity-based access for Azure Files (use Microsoft Entra ID for authentication)
  **Practical Task**: Create storage account with network restrictions for SkyCraft configuration files, integrate with your VNet

---

## **Section 4.2: Configure and Manage Storage Accounts (2.5 hours)**

**Hours 29-31**: Storage Infrastructure for Game Data

- Create and configure storage accounts (general-purpose v2 for SkyCraft)
- Configure Azure Storage redundancy (LRS for dev, GRS for production)
- Configure object replication (replicate game assets across regions)
- Configure storage account encryption (enable Microsoft-managed keys)
- Manage data by using Azure Storage Explorer and AzCopy (upload and download game files)

**Practical Task**: Deploy storage account and use AzCopy to upload SkyCraft server binaries and data files

---

## **Section 4.3: Configure Azure Files and Azure Blob Storage (2.5 hours)**

**Hours 32-34**: File Shares and Blob Storage

- Create and configure a file share in Azure Storage (shared configs for SkyCraft servers)
- Create and configure a container in Blob Storage (store game client data, patches)
- Configure storage tiers (Hot, Cool, Archive for different data types)
- Configure snapshots and soft delete for Azure Files (protect configuration files)
- Configure blob lifecycle management (automatically archive old logs)
- Configure blob versioning (track changes to game configuration files)

**Practical Task**: Create Azure File Share mounted to your SkyCraft VMs for shared configuration, create Blob containers for client downloads

**Milestone**: Complete storage layer with proper redundancy, security, and lifecycle management integrated with your compute infrastructure

---

## **Module 5: Monitor and Maintain Azure Resources (5 hours)**

**Exam Weight**: 10-15%[](https://learn.microsoft.com/en-us/credentials/certifications/resources/study-guides/az-104)​

## **Section 5.1: Monitor Resources in Azure (2.5 hours)**

**Hours 35-37**: Comprehensive Monitoring

- Interpret metrics in Azure Monitor (CPU, memory, network for game servers)
- Configure log settings in Azure Monitor (collect VM logs, application logs)
- Query and analyze logs in Azure Monitor (use Kusto Query Language/KQL)
- Set up alert rules, action groups, and alert processing rules in Azure Monitor
- Configure and interpret monitoring of virtual machines, storage accounts, and networks by using Azure Monitor Insights
- Use Azure Network Watcher and Connection Monitor (diagnose network issues)

**Practical Task**: Create Azure Monitor workspace, configure VM Insights, write KQL queries to analyze SkyCraft performance, set up alerts for high CPU usage

---

## **Section 5.2: Implement Backup and Recovery (2.5 hours)**

**Hours 38-40**: Business Continuity

- Create a Recovery Services vault
- Create an Azure Backup vault
- Create and configure a backup policy (daily backups with 30-day retention)
- Perform backup and restore operations by using Azure Backup
- Configure Azure Site Recovery for Azure resources (disaster recovery setup)
- Perform a failover to a secondary region by using Site Recovery
- Configure and interpret reports and alerts for backups

**Practical Task**: Configure automated backups for SkyCraft VMs and Azure SQL Database, perform test restore, configure Site Recovery for production failover

**Milestone**: Production-ready monitoring and disaster recovery capabilities

---

## **Capstone Project & Exam Preparation (Integrated throughout)**

**Final Assessment** (embedded in Hour 40): Deploy complete SkyCraft infrastructure from scratch using learned skills in sequence:

- Establish governance framework (policies, RBAC, tags)
- Deploy network infrastructure (VNets, NSGs, load balancer)
- Provision and configure compute resources (VMs with proper sizing)
- Attach storage and configure access
- Implement comprehensive monitoring and backups
- Document the architecture and operational procedures
