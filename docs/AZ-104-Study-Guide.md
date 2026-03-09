# AZ-104 Study Guide - Microsoft Azure Administrator

## Complete Study Guide with Strategies, Flashcards & Practice Quiz

> Source: [azurekt.com/az-104](https://www.azurekt.com/az-104)

> Used with permission from [Krishna Venkataraman](https://www.linkedin.com/in/krishnavenk/)

---

## Exam Overview

| Detail        | Value                                  |
| ------------- | -------------------------------------- |
| Exam Code     | AZ-104                                 |
| Duration      | 100-120 Minutes                        |
| Questions     | 50-60                                  |
| Cost          | $165 USD                               |
| Passing Score | 700 out of 1000                        |
| Prerequisites | None (hands-on experience recommended) |

---

## 5 Exam Domains

### Domain 1: Manage Azure Identities and Governance (20-25%)

- Manage Microsoft Entra users, groups, and licenses
- Configure self-service password reset (SSPR)
- Manage built-in roles and role assignments
- Implement Azure Policy, tags, and resource locks
- Manage subscriptions and management groups
- Control costs using budgets and Azure Advisor

### Domain 2: Implement and Manage Storage (15-20%)

- Configure storage account access and SAS
- Manage access keys and identity-based access
- Configure redundancy and encryption
- Manage Azure Files and Blob Storage
- Configure tiers, soft delete, and lifecycle rules

### Domain 3: Deploy and Manage Azure Compute (20-25%)

- Deploy ARM templates and Bicep files
- Create and manage VMs and Scale Sets
- Configure disks, encryption, and availability
- Provision containers using ACR, ACI, and Container Apps
- Create and manage App Service and plans

### Domain 4: Implement and Manage Virtual Networking (15-20%)

- Create VNets, subnets, and VNet peering
- Implement NSGs and ASGs
- Configure service endpoints and private endpoints
- Implement Azure DNS and load balancers
- Configure Azure Bastion and VPN Gateway

### Domain 5: Monitor and Maintain Azure Resources (10-15%)

- Monitor metrics and logs using Azure Monitor
- Configure alerts and action groups
- Use Network Watcher for diagnostics
- Configure Azure Backup and Recovery Services
- Implement Azure Site Recovery and failovers

### Domain 1 Details: Manage Azure Identities and Governance

> This domain covers identity management with Microsoft Entra ID (formerly Azure AD), role-based access control (RBAC), Azure Policy for governance, and cost management. You must understand how to create and manage users, groups, and administrative units, assign roles at different scopes, and enforce organizational standards through policies and resource locks.

#### Key Concepts

#### Microsoft Entra ID (Azure AD) [CRITICAL]

Cloud-based identity and access management service. Manages users, groups, app registrations, and enterprise applications. Supports multi-factor authentication (MFA), Conditional Access policies, and self-service password reset (SSPR). Administrative Units allow delegated management of specific user/group subsets.

#### Role-Based Access Control (RBAC) [CRITICAL]

Authorization system built on Azure Resource Manager. Roles are assigned at four scope levels: Management Group > Subscription > Resource Group > Resource. Built-in roles include Owner (full access + role assignment), Contributor (full access, no role assignment), and Reader (view only). Custom roles can be created for granular permissions. Role assignments are additive and inherited downward.

#### Azure Policy [CRITICAL]

Governance service that enforces organizational standards. Policies evaluate resources for compliance using JSON-based policy definitions. Effects include Deny (block non-compliant resources), Audit (log violations), DeployIfNotExists (auto-remediate), and Modify (add/update tags). Initiatives group multiple policies. Policies are assigned at management group, subscription, or resource group scope.

#### Management Groups [HIGH]

Containers above subscriptions for organizing resources at scale. Support up to 6 levels of depth (excluding root and subscription). Governance conditions (RBAC, Policy) applied at management group level inherit to all child subscriptions and resources. Every directory has a single root management group.

#### Resource Locks [HIGH]

Prevent accidental modification or deletion of Azure resources. Two lock types: CanNotDelete (allows read/modify but blocks delete) and ReadOnly (allows read only, blocks modify and delete). Locks are inherited by child resources. Only Owner and User Access Administrator roles can manage locks.

#### Cost Management [MEDIUM]

Azure Cost Management + Billing provides cost analysis, budgets, and recommendations. Azure Advisor offers personalized best practices for cost optimization, security, reliability, and performance. Budgets trigger alerts at defined thresholds and can invoke action groups for automated responses.

#### Tags [HIGH]

Name-value pairs for organizing and tracking Azure resources. Maximum 50 tags per resource. Tags do NOT automatically inherit from resource groups - use Azure Policy (Modify effect) to enforce tag inheritance. Useful for cost allocation, environment identification, and compliance tracking.

#### Microsoft Learn Resources

- [Learning Path] [AZ-104: Manage identities and governance in Azure](https://learn.microsoft.com/en-us/training/paths/az-104-manage-identities-governance/)
- [Module] [Manage Microsoft Entra users and groups](https://learn.microsoft.com/en-us/training/modules/manage-users-and-groups-in-aad/)
- [Module] [Configure role-based access control](https://learn.microsoft.com/en-us/training/modules/configure-role-based-access-control/)
- [Module] [Configure Azure Policy](https://learn.microsoft.com/en-us/training/modules/configure-azure-policy/)
- [Module] [Configure management groups](https://learn.microsoft.com/en-us/training/modules/configure-management-groups/)
- [Docs] [Azure RBAC documentation](https://learn.microsoft.com/en-us/azure/role-based-access-control/overview)
- [Docs] [Azure Policy documentation](https://learn.microsoft.com/en-us/azure/governance/policy/overview)

---

### Domain 2 Details: Implement and Manage Storage

> This domain focuses on Azure Storage accounts, including blob storage, file shares, access control, redundancy, and data protection. You need to understand storage account types, replication options, access tiers, shared access signatures (SAS), and tools like AzCopy and Storage Explorer for data management.

#### Key Concepts

#### Storage Account Types [CRITICAL]

Standard general-purpose v2 is the recommended type for most scenarios, supporting blobs, files, queues, and tables. Premium storage offers low-latency SSD-backed performance for block blobs, page blobs, or file shares. Storage account names must be globally unique, 3-24 characters, lowercase letters and numbers only.

#### Blob Storage & Access Tiers [CRITICAL]

Three access tiers optimize cost vs. access frequency. Hot: frequent access, highest storage cost, lowest access cost. Cool: infrequent access (30-day minimum retention), lower storage cost. Archive: rare access (180-day minimum), cheapest storage but hours to rehydrate. Tiers can be set at account level (Hot/Cool) or blob level (Hot/Cool/Archive). Lifecycle management policies automate tier transitions.

#### Storage Redundancy [CRITICAL]

LRS: 3 copies in one datacenter (11 nines durability). ZRS: 3 copies across 3 availability zones (12 nines). GRS: LRS + async copy to secondary region (16 nines). RA-GRS: GRS with read access to secondary. GZRS: ZRS in primary + LRS in secondary. RA-GZRS: GZRS with read access to secondary. Changing LRS to ZRS requires live migration.

#### Shared Access Signatures (SAS) [CRITICAL]

Provides delegated access to storage resources without sharing account keys. Three types: User delegation SAS (secured with Entra ID, recommended), Service SAS (secured with account key, scoped to one service), and Account SAS (secured with account key, scoped to one or more services). SAS tokens specify permissions, start/expiry time, allowed IP ranges, and protocols.

#### Azure Files [HIGH]

Fully managed file shares accessible via SMB (port 445) or NFS protocols. Supports Azure File Sync for hybrid scenarios, caching files on Windows Server. Snapshots provide point-in-time copies. Premium file shares offer SSD-based storage with IOPS guarantees. Soft delete protects against accidental file share deletion.

#### Data Protection [HIGH]

Soft delete retains deleted blobs/containers for a specified retention period (1-365 days). Blob versioning automatically maintains previous versions on every write/delete. Point-in-time restore allows restoring block blobs to a previous state. Immutable storage with WORM (Write Once, Read Many) policies prevents modification or deletion for compliance.

#### AzCopy & Storage Explorer [MEDIUM]

AzCopy is a command-line utility for high-performance data transfer to/from Azure Storage. Supports blob and file copy, sync operations, and benchmarking. Azure Storage Explorer is a GUI tool for managing storage across subscriptions with drag-and-drop support. Both support SAS tokens and Entra ID authentication.

#### Microsoft Learn Resources

- [Learning Path] [AZ-104: Implement and manage storage in Azure](https://learn.microsoft.com/en-us/training/paths/az-104-manage-storage/)
- [Module] [Configure Azure Storage accounts](https://learn.microsoft.com/en-us/training/modules/configure-storage-accounts/)
- [Module] [Configure Azure Blob Storage](https://learn.microsoft.com/en-us/training/modules/configure-blob-storage/)
- [Module] [Configure Azure Storage security](https://learn.microsoft.com/en-us/training/modules/configure-storage-security/)
- [Module] [Configure Azure Files and Azure File Sync](https://learn.microsoft.com/en-us/training/modules/configure-azure-files-file-sync/)
- [Docs] [Azure Storage redundancy](https://learn.microsoft.com/en-us/azure/storage/common/storage-redundancy)
- [Docs] [Storage account overview](https://learn.microsoft.com/en-us/azure/storage/common/storage-account-overview)

---

### Domain 3 Details: Deploy and Manage Azure Compute

> This domain covers virtual machines, scale sets, containers, App Service, and infrastructure-as-code deployments. You must understand VM sizing, availability options, disk management, ARM templates, Bicep, and container services including Azure Container Registry, Container Instances, and Container Apps.

#### Key Concepts

#### Virtual Machines [CRITICAL]

IaaS compute resources providing full OS control. VM sizes are grouped by families: D-series (general purpose), F-series (compute optimized), E-series (memory optimized), N-series (GPU), S-series (storage optimized). Deallocated VMs stop compute charges but disk and IP costs continue. Generalize before capturing: Sysprep (Windows) or waagent -deprovision (Linux).

#### Availability Sets & Zones [CRITICAL]

Availability Sets distribute VMs across fault domains (hardware racks, max 3) and update domains (reboot groups, max 20) within a single datacenter for 99.95% SLA. Availability Zones distribute across physically separate datacenters in a region for 99.99% SLA. Choose Zones for highest SLA, Sets for rack/maintenance protection within one datacenter.

#### VM Scale Sets (VMSS) [CRITICAL]

Automatically deploy and manage a group of identical VMs. Support autoscale rules based on metrics (CPU, memory, custom metrics). Two orchestration modes: Uniform (identical VMs, classic autoscale) and Flexible (mix VM sizes, zone-aware). Scale-out adds VMs, scale-in removes. Health probes monitor instance health for automatic repair.

#### Azure Disks [HIGH]

Managed disks abstract storage account management. Types: Ultra (highest IOPS), Premium SSD v2 (configurable), Premium SSD (production), Standard SSD (dev/test), Standard HDD (backup). OS disk holds the operating system, data disks for application data. Temporary disks are ephemeral and lost on deallocation. Server-side encryption (SSE) encrypts at rest by default.

#### ARM Templates & Bicep [CRITICAL]

ARM templates are JSON files defining infrastructure as code. They are declarative and idempotent - deploying the same template produces the same result. Bicep is a domain-specific language that compiles to ARM JSON with cleaner syntax, module support, and parameter validation. Both support parameters, variables, resources, and outputs. Deployment modes: Incremental (default, adds/updates) and Complete (deletes resources not in template).

#### Azure Container Instances (ACI) [HIGH]

Serverless container platform for running containers without managing VMs. Supports Linux and Windows containers. Container groups share lifecycle, network, and storage (similar to Kubernetes pods). Supports mounting Azure Files for persistent storage. Fast startup times, per-second billing. Best for burst workloads, CI/CD agents, and simple container apps.

#### Azure App Service [HIGH]

PaaS platform for hosting web apps, REST APIs, and mobile backends. App Service Plans define compute resources (Free, Shared, Basic, Standard, Premium, Isolated tiers). Supports auto-scaling, deployment slots (for staging/production swaps), custom domains, and SSL certificates. Built-in CI/CD integration with GitHub, Azure DevOps, and local Git.

#### Microsoft Learn Resources

- [Learning Path] [AZ-104: Deploy and manage compute resources](https://learn.microsoft.com/en-us/training/paths/az-104-manage-compute-resources/)
- [Module] [Configure virtual machines](https://learn.microsoft.com/en-us/training/modules/configure-virtual-machines/)
- [Module] [Configure virtual machine availability](https://learn.microsoft.com/en-us/training/modules/configure-virtual-machine-availability/)
- [Module] [Configure Azure App Service](https://learn.microsoft.com/en-us/training/modules/configure-azure-app-services/)
- [Module] [Manage Azure resources with ARM templates](https://learn.microsoft.com/en-us/training/modules/configure-resources-arm-templates/)
- [Module] [Introduction to Azure Container Instances](https://learn.microsoft.com/en-us/training/modules/intro-to-azure-container-instances/)
- [Docs] [Azure Virtual Machines documentation](https://learn.microsoft.com/en-us/azure/virtual-machines/overview)

---

### Domain 4 Details: Implement and Manage Virtual Networking

> This domain covers virtual networks, subnets, NSGs, DNS, load balancing, VPN connectivity, and private access to Azure services. You must understand how to design and implement network security, configure connectivity between networks and on-premises environments, and select appropriate load balancing solutions.

#### Key Concepts

#### Virtual Networks (VNets) [CRITICAL]

Fundamental building block for private networking in Azure. VNets are scoped to a single region and subscription. Address space uses CIDR notation (e.g., 10.0.0.0/16). Subnets segment VNets and cannot overlap. Certain services require dedicated subnets (e.g., AzureBastionSubnet, GatewaySubnet). Resources in a VNet can communicate with each other by default.

#### Network Security Groups (NSGs) [CRITICAL]

Stateful packet filtering using 5-tuple rules: source/destination IP, source/destination port, and protocol. Rules have priority numbers (100-4096, lower = higher priority). Default rules allow VNet-to-VNet and outbound internet, deny inbound internet. NSGs can be associated with subnets or individual NICs. Application Security Groups (ASGs) simplify rules by grouping VMs logically instead of by IP.

#### VNet Peering [CRITICAL]

Connects two VNets with low-latency, high-bandwidth private connectivity via Microsoft backbone. Regional peering (same region) and global peering (cross-region) are available. Peering is NON-TRANSITIVE: if A peers with B and B peers with C, A cannot reach C without direct peering. Address spaces cannot overlap. Gateway transit allows shared VPN/ExpressRoute gateways across peered VNets.

#### Azure DNS [HIGH]

Hosting service for DNS domains using Microsoft infrastructure. Public DNS zones resolve to internet-facing resources. Private DNS zones provide name resolution within VNets. Supports A, AAAA, CNAME, MX, NS, PTR, SOA, SRV, and TXT record types. Alias records point to Azure resources (load balancer, Traffic Manager, CDN) and automatically update when the target IP changes.

#### Load Balancing Options [CRITICAL]

Azure Load Balancer operates at Layer 4 (TCP/UDP) for non-HTTP traffic with public or internal frontends. Application Gateway operates at Layer 7 (HTTP/HTTPS) with URL path-based routing, SSL termination, and Web Application Firewall (WAF). Azure Front Door provides global Layer 7 load balancing with CDN and WAF. Traffic Manager uses DNS-based routing for global traffic distribution (no data path).

#### Private & Service Endpoints [CRITICAL]

Service Endpoints extend VNet identity to Azure services via an optimized route, but the service still has a public IP. Private Endpoints assign a private IP address from your VNet to an Azure service, eliminating public internet exposure entirely. Private Link enables access to Azure PaaS services over a private connection. Use Private Endpoints when the requirement mentions 'eliminate public exposure'.

#### Azure Bastion & VPN Gateway [HIGH]

Azure Bastion provides secure RDP/SSH to VMs directly through the Azure portal over TLS, without exposing public IPs. Requires AzureBastionSubnet with minimum /26 CIDR. VPN Gateway connects on-premises networks to Azure via site-to-site (S2S), point-to-site (P2S), or VNet-to-VNet IPsec tunnels. ExpressRoute provides private, dedicated connectivity bypassing the public internet.

#### Microsoft Learn Resources

- [Learning Path] [AZ-104: Configure and manage virtual networking](https://learn.microsoft.com/en-us/training/paths/az-104-manage-virtual-networks/)
- [Module] [Configure virtual networks](https://learn.microsoft.com/en-us/training/modules/configure-virtual-networks/)
- [Module] [Configure network security groups](https://learn.microsoft.com/en-us/training/modules/configure-network-security-groups/)
- [Module] [Configure Azure Virtual Network peering](https://learn.microsoft.com/en-us/training/modules/configure-vnet-peering/)
- [Module] [Configure Azure Load Balancer](https://learn.microsoft.com/en-us/training/modules/configure-azure-load-balancer/)
- [Module] [Configure Azure DNS](https://learn.microsoft.com/en-us/training/modules/configure-azure-dns/)
- [Docs] [Azure networking documentation](https://learn.microsoft.com/en-us/azure/networking/fundamentals/networking-overview)

---

### Domain 5 Details: Monitor and Maintain Azure Resources

> This domain covers monitoring, alerting, backup, and disaster recovery. You need to understand Azure Monitor for metrics and logs, configure alerts and action groups, use Network Watcher for network diagnostics, and implement backup and site recovery strategies for business continuity.

#### Key Concepts

#### Azure Monitor [CRITICAL]

Comprehensive monitoring platform collecting metrics (numeric time-series data) and logs (structured/unstructured event data) from Azure resources. Metrics are stored for 93 days and available near real-time. Logs are stored in Log Analytics workspaces and queried using Kusto Query Language (KQL). Key KQL operators: where (filter), summarize (aggregate), project (select columns), top (limit results).

#### Alerts & Action Groups [CRITICAL]

Alerts notify you when conditions are met in monitoring data. Three signal types: Metric (numeric thresholds), Log (KQL query results), and Activity Log (subscription-level events). Alert rules define condition, scope, and action group. Action Groups specify notification methods (email, SMS, push) and automated actions (Azure Function, Logic App, webhook, ITSM). Alert states: New, Acknowledged, Closed.

#### Network Watcher [HIGH]

Suite of network diagnostic and monitoring tools. IP Flow Verify checks if traffic is allowed/denied through NSG rules. Next Hop identifies routing for packets. Connection Troubleshoot tests connectivity between resources. NSG Flow Logs capture network traffic data. Packet Capture records packets to/from VMs. Connection Monitor provides end-to-end monitoring.

#### Azure Backup [CRITICAL]

Enterprise-grade backup solution with zero-infrastructure management. Recovery Services Vault stores backup data with geo-redundancy options (LRS, GRS). Backup Policies define schedule (daily/weekly) and retention (days/weeks/months/years). Supports VMs, SQL databases, Azure Files, and on-premises workloads via MARS agent. Soft delete retains backup data for 14 additional days after deletion.

#### Azure Site Recovery (ASR) [HIGH]

Disaster recovery as a service (DRaaS) for business continuity. Replicates VMs, physical servers, and workloads from primary to secondary region. Provides near-zero RPO (Recovery Point Objective) through continuous replication. RTO (Recovery Time Objective) measured in minutes to hours. Recovery plans define failover sequence and include manual/automated steps. Test failover validates DR strategy without impacting production.

#### Log Analytics Workspace [HIGH]

Central repository for log data in Azure Monitor. Collects data from Azure resources, on-premises servers (via agents), and custom sources. Data retention configurable from 30 to 730 days. Interactive queries using KQL with visualization options (charts, tables). Workbooks combine logs, metrics, and parameters into interactive reports. Supports cross-workspace queries for multi-tenant scenarios.

#### Microsoft Learn Resources

- [Learning Path] [AZ-104: Monitor and back up Azure resources](https://learn.microsoft.com/en-us/training/paths/az-104-monitor-backup-resources/)
- [Module] [Configure Azure Monitor](https://learn.microsoft.com/en-us/training/modules/configure-azure-monitor/)
- [Module] [Configure Azure alerts](https://learn.microsoft.com/en-us/training/modules/configure-azure-alerts/)
- [Module] [Configure Network Watcher](https://learn.microsoft.com/en-us/training/modules/configure-network-watcher/)
- [Module] [Configure Azure Recovery Services vault backup](https://learn.microsoft.com/en-us/training/modules/configure-virtual-machine-backups/)
- [Docs] [Azure Monitor documentation](https://learn.microsoft.com/en-us/azure/azure-monitor/overview)
- [Docs] [Azure Backup documentation](https://learn.microsoft.com/en-us/azure/backup/backup-overview)

---

## Domain-Specific Study Strategies

### Domain 1: Manage Azure Identities and Governance (20-25%)

_The "Who, What, Where" of Azure_

#### Memory Anchor: "RBAC = Bouncer, Policy = Building Code"

Think of RBAC as the bouncer at a club (controls WHO gets in and WHERE they can go). Azure Policy is the building code (controls WHAT can be built, regardless of who’s building it). This distinction is tested heavily. If the question is about "preventing someone from doing something" it’s RBAC. If it’s about "preventing something from being created a certain way" it’s Policy.

#### Mnemonic: "COR" for RBAC Roles

- **C**ontributor = Can create and manage everything, but can’t give access to others
- **O**wner = Can do everything INCLUDING granting access to others
- **R**eader = Can only view, nothing else

> The difference between Owner and Contributor is just one thing - the ability to assign roles. This is a common exam trap.

#### Governance Hierarchy: "MGSRL"

Picture a tree: Management Groups are the trunk (broadest scope), Subscriptions are branches, Resource Groups are leaves, and Resources are the fruit. Policies and RBAC "flow down" like water - assign once at the trunk and everything below inherits.

#### Common Exam Traps

1. ReadOnly lock prevents MODIFICATIONS but allows DELETION - CanNotDelete prevents deletion but allows modifications.
2. Tags do NOT inherit from resource groups. You must use Azure Policy to enforce tag inheritance.
3. Maximum 50 tags per resource. Tag name max 512 characters, value max 256 characters.

#### Speed Drill

Who controls access? RBAC. What controls configuration? Policy. Where does governance apply broadest? Management Group.

---

### Domain 2: Implement and Manage Storage (15-20%)

_The "Filing Cabinet" of Azure_

#### Memory Anchor: "HCA" - Hot, Cool, Archive = Desk, Filing Cabinet, Warehouse

- Hot tier = Your desk (instant access, highest storage cost, lowest access cost)
- Cool tier = Your filing cabinet (slight delay, lower storage cost, higher access cost, 30-day minimum)
- Archive tier = Your warehouse (hours to retrieve, cheapest storage, most expensive access, 180-day minimum)

> Storage cost and access cost are INVERSELY related.

#### Mnemonic: "LZG-R" for Redundancy

- **L**RS = 3 copies in ONE datacenter (cheapest, least durable)
- **Z**RS = 3 copies across 3 availability ZONES (same region)
- **G**RS = LRS + copy to secondary REGION (read only after failover)
- **R**A-GRS = GRS + READ ACCESS to secondary region anytime

> Key difference: GRS vs RA-GRS - can you READ from the secondary before failover? RA-GRS = yes.

#### Access Methods: "KSA" - Keys, SAS, Azure AD

- **Keys** = Master keys (full access to everything, treat like root password)
- **SAS** = Valet key (scoped access: specific services, permissions, time window, IP range)
- **Azure AD** = Identity-based (best practice, uses RBAC roles like Storage Blob Data Reader)

> When asked for "most secure" access, the answer is almost always Azure AD (identity-based).

#### Common Exam Traps

1. AzCopy = high-performance CLI for bulk transfers. Storage Explorer = GUI with drag-and-drop.
2. Lifecycle management automates tiering. Soft delete protects against accidental deletion. Versioning protects against overwrites.
3. Changing redundancy from LRS to ZRS requires a live migration request.

---

### Domain 3: Deploy and Manage Azure Compute (20-25%)

_The "Engines" of Azure_

#### Memory Anchor: "The Compute Ladder"

VMs (full OS control) -> Containers/ACI (app + dependencies) -> App Service (just your code) -> Functions (just a function). More control = more management responsibility.

#### Mnemonic: "DFENS" for VM Size Families

- **D**-series = General purpose (Default, balanced CPU/memory)
- **F**-series = Compute optimized (Fast CPU, high CPU-to-memory ratio)
- **E**-series = Memory optimized (Extra RAM for databases)
- **N**-series = GPU enabled (Neural networks, rendering)
- **S**-series = Storage optimized (Sequential read/write, data warehousing)

> Quick rule: "What’s the bottleneck?" CPU=F, Memory=E, GPU=N, Storage=S, Don’t know=D

#### Availability: "Set vs Zone" Decision Matrix

- **Availability Set** = Protection within ONE datacenter. SLA: 99.95%
- **Availability Zone** = Protection across MULTIPLE datacenters in one region. SLA: 99.99%

> "Datacenter failure protection" or "highest SLA" = Availability Zone. "Hardware rack" or "maintenance window" = Availability Set.

#### Common Exam Traps

1. Deallocated VM = no compute charges but you STILL pay for disks and static IPs.
2. Generalized VM image: Windows = Sysprep, Linux = waagent -deprovision.
3. Resizing a VM may require deallocation if the new size isn’t available on the current cluster.
4. ARM templates are idempotent. Bicep compiles to ARM JSON.

#### Speed Drill

Full OS control? VM. Container without infra? ACI. Web app with scaling? App Service. Event-driven pay-per-execution? Functions.

---

### Domain 4: Implement and Manage Virtual Networking (15-20%)

_The "Roads and Highways" of Azure_

#### Memory Anchor: "NSG = Security Guard, UDR = GPS"

NSG = Security guard checking your ID (Allow/Deny based on IP, port, protocol). UDR = GPS rerouting your car through a checkpoint. NSGs filter traffic. UDRs redirect traffic.

#### Mnemonic: "PEPS" for Private Connectivity

- **P**eering = Connect two VNets (no overlap allowed, non-transitive)
- **E**xpressRoute = Private dedicated wire to Azure (no internet)
- **P**rivate Endpoint = Private IP for an Azure service inside your VNet
- **S**ervice Endpoint = Optimized path to Azure service (still uses public IP internally)

> "Eliminate public internet exposure" = Private Endpoint.

#### Load Balancing Decision Tree

- **HTTP/HTTPS?** -> Application Gateway (Layer 7, URL routing, WAF) or Front Door (global)
- **Non-HTTP (TCP/UDP)?** -> Azure Load Balancer (Layer 4)
- **DNS-based global?** -> Traffic Manager (DNS routing, no data path)

#### Common Exam Traps

1. VNet Peering is NON-TRANSITIVE. A-B and B-C does NOT mean A-C.
2. NSG rules processed by PRIORITY (lowest number = highest priority). Default rules at 65000+.
3. Azure Bastion requires subnet named "AzureBastionSubnet" with minimum /26 CIDR.
4. Gateway transit lets one VNet’s gateway serve the peered VNet.

#### Speed Drill

Connect two VNets? Peering. On-prem via internet? VPN Gateway. On-prem without internet? ExpressRoute. Secure RDP without public IP? Bastion. Private IP on Azure SQL? Private Endpoint. Block port 22? NSG.

---

### Domain 5: Monitor and Maintain Azure Resources (10-15%)

_The "Eyes and Safety Net" of Azure_

#### Memory Anchor: "Monitor = MALL" (Metrics, Alerts, Logs, Log Analytics)

Azure Monitor is a shopping MALL: Metrics store (real-time numbers), Alerts store (automated notifications), Logs store (detailed events with KQL), Log Analytics store (query workspace). Everything feeds into Azure Monitor.

#### Mnemonic: "BAR" for Backup Components

- **B**ackup Policy = WHEN and HOW LONG (schedule + retention)
- **A**gent = Azure Backup Agent or Azure Monitor Agent (on VM)
- **R**ecovery Services Vault = WHERE backups are stored

> Flow: Create Vault -> Define Policy -> Enable Backup -> Test Recovery.

#### Disaster Recovery: "ASR = Photocopier for VMs"

Azure Site Recovery continuously photocopies your VMs to another region.

- **RPO** (Recovery Point Objective) = How much data can you afford to lose?
- **RTO** (Recovery Time Objective) = How fast must you be back up?

> ASR: near-zero RPO (continuous replication) and minutes-to-hours RTO.

#### Common Exam Traps

1. Metrics = real-time numeric data. Logs = detailed text-based events. Different data, different tools.
2. KQL is NOT SQL. Syntax: Table | where | summarize | top.
3. Network Watcher: IP Flow Verify, Next Hop, Connection Troubleshoot, Packet Capture.
4. Soft delete retains backup data 14 days. Immutable vaults prevent deletion entirely.

---

## Exam Day Strategy

### Time Management

- 120 minutes for ~55 questions = ~2 min per question
- Flag difficult questions and move on immediately
- Budget 15 minutes at the end for flagged review
- Never leave a question unanswered - no penalty for guessing

### Elimination Technique

- Read ALL options before selecting
- Eliminate obviously wrong answers first (usually 2 are clearly wrong)
- Between remaining options, pick the one most specific to the scenario
- "Most secure" usually means identity-based over key/token-based

### 30-Day Study Plan

| Week   | Focus                                          |
| ------ | ---------------------------------------------- |
| Week 1 | Identity/Governance + Storage (read + labs)    |
| Week 2 | Compute + Networking (read + labs)             |
| Week 3 | Monitor/Backup + full practice exams           |
| Week 4 | Review weak areas + timed practice exams daily |

### Key Trigger Words

| Trigger                | Answer Pattern                     |
| ---------------------- | ---------------------------------- |
| "Least privilege"      | Smallest role that works           |
| "Cost effective"       | Scale out/autoscale, not upgrade   |
| "Without code changes" | Platform feature, not app redesign |
| "Minimum effort"       | Built-in tool over custom solution |

---

## Flashcards (75 cards)

### Card 1 [EASY]

**Q:** What is Microsoft Entra ID (formerly Azure AD)?

**A:** Microsoft's cloud-based identity and access management service. It helps employees sign in and access resources including Microsoft 365, Azure portal, and thousands of SaaS applications.

---

### Card 2 [MEDIUM]

**Q:** What are the main types of user accounts in Microsoft Entra ID?

**A:** • Cloud identities: Users created directly in Entra ID
• Directory-synchronized: Users synced from on-premises AD
• Guest users: External users invited via B2B collaboration

---

### Card 3 [MEDIUM]

**Q:** What is Self-Service Password Reset (SSPR)?

**A:** A feature that allows users to reset their own passwords without IT help desk intervention. Requires authentication methods (phone, email, security questions) and can be enabled for all, selected, or no users.

---

### Card 4 [MEDIUM]

**Q:** What are Microsoft Entra ID groups?

**A:** • Security groups: Manage access to resources
• Microsoft 365 groups: Collaboration with shared mailbox, calendar, files
• Membership types: Assigned, Dynamic user, Dynamic device

---

### Card 5 [EASY]

**Q:** What is Azure RBAC (Role-Based Access Control)?

**A:** Authorization system for managing who has access to Azure resources, what they can do, and what scope they can access. Built on Azure Resource Manager with roles like Owner, Contributor, Reader.

---

### Card 6 [MEDIUM]

**Q:** What are the key built-in RBAC roles?

**A:** • Owner: Full access including delegation
• Contributor: Full access except delegation
• Reader: View only
• User Access Administrator: Manage user access to resources

---

### Card 7 [MEDIUM]

**Q:** What is Azure Policy?

**A:** A service to create, assign, and manage policies that enforce rules and effects on resources. Ensures compliance with corporate standards and SLAs. Policies can audit or deny non-compliant resources.

---

### Card 8 [EASY]

**Q:** What are resource locks in Azure?

**A:** Prevent accidental deletion or modification of resources.
• CanNotDelete: Resources can be read and modified but not deleted
• ReadOnly: Resources can only be read, not modified or deleted

---

### Card 9 [MEDIUM]

**Q:** What are Azure Management Groups?

**A:** Containers for managing access, policies, and compliance across multiple subscriptions. Create a hierarchy for governance that applies to all subscriptions beneath. Maximum 6 levels of depth.

---

### Card 10 [EASY]

**Q:** What are Azure tags?

**A:** Name-value pairs for organizing resources. Use for cost tracking, automation, and resource management. Tags are NOT inherited by default. Maximum 50 tags per resource.

---

### Card 11 [MEDIUM]

**Q:** What is Azure Cost Management?

**A:** Tools for monitoring, allocating, and optimizing cloud costs. Features include cost analysis, budgets, alerts, recommendations, and integration with Azure Advisor for cost optimization.

---

### Card 12 [EASY]

**Q:** What is Azure Advisor?

**A:** A personalized cloud consultant that analyzes configurations and usage to recommend improvements in reliability, security, performance, operational excellence, and cost optimization.

---

### Card 13 [HARD]

**Q:** How do role assignments work in Azure RBAC?

**A:** Role assignments attach a role definition to a security principal at a particular scope.
• Security principal: User, group, service principal, managed identity
• Role: Collection of permissions
• Scope: Management group, subscription, resource group, or resource

---

### Card 14 [HARD]

**Q:** What is the difference between Azure Policy and RBAC?

**A:** • RBAC: Controls WHO can perform actions (user permissions)
• Azure Policy: Controls WHAT actions can be performed (resource compliance)
RBAC manages user access; Policy manages resource configuration.

---

### Card 15 [HARD]

**Q:** What are custom roles in Azure RBAC?

**A:** User-defined roles when built-in roles don't meet specific needs. Created using JSON defining Actions, NotActions, DataActions, NotDataActions, and AssignableScopes. Require Owner or User Access Admin permissions.

---

### Card 16 [MEDIUM]

**Q:** What are the Azure storage account types?

**A:** • Standard general-purpose v2: Blobs, Files, Queues, Tables
• Premium block blobs: High transaction rates
• Premium file shares: Enterprise file applications
• Premium page blobs: High-performance VM disks

---

### Card 17 [HARD]

**Q:** What are Azure storage redundancy options?

**A:** • LRS: 3 copies in one datacenter (11 9s durability)
• ZRS: 3 copies across availability zones (12 9s)
• GRS: LRS + async copy to secondary region (16 9s)
• GZRS: ZRS + async copy to secondary region (16 9s)

---

### Card 18 [EASY]

**Q:** What is Azure Blob Storage?

**A:** Object storage for unstructured data like text and binary data. Access tiers: Hot (frequent access), Cool (infrequent, 30+ days), Cold (rare, 90+ days), Archive (offline, 180+ days).

---

### Card 19 [MEDIUM]

**Q:** What is a Shared Access Signature (SAS)?

**A:** A URI that grants restricted access to storage resources. Types:
• User delegation SAS (most secure, uses Entra ID)
• Service SAS (specific service)
• Account SAS (multiple services)

---

### Card 20 [EASY]

**Q:** What are Azure storage access keys?

**A:** Two 512-bit keys for authorizing access to storage accounts. Best practices: Rotate regularly, use Key Vault for storage, prefer Entra ID authentication when possible.

---

### Card 21 [MEDIUM]

**Q:** What is Azure Files?

**A:** Fully managed file shares in the cloud accessible via SMB, NFS, or REST. Use for lift-and-shift, hybrid scenarios, and cloud-native apps. Supports Azure File Sync for on-premises caching.

---

### Card 22 [HARD]

**Q:** What is Azure File Sync?

**A:** Centralizes file shares in Azure Files while keeping local access. Features: cloud tiering (cache hot files locally), multi-site sync, disaster recovery. Requires sync agent on Windows Server.

---

### Card 23 [MEDIUM]

**Q:** What are blob lifecycle management policies?

**A:** Rules to automatically transition blobs between tiers or delete them. Based on: last modified date, creation date, last accessed date. Actions: tierToCool, tierToArchive, delete.

---

### Card 24 [EASY]

**Q:** What is soft delete for blobs?

**A:** Protects data from accidental deletion by retaining deleted data for a specified period (1-365 days). Can recover deleted blobs and snapshots. Enable for container and blob level.

---

### Card 25 [HARD]

**Q:** What are storage account firewalls and virtual networks?

**A:** Restrict storage account access to specific VNets, subnets, or IP ranges. Service endpoints route traffic over Azure backbone. Private endpoints provide private IP within VNet.

---

### Card 26 [MEDIUM]

**Q:** What is Azure Storage encryption?

**A:** All data encrypted at rest with 256-bit AES. Options:
• Microsoft-managed keys (default)
• Customer-managed keys in Key Vault
• Customer-provided keys for Blob storage

---

### Card 27 [HARD]

**Q:** What is object replication in Azure Storage?

**A:** Asynchronously copies blobs between containers in same or different storage accounts. Use for: latency reduction, compute efficiency, data distribution. Requires versioning and change feed.

---

### Card 28 [MEDIUM]

**Q:** What are blob snapshots and versions?

**A:** • Snapshots: Read-only point-in-time copies, manual creation
• Versioning: Automatic, maintains previous versions when modified
Both help protect against accidental deletion or modification.

---

### Card 29 [EASY]

**Q:** What is AzCopy?

**A:** Command-line utility for copying data to/from Azure Storage. Supports blobs, files, and tables. Features: resume failed jobs, sync capabilities, parallel transfers. Uses SAS or Entra ID auth.

---

### Card 30 [MEDIUM]

**Q:** What is Azure Import/Export service?

**A:** Securely transfer large amounts of data to Azure Blob or Azure Files by shipping disk drives. Used when network transfer is impractical. Supports BitLocker encryption.

---

### Card 31 [MEDIUM]

**Q:** What are ARM templates?

**A:** JSON files that define infrastructure and configuration for Azure resources. Enable Infrastructure as Code (IaC). Features: declarative syntax, idempotent deployments, modular design, validation.

---

### Card 32 [MEDIUM]

**Q:** What is Azure Bicep?

**A:** Domain-specific language for deploying Azure resources. Compiles to ARM templates but with cleaner syntax, type safety, and better tooling. Native Azure support with no state files needed.

---

### Card 33 [MEDIUM]

**Q:** What are Azure VM sizes and series?

**A:** • B-series: Burstable, cost-effective
• D-series: General purpose
• E-series: Memory optimized
• F-series: Compute optimized
• N-series: GPU enabled
• L-series: Storage optimized

---

### Card 34 [HARD]

**Q:** What are Azure VM availability options?

**A:** • Availability Sets: Fault domains (power/network) + Update domains
• Availability Zones: Physically separate datacenters
• Virtual Machine Scale Sets: Auto-scaling identical VMs

---

### Card 35 [MEDIUM]

**Q:** What are Azure managed disks?

**A:** Block-level storage volumes managed by Azure. Types:
• Ultra: Highest IOPS and throughput
• Premium SSD v2: High performance, flexible
• Premium SSD: Production workloads
• Standard SSD/HDD: Dev/test, backup

---

### Card 36 [HARD]

**Q:** What is Azure Disk Encryption?

**A:** Uses BitLocker (Windows) or DM-Crypt (Linux) to encrypt OS and data disks. Integrated with Azure Key Vault. Options: Azure Disk Encryption (ADE), Server-Side Encryption with customer keys.

---

### Card 37 [MEDIUM]

**Q:** What are VM Scale Sets (VMSS)?

**A:** Create and manage a group of identical, load-balanced VMs. Auto-scale based on demand or schedule. Supports up to 1000 VMs (600 with custom images). Uses uniform or flexible orchestration.

---

### Card 38 [EASY]

**Q:** What is Azure Container Registry (ACR)?

**A:** Private Docker registry for storing and managing container images. Tiers: Basic, Standard, Premium. Features: geo-replication, image scanning, tasks for automated builds.

---

### Card 39 [EASY]

**Q:** What is Azure Container Instances (ACI)?

**A:** Fastest and simplest way to run containers in Azure without managing VMs. Use for: simple apps, task automation, CI/CD agents. Supports Linux and Windows containers.

---

### Card 40 [MEDIUM]

**Q:** What is Azure Container Apps?

**A:** Serverless container platform built on Kubernetes. Features: auto-scaling (including to zero), Dapr integration, traffic splitting, built-in HTTPS. Best for microservices and event-driven apps.

---

### Card 41 [EASY]

**Q:** What is Azure App Service?

**A:** Fully managed platform for building web apps, APIs, and mobile backends. Supports: .NET, Java, Node.js, Python, PHP. Features: auto-scale, CI/CD, custom domains, SSL, deployment slots.

---

### Card 42 [MEDIUM]

**Q:** What are App Service deployment slots?

**A:** Live apps with their own hostnames. Use for staging, testing, A/B testing. Swap slots to promote to production with no downtime. Settings can be slot-specific or swapped.

---

### Card 43 [MEDIUM]

**Q:** What are App Service plans?

**A:** Define compute resources for App Service apps. Tiers:
• Free/Shared: Dev/test, shared infrastructure
• Basic: Dedicated, no auto-scale
• Standard/Premium: Production, auto-scale, slots
• Isolated: High security, VNet integration

---

### Card 44 [MEDIUM]

**Q:** What is the Custom Script Extension for VMs?

**A:** Downloads and runs scripts on Azure VMs for post-deployment configuration. Supports PowerShell (Windows) and Bash (Linux). Timeout: 90 minutes. Common for software installation, config.

---

### Card 45 [EASY]

**Q:** What is Azure Bastion?

**A:** Fully managed PaaS service for secure RDP/SSH connectivity to VMs without exposing public IPs. Deployed per VNet. Protects against port scanning and zero-day exploits on public IPs.

---

### Card 46 [EASY]

**Q:** What is an Azure Virtual Network (VNet)?

**A:** Fundamental building block for private network in Azure. Enables resources to communicate with each other, internet, and on-premises. Features: isolation, subnets, routing, name resolution.

---

### Card 47 [MEDIUM]

**Q:** What are Azure subnets?

**A:** Segments within a VNet for organizing and securing resources. Each subnet has a range of IP addresses. Azure reserves 5 IPs per subnet (network, gateway, DNS x2, broadcast).

---

### Card 48 [MEDIUM]

**Q:** What is VNet peering?

**A:** Connects two VNets for low-latency, high-bandwidth private connectivity. Types:
• Regional: Same region
• Global: Cross-region
Traffic uses Microsoft backbone. Non-transitive by default.

---

### Card 49 [MEDIUM]

**Q:** What is a Network Security Group (NSG)?

**A:** Filter network traffic with security rules. Applied to subnets or NICs. Rules specify: priority (100-4096), source/destination, port, protocol, allow/deny. Lower priority number = higher precedence.

---

### Card 50 [HARD]

**Q:** What are Application Security Groups (ASG)?

**A:** Group VMs by application for easier NSG rule management. Instead of specifying IP addresses, reference ASG in rules. Simplifies security for multi-tier applications.

---

### Card 51 [MEDIUM]

**Q:** What is Azure DNS?

**A:** Hosting service for DNS domains. Features:
• Public zones: Internet-facing domains
• Private zones: Name resolution within VNets
• Alias records: Point to Azure resources
Uses Azure infrastructure for reliability.

---

### Card 52 [HARD]

**Q:** What are User-Defined Routes (UDR)?

**A:** Custom routes that override Azure's default system routes. Common uses: force traffic through NVA or firewall, route to VPN gateway. Applied to subnets via route tables.

---

### Card 53 [MEDIUM]

**Q:** What is Azure Load Balancer?

**A:** Layer 4 (TCP/UDP) load balancer. Types:
• Public: Distributes internet traffic to VMs
• Internal: Distributes traffic within VNet
SKUs: Basic (free, limited) and Standard (SLA, zone-redundant).

---

### Card 54 [MEDIUM]

**Q:** What is Azure Application Gateway?

**A:** Layer 7 (HTTP/HTTPS) load balancer. Features: SSL termination, URL-based routing, cookie affinity, WAF integration, autoscaling. Ideal for web application traffic management.

---

### Card 55 [MEDIUM]

**Q:** What are service endpoints?

**A:** Extend VNet private address space to Azure services over the Azure backbone. Secure resources to specific VNets. Supported services: Storage, SQL, Key Vault, Service Bus, etc.

---

### Card 56 [HARD]

**Q:** What are private endpoints?

**A:** Network interface with private IP that connects privately to a service. More secure than service endpoints as traffic never leaves VNet. Uses Azure Private Link. Supports on-premises access.

---

### Card 57 [MEDIUM]

**Q:** What is Azure VPN Gateway?

**A:** Enables encrypted cross-premises connectivity. Types:
• Site-to-Site: Connect on-premises to Azure
• Point-to-Site: Connect individual clients
• VNet-to-VNet: Connect Azure VNets
SKUs determine throughput and features.

---

### Card 58 [HARD]

**Q:** What is Azure ExpressRoute?

**A:** Private connection between on-premises and Azure via connectivity provider. Benefits: higher bandwidth (up to 100 Gbps), lower latency, more reliable than internet. Does NOT encrypt traffic by default.

---

### Card 59 [MEDIUM]

**Q:** What are public IP addresses in Azure?

**A:** SKUs: Basic (dynamic/static, open by default) and Standard (static only, secure by default, zone-redundant). Assignment: Dynamic (changes on stop) or Static (persistent).

---

### Card 60 [MEDIUM]

**Q:** What is Azure Firewall?

**A:** Cloud-native, stateful firewall as a service. Features: built-in HA, unrestricted scalability, application and network rules, threat intelligence filtering, FQDN tags. Tiers: Standard, Premium.

---

### Card 61 [EASY]

**Q:** What is Azure Monitor?

**A:** Comprehensive monitoring solution for collecting, analyzing, and acting on telemetry. Collects: metrics (numeric data), logs (text data), traces. Enables alerts, dashboards, and insights.

---

### Card 62 [MEDIUM]

**Q:** What are Azure Monitor metrics vs logs?

**A:** • Metrics: Numerical values collected at regular intervals, stored 93 days, near real-time alerts
• Logs: Text/structured data stored in Log Analytics, queryable with KQL, long retention

---

### Card 63 [MEDIUM]

**Q:** What is Log Analytics workspace?

**A:** Central repository for Azure Monitor logs. Collect data from multiple sources, query with KQL, visualize with workbooks. Features: data retention policies, access control, pricing tiers.

---

### Card 64 [MEDIUM]

**Q:** What are Azure Monitor alerts?

**A:** Proactively notify when conditions are met. Components:
• Target resource
• Signal (metric, log, activity log)
• Criteria/threshold
• Action group (email, SMS, webhook, etc.)
Stateful: Fired, Acknowledged, Closed.

---

### Card 65 [EASY]

**Q:** What are Azure Monitor action groups?

**A:** Reusable notification preferences. Actions include: Email/SMS, Azure Functions, Logic Apps, webhooks, ITSM, Automation runbooks. Assign to multiple alert rules.

---

### Card 66 [MEDIUM]

**Q:** What is Azure Network Watcher?

**A:** Network monitoring and diagnostic service. Tools: IP flow verify, next hop, connection troubleshoot, packet capture, NSG diagnostics, topology view, connection monitor.

---

### Card 67 [HARD]

**Q:** What is Connection Monitor in Network Watcher?

**A:** Monitors connectivity between sources and destinations. Checks: latency, packet loss, reachability. Supports hybrid scenarios with on-premises agents. Alerts on connectivity issues.

---

### Card 68 [EASY]

**Q:** What is Azure Backup?

**A:** Enterprise backup solution integrated into Azure. Supports: VMs, SQL in VMs, Azure Files, on-premises. Features: app-consistent backups, long-term retention, geo-redundancy.

---

### Card 69 [MEDIUM]

**Q:** What is a Recovery Services vault?

**A:** Storage entity for backup data and recovery points. Contains backup policies, recovery points, and protected items. Supports Azure VMs, SQL, Files, and on-premises workloads.

---

### Card 70 [MEDIUM]

**Q:** What are Azure VM backup policies?

**A:** Define backup frequency and retention. Standard policy: daily/weekly/monthly/yearly retention. Enhanced policy: Multiple backups per day. Instant restore for quick VM recovery.

---

### Card 71 [MEDIUM]

**Q:** What is Azure Site Recovery (ASR)?

**A:** Disaster recovery as a service. Replicates VMs to secondary region. Features: automated protection, recovery plans, non-disruptive DR drills, RPO in minutes. Supports Azure-to-Azure and on-premises.

---

### Card 72 [HARD]

**Q:** What is a recovery plan in ASR?

**A:** Customizable model for failover. Define: order of machine recovery, manual actions, scripts, dependencies. Run test failovers without affecting production. Automate complex multi-tier app recovery.

---

### Card 73 [MEDIUM]

**Q:** What is VM Insights?

**A:** Monitor VM performance and health at scale. Features: performance charts, dependency maps, health diagnostics. Requires Log Analytics agent. View trends across multiple VMs.

---

### Card 74 [HARD]

**Q:** What is the Azure Monitor Agent (AMA)?

**A:** New unified agent replacing Log Analytics agent and Diagnostics extension. Collects: performance counters, logs, Windows events. Uses Data Collection Rules (DCR) for flexible configuration.

---

### Card 75 [EASY]

**Q:** What is Azure Activity Log?

**A:** Platform log recording subscription-level events. Tracks: resource creation/modification/deletion, service health, recommendations. Retention: 90 days (export to Log Analytics for longer).

---

## Practice Quiz (150 questions)

### Question 1

Which service is used to manage users, groups, and access to Azure resources?

- A) Azure Key Vault
- B) Microsoft Entra ID **[CORRECT]**
- C) Azure Monitor
- D) Azure Policy

> **Explanation:** Microsoft Entra ID (formerly Azure AD) is the identity and access management service for managing users, groups, and resource access.

---

### Question 2

What does Azure RBAC control?

- A) Network traffic between VNets
- B) Who has access to Azure resources and what they can do **[CORRECT]**
- C) Virtual machine pricing
- D) Storage account encryption

> **Explanation:** Azure RBAC (Role-Based Access Control) controls who has access to Azure resources, what they can do with those resources, and at what scope.

---

### Question 3

Which built-in RBAC role can manage all resources but cannot grant access to others?

- A) Owner
- B) Contributor **[CORRECT]**
- C) Reader
- D) User Access Administrator

> **Explanation:** The Contributor role can create and manage all types of Azure resources but cannot grant access to others.

---

### Question 4

What is the purpose of Azure Management Groups?

- A) Store encryption keys
- B) Organize subscriptions for governance at scale **[CORRECT]**
- C) Monitor virtual machine performance
- D) Configure network security rules

> **Explanation:** Management Groups help organize subscriptions into containers to apply governance policies and access controls across multiple subscriptions.

---

### Question 5

Which type of resource lock prevents modification but allows deletion?

- A) CanNotDelete
- B) ReadOnly **[CORRECT]**
- C) DoNotModify
- D) PreventChanges

> **Explanation:** ReadOnly locks prevent any modifications to resources but allow them to be deleted. CanNotDelete allows modifications but prevents deletion.

---

### Question 6

What is the maximum number of tags that can be applied to a single Azure resource?

- A) 15
- B) 25
- C) 50 **[CORRECT]**
- D) 100

> **Explanation:** Azure allows a maximum of 50 tags per resource. Tags are name-value pairs used for organizing and managing resources.

---

### Question 7

Which Azure service provides recommendations for reliability, security, and cost optimization?

- A) Azure Policy
- B) Azure Advisor **[CORRECT]**
- C) Azure Monitor
- D) Azure Blueprints

> **Explanation:** Azure Advisor is a personalized cloud consultant that provides recommendations to optimize deployments for reliability, security, performance, cost, and operational excellence.

---

### Question 8

What is the difference between Azure Policy and Azure RBAC?

- A) Policy controls WHO can access resources; RBAC controls WHAT resources can do
- B) Policy controls WHAT resources can do; RBAC controls WHO can access resources **[CORRECT]**
- C) They are the same thing with different names
- D) Policy is for storage only; RBAC is for compute only

> **Explanation:** Azure Policy controls what actions resources can perform (compliance), while RBAC controls who can perform actions on resources (access).

---

### Question 9

Which authentication method does Self-Service Password Reset (SSPR) NOT support?

- A) Mobile phone
- B) Email
- C) Security questions
- D) Fingerprint scanner **[CORRECT]**

> **Explanation:** SSPR supports mobile phone, email, security questions, mobile app notifications, and office phone. Fingerprint scanning is not a supported authentication method for SSPR.

---

### Question 10

What is the maximum depth of Azure Management Group hierarchy?

- A) 3 levels
- B) 6 levels **[CORRECT]**
- C) 10 levels
- D) Unlimited

