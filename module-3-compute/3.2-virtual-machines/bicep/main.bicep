/*=====================================================
SUMMARY: Lab 3.2 - Virtual Machines Orchestrator
DESCRIPTION: Orchestrates deployment of VMs, NICs, Disks, and Key Vault for SkyCraft Lab 3.2
EXAMPLE: az deployment sub create --location swedencentral --template-file main.bicep --parameters parEnvironment=dev parSshPublicKey="ssh-rsa ..."
AUTHOR/S: Marcin Biszczanik
VERSION: 1.0.0
DEPLOYMENT: .\scripts\Deploy-Bicep.ps1
======================================================*/

targetScope = 'subscription'

// ============================================================================
// PARAMETERS
// ============================================================================

@description('Azure region for resource deployment')
@allowed(['swedencentral', 'westeurope', 'northeurope'])
param parLocation string = 'swedencentral'

@description('Environment name')
@allowed(['dev', 'prod'])
param parEnvironment string

@description('Project name for resource naming')
param parProject string = 'skycraft'

@description('Service/workload name')
param parService string = 'swc'

@description('Cost center for billing')
param parCostCenter string = 'MSDN'

@description('SSH public key for VM authentication')
@secure()
param parSshPublicKey string

@description('VM size for development VMs')
@allowed([
  'Standard_B1s'
  'Standard_B2s'
  'Standard_B2ms'
  'Standard_D2s_v3'
])
param parVmSize string = 'Standard_B2s'

@description('Encryption strategy for VMs')
@allowed([
  'None'
  'EncryptionAtHost'
  'AzureDiskEncryption'
])
param parEncryptionStrategy string = 'None'

@description('Worldserver data disk size in GB')
param parDataDiskSizeGB int = 64

@description('Deployment timestamp (auto-generated)')
param parCurrentDate string = utcNow('yyyy-MM-dd')

// ============================================================================
// VARIABLES
// ============================================================================

var varLocationShortCode = 'swc' // Sweden Central
var varCommonTags = {
  Project: parProject
  Service: parService
  CostCenter: parCostCenter
  ManagedBy: 'Bicep'
  DeploymentDate: parCurrentDate
}

// Resource group name (uses existing from Lab 3.1)
var varDevRgName = '${parEnvironment}-${parProject}-${varLocationShortCode}-rg'

// Resource naming
var varNamePrefix = '${parEnvironment}-${parProject}-${varLocationShortCode}'
var varDevVnetName = '${varNamePrefix}-vnet'

// Key Vault name must be globally unique (add random suffix based on subscription)
var varKeyVaultName = '${varNamePrefix}-kv'

// ============================================================================
// EXISTING RESOURCES (from Lab 3.1)
// ============================================================================

resource resDevRg 'Microsoft.Resources/resourceGroups@2023-07-01' existing = {
  name: varDevRgName
}

// ============================================================================
// KEY VAULT (for Azure Disk Encryption)
// ============================================================================

module modKeyVault 'modules/keyvault.bicep' = if (parEncryptionStrategy == 'AzureDiskEncryption') {
  name: 'keyVaultDeployment'
  scope: resDevRg
  params: {
    parKeyVaultName: varKeyVaultName
    parLocation: parLocation
    parEnabledForDiskEncryption: true
    parEnabledForDeployment: true
    parTags: union(varCommonTags, {
      Environment: parEnvironment == 'dev' ? 'Development' : 'Production'
      Purpose: 'DiskEncryption'
    })
  }
}

// ============================================================================
// NETWORK INTERFACES
// ============================================================================

// Get subnet IDs from existing VNet
resource resDevVnet 'Microsoft.Network/virtualNetworks@2023-05-01' existing = {
  name: varDevVnetName
  scope: resDevRg
}

// Get Load Balancer for backend pool association
resource resDevLb 'Microsoft.Network/loadBalancers@2023-05-01' existing = {
  name: '${varNamePrefix}-lb'
  scope: resDevRg
}

