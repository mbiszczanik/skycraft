# Lab 3.1 Completion Checklist

## ✅ Infrastructure as Code Setup Verification

### Bicep Tools Installation
- [ ] Bicep CLI installed and verified
  - Command used: `az bicep version`
  - Version installed: [Record version: ____________]

- [ ] VS Code installed
- [ ] VS Code Bicep extension installed by Microsoft
- [ ] IntelliSense working in .bicep files (tested with autocomplete)

### Understanding IaC Concepts
- [ ] Understand benefits: Repeatability, version control, speed, testing
- [ ] Know difference between ARM templates (JSON) and Bicep (DSL)
- [ ] Understand Bicep workflow: Bicep → transpile → ARM → Azure
- [ ] Can explain declarative vs imperative infrastructure code

---

## ✅ ARM Template Export and Analysis

### Exported ARM Template
- [ ] Exported existing resource group as ARM template
  - Resource group exported: [Name: ____________]
  - Export date: [Date: ____________]
  - Template size: [Lines/KB: ____________]

### ARM Template Components Identified
- [ ] Located `parameters` section in template
- [ ] Located `variables` section in template
- [ ] Located `resources` array in template
- [ ] Located `outputs` section in template
- [ ] Identified at least 3 ARM template functions (concat, resourceId, etc.)

### ARM Template Functions Understood
- [ ] `parameters()` function
- [ ] `variables()` function
- [ ] `resourceId()` function
- [ ] `resourceGroup()` function
- [ ] `concat()` or string interpolation

---

## ✅ Bicep Files Created

### Core Bicep Files
- [ ] **first-resource.bicep** created
  - Contains: Parameter, variable, resource, output
  - Resource type: [Type: ____________]
  - Successfully built with `az bicep build`

- [ ] **main.bicep** created
  - Target scope: `subscription`
  - Creates 3 resource groups (platform, dev, prod)
  - References modules
  - File size: [Record lines: ____________]

### Bicep Parameter Files
- [ ] **dev.bicepparam** created
  - Contains `using './main.bicep'` statement
  - Development-specific parameters defined
  - Location: `swedencentral`
  - Environment: `dev`

- [ ] **prod.bicepparam** created
  - Contains `using './main.bicep'` statement
  - Production-specific parameters defined
  - Larger VM sizes than dev (if applicable)

---

## ✅ Bicep Modules Created

### modules/network.bicep
- [ ] File created at `modules/network.bicep`
- [ ] Parameters defined:
  - [ ] `namePrefix` (string)
  - [ ] `location` (string with default)
  - [ ] `environment` (string with @allowed decorator)
  - [ ] `vnetAddressPrefix` (string)
  - [ ] `subnets` (array)
  - [ ] `tags` (object)

- [ ] Resource created: `Microsoft.Network/virtualNetworks`
- [ ] Subnets created using `for` loop
- [ ] Outputs defined: `vnetId`, `vnetName`, `subnets` array

### modules/nsg.bicep
- [ ] File created at `modules/nsg.bicep`
- [ ] Parameters defined:
  - [ ] `nsgName` (string)
  - [ ] `location` (string with default)
  - [ ] `securityRules` (array)
  - [ ] `tags` (object)

- [ ] Resource created: `Microsoft.Network/networkSecurityGroups`
- [ ] Security rules created using `for` loop
- [ ] Outputs defined: `nsgId`, `nsgName`

### modules/loadbalancer.bicep
- [ ] File created at `modules/loadbalancer.bicep`
- [ ] Parameters defined:
  - [ ] `namePrefix` (string)
  - [ ] `location` (string with default)
  - [ ] `publicIpId` (string)
  - [ ] `backendPools` (array)
  - [ ] `healthProbes` (array)
  - [ ] `lbRules` (array)
  - [ ] `tags` (object)

- [ ] Load balancer SKU: `Standard`
- [ ] Frontend IP configuration defined
- [ ] Backend pools created using `for` loop
- [ ] Health probes created using `for` loop
- [ ] Load balancing rules created using `for` loop
- [ ] Outputs defined: `loadBalancerId`, `loadBalancerName`, `backendPoolIds`