> **Explanation:** Azure Management Groups support a maximum of 6 levels of depth (not including the root or subscription level).

---

### Question 11

Which storage redundancy option replicates data across availability zones?

- A) LRS (Locally Redundant Storage)
- B) GRS (Geo-Redundant Storage)
- C) ZRS (Zone-Redundant Storage) **[CORRECT]**
- D) RA-GRS (Read-Access Geo-Redundant Storage)

> **Explanation:** ZRS replicates data synchronously across three availability zones in the primary region, providing high availability.

---

### Question 12

What is the most cost-effective storage tier for data accessed less than once a year?

- A) Hot
- B) Cool
- C) Cold
- D) Archive **[CORRECT]**

> **Explanation:** Archive tier is the most cost-effective for rarely accessed data (180+ days), with the lowest storage costs but highest access costs and retrieval latency.

---

### Question 13

Which SAS type is the most secure option for delegating access to storage?

- A) Account SAS
- B) Service SAS
- C) User delegation SAS **[CORRECT]**
- D) Ad-hoc SAS

> **Explanation:** User delegation SAS is the most secure because it's signed with Entra ID credentials rather than the storage account key.

---

### Question 14

What is the purpose of Azure File Sync?

- A) Backup virtual machines to Azure
- B) Sync files from on-premises servers to Azure Files **[CORRECT]**
- C) Replicate databases across regions
- D) Monitor file access patterns

