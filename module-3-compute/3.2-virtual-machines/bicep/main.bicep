/*=====================================================
SUMMARY: Lab 3.2 - Virtual Machines Orchestrator
DESCRIPTION: Deploys the Auth and World Linux VMs (NICs via the AVM VM module, in the Lab 2.2 ASGs in dev), the World data disk and the Key Vault for Azure Disk Encryption into the Lab 3.1 network, via Azure Verified Modules. Deploy-Bicep.ps1 then encrypts the Auth VM only (Enable-Encryption.ps1, #368). The scale set of Steps 3.2.29-3.2.33 is a Portal exercise the guide deletes again, so the template does not create it.
EXAMPLE: .\scripts\Deploy-Bicep.ps1 -Environment dev -SshKeyPath $HOME\.ssh\skycraft-dev.pub
AUTHOR/S: Marcin Biszczanik
VERSION: 1.3.0
DEPLOYMENT: .\scripts\Deploy-Bicep.ps1
======================================================*/

targetScope = 'subscription'

/*******************
*    Parameters    *
*******************/

@description('Azure region for resource deployment')
@allowed(['swedencentral', 'northeurope'])
param parLocation string = 'swedencentral'

@description('Environment name (selects the Lab 3.1 resource group, VNet and load balancer)')
@allowed(['dev', 'prod'])
param parEnvironment string

@description('Project name used in resource names (lowercase)')
@minLength(2)
@maxLength(12)
param parProject string = 'skycraft'

@description('Resource owner tag value')
@minLength(1)
param parOwner string = 'mbiszczanik'

@description('SSH public key for VM authentication')
@secure()
param parSshPublicKey string

@description('Admin username for SSH access')
@minLength(1)
@maxLength(32)
param parAdminUsername string = 'azureuser'

@description('VM size (B-series v2 - v1 is not available in Sweden Central on this subscription; 4 GB sizes are resized for Azure Disk Encryption by Enable-Encryption.ps1)')
@allowed([
  'Standard_B2ls_v2'
  'Standard_B2als_v2'
  'Standard_B2s_v2'
  'Standard_B2as_v2'
  'Standard_D2s_v3'
  'Standard_D4s_v3'
])
param parVmSize string = 'Standard_B2ls_v2'

@description('Encryption strategy for VMs. AzureDiskEncryption (the guide\'s end state) creates the Key Vault; Enable-Encryption.ps1 then encrypts the Auth VM only.')
@allowed([
  'None'
  'EncryptionAtHost'
  'AzureDiskEncryption'
])
param parEncryptionStrategy string = 'AzureDiskEncryption'

@description('Key Vault name (globally unique; pass another one when the default is taken)')
@minLength(3)
@maxLength(24)
param parKeyVaultName string = '${parEnvironment}-${parProject}-swc-kv'

@description('Worldserver data disk size in GB')
@minValue(4)
@maxValue(32767)
param parDataDiskSizeGB int = 64

@description('Availability zone for the Auth VM (-1 = let Azure choose)')
@allowed([-1, 1, 2, 3])
param parAvailabilityZoneAuth int = 1

@description('Availability zone for the World VM and its data disk (-1 = let Azure choose)')
@allowed([-1, 1, 2, 3])
param parAvailabilityZoneWorld int = 2

/*******************
*    Variables     *
*******************/

var varLocationShortCode = 'swc' // Sweden Central
var varNamePrefix = '${parEnvironment}-${parProject}-${varLocationShortCode}'
var varResourceGroupName = '${varNamePrefix}-rg'
var varVnetName = '${varNamePrefix}-vnet'
var varLbName = '${varNamePrefix}-lb'
// Lab 2.2 creates the ASGs in dev only.
var varUseAsgs = parEnvironment == 'dev'

var varEnvironmentTag = parEnvironment == 'dev' ? 'Development' : 'Production'
var varCommonTags = {
  Project: 'SkyCraft'
  Environment: varEnvironmentTag
  CostCenter: 'MSDN'
  Owner: parOwner
}

// Ubuntu 22.04 LTS Gen2, pinned: 22.04.202506200 boots kernel 6.8.0-1030-azure, which every Azure
// Site Recovery agent listed supports. 'latest' booted 6.8.0-1065-azure and Lab 5.2's replication
// failed with ASRMobilityServiceKernelNotSupportedV2 (issue #366, decision 2026-10-28).
var varImageReference = {
  publisher: 'Canonical'
  offer: '0001-com-ubuntu-server-jammy'
  sku: '22_04-lts-gen2'
  version: '22.04.202506200'
}