### modules/publicip.bicep
- [ ] File created at `modules/publicip.bicep`
- [ ] Parameters defined:
  - [ ] `publicIpName` (string)
  - [ ] `location` (string with default)
  - [ ] `sku` (string with @allowed)
  - [ ] `allocationMethod` (string with @allowed)
  - [ ] `tags` (object)

- [ ] Resource created: `Microsoft.Network/publicIPAddresses`
- [ ] SKU: `Standard`
- [ ] Allocation method: `Static`
- [ ] Outputs defined: `publicIpId`, `publicIpName`, `ipAddress`

---

## ✅ ARM to Bicep Conversion

### Decompilation Process
- [ ] Decompiled ARM template using `az bicep decompile --file template.json`
- [ ] Decompiled file created: `template.bicep`
- [ ] Reviewed decompiled Bicep for issues
  - [ ] Long parameter names identified
  - [ ] Hardcoded values identified
  - [ ] Missing descriptions identified

### Bicep Cleanup Applied
- [ ] Shortened parameter names (e.g., `virtualNetworks_dev_name` → `vnetName`)
- [ ] Added `@description()` decorators to parameters
- [ ] Added `@allowed()` decorators where appropriate
- [ ] Extracted hardcoded values to parameters
- [ ] Added outputs for important resource IDs
- [ ] Tested cleaned Bicep with `az bicep build`

---

## ✅ Template Validation and Deployment

### Bicep Build Validation
- [ ] Successfully built main.bicep: `az bicep build --file main.bicep`
  - Output file created: `main.json` (ARM template)
  - No errors or warnings

- [ ] Verified ARM template is valid JSON
- [ ] Reviewed transpiled ARM template structure

### Template Validation
- [ ] Validated deployment without deploying:
  ```bash
  az deployment sub validate     --location swedencentral     --template-file main.bicep     --parameters dev.bicepparam
  ```
  - Validation result: [✅ Success / ❌ Failed]
  - Validation date/time: [Record: ____________]

### What-If Analysis
- [ ] Ran what-if analysis:
  ```bash
  az deployment sub what-if     --location swedencentral     --template-file main.bicep     --parameters dev.bicepparam
  ```
  - Resources to create: [Number: ______]
  - Resources to modify: [Number: ______]
  - Resources to delete: [Number: ______]

- [ ] Reviewed what-if output carefully
- [ ] No unexpected deletions or modifications
- [ ] Confirmed changes match expectations

### Deployment Execution
- [ ] Deployed Bicep template successfully:
  ```bash
  az deployment sub create     --name "SkyCraft-Dev-YYYYMMDD-HHMMSS"     --location swedencentral     --template-file main.bicep     --parameters dev.bicepparam
  ```
  - Deployment name: [Record: ____________]
  - Deployment start time: [Record: ____________]
  - Deployment duration: [Record: ______ minutes]
  - Deployment state: [✅ Succeeded / ❌ Failed]

---

## ✅ Deployed Resources Verification

### Resource Groups Created
- [ ] **platform-skycraft-swc-rg**
  - Location: `swedencentral`
  - Tags: Project=SkyCraft, Environment=Platform, CostCenter=MSDN
  - Provisioning state: Succeeded

- [ ] **dev-skycraft-swc-rg**
  - Location: `swedencentral`
  - Tags: Project=SkyCraft, Environment=Development, CostCenter=MSDN
  - Provisioning state: Succeeded

- [ ] **prod-skycraft-swc-rg** (if deployed)
  - Location: `swedencentral`
  - Tags: Project=SkyCraft, Environment=Production, CostCenter=MSDN
  - Provisioning state: Succeeded

### Network Resources in Dev
- [ ] VNet: `dev-skycraft-swc-vnet`
  - Address space: `10.1.0.0/16`
  - Number of subnets: [Record: ______]
  - Provisioning state: Succeeded

- [ ] NSG: `auth-nsg`
  - Number of security rules: [Record: ______]
  - Associated to subnet: [Yes/No]

- [ ] NSG: `world-nsg`
  - Number of security rules: [Record: ______]
  - Associated to subnet: [Yes/No]

### Load Balancer Resources in Dev
- [ ] Public IP: `dev-skycraft-swc-lb-pip`
  - SKU: `Standard`
  - Allocation: `Static`
  - IP address: [Record IP: ____________]