> **Explanation:** Azure File Sync enables centralizing file shares in Azure Files while maintaining local server access with cloud tiering capabilities.

---

### Question 15

Which tool is best for copying large amounts of data to Azure Storage via command line?

- A) Azure Storage Explorer
- B) AzCopy **[CORRECT]**
- C) Azure Portal
- D) PowerShell only

> **Explanation:** AzCopy is a command-line utility optimized for high-performance data transfer to and from Azure Storage with features like parallel transfers and resumable jobs.

---

### Question 16

What does soft delete protect against in Azure Blob Storage?

- A) Encryption key loss
- B) Accidental deletion of blobs **[CORRECT]**
- C) Network attacks
- D) Storage account misconfiguration

> **Explanation:** Soft delete retains deleted blobs for a specified period (1-365 days), allowing recovery from accidental deletions.

---

### Question 17

Which feature automatically moves blobs between access tiers based on rules?

- A) Object replication
- B) Lifecycle management policies **[CORRECT]**
- C) Azure File Sync
- D) Blob versioning

> **Explanation:** Lifecycle management policies automate transitioning blobs between tiers (Hot → Cool → Archive) or deleting them based on age or access patterns.

---

### Question 18

How many storage account access keys does Azure provide?

- A) 1
- B) 2 **[CORRECT]**
- C) 3
- D) 4