/*******************
*     Existing     *
*******************/

// Lab 3.1 (or Labs 1.2 + 2.1/2.3) resources
resource resRg 'Microsoft.Resources/resourceGroups@2023-07-01' existing = {
  name: varResourceGroupName
}

resource resSubnetAuth 'Microsoft.Network/virtualNetworks/subnets@2023-11-01' existing = {
  name: '${varVnetName}/AuthSubnet'
  scope: resRg
}

resource resSubnetWorld 'Microsoft.Network/virtualNetworks/subnets@2023-11-01' existing = {
  name: '${varVnetName}/WorldSubnet'
  scope: resRg
}

resource resLbPoolAuth 'Microsoft.Network/loadBalancers/backendAddressPools@2023-11-01' existing = {
  name: '${varLbName}/${varLbName}-be-auth'
  scope: resRg
}

resource resLbPoolWorld 'Microsoft.Network/loadBalancers/backendAddressPools@2023-11-01' existing = {
  name: '${varLbName}/${varLbName}-be-world'
  scope: resRg
}

// Egress pool (Lab 2.3 / 3.1): the subnets are private, and the load balancer's one outbound rule
// gives internet access to this pool only (a frontend IP takes a single outbound rule), so every
// VM NIC joins it besides its role pool.
resource resLbPoolOutbound 'Microsoft.Network/loadBalancers/backendAddressPools@2023-11-01' existing = {
  name: '${varLbName}/${varLbName}-be-outbound'
  scope: resRg
}

// Lab 2.2 ASGs (dev only); referenced by ID only, so prod never reads them
resource resAsgAuth 'Microsoft.Network/applicationSecurityGroups@2023-11-01' existing = {
  name: '${varNamePrefix}-asg-auth'
  scope: resRg
}

resource resAsgWorld 'Microsoft.Network/applicationSecurityGroups@2023-11-01' existing = {
  name: '${varNamePrefix}-asg-world'
  scope: resRg
}

/*******************
*     Modules      *
*******************/

// Key Vault for Azure Disk Encryption (only with that strategy)
module modKeyVault 'br/public:avm/res/key-vault/vault:0.14.2' = if (parEncryptionStrategy == 'AzureDiskEncryption') {
  name: 'keyvault-deployment'
  scope: resRg
  params: {
    name: parKeyVaultName
    location: parLocation
    tags: varCommonTags
    sku: 'standard'
    enableVaultForDeployment: true
    enableVaultForDiskEncryption: true
    // Step 3.2.17 leaves it unchecked; ADE does not need it.
    enableVaultForTemplateDeployment: false
    enableRbacAuthorization: true
    publicNetworkAccess: 'Enabled'
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: 'Allow'
    }
    // Lab-friction override (standards section 4.5): Azure no longer allows soft delete to be
    // disabled, so keep the shortest retention and no purge protection; Remove-LabResource.ps1
    // purges the vault so the name is reusable immediately.
    enableSoftDelete: true
    softDeleteRetentionInDays: 7
    enablePurgeProtection: false
  }
}

// Data disk for the Worldserver database, named as Step 3.2.14 names it (#355)
module modWorldDataDisk 'br/public:avm/res/compute/disk:0.6.1' = {
  name: 'world-datadisk-deployment'
  scope: resRg
  params: {
    name: '${varNamePrefix}-world-vm-data'
    location: parLocation
    tags: varCommonTags
    sku: 'StandardSSD_LRS'
    diskSizeGB: parDataDiskSizeGB
    createOption: 'Empty'
    osType: 'Linux'
    availabilityZone: parAvailabilityZoneWorld
  }
}

