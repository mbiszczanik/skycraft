/*=====================================================
SUMMARY: Virtual Machine Module
DESCRIPTION: Deploys Azure Linux VMs with SSH authentication and optional Encryption at Host
AUTHOR/S: Marcin Biszczanik
VERSION: 1.0.0
DEPLOYMENT: Internal use via Orchestrator
======================================================*/

// ============================================================================
// PARAMETERS
// ============================================================================

@description('Name of the Virtual Machine')
param parVmName string

@description('Azure region for deployment')
param parLocation string = resourceGroup().location

@description('VM size (SKU)')
@allowed([
  'Standard_B1s'
  'Standard_B2s'
  'Standard_B2ms'
  'Standard_D2s_v3'
  'Standard_D4s_v3'
])
param parVmSize string = 'Standard_B2s'

@description('Availability zone (1, 2, or 3)')
@allowed(['1', '2', '3'])
param parAvailabilityZone string = '1'

@description('Admin username for SSH access')
param parAdminUsername string = 'azureuser'

@description('SSH public key for authentication')
@secure()
param parSshPublicKey string

@description('Network Interface resource ID')
param parNicId string

@description('OS disk size in GB')
param parOsDiskSizeGB int = 30

@description('OS disk storage account type')
@allowed([
  'Standard_LRS'
  'StandardSSD_LRS'
  'Premium_LRS'
])
param parOsDiskSku string = 'StandardSSD_LRS'

@description('Data disk IDs to attach (optional)')
param parDataDiskIds array = []

@description('Enable system-assigned managed identity')
param parEnableSystemIdentity bool = true

@description('Encryption strategy for the VM')
@allowed([
  'None'
  'EncryptionAtHost'
  'AzureDiskEncryption'
])
param parEncryptionStrategy string = 'None'

@description('Resource tags')
param parTags object

// ============================================================================
// VARIABLES
// ============================================================================

// Ubuntu 22.04 LTS image reference
var varImageReference = {
  publisher: 'Canonical'
  offer: '0001-com-ubuntu-server-jammy'
  sku: '22_04-lts-gen2'
  version: 'latest'
}

// Build data disk attachments array
var varDataDisks = [for (diskId, i) in parDataDiskIds: {
  lun: i
  createOption: 'Attach'
  managedDisk: {
    id: diskId
  }
}]

// ============================================================================
// RESOURCES
// ============================================================================

resource resVm 'Microsoft.Compute/virtualMachines@2023-09-01' = {
  name: parVmName
  location: parLocation
  tags: parTags
  zones: [
    parAvailabilityZone
  ]
  identity: parEnableSystemIdentity ? {
    type: 'SystemAssigned'
  } : null
  properties: {
    hardwareProfile: {
      vmSize: parVmSize
    }
    osProfile: {
      computerName: parVmName
      adminUsername: parAdminUsername
      linuxConfiguration: {
        disablePasswordAuthentication: true
        ssh: {
          publicKeys: [
            {
              path: '/home/${parAdminUsername}/.ssh/authorized_keys'
              keyData: parSshPublicKey
            }
          ]
        }
        provisionVMAgent: true
      }
    }
    storageProfile: {
      imageReference: varImageReference
      osDisk: {
        name: '${parVmName}-osdisk'
        createOption: 'FromImage'
        diskSizeGB: parOsDiskSizeGB
        managedDisk: {
          storageAccountType: parOsDiskSku
        }
        deleteOption: 'Delete'
      }
      dataDisks: varDataDisks
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: parNicId
          properties: {
            deleteOption: 'Delete'
          }
        }
      ]
    }
    securityProfile: parEncryptionStrategy == 'EncryptionAtHost' ? {
      encryptionAtHost: true
    } : null
    diagnosticsProfile: {
      bootDiagnostics: {
        enabled: false
      }
    }
  }
}

// ============================================================================
// OUTPUTS
// ============================================================================

output outVmId string = resVm.id
output outVmName string = resVm.name
output outVmPrincipalId string = parEnableSystemIdentity ? resVm.identity.principalId : ''
output outEncryptionStrategy string = parEncryptionStrategy