> **Explanation:** Azure provides two 512-bit access keys per storage account, allowing key rotation without downtime.

---

### Question 19

Which storage feature provides a private IP address for accessing storage from within a VNet?

- A) Service endpoints
- B) Private endpoints **[CORRECT]**
- C) Storage firewalls
- D) Access keys

> **Explanation:** Private endpoints provide a private IP address within your VNet for accessing Azure services, ensuring traffic stays on the Microsoft backbone.

---

### Question 20

What protocol does Azure Files support for Windows-based access?

- A) NFS only
- B) SMB only
- C) SMB and NFS **[CORRECT]**
- D) iSCSI

> **Explanation:** Azure Files supports both SMB (primarily for Windows) and NFS (for Linux) protocols, as well as REST API access.

---

### Question 21

What is Azure Bicep?

- A) A virtual machine monitoring tool
- B) A domain-specific language for deploying Azure resources **[CORRECT]**
- C) A backup service
- D) A container orchestration platform

> **Explanation:** Azure Bicep is a domain-specific language that compiles to ARM templates, providing cleaner syntax for Infrastructure as Code deployments.

---

### Question 22

Which VM series is best for burstable, cost-effective workloads?

- A) D-series
- B) E-series
- C) B-series **[CORRECT]**
- D) N-series