- [ ] Load Balancer: `dev-skycraft-swc-lb`
  - SKU: `Standard`
  - Frontend IP configurations: 1
  - Backend pools: [Record: ______]
  - Health probes: [Record: ______]
  - Load balancing rules: [Record: ______]

### Deployment Outputs
- [ ] Retrieved deployment outputs successfully
- [ ] Documented output values:
  - `platformResourceGroupName`: [____________]
  - `devResourceGroupName`: [____________]
  - `hubVnetId`: [____________]
  - `devVnetId`: [____________]
  - `devLoadBalancerId`: [____________]
  - `devLoadBalancerPublicIp`: [____________]

---

## 🔍 Validation Commands

Run these commands and document the results:

### Bicep CLI Validation

```bash
# Verify Bicep CLI version
az bicep version

# Expected output: Bicep CLI version 0.24.24 (or later)
# Your version: ________________
```

```bash
# Build Bicep to ARM
az bicep build --file main.bicep

# Expected output: "Build succeeded"
# Result: ________________
```

```bash
# List all Bicep files in directory
find . -name "*.bicep" -type f

# Expected files:
# ./main.bicep
# ./first-resource.bicep
# ./modules/network.bicep
# ./modules/nsg.bicep
# ./modules/loadbalancer.bicep
# ./modules/publicip.bicep

# Your files: ________________
```

### Deployment Validation

```bash
# List subscription deployments
az deployment sub list   --query "[?contains(name, 'SkyCraft')].{Name:name,State:properties.provisioningState,Timestamp:properties.timestamp}"   --output table

# Expected output: At least one SkyCraft deployment with Succeeded state
```

```bash
# Show specific deployment details
az deployment sub show   --name "YOUR-DEPLOYMENT-NAME"   --query "{Name:name,State:properties.provisioningState,Duration:properties.duration,ResourceGroups:properties.outputResources[?type=='Microsoft.Resources/resourceGroups'].id}"   --output json

# Document your deployment name: ________________
```

### Resource Group Validation

```bash
# List all SkyCraft resource groups
az group list   --query "[?contains(name, 'skycraft')].{Name:name,Location:location,State:properties.provisioningState,Tags:tags}"   --output table

# Expected output: 3 resource groups (platform, dev, prod)
# Your count: ________________
```

### Network Resources Validation

```bash
# List VNets in dev resource group
az network vnet list   --resource-group dev-skycraft-swc-rg   --query "[].{Name:name,AddressSpace:addressSpace.addressPrefixes[0],Subnets:length(subnets),State:provisioningState}"   --output table

# Expected output: 1 VNet with 3 subnets
# Your result: ________________
```

```bash
# List NSGs in dev resource group
az network nsg list   --resource-group dev-skycraft-swc-rg   --query "[].{Name:name,Rules:length(securityRules),Location:location}"   --output table

# Expected output: 2-3 NSGs with configured rules
# Your result: ________________
```

```bash
# List load balancers
az network lb list   --resource-group dev-skycraft-swc-rg   --query "[].{Name:name,SKU:sku.name,BackendPools:length(backendAddressPools),Probes:length(probes),Rules:length(loadBalancingRules)}"   --output table

# Expected output: 1 load balancer (Standard SKU) with 2 backend pools, 2 probes, 2 rules
# Your result: ________________
```

### Bicep Module Validation

```bash
# Validate network module independently
az bicep build --file modules/network.bicep

# Result: ________________
```

```bash
# Validate NSG module independently
az bicep build --file modules/nsg.bicep

# Result: ________________
```

```bash
# Validate load balancer module independently
az bicep build --file modules/loadbalancer.bicep

# Result: ________________
```

---

## 📊 Infrastructure as Code Architecture Summary

Document your IaC architecture:

| Component | File Name | Purpose | Status |
|-----------|-----------|---------|--------|
| **Main Template** | main.bicep | Orchestrates all deployments | ✅ |
| **Dev Parameters** | dev.bicepparam | Development environment params | ✅ |
| **Prod Parameters** | prod.bicepparam | Production environment params | ✅ |
| **Network Module** | modules/network.bicep | Reusable VNet creation | ✅ |
| **NSG Module** | modules/nsg.bicep | Reusable NSG with rules | ✅ |
| **Load Balancer Module** | modules/loadbalancer.bicep | Reusable LB configuration | ✅ |
| **Public IP Module** | modules/publicip.bicep | Reusable public IP | ✅ |
| **ARM Template** | main.json | Transpiled ARM (generated) | ✅ |