module modAuthNic 'modules/nic.bicep' = {
  name: 'authNicDeployment'
  scope: resDevRg
  params: {
    parNicName: '${varNamePrefix}-auth-nic'
    parLocation: parLocation
    parSubnetId: '${resDevVnet.id}/subnets/AuthSubnet'
    parLoadBalancerBackendPoolIds: [
      '${resDevLb.id}/backendAddressPools/${varNamePrefix}-lb-be-auth'
    ]
    parTags: union(varCommonTags, {
      Environment: parEnvironment == 'dev' ? 'Development' : 'Production'
      Purpose: 'AuthServer'
    })
  }
}

module modWorldNic 'modules/nic.bicep' = {
  name: 'worldNicDeployment'
  scope: resDevRg
  params: {
    parNicName: '${varNamePrefix}-world-nic'
    parLocation: parLocation
    parSubnetId: '${resDevVnet.id}/subnets/WorldSubnet'
    parLoadBalancerBackendPoolIds: [
      '${resDevLb.id}/backendAddressPools/${varNamePrefix}-lb-be-world'
    ]
    parTags: union(varCommonTags, {
      Environment: parEnvironment == 'dev' ? 'Development' : 'Production'
      Purpose: 'WorldServer'
    })
  }
}

// ============================================================================
// DATA DISK (for Worldserver database)
// ============================================================================

module modWorldDataDisk 'modules/disk.bicep' = {
  name: 'worldDataDiskDeployment'
  scope: resDevRg
  params: {
    parDiskName: '${varNamePrefix}-world-datadisk'
    parLocation: parLocation
    parDiskSizeGB: parDataDiskSizeGB
    parDiskSku: 'StandardSSD_LRS'
    parAvailabilityZone: '2' // Same zone as World VM
    parTags: union(varCommonTags, {
      Environment: parEnvironment == 'dev' ? 'Development' : 'Production'
      Purpose: 'WorldServerDatabase'
    })
  }
}

// ============================================================================
// VIRTUAL MACHINES
// ============================================================================

module modAuthVm 'modules/vm.bicep' = {
  name: 'authVmDeployment'
  scope: resDevRg
  params: {
    parVmName: '${varNamePrefix}-auth-vm'
    parLocation: parLocation
    parVmSize: parVmSize
    parAvailabilityZone: '1'
    parSshPublicKey: parSshPublicKey
    parNicId: modAuthNic.outputs.outNicId
    parEncryptionStrategy: parEncryptionStrategy
    parTags: union(varCommonTags, {
      Environment: parEnvironment == 'dev' ? 'Development' : 'Production'
      Purpose: 'AuthServer'
      Port: '3724'
    })
  }
}

module modWorldVm 'modules/vm.bicep' = {
  name: 'worldVmDeployment'
  scope: resDevRg
  params: {
    parVmName: '${varNamePrefix}-world-vm'
    parLocation: parLocation
    parVmSize: parVmSize
    parAvailabilityZone: '2'
    parSshPublicKey: parSshPublicKey
    parNicId: modWorldNic.outputs.outNicId
    parDataDiskIds: [
      modWorldDataDisk.outputs.outDiskId
    ]
    parEncryptionStrategy: parEncryptionStrategy
    parTags: union(varCommonTags, {
      Environment: parEnvironment == 'dev' ? 'Development' : 'Production'
      Purpose: 'WorldServer'
      Port: '8085'
    })
  }
}

// ============================================================================
// OUTPUTS
// ============================================================================

output outResourceGroupName string = resDevRg.name

output outAuthVmId string = modAuthVm.outputs.outVmId
output outAuthVmName string = modAuthVm.outputs.outVmName
output outWorldVmId string = modWorldVm.outputs.outVmId
output outWorldVmName string = modWorldVm.outputs.outVmName

output outAuthNicPrivateIp string = modAuthNic.outputs.outPrivateIpAddress
output outWorldNicPrivateIp string = modWorldNic.outputs.outPrivateIpAddress

output outWorldDataDiskId string = modWorldDataDisk.outputs.outDiskId

output outKeyVaultName string = parEncryptionStrategy == 'AzureDiskEncryption' ? modKeyVault!.outputs.outKeyVaultName : 'N/A - ADE not enabled'
output outEncryptionStrategy string = parEncryptionStrategy