> **Explanation:** B-series VMs are burstable instances that are cost-effective for workloads with variable CPU usage that don't need full CPU continuously.

---

### Question 23

What do Availability Sets protect against?

- A) Regional failures only
- B) Hardware failures and planned maintenance **[CORRECT]**
- C) DDoS attacks
- D) Data encryption issues

> **Explanation:** Availability Sets use fault domains (separate power/network) and update domains to protect VMs from hardware failures and planned maintenance.

---

### Question 24

What is the maximum number of VMs supported in a Virtual Machine Scale Set?

- A) 100
- B) 500
- C) 1000 **[CORRECT]**
- D) 5000

> **Explanation:** VM Scale Sets support up to 1000 VM instances (or 600 with custom images).

---

### Question 25

Which service provides the fastest way to run containers without managing VMs?

- A) Azure Virtual Machines
- B) Azure Container Instances **[CORRECT]**
- C) Azure Kubernetes Service
- D) Azure App Service

> **Explanation:** Azure Container Instances (ACI) is the fastest and simplest way to run containers in Azure without managing infrastructure.

---

### Question 26

What are App Service deployment slots used for?

- A) Increasing storage capacity
- B) Staging and testing before production with zero-downtime swaps **[CORRECT]**
- C) Encrypting application data
- D) Load balancing traffic

> **Explanation:** Deployment slots allow running separate app instances (staging, testing) and swapping them to production without downtime.

---

### Question 27

Which disk type provides the highest IOPS and throughput in Azure?

- A) Standard HDD
- B) Standard SSD
- C) Premium SSD
- D) Ultra Disk **[CORRECT]**

> **Explanation:** Ultra Disks provide the highest IOPS and throughput for demanding workloads like SAP HANA and top-tier databases.

---

### Question 28

What does Azure Container Registry (ACR) store?

- A) Virtual machine images
- B) Docker container images **[CORRECT]**
- C) ARM templates
- D) Database backups

> **Explanation:** Azure Container Registry is a private Docker registry for storing and managing container images for Azure deployments.

---

### Question 29

What is the Custom Script Extension used for?

- A) Encrypting VM disks
- B) Running post-deployment scripts on VMs **[CORRECT]**
- C) Backing up VMs
- D) Monitoring VM performance

> **Explanation:** Custom Script Extension downloads and executes scripts on Azure VMs for post-deployment configuration tasks like installing software.

---

### Question 30

Which Azure service provides secure RDP/SSH access to VMs without public IPs?

- A) Azure VPN Gateway
- B) Azure Bastion **[CORRECT]**
- C) Azure Load Balancer
- D) Azure Firewall

> **Explanation:** Azure Bastion is a PaaS service that provides secure RDP/SSH connectivity to VMs directly from the Azure portal without exposing public IPs.

---

### Question 31

How many IP addresses does Azure reserve in each subnet?

- A) 2
- B) 3
- C) 5 **[CORRECT]**
- D) 10

> **Explanation:** Azure reserves 5 IP addresses per subnet: network address, default gateway, Azure DNS (x2), and broadcast address.

---

### Question 32

What is VNet peering?

- A) A method to encrypt VNet traffic
- B) A connection between two VNets for private communication **[CORRECT]**
- C) A backup solution for VNets
- D) A way to monitor VNet traffic

> **Explanation:** VNet peering connects two virtual networks enabling resources in each VNet to communicate privately using the Microsoft backbone.

---

### Question 33

What does an NSG (Network Security Group) control?

- A) User access to Azure portal
- B) Network traffic filtering with security rules **[CORRECT]**
- C) DNS resolution
- D) Storage account access

> **Explanation:** NSGs filter network traffic to and from Azure resources with security rules that specify source, destination, port, and protocol.

---

### Question 34

In NSG rules, which priority number has the highest precedence?

- A) 100 **[CORRECT]**
- B) 1000
- C) 4096
- D) 65000

> **Explanation:** Lower priority numbers have higher precedence. Priority 100 is evaluated before priority 1000 or higher.

---

### Question 35

What layer does Azure Load Balancer operate at?

- A) Layer 3 (Network)
- B) Layer 4 (Transport) **[CORRECT]**
- C) Layer 7 (Application)
- D) Layer 2 (Data Link)

> **Explanation:** Azure Load Balancer is a Layer 4 (TCP/UDP) load balancer that distributes traffic based on IP and port.

---

### Question 36

What layer does Azure Application Gateway operate at?

- A) Layer 3 (Network)
- B) Layer 4 (Transport)
- C) Layer 7 (Application) **[CORRECT]**
- D) Layer 2 (Data Link)

> **Explanation:** Azure Application Gateway is a Layer 7 load balancer that can route based on URL path, hostname, and supports SSL termination.

---

### Question 37

Which Azure service provides private dedicated connectivity to Azure bypassing the internet?

- A) VPN Gateway
- B) ExpressRoute **[CORRECT]**
- C) Azure Bastion
- D) Virtual WAN

> **Explanation:** Azure ExpressRoute provides private, dedicated connections between on-premises infrastructure and Azure through connectivity providers.

---

### Question 38

What are User-Defined Routes (UDR) used for?

- A) Defining user access policies
- B) Overriding Azure's default system routes **[CORRECT]**
- C) Managing DNS records
- D) Configuring VM sizes

> **Explanation:** User-Defined Routes allow you to create custom routes that override Azure's default system routes, commonly used to force traffic through firewalls or NVAs.

---

### Question 39

Which DNS zone type provides name resolution within virtual networks?

- A) Public DNS zone
- B) Private DNS zone **[CORRECT]**
- C) External DNS zone
- D) Global DNS zone

> **Explanation:** Private DNS zones provide name resolution for resources within virtual networks without exposing records to the internet.

---

### Question 40

What is the difference between Standard and Basic public IP SKUs?

- A) Basic is zone-redundant; Standard is not
- B) Standard is secure by default and zone-redundant; Basic is not **[CORRECT]**
- C) They are identical in features
- D) Basic supports static only; Standard supports dynamic only

> **Explanation:** Standard SKU public IPs are secure by default (closed to inbound traffic unless allowed by NSG), zone-redundant, and support only static allocation.

---

### Question 41

What is Azure Monitor used for?

- A) Managing user identities
- B) Collecting and analyzing telemetry from Azure resources **[CORRECT]**
- C) Deploying ARM templates
- D) Configuring network security

> **Explanation:** Azure Monitor is a comprehensive monitoring solution for collecting, analyzing, and acting on telemetry from Azure and on-premises environments.

---

### Question 42

What is the difference between Azure Monitor metrics and logs?

- A) Metrics are text data; logs are numeric data
- B) Metrics are numeric time-series data; logs are text/structured data **[CORRECT]**
- C) They are the same thing
- D) Metrics are for storage; logs are for compute

> **Explanation:** Metrics are lightweight numeric data collected at regular intervals, while logs are rich text or structured data stored in Log Analytics for complex querying.

---

### Question 43

Where are Azure Monitor logs stored for querying?

- A) Azure Blob Storage
- B) Log Analytics workspace **[CORRECT]**
- C) Azure SQL Database
- D) Azure Cosmos DB

> **Explanation:** Azure Monitor logs are stored in Log Analytics workspaces where they can be queried using Kusto Query Language (KQL).

---

### Question 44

What are Azure Monitor action groups?

- A) Groups of users who can view alerts
- B) Reusable collections of notification and action preferences **[CORRECT]**
- C) Sets of metrics to monitor
- D) Categories of log data

> **Explanation:** Action groups define a reusable set of notification preferences (email, SMS, webhook, etc.) that can be assigned to multiple alert rules.

---

### Question 45

Which tool in Network Watcher helps diagnose NSG rule issues?

- A) Connection Monitor
- B) IP Flow Verify **[CORRECT]**
- C) Packet Capture
- D) Topology View

> **Explanation:** IP Flow Verify checks if a packet is allowed or denied to or from a VM based on NSG rules, helping diagnose connectivity issues.

---

### Question 46

What is a Recovery Services vault used for?

- A) Storing encryption keys
- B) Storing backup data and recovery points **[CORRECT]**
- C) Managing user passwords
- D) Deploying virtual machines

> **Explanation:** Recovery Services vaults are storage entities in Azure that hold backup data, recovery points, and backup policies for protected resources.

---

### Question 47

What does Azure Site Recovery provide?

- A) Database optimization
- B) Disaster recovery as a service with VM replication **[CORRECT]**
- C) Cost management
- D) Identity management

> **Explanation:** Azure Site Recovery provides disaster recovery by replicating VMs to a secondary region with automated failover capabilities.

---

### Question 48

How long does Azure Activity Log retain data by default?

- A) 30 days
- B) 90 days **[CORRECT]**
- C) 180 days
- D) 365 days

> **Explanation:** Azure Activity Log retains data for 90 days by default. For longer retention, export to Log Analytics or Azure Storage.

---

### Question 49

What is the Azure Monitor Agent (AMA) replacing?

- A) Azure Bastion
- B) Log Analytics agent and Diagnostics extension **[CORRECT]**
- C) Azure Backup agent
- D) Azure AD Connect

> **Explanation:** The Azure Monitor Agent (AMA) is the new unified agent replacing the legacy Log Analytics agent (MMA/OMS) and Azure Diagnostics extension.

---

### Question 50

What can you test with Azure Site Recovery without affecting production?

- A) Billing calculations
- B) Test failover to validate recovery plans **[CORRECT]**
- C) Storage performance
- D) Network bandwidth

> **Explanation:** Azure Site Recovery supports test failovers that create a copy in the target region for validation without impacting production workloads.

---

### Question 51

A company needs to ensure that all Azure resources deployed in a subscription must be in the East US or West US regions. Which Azure service should you use?

- A) Azure Blueprints
- B) Azure Policy **[CORRECT]**
- C) Azure Resource Manager templates
- D) Management Groups

> **Explanation:** Azure Policy can enforce location restrictions by denying resource creation outside allowed regions. You would use the built-in 'Allowed locations' policy definition.

---

### Question 52

You need to grant a user the ability to manage virtual machines but not the virtual network they connect to. Which RBAC role should you assign?

- A) Contributor
- B) Virtual Machine Contributor **[CORRECT]**
- C) Owner
- D) Network Contributor

> **Explanation:** The Virtual Machine Contributor role lets you manage virtual machines but not the virtual network or storage account they are connected to, following the principle of least privilege.

---

### Question 53

You have an Azure Storage account. You need to ensure that data is replicated to a secondary region and that read access is available from the secondary region. Which replication type should you choose?

- A) Locally-redundant storage (LRS)
- B) Zone-redundant storage (ZRS)
- C) Geo-redundant storage (GRS)
- D) Read-access geo-redundant storage (RA-GRS) **[CORRECT]**

> **Explanation:** RA-GRS replicates data to a secondary geographic region and provides read access to the secondary endpoint, unlike GRS which only allows access to the secondary after a failover.

---

### Question 54

You are deploying an Azure Virtual Machine Scale Set. You need the instances to automatically scale based on CPU utilization. What should you configure?

- A) Azure Load Balancer health probes
- B) Autoscale settings with metric-based rules **[CORRECT]**
- C) Availability zones
- D) Azure Traffic Manager

> **Explanation:** Autoscale settings with metric-based rules allow VMSS to automatically add or remove instances based on metrics like CPU utilization, ensuring optimal performance and cost management.

---

### Question 55

Which PowerShell cmdlet would you use to create a new resource group in Azure?

- A) New-AzResource
- B) New-AzResourceGroup **[CORRECT]**
- C) Set-AzResourceGroup
- D) Add-AzResourceGroup

> **Explanation:** New-AzResourceGroup is the PowerShell cmdlet used to create a new resource group. It requires the -Name and -Location parameters.

---

### Question 56

A virtual machine in Azure has a public IP address assigned. You need to ensure the VM can only be accessed via RDP from your corporate network (203.0.113.0/24). What should you configure?