---

## 📊 Deployment Summary Table

| Deployment Metric | Value |
|-------------------|-------|
| **Total Bicep Files** | ______ |
| **Total Modules** | ______ |
| **Resource Groups Deployed** | ______ |
| **VNets Deployed** | ______ |
| **NSGs Deployed** | ______ |
| **Load Balancers Deployed** | ______ |
| **Public IPs Deployed** | ______ |
| **Total Deployment Time** | ______ minutes |
| **Manual Deployment Time (estimated)** | ~180 minutes |
| **Time Saved** | ______ minutes (______%) |

---

## 📝 Reflection Questions

Answer these questions to document your hands-on experience:

### Question 1: Bicep Module Benefits
**Describe a specific example where using a Bicep module saved you time or prevented errors in this lab:**

_________________________________________________________________

_________________________________________________________________

_________________________________________________________________

**How would you modify the network module to support a different address space?**

_________________________________________________________________

_________________________________________________________________

### Question 2: What-If Analysis Experience
**Document what the what-if analysis showed before your deployment:**

Resources to create:
_________________________________________________________________

Resources to modify:
_________________________________________________________________

Resources to delete:
_________________________________________________________________

**Did anything in the what-if output surprise you? If so, what?**

_________________________________________________________________

_________________________________________________________________

### Question 3: ARM Template vs Bicep Comparison
**Choose one resource from your exported ARM template. Document the difference:**

**ARM Template (JSON) - Number of lines:** ______

**Bicep Equivalent - Number of lines:** ______

**Which was easier to read and understand? Why?**

_________________________________________________________________

_________________________________________________________________

### Question 4: Parameterization Strategy
**You created dev.bicepparam and prod.bicepparam. List 3 parameters where the values differ between dev and prod:**

| Parameter Name | Dev Value | Prod Value | Reason for Difference |
|----------------|-----------|------------|----------------------|
| 1. ____________ | _________ | _________ | __________________ |
| 2. ____________ | _________ | _________ | __________________ |
| 3. ____________ | _________ | _________ | __________________ |

### Question 5: Troubleshooting Experience
**Did you encounter any errors during this lab? If yes, describe the error and how you resolved it:**

Error encountered:
_________________________________________________________________

_________________________________________________________________

Solution applied:
_________________________________________________________________

_________________________________________________________________

**If no errors, describe what you would do if deployment failed with "Template validation failed":**

_________________________________________________________________

_________________________________________________________________

### Question 6: Multi-Region Deployment Planning
**You currently deploy to Sweden Central. Plan how you would deploy the same infrastructure to West Europe:**

Approach (parameter file / script / Bicep loop):
_________________________________________________________________

_________________________________________________________________

Files to create or modify:
_________________________________________________________________

_________________________________________________________________

Deployment command:
_________________________________________________________________

### Question 7: Version Control Integration
**How would you use Git to manage these Bicep templates in a team environment?**

Branching strategy:
_________________________________________________________________

_________________________________________________________________

Files to commit to Git:
_________________________________________________________________

Files to exclude (.gitignore):
_________________________________________________________________

Code review process:
_________________________________________________________________

_________________________________________________________________

**Instructor Review Date**: _________  
**Feedback**: 

_________________________________________________________________

_________________________________________________________________

---

## ⏱️ Completion Tracking

- **Estimated Time**: 3 hours
- **Actual Time Spent**: _________ hours
- **Date Started**: _________
- **Date Completed**: _________

**Challenges Encountered**:

_________________________________________________________________

_________________________________________________________________

_________________________________________________________________

**Most Valuable Learning**:

_________________________________________________________________

_________________________________________________________________

**Questions for Instructor**:

_________________________________________________________________

_________________________________________________________________

---

## ✅ Final Lab 3.1 Sign-off

