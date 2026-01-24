# Module 3: Deploy and Manage Azure Compute Resources

## 🎯 Module Overview

In **Module 3: Compute**, we will deploy the core application infrastructure for SkyCraft. Building upon the networking foundation from Module 2, we will provision Linux Virtual Machines to host the game servers (Auth and World), explore containerization options, and deploy a web-based management dashboard.

This module focuses on **Azure Compute** resources, Infrastructure as Code (IaC) automation, and high-availability configurations.

## 📚 Learning Objectives

- **Automate Deployment**: Use Bicep to define and deploy complete infrastructure stacks.
- **Virtual Machines**: Deploy, configure, and manage Linux VMs for mission-critical workloads.
- **High Availability**: Implement Availability Zones and Scale Sets.
- **Containers**: Provision Azure Container Instances (ACI) and Container Registries (ACR).
- **App Service**: Deploy web applications using Azure App Service.

## 🛠️ Labs

| Lab     | Title                                                            | Description                                          | Est. Time |
| :------ | :--------------------------------------------------------------- | :--------------------------------------------------- | :-------- |
| **3.1** | [Infrastructure as Code](./3.1-infrastructure-as-code/README.md) | Automate deployments using Bicep templates.          | 3 hours   |
| **3.2** | [Virtual Machines](./3.2-virtual-machines/README.md)             | Deploy and configure Linux VMs for SkyCraft servers. | 4 hours   |
| **3.3** | [Containers](./3.3-containers/README.md)                         | (Optional) Deploy game services using containers.    | 2 hours   |
| **3.4** | [App Service](./3.4-app-service/README.md)                       | Deploy a web dashboard for server management.        | 1 hour    |

## ✅ Prerequisites

- Completed **Module 2: Networking** (VNets, NSGs, Peering active).
- Active Azure Subscription.
- Azure CLI and Bicep CLI installed.

---

[← Back to Main Index](../README.md) | [Next: Lab 3.1 - Infrastructure as Code →](./3.1-infrastructure-as-code/README.md)