- A) Azure Firewall
- B) A Network Security Group inbound rule **[CORRECT]**
- C) Azure Front Door
- D) A route table

> **Explanation:** A Network Security Group (NSG) inbound rule can restrict RDP (port 3389) access to only the specified source IP range (203.0.113.0/24), providing network-level access control.

---

### Question 57

You need to move an Azure VM from one resource group to another within the same subscription. What happens to the VM during the move?

- A) The VM is deleted and recreated
- B) The VM is stopped and restarted
- C) The resource ID changes but the VM remains running **[CORRECT]**
- D) The VM's IP address changes

> **Explanation:** When moving a VM between resource groups, the resource ID of the VM changes to reflect the new resource group, but the VM itself continues running without interruption.

---

### Question 58

You need to configure Azure DNS to resolve a custom domain name to an Azure App Service. Which DNS record type should you create?

- A) A record
- B) CNAME record **[CORRECT]**
- C) MX record
- D) TXT record

> **Explanation:** A CNAME record is used to map a custom domain name (like www.contoso.com) to the Azure App Service default domain (contoso.azurewebsites.net). An A record can also be used with the IP address.

---

### Question 59

Which Azure service provides a fully managed domain controller service without the need to deploy and manage VMs?

- A) Microsoft Entra ID
- B) Microsoft Entra Domain Services **[CORRECT]**
- C) Active Directory Federation Services
- D) Azure Key Vault

> **Explanation:** Microsoft Entra Domain Services (formerly Azure AD DS) provides managed domain services such as domain join, group policy, LDAP, and Kerberos/NTLM authentication without deploying domain controllers.

---

### Question 60

You have a storage account with a blob container. You need to provide temporary read access to a specific blob for 24 hours to an external user. What should you use?

- A) Access keys
- B) Shared Access Signature (SAS) token **[CORRECT]**
- C) Microsoft Entra ID authentication
- D) Anonymous public access

> **Explanation:** A Shared Access Signature (SAS) token provides delegated access to resources with specified permissions and time constraints, making it ideal for granting temporary, scoped access to external users.

---

### Question 61

You need to deploy identical resources across multiple Azure regions. Which approach provides the most consistent and repeatable deployments?

- A) Azure Portal
- B) Azure CLI scripts
- C) ARM templates or Bicep **[CORRECT]**
- D) Azure PowerShell

> **Explanation:** ARM templates (or Bicep) provide declarative infrastructure-as-code deployments that ensure identical, consistent, and repeatable resource deployments across any number of regions.

---

### Question 62

What is the maximum number of Azure subscriptions that can be associated with a single Microsoft Entra ID tenant?

- A) 10
- B) 100
- C) 500
- D) There is no specific limit **[CORRECT]**

> **Explanation:** There is no specific limit on the number of Azure subscriptions that can trust a single Microsoft Entra ID tenant. A tenant can be associated with many subscriptions.

---

### Question 63

You need to create a VPN connection between your on-premises network and an Azure virtual network. Which two Azure resources are required? (Choose the best answer)

- A) Azure CDN and Application Gateway
- B) Virtual Network Gateway and Local Network Gateway **[CORRECT]**
- C) Azure Firewall and NSG
- D) ExpressRoute Circuit and Traffic Manager

> **Explanation:** A Site-to-Site VPN requires a Virtual Network Gateway (in Azure) and a Local Network Gateway (representing the on-premises VPN device) to establish the encrypted tunnel.

---

### Question 64

Which Azure Monitor feature allows you to proactively respond to critical conditions by sending notifications or triggering automated actions?

- A) Metrics Explorer
- B) Log Analytics
- C) Alert rules **[CORRECT]**
- D) Application Insights

> **Explanation:** Azure Monitor Alert rules evaluate conditions against metrics or logs and can trigger action groups to send notifications (email, SMS) or automated responses (Logic Apps, runbooks).

---

### Question 65

You are configuring an Azure Load Balancer. You need to distribute traffic based on a five-tuple hash. What does the five-tuple consist of?

- A) Source IP, destination IP, source port, destination port, protocol **[CORRECT]**
- B) Source IP, destination IP, source MAC, destination MAC, VLAN
- C) Source IP, destination IP, protocol, TTL, packet size
- D) Source port, destination port, protocol, sequence number, flags

> **Explanation:** Azure Load Balancer's default distribution mode uses a five-tuple hash of source IP, destination IP, source port, destination port, and protocol type to map traffic to available servers.

---

### Question 66

You need to configure a storage account so that blobs are automatically moved from Hot to Cool tier after 30 days. What should you configure?

- A) Azure Policy
- B) Lifecycle management rules **[CORRECT]**
- C) Azure Automation runbook
- D) Blob versioning

> **Explanation:** Lifecycle management rules allow you to automate tiering and deletion of blobs based on last modified or created time, reducing storage costs by moving infrequently accessed data to cooler tiers.

---

### Question 67

Which Azure compute option is best suited for running short-lived, event-driven code without managing infrastructure?

- A) Azure Virtual Machines
- B) Azure App Service
- C) Azure Functions **[CORRECT]**
- D) Azure Container Instances

> **Explanation:** Azure Functions is a serverless compute service that lets you run event-triggered code without managing infrastructure. It supports consumption-based pricing where you only pay for execution time.

---

### Question 68

You need to enable diagnostic logging for an Azure Virtual Machine to collect guest OS performance counters. What should you install?

- A) Azure Monitor Agent **[CORRECT]**
- B) Azure Site Recovery agent
- C) Azure Backup agent
- D) Custom Script Extension

> **Explanation:** The Azure Monitor Agent (AMA) collects monitoring data from the guest OS of VMs and delivers it to Azure Monitor. It replaces the legacy Log Analytics agent and Diagnostics extension.

---

### Question 69

You have two virtual networks, VNet1 and VNet2, that need to communicate. The address spaces do not overlap. What should you configure?

- A) VPN Gateway
- B) VNet Peering **[CORRECT]**
- C) Azure Front Door
- D) Azure Relay

> **Explanation:** VNet Peering enables seamless connectivity between two Azure virtual networks. Traffic between peered VNets uses the Microsoft backbone network, providing low-latency, high-bandwidth connections.

---

### Question 70

Which Azure Backup feature allows you to restore individual files from a VM backup without restoring the entire VM?

- A) Full VM restore
- B) File recovery **[CORRECT]**
- C) Snapshot restore
- D) Cross-region restore

> **Explanation:** Azure Backup's File Recovery feature mounts the backup as a drive on your machine, allowing you to browse and restore individual files and folders without restoring the entire VM.

---

### Question 71

You are configuring Conditional Access policies. Which condition allows you to require MFA only when users sign in from outside the corporate network?

- A) Device platform
- B) Named locations **[CORRECT]**
- C) Client apps
- D) User risk level

> **Explanation:** Named locations in Conditional Access allow you to define trusted IP ranges (like corporate networks) and create policies that require additional authentication when users sign in from outside those locations.

---

### Question 72

What is the purpose of Azure Bastion?

- A) Load balance traffic across VMs
- B) Provide secure RDP/SSH connectivity to VMs without public IP exposure **[CORRECT]**
- C) Monitor VM performance metrics
- D) Automate VM deployments

> **Explanation:** Azure Bastion provides secure and seamless RDP/SSH connectivity to virtual machines directly through the Azure portal over TLS, without the need to expose VMs via public IP addresses.

---

### Question 73

You need to ensure that deleted blobs in a storage account can be recovered for up to 14 days. What should you enable?

- A) Blob versioning
- B) Soft delete for blobs **[CORRECT]**
- C) Immutability policies
- D) Change feed

> **Explanation:** Soft delete for blobs protects data from accidental deletion by retaining deleted data for a specified retention period (1-365 days), allowing recovery of deleted blobs.

---

### Question 74

Which VM size series in Azure is optimized for memory-intensive workloads such as large databases and in-memory analytics?

- A) D-series (General purpose)
- B) F-series (Compute optimized)
- C) E-series (Memory optimized) **[CORRECT]**
- D) N-series (GPU enabled)

> **Explanation:** E-series VMs are memory optimized, offering high memory-to-CPU ratios ideal for relational databases, large caches, and in-memory analytics workloads.

---

### Question 75

You need to configure an Application Gateway to route traffic based on the URL path. What feature should you use?

- A) Health probes
- B) URL path-based routing rules **[CORRECT]**
- C) SSL termination
- D) Connection draining

> **Explanation:** URL path-based routing in Application Gateway allows you to route traffic to different backend pools based on the URL path of the request, such as /images/_ to one pool and /api/_ to another.

---

### Question 76

What is the Azure CLI command to list all resource groups in a subscription?

- A) az group list **[CORRECT]**
- B) az resourcegroup list
- C) az resource group show
- D) az list groups

> **Explanation:** The 'az group list' command lists all resource groups in the current subscription. You can add --output table for a formatted view.

---

### Question 77

You need to implement network isolation for an Azure SQL Database. Which feature allows the database to be accessed only from a specific virtual network?

- A) Transparent Data Encryption
- B) Virtual Network service endpoints **[CORRECT]**
- C) Always Encrypted
- D) Dynamic Data Masking

> **Explanation:** Virtual Network service endpoints extend your VNet identity to Azure SQL Database, allowing you to restrict access to only traffic from your specified virtual network subnet.

---

### Question 78

Which availability option provides the highest SLA for a single Azure VM?

- A) No availability configuration
- B) Availability Set
- C) Availability Zone **[CORRECT]**
- D) Virtual Machine Scale Set

> **Explanation:** Deploying a VM in an Availability Zone provides a 99.99% SLA, compared to 99.95% for Availability Sets and 99.9% for a single VM with premium storage.

---

### Question 79

You need to centrally manage and enforce password policies for cloud-only users. Where should you configure this?

- A) Azure Policy
- B) Microsoft Entra ID Password Protection **[CORRECT]**
- C) Azure Key Vault
- D) Conditional Access

> **Explanation:** Microsoft Entra ID Password Protection allows you to configure custom banned password lists and enforce password policies for cloud users, preventing weak or commonly used passwords.

---

### Question 80

What type of Azure disk provides the highest IOPS and lowest latency for mission-critical workloads?

- A) Standard HDD
- B) Standard SSD
- C) Premium SSD
- D) Ultra Disk **[CORRECT]**

> **Explanation:** Ultra Disks provide the highest performance tier with up to 160,000 IOPS and 4,000 MB/s throughput per disk, with sub-millisecond latency for demanding workloads like SAP HANA and top-tier databases.

---

### Question 81

You need to deploy a containerized application without managing the underlying infrastructure. The container should run on-demand and you want per-second billing. Which service should you use?

- A) Azure Kubernetes Service
- B) Azure Container Instances **[CORRECT]**
- C) Azure App Service
- D) Azure Virtual Machines

> **Explanation:** Azure Container Instances (ACI) provides the fastest and simplest way to run containers in Azure without managing VMs. It offers per-second billing and is ideal for short-lived, on-demand workloads.

---

### Question 82

You are configuring Azure Monitor to collect logs from multiple VMs. Where should you send the collected log data for querying with KQL?

- A) Azure Storage account
- B) Log Analytics workspace **[CORRECT]**
- C) Event Hub
- D) Azure SQL Database

> **Explanation:** A Log Analytics workspace is the primary destination for Azure Monitor log data. It stores the data and provides the query engine (KQL - Kusto Query Language) for analysis and visualization.

---

### Question 83

You have an Azure subscription with multiple resource groups. You need to apply a consistent set of tags to all resources for cost tracking. What is the most efficient approach?

- A) Manually tag each resource in the portal
- B) Use Azure Policy with a 'Modify' effect to automatically apply tags **[CORRECT]**
- C) Write a PowerShell script to tag resources one by one
- D) Use Azure Advisor recommendations

> **Explanation:** Azure Policy with a 'Modify' effect can automatically add or update tags on resources during creation or updates, ensuring consistent tagging across all resources without manual intervention.

---

### Question 84

What is the purpose of an Azure Network Security Group (NSG) application security group?

- A) Encrypt network traffic between VMs
- B) Group VMs logically and define NSG rules based on application roles **[CORRECT]**
- C) Load balance traffic across application tiers
- D) Monitor application performance

> **Explanation:** Application Security Groups (ASGs) allow you to group VMs by application role (web servers, database servers) and use those groups in NSG rules, simplifying security management for complex environments.

---

### Question 85

You need to implement a backup solution for Azure Files shares. Which service should you use?

- A) Azure Site Recovery
- B) Azure Backup with Azure Files backup **[CORRECT]**
- C) AzCopy scheduled task
- D) Storage Account replication

> **Explanation:** Azure Backup provides a native, fully managed backup solution for Azure Files that supports snapshot-based backups, point-in-time restore, and integration with Recovery Services vault policies.

---

### Question 86

You need to configure an Azure Virtual Machine to automatically shut down every day at 7:00 PM to save costs. Where do you configure this?

- A) Azure Advisor
- B) Auto-shutdown in the VM configuration **[CORRECT]**
- C) Azure Automation
- D) Azure Policy

> **Explanation:** Azure VMs have a built-in auto-shutdown feature that can be configured directly in the VM settings. You specify the shutdown time and time zone, and optionally receive a notification before shutdown.

---

### Question 87

Which Azure storage service is a fully managed file share that supports the SMB and NFS protocols?

- A) Azure Blob Storage
- B) Azure Files **[CORRECT]**
- C) Azure Table Storage
- D) Azure Queue Storage

> **Explanation:** Azure Files provides fully managed file shares accessible via SMB (Server Message Block) and NFS (Network File System) protocols, which can be mounted simultaneously by cloud or on-premises deployments.

---

### Question 88

You need to create a custom RBAC role that allows users to restart VMs but not delete them. What should you include in the role definition?