// Auth VM (NIC created by the module, in the Auth backend pool, the egress pool and, in dev, the Auth ASG)
module modAuthVm 'br/public:avm/res/compute/virtual-machine:0.22.3' = {
  name: 'auth-vm-deployment'
  scope: resRg
  params: {
    name: '${varNamePrefix}-auth-vm'
    location: parLocation
    tags: varCommonTags
    vmSize: parVmSize
    osType: 'Linux'
    availabilityZone: parAvailabilityZoneAuth
    imageReference: varImageReference
    adminUsername: parAdminUsername
    disablePasswordAuthentication: true
    publicKeys: [
      {
        keyData: parSshPublicKey
        path: '/home/${parAdminUsername}/.ssh/authorized_keys'
      }
    ]
    osDisk: {
      name: '${varNamePrefix}-auth-vm-osdisk'
      diskSizeGB: 30
      caching: 'ReadWrite'
      deleteOption: 'Delete'
      managedDisk: {
        storageAccountType: 'StandardSSD_LRS'
      }
    }
    nicConfigurations: [
      {
        name: '${varNamePrefix}-auth-nic'
        deleteOption: 'Delete'
        enableAcceleratedNetworking: false
        ipConfigurations: [
          {
            name: 'ipconfig1'
            subnetResourceId: resSubnetAuth.id
            loadBalancerBackendAddressPools: [
              { id: resLbPoolAuth.id }
              { id: resLbPoolOutbound.id }
            ]
            applicationSecurityGroups: varUseAsgs ? [{ id: resAsgAuth.id }] : []
          }
        ]
      }
    ]
    managedIdentities: {
      systemAssigned: true
    }
    // As the guide's Security type row; API 2025-11-01 defaults an unset value to Trusted launch.
    securityType: 'Standard'
    encryptionAtHost: parEncryptionStrategy == 'EncryptionAtHost'
    bootDiagnostics: false
  }
}

// World VM (NIC in the World backend pool, the egress pool and, in dev, the World ASG; data disk attached)
module modWorldVm 'br/public:avm/res/compute/virtual-machine:0.22.3' = {
  name: 'world-vm-deployment'
  scope: resRg
  params: {
    name: '${varNamePrefix}-world-vm'
    location: parLocation
    tags: varCommonTags
    vmSize: parVmSize
    osType: 'Linux'
    availabilityZone: parAvailabilityZoneWorld
    imageReference: varImageReference
    adminUsername: parAdminUsername
    disablePasswordAuthentication: true
    publicKeys: [
      {
        keyData: parSshPublicKey
        path: '/home/${parAdminUsername}/.ssh/authorized_keys'
      }
    ]
    osDisk: {
      name: '${varNamePrefix}-world-vm-osdisk'
      diskSizeGB: 30
      caching: 'ReadWrite'
      deleteOption: 'Delete'
      managedDisk: {
        storageAccountType: 'StandardSSD_LRS'
      }
    }
    dataDisks: [
      {
        lun: 0
        managedDisk: {
          resourceId: modWorldDataDisk.outputs.resourceId
        }
      }
    ]
    nicConfigurations: [
      {
        name: '${varNamePrefix}-world-nic'
        deleteOption: 'Delete'
        enableAcceleratedNetworking: false
        ipConfigurations: [
          {
            name: 'ipconfig1'
            subnetResourceId: resSubnetWorld.id
            loadBalancerBackendAddressPools: [
              { id: resLbPoolWorld.id }
              { id: resLbPoolOutbound.id }
            ]
            applicationSecurityGroups: varUseAsgs ? [{ id: resAsgWorld.id }] : []
          }
        ]
      }
    ]
    managedIdentities: {
      systemAssigned: true
    }
    // As the guide's Security type row; API 2025-11-01 defaults an unset value to Trusted launch.
    securityType: 'Standard'
    encryptionAtHost: parEncryptionStrategy == 'EncryptionAtHost'
    bootDiagnostics: false
  }
}

/******************
*     Outputs     *
******************/

output outResourceGroupName string = resRg.name

output outAuthVmId string = modAuthVm.outputs.resourceId
output outAuthVmName string = modAuthVm.outputs.name
output outWorldVmId string = modWorldVm.outputs.resourceId
output outWorldVmName string = modWorldVm.outputs.name

output outAuthNicPrivateIp string = modAuthVm.outputs.nicConfigurations[0].ipConfigurations[0].privateIP!
output outWorldNicPrivateIp string = modWorldVm.outputs.nicConfigurations[0].ipConfigurations[0].privateIP!

output outWorldDataDiskId string = modWorldDataDisk.outputs.resourceId

output outKeyVaultName string = parEncryptionStrategy == 'AzureDiskEncryption' ? modKeyVault!.outputs.name : 'N/A - ADE not enabled'
output outEncryptionStrategy string = parEncryptionStrategy