**All Verification Items Complete**:
- [ ] Bicep CLI and VS Code extension installed and working
- [ ] Exported and analyzed ARM template from existing resources
- [ ] Created first-resource.bicep successfully
- [ ] Created 4 Bicep modules (network, NSG, load balancer, public IP)
- [ ] Created main.bicep orchestrator with subscription scope
- [ ] Created parameter files for dev and prod environments
- [ ] Successfully built Bicep to ARM with `az bicep build`
- [ ] Validated template with `az deployment sub validate`
- [ ] Previewed changes with what-if analysis
- [ ] Deployed infrastructure using Bicep template
- [ ] Verified all resources created successfully
- [ ] Retrieved and documented deployment outputs
- [ ] All reflection questions answered
- [ ] Understand IaC benefits and workflow
- [ ] Can modify and parameterize Bicep files
- [ ] Ready to proceed to Lab 3.2 (Deploy VMs)

**Student Name**: _________________  
**Lab 3.1 Completion Date**: _________________  
**Instructor Signature**: _________________

---

## 🎉 Congratulations!

You've successfully completed **Lab 3.1: Automate Deployment Using ARM/Bicep**!

**What You Built**:
- ✅ Complete Infrastructure as Code solution using Bicep
- ✅ 4 reusable Bicep modules for network components
- ✅ Main orchestrator template with multi-resource group deployment
- ✅ Parameter files for environment-specific configurations
- ✅ Automated deployment pipeline replacing 3-hour manual process

**Skills Gained**:
- 🎯 Infrastructure as Code principles and benefits
- 🎯 ARM template interpretation and analysis
- 🎯 Bicep language proficiency (parameters, variables, resources, outputs)
- 🎯 Module-based architecture design
- 🎯 Template validation and what-if analysis
- 🎯 Multi-scope deployments (subscription and resource group)
- 🎯 Deployment automation and verification

**Infrastructure as Code Benefits Realized**:
- 🚀 **Speed**: 15-minute deployment vs 180-minute manual process (90% time savings)
- 🔁 **Repeatability**: Identical environments every deployment
- 📝 **Documentation**: Infrastructure configuration in code
- 🔍 **Version Control**: Infrastructure changes tracked in Git
- 🧪 **Testing**: What-if preview before deployment
- 🤝 **Collaboration**: Team code reviews for infrastructure
- 🔄 **Disaster Recovery**: One-command infrastructure rebuild

**Real-World Impact**:
- Development team can spin up test environments in minutes
- Configuration drift eliminated (dev and prod match exactly)
- Infrastructure changes reviewed like application code
- Disaster recovery time reduced from days to minutes
- New team members onboard faster with documented IaC

**Next Steps**: In **Lab 3.2: Deploy Virtual Machines**, you'll:
- Extend main.bicep to include VM resources
- Create compute module for VM deployment
- Configure VM extensions for automation
- Deploy Linux VMs for AzerothCore game servers
- Add VMs to load balancer backend pools
- Implement SSH key authentication

**Preview - VM Module You'll Create**:
```bicep
// modules/vm.bicep
param vmName string
param vmSize string
param subnetId string
param sshPublicKey string

resource vm 'Microsoft.Compute/virtualMachines@2023-09-01' = {
  name: vmName
  location: location
  properties: {
    hardwareProfile: { vmSize: vmSize }
    osProfile: {
      computerName: vmName
      adminUsername: 'azureuser'
      linuxConfiguration: {
        ssh: {
          publicKeys: [{
            path: '/home/azureuser/.ssh/authorized_keys'
            keyData: sshPublicKey
          }]
        }
      }
    }
  }
}
```

---

## 📌 Module Navigation

- [← Back to Module 3 Index](../README.md)
- [← Previous Module: Module 2 Virtual Networking](../../module-2-networking/README.md)
- [Lab Guide: 3.1 Automate Deployment →](lab-guide-3.1.md)
- [Next Lab: 3.2 Deploy Virtual Machines →](../3.2-deploy-vms/README.md)

---

**Time Investment**: 3 hours  
**Time Saved (future deployments)**: 2.5 hours per environment  
**ROI**: Pays for itself after 2 deployments ✅

*Remember: Infrastructure as Code is not just about automation—it's about treating infrastructure with the same rigor as application code. Version control, testing, code review, and continuous improvement all apply to infrastructure now!*