- A) Actions: Microsoft.Compute/virtualMachines/\*
- B) Actions: Microsoft.Compute/virtualMachines/restart/action, NotActions: Microsoft.Compute/virtualMachines/delete
- C) Actions: Microsoft.Compute/virtualMachines/restart/action only **[CORRECT]**
- D) AssignableScopes: /subscriptions/\* with Reader role

> **Explanation:** A custom RBAC role should include only the specific actions needed. By specifying only the restart action, users can restart VMs but have no other permissions including delete.

---

### Question 89

You are designing a network architecture. You need to route all outbound internet traffic from Azure VMs through an on-premises firewall. What should you configure?

- A) Forced tunneling via User Defined Routes **[CORRECT]**
- B) Azure Firewall
- C) NAT Gateway
- D) Application Gateway

> **Explanation:** Forced tunneling uses User Defined Routes (UDRs) to redirect all internet-bound traffic from Azure VMs through the VPN tunnel to the on-premises network for inspection by an on-premises firewall.

---

### Question 90

What is the purpose of Azure Cost Management + Billing budgets?

- A) Automatically stop resources when budget is exceeded
- B) Set spending thresholds and receive alerts when costs approach or exceed the budget **[CORRECT]**
- C) Allocate funds to specific resource groups
- D) Negotiate pricing discounts with Microsoft

> **Explanation:** Azure Budgets allow you to set spending thresholds and configure alerts at various percentage levels (e.g., 50%, 75%, 100%) to monitor and control cloud spending proactively.

---

### Question 91

You need to enable encryption at rest for an Azure managed disk using your own encryption key. What should you use?

- A) Azure Disk Encryption with BitLocker
- B) Server-side encryption with customer-managed keys in Azure Key Vault **[CORRECT]**
- C) Storage Service Encryption
- D) TLS 1.2

> **Explanation:** Server-side encryption (SSE) with customer-managed keys (CMK) stored in Azure Key Vault provides control over the encryption keys used for managed disk encryption at rest.

---

### Question 92

Which networking feature allows you to extend a private IP address space to Azure services, eliminating exposure to the public internet?

- A) Service endpoints
- B) Private endpoints (Azure Private Link) **[CORRECT]**
- C) Public IP address
- D) Azure CDN

> **Explanation:** Private Endpoints (Azure Private Link) provide a private IP address from your VNet to Azure services, ensuring traffic stays on the Microsoft backbone network without internet exposure.

---

### Question 93

You need to configure an Azure VM to use multiple NICs. What is a prerequisite?

- A) The VM must use Premium SSD disks
- B) The VM size must support multiple NICs **[CORRECT]**
- C) The VM must be in an Availability Zone
- D) The VM must be running Windows Server

> **Explanation:** Not all VM sizes support multiple NICs. The number of NICs a VM can have depends on the VM size. You must select a VM size that supports the required number of NICs.

---

### Question 94

You have deployed an Azure App Service web app. You need to configure a custom domain with SSL. Which certificate source is built into App Service at no extra cost?

- A) Azure Key Vault certificate
- B) App Service Managed Certificate **[CORRECT]**
- C) Third-party CA certificate
- D) Self-signed certificate

> **Explanation:** App Service Managed Certificates are free SSL/TLS certificates created and managed by Azure. They auto-renew and are ideal for securing custom domains on App Service.

---

### Question 95

What KQL query would you use in Log Analytics to find all heartbeat failures in the last 24 hours?

- A) Heartbeat | where TimeGenerated > ago(24h) | summarize LastHeartbeat = max(TimeGenerated) by Computer **[CORRECT]**
- B) SELECT \* FROM Heartbeat WHERE time > NOW() - 24h
- C) Get-AzLog -TimeGenerated 24h -Category Heartbeat
- D) az monitor log-query --query Heartbeat --timespan 24h

> **Explanation:** KQL (Kusto Query Language) is used in Log Analytics. The query filters the Heartbeat table for the last 24 hours and summarizes the last heartbeat per computer to identify failures.

---

### Question 96

You need to configure Azure Storage so that a blob container can only be accessed from a specific subnet. What should you configure?

- A) Access keys rotation
- B) Storage account firewall and virtual network rules **[CORRECT]**
- C) Blob access tier
- D) CORS rules

> **Explanation:** Storage account firewall and virtual network rules restrict access to the storage account from specific subnets, IP addresses, or Azure services, providing network-level security.

---

### Question 97

Which Azure service should you use to automate the deployment and configuration of VMs at scale using desired state configuration?

- A) Azure DevOps
- B) Azure Automation State Configuration (DSC) **[CORRECT]**
- C) Azure Advisor
- D) Azure Monitor

> **Explanation:** Azure Automation State Configuration (DSC) allows you to define and automatically enforce the desired configuration state of VMs at scale, ensuring consistency across your environment.

---

### Question 98

You have a Recovery Services vault protecting multiple VMs. You need to ensure backups are retained for 1 year for compliance. What should you configure?

- A) Backup frequency
- B) Retention policy in the backup policy **[CORRECT]**
- C) Soft delete settings
- D) Geo-redundancy

> **Explanation:** The retention policy within a backup policy defines how long recovery points are kept. You can configure daily, weekly, monthly, and yearly retention periods to meet compliance requirements.

---

### Question 99

What is the maximum size of a single block blob in Azure Blob Storage?

- A) 5 TB
- B) 190.7 TiB **[CORRECT]**
- C) 1 PB
- D) 100 TB

> **Explanation:** A single block blob can be up to approximately 190.7 TiB (4.77 TB x 50,000 blocks at 4000 MiB per block). This supports extremely large object storage scenarios.

---

### Question 100

You need to configure Azure ExpressRoute for a hybrid connection. What does ExpressRoute provide that a Site-to-Site VPN does not?

- A) Encrypted tunnel over the internet
- B) Private dedicated connection that does not traverse the public internet **[CORRECT]**
- C) SSL certificate management
- D) DNS resolution

> **Explanation:** ExpressRoute provides a private, dedicated connection between on-premises infrastructure and Azure through a connectivity provider, bypassing the public internet for higher reliability, faster speeds, and lower latencies.

---

### Question 101

You need to assign a static private IP address to an Azure VM's network interface. Where should you configure this?

- A) The VM's OS network settings
- B) The network interface IP configuration in Azure **[CORRECT]**
- C) The virtual network address space
- D) Azure DNS

> **Explanation:** Static private IP addresses are configured on the network interface's IP configuration in Azure, not within the guest OS. You change the allocation method from Dynamic to Static.

---

### Question 102

A company requires that all storage accounts must enforce HTTPS-only traffic. Which Azure service enforces this requirement across all subscriptions?

- A) Azure Firewall
- B) Azure Policy with a Deny effect **[CORRECT]**
- C) Network Security Group
- D) Azure Monitor

> **Explanation:** Azure Policy with a Deny effect can prevent the creation of storage accounts that do not enforce HTTPS. The built-in policy 'Secure transfer to storage accounts should be enabled' enforces this.

---

### Question 103

You have a VM running in Azure. You need to add a new data disk to the VM. What is the correct order of steps?

- A) Create a disk, attach it to the VM, initialize and format it in the OS **[CORRECT]**
- B) Initialize a disk in the OS, then attach it in the Azure portal
- C) Create a snapshot first, then attach the disk
- D) Stop the VM, create the disk, restart the VM

> **Explanation:** To add a data disk: first create or select a managed disk in Azure, attach it to the VM through the portal or CLI, then initialize and format the disk within the guest operating system.

---

### Question 104

Which type of Azure Load Balancer operates at Layer 7 and can make routing decisions based on HTTP headers and URL paths?

- A) Azure Load Balancer (Basic)
- B) Azure Load Balancer (Standard)
- C) Azure Application Gateway **[CORRECT]**
- D) Azure Traffic Manager

> **Explanation:** Azure Application Gateway is a Layer 7 (application layer) load balancer that can route traffic based on HTTP attributes like URL paths, host headers, and query strings.

---

### Question 105

You need to ensure a user can only create resources that use specific VM SKUs. Which Azure governance tool should you use?

- A) Azure Blueprints
- B) Azure Policy with allowed VM SKUs **[CORRECT]**
- C) Azure RBAC
- D) Management Groups

> **Explanation:** Azure Policy with the built-in 'Allowed virtual machine size SKUs' policy restricts which VM sizes users can deploy, enforcing cost and compliance controls.

---

### Question 106

What happens when you deallocate an Azure VM?

- A) The VM is deleted permanently
- B) You are charged for compute but not storage
- C) Compute charges stop but storage charges continue for the OS and data disks **[CORRECT]**
- D) All charges stop including storage

> **Explanation:** When a VM is deallocated, compute charges stop and the public dynamic IP is released, but you continue to pay for the managed disks (OS and data disks) attached to the VM.

---

### Question 107

You need to peer two virtual networks in different Azure regions. What type of peering is this?

- A) Local VNet peering
- B) Global VNet peering **[CORRECT]**
- C) VPN Gateway peering
- D) ExpressRoute peering

> **Explanation:** Global VNet peering connects virtual networks across different Azure regions. Traffic between globally peered VNets travels over the Microsoft backbone network.

---

### Question 108

Which storage access tier has the lowest storage cost but the highest access cost?

- A) Hot
- B) Cool
- C) Cold
- D) Archive **[CORRECT]**

> **Explanation:** The Archive tier has the lowest storage cost per GB but the highest access and retrieval costs. Data must be rehydrated to Hot or Cool before it can be read, which can take hours.

---

### Question 109

You are configuring an Azure Recovery Services vault. Which backup policy setting determines how many recovery points are retained?

- A) Backup frequency
- B) Retention range **[CORRECT]**
- C) Consistency type
- D) Snapshot tier

> **Explanation:** The retention range in a backup policy determines how long daily, weekly, monthly, and yearly recovery points are kept, controlling how far back in time you can restore.

---

### Question 110

You need to configure Microsoft Entra ID self-service password reset (SSPR). Which authentication methods can users use to verify their identity? (Choose the best answer)

- A) Only security questions
- B) Email, phone, authenticator app, and security questions **[CORRECT]**
- C) Only email and phone
- D) Only the Microsoft Authenticator app

> **Explanation:** SSPR supports multiple authentication methods including email, mobile phone, office phone, Microsoft Authenticator app, OATH tokens, and security questions.

---

### Question 111

Which Azure networking component provides DDoS protection for resources in a virtual network?

- A) Network Security Group
- B) Azure DDoS Protection **[CORRECT]**
- C) Azure Firewall
- D) Web Application Firewall

> **Explanation:** Azure DDoS Protection provides enhanced mitigation against DDoS attacks for Azure resources in virtual networks. It offers always-on traffic monitoring and automatic attack mitigation.

---

### Question 112

You need to copy a large number of files from an on-premises file server to Azure Blob Storage. Which tool is best suited for high-performance bulk transfers?

- A) Azure Storage Explorer
- B) AzCopy **[CORRECT]**
- C) Azure Portal upload
- D) Azure File Sync

> **Explanation:** AzCopy is a command-line tool optimized for high-performance data transfer to and from Azure Storage. It supports parallel transfers, resume capability, and can handle millions of files.

---

### Question 113

What is the default priority value for a new NSG inbound security rule?

- A) 100
- B) There is no default; you must specify it **[CORRECT]**
- C) 1000
- D) 65000

> **Explanation:** When creating an NSG rule, you must specify a priority value between 100 and 4096. There is no default; lower numbers indicate higher priority. Azure system rules use priorities 65000-65500.

---

### Question 114

Which Azure service provides a centralized place to manage and enforce compliance across multiple subscriptions?

- A) Azure Advisor
- B) Microsoft Defender for Cloud
- C) Azure Policy with Management Groups **[CORRECT]**
- D) Azure Monitor

> **Explanation:** Azure Policy combined with Management Groups allows you to create, assign, and manage policies across multiple subscriptions from a centralized location, ensuring organization-wide compliance.

---

### Question 115

You need to create an Azure VM from a generalized image. What must you do to the source VM before capturing the image?

- A) Install the Azure Monitor Agent
- B) Run Sysprep (Windows) or waagent deprovision (Linux) **[CORRECT]**
- C) Remove all data disks
- D) Change the VM size to a smaller SKU

> **Explanation:** Before capturing a generalized image, you must run Sysprep on Windows or waagent -deprovision on Linux to remove machine-specific information, making the image reusable for new VMs.

---

### Question 116

Which Azure Monitor feature visualizes metrics and logs in customizable dashboards and workbooks?

- A) Action Groups
- B) Azure Workbooks **[CORRECT]**
- C) Alert Rules
- D) Diagnostic Settings

> **Explanation:** Azure Workbooks provide flexible canvas for data analysis and rich visual report creation within the Azure portal, combining metrics, logs, and text into interactive reports.

---

### Question 117

You have an Azure subscription with a spending limit. What happens when the spending limit is reached?

- A) Resources are immediately deleted
- B) Resources are deallocated and disabled until the next billing period or limit is removed **[CORRECT]**
- C) Azure automatically increases the limit
- D) Only new deployments are blocked; existing resources continue running

> **Explanation:** When a spending limit is reached, deployed resources are disabled and deallocated. They remain in Azure but are taken offline until the next billing period starts or you remove the spending limit.

---

### Question 118

Which Azure DNS feature allows you to host a private DNS zone that is resolvable only within specified virtual networks?

- A) Azure DNS public zone
- B) Azure Private DNS zone **[CORRECT]**
- C) Azure Traffic Manager
- D) Azure Front Door

> **Explanation:** Azure Private DNS zones provide name resolution for virtual machines within and across virtual networks without exposing DNS records to the internet, supporting auto-registration of VM records.

---

### Question 119

You need to resize an Azure VM to a different size family. What is required?

- A) The VM must be redeployed from scratch
- B) The VM must be deallocated first if the new size is not available on the current hardware cluster **[CORRECT]**
- C) The resource group must be deleted and recreated
- D) A new virtual network is required

> **Explanation:** If the new VM size is available on the current hardware cluster, you can resize without stopping. If not, the VM must be deallocated first so Azure can move it to a cluster that supports the new size.

---

### Question 120

What is the purpose of Azure Storage account access keys?

- A) They encrypt data at rest
- B) They provide full access to the storage account and all its data **[CORRECT]**
- C) They manage RBAC role assignments
- D) They configure network firewall rules

> **Explanation:** Storage account access keys grant full access to the entire storage account. There are two keys to enable rotation without downtime. They should be protected like root passwords.

---

### Question 121

You are configuring a scale set with a custom health probe. The probe checks an HTTP endpoint on port 80. If 3 consecutive probes fail, what happens?

- A) The VM is deallocated
- B) The VM instance is marked as unhealthy and can be automatically repaired or replaced **[CORRECT]**
- C) An alert is sent to the subscription owner
- D) The entire scale set is restarted

> **Explanation:** When health probes fail, the VM instance is marked as unhealthy. With automatic instance repair enabled, unhealthy instances are automatically deleted and replaced with new ones.

---

### Question 122

Which Microsoft Entra ID feature allows you to provide time-limited elevated access to Azure resources?

- A) Conditional Access
- B) Privileged Identity Management (PIM) **[CORRECT]**
- C) Access Reviews
- D) Identity Protection

> **Explanation:** Privileged Identity Management (PIM) provides just-in-time privileged access to Azure resources. Users can activate eligible roles for a limited time, reducing standing admin access.

---

### Question 123

You need to configure an Azure Storage account to only accept requests from a specific virtual network subnet. What should you enable?

- A) Shared Access Signatures
- B) Storage firewall with virtual network rules **[CORRECT]**
- C) Azure AD authentication
- D) Customer-managed encryption keys

> **Explanation:** Storage firewall with virtual network rules restricts storage account access to specific subnets. You configure the firewall to deny all traffic by default and allow only the specified subnet.

---

### Question 124

What is the maximum number of virtual networks that can be peered with a single virtual network?

- A) 10
- B) 50
- C) 100
- D) 500 **[CORRECT]**

> **Explanation:** A single virtual network can have up to 500 peering connections. This limit applies to both local and global VNet peering combined.

---

### Question 125

Which Azure Backup feature protects against accidental deletion of backup data by retaining deleted recovery points for 14 additional days?

- A) Geo-redundant storage
- B) Soft delete for Azure Backup **[CORRECT]**
- C) Immutable vault
- D) Cross-region restore

> **Explanation:** Soft delete for Azure Backup retains deleted backup data for 14 additional days at no cost. This protects against accidental or malicious deletion of backup data.

---

### Question 126

You need to deploy an ARM template that includes a parameters file. Which Azure CLI command should you use?

- A) az group create --template-file main.json
- B) az deployment group create --resource-group myRG --template-file main.json --parameters @params.json **[CORRECT]**
- C) az resource deploy --template main.json --params params.json
- D) az arm deploy --file main.json

> **Explanation:** The 'az deployment group create' command deploys an ARM template to a resource group. Use --template-file for the template and --parameters with @ prefix to reference a parameters file.

---

### Question 127

Which Azure service allows you to run scheduled and on-demand tasks using PowerShell or Python runbooks?

- A) Azure Functions
- B) Azure Automation **[CORRECT]**
- C) Azure Logic Apps
- D) Azure Batch

> **Explanation:** Azure Automation provides a cloud-based automation service with PowerShell and Python runbooks, scheduled execution, and integration with Azure resources for repetitive management tasks.

---

### Question 128

You configure a user-defined route (UDR) with a next hop type of 'Virtual Appliance'. What must you specify?

- A) The Azure region of the appliance
- B) The private IP address of the virtual appliance **[CORRECT]**
- C) The public IP address of the appliance
- D) The MAC address of the appliance

> **Explanation:** When configuring a UDR with 'Virtual Appliance' as the next hop type, you must specify the private IP address of the network virtual appliance (NVA) that will inspect or forward the traffic.

---

### Question 129

You need to convert an Azure VM from unmanaged disks to managed disks. What must you do first?

- A) Create a snapshot of each disk
- B) Stop and deallocate the VM **[CORRECT]**
- C) Delete the storage account
- D) Remove all data disks

> **Explanation:** To convert a VM from unmanaged to managed disks, you must first stop and deallocate the VM. Then use the ConvertTo-AzVMManagedDisk cmdlet or az vm convert CLI command.

---

### Question 130

Which type of Azure Managed Identity is tied to the lifecycle of the resource it is assigned to?

- A) User-assigned managed identity
- B) System-assigned managed identity **[CORRECT]**
- C) Service principal
- D) Application identity

> **Explanation:** A system-assigned managed identity is created and tied to a specific Azure resource. When the resource is deleted, the identity is automatically deleted as well.

---

### Question 131

You need to create an Azure Storage account that supports Azure Data Lake Storage Gen2 hierarchical namespace. Which setting must you enable?

- A) Large file shares
- B) Hierarchical namespace **[CORRECT]**
- C) Blob versioning
- D) Static website hosting

> **Explanation:** To use Azure Data Lake Storage Gen2 features, you must enable the hierarchical namespace on the storage account at creation time. This cannot be enabled after account creation.

---

### Question 132

What is the purpose of Azure Network Watcher?

- A) Deploy and manage virtual networks
- B) Monitor, diagnose, and gain insights into network performance and health **[CORRECT]**
- C) Configure DNS records
- D) Create VPN connections

> **Explanation:** Azure Network Watcher provides network monitoring and diagnostic tools including IP flow verify, next hop analysis, connection troubleshoot, packet capture, and NSG flow logs.

---

### Question 133

You are implementing Azure Disk Encryption for a Windows VM. Which technology does it use?

- A) dm-crypt
- B) BitLocker **[CORRECT]**
- C) TDE
- D) Always Encrypted

> **Explanation:** Azure Disk Encryption for Windows VMs uses BitLocker to provide full volume encryption for the OS and data disks. For Linux VMs, it uses dm-crypt.

---

### Question 134

Which Azure feature allows you to automatically register DNS records for VMs when they are created in a virtual network?

- A) Azure DNS public zone
- B) Azure Private DNS zone with auto-registration **[CORRECT]**
- C) Azure Traffic Manager
- D) Custom DNS server

> **Explanation:** Azure Private DNS zones with auto-registration enabled automatically create DNS A records for VMs when they are deployed in linked virtual networks, simplifying DNS management.

---

### Question 135

You need to configure an Azure Load Balancer health probe. Which protocols are supported?

- A) HTTP and HTTPS only
- B) TCP, HTTP, and HTTPS **[CORRECT]**
- C) TCP and UDP
- D) ICMP only

> **Explanation:** Azure Load Balancer supports TCP, HTTP, and HTTPS health probes. TCP probes check for a successful connection, while HTTP/HTTPS probes check for a 200 OK response from a specified path.

---

### Question 136

What is the effect of setting 'Allow gateway transit' on a VNet peering configuration?

- A) It enables internet access for peered VNets
- B) It allows the peered VNet to use the gateway in this VNet for on-premises connectivity **[CORRECT]**
- C) It creates a new VPN gateway automatically
- D) It blocks all traffic between peered VNets

> **Explanation:** Gateway transit allows a peered virtual network to use the VPN or ExpressRoute gateway in another VNet to connect to on-premises networks, avoiding the need for a gateway in each VNet.

---

### Question 137

Which Azure Monitor log query returns the top 10 computers with the highest average CPU usage over the last hour?

- A) Perf | where TimeGenerated > ago(1h) | where ObjectName == 'Processor' | summarize AvgCPU = avg(CounterValue) by Computer | top 10 by AvgCPU desc **[CORRECT]**
- B) SELECT TOP 10 Computer, AVG(CPU) FROM PerfCounters
- C) Get-AzMetric -ResourceType VM -Metric CPU -Top 10
- D) az monitor metrics list --top 10 --metric cpu

> **Explanation:** This KQL query filters the Perf table for processor metrics in the last hour, calculates average CPU per computer, and returns the top 10 highest-usage computers.

---

### Question 138

You need to restrict which Azure regions resources can be deployed to. Which scope provides the broadest enforcement?

- A) Resource group level
- B) Subscription level
- C) Management group level **[CORRECT]**
- D) Resource level

> **Explanation:** Assigning an Azure Policy at the Management Group level enforces it across all subscriptions and resource groups within that management group, providing the broadest scope of enforcement.

---

### Question 139

Which storage redundancy option replicates data across three availability zones within a single region?

- A) Locally-redundant storage (LRS)
- B) Zone-redundant storage (ZRS) **[CORRECT]**
- C) Geo-redundant storage (GRS)
- D) Read-access geo-redundant storage (RA-GRS)

> **Explanation:** Zone-redundant storage (ZRS) replicates data synchronously across three Azure availability zones in the same region, providing high availability and protection against zone-level failures.

---

### Question 140

You need to configure an Azure VM extension to run a script after VM deployment. Which extension should you use?

- A) Azure Monitor Agent
- B) Custom Script Extension **[CORRECT]**
- C) Desired State Configuration extension
- D) Disk Encryption extension

> **Explanation:** The Custom Script Extension downloads and executes scripts on Azure VMs. It is useful for post-deployment configuration, software installation, or any other configuration task.

---

### Question 141

You have a Microsoft Entra ID group of type 'Dynamic User'. What determines group membership?

- A) Manual assignment by an administrator
- B) Rules based on user attributes that automatically add or remove users **[CORRECT]**
- C) Azure Policy assignments
- D) Subscription-level RBAC roles

> **Explanation:** Dynamic groups use rules based on user properties (department, jobTitle, etc.) to automatically add and remove members. Membership is continuously evaluated as user attributes change.

---

### Question 142

What is the Azure CLI command to create a snapshot of a managed disk?

- A) az disk create --source
- B) az snapshot create --source <disk-id> **[CORRECT]**
- C) az disk snapshot --id <disk-id>
- D) az vm snapshot create --disk <disk-id>

> **Explanation:** The 'az snapshot create' command creates a snapshot of a managed disk. You specify the source disk ID and can optionally set the snapshot SKU (Standard_LRS or Premium_LRS).

---

### Question 143

Which Azure feature allows you to apply a set of policies, RBAC assignments, and ARM templates as a single package for environment setup?

- A) Azure Resource Manager
- B) Azure Blueprints **[CORRECT]**
- C) Azure DevOps
- D) Azure Lighthouse

> **Explanation:** Azure Blueprints packages role assignments, policy assignments, ARM templates, and resource groups into a single definition that can be versioned and repeatedly deployed for environment governance.

---

### Question 144

You are configuring Azure Site Recovery for disaster recovery. Which is the correct order for setting up VM replication?

- A) Create vault, configure replication policy, enable replication, test failover **[CORRECT]**
- B) Enable replication, create vault, test failover, configure policy
- C) Test failover, create vault, enable replication, configure policy
- D) Configure policy, test failover, enable replication, create vault

> **Explanation:** The correct order is: create a Recovery Services vault, configure the replication policy (RPO, retention), enable replication for VMs, then run a test failover to validate the DR plan.

---

### Question 145

What is the maximum number of NSG rules (including default rules) that can be applied to a network interface?

- A) 100
- B) 200
- C) 500
- D) 1000 **[CORRECT]**

> **Explanation:** By default, you can create up to 1000 NSG rules per NSG. This limit includes both inbound and outbound rules. The limit can be increased to 5000 through Azure support.

---

### Question 146

You need to configure Azure App Service to scale based on a schedule. Which scaling option should you use?

- A) Manual scale
- B) Custom autoscale with schedule-based rules **[CORRECT]**
- C) Scale up (vertical scaling)
- D) Azure Functions Premium plan

> **Explanation:** Custom autoscale with schedule-based rules allows you to define scaling profiles that activate on specific dates, days of the week, or time ranges to handle predictable load patterns.

---

### Question 147

Which Azure Storage feature creates automatic point-in-time snapshots of blobs to protect against accidental modifications?

- A) Soft delete
- B) Blob versioning **[CORRECT]**
- C) Immutability policies
- D) Object replication

> **Explanation:** Blob versioning automatically creates a new version whenever a blob is modified or deleted. Previous versions are preserved and can be restored, providing protection against accidental changes.

---

### Question 148

You need to connect two Azure virtual networks that have overlapping IP address spaces. Which solution should you use?

- A) VNet peering
- B) NAT Gateway with Virtual Network Gateway
- C) VNet peering is not possible; you must re-address one VNet **[CORRECT]**
- D) Azure Front Door

> **Explanation:** VNet peering requires non-overlapping IP address spaces. If two VNets have overlapping address ranges, you must re-address one of them before peering can be established.

---

### Question 149

What is the purpose of Azure Diagnostic Settings on a resource?

- A) Configure RBAC for the resource
- B) Route platform logs and metrics to Log Analytics, Storage, or Event Hubs **[CORRECT]**
- C) Set up backup policies
- D) Enable encryption at rest

> **Explanation:** Diagnostic Settings configure where platform logs (activity, resource, and metrics) are sent. Destinations include Log Analytics workspaces, Storage accounts, Event Hubs, or partner solutions.

---

### Question 150

You have a Recovery Services vault with immutability enabled. What does this prevent?

- A) New backup jobs from running
- B) Deletion or reduction of retention periods for backup data **[CORRECT]**
- C) Cross-region restore operations
- D) Adding new VMs to the backup policy

> **Explanation:** Immutability for Recovery Services vaults prevents deletion of backup data and reduction of retention periods, protecting against ransomware attacks and malicious administrators.

---

_Generated from [Azure Mastery Learning Platform](https://www.azurekt.com/az-104)_
_Study smarter. Pass faster._
